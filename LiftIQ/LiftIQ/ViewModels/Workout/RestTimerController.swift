import Foundation
import Observation
import UserNotifications

/// Owns the between-set rest countdown: wall-clock state, the repeating
/// Timer, and the local "rest complete" notification. Extracted from
/// WorkoutExecutionViewModel so timer mechanics stay isolated from workout
/// logic. The displayed value derives from `endDate` rather than counting
/// ticks so the countdown survives backgrounding (foreground Timers suspend).
@MainActor
@Observable
final class RestTimerController {
    var isActive = false
    var secondsRemaining: Int = 0
    var totalSeconds: Int = 0

    private var endDate: Date?
    private var timer: Timer?
    private static let restNotificationId = "liftiq.rest-timer-complete"
    /// Invalidates in-flight notification-scheduling callbacks: bumped on
    /// every schedule and cancel, so a stale `getNotificationSettings`
    /// completion can never add a notification for a timer that was skipped,
    /// adjusted, or restarted while the callback was in flight.
    private var notificationGeneration = 0
    /// Injectable clock so tests can drive wall-clock expiry.
    private let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Control

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        timer?.invalidate()
        endDate = now().addingTimeInterval(TimeInterval(seconds))
        secondsRemaining = seconds
        totalSeconds = seconds
        isActive = true
        scheduleRestEndNotification()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func skip() {
        timer?.invalidate()
        endDate = nil
        secondsRemaining = 0
        isActive = false
        cancelRestEndNotification()
    }

    func adjust(by seconds: Int) {
        guard let endDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(seconds))
        let remaining = max(0, Int(newEnd.timeIntervalSince(now()).rounded(.up)))
        if remaining <= 0 {
            skip()
            return
        }
        self.endDate = newEnd
        secondsRemaining = remaining
        totalSeconds = max(totalSeconds, remaining)
        scheduleRestEndNotification()
    }

    /// Re-syncs the displayed countdown from the wall clock. Called when the
    /// app returns to the foreground, since Timers suspend in the background.
    func refreshFromWallClock() {
        guard isActive else { return }
        if let endDate, endDate.timeIntervalSince(now()) <= 0 {
            // Rest ended while backgrounded: the local notification already
            // rang, so finish without the in-app chime — ringing here too
            // would double-ring the same rest.
            secondsRemaining = 0
            finish(ringInApp: false)
        } else {
            tick()
        }
    }

    /// Tears down the timer and any pending notification without firing
    /// completion feedback (used when the workout screen goes away). Resets
    /// the published state too — a VM that outlives its view would otherwise
    /// keep showing a stale rest overlay when re-presented.
    func stop() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isActive = false
        secondsRemaining = 0
        totalSeconds = 0
        cancelRestEndNotification()
    }

    // MARK: - Tick

    private func tick() {
        guard let endDate else {
            timer?.invalidate()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSince(now()).rounded(.up)))
        secondsRemaining = remaining
        if remaining <= 0 {
            // Foreground completion: iOS suppresses the pending local
            // notification (no foreground-presentation delegate), so ring
            // in-app.
            finish(ringInApp: true)
        }
    }

    /// Common completion: tears down the timer and pending notification.
    /// `ringInApp` is true only for foreground expiry — background expiry
    /// already rang via the local notification.
    private func finish(ringInApp: Bool) {
        timer?.invalidate()
        endDate = nil
        isActive = false
        cancelRestEndNotification()
        if ringInApp {
            SoundEffects.restComplete()
            Haptics.success()
        }
    }

    // MARK: - Rest-End Notification

    /// Asks for notification permission before the first rest timer needs it.
    /// Called when the workout screen appears, so the system prompt doesn't
    /// land mid-set and the first timer's notification isn't delayed behind
    /// the user's answer to the prompt.
    static func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func scheduleRestEndNotification() {
        guard endDate != nil else { return }
        notificationGeneration += 1
        let generation = notificationGeneration
        // Drop the previous schedule synchronously: if the app suspends while
        // the settings callback below is in flight, an already-pending stale
        // notification must not be the one that fires.
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            Task { @MainActor in
                // Re-validate against current timer state: a skip, adjust, or
                // restart while the settings callback was in flight bumped the
                // generation, and this schedule must be dropped.
                guard let self,
                      generation == self.notificationGeneration,
                      let endDate = self.endDate else { return }
                let remaining = endDate.timeIntervalSince(self.now())
                guard remaining > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = "Rest complete"
                content.body = "Time for your next set."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
                UNUserNotificationCenter.current()
                    .add(UNNotificationRequest(identifier: Self.restNotificationId, content: content, trigger: trigger))
            }
        }
    }

    private func cancelRestEndNotification() {
        notificationGeneration += 1
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.restNotificationId])
    }
}
