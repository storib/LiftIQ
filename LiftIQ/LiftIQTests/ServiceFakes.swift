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
        activeSession = session.status == .inProgress ? session : nil
    }

    @discardableResult
    func completeSession(_ session: WorkoutSession) async throws -> WorkoutSession {
        if let completeSessionError { throw completeSessionError }
        var completed = session
        completed.status = .completed
        completed.completedAt = Date()
        completedSessions.append(completed)
        activeSession = nil
        return completed
    }

    func abandonSession(_ session: WorkoutSession) async throws {
        if let abandonSessionError { throw abandonSessionError }
        abandonedSessions.append(session)
        activeSession = nil
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
    private(set) var deletedRecords: [PersonalRecord] = []

    func loadRecentPRs(userId: String) async throws {}

    func getProgressRecords(userId: String, exerciseId: String) async throws -> [ProgressRecord] {
        if let getProgressRecordsError { throw getProgressRecordsError }
        return progressRecordsByExerciseId[exerciseId] ?? []
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

    func deleteRecord(_ record: PersonalRecord) async throws {
        if let deleteRecordError { throw deleteRecordError }
        deletedRecords.append(record)
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
