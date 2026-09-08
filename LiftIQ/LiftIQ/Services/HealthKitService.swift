import Foundation
import HealthKit
import Observation

enum HealthKitError: LocalizedError {
    case sharingAuthorizationDenied
    /// Export skipped because workout sharing isn't authorized. Thrown (not
    /// silently returned) so a replacement stays pending until it can run.
    case sharingNotAuthorized
    /// Export skipped because the session has no end, or ends before it starts.
    case invalidWorkoutBounds

    var errorDescription: String? {
        switch self {
        case .sharingAuthorizationDenied:
            return "Health access was declined. To sync workouts, allow LiftIQ in the Health app under Sharing → Apps."
        case .sharingNotAuthorized:
            return "Workout sharing to Apple Health isn't authorized."
        case .invalidWorkoutBounds:
            return "The workout has no valid start and end time."
        }
    }
}

/// The three HealthKit operations the export/replace path needs, behind a
/// protocol so the failure ordering (delete vs. save) can be unit tested.
/// Everything else in `HealthKitService` still talks to `HKHealthStore`.
@MainActor
protocol WorkoutSampleStore: AnyObject {
    var isAvailable: Bool { get }
    var isWorkoutSharingAuthorized: Bool { get }
    func saveWorkout(startedAt: Date, completedAt: Date, externalId: String) async throws
    func deleteWorkouts(externalId: String) async throws
}

@MainActor
final class HealthKitWorkoutStore: WorkoutSampleStore {
    private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isWorkoutSharingAuthorized: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func saveWorkout(startedAt: Date, completedAt: Date, externalId: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: startedAt)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: externalId])
        try await builder.endCollection(at: completedAt)
        _ = try await builder.finishWorkout()
    }

    func deleteWorkouts(externalId: String) async throws {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalId]
        )
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return }
        try await store.delete(samples)
    }
}

/// Mirrors completed sessions into Apple Health and optionally reads external
/// workouts for the dashboard. Both preferences and imported data stay local
/// to the device; Health failures never break a workout flow.
@MainActor
@Observable
final class HealthKitService {
    private let store: HKHealthStore
    private let workoutStore: any WorkoutSampleStore
    private let defaults: UserDefaults
    private static let syncEnabledKey = "liftiq.healthKitSyncEnabled"
    private static let activityImportEnabledKey = "liftiq.healthKitActivityImportEnabled"

    private(set) var isSyncEnabled: Bool
    private(set) var isActivityImportEnabled: Bool

    var isAvailable: Bool { workoutStore.isAvailable }

    init(
        workoutStore: (any WorkoutSampleStore)? = nil,
        defaults: UserDefaults = .standard
    ) {
        let hkStore = HKHealthStore()
        self.store = hkStore
        self.workoutStore = workoutStore ?? HealthKitWorkoutStore(store: hkStore)
        self.defaults = defaults
        isSyncEnabled = defaults.bool(forKey: Self.syncEnabledKey)
        isActivityImportEnabled = defaults.bool(forKey: Self.activityImportEnabledKey)
    }

    func enableSync() async throws {
        // requestAuthorization succeeds even when the user declines; the
        // share status is the real signal.
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthKitError.sharingAuthorizationDenied
        }
        isSyncEnabled = true
        defaults.set(true, forKey: Self.syncEnabledKey)
    }

    func disableSync() {
        isSyncEnabled = false
        defaults.set(false, forKey: Self.syncEnabledKey)
    }

    func enableActivityImport() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        // HealthKit intentionally does not reveal read-denial status. A
        // successful request means the preference can be enabled; a declined
        // user simply receives no samples.
        isActivityImportEnabled = true
        defaults.set(true, forKey: Self.activityImportEnabledKey)
    }

    func disableActivityImport() {
        isActivityImportEnabled = false
        defaults.set(false, forKey: Self.activityImportEnabledKey)
    }

    func fetchExternalActivities(from startDate: Date, to endDate: Date) async throws -> [ExternalActivity] {
        guard isActivityImportEnabled, isAvailable, endDate > startDate else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKWorkout] ?? [])
                }
            }
            store.execute(query)
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        return workouts.compactMap { workout in
            let source = workout.sourceRevision.source
            guard source.bundleIdentifier != ownBundleIdentifier else { return nil }
            return ExternalActivity(
                id: workout.uuid.uuidString,
                kind: Self.kind(for: workout.workoutActivityType),
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                sourceName: source.name,
                activeEnergyKilocalories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
            )
        }
    }

    private static func kind(for activityType: HKWorkoutActivityType) -> ExternalActivity.Kind {
        switch activityType {
        case .walking: return .walking
        case .running: return .running
        case .cycling: return .cycling
        case .hiking: return .hiking
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strengthTraining
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .yoga: return .yoga
        case .pilates: return .pilates
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimbing
        case .dance: return .dance
        case .coreTraining: return .coreTraining
        default: return .other
        }
    }

    /// Saves a completed session as an HKWorkout, tagged with the session id
    /// so a later session delete can find and remove it. Best-effort; the
    /// session itself is already saved.
    func exportSession(_ session: WorkoutSession) async {
        guard isSyncEnabled, isAvailable else { return }
        try? await export(session)
    }

    /// Replaces the exported HKWorkout after a time edit. HKWorkout samples
    /// are immutable, so this is delete-by-external-UUID then add. Skipped
    /// entirely when sync is off. Both steps can fail, and the order of
    /// failure matters: a failed delete must not be followed by an export
    /// (that would duplicate), and a successful delete followed by a failed
    /// or skipped export must be retried (or the workout is gone from
    /// Health). Any failure records the session under its owner in the
    /// pending ledger; only a real save clears it.
    @discardableResult
    func reexportSession(_ session: WorkoutSession) async -> Bool {
        guard isSyncEnabled, isAvailable else { return false }
        do {
            try await workoutStore.deleteWorkouts(externalId: session.id)
            try await export(session)
            removePending(session.id, userId: session.userId)
            return true
        } catch {
            addPending(session.id, userId: session.userId)
            return false
        }
    }

    /// Session ids owned by `userId` whose Health replacement did not
    /// complete. The ledger is device-local (the exports are) but scoped by
    /// account: another account signed in on this device must never see,
    /// retry, or clear these — looking one up under the wrong user finds no
    /// document and would delete the owner's export.
    func pendingReexportSessionIds(userId: String) -> Set<String> {
        Set(pendingLedger[userId] ?? [])
    }

    /// Retries replacements that failed earlier, each checked against its
    /// own owner's ledger. A retry after a delete-then-failed-export finds
    /// nothing to delete and simply exports.
    func retryPendingReexports(sessions: [WorkoutSession]) async {
        guard isSyncEnabled, isAvailable else { return }
        for session in sessions
        where session.status == .completed && pendingReexportSessionIds(userId: session.userId).contains(session.id) {
            await reexportSession(session)
        }
    }

    /// Best-effort removal of the HKWorkout exported for a deleted session.
    /// Only samples this app wrote can be deleted, which is exactly the set
    /// tagged with our external UUID. Also drops any pending replacement —
    /// a session that no longer exists has nothing to replace. Callers must
    /// only pass ids that belong to the signed-in account.
    func deleteExportedSession(sessionId: String, userId: String) async {
        removePending(sessionId, userId: userId)
        guard isAvailable else { return }
        try? await workoutStore.deleteWorkouts(externalId: sessionId)
    }

    // MARK: - Export primitive and pending ledger

    private static let pendingReexportKey = "liftiq.health.pendingReexportByUser"

    /// Throws when the export can't happen — including the "skipped"
    /// cases, so a caller replacing a workout never mistakes a skip for a
    /// success.
    private func export(_ session: WorkoutSession) async throws {
        guard workoutStore.isWorkoutSharingAuthorized else { throw HealthKitError.sharingNotAuthorized }
        guard let completedAt = session.completedAt, completedAt > session.startedAt else {
            throw HealthKitError.invalidWorkoutBounds
        }
        try await workoutStore.saveWorkout(startedAt: session.startedAt, completedAt: completedAt, externalId: session.id)
    }

    /// userId → pending session ids.
    private var pendingLedger: [String: [String]] {
        get { defaults.dictionary(forKey: Self.pendingReexportKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Self.pendingReexportKey) }
    }

    private func addPending(_ id: String, userId: String) {
        var ledger = pendingLedger
        var ids = Set(ledger[userId] ?? [])
        ids.insert(id)
        ledger[userId] = Array(ids).sorted()
        pendingLedger = ledger
    }

    private func removePending(_ id: String, userId: String) {
        var ledger = pendingLedger
        var ids = Set(ledger[userId] ?? [])
        guard ids.remove(id) != nil else { return }
        ledger[userId] = ids.isEmpty ? nil : Array(ids).sorted()
        pendingLedger = ledger
    }
}
