import SwiftUI

struct WorkoutExecutionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: WorkoutExecutionViewModel

    private static let supersetColors: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo]

    var body: some View {
        ZStack {
            Color.liftBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom toolbar
                toolbar

                // Progress bar
                ProgressView(value: viewModel.progressFraction)
                    .tint(Color.accentColor)
                    .padding(.horizontal)

                // Unit toggle
                Picker("Unit", selection: $viewModel.unitSystem) {
                    Text("kg").tag(UnitSystem.metric)
                    Text("lb").tag(UnitSystem.imperial)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .padding(.vertical, 8)

                // Exercise list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            exerciseList
                        }
                        .padding(.horizontal)
                        .padding(.bottom, viewModel.restTimerActive ? 280 : 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.isLoading) { _, isLoading in
                        guard !isLoading,
                              let target = viewModel.scrollToExerciseLogIndex else { return }
                        Task { @MainActor in
                            withAnimation {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            // Retry after layout settles; deep LazyVStack targets can
                            // undershoot on the first pass while cells materialize.
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            withAnimation {
                                proxy.scrollTo(target, anchor: .top)
                            }
                            viewModel.scrollToExerciseLogIndex = nil
                        }
                    }
                }
            }

            // Rest timer overlay
            if viewModel.restTimerActive {
                VStack {
                    Spacer()
                    RestTimerView(
                        secondsRemaining: viewModel.restSecondsRemaining,
                        totalSeconds: viewModel.restTotalSeconds,
                        onSkip: { viewModel.skipRestTimer() },
                        onAdjust: { viewModel.adjustRestTimer(by: $0) }
                    )
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom))
                .animation(.spring(response: 0.4), value: viewModel.restTimerActive)
            }

            // PR celebration overlay
            if let pr = viewModel.newPR {
                PRCelebrationOverlay(
                    personalRecord: pr,
                    unitSystem: viewModel.unitSystem,
                    onDismiss: { viewModel.newPR = nil }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.newPR != nil)
            }
        }
        .sheet(isPresented: $viewModel.showingExerciseSwap) {
            if let swapIndex = viewModel.swapTargetExerciseLogIndex {
                let currentExercise = viewModel.exerciseDetails[viewModel.session.exerciseLogs[swapIndex].exerciseId]
                ExerciseSwapSheet(currentExercise: currentExercise) { newExercise in
                    Task {
                        await viewModel.swapExercise(
                            newExercise: newExercise,
                            workoutService: dependencies.workoutService,
                            userId: viewModel.session.userId
                        )
                    }
                }
            }
        }
        .alert("Abandon Workout?", isPresented: $viewModel.showingAbandonConfirmation) {
            Button("Abandon", role: .destructive) {
                Task {
                    await viewModel.abandonWorkout(workoutService: dependencies.workoutService)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress for this session will be lost.")
        }
        .fullScreenCover(isPresented: $viewModel.showingSummary) {
            WorkoutSummaryView(
                session: viewModel.session,
                sessionPRs: viewModel.sessionPRs,
                unitSystem: viewModel.unitSystem,
                onSaveMoodAndNotes: { mood, notes in
                    Task {
                        await viewModel.saveMoodAndNotes(
                            mood: mood,
                            notes: notes,
                            workoutService: dependencies.workoutService
                        )
                    }
                },
                onDismiss: { dismiss() }
            )
        }
        .task {
            guard let userId = dependencies.authService.currentUserId else { return }
            let profile = dependencies.authService.currentUser?.profile
            let userUnit = profile?.unitSystem ?? .metric
            let userDefaultRest = profile?.effectiveDefaultRestSeconds ?? 60
            await viewModel.start(
                workoutService: dependencies.workoutService,
                exerciseService: dependencies.exerciseService,
                progressService: dependencies.progressService,
                userId: userId,
                userUnitSystem: userUnit,
                userDefaultRestSeconds: userDefaultRest
            )
        }
        .onDisappear {
            viewModel.stopTimers()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Elapsed time
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(viewModel.elapsedFormatted)
                    .font(.subheadline.monospacedDigit())
            }
            .foregroundStyle(.secondary)

            Spacer()

            // Workout name
            Text(viewModel.session.workoutName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Finish + menu
            HStack(spacing: 12) {
                Menu {
                    Button(role: .destructive) {
                        viewModel.showingAbandonConfirmation = true
                    } label: {
                        Label("Abandon Workout", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await viewModel.finishWorkout(workoutService: dependencies.workoutService)
                    }
                } label: {
                    Text("Finish")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.liftCardBackground)
    }

    // MARK: - Exercise List

    @ViewBuilder
    private var exerciseList: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding(.top, 40)
        } else {
            // Group exercises by their group index for rendering
            let grouped = groupedExerciseLogs()
            ForEach(grouped, id: \.groupIndex) { group in
                VStack(spacing: 8) {
                    // Group header for non-straight groups
                    if group.groupType != .straight {
                        HStack {
                            Label(group.groupType.displayName, systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(supersetColor(for: group.groupIndex))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }

                    // Exercise cards
                    ForEach(group.exerciseLogIndices, id: \.self) { logIndex in
                        ExerciseCardView(
                            viewModel: viewModel,
                            exerciseLogIndex: logIndex,
                            groupColor: group.groupType != .straight
                                ? supersetColor(for: group.groupIndex)
                                : nil
                        )
                        .id(logIndex)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private struct ExerciseGroupInfo: Identifiable {
        let groupIndex: Int
        let groupType: GroupType
        let exerciseLogIndices: [Int]
        var id: Int { groupIndex }
    }

    private func groupedExerciseLogs() -> [ExerciseGroupInfo] {
        var groups: [ExerciseGroupInfo] = []
        var seen = Set<Int>()

        for logIndex in viewModel.session.exerciseLogs.indices {
            let gi = viewModel.groupIndex(for: logIndex) ?? logIndex + 1000
            if seen.contains(gi) { continue }
            seen.insert(gi)

            let indices = viewModel.exerciseLogIndices(forGroupIndex: gi)
            let gt = viewModel.groupType(for: logIndex)

            // For recovered sessions without group data, treat as straight
            if indices.isEmpty {
                groups.append(ExerciseGroupInfo(
                    groupIndex: gi,
                    groupType: .straight,
                    exerciseLogIndices: [logIndex]
                ))
            } else {
                groups.append(ExerciseGroupInfo(
                    groupIndex: gi,
                    groupType: gt,
                    exerciseLogIndices: indices
                ))
            }
        }
        return groups
    }

    private func supersetColor(for groupIndex: Int) -> Color {
        Self.supersetColors[groupIndex % Self.supersetColors.count]
    }
}
