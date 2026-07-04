import Foundation
import Observation

/// One cell in the weekly history view: either a completed/abandoned session
/// or a projected upcoming plan day.
enum HistoryDayEntry: Identifiable, Hashable {
    case session(WorkoutSession)
    case planned(WorkoutTemplate, Date)

    var id: String {
        switch self {
        case .session(let session): return "session-\(session.id)"
        case .planned(let template, let date): return "planned-\(template.id)-\(date.timeIntervalSince1970)"
        }
    }
}

@MainActor
@Observable
final class WorkoutHistoryViewModel {
    var weekStart: Date
    var errorMessage: String?

    private let calendar = Calendar.current

    init(weekStart: Date = Date().startOfWeek()) {
        self.weekStart = weekStart
    }

    var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var isCurrentWeek: Bool {
        calendar.isDate(weekStart, inSameDayAs: Date().startOfWeek())
    }

    func moveWeek(by offset: Int) {
        if let moved = calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart) {
            weekStart = moved
        }
    }

    func goToCurrentWeek() {
        weekStart = Date().startOfWeek()
    }

    func sessions(on day: Date, from sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions
            .filter { $0.status != .inProgress && calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    /// Projects the plan rotation onto upcoming days of the displayed week:
    /// future days (and today, if nothing was completed yet) are filled, one
    /// workout per day, until the week holds `plan.workoutsPerWeek` workouts.
    /// A heuristic — plans order days but don't pin them to weekdays.
    func plannedEntries(
        plan: WorkoutPlan?,
        sessions allSessions: [WorkoutSession],
        today: Date = Date()
    ) -> [Date: WorkoutTemplate] {
        guard let plan, plan.workoutsPerWeek > 0 else { return [:] }
        let startOfToday = calendar.startOfDay(for: today)

        let completedThisWeek = allSessions.filter {
            $0.status == .completed &&
            $0.startedAt >= weekStart &&
            $0.startedAt < (calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart)
        }

        let openDays = weekDays.filter { day in
            day >= startOfToday && !completedThisWeek.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
        }
        let remaining = max(0, plan.workoutsPerWeek - completedThisWeek.count)
        guard remaining > 0 else { return [:] }

        let rotation = DashboardViewModel.upcomingRotation(plan: plan, sessions: allSessions, count: remaining)
        var result: [Date: WorkoutTemplate] = [:]
        for (day, template) in zip(openDays.prefix(remaining), rotation) {
            result[day] = template
        }
        return result
    }

    /// PR rollback and progress-record cleanup are handled by the service
    /// and the backend respectively; the ViewModel only surfaces errors.
    func delete(session: WorkoutSession, workoutService: any WorkoutServicing) async {
        errorMessage = nil
        do {
            try await workoutService.deleteSession(session)
        } catch {
            errorMessage = "Couldn't delete workout: \(error.localizedDescription)"
        }
    }
}
