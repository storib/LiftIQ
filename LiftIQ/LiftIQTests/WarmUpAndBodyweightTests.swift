import XCTest
@testable import LiftIQ

/// Covers the warm-up prescription pipeline (WarmUpPlanner ->
/// WorkoutSession.create -> WorkoutExecutionViewModel) and the
/// bodyweight-exercise completion rules.
@MainActor
final class WarmUpAndBodyweightTests: XCTestCase {

    // MARK: - Helpers

    private func makePlanned(
        id: String = "p1",
        exerciseId: String = "bench-press",
        sets: Int = 3,
        restSeconds: Int = 90,
        warmUpSets: [WarmUpSet]? = nil
    ) -> PlannedExercise {
        PlannedExercise(
            id: id,
            exerciseId: exerciseId,
            order: 1,
            sets: sets,
            repsMin: 8,
            repsMax: 10,
            rirTarget: nil,
            rpeTarget: nil,
            restSeconds: restSeconds,
            warmUpSets: warmUpSets,
            notes: nil,
            isOptional: false
        )
    }

    private func makeTemplate(groups: [ExerciseGroup]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: "tmpl-1",
            planId: "plan-1",
            dayNumber: 1,
            name: "Test Day",
            targetMuscleGroups: [.chest],
            estimatedDurationMinutes: 60,
            exerciseGroups: groups,
            notes: nil
        )
    }

    private func makeVM(
        template: WorkoutTemplate,
        workout: FakeWorkoutService? = nil,
        progress: FakeProgressService? = nil,
        exercise: FakeExerciseService? = nil
    ) -> WorkoutExecutionViewModel {
        WorkoutExecutionViewModel(
            template: template,
            userId: "u1",
            planId: nil,
            workoutService: workout ?? FakeWorkoutService(),
            exerciseService: exercise ?? FakeExerciseService(),
            progressService: progress ?? FakeProgressService(),
            progressionService: ProgressionService()
        )
    }

    private func seedInput(
        _ vm: WorkoutExecutionViewModel,
        exercise: Int,
        set: Int,
        weight: String = "",
        reps: String = "",
        rpe: String = ""
    ) {
        let id = vm.session.exerciseLogs[exercise].sets[set].id
        vm.setInputs[id] = SetInput(weight: weight, reps: reps, rpe: rpe)
    }

    private func makeExercise(
        id: String,
        name: String? = nil,
        equipment: [Equipment] = [.barbell]
    ) -> Exercise {
        Exercise(
            id: id,
            name: name ?? id.capitalized,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            equipment: equipment,
            movementPattern: .horizontalPush,
            difficulty: .beginner,
            youtubeVideoId: "",
            instructions: "",
            tips: [],
            alternatives: [],
            isCompound: true,
            tags: []
        )
    }

    private func makeWarmUpSet(
        id: String,
        percentage: Double,
        reps: Int
    ) -> WarmUpSet {
        WarmUpSet(id: id, percentageOf1RM: percentage, reps: reps, label: "\(percentage)")
    }

    // MARK: - WorkoutSession.create warm-up synthesis

    func testCreateSynthesizesWarmUpsForFirstExerciseOfFirstTwoStraightGroups() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .straight, exercises: [
                makePlanned(id: "p3", exerciseId: "ex-c", sets: 2),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g3", groupType: .straight, exercises: [
                makePlanned(id: "p4", exerciseId: "ex-d", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g4", groupType: .superset, exercises: [
                makePlanned(id: "p5", exerciseId: "ex-e", sets: 3),
                makePlanned(id: "p6", exerciseId: "ex-f", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])

        let session = WorkoutSession.create(from: template, userId: "u1", planId: nil)

        func setTypes(_ index: Int) -> [SetType] {
            session.exerciseLogs[index].sets.map(\.setType)
        }

        // Group 0, first exercise: 2-set ramp prepended
        XCTAssertEqual(setTypes(0), [.warmUp, .warmUp, .working, .working, .working])
        // Group 0, second exercise: no warm-ups
        XCTAssertEqual(setTypes(1), [.working, .working, .working])
        // Group 1, first exercise: 2-set ramp prepended
        XCTAssertEqual(setTypes(2), [.warmUp, .warmUp, .working, .working])
        // Group 2 (third group): no warm-ups even for its first exercise
        XCTAssertEqual(setTypes(3), [.working, .working, .working])
        // Superset group: never gets warm-ups
        XCTAssertEqual(setTypes(4), [.working, .working, .working])
        XCTAssertEqual(setTypes(5), [.working, .working, .working])
    }

    func testSupersetGroupGetsNoWarmUpsEvenAsFirstGroup() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3),
            ], restBetweenRoundsSeconds: 60),
            ExerciseGroup(id: "g2", groupType: .straight, exercises: [
                makePlanned(id: "p3", exerciseId: "ex-c", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])

        let session = WorkoutSession.create(from: template, userId: "u1", planId: nil)

        XCTAssertTrue(session.exerciseLogs[0].sets.allSatisfy { $0.setType == .working })
        XCTAssertTrue(session.exerciseLogs[1].sets.allSatisfy { $0.setType == .working })
        // The straight group at index 1 still opens with a ramp
        XCTAssertEqual(session.exerciseLogs[2].sets.map(\.setType),
                       [.warmUp, .warmUp, .working, .working, .working])
    }

    func testCreateHonorsExplicitPlannedWarmUpSets() {
        // Explicit warm-ups apply wherever the plan carries them — including a
        // second exercise (which would never get a synthesized ramp) — and
        // they replace the default ramp on an opening exercise.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, warmUpSets: [
                    makeWarmUpSet(id: "w1", percentage: 0.4, reps: 10),
                ]),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 4, warmUpSets: [
                    makeWarmUpSet(id: "w2", percentage: 0.5, reps: 8),
                    makeWarmUpSet(id: "w3", percentage: 0.6, reps: 6),
                    makeWarmUpSet(id: "w4", percentage: 0.8, reps: 3),
                ]),
            ], restBetweenRoundsSeconds: nil),
        ])

        let session = WorkoutSession.create(from: template, userId: "u1", planId: nil)

        // Opening exercise: exactly the 1 explicit warm-up, not the 2-set ramp
        XCTAssertEqual(session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .working, .working, .working])
        // Second exercise: 3 explicit warm-ups before its 4 working sets
        XCTAssertEqual(session.exerciseLogs[1].sets.map(\.setType),
                       [.warmUp, .warmUp, .warmUp, .working, .working, .working, .working])
        // setNumber counts within each type: warm-ups 1...M, working 1...N
        XCTAssertEqual(session.exerciseLogs[1].sets.map(\.setNumber),
                       [1, 2, 3, 1, 2, 3, 4])
    }

    // MARK: - WarmUpPlanner.specs

    func testWarmUpPlannerNormalizesPercentagesGreaterThanOne() {
        let groups = [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, warmUpSets: [
                    makeWarmUpSet(id: "w1", percentage: 50, reps: 8),  // 0-100 scale
                    makeWarmUpSet(id: "w2", percentage: 0.7, reps: 5), // already 0-1
                ]),
            ], restBetweenRoundsSeconds: nil),
        ]

        let specs = WarmUpPlanner.specs(forGroups: groups)

        XCTAssertEqual(specs["ex-a"]?.map(\.percentageOf1RM), [0.5, 0.7])
        XCTAssertEqual(specs["ex-a"]?.map(\.reps), [8, 5])
    }

    func testWarmUpPlannerSynthesizedRampIsFiftyByEightThenSeventyByFive() {
        let groups = [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ]

        let specs = WarmUpPlanner.specs(forGroups: groups)

        XCTAssertEqual(specs["ex-a"]?.map(\.percentageOf1RM), [0.5, 0.7])
        XCTAssertEqual(specs["ex-a"]?.map(\.reps), [8, 5])
    }

    // MARK: - previousSet type-aware matching

    func testPreviousSetMatchesByTypeAndPositionWithinType() {
        // Current log: [warmUp, warmUp, working, working, working]
        // Previous log: [working, working, working] (no warm-ups last time)
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        let prevSets = [60.0, 62.5, 65.0].enumerated().map { i, weight in
            SetLog(
                id: "prev-\(i + 1)",
                setNumber: i + 1,
                setType: .working,
                weightKg: weight,
                reps: 10,
                rpe: nil,
                isPersonalRecord: false,
                completedAt: Date()
            )
        }
        vm.previousLogs["bench-press"] = ExerciseLog(
            id: "prev-log",
            sessionId: "prev-session",
            exerciseId: "bench-press",
            exerciseName: "Bench Press",
            order: 0,
            groupType: .straight,
            sets: prevSets,
            notes: nil
        )
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .warmUp, .working, .working, .working])

        // First working set (absolute index 2) matches the previous FIRST
        // working set — not the previous set at absolute index 2.
        XCTAssertEqual(vm.previousSet(exerciseLogIndex: 0, setIndex: 2)?.id, "prev-1")
        XCTAssertEqual(vm.previousSet(exerciseLogIndex: 0, setIndex: 2)?.weightKg, 60)
        XCTAssertEqual(vm.previousSet(exerciseLogIndex: 0, setIndex: 3)?.id, "prev-2")
        XCTAssertEqual(vm.previousSet(exerciseLogIndex: 0, setIndex: 4)?.id, "prev-3")

        // Warm-up rows have no type match in the previous session
        XCTAssertNil(vm.previousSet(exerciseLogIndex: 0, setIndex: 0))
        XCTAssertNil(vm.previousSet(exerciseLogIndex: 0, setIndex: 1))
    }

    // MARK: - Bodyweight completion

    func testCompleteSetBodyweightExerciseCompletesWithRepsOnly() async {
        let workout = FakeWorkoutService()
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-up", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "pull-up", name: "Pull-Up", equipment: [.bodyweight]),
        ])
        let vm = makeVM(template: template, workout: workout, exercise: exercise)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        // completeSet reads isBodyweight from exerciseDetails (populated by
        // start() in production); seed it directly to keep the test sync.
        vm.exerciseDetails["pull-up"] = exercise.getExercise(id: "pull-up")

        // First working set (index 2, behind the warm-ups): reps only, no weight
        seedInput(vm, exercise: 0, set: 2, reps: "10")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        let set = vm.session.exerciseLogs[0].sets[2]
        XCTAssertEqual(set.weightKg, 0) // bodyweight persists as zero load
        XCTAssertEqual(set.reps, 10)
        XCTAssertNotNil(set.completedAt)
        XCTAssertTrue(vm.completedSetIds.contains(set.id))
        XCTAssertEqual(workout.updatedSessions.count, 1)
        XCTAssertEqual(workout.updatedSessions.first?.exerciseLogs[0].sets[2].weightKg, 0)
        XCTAssertEqual(workout.updatedSessions.first?.exerciseLogs[0].sets[2].reps, 10)
        XCTAssertNil(vm.errorMessage)
    }

    func testCompleteSetBarbellExerciseStillRefusesWithoutWeight() async {
        let workout = FakeWorkoutService()
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        vm.exerciseDetails["bench-press"] = makeExercise(id: "bench-press", equipment: [.barbell, .bench])

        seedInput(vm, exercise: 0, set: 2, reps: "10") // reps but no weight
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        let set = vm.session.exerciseLogs[0].sets[2]
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertNil(set.completedAt)
        XCTAssertFalse(vm.completedSetIds.contains(set.id))
        XCTAssertTrue(workout.updatedSessions.isEmpty)
    }

    // MARK: - Resume completion detection

    func testResumeMarksCompletedAtStampedZeroWeightSetAsCompleted() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-up", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        var existing = WorkoutSession.create(from: template, userId: "u1", planId: nil)
        // Bodyweight-style completion: completedAt stamped, zero weight
        existing.exerciseLogs[0].sets[2].reps = 10
        existing.exerciseLogs[0].sets[2].completedAt = Date()
        // Legacy fallback: real weight+reps but no completedAt stamp
        existing.exerciseLogs[0].sets[3].weightKg = 20
        existing.exerciseLogs[0].sets[3].reps = 8
        // Untouched set: zero weight, some reps, no stamp — NOT completed
        existing.exerciseLogs[0].sets[4].reps = 8

        let vm = WorkoutExecutionViewModel(
            existingSession: existing,
            workoutService: FakeWorkoutService(),
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }

        XCTAssertTrue(vm.completedSetIds.contains(existing.exerciseLogs[0].sets[2].id))
        XCTAssertTrue(vm.completedSetIds.contains(existing.exerciseLogs[0].sets[3].id))
        XCTAssertFalse(vm.completedSetIds.contains(existing.exerciseLogs[0].sets[4].id))
    }

    // MARK: - Per-type renumbering

    func testUpdateSetTypeRenumbersBothSequences() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        // [warmUp 1, warmUp 2, working 1, working 2, working 3]
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setNumber), [1, 2, 1, 2, 3])

        // Convert the first working set (index 2) into a third warm-up
        vm.updateSetType(exerciseLogIndex: 0, setIndex: 2, newType: .warmUp)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .warmUp, .warmUp, .working, .working])
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setNumber), [1, 2, 3, 1, 2])
    }

    func testRemoveWarmUpSetRenumbersRemainingWarmUpsOnly() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        await vm.removeSet(exerciseLogIndex: 0, setIndex: 0) // drop warm-up 1

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .working, .working, .working])
        // The surviving warm-up renumbers to 1; working sets stay 1...3
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setNumber), [1, 1, 2, 3])
    }
}
