import Foundation

@MainActor
@Observable
final class WorkoutService {
    private let planRepository: WorkoutPlanRepository
    private let sessionRepository: WorkoutSessionRepository
    private let prRepository: PersonalRecordRepository
    private let healthKitService: any HealthKitServicing

    var activePlan: WorkoutPlan?
    var plans: [WorkoutPlan] = []
    var recentSessions: [WorkoutSession] = []
    var activeSession: WorkoutSession?

    init(
        planRepository: WorkoutPlanRepository,
        sessionRepository: WorkoutSessionRepository,
        prRepository: PersonalRecordRepository,
        healthKitService: any HealthKitServicing
    ) {
        self.planRepository = planRepository
        self.sessionRepository = sessionRepository
        self.prRepository = prRepository
        self.healthKitService = healthKitService
    }

    func loadPlans(userId: String) async throws {
        plans = try await planRepository.getPlans(userId: userId)
        activePlan = plans.first { $0.isActive }
    }

    func loadRecentSessions(userId: String) async throws {
        recentSessions = try await sessionRepository.getSessions(userId: userId, limit: 20)
        await retryPendingHealthReplacements(userId: userId)
    }

    /// A Health replacement that failed after a time edit gets another go on
    /// every dashboard load. Pending sessions are fetched by id — the edited
    /// workout may be older than any recent-sessions window — and one that
    /// no longer exists is dropped from the ledger. Only the signed-in
    /// account's ledger is read: another account's ids would resolve to
    /// missing documents under this user and wrongly delete their exports.
    private func retryPendingHealthReplacements(userId: String) async {
        let pending = healthKitService.pendingReexportSessionIds(userId: userId)
        guard !pending.isEmpty else { return }
        var sessions: [WorkoutSession] = []
        for sessionId in pending {
            if let cached = recentSessions.first(where: { $0.id == sessionId }) {
                sessions.append(cached)
                continue
            }
            do {
                if let fetched = try await sessionRepository.getSession(userId: userId, sessionId: sessionId) {
                    sessions.append(fetched)
                } else {
                    // Gone from Firestore: nothing to replace, drop the entry.
                    await healthKitService.deleteExportedSession(sessionId: sessionId, userId: userId)
                }
            } catch {
                // Transient read failure: leave it pending for next time.
            }
        }
        await healthKitService.retryPendingReexports(sessions: sessions)
    }

    func completedSessionDates(userId: String, since: Date) async throws -> [Date] {
        try await sessionRepository.getCompletedSessionDates(userId: userId, since: since)
    }

    func completedSessions(userId: String, since: Date) async throws -> [WorkoutSession] {
        try await sessionRepository.getCompletedSessions(userId: userId, since: since)
    }

    func completedSessionCount(userId: String) async throws -> Int {
        try await sessionRepository.countCompletedSessions(userId: userId)
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

    /// Completes a session ending at `end` — now for a normal finish, or the
    /// last set's time when a forgotten session is closed out. This is the
    /// one place `durationSeconds` is derived at completion, so the stored
    /// duration and the Apple Health bounds can't disagree.
    @discardableResult
    func completeSession(_ session: WorkoutSession, endingAt end: Date) async throws -> WorkoutSession {
        var completed = session
        completed.status = .completed
        completed.completedAt = end
        completed.durationSeconds = max(0, Int(end.timeIntervalSince(session.startedAt)))
        try await sessionRepository.saveSession(completed)
        activeSession = nil
        try await loadRecentSessions(userId: session.userId)
        // Best-effort mirror into Apple Health; never fails completion.
        await healthKitService.exportSession(completed)
        return completed
    }

    /// Rewrites a completed session's times. Kept separate from
    /// `updateSession` — which runs on every ✓ tap and on mood/notes — so
    /// Apple Health is only touched when the workout's bounds actually move.
    @discardableResult
    func updateSessionTimes(_ session: WorkoutSession, startedAt: Date, completedAt: Date) async throws -> WorkoutSession {
        guard session.status == .completed else { throw WorkoutServiceError.sessionNotCompleted }
        var updated = session
        updated.startedAt = startedAt
        updated.completedAt = completedAt
        updated.durationSeconds = max(0, Int(completedAt.timeIntervalSince(startedAt)))
        try await sessionRepository.saveSession(updated)
        if let index = recentSessions.firstIndex(where: { $0.id == updated.id }) {
            recentSessions[index] = updated
        }
        await healthKitService.reexportSession(updated)
        return updated
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
        await healthKitService.deleteExportedSession(sessionId: session.id, userId: session.userId)
        recentSessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = nil
        }
    }

    /// Abandons a session and best-effort rolls back its PRs — the dashboard
    /// discards forgotten sessions without going through the execution view
    /// model, which otherwise owns that rollback.
    func abandonSession(_ session: WorkoutSession) async throws {
        let recordIds = Set(session.exerciseLogs.flatMap(\.sets).flatMap { $0.personalRecordIds ?? [] })
        for recordId in recordIds {
            try? await prRepository.deleteRecord(userId: session.userId, recordId: recordId)
        }
        var abandoned = session
        abandoned.status = .abandoned
        let end = Date()
        abandoned.completedAt = end
        abandoned.durationSeconds = max(0, Int(end.timeIntervalSince(session.startedAt)))
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

enum WorkoutServiceError: LocalizedError {
    case sessionNotCompleted

    var errorDescription: String? {
        switch self {
        case .sessionNotCompleted: return "Only completed workouts can have their times changed."
        }
    }
}
