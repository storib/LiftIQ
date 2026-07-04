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

    // MARK: - Control

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        timer?.invalidate()
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        secondsRemaining = seconds
        totalSeconds = seconds
        isActive = true
        scheduleRestEndNotification(after: seconds)

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
        let remaining = max(0, Int(newEnd.timeIntervalSinceNow.rounded(.up)))
        if remaining <= 0 {
            skip()
            return
        }
        self.endDate = newEnd
        secondsRemaining = remaining
        totalSeconds = max(totalSeconds, remaining)
        scheduleRestEndNotification(after: remaining)
    }

    /// Re-syncs the displayed countdown from the wall clock. Called when the
    /// app returns to the foreground, since Timers suspend in the background.
    func refreshFromWallClock() {
        if isActive {
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
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        secondsRemaining = remaining
        if remaining <= 0 {
            timer?.invalidate()
            self.endDate = nil
            isActive = false
            Haptics.success()
        }
    }

    // MARK: - Rest-End Notification

    private func scheduleRestEndNotification(after seconds: Int) {
        guard seconds > 0 else { return }
        let identifier = Self.restNotificationId
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Time for your next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(seconds),
                repeats: false
            )
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    private func cancelRestEndNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
    }
}
