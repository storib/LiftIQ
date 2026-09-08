import ActivityKit
import Foundation

/// Everything the Lock Screen / Dynamic Island needs, as display-ready
/// primitives. Shared by the app and the widget extension (listed in both
/// targets' sources), so it must not pull in the app's models or Firebase.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Exercise being worked, or a closing line once every set is done.
        var exerciseName: String
        /// "Set 2 of 3 · 8-12 reps · 185 lb"
        var setLabel: String
        /// "Next: Set 3 · 185 lb" or "Next: Incline DB Press"; nil when done.
        var nextUpLabel: String?
        var completedSets: Int
        var totalSets: Int
        /// Present only while resting.
        var restEndDate: Date?
        var restTotalSeconds: Int?

        var isResting: Bool { restEndDate != nil }

        /// Range for `timerInterval` views: stable lower bound (rest start),
        /// nil once the rest has expired — a `now...end` range with `end`
        /// in the past is an invalid ClosedRange and traps inside the
        /// extension, which can render long after the app was suspended.
        func restRange(now: Date = Date()) -> ClosedRange<Date>? {
            guard let end = restEndDate, end > now else { return nil }
            let total = max(1, restTotalSeconds ?? 60)
            let start = min(end.addingTimeInterval(-Double(total)), now)
            return start...end
        }
    }

    var workoutName: String
    var startedAt: Date
    /// Lets a relaunched app adopt its own activity instead of duplicating it.
    var sessionId: String
}
