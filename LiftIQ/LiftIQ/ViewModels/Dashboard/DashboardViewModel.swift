import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var isLoading = false
    var todayWorkout: WorkoutTemplate?
    /// Today's workout after an accepted "adapt" — held until Start, and
    /// only while it still belongs to the recommended day of the same plan.
    var adaptedWorkout: AdaptedWorkout?
    private var activePlanId: String?

    /// What Start Workout runs: the adaptation when it matches today's
    /// recommended day, else the plan's template.
    var effectiveTodayWorkout: WorkoutTemplate? {
        if let adaptedWorkout, adaptedWorkout.sourceTemplateId == todayWorkout?.id, adaptedWorkout.planId == activePlanId {
            return adaptedWorkout.template
        }
        return todayWorkout
    }

    func revertAdaptation() {
        adaptedWorkout = nil
    }

    /// The "Change" menu picks a different day; an adaptation of the old
    /// day must not follow it.
    func selectWorkout(_ template: WorkoutTemplate) {
        todayWorkout = template
        adaptedWorkout = nil
    }
    /// Consecutive weeks meeting the plan's training days (falls back to 2).
    /// Replaces the old day streak, which meant little to a 3-4×/week lifter.
    var weekStreak: Int = 0
    var blockProgress: BlockProgress?
    var blockReview: BlockReview?
    /// The opt-in "you've been on this program a while" checkpoint. Nil
    /// unless the lifter set a cadence in Profile and it has come due.
    var programRefresh: ProgramRefresh?
    /// "Want the AI to suggest a change?" for stalled lifts. Shown only when
    /// neither checkpoint card is, and hidden once dismissed or acted on.
    var coachSuggestion: CoachSuggestion?
    private let coachSuggestionStore: CoachSuggestionStore
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

    init(
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        coachSuggestionStore: CoachSuggestionStore = CoachSuggestionStore()
    ) {
        self.calendar = calendar
        self.coachSuggestionStore = coachSuggestionStore
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
        progressService: (any ProgressServicing)? = nil,
        liveActivity: (any WorkoutLiveActivitying)? = nil,
        profile: UserProfile? = nil,
        progressionService: ProgressionService? = nil,
        exercises: [String: Exercise] = [:]
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
            // No running session means no banner should be up (finished on
            // another device, or the app was reinstalled mid-workout).
            if workoutService.activeSession == nil { liveActivity?.endAll() }

            todayWorkout = Self.nextWorkout(
                plan: workoutService.activePlan,
                sessions: workoutService.recentSessions
            )
            activePlanId = workoutService.activePlan?.id
            // A reload recomputes the recommended day; keep the adaptation
            // only if it is still for that day of the same plan.
            if let adaptedWorkout,
               adaptedWorkout.sourceTemplateId != todayWorkout?.id || adaptedWorkout.planId != activePlanId {
                self.adaptedWorkout = nil
            }
            computeStats(from: workoutService.recentSessions)
        } catch {
            // Handle silently for dashboard
        }

        await loadLongRange(workoutService: workoutService, progressService: progressService,
                            userId: userId, referenceDate: referenceDate,
                            profile: profile, progressionService: progressionService,
                            exercises: exercises)

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
        referenceDate: Date,
        profile: UserProfile? = nil,
        progressionService: ProgressionService? = nil,
        exercises: [String: Exercise] = [:]
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
            programRefresh = nil
            coachSuggestion = nil
            return
        }
        let progress = BlockProgress.compute(plan: plan, sessions: sessions)
        blockProgress = progress

        let slotSuggestions = progressionService.map {
            Self.currentSuggestions(plan: plan, sessions: sessions, progressionService: $0, exercises: exercises)
        } ?? []
        // Reloads that don't pass the progression service (e.g. after a
        // session delete) can't judge stalls: leave the card and the snoozes
        // as they were rather than reading "nothing stalled" as a recovery.
        if progressionService != nil {
            var names: [String: String] = [:]
            for log in sessions.flatMap(\.exerciseLogs) where names[log.exerciseId] == nil {
                names[log.exerciseId] = log.exerciseName
            }
            for (id, exercise) in exercises { names[id] = exercise.name }
            let stalled = CoachSuggestion.stalledLifts(slots: slotSuggestions, names: names)
            coachSuggestionStore.forgetRecovered(
                planId: plan.id,
                stillStalled: Set(stalled.map { $0.snoozeKey(planId: plan.id) }),
                userId: userId
            )
            coachSuggestion = CoachSuggestion.evaluate(planId: plan.id, stalled: stalled) {
                coachSuggestionStore.isSnoozed($0, userId: userId, now: referenceDate)
            }
        }

        // The block review is the stronger, more specific checkpoint; only
        // offer the time-based one when no block is waiting to be reviewed.
        programRefresh = ProgramRefresh.due(
            plan: plan,
            cadenceWeeks: progress.isComplete ? nil : profile?.programRefreshWeeks,
            planSessionDates: sessions.filter { $0.planId == plan.id }.map(\.startedAt),
            holdingLifts: ProgramRefresh.holdingLiftCount(slotSuggestions.map(\.suggestion)),
            now: referenceDate,
            calendar: calendar
        )

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

    /// How many of the plan's lifts are currently stalled — the best
    /// top-weight set has missed the rep floor at the same weight for
    /// `Constants.stallThreshold` sessions running. A description of what has
    /// happened, never a claim that progress has stopped: that would need far
    /// more data than a few sessions can carry (see `StrengthTrend`).
    static func holdingLiftCount(
        plan: WorkoutPlan,
        sessions: [WorkoutSession],
        progressionService: ProgressionService,
        exercises: [String: Exercise]
    ) -> Int {
        ProgramRefresh.holdingLiftCount(
            currentSuggestions(plan: plan, sessions: sessions, progressionService: progressionService, exercises: exercises)
                .map(\.suggestion)
        )
    }

    /// The progression suggestion each plan slot would get today, in plan
    /// order, judged only on the last five sessions that logged *that slot*.
    /// A lift on two days (heavy 3-5, volume 10-12) has two prescriptions;
    /// mixing its history would grade heavy-day sets against the volume
    /// floor and report misses that never happened. A log belongs to a slot
    /// by `plannedExerciseId` when it names one of this plan's slots, else
    /// (older sessions, or a one-session AI edit that re-pointed the logs) by
    /// the session's day plus the exercise. A mid-workout swap is a different
    /// exercise in the slot, so it is not that slot's history.
    static func currentSuggestions(
        plan: WorkoutPlan,
        sessions: [WorkoutSession],
        progressionService: ProgressionService,
        exercises: [String: Exercise]
    ) -> [PlanSlotSuggestion] {
        let planSlotIds = Set(plan.workouts.flatMap { $0.exerciseGroups.flatMap(\.exercises).map(\.id) })
        let planSessions = sessions
            .filter { $0.planId == plan.id }
            .sorted { $0.startedAt > $1.startedAt }

        var results: [PlanSlotSuggestion] = []
        for day in plan.workouts {
            for planned in day.exerciseGroups.flatMap(\.exercises) {
                var logs: [ExerciseLog] = []
                for session in planSessions where logs.count < 5 {
                    let match = session.exerciseLogs.first { log in
                        guard log.exerciseId == planned.exerciseId else { return false }
                        if let slot = log.plannedExerciseId, planSlotIds.contains(slot) {
                            return slot == planned.id
                        }
                        return session.workoutTemplateId == day.id
                    }
                    if let match { logs.append(match) }
                }
                guard !logs.isEmpty,
                      let suggestion = progressionService.suggest(
                          for: planned,
                          previousLogs: logs,
                          exerciseInfo: exercises[planned.exerciseId]
                      ) else { continue }
                results.append(PlanSlotSuggestion(dayId: day.id, dayName: day.name, planned: planned, suggestion: suggestion))
            }
        }
        return results
    }

    /// "Not now" on the coach card: snooze these lifts on this device for
    /// `CoachSuggestion.snoozeDays`. A lift that recovers in the meantime
    /// loses its snooze, so stalling again later is offered again.
    func dismissCoachSuggestion(userId: String, now: Date = Date()) {
        guard let coachSuggestion else { return }
        coachSuggestionStore.snooze(coachSuggestion.snoozeKeys, userId: userId, now: now)
        self.coachSuggestion = nil
    }

    /// The lifter saved the AI's plan edit from the coach card. Retire the
    /// card and re-derive Up Next from the saved plan, exactly as
    /// `applyRefreshedProgram` does: the AI hands back rewritten days, and an
    /// adaptation of the old day doesn't apply to the new one.
    func applyCoachSuggestion(plan: WorkoutPlan, userId: String, workoutService: any WorkoutServicing, now: Date = Date()) {
        // Also snooze the edited slots: a new rep range would otherwise be
        // judged at once on history logged under the old one.
        if let coachSuggestion {
            coachSuggestionStore.snooze(coachSuggestion.editedSnoozeKeys(in: plan), userId: userId, now: now)
        }
        dismissCoachSuggestion(userId: userId, now: now)
        adaptedWorkout = nil
        activePlanId = plan.id
        todayWorkout = Self.nextWorkout(plan: plan, sessions: workoutService.recentSessions)
    }

    /// "Keep going" on the switch-it-up card: the program is working, so
    /// nothing about it changes — only the card's clock restarts, buying
    /// another full cadence. Today's choices are deliberately left alone: an
    /// accepted adaptation and a day picked from "Change" both survive,
    /// because keeping the program is not a change to it.
    func keepProgram(
        plan: WorkoutPlan,
        workoutService: any WorkoutServicing,
        now: Date = Date()
    ) async throws {
        try await dismissProgramRefresh(plan: plan, workoutService: workoutService, now: now)
    }

    /// An accepted "Switch it up with AI" edit. The sheet has already saved
    /// the rewritten plan, so Up Next must be re-derived from it the way
    /// `startNextBlock` does: the day it pointed at may be gone or rewritten
    /// in place, and an adaptation of the old day certainly doesn't apply to
    /// the new one.
    func applyRefreshedProgram(
        plan: WorkoutPlan,
        workoutService: any WorkoutServicing,
        now: Date = Date()
    ) async throws {
        try await dismissProgramRefresh(plan: plan, workoutService: workoutService, now: now)
        adaptedWorkout = nil
        activePlanId = plan.id
        todayWorkout = Self.nextWorkout(plan: plan, sessions: workoutService.recentSessions)
    }

    /// Stamps the dismissal both choices share.
    private func dismissProgramRefresh(
        plan: WorkoutPlan,
        workoutService: any WorkoutServicing,
        now: Date
    ) async throws {
        var next = plan
        next.refreshPromptedAt = now
        try await workoutService.savePlan(next)
        programRefresh = nil
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
        programRefresh = nil
        adaptedWorkout = nil
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
        userId: String,
        liveActivity: (any WorkoutLiveActivitying)? = nil
    ) async {
        guard let session = staleSession else { return }
        isRepairing = true
        repairError = nil
        do {
            try await workoutService.completeSession(session, endingAt: session.repairEndDate())
            SessionReminderScheduler.cancelPending()
            liveActivity?.endAll()
            staleSession = nil
            await load(workoutService: workoutService, healthKitService: healthKitService, userId: userId, liveActivity: liveActivity)
        } catch {
            repairError = "Couldn't finish workout: \(error.localizedDescription)"
        }
        isRepairing = false
    }

    func discardStaleSession(
        workoutService: any WorkoutServicing,
        healthKitService: any HealthKitServicing,
        userId: String,
        liveActivity: (any WorkoutLiveActivitying)? = nil
    ) async {
        guard let session = staleSession else { return }
        isRepairing = true
        repairError = nil
        do {
            try await workoutService.abandonSession(session)
            SessionReminderScheduler.cancelPending()
            liveActivity?.endAll()
            staleSession = nil
            await load(workoutService: workoutService, healthKitService: healthKitService, userId: userId, liveActivity: liveActivity)
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
