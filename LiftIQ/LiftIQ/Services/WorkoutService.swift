import Foundation

@MainActor
@Observable
final class WorkoutService {
    private let planRepository: WorkoutPlanRepository
    private let sessionRepository: WorkoutSessionRepository
    private let prRepository: PersonalRecordRepository

    var activePlan: WorkoutPlan?
    var plans: [WorkoutPlan] = []
    var recentSessions: [WorkoutSession] = []
    var activeSession: WorkoutSession?

    init(
        planRepository: WorkoutPlanRepository,
        sessionRepository: WorkoutSessionRepository,
        prRepository: PersonalRecordRepository
    ) {
        self.planRepository = planRepository
        self.sessionRepository = sessionRepository
        self.prRepository = prRepository
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
            try await planRepository.saveAndActivate(plan)
        } else {
            try await planRepository.savePlan(plan)
        }
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
        if let index = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[index] = session
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

    /// Deletes a session and best-effort rolls back the personal records its
    /// sets produced (same tradeoff as the set-clearing rollback in workout
    /// execution). progressRecords cleanup happens server-side on the delete.
    func deleteSession(_ session: WorkoutSession) async throws {
        let recordIds = Set(session.exerciseLogs.flatMap(\.sets).flatMap { $0.personalRecordIds ?? [] })
        for recordId in recordIds {
            try? await prRepository.deleteRecord(userId: session.userId, recordId: recordId)
        }
        try await sessionRepository.deleteSession(userId: session.userId, sessionId: session.id)
        recentSessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = nil
        }
    }

    func abandonSession(_ session: WorkoutSession) async throws {
        var abandoned = session
        abandoned.status = .abandoned
        abandoned.completedAt = Date()
        try await sessionRepository.saveSession(abandoned)
        activeSession = nil
    }

    /// Fetches recent history once and derives per-exercise logs in memory.
    /// Sessions embed their logs, so one bounded query serves every exercise;
    /// querying per exercise would re-download the same documents.
    /// `excludingSessionId` keeps the in-flight session out of its own history.
    func getRecentExerciseLogs(
        userId: String,
        exerciseIds: Set<String>,
        excludingSessionId: String? = nil,
        limit: Int = 5
    ) async throws -> [String: [ExerciseLog]] {
        // Only completed sessions count as history — abandoned or in-progress
        // sessions carry zero-weight sets that would poison "previous" ghost
        // values and progression suggestions ("Hold at 0 lb").
        let sessions = try await sessionRepository.getSessions(userId: userId, limit: 100)
            .filter { $0.id != excludingSessionId && $0.status == .completed }
        var logs: [String: [ExerciseLog]] = [:]
        for exerciseId in exerciseIds {
            let recent = sessions.compactMap { session in
                session.exerciseLogs.first { $0.exerciseId == exerciseId }
            }
            logs[exerciseId] = Array(recent.prefix(limit))
        }
        return logs
    }
}
