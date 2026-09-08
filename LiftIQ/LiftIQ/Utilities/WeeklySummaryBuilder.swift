import Foundation

/// Builds the weekly check-in request from sessions already loaded on the
/// dashboard. Pure so the exact payload that leaves the device is testable.
enum WeeklySummaryBuilder {
    static let maxLifts = 10

    /// Nil when the reviewed week has no completed session — there is
    /// nothing honest to say about an empty week.
    static func build(
        sessions: [WorkoutSession],
        plan: WorkoutPlan?,
        profile: UserProfile?,
        unitSystem: UnitSystem,
        reviewWeekStart: Date,
        calendar: Calendar = .current
    ) -> WeeklyInsightsRequest? {
        guard let priorWeekStart = calendar.date(byAdding: .day, value: -7, to: reviewWeekStart),
              let reviewWeekEnd = calendar.date(byAdding: .day, value: 7, to: reviewWeekStart) else { return nil }

        let completed = sessions.filter { $0.status == .completed }
        let lastWeek = completed.filter { $0.startedAt >= reviewWeekStart && $0.startedAt < reviewWeekEnd }
        let priorWeek = completed.filter { $0.startedAt >= priorWeekStart && $0.startedAt < reviewWeekStart }
        guard !lastWeek.isEmpty else { return nil }

        let priorBest = bestSets(in: priorWeek)
        let lifts = bestSets(in: lastWeek)
            .sorted { $0.value.set.estimated1RM > $1.value.set.estimated1RM }
            .prefix(maxLifts)
            .map { exerciseId, entry in
                WeeklyInsightsRequest.Lift(
                    name: entry.name,
                    lastWeek: liftWeek(entry.set, unitSystem: unitSystem),
                    priorWeek: priorBest[exerciseId].map { liftWeek($0.set, unitSystem: unitSystem) }
                )
            }

        return WeeklyInsightsRequest(
            weightUnit: UnitConversionService.weightLabel(for: unitSystem),
            plannedSessionsPerWeek: plan.map { min(7, max(1, $0.workoutsPerWeek)) },
            goal: profile?.goals.first?.rawValue,
            experienceLevel: profile?.experienceLevel.rawValue,
            lastWeek: summary(of: lastWeek, weekStart: reviewWeekStart, unitSystem: unitSystem, calendar: calendar),
            priorWeek: priorWeek.isEmpty
                ? nil
                : summary(of: priorWeek, weekStart: priorWeekStart, unitSystem: unitSystem, calendar: calendar),
            lifts: Array(lifts)
        )
    }

    private static func summary(
        of sessions: [WorkoutSession],
        weekStart: Date,
        unitSystem: UnitSystem,
        calendar: Calendar
    ) -> WeeklyInsightsRequest.WeekSummary {
        let moods = sessions.compactMap(\.mood).map(Double.init)
        let prIds = Set(sessions.flatMap(\.exerciseLogs).flatMap(\.sets).flatMap { $0.personalRecordIds ?? [] })
        let volumeKg = sessions.reduce(0) { $0 + $1.totalVolumeKg }
        return WeeklyInsightsRequest.WeekSummary(
            weekStart: dayString(weekStart, calendar: calendar),
            sessionsCompleted: sessions.count,
            totalVolume: UnitConversionService.convertWeight(volumeKg, to: unitSystem).rounded(),
            distinctDays: Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).count,
            prCount: prIds.count,
            averageDifficulty: moods.isEmpty ? nil : (moods.reduce(0, +) / Double(moods.count) * 10).rounded() / 10
        )
    }

    /// Best working set per exercise (by e1RM) with the name it was logged under.
    private static func bestSets(in sessions: [WorkoutSession]) -> [String: (name: String, set: SetLog)] {
        var best: [String: (name: String, set: SetLog)] = [:]
        for log in sessions.flatMap(\.exerciseLogs) {
            for set in log.sets where set.setType == .working && set.weightKg > 0 && set.reps > 0 {
                if let current = best[log.exerciseId], current.set.estimated1RM >= set.estimated1RM { continue }
                best[log.exerciseId] = (log.exerciseName, set)
            }
        }
        return best
    }

    private static func liftWeek(_ set: SetLog, unitSystem: UnitSystem) -> WeeklyInsightsRequest.LiftWeek {
        let weight = UnitConversionService.convertWeight(set.weightKg, to: unitSystem)
        return WeeklyInsightsRequest.LiftWeek(weight: (weight * 10).rounded() / 10, reps: set.reps)
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
