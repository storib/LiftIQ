import Foundation

struct ProgressionSuggestion {
    let exerciseId: String
    let suggestedWeight: Double
    let suggestedRepsMin: Int
    let suggestedRepsMax: Int
    let message: String
    /// Three consecutive sessions below the rep floor at the same top weight.
    /// An acute load-management signal ("back off ~10% and rebuild"), not a
    /// long-term plateau claim — per-session data is far too noisy for that
    /// (see StrengthTrend for the honest long-window version).
    let isStalled: Bool
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

        let increment = weightIncrement(for: exerciseInfo)

        // Anchor to the heaviest working set of the last session. Anchoring to
        // the first set undershoots badly for lifters who ramp across sets.
        let topWeight = workingSets.map(\.weightKg).max() ?? 0
        let setsAtTop = workingSets.filter { $0.weightKg >= topWeight - 0.001 }
        let allHitMax = setsAtTop.allSatisfy { $0.reps >= exercise.repsMax }

        // A deload or an off week shouldn't drag the suggestion below what the
        // lifter recently handled: floor it at the best recent top-set weight
        // where the rep floor was met.
        let bestRecentTop = previousLogs
            .compactMap { provenTopWeight(in: $0, repsMin: exercise.repsMin) }
            .max() ?? 0

        if allHitMax {
            let newWeight = max(topWeight + increment, bestRecentTop)
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: newWeight,
                suggestedRepsMin: exercise.repsMin,
                suggestedRepsMax: exercise.repsMax,
                message: "Increase to \(newWeight.formatted())kg",
                isStalled: false
            )
        }

        // Stall: the rep floor was missed at this same top weight for N
        // consecutive sessions. Requiring the same weight matters — after a
        // weight increase the lifter legitimately rebuilds reps from below
        // the ceiling, and that must not read as a stall.
        let missedFloorAtTop = setsAtTop.contains { $0.reps < exercise.repsMin }
        if missedFloorAtTop,
           consecutiveFloorMisses(logs: previousLogs, repsMin: exercise.repsMin, atWeight: topWeight)
               >= Constants.stallThreshold {
            let backoff = backoffWeight(from: topWeight, increment: increment)
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: backoff,
                suggestedRepsMin: exercise.repsMin,
                suggestedRepsMax: exercise.repsMax,
                message: "Stuck at \(topWeight.formatted())kg — drop to \(backoff.formatted())kg and build back up",
                isStalled: true
            )
        }

        let holdWeight = max(topWeight, bestRecentTop)
        return ProgressionSuggestion(
            exerciseId: exercise.exerciseId,
            suggestedWeight: holdWeight,
            suggestedRepsMin: exercise.repsMin,
            suggestedRepsMax: exercise.repsMax,
            message: "Aim for \(exercise.repsMax) reps on all sets",
            isStalled: false
        )
    }

    /// The session's top working weight, but only when at least one set at
    /// that weight met the rep floor — an aborted or failed attempt isn't
    /// proof the weight is owned.
    private func provenTopWeight(in log: ExerciseLog, repsMin: Int) -> Double? {
        let sets = log.sets.filter { $0.setType == .working && $0.weightKg > 0 }
        guard let top = sets.map(\.weightKg).max() else { return nil }
        let topSets = sets.filter { $0.weightKg >= top - 0.001 }
        return topSets.contains { $0.reps >= repsMin } ? top : nil
    }

    private func weightIncrement(for exercise: Exercise?) -> Double {
        guard let exercise else { return Constants.barbellIncrement }
        if exercise.equipment.contains(.barbell) { return Constants.barbellIncrement }
        if exercise.equipment.contains(.dumbbell) { return Constants.dumbbellIncrement }
        return Constants.machineIncrement
    }

    /// ~10% reduction rounded down to a loadable increment, always at least
    /// one increment below the stalled weight.
    private func backoffWeight(from weight: Double, increment: Double) -> Double {
        let target = ((weight * 0.9) / increment).rounded(.down) * increment
        return max(min(target, weight - increment), increment)
    }

    /// Consecutive recent sessions (newest first) whose top working weight is
    /// at the stalled weight and where a top set missed the rep floor. Stops
    /// at the first session that either progressed past the floor or was
    /// lifted at a different top weight.
    private func consecutiveFloorMisses(logs: [ExerciseLog], repsMin: Int, atWeight weight: Double) -> Int {
        var count = 0
        for log in logs {
            let sets = log.sets.filter { $0.setType == .working && $0.weightKg > 0 }
            guard let top = sets.map(\.weightKg).max(), abs(top - weight) < 0.1 else { break }
            let topSets = sets.filter { $0.weightKg >= top - 0.001 }
            if topSets.contains(where: { $0.reps < repsMin }) { count += 1 } else { break }
        }
        return count
    }
}
