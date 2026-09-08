import Foundation

/// Achievements worth a moment on the summary screen. Only milestones the
/// just-finished session crossed are returned, so nothing needs persisting:
/// a threshold is hit exactly once.
enum Milestone: Equatable, Identifiable, Hashable {
    /// Lifetime completed workouts: 10, 25, 50, 100, then every 50.
    case workoutCount(Int)
    /// Consecutive weeks meeting the weekly training target: 4, 8, 12, 26, 52.
    case weekStreak(Int)

    var id: String {
        switch self {
        case .workoutCount(let count): return "workouts-\(count)"
        case .weekStreak(let weeks): return "weeks-\(weeks)"
        }
    }

    var title: String {
        switch self {
        case .workoutCount(let count): return "\(count) workouts"
        case .weekStreak(let weeks): return "\(weeks)-week streak"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutCount(let count):
            switch count {
            case 10: return "Ten sessions in the book. This is a habit now."
            case 25: return "Twenty-five workouts of showing up."
            case 50: return "Fifty. Most people never get here."
            case 100: return "One hundred workouts. Look at your charts."
            default: return "\(count) workouts and still going."
            }
        case .weekStreak(let weeks):
            switch weeks {
            case 4: return "A full month of hitting your training days."
            case 8: return "Two months without missing a week."
            case 12: return "A whole quarter of consistency."
            case 26: return "Half a year. Consistency is the whole game."
            default: return "\(weeks) weeks straight. Remarkable."
            }
        }
    }
}

enum Milestones {
    static let streakThresholds: Set<Int> = [4, 8, 12, 26, 52]
    /// How far back the streak needs to look; also the fetch bound callers use.
    static let streakWindowWeeks = 53

    static func isWorkoutMilestone(_ count: Int) -> Bool {
        switch count {
        case 10, 25, 50: return true
        default: return count >= 100 && count % 50 == 0
        }
    }

    /// Consecutive weeks (Monday-start, matching the dashboard strip) with at
    /// least `weeklyTarget` completed sessions, counted back from the week
    /// containing `now`. The current week never breaks the streak while it's
    /// still in progress — it simply doesn't count until it qualifies.
    static func weekStreak(
        completedSessionDates: [Date],
        weeklyTarget: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let target = max(1, weeklyTarget)
        var counts: [Date: Int] = [:]
        for date in completedSessionDates {
            counts[date.startOfWeek(using: calendar), default: 0] += 1
        }
        var week = now.startOfWeek(using: calendar)
        var streak = 0
        if (counts[week] ?? 0) < target {
            guard let previous = calendar.date(byAdding: .day, value: -7, to: week) else { return 0 }
            week = previous
        }
        while (counts[week] ?? 0) >= target {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: week) else { break }
            week = previous
        }
        return streak
    }

    /// Milestones crossed by the session completed at `now`.
    /// `completedSessionDates` must include that session.
    static func evaluate(
        totalCompletedCount: Int,
        completedSessionDates: [Date],
        weeklyTarget: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Milestone] {
        var milestones: [Milestone] = []
        if isWorkoutMilestone(totalCompletedCount) {
            milestones.append(.workoutCount(totalCompletedCount))
        }
        // A streak milestone fires on the session that makes this week
        // qualify — exactly the target-th one, so a bonus session later in
        // the week can't fire it twice.
        let target = max(1, weeklyTarget)
        let thisWeek = now.startOfWeek(using: calendar)
        let thisWeekCount = completedSessionDates.filter { $0.startOfWeek(using: calendar) == thisWeek }.count
        if thisWeekCount == target {
            let streak = weekStreak(completedSessionDates: completedSessionDates, weeklyTarget: target, now: now, calendar: calendar)
            if streakThresholds.contains(streak) {
                milestones.append(.weekStreak(streak))
            }
        }
        return milestones
    }
}
