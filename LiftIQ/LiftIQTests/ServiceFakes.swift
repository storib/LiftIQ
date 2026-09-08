import Foundation
@testable import LiftIQ

// In-memory fakes for the service protocols. Deterministic: no I/O, no
// randomness beyond UUID identifiers, all behavior driven by seeded fields.

struct FakeServiceError: LocalizedError, Equatable {
    var message: String = "fake failure"
    var errorDescription: String? { message }
}

// MARK: - FakeWorkoutService

@MainActor
final class FakeWorkoutService: WorkoutServicing {
    // Observable-surface state (settable so tests can seed it)
    var plans: [WorkoutPlan] = []
    var activePlan: WorkoutPlan?
    var recentSessions: [WorkoutSession] = []
    var activeSession: WorkoutSession?

    // Seeded behavior
    var recentLogsByExerciseId: [String: [ExerciseLog]] = [:]
    var startSessionError: Error?
    var updateSessionError: Error?
    var completeSessionError: Error?
    var abandonSessionError: Error?
    var savePlanError: Error?
    var deletePlanError: Error?
    var loadError: Error?
    var recentLogsError: Error?

    // Recorded calls
    private(set) var startedSessions: [WorkoutSession] = []
    private(set) var updatedSessions: [WorkoutSession] = []
    private(set) var completedSessions: [WorkoutSession] = []
    private(set) var abandonedSessions: [WorkoutSession] = []
    private(set) var savedPlans: [WorkoutPlan] = []
    private(set) var deletedPlanIds: [String] = []
    private(set) var loadPlansUserIds: [String] = []
    private(set) var loadRecentSessionsUserIds: [String] = []
    private(set) var loadActiveSessionUserIds: [String] = []
    private(set) var recentLogsRequests: [(userId: String, exerciseIds: Set<String>, excludingSessionId: String?, limit: Int)] = []

    func loadPlans(userId: String) async throws {
        if let loadError { throw loadError }
        loadPlansUserIds.append(userId)
    }

    func completedSessionDates(userId: String, since: Date) async throws -> [Date] {
        recentSessions
            .filter { $0.status == .completed && $0.startedAt >= since }
            .map(\.startedAt)
    }

    /// Completed sessions come from `recentSessions`; the lifetime count can
    /// be pinned for milestone tests.
    var completedSessionCountOverride: Int?

    func completedSessions(userId: String, since: Date) async throws -> [WorkoutSession] {
        if let loadError { throw loadError }
        return recentSessions
            .filter { $0.status == .completed && $0.startedAt >= since }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func completedSessionCount(userId: String) async throws -> Int {
        if let loadError { throw loadError }
        return completedSessionCountOverride ?? recentSessions.filter { $0.status == .completed }.count
    }

    func loadRecentSessions(userId: String) async throws {
        if let loadError { throw loadError }
        loadRecentSessionsUserIds.append(userId)
    }

    func loadActiveSession(userId: String) async throws {
        if let loadError { throw loadError }
        loadActiveSessionUserIds.append(userId)
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        if let savePlanError { throw savePlanError }
        savedPlans.append(plan)
        plans.append(plan)
        if plan.isActive { activePlan = plan }
    }

    func deletePlan(userId: String, planId: String) async throws {
        if let deletePlanError { throw deletePlanError }
        deletedPlanIds.append(planId)
        plans.removeAll { $0.id == planId }
    }

    func startSession(_ session: WorkoutSession) async throws {
        if let startSessionError { throw startSessionError }
        startedSessions.append(session)
        activeSession = session
    }

    func updateSession(_ session: WorkoutSession) async throws {
        if let updateSessionError { throw updateSessionError }
        updatedSessions.append(session)
        if let index = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[index] = session
        }
        activeSession = session.status == .inProgress ? session : nil
    }

    @discardableResult
    func completeSession(_ session: WorkoutSession, endingAt end: Date) async throws -> WorkoutSession {
        if let completeSessionError { throw completeSessionError }
        var completed = session
        completed.status = .completed
        completed.completedAt = end
        completed.durationSeconds = max(0, Int(end.timeIntervalSince(session.startedAt)))
        completedSessions.append(completed)
        activeSession = nil
        return completed
    }

    var timeUpdates: [(session: WorkoutSession, startedAt: Date, completedAt: Date)] = []
    var updateSessionTimesError: Error?

    @discardableResult
    func updateSessionTimes(_ session: WorkoutSession, startedAt: Date, completedAt: Date) async throws -> WorkoutSession {
        if let updateSessionTimesError { throw updateSessionTimesError }
        timeUpdates.append((session, startedAt, completedAt))
        var updated = session
        updated.startedAt = startedAt
        updated.completedAt = completedAt
        updated.durationSeconds = max(0, Int(completedAt.timeIntervalSince(startedAt)))
        if let index = recentSessions.firstIndex(where: { $0.id == updated.id }) {
            recentSessions[index] = updated
        }
        return updated
    }

    func abandonSession(_ session: WorkoutSession) async throws {
        if let abandonSessionError { throw abandonSessionError }
        abandonedSessions.append(session)
        activeSession = nil
    }

    var deletedSessions: [WorkoutSession] = []
    var deleteSessionError: Error?

    func deleteSession(_ session: WorkoutSession) async throws {
        if let deleteSessionError { throw deleteSessionError }
        deletedSessions.append(session)
        recentSessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = nil
        }
    }

    func getRecentExerciseLogs(
        userId: String,
        exerciseIds: Set<String>,
        excludingSessionId: String?,
        limit: Int
    ) async throws -> [String: [ExerciseLog]] {
        recentLogsRequests.append((userId, exerciseIds, excludingSessionId, limit))
        if let recentLogsError { throw recentLogsError }
        return recentLogsByExerciseId.filter { exerciseIds.contains($0.key) }
            .mapValues { Array($0.prefix(limit)) }
    }
}

// MARK: - FakeProgressService

@MainActor
final class FakeProgressService: ProgressServicing {
    var recentPRs: [PersonalRecord] = []

    // Seeded behavior
    var existingPRsByExerciseId: [String: [PersonalRecord]] = [:]
    var progressRecordsByExerciseId: [String: [ProgressRecord]] = [:]
    /// PR types checkForPRs should "detect" (it builds records from the set's
    /// actual values so rollback matching in the VM works).
    var prTypesToDetect: [PRType] = []
    var getProgressRecordsError: Error?
    var getExercisePRsError: Error?
    var checkForPRsError: Error?
    var deleteRecordError: Error?

    // Recorded calls
    private(set) var checkForPRsCalls: [(exerciseId: String, setLog: SetLog, sessionId: String, existingPRs: [PersonalRecord])] = []
    private(set) var savedPRs: [PersonalRecord] = []
    private(set) var deletedRecordIds: [String] = []

    func loadRecentPRs(userId: String) async throws {}

    func getProgressRecords(userId: String, exerciseId: String) async throws -> [ProgressRecord] {
        if let getProgressRecordsError { throw getProgressRecordsError }
        return progressRecordsByExerciseId[exerciseId] ?? []
    }

    func getAllProgressRecords(userId: String, since: Date) async throws -> [ProgressRecord] {
        if let getProgressRecordsError { throw getProgressRecordsError }
        return progressRecordsByExerciseId.values.flatMap { $0 }
            .filter { $0.date >= since }
            .sorted { $0.date < $1.date }
    }

    func getExercisePRs(userId: String, exerciseId: String) async throws -> [PersonalRecord] {
        if let getExercisePRsError { throw getExercisePRsError }
        return existingPRsByExerciseId[exerciseId] ?? []
    }

    func checkForPRs(
        userId: String,
        exerciseId: String,
        exerciseName: String,
        setLog: SetLog,
        sessionId: String,
        existingPRs: [PersonalRecord]
    ) async throws -> [PersonalRecord] {
        if let checkForPRsError { throw checkForPRsError }
        checkForPRsCalls.append((exerciseId, setLog, sessionId, existingPRs))
        var prs: [PersonalRecord] = []
        if prTypesToDetect.contains(.weight) {
            prs.append(PersonalRecord(
                id: UUID().uuidString,
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                type: .weight,
                value: setLog.weightKg,
                previousValue: nil,
                achievedAt: Date(),
                sessionId: sessionId
            ))
        }
        if prTypesToDetect.contains(.estimated1RM) {
            prs.append(PersonalRecord(
                id: UUID().uuidString,
                userId: userId,
                exerciseId: exerciseId,
                exerciseName: exerciseName,
                type: .estimated1RM,
                value: setLog.estimated1RM,
                previousValue: nil,
                achievedAt: Date(),
                sessionId: sessionId
            ))
        }
        savedPRs.append(contentsOf: prs)
        return prs
    }

    func deleteRecord(userId: String, recordId: String) async throws {
        if let deleteRecordError { throw deleteRecordError }
        deletedRecordIds.append(recordId)
    }
}

// MARK: - FakeExerciseService

@MainActor
final class FakeExerciseService: ExerciseServicing {
    var exercises: [Exercise] = []
    var isLoaded = false
    var loadError: Error?
    private(set) var loadExercisesCallCount = 0

    init(exercises: [Exercise] = []) {
        self.exercises = exercises
    }

    func loadExercises() async throws {
        loadExercisesCallCount += 1
        if let loadError { throw loadError }
        isLoaded = true
    }

    func getExercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func searchExercises(query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let lowered = query.lowercased()
        return exercises.filter { $0.name.lowercased().contains(lowered) }
    }

    func getExercises(forMuscleGroup group: MuscleGroup) -> [Exercise] {
        exercises.filter { $0.primaryMuscleGroup == group || $0.secondaryMuscleGroups.contains(group) }
    }

    func getExercises(forEquipment equipment: Set<Equipment>) -> [Exercise] {
        exercises.filter { $0.equipment.allSatisfy { equipment.contains($0) } }
    }
}

// MARK: - FakeHealthKitService

@MainActor
final class FakeHealthKitService: HealthKitServicing {
    var isAvailable = true
    var isSyncEnabled = false
    var isActivityImportEnabled = false
    var activities: [ExternalActivity] = []
    var fetchError: Error?

    private(set) var fetchRanges: [(start: Date, end: Date)] = []

    func enableSync() async throws { isSyncEnabled = true }
    func disableSync() { isSyncEnabled = false }
    func enableActivityImport() async throws { isActivityImportEnabled = true }
    func disableActivityImport() { isActivityImportEnabled = false }

    func fetchExternalActivities(from startDate: Date, to endDate: Date) async throws -> [ExternalActivity] {
        fetchRanges.append((startDate, endDate))
        if let fetchError { throw fetchError }
        guard isActivityImportEnabled else { return [] }
        return activities.filter { $0.startedAt >= startDate && $0.startedAt < endDate }
    }

    private(set) var exportedSessionIds: [String] = []
    private(set) var deletedSessionIds: [String] = []
    private(set) var reexportedSessionIds: [String] = []
    private(set) var retryBatches: [[String]] = []
    var reexportSucceeds = true
    var pendingReexportSessionIdsByUser: [String: Set<String>] = [:]

    func pendingReexportSessionIds(userId: String) -> Set<String> {
        pendingReexportSessionIdsByUser[userId] ?? []
    }

    func exportSession(_ session: WorkoutSession) async { exportedSessionIds.append(session.id) }
    func deleteExportedSession(sessionId: String, userId: String) async { deletedSessionIds.append(sessionId) }
    func reexportSession(_ session: WorkoutSession) async -> Bool {
        reexportedSessionIds.append(session.id)
        return reexportSucceeds
    }
    func retryPendingReexports(sessions: [WorkoutSession]) async { retryBatches.append(sessions.map(\.id)) }
}

// MARK: - FakeProfileStore / FakeMemoryService

@MainActor
final class FakeProfileStore: ProfileStoring {
    var currentProfile: UserProfile?
    private(set) var savedProfiles: [UserProfile] = []
    var updateError: Error?

    init(profile: UserProfile? = nil) {
        currentProfile = profile
    }

    func updateProfile(_ profile: UserProfile) async throws {
        if let updateError { throw updateError }
        savedProfiles.append(profile)
        currentProfile = profile
    }
}

@MainActor
final class FakeMemoryService: MemoryServicing {
    var preferences: [String: ExercisePreference] = [:]
    var activeEquipment: Set<Equipment> = Set(Equipment.allCases)
    var weightIncrements: WeightIncrements = .standard
    private(set) var recordedAlternatives: [(exerciseId: String, replacement: String)] = []
    private(set) var notes: [String: String?] = [:]
    private(set) var avoided: [String: Bool] = [:]
    private(set) var savedSetups: [[GymSetup]] = []
    private(set) var savedIncrements: [WeightIncrements?] = []

    func recordUsualAlternative(for exerciseId: String, replacement: String) async {
        recordedAlternatives.append((exerciseId, replacement))
        preferences[exerciseId, default: ExercisePreference()].usualAlternativeId = replacement
    }
    func setNote(_ note: String?, for exerciseId: String) async throws {
        notes[exerciseId] = note
        preferences[exerciseId, default: ExercisePreference()].note = note
    }
    func setAvoided(_ avoided: Bool, for exerciseId: String) async throws {
        self.avoided[exerciseId] = avoided
        preferences[exerciseId, default: ExercisePreference()].avoided = avoided
    }
    func saveGymSetups(_ setups: [GymSetup]) async throws { savedSetups.append(setups) }
    func setWeightIncrements(_ increments: WeightIncrements?) async throws { savedIncrements.append(increments) }
}

// MARK: - FakeBetaEventLogger

final class FakeBetaEventLogger: BetaEventLogging, @unchecked Sendable {
    struct Event { let name: String; let props: [String: any Sendable] }
    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] { lock.withLock { storage } }
    func names(_ name: String) -> [Event] { events.filter { $0.name == name } }

    func log(_ name: String, _ props: [String: any Sendable]) {
        lock.withLock { storage.append(Event(name: name, props: props)) }
    }
}

