import SwiftUI

struct WorkoutDayDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var workoutExecutionVM: WorkoutExecutionViewModel?
    @State private var selectedExercise: Exercise?
    let workout: WorkoutTemplate

    private var flatIndexByPlannedId: [String: Int] {
        var map: [String: Int] = [:]
        var i = 0
        for group in workout.exerciseGroups {
            for planned in group.exercises {
                map[planned.id] = i
                i += 1
            }
        }
        return map
    }

    var body: some View {
        List {
            Section {
                workoutOverview
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .listRowBackground(Color.clear)

            ForEach(workout.exerciseGroups) { group in
                Section {
                    if group.groupType != .straight {
                        Label(group.groupType.displayName, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    ForEach(group.exercises) { planned in
                        let exercise = dependencies.exerciseService.getExercise(id: planned.exerciseId)
                        HStack(spacing: 12) {
                            Button {
                                startWorkout(at: flatIndexByPlannedId[planned.id] ?? 0)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise?.name ?? planned.exerciseId)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text("\(planned.sets) sets x \(planned.repsMin)-\(planned.repsMax) reps")
                                        if planned.restSeconds > 0 {
                                            Text("\u{2022}")
                                            Text("\(planned.restSeconds)s rest")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                    if let exercise {
                                        Text(exercise.instructions)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .padding(.top, 2)
                                    }

                                    if planned.restSeconds > 0 {
                                        HStack(spacing: 6) {
                                            if let exercise {
                                                Text(exercise.primaryMuscleGroup.displayName)
                                                    .workoutChip(tint: Color.accentColor)
                                                Text(exercise.movementPattern.displayName)
                                                    .workoutChip(tint: .teal)
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if let exercise {
                                Button {
                                    selectedExercise = exercise
                                } label: {
                                    Image(systemName: exercise.youtubeVideoId.isEmpty ? "info.circle" : "play.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show exercise guidance")
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .task {
            try? await dependencies.exerciseService.loadExercises()
        }
        .sheet(item: $selectedExercise) { exercise in
            NavigationStack {
                ScrollView {
                    ExerciseGuidanceView(exercise: exercise)
                        .padding()
                }
                .background(Color.liftBackground)
                .navigationTitle("Exercise Guide")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            selectedExercise = nil
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $workoutExecutionVM) { vm in
            WorkoutExecutionView(viewModel: vm)
                .environment(dependencies)
        }
    }

    private var workoutOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.heart.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(workoutDescription)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let notes = workout.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                overviewMetric(
                    value: "\(exerciseCount)",
                    label: "Exercises",
                    systemImage: "dumbbell.fill",
                    tint: .blue
                )
                overviewMetric(
                    value: "~\(workout.estimatedDurationMinutes)",
                    label: "Minutes",
                    systemImage: "clock.fill",
                    tint: .orange
                )
                overviewMetric(
                    value: "\(compoundExerciseCount)",
                    label: "Compound",
                    systemImage: "square.stack.3d.up.fill",
                    tint: .teal
                )
            }
        }
        .padding(16)
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func overviewMetric(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exerciseCount: Int {
        workout.exerciseGroups.flatMap(\.exercises).count
    }

    private var compoundExerciseCount: Int {
        workout.exerciseGroups
            .flatMap(\.exercises)
            .compactMap { dependencies.exerciseService.getExercise(id: $0.exerciseId) }
            .filter(\.isCompound)
            .count
    }

    private var workoutDescription: String {
        let targets = workout.targetMuscleGroups.map(\.displayName).joined(separator: ", ")
        let groupCount = workout.exerciseGroups.filter { $0.groupType != .straight }.count
        let groupText = groupCount > 0 ? " Includes \(groupCount) paired block\(groupCount == 1 ? "" : "s") to keep the pace up." : ""
        return "A \(workout.estimatedDurationMinutes)-minute \(targets.lowercased()) session built around \(exerciseCount) planned exercises.\(groupText)"
    }

    private func startWorkout(at logIndex: Int) {
        guard let userId = dependencies.authService.currentUserId else { return }
        let vm = WorkoutExecutionViewModel(
            template: workout,
            userId: userId,
            planId: workout.planId
        )
        vm.scrollToExerciseLogIndex = logIndex
        workoutExecutionVM = vm
    }
}

private extension Text {
    func workoutChip(tint: Color) -> some View {
        font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
