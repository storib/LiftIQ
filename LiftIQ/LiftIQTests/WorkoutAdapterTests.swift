import XCTest
@testable import LiftIQ

final class WorkoutAdapterTests: XCTestCase {

    // MARK: - Fixtures

    private func exercise(
        _ id: String, muscle: MuscleGroup = .chest, equipment: [Equipment] = [.barbell, .bench],
        pattern: MovementPattern = .horizontalPush, compound: Bool = true, alternatives: [String] = []
    ) -> Exercise {
        Exercise(id: id, name: id.capitalized, primaryMuscleGroup: muscle, secondaryMuscleGroups: [],
                 equipment: equipment, movementPattern: pattern, difficulty: .intermediate,
                 youtubeVideoId: "", instructions: "", tips: [], alternatives: alternatives,
                 isCompound: compound, tags: [])
    }

    private func planned(_ exerciseId: String, sets: Int = 3, rest: Int = 90, optional: Bool = false) -> PlannedExercise {
        PlannedExercise(id: "slot-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: sets, repsMin: 8, repsMax: 12,
                        rirTarget: nil, rpeTarget: nil, restSeconds: rest, warmUpSets: nil, notes: nil, isOptional: optional)
    }

    private func straight(_ exercises: [PlannedExercise]) -> [ExerciseGroup] {
        exercises.map { ExerciseGroup(id: "g-\($0.id)", groupType: .straight, exercises: [$0], restBetweenRoundsSeconds: nil) }
    }

    private func template(_ groups: [ExerciseGroup]) -> WorkoutTemplate {
        WorkoutTemplate(id: "t1", planId: "plan-1", dayNumber: 1, name: "Push", targetMuscleGroups: [.chest],
                        estimatedDurationMinutes: 60, exerciseGroups: groups, notes: nil)
    }

    private var catalog: [String: Exercise] {
        let all = [
            exercise("bench"),
            exercise("incline-db", equipment: [.dumbbell, .bench]),
            exercise("machine-press", equipment: [.machines]),
            exercise("push-up", equipment: [.bodyweight]),
            exercise("cable-fly", equipment: [.cables], pattern: .isolation, compound: false),
            exercise("db-fly", equipment: [.dumbbell, .bench], pattern: .isolation, compound: false),
            exercise("pushdown", muscle: .triceps, equipment: [.cables], pattern: .isolation, compound: false),
            exercise("skull-crusher", muscle: .triceps, equipment: [.ezBar, .bench], pattern: .isolation, compound: false),
            exercise("dips", muscle: .triceps, equipment: [.bodyweight], pattern: .verticalPush),
            exercise("ohp", muscle: .shoulders, equipment: [.barbell], pattern: .verticalPush),
            exercise("lateral-raise", muscle: .shoulders, equipment: [.dumbbell], pattern: .isolation, compound: false),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    private func context(preferences: [String: ExercisePreference] = [:], lastLogs: [String: ExerciseLog] = [:], restOverride: Int? = nil) -> WorkoutAdapter.Context {
        WorkoutAdapter.Context(exercises: catalog, preferences: preferences, lastLogs: lastLogs, userRestOverride: restOverride, defaultRestSeconds: 60)
    }

    private func log(_ exerciseId: String) -> ExerciseLog {
        ExerciseLog(id: "l-\(exerciseId)", sessionId: "s", exerciseId: exerciseId, exerciseName: exerciseId, order: 1, groupType: .straight,
                    sets: [SetLog(id: "x", setNumber: 1, setType: .working, weightKg: 40, reps: 10, rpe: nil, isPersonalRecord: false, completedAt: Date())], notes: nil)
    }

    /// bench 3×120s (first straight group → 2 synthesized warm-ups), ohp 3×120s (second → warm-ups), cable-fly 3×60s, pushdown 3×60s, optional lateral-raise 3×60s.
    private var pushDay: WorkoutTemplate {
        template(straight([
            planned("bench", rest: 120), planned("ohp", rest: 120),
            planned("cable-fly", rest: 60), planned("pushdown", rest: 60),
            planned("lateral-raise", rest: 60, optional: true),
        ]))
    }

    // MARK: - Estimate

    func testEstimateStraightAndSuperset() {
        // The first exercise of the first two straight groups gets two synthesized warm-ups.
        // bench: 60 + 2×60 + 3×30 + 2×90 = 450s; cable-fly: 60 + 2×60 + 90 + 2×60 = 390s → 840s = 14 min
        let t = template(straight([planned("bench", rest: 90), planned("cable-fly", rest: 60)]))
        XCTAssertEqual(WorkoutAdapter.estimatedMinutes(t, context: context()), 14)

        // superset of two 3-set exercises with 60s round rest: 60 + 3×(60 + 60) = 420s = 7 min
        let ss = template([ExerciseGroup(id: "g", groupType: .superset, exercises: [planned("cable-fly"), planned("pushdown")], restBetweenRoundsSeconds: 60)])
        XCTAssertEqual(WorkoutAdapter.estimatedMinutes(ss, context: context()), 7)
    }

    func testEstimateHonoursUserRestOverride() {
        let t = template(straight([planned("cable-fly", rest: 120)]))
        XCTAssertEqual(WorkoutAdapter.estimatedMinutes(t, context: context(restOverride: 30)), 6)   // 60 + 2×60 + 90 + 2×30 = 330s
        XCTAssertEqual(WorkoutAdapter.estimatedMinutes(t, context: context()), 9)                   // 60 + 2×60 + 90 + 2×120 = 510s
    }

    // MARK: - Short on time

    func testShortOnTimeDropsOptionalFirst() {
        let before = WorkoutAdapter.estimatedMinutes(pushDay, context: context())
        let result = WorkoutAdapter.shortOnTime(pushDay, targetMinutes: before - 3, context: context())
        XCTAssertEqual(result.changes.first?.kind, .removedExercise)
        XCTAssertEqual(result.changes.first?.exerciseId, "lateral-raise")
        XCTAssertTrue(result.changes.first?.reason.contains("Optional") ?? false)
        XCTAssertFalse(result.template.exerciseGroups.flatMap(\.exercises).contains { $0.exerciseId == "lateral-raise" })
        XCTAssertLessThan(result.minutesAfter, result.minutesBefore)
    }

    func testShortOnTimeTrimsIsolationSetsToFloorBeforeRest() {
        let result = WorkoutAdapter.shortOnTime(pushDay, targetMinutes: 22, context: context())
        let slots = result.template.exerciseGroups.flatMap(\.exercises)
        for slot in slots where ["cable-fly", "pushdown"].contains(slot.exerciseId) {
            XCTAssertGreaterThanOrEqual(slot.sets, WorkoutAdapter.setFloor)
        }
        XCTAssertTrue(result.changes.contains { $0.kind == .reducedSets })
        // Merged: one change per exercise, from 3 to 2.
        let pushdown = result.changes.first { $0.kind == .reducedSets && $0.exerciseId == "pushdown" }
        XCTAssertEqual(pushdown?.fromValue, 3)
        XCTAssertEqual(pushdown?.toValue, 2)
        XCTAssertLessThanOrEqual(result.minutesAfter, 22)
    }

    func testShortOnTimeCapsRestThenDropsIsolationAndNeverTheFirstCompound() {
        let result = WorkoutAdapter.shortOnTime(pushDay, targetMinutes: 12, context: context())
        let slots = result.template.exerciseGroups.flatMap(\.exercises)
        XCTAssertEqual(slots.first?.exerciseId, "bench", "the first compound survives every lever")
        XCTAssertTrue(result.changes.contains { $0.kind == .restShortened })
        XCTAssertTrue(result.changes.contains { $0.kind == .removedExercise && $0.exerciseId == "pushdown" })
        XCTAssertTrue(result.changes.allSatisfy { !$0.reason.isEmpty })
    }

    func testShortOnTimeReportsWhenTargetUnreachable() {
        let result = WorkoutAdapter.shortOnTime(pushDay, targetMinutes: 1, context: context())
        XCTAssertGreaterThan(result.minutesAfter, 1)
        XCTAssertEqual(result.template.exerciseGroups.flatMap(\.exercises).first?.exerciseId, "bench")
        XCTAssertEqual(result.template.exerciseGroups.flatMap(\.exercises).first?.sets, 3, "first compound keeps its sets")
    }

    func testShortOnTimeDegradesSupersetWhenOneExerciseLeft() {
        let t = template([
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench", rest: 90)], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [planned("ohp", sets: 3), planned("cable-fly", sets: 3)], restBetweenRoundsSeconds: 90),
        ])
        let result = WorkoutAdapter.shortOnTime(t, targetMinutes: 9, context: context())
        let g2 = result.template.exerciseGroups.first { $0.exercises.contains { $0.exerciseId == "ohp" } }
        XCTAssertEqual(g2?.exercises.count, 1)
        XCTAssertEqual(g2?.groupType, .straight)
    }

    func testShortOnTimeSkipsRestCapWhenLifterPinnedRest() {
        let result = WorkoutAdapter.shortOnTime(pushDay, targetMinutes: 12, context: context(restOverride: 120))
        XCTAssertFalse(result.changes.contains { $0.kind == .restShortened })
    }

    // MARK: - Candidates

    func testCandidatesRequireSameMuscleAndEquipmentAndExcludeInWorkoutAndAvoided() {
        let t = template(straight([planned("bench"), planned("incline-db")]))
        let prefs = ["push-up": ExercisePreference(avoided: true)]
        let result = WorkoutAdapter.candidates(replacing: "bench", in: t, equipment: [.dumbbell, .bench, .machines, .bodyweight], context: context(preferences: prefs))
        let ids = result.map(\.id)
        XCTAssertTrue(ids.contains("machine-press"))
        XCTAssertTrue(ids.contains("db-fly"))
        XCTAssertFalse(ids.contains("incline-db"), "already in the workout")
        XCTAssertFalse(ids.contains("push-up"), "avoided")
        XCTAssertFalse(ids.contains("cable-fly"), "needs cables")
        XCTAssertFalse(ids.contains("ohp"), "different muscle")
    }

    func testUsualAlternativeRanksFirstThenPatternAndHistory() {
        let t = template(straight([planned("bench")]))
        let prefs = ["bench": ExercisePreference(usualAlternativeId: "db-fly")]
        let result = WorkoutAdapter.candidates(replacing: "bench", in: t, equipment: Set(Equipment.allCases),
                                               context: context(preferences: prefs, lastLogs: ["machine-press": log("machine-press")]))
        XCTAssertEqual(result.first?.id, "db-fly")
        XCTAssertTrue(result.first?.isUsualAlternative ?? false)
        XCTAssertEqual(result.first?.reasons.first, "Your usual swap")
        // Among the rest, same pattern + history beats same pattern alone.
        let machine = result.first { $0.id == "machine-press" }
        let incline = result.first { $0.id == "incline-db" }
        XCTAssertGreaterThan(machine?.score ?? 0, incline?.score ?? 0)
        XCTAssertTrue(machine?.reasons.contains("You've done this before") ?? false)
    }

    func testAlternativesBoostIgnoresDanglingIds() {
        var cat = catalog
        cat["bench"] = exercise("bench", alternatives: ["machine-press", "does-not-exist"])
        let ctx = WorkoutAdapter.Context(exercises: cat)
        let result = WorkoutAdapter.candidates(replacing: "bench", in: template(straight([planned("bench")])), equipment: Set(Equipment.allCases), context: ctx)
        XCTAssertEqual(result.first?.id, "machine-press")
        XCTAssertTrue(result.first?.reasons.contains("Listed alternative") ?? false)
    }

    // MARK: - Equipment busy / different gym / diff

    func testEquipmentBusyReplacesSlotInPlace() {
        let t = template(straight([planned("bench", sets: 4, rest: 120), planned("pushdown")]))
        let result = WorkoutAdapter.equipmentBusy(t, exerciseId: "bench", replacement: catalog["machine-press"]!, reason: "Bench taken", context: context())
        let slot = result.template.exerciseGroups[0].exercises[0]
        XCTAssertEqual(slot.exerciseId, "machine-press")
        XCTAssertEqual(slot.sets, 4)
        XCTAssertEqual(slot.restSeconds, 120)
        XCTAssertEqual(slot.id, "slot-bench", "slot identity survives")
        XCTAssertEqual(result.changes.map(\.kind), [.swappedExercise])
        XCTAssertEqual(result.record.busyExerciseId, "bench")
    }

    func testDifferentGymPrefersSamePatternAndSkipsExercisesAlreadyInTheWorkout() {
        let home = GymSetup(id: "home", name: "Home", equipment: [.dumbbell, .bench, .bodyweight], isDefault: false)
        let t = template(straight([planned("bench"), planned("pushdown"), planned("incline-db")]))
        guard case .adapted(let result) = WorkoutAdapter.differentGym(t, setup: home, context: context()) else {
            return XCTFail("push-up and dips make every slot resolvable at home")
        }
        // bench → push-up (same horizontal push; incline-db is already in the workout, db-fly is isolation)
        XCTAssertEqual(result.template.exerciseGroups[0].exercises[0].exerciseId, "push-up")
        XCTAssertEqual(result.template.exerciseGroups[0].exercises[0].id, "slot-bench")
        // pushdown → dips (only triceps exercise within the setup)
        XCTAssertEqual(result.template.exerciseGroups[1].exercises[0].exerciseId, "dips")
        // incline-db already fits and is untouched
        XCTAssertEqual(result.template.exerciseGroups[2].exercises[0].exerciseId, "incline-db")
        XCTAssertEqual(result.changes.count, 2)
        XCTAssertTrue(result.changes[0].reason.contains("No Barbell at Home"))
    }

    func testDifferentGymFullyResolvedWhenEveryExerciseHasACandidate() {
        let gym = GymSetup(id: "g", name: "Hotel", equipment: [.dumbbell, .bench, .bodyweight], isDefault: false)
        let t = template(straight([planned("bench"), planned("pushdown")]))
        guard case .adapted(let result) = WorkoutAdapter.differentGym(t, setup: gym, context: context()) else {
            return XCTFail("dips (bodyweight, triceps) should resolve pushdown")
        }
        XCTAssertEqual(result.changes.count, 2)
        XCTAssertEqual(result.record.kind, .differentGym)
        XCTAssertEqual(result.record.gymSetupId, "g")
    }

    func testDifferentGymReportsUnresolvedWhenNothingFits() {
        let bands = GymSetup(id: "b", name: "Bands", equipment: [.bands], isDefault: false)
        let t = template(straight([planned("bench")]))
        guard case .needsAI(let partial, let unresolved) = WorkoutAdapter.differentGym(t, setup: bands, context: context()) else {
            return XCTFail("no chest exercise uses bands only")
        }
        XCTAssertEqual(unresolved.map(\.exerciseId), ["bench"])
        XCTAssertTrue(partial.changes.isEmpty)

        let dropped = WorkoutAdapter.removingUnresolved(partial, unresolved: unresolved, setupName: "Bands", context: context())
        XCTAssertTrue(dropped.template.exerciseGroups.isEmpty)
        XCTAssertEqual(dropped.changes.first?.kind, .removedExercise)
    }

    func testDiffDetectsSwapRemoveAdd() {
        let original = template(straight([planned("bench"), planned("pushdown"), planned("ohp")]))
        var ai = original
        ai.exerciseGroups[0].exercises[0].exerciseId = "machine-press"        // swap
        ai.exerciseGroups.remove(at: 1)                                       // remove pushdown
        ai.exerciseGroups.append(ExerciseGroup(id: "new", groupType: .straight, exercises: [planned("dips")], restBetweenRoundsSeconds: nil)) // add
        let changes = WorkoutAdapter.diff(original: original, aiResult: ai, context: context(), reason: "Replaced by AI")
        XCTAssertEqual(changes.map(\.kind), [.swappedExercise, .removedExercise, .addedExercise])
        XCTAssertEqual(changes[0].replacementExerciseId, "machine-press")
        XCTAssertEqual(changes[1].exerciseId, "pushdown")
        XCTAssertEqual(changes[2].exerciseId, "dips")
    }
}
