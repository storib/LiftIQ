import SwiftUI

struct ExerciseSearchView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var searchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    let onSelect: (Exercise) -> Void

    private var filteredExercises: [Exercise] {
        var results = dependencies.exerciseService.exercises

        if let group = selectedMuscleGroup {
            results = results.filter {
                $0.primaryMuscleGroup == group || $0.secondaryMuscleGroups.contains(group)
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(query) ||
                $0.tags.contains { $0.lowercased().contains(query) }
            }
        }

        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            // Muscle group filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedMuscleGroup == nil) {
                        selectedMuscleGroup = nil
                    }
                    ForEach(MuscleGroup.allCases) { group in
                        FilterChip(title: group.displayName, isSelected: selectedMuscleGroup == group) {
                            selectedMuscleGroup = selectedMuscleGroup == group ? nil : group
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            List(filteredExercises) { exercise in
                Button {
                    onSelect(exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            Text(exercise.primaryMuscleGroup.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if exercise.isCompound {
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
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Exercises")
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
