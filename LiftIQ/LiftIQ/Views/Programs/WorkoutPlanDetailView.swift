import SwiftUI

struct WorkoutPlanDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    // Local copy so an applied AI modification refreshes this screen in place.
    @State private var plan: WorkoutPlan
    @State private var showingAIModify = false

    init(plan: WorkoutPlan) {
        _plan = State(initialValue: plan)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Template", value: plan.templateType.displayName)
                LabeledContent("Goal", value: plan.goal.displayName)
                LabeledContent("Duration", value: "\(plan.weekCount) weeks")
                LabeledContent("Current Week", value: "\(plan.currentWeek)")
                if let deload = plan.deloadWeek {
                    LabeledContent("Deload Week", value: "\(deload)")
                }
            } header: {
                Text("Plan Details")
            }

            Section {
                ForEach(plan.workouts) { workout in
                    NavigationLink {
                        WorkoutDayDetailView(workout: workout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Day \(workout.dayNumber): \(workout.name)")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                let exerciseCount = workout.exerciseGroups.flatMap(\.exercises).count
                                Text("\(exerciseCount) exercises")
                                Text("\u{2022}")
                                Text("~\(workout.estimatedDurationMinutes) min")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                ForEach(workout.targetMuscleGroups, id: \.self) { group in
                                    Text(group.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Workouts")
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAIModify = true
                } label: {
                    Label("Modify with AI", systemImage: "wand.and.stars")
                }
                .accessibilityLabel("Modify plan with AI")
            }
        }
        .sheet(isPresented: $showingAIModify) {
            AIModifySheet(
                plan: plan,
                workout: nil,
                onApplyPlan: { updated in plan = updated }
            )
            .environment(dependencies)
        }
    }
}
