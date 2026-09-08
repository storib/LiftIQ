import XCTest
@testable import LiftIQ

/// Covers the export/replace failure ordering behind the WorkoutSampleStore
/// seam: a failed delete must never be followed by a save (duplicate), a
/// successful delete followed by a failed or skipped save must stay pending
/// (lost workout), and only a real save clears the ledger.
@MainActor
final class HealthKitServiceTests: XCTestCase {

    private enum StoreError: Error { case boom }

    @MainActor
    private final class FakeSampleStore: WorkoutSampleStore {
        var isAvailable = true
        var isWorkoutSharingAuthorized = true
        var deleteError: Error?
        var saveError: Error?
        private(set) var saved: [(externalId: String, startedAt: Date, completedAt: Date)] = []
        private(set) var deletedIds: [String] = []

        func saveWorkout(startedAt: Date, completedAt: Date, externalId: String) async throws {
            if let saveError { throw saveError }
            saved.append((externalId, startedAt, completedAt))
        }

        func deleteWorkouts(externalId: String) async throws {
            if let deleteError { throw deleteError }
            deletedIds.append(externalId)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService(syncEnabled: Bool = true) -> (HealthKitService, FakeSampleStore, UserDefaults) {
        let suite = "HealthKitServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(syncEnabled, forKey: "liftiq.healthKitSyncEnabled")
        let store = FakeSampleStore()
        return (HealthKitService(workoutStore: store, defaults: defaults), store, defaults)
    }

    private func makeSession(id: String = "s1", userId: String = "u1", status: SessionStatus = .completed, completedAt: Date? = nil) -> WorkoutSession {
        WorkoutSession(
            id: id, userId: userId, planId: nil, workoutTemplateId: nil, workoutName: "Push",
            startedAt: t0, completedAt: completedAt ?? t0.addingTimeInterval(3600), status: status,
            exerciseLogs: [], durationSeconds: 3600, notes: nil, mood: nil
        )
    }

    func testReexportDeletesThenSavesAndClearsPending() async {
        let (service, store, _) = makeService()
        let ok = await service.reexportSession(makeSession())
        XCTAssertTrue(ok)
        XCTAssertEqual(store.deletedIds, ["s1"])
        XCTAssertEqual(store.saved.map(\.externalId), ["s1"])
        XCTAssertEqual(store.saved.first?.completedAt, t0.addingTimeInterval(3600))
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty)
    }

    func testFailedDeleteNeverSavesAndStaysPending() async {
        let (service, store, _) = makeService()
        store.deleteError = StoreError.boom
        let ok = await service.reexportSession(makeSession())
        XCTAssertFalse(ok)
        XCTAssertTrue(store.saved.isEmpty, "a duplicate would have been created")
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "u1"), ["s1"])
    }

    func testDeleteThenFailedSaveStaysPendingAndRetrySucceeds() async {
        let (service, store, _) = makeService()
        store.saveError = StoreError.boom
        let ok = await service.reexportSession(makeSession())
        XCTAssertFalse(ok)
        XCTAssertEqual(store.deletedIds, ["s1"])
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "u1"), ["s1"])

        store.saveError = nil
        await service.retryPendingReexports(sessions: [makeSession()])

        XCTAssertEqual(store.saved.map(\.externalId), ["s1"])
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty)
    }

    func testUnauthorizedSharingIsNotCountedAsSuccess() async {
        let (service, store, _) = makeService()
        store.isWorkoutSharingAuthorized = false
        let ok = await service.reexportSession(makeSession())
        XCTAssertFalse(ok)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "u1"), ["s1"], "must survive until sharing is authorized")

        store.isWorkoutSharingAuthorized = true
        await service.retryPendingReexports(sessions: [makeSession()])
        XCTAssertEqual(store.saved.map(\.externalId), ["s1"])
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty)
    }

    func testInvalidBoundsIsNotCountedAsSuccess() async {
        let (service, store, _) = makeService()
        let ok = await service.reexportSession(makeSession(completedAt: t0.addingTimeInterval(-60)))
        XCTAssertFalse(ok)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "u1"), ["s1"])
    }

    func testPendingLedgerPersistsAcrossInstances() async {
        let (service, store, defaults) = makeService()
        store.saveError = StoreError.boom
        _ = await service.reexportSession(makeSession())

        let again = HealthKitService(workoutStore: FakeSampleStore(), defaults: defaults)
        XCTAssertEqual(again.pendingReexportSessionIds(userId: "u1"), ["s1"])
    }

    func testRetryOnlyTouchesPendingCompletedSessions() async {
        let (service, store, _) = makeService()
        store.saveError = StoreError.boom
        _ = await service.reexportSession(makeSession(id: "pending"))
        store.saveError = nil

        await service.retryPendingReexports(sessions: [
            makeSession(id: "pending"),
            makeSession(id: "other"),
            makeSession(id: "abandoned", status: .abandoned),
        ])

        XCTAssertEqual(store.saved.map(\.externalId), ["pending"])
    }

    func testDeleteExportedSessionDropsPendingEntry() async {
        let (service, store, _) = makeService()
        store.saveError = StoreError.boom
        _ = await service.reexportSession(makeSession())
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "u1"), ["s1"])

        await service.deleteExportedSession(sessionId: "s1", userId: "u1")

        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty)
    }

    func testSyncDisabledSkipsWithoutPending() async {
        let (service, store, _) = makeService(syncEnabled: false)
        let ok = await service.reexportSession(makeSession())
        XCTAssertFalse(ok)
        XCTAssertTrue(store.deletedIds.isEmpty)
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty)
    }

    func testBestEffortExportSwallowsFailures() async {
        let (service, store, _) = makeService()
        store.saveError = StoreError.boom
        await service.exportSession(makeSession())
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "u1").isEmpty, "a first export is not a replacement")
    }

    // MARK: - Account scoping

    func testPendingLedgerIsScopedByAccount() async {
        // Account A's failed replacement must be invisible to account B on
        // the same device: B's dashboard load reads only B's ledger, so it
        // never looks A's session up under /users/B (where it's absent) and
        // never deletes A's Health export as "gone".
        let (service, store, _) = makeService()
        store.saveError = StoreError.boom
        _ = await service.reexportSession(makeSession(id: "a-session", userId: "A"))
        store.saveError = nil

        XCTAssertEqual(service.pendingReexportSessionIds(userId: "A"), ["a-session"])
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "B").isEmpty)

        // B retrying with B's sessions — even one that reuses A's id in a
        // hostile fixture — leaves A's entry alone.
        await service.retryPendingReexports(sessions: [makeSession(id: "a-session", userId: "B")])
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "A"), ["a-session"])

        // B deleting under its own account cannot clear A's entry either.
        await service.deleteExportedSession(sessionId: "a-session", userId: "B")
        XCTAssertEqual(service.pendingReexportSessionIds(userId: "A"), ["a-session"])

        // A comes back: the retry runs and clears A's ledger.
        await service.retryPendingReexports(sessions: [makeSession(id: "a-session", userId: "A")])
        XCTAssertEqual(store.saved.map(\.externalId), ["a-session"])
        XCTAssertTrue(service.pendingReexportSessionIds(userId: "A").isEmpty)
    }
}
