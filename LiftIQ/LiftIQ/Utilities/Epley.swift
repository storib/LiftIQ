import Foundation

enum Epley {
    /// Estimate 1RM from weight and reps using Epley formula
    static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    /// Estimate weight for target reps given a known 1RM
    static func weightForReps(oneRM: Double, targetReps: Int) -> Double {
        guard targetReps > 1 else { return oneRM }
        return oneRM / (1 + Double(targetReps) / 30.0)
    }

    /// Warm-up percentages for a given working weight
    static func warmUpSets(workingWeight: Double) -> [(label: String, weight: Double, reps: Int)] {
        [
            ("Empty bar", min(20, workingWeight * 0.25), 10),
            ("40%", workingWeight * 0.4, 8),
            ("60%", workingWeight * 0.6, 5),
            ("80%", workingWeight * 0.8, 3)
        ].filter { $0.weight > 0 && $0.weight < workingWeight }
    }
}
