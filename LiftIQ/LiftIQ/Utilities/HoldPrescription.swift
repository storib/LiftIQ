import Foundation

/// Reads a timed hold's prescription out of a plan slot.
///
/// Plans carry no seconds field: a hold's prescription travels in
/// `repsMin`/`repsMax`, which the generation prompt fills with seconds from
/// v2.3.0 on. Plans written before that — and slots a mid-workout swap just
/// turned into a hold — carry an ordinary rep range instead, and "hold a
/// plank for 8 seconds" is not a prescription anyone means. A floor below
/// `Constants.minHoldPrescriptionSeconds` is therefore read as a rep range
/// and replaced with a plain 30-60s hold.
enum HoldPrescription {
    static func seconds(for planned: PlannedExercise) -> (min: Int, max: Int) {
        let low = planned.repsMin
        guard low >= Constants.minHoldPrescriptionSeconds else {
            return (Constants.defaultHoldSeconds, Constants.defaultHoldSeconds * 2)
        }
        return (low, max(low, planned.repsMax))
    }
}
