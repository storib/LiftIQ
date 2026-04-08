import Foundation

struct ProgressionSuggestion {
    let exerciseId: String
    let suggestedWeight: Double
    let suggestedRepsMin: Int
    let suggestedRepsMax: Int
    let message: String
    let isPlateaued: Bool
}

final class ProgressionService {
    func suggest(
        for exercise: PlannedExercise,
        previousLogs: [ExerciseLog],
        exerciseInfo: Exercise?
    ) -> ProgressionSuggestion? {
        guard let lastLog = previousLogs.first else { return nil }
        let workingSets = lastLog.sets.filter { $0.setType == .working }
        guard !workingSets.isEmpty else { return nil }

        let allHitMax = workingSets.allSatisfy { $0.reps >= exercise.repsMax }
        let anyFailedMin = workingSets.contains { $0.reps < exercise.repsMin }
        let lastWeight = workingSets.first?.weightKg ?? 0

        let increment = weightIncrement(for: exerciseInfo)

        if allHitMax {
            let newWeight = lastWeight + increment
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: newWeight,
                suggestedRepsMin: exercise.repsMin,
                suggestedRepsMax: exercise.repsMax,
                message: "Increase to \(newWeight.formatted())kg",
                isPlateaued: false
            )
        }

        let consecutiveFailures = countConsecutiveFailures(logs: previousLogs, repsMin: exercise.repsMin)

        if anyFailedMin && consecutiveFailures >= Constants.plateauThreshold {
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: lastWeight,
                suggestedRepsMin: exercise.repsMin,
                suggestedRepsMax: exercise.repsMax,
                message: "Plateau detected — consider swapping this exercise",
                isPlateaued: true
            )
        }

        return ProgressionSuggestion(
            exerciseId: exercise.exerciseId,
            suggestedWeight: lastWeight,
            suggestedRepsMin: exercise.repsMin,
            suggestedRepsMax: exercise.repsMax,
            message: "Aim for \(exercise.repsMax) reps on all sets",
            isPlateaued: false
        )
    }

    private func weightIncrement(for exercise: Exercise?) -> Double {
        guard let exercise else { return Constants.barbellIncrement }
        if exercise.equipment.contains(.barbell) { return Constants.barbellIncrement }
        if exercise.equipment.contains(.dumbbell) { return Constants.dumbbellIncrement }
        return Constants.machineIncrement
    }

    private func countConsecutiveFailures(logs: [ExerciseLog], repsMin: Int) -> Int {
        var count = 0
        for log in logs {
            let workingSets = log.sets.filter { $0.setType == .working }
            let failed = workingSets.contains { $0.reps < repsMin }
            if failed { count += 1 } else { break }
        }
        return count
    }
}
