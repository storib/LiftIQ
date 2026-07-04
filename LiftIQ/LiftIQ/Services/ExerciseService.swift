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

        // The 136-doc global catalog rarely changes, so serve Firestore's
        // local cache first and only hit the server when the cache is empty.
        if let cached = try? await repository.getCachedExercises(), !cached.isEmpty {
            exercises = cached
            isLoaded = true
            // Refresh in the background so catalog updates still propagate
            // within this session.
            Task { [weak self] in
                guard let self,
                      let fresh = try? await self.repository.getAllExercises(),
                      !fresh.isEmpty else { return }
                self.exercises = fresh
            }
            return
        }

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
}
