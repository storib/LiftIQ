import Foundation

// Protocol seams over the concrete services, covering exactly the surface the
// ViewModels consume. ViewModel methods take `any XxxServicing` so tests can
// substitute in-memory fakes.
//
// Note on observation: AppDependencies intentionally keeps exposing the
// CONCRETE service types. SwiftUI's @Observable tracking is preserved when
// Views read properties through the concrete type; holding an existential
// (`any WorkoutServicing`) in a View would break change tracking. The
// protocols exist only at ViewModel method boundaries, where values are read
// once per call rather than observed.

@MainActor
protocol WorkoutServicing: AnyObject {
    var plans: [WorkoutPlan] { get }
    var activePlan: WorkoutPlan? { get }
    var recentSessions: [WorkoutSession] { get }
    var activeSession: WorkoutSession? { get }

    func loadPlans(userId: String) async throws
    func loadRecentSessions(userId: String) async throws
    func loadActiveSession(userId: String) async throws
    func savePlan(_ plan: WorkoutPlan) async throws
    func deletePlan(userId: String, planId: String) async throws
    func startSession(_ session: WorkoutSession) async throws
    func updateSession(_ session: WorkoutSession) async throws
    @discardableResult
    func completeSession(_ session: WorkoutSession) async throws -> WorkoutSession
    func abandonSession(_ session: WorkoutSession) async throws
    func deleteSession(_ session: WorkoutSession) async throws
    func getRecentExerciseLogs(
        userId: String,
        exerciseIds: Set<String>,
        excludingSessionId: String?,
        limit: Int
    ) async throws -> [String: [ExerciseLog]]
}

@MainActor
protocol ProgressServicing: AnyObject {
    var recentPRs: [PersonalRecord] { get }

    func loadRecentPRs(userId: String) async throws
    func getProgressRecords(userId: String, exerciseId: String) async throws -> [ProgressRecord]
    func getExercisePRs(userId: String, exerciseId: String) async throws -> [PersonalRecord]
    func checkForPRs(
        userId: String,
        exerciseId: String,
        exerciseName: String,
        setLog: SetLog,
        sessionId: String,
        existingPRs: [PersonalRecord]
    ) async throws -> [PersonalRecord]
    func deleteRecord(userId: String, recordId: String) async throws
}

@MainActor
protocol ExerciseServicing: AnyObject {
    var exercises: [Exercise] { get }
    var isLoaded: Bool { get }

    func loadExercises() async throws
    func getExercise(id: String) -> Exercise?
    func searchExercises(query: String) -> [Exercise]
    func getExercises(forMuscleGroup group: MuscleGroup) -> [Exercise]
    func getExercises(forEquipment equipment: Set<Equipment>) -> [Exercise]
}

@MainActor
protocol HealthKitServicing: AnyObject {
    var isAvailable: Bool { get }
    var isSyncEnabled: Bool { get }

    func enableSync() async throws
    func disableSync()
    func exportSession(_ session: WorkoutSession) async
    func deleteExportedSession(sessionId: String) async
}

extension WorkoutService: WorkoutServicing {}
extension HealthKitService: HealthKitServicing {}
extension ProgressService: ProgressServicing {}
extension ExerciseService: ExerciseServicing {}
