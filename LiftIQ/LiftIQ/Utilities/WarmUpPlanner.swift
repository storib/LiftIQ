import Foundation

/// Decides which planned exercises get warm-up sets and what they prescribe.
/// Used by both the session factory (to create the SetLogs) and the execution
/// view model (to prefill suggested warm-up weights/reps), so the two always
/// agree on the prescription order.
enum WarmUpPlanner {
    /// Warm-up prescriptions keyed by exerciseId. AI-generated plans carry
    /// explicit `warmUpSets`; when they're missing, the opening exercise of
    /// each of the first two groups gets a synthesized ramp. Superset and
    /// circuit groups never get warm-ups — their rest logic pairs sets across
    /// the group's exercises by set index, which extra warm-up rows would
    /// misalign.
    static func specs(forGroups groups: [ExerciseGroup]) -> [String: [WarmUpSet]] {
        var result: [String: [WarmUpSet]] = [:]
        for (groupIndex, group) in groups.enumerated() where group.groupType == .straight {
            for (exerciseIndex, planned) in group.exercises.enumerated() {
                if let explicit = planned.warmUpSets, !explicit.isEmpty {
                    result[planned.exerciseId] = explicit.map(normalized)
                } else if groupIndex < 2 && exerciseIndex == 0 {
                    result[planned.exerciseId] = defaultRamp()
                }
            }
        }
        return result
    }

    /// Two-set ramp toward the first working weight.
    private static func defaultRamp() -> [WarmUpSet] {
        [
            WarmUpSet(id: UUID().uuidString, percentageOf1RM: 0.5, reps: 8, label: "50%"),
            WarmUpSet(id: UUID().uuidString, percentageOf1RM: 0.7, reps: 5, label: "70%"),
        ]
    }

    /// Plans in the wild carry percentages on both 0-1 and 0-100 scales.
    private static func normalized(_ set: WarmUpSet) -> WarmUpSet {
        guard set.percentageOf1RM > 1 else { return set }
        var copy = set
        copy.percentageOf1RM = set.percentageOf1RM / 100
        return copy
    }
}
