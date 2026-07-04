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

    // MARK: - Charts

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Strength Trends")
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

    private var estimated1RMCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated 1RM \u{2022} \(selectedExerciseName)")
                .font(.subheadline.weight(.semibold))

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
