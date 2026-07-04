import SwiftUI

struct WorkoutExecutionView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: WorkoutExecutionViewModel

    @FocusState private var focusedSetField: SetFieldFocus?

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
        // Attached once at screen level; attaching inside LazyVStack rows
        // would duplicate the toolbar per materialized row.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    if let target = previousFocusTarget {
                        focusedSetField = target
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(previousFocusTarget == nil)
                .accessibilityLabel("Previous field")

                Button {
                    if let target = nextFocusTarget {
                        focusedSetField = target
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(nextFocusTarget == nil)
                .accessibilityLabel("Next field")

                Spacer()

                Button("Done") {
                    focusedSetField = nil
                }
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
        .alert("Couldn't Save", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
        .onChange(of: scenePhase) { _, phase in
            // Timers suspend in the background; re-derive from the wall clock
            // the moment the app is foregrounded again.
            if phase == .active {
                viewModel.refreshTimersFromWallClock()
            }
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
                .accessibilityLabel("Workout options")

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
                                : nil,
                            focusedField: $focusedSetField
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

    // MARK: - Keyboard Focus Navigation

    private var previousFocusTarget: SetFieldFocus? {
        focusedSetField.flatMap {
            SetFieldFocus.previous(before: $0, in: viewModel.session.exerciseLogs)
        }
    }

    private var nextFocusTarget: SetFieldFocus? {
        focusedSetField.flatMap {
            SetFieldFocus.next(after: $0, in: viewModel.session.exerciseLogs)
        }
    }
}

// MARK: - Set Field Focus

/// Identifies a single input field within the workout's set rows so a single
/// `@FocusState` at the screen level can drive the keyboard focus chain.
struct SetFieldFocus: Hashable {
    enum Field: Hashable {
        case weight, reps, rpe
    }

    let exerciseLogIndex: Int
    let setIndex: Int
    let field: Field

    // Navigation is kept as pure helpers over the session's exercise logs so
    // the chain can be exercised in tests without a view hierarchy.

    /// Next field in the chain: weight → reps → rpe (working sets only) →
    /// next set's weight, then the next exercise's first set. `nil` at the end.
    static func next(after current: SetFieldFocus, in exerciseLogs: [ExerciseLog]) -> SetFieldFocus? {
        guard exerciseLogs.indices.contains(current.exerciseLogIndex),
              exerciseLogs[current.exerciseLogIndex].sets.indices.contains(current.setIndex) else { return nil }

        let set = exerciseLogs[current.exerciseLogIndex].sets[current.setIndex]
        switch current.field {
        case .weight:
            return SetFieldFocus(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex, field: .reps)
        case .reps where set.setType == .working:
            // Non-working sets don't render an RPE field, so skip it.
            return SetFieldFocus(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex, field: .rpe)
        case .reps, .rpe:
            return firstField(after: current, in: exerciseLogs)
        }
    }

    /// Mirror of `next(after:in:)`. `nil` at the very first field.
    static func previous(before current: SetFieldFocus, in exerciseLogs: [ExerciseLog]) -> SetFieldFocus? {
        guard exerciseLogs.indices.contains(current.exerciseLogIndex),
              exerciseLogs[current.exerciseLogIndex].sets.indices.contains(current.setIndex) else { return nil }

        switch current.field {
        case .rpe:
            return SetFieldFocus(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex, field: .reps)
        case .reps:
            return SetFieldFocus(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex, field: .weight)
        case .weight:
            return lastField(before: current, in: exerciseLogs)
        }
    }

    /// First field of the following set, rolling over to the next exercise
    /// that has sets.
    private static func firstField(after current: SetFieldFocus, in exerciseLogs: [ExerciseLog]) -> SetFieldFocus? {
        if current.setIndex + 1 < exerciseLogs[current.exerciseLogIndex].sets.count {
            return SetFieldFocus(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex + 1, field: .weight)
        }
        for logIndex in (current.exerciseLogIndex + 1)..<exerciseLogs.count where !exerciseLogs[logIndex].sets.isEmpty {
            return SetFieldFocus(exerciseLogIndex: logIndex, setIndex: 0, field: .weight)
        }
        return nil
    }

    /// Last field of the preceding set, rolling back to the previous exercise
    /// that has sets.
    private static func lastField(before current: SetFieldFocus, in exerciseLogs: [ExerciseLog]) -> SetFieldFocus? {
        if current.setIndex > 0 {
            return lastField(exerciseLogIndex: current.exerciseLogIndex, setIndex: current.setIndex - 1, in: exerciseLogs)
        }
        for logIndex in stride(from: current.exerciseLogIndex - 1, through: 0, by: -1) where !exerciseLogs[logIndex].sets.isEmpty {
            return lastField(exerciseLogIndex: logIndex, setIndex: exerciseLogs[logIndex].sets.count - 1, in: exerciseLogs)
        }
        return nil
    }

    private static func lastField(exerciseLogIndex: Int, setIndex: Int, in exerciseLogs: [ExerciseLog]) -> SetFieldFocus {
        let setType = exerciseLogs[exerciseLogIndex].sets[setIndex].setType
        return SetFieldFocus(
            exerciseLogIndex: exerciseLogIndex,
            setIndex: setIndex,
            field: setType == .working ? .rpe : .reps
        )
    }
}
