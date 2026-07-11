import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var isLoading = false
    var todayWorkout: WorkoutTemplate?
    var streak: Int = 0
    var weeklyVolume: Double = 0
    var weeklySessionCount: Int = 0
    var selectedDate: Date
    private(set) var externalActivities: [ExternalActivity] = []

    private let calendar: Calendar
    private var weekStart: Date

    init(referenceDate: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
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
        referenceDate: Date = Date()
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

            todayWorkout = Self.nextWorkout(
                plan: workoutService.activePlan,
                sessions: workoutService.recentSessions
            )
            computeStats(from: workoutService.recentSessions)
        } catch {
            // Handle silently for dashboard
        }

        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        do {
            externalActivities = try await healthKitService.fetchExternalActivities(from: weekStart, to: weekEnd)
        } catch {
            externalActivities = []
        }
        isLoading = false
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
        let calendar = Calendar.current
        let startOfWeek = Date().startOfWeek()
        let thisWeekSessions = sessions.filter { $0.status == .completed && $0.startedAt >= startOfWeek }
        weeklySessionCount = thisWeekSessions.count
        weeklyVolume = thisWeekSessions.reduce(0) { $0 + $1.totalVolumeKg }

        // Calculate streak
        streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        let completedDates = Set(sessions.filter { $0.status == .completed }.map { calendar.startOfDay(for: $0.startedAt) })

        // Check if today has a workout, if not start from yesterday
        if !completedDates.contains(checkDate) {
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }

        while completedDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
    }
}
