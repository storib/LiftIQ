import Foundation

/// The "switch it up" checkpoint: an opt-in nudge, after a user-chosen number
/// of weeks on the same program, to keep it, have the AI tweak it, or build
/// something new.
///
/// Deliberately a *scheduling* rule, not a plateau detector. Per-session e1RM
/// observations carry ~10% noise against trained gain rates of 1-3%/year, so
/// no short-window signal can honestly say a program stopped working (see
/// `StrengthTrend` and `ProgressionService`). What this can say is how long
/// the program has been running and how many lifts have been holding at the
/// same top weight — both descriptions of what happened, never predictions.
/// Nothing here changes the plan on its own.
struct ProgramRefresh: Equatable {
    /// Whole weeks since the program started (or since the last time this
    /// card was dismissed).
    let weeksOnProgram: Int
    /// The cadence the lifter chose, in weeks.
    let cadenceWeeks: Int
    /// Completed sessions on this plan since the same anchor.
    let sessionsOnProgram: Int
    /// Lifts whose progression suggestion is currently a stall — the best
    /// top-weight set has missed the rep floor at the same weight for
    /// `Constants.stallThreshold` sessions running. Descriptive only.
    let holdingLifts: Int

    /// Cadences offered in Profile. Eight weeks is about the shortest block
    /// worth judging; a year of the same program is where even a happy
    /// lifter should be asked.
    static let cadenceOptions = [8, 12, 16, 24]

    /// A prompt only makes sense while the program is actually in use; a plan
    /// left untouched for a month shouldn't greet the lifter with "16 weeks
    /// on this program" when they come back.
    static let activityWindowDays = 21

    /// Non-nil when the card should be shown.
    ///
    /// - Parameters:
    ///   - cadenceWeeks: `UserProfile.programRefreshWeeks`; nil means off.
    ///   - planSessionDates: start dates of completed sessions for this plan.
    static func due(
        plan: WorkoutPlan,
        cadenceWeeks: Int?,
        planSessionDates: [Date],
        holdingLifts: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgramRefresh? {
        guard let cadenceWeeks, cadenceWeeks > 0 else { return nil }
        let anchor = anchorDate(for: plan)
        guard anchor <= now else { return nil }

        let weeks = calendar.dateComponents([.weekOfYear], from: anchor, to: now).weekOfYear ?? 0
        guard weeks >= cadenceWeeks else { return nil }

        let activeSince = calendar.date(byAdding: .day, value: -activityWindowDays, to: now) ?? now
        let sessionsSinceAnchor = planSessionDates.filter { $0 >= anchor }
        guard sessionsSinceAnchor.contains(where: { $0 >= activeSince }) else { return nil }

        return ProgramRefresh(
            weeksOnProgram: weeks,
            cadenceWeeks: cadenceWeeks,
            sessionsOnProgram: sessionsSinceAnchor.count,
            holdingLifts: holdingLifts
        )
    }

    /// Where the clock starts: the program's creation, or the last time the
    /// lifter said "keep going" to this card (which buys another full
    /// cadence).
    static func anchorDate(for plan: WorkoutPlan) -> Date {
        guard let prompted = plan.refreshPromptedAt else { return plan.createdAt }
        return max(plan.createdAt, prompted)
    }

    /// How many of the plan's lifts are currently stalled, from suggestions
    /// already computed elsewhere. Kept here so the card's copy and this
    /// count can never drift apart.
    static func holdingLiftCount(_ suggestions: [ProgressionSuggestion]) -> Int {
        suggestions.count { $0.isStalled }
    }
}
