import Foundation

@MainActor
@Observable
final class ExerciseService {
    private let repository: ExerciseRepository
    var exercises: [Exercise] = []
    var isLoaded = false

    init(repository: ExerciseRepository) {
        self.repository = repository
    }

    func loadExercises() async throws {
        guard !isLoaded else { return }
        exercises = try await repository.getAllExercises()
        isLoaded = true
    }

    func getExercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func searchExercises(query: String) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        let lowered = query.lowercased()
        return exercises.filter { exercise in
            exercise.name.lowercased().contains(lowered) ||
            exercise.primaryMuscleGroup.displayName.lowercased().contains(lowered) ||
            exercise.tags.contains { $0.lowercased().contains(lowered) }
        }
    }

    func getExercises(forMuscleGroup group: MuscleGroup) -> [Exercise] {
        exercises.filter { $0.primaryMuscleGroup == group || $0.secondaryMuscleGroups.contains(group) }
    }

    func getExercises(forEquipment equipment: Set<Equipment>) -> [Exercise] {
        exercises.filter { exercise in
            exercise.equipment.allSatisfy { equipment.contains($0) }
        }
    }

    func getAlternatives(for exercise: Exercise, availableEquipment: Set<Equipment>) -> [Exercise] {
        exercises.filter { alt in
            alt.id != exercise.id &&
            alt.primaryMuscleGroup == exercise.primaryMuscleGroup &&
            alt.equipment.allSatisfy { availableEquipment.contains($0) }
        }
    }
}
