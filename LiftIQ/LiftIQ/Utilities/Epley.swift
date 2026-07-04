import Foundation

enum Epley {
    /// Estimate 1RM from weight and reps using Epley formula
    static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }
}
