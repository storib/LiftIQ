import SwiftUI

struct WorkoutDayDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var workoutExecutionVM: WorkoutExecutionViewModel?
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
            ForEach(workout.exerciseGroups) { group in
                Section {
                    if group.groupType != .straight {
                        Label(group.groupType.displayName, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    ForEach(group.exercises) { planned in
                        let exercise = dependencies.exerciseService.getExercise(id: planned.exerciseId)
                        Button {
                            startWorkout(at: flatIndexByPlannedId[planned.id] ?? 0)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise?.name ?? planned.exerciseId)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(planned.sets) sets x \(planned.repsMin)-\(planned.repsMax) reps")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if planned.restSeconds > 0 {
                                        Text("Rest: \(planned.restSeconds)s")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if exercise?.isCompound == true {
                                    Text("Compound")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .task {
            try? await dependencies.exerciseService.loadExercises()
        }
        .fullScreenCover(item: $workoutExecutionVM) { vm in
            WorkoutExecutionView(viewModel: vm)
                .environment(dependencies)
        }
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
