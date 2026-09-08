import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var isLoading = false
    var todayWorkout: WorkoutTemplate?
    /// Consecutive weeks meeting the plan's training days (falls back to 2).
    /// Replaces the old day streak, which meant little to a 3-4×/week lifter.
    var weekStreak: Int = 0
    var blockProgress: BlockProgress?
    var blockReview: BlockReview?
    /// Completed sessions over the last ~year: feeds the week streak, block
    /// progress and the weekly check-in. Fetched once per load.
    private(set) var completedSessions: [WorkoutSession] = []
    var weeklyVolume: Double = 0
    var weeklySessionCount: Int = 0
    var selectedDate: Date
    private(set) var externalActivities: [ExternalActivity] = []

    /// The in-progress session the lifter almost certainly forgot to finish.
    private(set) var staleSession: WorkoutSession?
    var repairError: String?
    var isRepairing = false

    private let calendar: Calendar
    private var weekStart: Date

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        selectedDate = calendar.startOfDay(for: referenceDate)
        weekStart = referenceDate.startOfWeek(using: calendar)
    }

    var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    func load(
        workoutService: any WorkoutServicing,
        healthKitService: any HealthKitServicing,
        userId: String,
        referenceDate: Date = Date(),
        progressService: (any ProgressServicing)? = nil
    ) async {
        // The dashboard view (and this view model) can stay alive across a
        // week boundary; snap the strip to the current week on every reload
        // so it can't disagree with the freshly computed weekly stats.
        let currentWeekStart = referenceDate.startOfWeek(using: calendar)
        if currentWeekStart != weekStart {
            weekStart = currentWeekStart
            selectedDate = calendar.startOfDay(for: referenceDate)
        }

        isLoading = true
        do {
            try await workoutService.loadPlans(userId: userId)
            try await workoutService.loadRecentSessions(userId: userId)
            try await workoutService.loadActiveSession(userId: userId)
            staleSession = workoutService.activeSession.flatMap { $0.isLikelyForgotten(at: referenceDate) ? $0 : nil }

            todayWorkout = Self.nextWorkout(
                plan: workoutService.activePlan,
                sessions: workoutService.recentSessions
            )
            computeStats(from: workoutService.recentSessions)
        } catch {
            // Handle silently for dashboard
        }

        await loadLongRange(workoutService: workoutService, progressService: progressService,
                            userId: userId, referenceDate: referenceDate)

        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        do {
            externalActivities = try await healthKitService.fetchExternalActivities(from: weekStart, to: weekEnd)
        } catch {
            externalActivities = []
        }
        isLoading = false
    }

    /// Week streak, block progress and (when a block is done) its review.
    /// Failures leave the previous values in place — none of this is worth
    /// an error on the dashboard.
    private func loadLongRange(
        workoutService: any WorkoutServicing,
        progressService: (any ProgressServicing)?,
        userId: String,
        referenceDate: Date
    ) async {
        let plan = workoutService.activePlan
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -Milestones.streakWindowWeeks, to: referenceDate) ?? .distantPast
        let since = min(windowStart, plan?.effectiveBlockStart ?? windowStart)
        guard let sessions = try? await workoutService.completedSessions(userId: userId, since: since) else { return }
        completedSessions = sessions

        let target = plan?.workoutsPerWeek ?? 2
        weekStreak = Milestones.weekStreak(
            completedSessionDates: sessions.map(\.startedAt),
            weeklyTarget: target, now: referenceDate, calendar: calendar
        )

        guard let plan else {
            blockProgress = nil
            blockReview = nil
            return
        }
        let progress = BlockProgress.compute(plan: plan, sessions: sessions)
        blockProgress = progress
        guard progress.isComplete else {
            blockReview = nil
            return
        }
        let blockSessions = sessions.filter { $0.planId == plan.id && $0.startedAt >= plan.effectiveBlockStart }
        let prCount = Set(blockSessions.flatMap(\.exerciseLogs).flatMap(\.sets).flatMap { $0.personalRecordIds ?? [] }).count
        var strength: Double?
        if let progressService,
           let records = try? await progressService.getAllProgressRecords(userId: userId, since: plan.effectiveBlockStart) {
            strength = ProgressOverview.compute(
                records: records,
                sessionDates: blockSessions.map(\.startedAt),
                through: referenceDate,
                calendar: calendar
            ).strengthChangePercent
        }
        blockReview = BlockReview(
            blockNumber: progress.blockNumber,
            weeks: progress.weekCount,
            sessions: progress.completedSessions,
            strengthChangePercent: strength,
            prCount: prCount
        )
    }

    /// "Keep going": starts the next block from now. The plan keeps its
    /// content; only the block boundary moves, so the review card retires
    /// and the week counter restarts.
    func startNextBlock(plan: WorkoutPlan, workoutService: any WorkoutServicing, now: Date = Date()) async throws {
        var next = plan
        next.blockStartedAt = now
        next.blockNumber = plan.effectiveBlockNumber + 1
        try await workoutService.savePlan(next)
        blockReview = nil
        blockProgress = BlockProgress.compute(plan: next, sessions: completedSessions)
        // "Tweak with AI" hands in a rewritten plan; Up Next must point at
        // one of its days, not the template it replaced.
        todayWorkout = Self.nextWorkout(plan: next, sessions: workoutService.recentSessions)
    }

    /// Re-evaluates staleness against the clock without a reload — on
    /// foreground return, and when the threshold passes while the dashboard
    /// stays on screen.
    func refreshStaleness(workoutService: any WorkoutServicing, now: Date = Date()) {
        staleSession = workoutService.activeSession.flatMap { $0.isLikelyForgotten(at: now) ? $0 : nil }
    }

    /// Seconds until the active session crosses the stale threshold; nil
    /// when there is no active session or it's already stale.
    func secondsUntilStale(workoutService: any WorkoutServicing, now: Date = Date()) -> TimeInterval? {
        guard let session = workoutService.activeSession else { return nil }
        let remaining = session.startedAt
            .addingTimeInterval(Constants.staleSessionThresholdSeconds)
            .timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    /// Closes a forgotten session at its last completed set (or a capped
    /// fallback when no set was logged), so the stored duration and the
    /// Apple Health export both reflect the real workout.
    func finishStaleSessionAtLastSet(
        workoutService: any WorkoutServicing,
        healthKitService: any HealthKitServicing,
        userId: String
    ) async {
        guard let session = staleSession else { return }
        isRepairing = true
        repairError = nil
        do {
            try await workoutService.completeSession(session, endingAt: session.repairEndDate())
            SessionReminderScheduler.cancelPending()
            staleSession = nil
            await load(workoutService: workoutService, healthKitService: healthKitService, userId: userId)
        } catch {
            repairError = "Couldn't finish workout: \(error.localizedDescription)"
        }
        isRepairing = false
    }

    func discardStaleSession(
        workoutService: any WorkoutServicing,
        healthKitService: any HealthKitServicing,
        userId: String
    ) async {
        guard let session = staleSession else { return }
        isRepairing = true
        repairError = nil
        do {
            try await workoutService.abandonSession(session)
            SessionReminderScheduler.cancelPending()
            staleSession = nil
            await load(workoutService: workoutService, healthKitService: healthKitService, userId: userId)
        } catch {
            repairError = "Couldn't discard workout: \(error.localizedDescription)"
        }
        isRepairing = false
    }

    func sessions(on day: Date, from sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions
            .filter { $0.status != .inProgress && calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func activities(on day: Date) -> [ExternalActivity] {
        externalActivities
            .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func hasSession(on day: Date, in sessions: [WorkoutSession]) -> Bool {
        sessions.contains { $0.status != .inProgress && calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    func hasExternalActivity(on day: Date) -> Bool {
        externalActivities.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    /// Recommends the plan day after the most recently completed one, cycling
    /// back to day 1 at the end of the rotation. Completing a workout advances
    /// the recommendation immediately — it is not tied to the calendar weekday.
    static func nextWorkout(plan: WorkoutPlan?, sessions: [WorkoutSession]) -> WorkoutTemplate? {
        guard let plan, !plan.workouts.isEmpty else { return nil }
        let templateIds = Set(plan.workouts.map(\.id))
        let lastCompleted = sessions
            .filter { session in
                session.status == .completed &&
                session.workoutTemplateId.map(templateIds.contains) == true
            }
            .max { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }

        guard let last = lastCompleted,
              let lastIndex = plan.workouts.firstIndex(where: { $0.id == last.workoutTemplateId }) else {
            return plan.workouts.first
        }
        return plan.workouts[(lastIndex + 1) % plan.workouts.count]
    }

    /// The rotation that follows `nextWorkout`, used to project upcoming days.
    static func upcomingRotation(plan: WorkoutPlan?, sessions: [WorkoutSession], count: Int) -> [WorkoutTemplate] {
        guard let plan, !plan.workouts.isEmpty, count > 0,
              let next = nextWorkout(plan: plan, sessions: sessions),
              let nextIndex = plan.workouts.firstIndex(where: { $0.id == next.id }) else { return [] }
        return (0..<count).map { plan.workouts[(nextIndex + $0) % plan.workouts.count] }
    }

    private func computeStats(from sessions: [WorkoutSession]) {
        let thisWeekSessions = sessions.filter { $0.status == .completed && $0.startedAt >= weekStart }
        weeklySessionCount = thisWeekSessions.count
        weeklyVolume = thisWeekSessions.reduce(0) { $0 + $1.totalVolumeKg }
    }
}
