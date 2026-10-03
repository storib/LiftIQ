import Foundation

/// Pure edits to a saved plan, so the two places that remove an exercise
/// permanently — the plan day screen and "remove from my plan" mid-workout —
/// apply exactly the same structural rules, and both can be tested without
/// Firestore.
enum PlanEditor {
    /// The plan with one slot removed from `dayId`.
    ///
    /// Slots are addressed by `PlannedExercise.id` (the same slot identity
    /// `ExerciseLog.plannedExerciseId` carries), falling back to the first
    /// slot with a matching `exerciseId` for sessions and templates written
    /// before slot ids were threaded through.
    ///
    /// Returns nil when there is nothing safe to do: the day or slot is gone,
    /// or the removal would leave the day with no exercises at all. Callers
    /// use nil to keep the permanent option off the menu rather than to
    /// silently empty a workout.
    static func removingExercise(
        plannedExerciseId: String?,
        exerciseId: String?,
        fromDayId dayId: String,
        in plan: WorkoutPlan
    ) -> WorkoutPlan? {
        guard let dayIndex = plan.workouts.firstIndex(where: { $0.id == dayId }) else { return nil }
        var day = plan.workouts[dayIndex]
        guard let location = locate(
            plannedExerciseId: plannedExerciseId,
            exerciseId: exerciseId,
            in: day.exerciseGroups
        ) else { return nil }

        let totalExercises = day.exerciseGroups.reduce(0) { $0 + $1.exercises.count }
        guard totalExercises > 1 else { return nil }

        day.exerciseGroups[location.group].exercises.remove(at: location.position)
        if day.exerciseGroups[location.group].exercises.isEmpty {
            day.exerciseGroups.remove(at: location.group)
        } else if day.exerciseGroups[location.group].exercises.count == 1 {
            // A one-exercise "superset" is just straight sets — the same
            // degradation WorkoutExecutionViewModel.removeExercise applies to
            // the live session.
            day.exerciseGroups[location.group].groupType = .straight
        }
        // `order` is positional within the day, so renumber across groups.
        var order = 0
        for groupIndex in day.exerciseGroups.indices {
            for exerciseIndex in day.exerciseGroups[groupIndex].exercises.indices {
                day.exerciseGroups[groupIndex].exercises[exerciseIndex].order = order
                order += 1
            }
        }

        var updated = plan
        updated.workouts[dayIndex] = day
        return updated
    }

    /// Whether `removingExercise` would succeed — what the UI asks before
    /// offering "remove from my plan".
    static func canRemoveExercise(
        plannedExerciseId: String?,
        exerciseId: String?,
        fromDayId dayId: String,
        in plan: WorkoutPlan
    ) -> Bool {
        removingExercise(
            plannedExerciseId: plannedExerciseId,
            exerciseId: exerciseId,
            fromDayId: dayId,
            in: plan
        ) != nil
    }

    private static func locate(
        plannedExerciseId: String?,
        exerciseId: String?,
        in groups: [ExerciseGroup]
    ) -> (group: Int, position: Int)? {
        if let plannedExerciseId {
            for (groupIndex, group) in groups.enumerated() {
                if let position = group.exercises.firstIndex(where: { $0.id == plannedExerciseId }) {
                    return (groupIndex, position)
                }
            }
        }
        guard let exerciseId else { return nil }
        for (groupIndex, group) in groups.enumerated() {
            if let position = group.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) {
                return (groupIndex, position)
            }
        }
        return nil
    }
}
