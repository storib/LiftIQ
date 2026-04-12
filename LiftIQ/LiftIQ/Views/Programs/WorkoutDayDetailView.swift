import SwiftUI

struct WorkoutDayDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    let workout: WorkoutTemplate

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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise?.name ?? planned.exerciseId)
                                    .font(.subheadline.weight(.semibold))
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
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.name)
        .task {
            try? await dependencies.exerciseService.loadExercises()
        }
    }
}
