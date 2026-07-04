import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var isLoading = false
    var todayWorkout: WorkoutTemplate?
    var streak: Int = 0
    var weeklyVolume: Double = 0
    var weeklySessionCount: Int = 0

    func load(workoutService: any WorkoutServicing, userId: String) async {
        isLoading = true
        do {
            try await workoutService.loadPlans(userId: userId)
            try await workoutService.loadRecentSessions(userId: userId)
            try await workoutService.loadActiveSession(userId: userId)

            computeTodayWorkout(from: workoutService.activePlan)
            computeStats(from: workoutService.recentSessions)
        } catch {
            // Handle silently for dashboard
        }
        isLoading = false
    }

    private func computeTodayWorkout(from plan: WorkoutPlan?) {
        guard let plan, !plan.workouts.isEmpty else {
            todayWorkout = nil
            return
        }
        let weekday = Calendar.current.component(.weekday, from: Date())
        // .weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
        // Convert to Monday=0, Tuesday=1, ..., Sunday=6
        let daysSinceMonday = (weekday + 5) % 7
        let workoutIndex = daysSinceMonday % plan.workouts.count
        todayWorkout = plan.workouts[workoutIndex]
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
