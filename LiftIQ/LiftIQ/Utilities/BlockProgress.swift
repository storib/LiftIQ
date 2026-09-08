import Foundation

/// Where the lifter is in the plan's current training block, derived from
/// completed sessions rather than the calendar: a week off pauses the block
/// instead of burning it, and `WorkoutPlan.currentWeek` (which nothing ever
/// advanced) stops mattering.
struct BlockProgress: Equatable {
    let blockNumber: Int
    let weekCount: Int
    let workoutsPerWeek: Int
    let completedSessions: Int

    var sessionsPerBlock: Int { weekCount * max(1, workoutsPerWeek) }

    var currentWeek: Int {
        min(weekCount, completedSessions / max(1, workoutsPerWeek) + 1)
    }

    var isComplete: Bool { completedSessions >= sessionsPerBlock }

    /// The plan's optional deload week, honoured as a caption only — never
    /// an automatic change to suggestions.
    func isDeloadWeek(_ deloadWeek: Int?) -> Bool {
        guard let deloadWeek else { return false }
        return !isComplete && deloadWeek == currentWeek
    }

    static func compute(plan: WorkoutPlan, sessions: [WorkoutSession]) -> BlockProgress {
        let start = plan.effectiveBlockStart
        let completed = sessions.filter {
            $0.status == .completed && $0.planId == plan.id && $0.startedAt >= start
        }
        return BlockProgress(
            blockNumber: plan.effectiveBlockNumber,
            weekCount: max(1, plan.weekCount),
            workoutsPerWeek: max(1, plan.workoutsPerWeek),
            completedSessions: completed.count
        )
    }
}

/// What the end-of-block card shows. Strength is the ProgressOverview index
/// over the block window, so it's block-relative by construction.
struct BlockReview: Equatable {
    let blockNumber: Int
    let weeks: Int
    let sessions: Int
    let strengthChangePercent: Double?
    let prCount: Int
}
