import SwiftUI
import Charts

struct ProgressDashboardView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    // Chart state
    @State private var selectedExerciseId: String?
    @State private var progressRecords: [ProgressRecord] = []
    @State private var isLoadingRecords = false
    @State private var overview: ProgressOverview?

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    private var weightUnit: String {
        UnitConversionService.weightLabel(for: unitSystem)
    }

    /// Exercises the user can chart, derived from the exercises present in
    /// their recent PRs (each PR carries the id + display name).
    private var exerciseOptions: [(id: String, name: String)] {
        var seen = Set<String>()
        var options: [(id: String, name: String)] = []
        for pr in dependencies.progressService.recentPRs where !seen.contains(pr.exerciseId) {
            seen.insert(pr.exerciseId)
            options.append((id: pr.exerciseId, name: pr.exerciseName))
        }
        return options.sorted { $0.name < $1.name }
    }

    private var selectedExerciseName: String {
        exerciseOptions.first { $0.id == selectedExerciseId }?.name ?? "Exercise"
    }

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                LoadingView()
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .task {
            await load()
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let overview, overview.weeklyStrengthIndex.count >= 2 {
                    overviewSection(overview)
                        .padding(.horizontal)
                }

                // PRs section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent PRs")
                        .font(.headline)

                    if dependencies.progressService.recentPRs.isEmpty {
                        Text("No personal records yet. Start lifting!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(dependencies.progressService.recentPRs.prefix(5)) { pr in
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(Color.liftPR)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.exerciseName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(prDescription(pr))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(pr.achievedAt.shortDate)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)

                chartsSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .refreshable {
            await load()
        }
    }

    // MARK: - Overview (all exercises)

    private func overviewSection(_ overview: ProgressOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            HStack(spacing: 12) {
                statTile(
                    label: "Strength",
                    value: overview.strengthChangePercent.map { "\($0 >= 0 ? "+" : "")\($0.formatted(decimals: 1))%" } ?? "—",
                    detail: baselineDetail(overview)
                )
                statTile(
                    label: "Days / week",
                    value: recentTrainingDaysPerWeek(overview).formatted(decimals: 1),
                    detail: "last 4 weeks"
                )
                statTile(
                    label: "Volume",
                    value: latestWeekVolumeLabel(overview),
                    detail: "this week"
                )
            }

            strengthIndexCard(overview)
            totalVolumeCard(overview)
        }
    }

    private func statTile(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Names the comparison point concretely ("since Jul") — the baseline is
    /// each lift's start inside the rolling 26-week window, which is the
    /// user's actual start only for histories shorter than the window.
    private func baselineDetail(_ overview: ProgressOverview) -> String {
        guard let first = overview.weeklyStrengthIndex.first else { return "vs. baseline" }
        return "since \(first.weekStart.formatted(.dateTime.month(.abbreviated)))"
    }

    private func recentTrainingDaysPerWeek(_ overview: ProgressOverview) -> Double {
        let recent = overview.weeklyTrainingDays.suffix(4)
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.value } / Double(recent.count)
    }

    private func latestWeekVolumeLabel(_ overview: ProgressOverview) -> String {
        guard let latest = overview.weeklyVolume.last else { return "—" }
        let display = UnitConversionService.convertWeight(latest.value, to: unitSystem)
        return "\(Int(display).formatted()) \(weightUnit)"
    }

    private func overviewTrendCaption(_ overview: ProgressOverview) -> String {
        guard let trend = overview.trend else {
            return "Each lift is measured against its own starting point, then averaged."
        }
        let pct = abs(trend.annualRate * 100)
        switch trend.verdict {
        case .insufficientData:
            return "Every lift vs. its own starting point, averaged. Trend verdicts unlock after ~8 weeks."
        case .unclear:
            return "Trend: too early to call — keep logging and check back."
        case .progressing:
            return "Overall strength trending up ≈ \(pct.formatted(decimals: 0))%/yr."
        case .declining:
            return "Overall strength trending down ≈ \(pct.formatted(decimals: 0))%/yr — check recovery, or try a lighter week."
        }
    }

    private func strengthIndexCard(_ overview: ProgressOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Strength")
                .font(.subheadline.weight(.semibold))
            Text(overviewTrendCaption(overview))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Chart(overview.weeklyStrengthIndex) { point in
                LineMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Change", (point.value - 1) * 100)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Change", (point.value - 1) * 100)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(50)

                RuleMark(y: .value("Baseline", 0))
                    .foregroundStyle(.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYAxisLabel("% vs. start")
            .frame(height: 180)
            .accessibilityLabel("Overall strength change across all exercises, percent versus your starting point")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func totalVolumeCard(_ overview: ProgressOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Weekly Volume")
                .font(.subheadline.weight(.semibold))

            Chart(overview.weeklyVolume) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Volume", UnitConversionService.convertWeight(point.value, to: unitSystem))
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
            }
            .chartYAxisLabel(weightUnit)
            .frame(height: 160)
            .accessibilityLabel("Total weekly training volume across all exercises")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Charts

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("By Exercise")
                    .font(.headline)

                Spacer()

                if !exerciseOptions.isEmpty {
                    exercisePicker
                }
            }

            if exerciseOptions.isEmpty {
                chartEmptyState("Complete more workouts to see trends")
            } else {
                estimated1RMCard
                weeklyVolumeCard
            }
        }
        .task(id: selectedExerciseId ?? exerciseOptions.first?.id) {
            await loadRecords()
        }
    }

    private var exercisePicker: some View {
        Menu {
            Picker("Exercise", selection: Binding(
                get: { selectedExerciseId ?? exerciseOptions.first?.id ?? "" },
                set: { selectedExerciseId = $0 }
            )) {
                ForEach(exerciseOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedExerciseName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityLabel("Select exercise for charts")
    }

    /// Records in chronological order (the repository returns newest-first).
    private var chronologicalRecords: [ProgressRecord] {
        progressRecords.sorted { $0.date < $1.date }
    }

    private struct WeeklyVolume: Identifiable {
        let weekStart: Date
        let volume: Double
        var id: Date { weekStart }
    }

    /// Total volume for the selected exercise, bucketed by calendar week and
    /// converted to the display unit.
    private var weeklyVolumes: [WeeklyVolume] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: progressRecords) { record in
            calendar.dateInterval(of: .weekOfYear, for: record.date)?.start ?? record.date
        }
        return grouped
            .map { weekStart, records in
                WeeklyVolume(
                    weekStart: weekStart,
                    volume: UnitConversionService.convertWeight(
                        records.reduce(0) { $0 + $1.totalVolume },
                        to: unitSystem
                    )
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    /// Recent-window trend of the charted e1RM series. Six months balances
    /// "recent enough to act on" against the statistical reality that shorter
    /// windows of formula e1RM are pure noise.
    private var strengthTrend: StrengthTrend? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -182, to: Date()) ?? .distantPast
        let recent = chronologicalRecords.filter { $0.date >= cutoff }
        return StrengthTrend.fit(dates: recent.map(\.date), e1RMs: recent.map(\.estimated1RM))
    }

    private func trendCaption(_ trend: StrengthTrend) -> String? {
        let pct = abs(trend.annualRate * 100)
        let weeks = trend.spanDays / 7
        switch trend.verdict {
        case .insufficientData:
            return nil
        case .unclear:
            return "Trend over \(weeks) wk: too early to call — e1RM readings vary ~10% set to set, "
                + "so real change takes months to show. Keep logging."
        case .progressing:
            return "Trending up ≈ \(pct.formatted(decimals: 0))%/yr over the last \(weeks) wk."
        case .declining:
            return "Trending down ≈ \(pct.formatted(decimals: 0))%/yr over the last \(weeks) wk — "
                + "check sleep, stress, and calories, or try one lighter week (−10%) and retest."
        }
    }

    private var estimated1RMCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated 1RM \u{2022} \(selectedExerciseName)")
                .font(.subheadline.weight(.semibold))

            if let trend = strengthTrend, let caption = trendCaption(trend) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if chronologicalRecords.count < 2 {
                chartEmptyState("Complete more workouts to see trends")
            } else {
                Chart(chronologicalRecords) { record in
                    LineMark(
                        x: .value("Date", record.date),
                        y: .value("Est. 1RM", UnitConversionService.convertWeight(record.estimated1RM, to: unitSystem))
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", record.date),
                        y: .value("Est. 1RM", UnitConversionService.convertWeight(record.estimated1RM, to: unitSystem))
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(50)
                }
                .chartYAxisLabel(weightUnit)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                .opacity(isLoadingRecords ? 0.5 : 1)
                .accessibilityLabel("Estimated one rep max over time for \(selectedExerciseName)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var weeklyVolumeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Volume \u{2022} \(selectedExerciseName)")
                .font(.subheadline.weight(.semibold))

            if weeklyVolumes.count < 2 {
                chartEmptyState("Complete more workouts to see trends")
            } else {
                Chart(weeklyVolumes) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Volume", week.volume)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(4)
                }
                .chartYAxisLabel(weightUnit)
                .frame(height: 200)
                .opacity(isLoadingRecords ? 0.5 : 1)
                .accessibilityLabel("Weekly training volume for \(selectedExerciseName)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    // MARK: - Data Loading

    private func prDescription(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .reps:
            return "\(pr.type.displayName): \(Int(pr.value))"
        case .weight, .estimated1RM, .volume:
            let value = UnitConversionService.convertWeight(pr.value, to: unitSystem)
            return "\(pr.type.displayName): \(value.formatted()) \(weightUnit)"
        }
    }

    private func load() async {
        guard let userId = dependencies.authService.currentUserId else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await dependencies.progressService.loadRecentPRs(userId: userId)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        // Overview is supplementary: a failed load never replaces the screen —
        // first load leaves the section hidden, a failed refresh keeps the
        // last successful overview. Session dates (not just weighted records)
        // feed training-day counts so bodyweight-only days aren't dropped.
        let cutoff = Calendar.current.date(byAdding: .day, value: -ProgressOverview.windowDays, to: Date()) ?? .distantPast
        let sessionDates = (try? await dependencies.workoutService.completedSessionDates(userId: userId, since: cutoff)) ?? []
        if let all = try? await dependencies.progressService.getAllProgressRecords(userId: userId, since: cutoff) {
            overview = ProgressOverview.compute(records: all, sessionDates: sessionDates)
        }
        isLoading = false
    }

    private func loadRecords() async {
        guard let userId = dependencies.authService.currentUserId,
              let exerciseId = selectedExerciseId ?? exerciseOptions.first?.id else { return }
        if selectedExerciseId == nil {
            selectedExerciseId = exerciseId
        }
        isLoadingRecords = true
        // Chart data is supplementary to the PR list; on failure the charts
        // simply show their empty state rather than replacing the screen.
        progressRecords = (try? await dependencies.progressService.getProgressRecords(
            userId: userId,
            exerciseId: exerciseId
        )) ?? []
        isLoadingRecords = false
    }
}
