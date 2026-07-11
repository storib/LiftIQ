import SwiftUI

struct DashboardView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = DashboardViewModel()
    @State private var workoutExecutionVM: WorkoutExecutionViewModel?
    @State private var sessionPendingDeletion: WorkoutSession?
    @State private var healthError: String?

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Greeting
                if let user = dependencies.authService.currentUser {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hey, \(user.displayName)!")
                                .font(.title2.bold())
                            Text(Date().relativeDescription)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.streak > 0 {
                            Label("\(viewModel.streak)", systemImage: "flame.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal)
                }

                weekOverview

                // Next recommended workout — advances as plan days complete
                if let workout = viewModel.todayWorkout {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Up Next")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let plan = dependencies.workoutService.activePlan, plan.workouts.count > 1 {
                                Menu {
                                    ForEach(plan.workouts) { template in
                                        Button {
                                            viewModel.todayWorkout = template
                                        } label: {
                                            if template.id == workout.id {
                                                Label("Day \(template.dayNumber) · \(template.name)", systemImage: "checkmark")
                                            } else {
                                                Text("Day \(template.dayNumber) · \(template.name)")
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Change", systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption.weight(.medium))
                                }
                                .accessibilityLabel("Choose a different workout")
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(workout.name)
                                .font(.title3.bold())

                            HStack(spacing: 16) {
                                Label("\(workout.exerciseGroups.flatMap(\.exercises).count) exercises", systemImage: "dumbbell.fill")
                                Label("~\(workout.estimatedDurationMinutes) min", systemImage: "clock")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack {
                                ForEach(workout.targetMuscleGroups, id: \.self) { group in
                                    Text(group.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }

                            Button {
                                if let userId = dependencies.authService.currentUserId {
                                    workoutExecutionVM = WorkoutExecutionViewModel(
                                        template: workout,
                                        userId: userId,
                                        planId: dependencies.workoutService.activePlan?.id,
                                        workoutService: dependencies.workoutService,
                                        exerciseService: dependencies.exerciseService,
                                        progressService: dependencies.progressService,
                                        progressionService: dependencies.progressionService
                                    )
                                }
                            } label: {
                                Text("Start Workout")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                } else if dependencies.workoutService.activePlan == nil && !viewModel.isLoading {
                    // No active plan
                    VStack(spacing: 12) {
                        EmptyStateView(
                            icon: "plus.circle",
                            title: "No active program",
                            message: "Create a workout plan to get started"
                        )
                        NavigationLink("Browse Programs") {
                            TemplateBrowserView()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }

                // Active session recovery
                if let activeSession = dependencies.workoutService.activeSession,
                   workoutExecutionVM == nil {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.liftWarning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Workout in Progress")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(activeSession.workoutName) \u{2022} \(Formatters.durationString(from: Int(Date().timeIntervalSince(activeSession.startedAt))))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Button {
                            workoutExecutionVM = WorkoutExecutionViewModel(
                                existingSession: activeSession,
                                workoutService: dependencies.workoutService,
                                exerciseService: dependencies.exerciseService,
                                progressService: dependencies.progressService,
                                progressionService: dependencies.progressionService
                            )
                        } label: {
                            Text("Resume Workout")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.liftWarning)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .background(Color.liftWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }

                // Quick Stats
                HStack(spacing: 12) {
                    StatCardView(
                        title: "This Week",
                        value: "\(viewModel.weeklySessionCount)",
                        subtitle: "workouts",
                        icon: "figure.strengthtraining.traditional"
                    )
                    let weeklyVolume = UnitConversionService.convertWeight(viewModel.weeklyVolume, to: unitSystem)
                    StatCardView(
                        title: "Volume",
                        value: weeklyVolume > 0 ? "\(Int(weeklyVolume / 1000))k" : "0",
                        subtitle: "\(UnitConversionService.weightLabel(for: unitSystem)) lifted",
                        icon: "scalemass.fill"
                    )
                }
                .padding(.horizontal)

                // Recent Activity
                if !dependencies.workoutService.recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Activity")
                                .font(.headline)
                            Spacer()
                            NavigationLink {
                                WorkoutHistoryView()
                            } label: {
                                Text("See All")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal)

                        ForEach(dependencies.workoutService.recentSessions.prefix(5)) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRowContent(session: session, unitSystem: unitSystem)
                                    .padding()
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Workout", role: .destructive) {
                                    sessionPendingDeletion = session
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .refreshable {
            await reloadDashboard()
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                if let session = sessionPendingDeletion, let userId = dependencies.authService.currentUserId {
                    Task {
                        try? await dependencies.workoutService.deleteSession(session)
                        await viewModel.load(
                            workoutService: dependencies.workoutService,
                            healthKitService: dependencies.healthKitService,
                            userId: userId
                        )
                    }
                }
                sessionPendingDeletion = nil
            }
        } message: {
            Text("This removes the workout and any records it set. This can't be undone.")
        }
        .alert("Apple Health", isPresented: Binding(
            get: { healthError != nil },
            set: { if !$0 { healthError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthError ?? "")
        }
        .fullScreenCover(item: $workoutExecutionVM) { vm in
            WorkoutExecutionView(viewModel: vm)
                .environment(dependencies)
        }
        .task {
            await reloadDashboard()
        }
    }

    private var weekOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    Image(systemName: "calendar")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Open workout history")
            }

            HStack(spacing: 4) {
                ForEach(viewModel.weekDays, id: \.self) { day in
                    weekDayButton(day)
                }
            }

            selectedDaySummary
        }
        .padding(.horizontal)
    }

    private func weekDayButton(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: viewModel.selectedDate)
        let hasSession = viewModel.hasSession(on: day, in: dependencies.workoutService.recentSessions)
        let hasExternalActivity = viewModel.hasExternalActivity(on: day)

        return Button {
            viewModel.selectedDate = day
        } label: {
            VStack(spacing: 5) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption2.weight(.semibold))
                Text(day, format: .dateTime.day())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 5, height: 5)
                        .opacity(hasSession ? 1 : 0)
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.75) : Color.liftSuccess)
                        .frame(width: 5, height: 5)
                        .opacity(hasExternalActivity ? 1 : 0)
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if day.isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue([hasSession ? "LiftIQ workout" : nil, hasExternalActivity ? "Health activity" : nil]
            .compactMap { $0 }
            .joined(separator: ", "))
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        let sessions = viewModel.sessions(
            on: viewModel.selectedDate,
            from: dependencies.workoutService.recentSessions
        )
        let activities = viewModel.activities(on: viewModel.selectedDate)

        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline.weight(.semibold))

            if sessions.isEmpty && activities.isEmpty {
                Text(viewModel.selectedDate > Date() ? "Nothing here yet" : "No activity recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        DayWorkoutRow(session: session, unitSystem: unitSystem)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(activities) { activity in
                    ExternalActivityRow(activity: activity, unitSystem: unitSystem)
                }
            }

            if dependencies.healthKitService.isAvailable,
               !dependencies.healthKitService.isActivityImportEnabled {
                Button {
                    Task { await connectAppleHealth() }
                } label: {
                    Label("Show Apple Health Activity", systemImage: "heart.text.square")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 2)
    }

    private func reloadDashboard() async {
        guard let userId = dependencies.authService.currentUserId else { return }
        await viewModel.load(
            workoutService: dependencies.workoutService,
            healthKitService: dependencies.healthKitService,
            userId: userId
        )
    }

    private func connectAppleHealth() async {
        do {
            try await dependencies.healthKitService.enableActivityImport()
            await reloadDashboard()
        } catch {
            healthError = error.localizedDescription
        }
    }
}

private struct DayWorkoutRow: View {
    let session: WorkoutSession
    let unitSystem: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.workoutName)
                    .font(.subheadline.weight(.semibold))
                Text("LiftIQ · \(Formatters.durationString(from: session.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(UnitConversionService.convertWeight(session.totalVolumeKg, to: unitSystem))) \(UnitConversionService.weightLabel(for: unitSystem))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct ExternalActivityRow: View {
    let activity: ExternalActivity
    let unitSystem: UnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.kind.systemImage)
                .foregroundStyle(Color.liftSuccess)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(activity.startedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        var parts = [activity.sourceName, Formatters.durationString(from: activity.durationSeconds)]
        if let meters = activity.distanceMeters, meters > 0 {
            if unitSystem == .imperial {
                parts.append(String(format: "%.1f mi", meters / 1_609.344))
            } else {
                parts.append(String(format: "%.1f km", meters / 1_000))
            }
        }
        if let calories = activity.activeEnergyKilocalories, calories > 0 {
            parts.append("\(Int(calories)) cal")
        }
        return parts.joined(separator: " · ")
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
