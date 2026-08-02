import Foundation

/// Cross-exercise "executive" aggregates for the Progress tab.
///
/// The strength index answers "am I stronger than six months ago?" without
/// the single-lift noise problem: each exercise's sessions are measured in
/// log-space against that exercise's own baseline (its first two sessions
/// inside the window), and a week's index is the mean of every observation's
/// delta that week. Averaging ~N lifts per week shrinks the ~9%
/// single-observation scatter by roughly √N, which is what lets an overview
/// chart show a trend the per-lift charts honestly can't.
///
/// The window is explicit (`windowDays`) rather than an accidental
/// query-limit truncation: the index is a *rolling* comparison against where
/// each lift stood at the window's start, which for histories shorter than
/// the window is simply the lifter's actual start.
struct ProgressOverview {
    /// 26 weeks. Also the fetch cutoff callers should use.
    static let windowDays = 182

    struct WeekPoint: Identifiable {
        let weekStart: Date
        let value: Double
        var id: Date { weekStart }
    }

    /// exp(mean log-delta) per week, as a fraction of baseline (1.0 = level
    /// with each lift's starting strength). Only weeks with observations —
    /// an untrained week has no strength measurement, so no point.
    let weeklyStrengthIndex: [WeekPoint]
    /// Total volume (kg) across all exercises per week, zero-filled for
    /// every calendar week from the first data week through `through` — a
    /// skipped week is a real zero, not a gap to paper over.
    let weeklyVolume: [WeekPoint]
    /// Distinct training days per week, zero-filled the same way. Sourced
    /// from completed-session dates when provided (so bodyweight-only days
    /// count), falling back to record dates.
    let weeklyTrainingDays: [WeekPoint]
    /// Trend over the index series, fitted with noise scaled down by the
    /// average number of observations per weekly point.
    let trend: StrengthTrend?

    /// Percent change of the latest index week vs baseline (e.g. +4.2).
    var strengthChangePercent: Double? {
        guard let last = weeklyStrengthIndex.last else { return nil }
        return (last.value - 1.0) * 100
    }

    static func compute(
        records: [ProgressRecord],
        sessionDates: [Date] = [],
        through: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgressOverview {
        let usable = records.filter { $0.estimated1RM > 0 }
        func weekStart(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }

        // Per-exercise baseline: mean ln(e1RM) of the first two observations.
        // Two sessions instead of one halves the odds that a single outlier
        // day defines "where you started".
        var baselines: [String: Double] = [:]
        let byExercise = Dictionary(grouping: usable, by: \.exerciseId)
        for (exerciseId, recs) in byExercise {
            let first = recs.sorted { $0.date < $1.date }.prefix(2).map { log($0.estimated1RM) }
            baselines[exerciseId] = first.reduce(0, +) / Double(first.count)
        }

        var deltasByWeek: [Date: [Double]] = [:]
        var volumeByWeek: [Date: Double] = [:]
        var daysByWeek: [Date: Set<Date>] = [:]
        for record in usable {
            let week = weekStart(record.date)
            if let baseline = baselines[record.exerciseId] {
                deltasByWeek[week, default: []].append(log(record.estimated1RM) - baseline)
            }
            volumeByWeek[week, default: 0] += record.totalVolume
        }
        for date in sessionDates.isEmpty ? usable.map(\.date) : sessionDates {
            daysByWeek[weekStart(date), default: []].insert(calendar.startOfDay(for: date))
        }

        let index = deltasByWeek
            .map { week, deltas in
                WeekPoint(weekStart: week, value: exp(deltas.reduce(0, +) / Double(deltas.count)))
            }
            .sorted { $0.weekStart < $1.weekStart }

        // Zero-fill volume and training days across every calendar week from
        // the earliest data to `through`, so time off shows as zeros instead
        // of silently compressing the timeline.
        var volume: [WeekPoint] = []
        var days: [WeekPoint] = []
        let dataWeeks = Set(volumeByWeek.keys).union(daysByWeek.keys)
        if let firstWeek = dataWeeks.min() {
            var week = firstWeek
            let lastWeek = max(weekStart(through), dataWeeks.max() ?? firstWeek)
            while week <= lastWeek {
                volume.append(WeekPoint(weekStart: week, value: volumeByWeek[week] ?? 0))
                days.append(WeekPoint(weekStart: week, value: Double(daysByWeek[week]?.count ?? 0)))
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = next
            }
        }

        // Effective per-point noise: single-lift SD shrunk by √(mean
        // observations per week), floored because same-day observations are
        // not fully independent (shared fatigue, sleep, and formula bias).
        var trend: StrengthTrend?
        if !index.isEmpty {
            let meanPerWeek = Double(usable.count) / Double(index.count)
            let sd = max(StrengthTrend.observationSD / meanPerWeek.squareRoot(), 0.035)
            trend = StrengthTrend.fit(
                dates: index.map(\.weekStart),
                e1RMs: index.map(\.value),
                observationSD: sd
            )
        }

        return ProgressOverview(
            weeklyStrengthIndex: index,
            weeklyVolume: volume,
            weeklyTrainingDays: days,
            trend: trend
        )
    }
}
