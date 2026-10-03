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
    ///
    /// `exercises` supplies the catalog entries for the planned ids. An
    /// exercise that carries no external load gets no warm-ups at all, not
    /// even ones the plan prescribes: a ramp to 50% of a pull-up is
    /// meaningless. Ids missing from the lookup keep the old position-based
    /// behavior; `WorkoutExecutionViewModel.start` prunes those rows once the
    /// catalog has loaded.
    static func specs(
        forGroups groups: [ExerciseGroup],
        exercises: [String: Exercise] = [:]
    ) -> [String: [WarmUpSet]] {
        var result: [String: [WarmUpSet]] = [:]
        for (groupIndex, group) in groups.enumerated() where group.groupType == .straight {
            for (exerciseIndex, planned) in group.exercises.enumerated() {
                if let info = exercises[planned.exerciseId], !info.allowsWarmUpSets { continue }
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
