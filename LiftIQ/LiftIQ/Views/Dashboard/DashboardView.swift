import SwiftUI

struct DashboardView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = DashboardViewModel()
    @State private var workoutExecutionVM: WorkoutExecutionViewModel?

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

                // Today's Workout Card
                if let workout = viewModel.todayWorkout {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Workout")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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
                                        planId: dependencies.workoutService.activePlan?.id
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
                            workoutExecutionVM = WorkoutExecutionViewModel(existingSession: activeSession)
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
                        Text("Recent Activity")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(dependencies.workoutService.recentSessions.prefix(5)) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.workoutName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(session.startedAt.relativeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(Formatters.durationString(from: session.durationSeconds))
                                        .font(.subheadline)
                                    Text("\(Int(UnitConversionService.convertWeight(session.totalVolumeKg, to: unitSystem))) \(UnitConversionService.weightLabel(for: unitSystem))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            if let userId = dependencies.authService.currentUserId {
                await viewModel.load(workoutService: dependencies.workoutService, userId: userId)
            }
        }
        .fullScreenCover(item: $workoutExecutionVM) { vm in
            WorkoutExecutionView(viewModel: vm)
                .environment(dependencies)
        }
        .task {
            if let userId = dependencies.authService.currentUserId {
                await viewModel.load(workoutService: dependencies.workoutService, userId: userId)
            }
        }
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
