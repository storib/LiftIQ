import ActivityKit
import Foundation

/// Seam over ActivityKit so the view model can be tested without a device.
@MainActor
protocol WorkoutLiveActivitying: AnyObject {
    func start(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState)
    func update(_ state: WorkoutActivityAttributes.ContentState)
    /// Ends the activity this controller owns.
    func end()
    /// Ends every workout activity — dashboard repair paths and orphan
    /// cleanup never hold the owning controller.
    func endAll()
}

/// Owns the one Live Activity for the running workout. Activities survive
/// app termination, so `start` adopts an existing one for the same session
/// instead of stacking a second banner. Everything is best-effort: a
/// refused or failed activity never touches the workout.
@MainActor
final class WorkoutLiveActivityController: WorkoutLiveActivitying {
    static let enabledKey = "liftiq.liveActivityEnabled"

    /// Device-local preference (Profile → Workout Settings), on by default.
    /// Turning it off removes the current banner immediately.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { WorkoutLiveActivityController.endAllActivities() }
        }
    }

    private var activity: Activity<WorkoutActivityAttributes>?

    func start(attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        guard Self.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: state.restEndDate)
        let existing = Activity<WorkoutActivityAttributes>.activities
        // Adopt this session's activity if the app was relaunched mid-workout;
        // anything else is a stray from an earlier session.
        for stray in existing where stray.attributes.sessionId != attributes.sessionId {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
        if let mine = existing.first(where: { $0.attributes.sessionId == attributes.sessionId }) {
            activity = mine
            Task { await mine.update(content) }
            return
        }
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: state.restEndDate)
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    func endAll() {
        activity = nil
        Self.endAllActivities()
    }

    private static func endAllActivities() {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
