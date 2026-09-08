import Foundation

/// Deterministic "adapt today's workout" engine. Everything here is a pure
/// function of the template, the catalog, and the lifter's memory, so each
/// change can carry a reason built from the rule that made it. The AI path
/// (`modifyWorkout`) is only a fallback for gym changes nothing here can
/// resolve; `diff` turns its result into the same change list.
enum WorkoutAdapter {
    struct Context {
        var exercises: [String: Exercise]
        var preferences: [String: ExercisePreference] = [:]
        /// Most recent completed log per exercise id, for "you've done this".
        var lastLogs: [String: ExerciseLog] = [:]
        var userRestOverride: Int? = nil
        var defaultRestSeconds: Int = 60
    }

    struct SwapCandidate: Identifiable, Hashable {
        let exercise: Exercise
        let score: Int
        let reasons: [String]
        let lastLog: ExerciseLog?
        let isUsualAlternative: Bool

        var id: String { exercise.id }
    }

    enum DifferentGymResult {
        case adapted(AdaptedWorkout)
        /// Deterministic swaps applied where possible; the rest need the AI.
        case needsAI(partial: AdaptedWorkout, unresolved: [PlannedExercise])
    }

    // MARK: - Time estimate

    static let secondsPerSet = 30
    static let setupSecondsPerExercise = 60
    static let secondsPerWarmUp = 60

    /// Rough session length: setup + warm-ups + sets + the rest between them.
    static func estimatedMinutes(_ template: WorkoutTemplate, context: Context) -> Int {
        let warmUps = WarmUpPlanner.specs(forGroups: template.exerciseGroups)
        var seconds = 0
        for group in template.exerciseGroups where !group.exercises.isEmpty {
            if group.groupType == .straight || group.exercises.count == 1 {
                for planned in group.exercises {
                    let rest = restSeconds(for: planned, context: context)
                    let warmUpCount = warmUps[planned.exerciseId]?.count ?? 0
                    seconds += setupSecondsPerExercise
                        + warmUpCount * secondsPerWarmUp
                        + planned.sets * secondsPerSet
                        + max(0, planned.sets - 1) * rest
                }
            } else {
                let rounds = group.exercises.map(\.sets).max() ?? 0
                let roundRest = context.userRestOverride ?? group.restBetweenRoundsSeconds ?? context.defaultRestSeconds
                seconds += setupSecondsPerExercise
                    + rounds * (secondsPerSet * group.exercises.count + roundRest)
            }
        }
        return Int((Double(seconds) / 60).rounded(.up))
    }

    private static func restSeconds(for planned: PlannedExercise, context: Context) -> Int {
        context.userRestOverride ?? (planned.restSeconds > 0 ? planned.restSeconds : context.defaultRestSeconds)
    }

    // MARK: - Short on time

    static let compoundRestCap = 90
    static let isolationRestCap = 60
    static let setFloor = 2

    /// Shrinks the workout to fit `targetMinutes`, cheapest lever first:
    /// optional exercises, then isolation sets, then rest, then whole
    /// isolation exercises, then compound sets. The first compound is never
    /// removed. Every change carries the rule that made it.
    static func shortOnTime(
        _ template: WorkoutTemplate,
        targetMinutes: Int,
        context: Context,
        now: Date = Date()
    ) -> AdaptedWorkout {
        var working = template
        var changes: [WorkoutChange] = []
        let before = estimatedMinutes(template, context: context)
        let fits = { estimatedMinutes(working, context: context) <= targetMinutes }

        // 1. Optional exercises, last first.
        if !fits() {
            for slot in flatSlots(working).reversed() where slot.planned.isOptional {
                let name = context.exercises[slot.planned.exerciseId]?.name ?? slot.planned.exerciseId
                working = removing(slot.planned.id, from: working)
                changes.append(WorkoutChange(
                    id: UUID().uuidString, kind: .removedExercise,
                    exerciseId: slot.planned.exerciseId, exerciseName: name,
                    reason: "Optional — dropped to fit \(targetMinutes) min"
                ))
                if fits() { break }
            }
        }

        // 2. Trim isolation sets to the floor, one set per pass, last first.
        var trimmed = true
        while !fits(), trimmed {
            trimmed = false
            for slot in flatSlots(working).reversed()
            where isIsolation(slot.planned, context: context) && slot.planned.sets > setFloor {
                working = updating(slot.planned.id, in: working) { $0.sets -= 1 }
                recordSetChange(&changes, slot.planned, context: context, to: slot.planned.sets - 1,
                                reason: "Fewer sets on isolation work to fit \(targetMinutes) min")
                trimmed = true
                if fits() { break }
            }
        }

        // 3. Cap rest (unless the lifter pinned rest in Profile).
        if !fits(), context.userRestOverride == nil {
            for slot in flatSlots(working) {
                let cap = isIsolation(slot.planned, context: context) ? isolationRestCap : compoundRestCap
                let current = restSeconds(for: slot.planned, context: context)
                guard current > cap else { continue }
                working = updating(slot.planned.id, in: working) { $0.restSeconds = cap }
                let name = context.exercises[slot.planned.exerciseId]?.name ?? slot.planned.exerciseId
                changes.append(WorkoutChange(
                    id: UUID().uuidString, kind: .restShortened,
                    exerciseId: slot.planned.exerciseId, exerciseName: name,
                    fromValue: current, toValue: cap,
                    reason: "Rest \(current)s → \(cap)s"
                ))
                if fits() { break }
            }
        }

        // 4. Drop whole isolation exercises, last first.
        if !fits() {
            for slot in flatSlots(working).reversed() where isIsolation(slot.planned, context: context) {
                let name = context.exercises[slot.planned.exerciseId]?.name ?? slot.planned.exerciseId
                working = removing(slot.planned.id, from: working)
                changes.append(WorkoutChange(
                    id: UUID().uuidString, kind: .removedExercise,
                    exerciseId: slot.planned.exerciseId, exerciseName: name,
                    reason: "Isolation work dropped — compounds kept"
                ))
                if fits() { break }
            }
        }

        // 5. Compound sets to the floor, never touching the first compound.
        trimmed = true
        while !fits(), trimmed {
            trimmed = false
            let slots = flatSlots(working)
            let firstCompoundId = slots.first { !isIsolation($0.planned, context: context) }?.planned.id
            for slot in slots.reversed()
            where !isIsolation(slot.planned, context: context) && slot.planned.id != firstCompoundId && slot.planned.sets > setFloor {
                working = updating(slot.planned.id, in: working) { $0.sets -= 1 }
                recordSetChange(&changes, slot.planned, context: context, to: slot.planned.sets - 1,
                                reason: "Fewer sets on later compounds to fit \(targetMinutes) min")
                trimmed = true
                if fits() { break }
            }
        }

        let after = estimatedMinutes(working, context: context)
        working.estimatedDurationMinutes = after
        return AdaptedWorkout(
            template: working,
            changes: mergeSetChanges(changes),
            record: WorkoutAdaptation(kind: .shortOnTime, targetMinutes: targetMinutes,
                                      changes: mergeSetChanges(changes), usedAI: false, acceptedAt: now),
            minutesBefore: before,
            minutesAfter: after,
            sourceTemplateId: template.id,
            planId: template.planId
        )
    }

    // MARK: - Candidates

    /// Alternatives for one exercise within the given equipment: same primary
    /// muscle, not avoided, not already in the workout. Ranked by what the
    /// lifter has taught the app first, then by similarity and familiarity.
    static func candidates(
        replacing exerciseId: String,
        in template: WorkoutTemplate,
        equipment: Set<Equipment>,
        context: Context
    ) -> [SwapCandidate] {
        guard let current = context.exercises[exerciseId] else { return [] }
        let inWorkout = Set(template.exerciseGroups.flatMap(\.exercises).map(\.exerciseId))
        let usual = context.preferences[exerciseId]?.usualAlternativeId
        let avoided = Set(context.preferences.filter { $0.value.isAvoided }.map(\.key))

        var results: [SwapCandidate] = []
        for exercise in context.exercises.values {
            guard exercise.id != exerciseId,
                  exercise.primaryMuscleGroup == current.primaryMuscleGroup,
                  !inWorkout.contains(exercise.id),
                  !avoided.contains(exercise.id),
                  exercise.equipment.allSatisfy({ equipment.contains($0) }) else { continue }
            var score = 0
            var reasons: [String] = []
            let isUsual = exercise.id == usual
            if isUsual { score += 100; reasons.append("Your usual swap") }
            if exercise.movementPattern == current.movementPattern { score += 30; reasons.append("Same movement pattern") }
            if current.alternatives.contains(exercise.id) { score += 25; reasons.append("Listed alternative") }
            if context.lastLogs[exercise.id] != nil { score += 20; reasons.append("You've done this before") }
            if exercise.isCompound == current.isCompound { score += 10 }
            results.append(SwapCandidate(
                exercise: exercise, score: score, reasons: reasons,
                lastLog: context.lastLogs[exercise.id], isUsualAlternative: isUsual
            ))
        }
        return results.sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.exercise.name < $1.exercise.name
        }
    }

    // MARK: - Equipment busy

    /// Replaces one slot's exercise in place; sets, reps and rest stay.
    static func equipmentBusy(
        _ template: WorkoutTemplate,
        exerciseId: String,
        replacement: Exercise,
        reason: String,
        context: Context,
        now: Date = Date()
    ) -> AdaptedWorkout {
        let before = estimatedMinutes(template, context: context)
        var working = template
        var changes: [WorkoutChange] = []
        if let slot = flatSlots(template).first(where: { $0.planned.exerciseId == exerciseId }) {
            working = updating(slot.planned.id, in: working) { $0.exerciseId = replacement.id }
            changes.append(WorkoutChange(
                id: UUID().uuidString, kind: .swappedExercise,
                exerciseId: exerciseId,
                exerciseName: context.exercises[exerciseId]?.name ?? exerciseId,
                replacementExerciseId: replacement.id, replacementName: replacement.name,
                reason: reason
            ))
        }
        return AdaptedWorkout(
            template: working, changes: changes,
            record: WorkoutAdaptation(kind: .equipmentBusy, busyExerciseId: exerciseId,
                                      changes: changes, usedAI: false, acceptedAt: now),
            minutesBefore: before, minutesAfter: estimatedMinutes(working, context: context),
            sourceTemplateId: template.id, planId: template.planId
        )
    }

    // MARK: - Different gym

    /// Swaps every slot whose equipment the setup lacks for the best
    /// candidate within it; slots with no candidate are handed to the AI.
    static func differentGym(
        _ template: WorkoutTemplate,
        setup: GymSetup,
        context: Context,
        now: Date = Date()
    ) -> DifferentGymResult {
        let equipment = Set(setup.equipment)
        let before = estimatedMinutes(template, context: context)
        var working = template
        var changes: [WorkoutChange] = []
        var unresolved: [PlannedExercise] = []

        for slot in flatSlots(template) {
            guard let exercise = context.exercises[slot.planned.exerciseId] else { continue }
            guard !exercise.equipment.allSatisfy({ equipment.contains($0) }) else { continue }
            let missing = exercise.equipment.filter { !equipment.contains($0) }.map(\.displayName).joined(separator: ", ")
            if let best = candidates(replacing: slot.planned.exerciseId, in: working, equipment: equipment, context: context).first {
                working = updating(slot.planned.id, in: working) { $0.exerciseId = best.exercise.id }
                let why = best.reasons.isEmpty ? "Same muscle group" : best.reasons.joined(separator: " · ")
                changes.append(WorkoutChange(
                    id: UUID().uuidString, kind: .swappedExercise,
                    exerciseId: exercise.id, exerciseName: exercise.name,
                    replacementExerciseId: best.exercise.id, replacementName: best.exercise.name,
                    reason: "No \(missing) at \(setup.name) — \(why.lowercased())"
                ))
            } else {
                unresolved.append(slot.planned)
            }
        }

        let adapted = AdaptedWorkout(
            template: working, changes: changes,
            record: WorkoutAdaptation(kind: .differentGym, gymSetupId: setup.id,
                                      changes: changes, usedAI: false, acceptedAt: now),
            minutesBefore: before, minutesAfter: estimatedMinutes(working, context: context),
            sourceTemplateId: template.id, planId: template.planId
        )
        return unresolved.isEmpty ? .adapted(adapted) : .needsAI(partial: adapted, unresolved: unresolved)
    }

    /// Drops the slots the AI would have handled — the no-consent path.
    static func removingUnresolved(
        _ partial: AdaptedWorkout,
        unresolved: [PlannedExercise],
        setupName: String,
        context: Context
    ) -> AdaptedWorkout {
        var result = partial
        for planned in unresolved {
            result.template = removing(planned.id, from: result.template)
            result.changes.append(WorkoutChange(
                id: UUID().uuidString, kind: .removedExercise,
                exerciseId: planned.exerciseId,
                exerciseName: context.exercises[planned.exerciseId]?.name ?? planned.exerciseId,
                reason: "No alternative available at \(setupName)"
            ))
        }
        result.record.changes = result.changes
        result.minutesAfter = estimatedMinutes(result.template, context: context)
        return result
    }

    // MARK: - Diff (AI fallback result → changes)

    /// Compares two templates by slot id: same slot with a different exercise
    /// is a swap, a missing slot a removal, a new slot an addition.
    static func diff(
        original: WorkoutTemplate,
        aiResult: WorkoutTemplate,
        context: Context,
        reason: String
    ) -> [WorkoutChange] {
        let before = Dictionary(uniqueKeysWithValues: flatSlots(original).map { ($0.planned.id, $0.planned) })
        let after = Dictionary(uniqueKeysWithValues: flatSlots(aiResult).map { ($0.planned.id, $0.planned) })
        func name(_ id: String) -> String { context.exercises[id]?.name ?? id }
        var changes: [WorkoutChange] = []
        for slot in flatSlots(original) {
            let old = slot.planned
            if let new = after[old.id] {
                if new.exerciseId != old.exerciseId {
                    changes.append(WorkoutChange(
                        id: UUID().uuidString, kind: .swappedExercise,
                        exerciseId: old.exerciseId, exerciseName: name(old.exerciseId),
                        replacementExerciseId: new.exerciseId, replacementName: name(new.exerciseId),
                        reason: reason
                    ))
                }
            } else {
                changes.append(WorkoutChange(
                    id: UUID().uuidString, kind: .removedExercise,
                    exerciseId: old.exerciseId, exerciseName: name(old.exerciseId), reason: reason
                ))
            }
        }
        for slot in flatSlots(aiResult) where before[slot.planned.id] == nil {
            changes.append(WorkoutChange(
                id: UUID().uuidString, kind: .addedExercise,
                exerciseId: slot.planned.exerciseId, exerciseName: name(slot.planned.exerciseId), reason: reason
            ))
        }
        return changes
    }

    // MARK: - Template surgery

    struct Slot {
        let groupIndex: Int
        let exerciseIndex: Int
        let planned: PlannedExercise
    }

    static func flatSlots(_ template: WorkoutTemplate) -> [Slot] {
        template.exerciseGroups.enumerated().flatMap { gi, group in
            group.exercises.enumerated().map { ei, planned in Slot(groupIndex: gi, exerciseIndex: ei, planned: planned) }
        }
    }

    static func isIsolation(_ planned: PlannedExercise, context: Context) -> Bool {
        guard let exercise = context.exercises[planned.exerciseId] else { return false }
        return !exercise.isCompound || exercise.movementPattern == .isolation
    }

    /// Removes a slot; an emptied group goes, and a one-exercise superset
    /// degrades to straight sets (same rule as removing mid-workout).
    static func removing(_ plannedId: String, from template: WorkoutTemplate) -> WorkoutTemplate {
        var result = template
        result.exerciseGroups = result.exerciseGroups.compactMap { group in
            var g = group
            g.exercises.removeAll { $0.id == plannedId }
            guard !g.exercises.isEmpty else { return nil }
            if g.exercises.count == 1, g.groupType != .straight {
                g.groupType = .straight
                g.restBetweenRoundsSeconds = nil
            }
            return g
        }
        return result
    }

    static func updating(_ plannedId: String, in template: WorkoutTemplate, _ change: (inout PlannedExercise) -> Void) -> WorkoutTemplate {
        var result = template
        for gi in result.exerciseGroups.indices {
            for ei in result.exerciseGroups[gi].exercises.indices where result.exerciseGroups[gi].exercises[ei].id == plannedId {
                change(&result.exerciseGroups[gi].exercises[ei])
            }
        }
        return result
    }

    private static func recordSetChange(_ changes: inout [WorkoutChange], _ planned: PlannedExercise, context: Context, to: Int, reason: String) {
        changes.append(WorkoutChange(
            id: UUID().uuidString, kind: .reducedSets,
            exerciseId: planned.exerciseId,
            exerciseName: context.exercises[planned.exerciseId]?.name ?? planned.exerciseId,
            fromValue: planned.sets, toValue: to, reason: reason
        ))
    }

    /// Several one-set trims on the same exercise collapse into one change
    /// ("4 → 2 sets") so the preview reads cleanly.
    private static func mergeSetChanges(_ changes: [WorkoutChange]) -> [WorkoutChange] {
        var merged: [WorkoutChange] = []
        for change in changes {
            if change.kind == .reducedSets,
               let index = merged.firstIndex(where: { $0.kind == .reducedSets && $0.exerciseId == change.exerciseId }) {
                merged[index].toValue = change.toValue
            } else {
                merged.append(change)
            }
        }
        return merged
    }
}
