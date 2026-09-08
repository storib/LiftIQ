import Foundation

/// Why the suggestion is what it is. The card renders copy, tint, and icon
/// from this; the service never produces user-facing strings (they would
/// have to be unit-aware, and the View owns the unit system).
enum ProgressionReason: Equatable {
    /// The best top-weight set reached repsMax and no top-weight set fell
    /// below repsMin: move up.
    case increase(previousTopKg: Double)
    /// Every top-weight set met the floor but the best one is short of the
    /// ceiling: hold, `repsToGo` more reps on the best set moves up.
    /// `topReps` were done at `previousTopKg`, which can sit below the
    /// suggested weight after a light week (the recent-best floor).
    case holdNearTarget(previousTopKg: Double, topReps: [Int], repsToGo: Int)
    /// A top-weight set dipped under the floor while the best set met it.
    /// Ordinary fatigue drop-off across sets, not a stall.
    case holdFloorMissed(previousTopKg: Double, topReps: [Int], bestReps: Int)
    /// First session at a weight above the previous session's proven top:
    /// rebuilding reps after an increase is expected, not a miss.
    case holdRebuilding(previousTopKg: Double, topReps: [Int], repsToGo: Int)
    /// `sessions` consecutive sessions at `stuckKg` where even the best
    /// top-weight set missed the floor: back off ~10% as a probe.
    case stall(stuckKg: Double, sessions: Int)
    /// No external load logged: progress by reps; never increment or stall.
    case bodyweight(bestReps: Int)
}

extension ProgressionReason {
    /// Stable label for beta events; never shown to the user.
    var analyticsName: String {
        switch self {
        case .increase: return "increase"
        case .holdNearTarget: return "holdNearTarget"
        case .holdFloorMissed: return "holdFloorMissed"
        case .holdRebuilding: return "holdRebuilding"
        case .stall: return "stall"
        case .bodyweight: return "bodyweight"
        }
    }
}

struct ProgressionSuggestion: Equatable {
    let exerciseId: String
    /// kg; 0 means no load (bodyweight).
    let suggestedWeight: Double
    let suggestedRepsMin: Int
    let suggestedRepsMax: Int
    let reason: ProgressionReason

    /// An acute load-management signal ("back off ~10% and rebuild"), not a
    /// long-term plateau claim — per-session data is far too noisy for that
    /// (see StrengthTrend for the honest long-window version).
    var isStalled: Bool {
        if case .stall = reason { return true }
        return false
    }
}

/// Double progression where the top set drives the decision. Plans routinely
/// prescribe wide ranges (8-15), and normal fatigue means only the first set
/// reaches the ceiling; requiring every set to hit it made progression
/// nearly unreachable and read ordinary drop-off as a stall.
final class ProgressionService {
    func suggest(
        for exercise: PlannedExercise,
        previousLogs: [ExerciseLog],
        exerciseInfo: Exercise?,
        increments: WeightIncrements = .standard
    ) -> ProgressionSuggestion? {
        guard let lastLog = previousLogs.first else { return nil }
        let workingSets = lastLog.sets.filter { $0.setType == .working }
        guard !workingSets.isEmpty else { return nil }

        let repsMin = exercise.repsMin
        let repsMax = max(exercise.repsMin, exercise.repsMax)

        // Unloaded movements progress by reps only. Without this branch a
        // bodyweight lift at max reps would suggest 0 + increment kg.
        let weighted = workingSets.filter { $0.weightKg > 0 }
        guard !weighted.isEmpty else {
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: 0,
                suggestedRepsMin: repsMin,
                suggestedRepsMax: repsMax,
                reason: .bodyweight(bestReps: workingSets.map(\.reps).max() ?? 0)
            )
        }

        let increment = increments.increment(for: exerciseInfo)

        // Anchor to the heaviest working set of the last session. Anchoring to
        // the first set undershoots badly for lifters who ramp across sets.
        let topWeight = weighted.map(\.weightKg).max() ?? 0
        let topSets = weighted.filter { $0.weightKg >= topWeight - 0.001 }
        let topReps = topSets.map(\.reps)
        let bestReps = topReps.max() ?? 0
        let allAboveFloor = topReps.allSatisfy { $0 >= repsMin }

        // A deload or an off week shouldn't drag the suggestion below what the
        // lifter recently handled: floor it at the best recent top-set weight
        // where the rep floor was met.
        let bestRecentTop = previousLogs
            .compactMap { provenTopWeight(in: $0, repsMin: repsMin) }
            .max() ?? 0

        if bestReps >= repsMax && allAboveFloor {
            return ProgressionSuggestion(
                exerciseId: exercise.exerciseId,
                suggestedWeight: max(topWeight + increment, bestRecentTop),
                suggestedRepsMin: repsMin,
                suggestedRepsMax: repsMax,
                reason: .increase(previousTopKg: topWeight)
            )
        }

        // Stall: even the best top-weight set missed the floor for N
        // consecutive sessions at this same weight. Requiring the same weight
        // matters — after an increase the lifter legitimately rebuilds reps
        // from below the ceiling, and that must not read as a stall.
        if bestReps < repsMin {
            let misses = consecutiveFloorMisses(logs: previousLogs, repsMin: repsMin, atWeight: topWeight)
            let backoff = backoffWeight(from: topWeight, increment: increment)
            // At very light loads there is nothing to back off to; a stall
            // that can't change the weight is just noise.
            if misses >= Constants.stallThreshold, backoff < topWeight - 0.001 {
                return ProgressionSuggestion(
                    exerciseId: exercise.exerciseId,
                    suggestedWeight: backoff,
                    suggestedRepsMin: repsMin,
                    suggestedRepsMax: repsMax,
                    reason: .stall(stuckKg: topWeight, sessions: misses)
                )
            }
        }

        let holdWeight = max(topWeight, bestRecentTop)
        let reason: ProgressionReason
        if !allAboveFloor {
            reason = .holdFloorMissed(previousTopKg: topWeight, topReps: topReps, bestReps: bestReps)
        } else if let priorTop = previousLogs.dropFirst().first.flatMap({ provenTopWeight(in: $0, repsMin: repsMin) }),
                  priorTop < topWeight - 0.001 {
            reason = .holdRebuilding(previousTopKg: topWeight, topReps: topReps, repsToGo: repsMax - bestReps)
        } else {
            reason = .holdNearTarget(previousTopKg: topWeight, topReps: topReps, repsToGo: repsMax - bestReps)
        }
        return ProgressionSuggestion(
            exerciseId: exercise.exerciseId,
            suggestedWeight: holdWeight,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: reason
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

    /// ~10% reduction rounded down to a loadable increment, always at least
    /// one increment below the stalled weight.
    private func backoffWeight(from weight: Double, increment: Double) -> Double {
        let target = ((weight * 0.9) / increment).rounded(.down) * increment
        return max(min(target, weight - increment), increment)
    }

    /// Consecutive recent sessions (newest first) whose top working weight is
    /// at the stalled weight and where every top set missed the rep floor.
    /// Stops at the first session that met the floor on any top set or was
    /// lifted at a different top weight.
    private func consecutiveFloorMisses(logs: [ExerciseLog], repsMin: Int, atWeight weight: Double) -> Int {
        var count = 0
        for log in logs {
            let sets = log.sets.filter { $0.setType == .working && $0.weightKg > 0 }
            guard let top = sets.map(\.weightKg).max(), abs(top - weight) < 0.1 else { break }
            let topSets = sets.filter { $0.weightKg >= top - 0.001 }
            if topSets.allSatisfy({ $0.reps < repsMin }) { count += 1 } else { break }
        }
        return count
    }
}
