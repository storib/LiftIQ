import Foundation

@Observable
final class WorkoutService {
    private let planRepository: WorkoutPlanRepository
    private let sessionRepository: WorkoutSessionRepository

    var activePlan: WorkoutPlan?
    var plans: [WorkoutPlan] = []
    var recentSessions: [WorkoutSession] = []
    var activeSession: WorkoutSession?

    init(planRepository: WorkoutPlanRepository, sessionRepository: WorkoutSessionRepository) {
        self.planRepository = planRepository
        self.sessionRepository = sessionRepository
    }

    func loadPlans(userId: String) async throws {
        plans = try await planRepository.getPlans(userId: userId)
        activePlan = plans.first { $0.isActive }
    }

    func loadRecentSessions(userId: String) async throws {
        recentSessions = try await sessionRepository.getSessions(userId: userId, limit: 20)
    }

    func loadActiveSession(userId: String) async throws {
        activeSession = try await sessionRepository.getActiveSession(userId: userId)
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        if plan.isActive {
            try await planRepository.deactivateAllPlans(userId: plan.userId)
        }
        try await planRepository.savePlan(plan)
        try await loadPlans(userId: plan.userId)
    }

    func deletePlan(userId: String, planId: String) async throws {
        try await planRepository.deletePlan(userId: userId, planId: planId)
        try await loadPlans(userId: userId)
    }

    func startSession(_ session: WorkoutSession) async throws {
        try await sessionRepository.saveSession(session)
        activeSession = session
    }

    func updateSession(_ session: WorkoutSession) async throws {
        try await sessionRepository.saveSession(session)
        if session.status == .inProgress {
            activeSession = session
        } else if activeSession?.id == session.id {
            activeSession = nil
        }
    }

    @discardableResult
    func completeSession(_ session: WorkoutSession) async throws -> WorkoutSession {
        var completed = session
        completed.status = .completed
        completed.completedAt = Date()
        try await sessionRepository.saveSession(completed)
        activeSession = nil
        try await loadRecentSessions(userId: session.userId)
        return completed
    }

    func abandonSession(_ session: WorkoutSession) async throws {
        var abandoned = session
        abandoned.status = .abandoned
        abandoned.completedAt = Date()
        try await sessionRepository.saveSession(abandoned)
        activeSession = nil
    }

    func getPreviousExerciseLog(userId: String, exerciseId: String) async throws -> ExerciseLog? {
        let sessions = try await sessionRepository.getSessionsForExercise(userId: userId, exerciseId: exerciseId, limit: 1)
        return sessions.first?.exerciseLogs.first { $0.exerciseId == exerciseId }
    }
}
