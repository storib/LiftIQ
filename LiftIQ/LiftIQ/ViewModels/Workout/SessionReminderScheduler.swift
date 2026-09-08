import Foundation
import UserNotifications

/// Schedules the "Still working out?" local notification for a session that
/// has been running unusually long. The app has no background execution, so
/// this can't end the session itself — it only brings the lifter back, where
/// the dashboard offers to finish at the last set or discard.
///
/// Mirrors `RestTimerController`'s notification plumbing: one identifier,
/// a settings check before adding, and a generation counter so a cancel
/// racing an in-flight settings check always wins.
@MainActor
final class SessionReminderScheduler {
    static let notificationId = "liftiq.session-still-active"
    static let enabledKey = "liftiq.sessionReminderEnabled"

    /// Device-local preference, on by default. Turning it off also drops any
    /// reminder already scheduled for a running session.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { cancelPending() }
        }
    }

    private var generation = 0
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// Seconds until the reminder should fire, or nil once the delay has
    /// already elapsed — resuming a session that is already stale gets no
    /// reminder; the lifter is in the app and the repair card handles it.
    static func fireDelay(
        startedAt: Date,
        now: Date,
        delay: TimeInterval = Constants.sessionReminderDelaySeconds
    ) -> TimeInterval? {
        let remaining = startedAt.addingTimeInterval(delay).timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    func schedule(for session: WorkoutSession) {
        generation += 1
        let generation = generation
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        guard Self.isEnabled,
              let delay = Self.fireDelay(startedAt: session.startedAt, now: now()) else { return }
        let workoutName = session.workoutName
        let sessionId = session.id
        Task { @MainActor [weak self] in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            // Re-validate after the await: a finish, abandon, or the Profile
            // toggle flipping off while we waited means this must be dropped.
            guard let self, generation == self.generation, Self.isEnabled else { return }
            let content = UNMutableNotificationContent()
            content.title = "Still working out?"
            content.body = "\(workoutName) has been running for 2 hours. Open LiftIQ to finish or discard it."
            content.sound = .default
            content.userInfo = ["sessionId": sessionId]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger))
        }
    }

    func cancel() {
        generation += 1
        Self.cancelPending()
    }

    /// Removes the reminder without an instance — the dashboard repair
    /// paths finish or discard a session the execution screen never held.
    static func cancelPending() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationId])
        center.removeDeliveredNotifications(withIdentifiers: [notificationId])
    }
}
