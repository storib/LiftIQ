import XCTest
@testable import LiftIQ

/// Covers the exercise tracking-mode classification: which exercises get
/// warm-up ramps, which can complete a set without a weight, and how timed
/// holds are prescribed, logged, and progressed.
@MainActor
final class TrackingModeTests: XCTestCase {

    // MARK: - Helpers

    private func makePlanned(
        id: String = "p1",
        exerciseId: String = "bench-press",
        sets: Int = 3,
        repsMin: Int = 8,
        repsMax: Int = 10,
        warmUpSets: [WarmUpSet]? = nil
    ) -> PlannedExercise {
        PlannedExercise(
            id: id,
            exerciseId: exerciseId,
            order: 1,
            sets: sets,
            repsMin: repsMin,
            repsMax: repsMax,
            rirTarget: nil,
            rpeTarget: nil,
            restSeconds: 90,
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

    private func makeExercise(
        id: String,
        equipment: [Equipment] = [.barbell],
        trackingMode: TrackingMode? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            name: id.capitalized,
            primaryMuscleGroup: .core,
            secondaryMuscleGroups: [],
            equipment: equipment,
            movementPattern: .core,
            difficulty: .beginner,
            youtubeVideoId: "",
            instructions: "",
            tips: [],
            alternatives: [],
            isCompound: false,
            tags: [],
            trackingMode: trackingMode
        )
    }

    private func makeVM(
        template: WorkoutTemplate,
        workout: FakeWorkoutService? = nil,
        exercise: FakeExerciseService? = nil,
        progress: FakeProgressService? = nil
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

    private func workingLog(
        exerciseId: String,
        holds: [Int],
        setType: SetType = .working
    ) -> ExerciseLog {
        ExerciseLog(
            id: "log-\(exerciseId)",
            sessionId: "s-prev",
            exerciseId: exerciseId,
            exerciseName: exerciseId,
            order: 0,
            groupType: .straight,
            sets: holds.enumerated().map { index, seconds in
                SetLog(
                    id: "prev-\(index)",
                    setNumber: index + 1,
                    setType: setType,
                    weightKg: 0,
                    reps: 0,
                    rpe: nil,
                    isPersonalRecord: false,
                    completedAt: Date(),
                    durationSeconds: seconds
                )
            },
            notes: nil
        )
    }

    // MARK: - Classification

    func testEffectiveTrackingModeFallsBackToEquipment() {
        XCTAssertEqual(makeExercise(id: "bench", equipment: [.barbell, .bench]).effectiveTrackingMode, .weightAndReps)
        XCTAssertEqual(makeExercise(id: "pull-up", equipment: [.pullUpBar, .bodyweight]).effectiveTrackingMode, .repsOnly)
    }

    func testExplicitTrackingModeWinsOverEquipmentDerivation() {
        let plank = makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)
        XCTAssertEqual(plank.effectiveTrackingMode, .timeHold)
        XCTAssertTrue(plank.tracksTime)
        XCTAssertTrue(plank.allowsUnloadedSets)
        XCTAssertFalse(plank.allowsWarmUpSets)

        // Bands carry reps but no kg, which equipment alone can't express.
        let band = makeExercise(id: "band-row", equipment: [.bands], trackingMode: .repsOnly)
        XCTAssertTrue(band.allowsUnloadedSets)
        XCTAssertFalse(band.allowsWarmUpSets)
    }

    func testSeededCatalogMarksHoldsAndUnloadedExercises() throws {
        // The shipped catalog is the source of truth for classification; a
        // regression here is what puts a 50% ramp back on pull-ups.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // LiftIQTests
            .deletingLastPathComponent()      // LiftIQ
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("firebase/functions/src/data/exercises.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let catalog = try decoder.decode([Exercise].self, from: data)

        let byId = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        XCTAssertEqual(byId["plank"]?.effectiveTrackingMode, .timeHold)
        XCTAssertEqual(byId["side-plank"]?.effectiveTrackingMode, .timeHold)
        XCTAssertEqual(byId["high-plank"]?.effectiveTrackingMode, .timeHold)
        XCTAssertEqual(byId["pull-ups"]?.effectiveTrackingMode, .repsOnly)
        XCTAssertEqual(byId["band-pull-apart"]?.effectiveTrackingMode, .repsOnly)
        XCTAssertEqual(byId["russian-twist"]?.effectiveTrackingMode, .repsOnly)
        XCTAssertEqual(byId["farmers-walk"]?.effectiveTrackingMode, .weightAndTime)
        XCTAssertEqual(byId["barbell-bench-press"]?.effectiveTrackingMode, .weightAndReps)

        // Nothing unloaded may claim a warm-up ramp.
        for exercise in catalog where !exercise.effectiveTrackingMode.requiresWeight {
            XCTAssertFalse(exercise.allowsWarmUpSets, "\(exercise.id) must not take warm-up sets")
        }
    }

    // MARK: - Warm-up suppression

    func testPlannerSkipsSynthesizedRampForUnloadedOpener() {
        let groups = [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-ups"),
            ], restBetweenRoundsSeconds: nil),
        ]
        let catalog = ["pull-ups": makeExercise(id: "pull-ups", equipment: [.pullUpBar, .bodyweight])]

        XCTAssertFalse(WarmUpPlanner.specs(forGroups: groups).isEmpty, "no catalog keeps the old behavior")
        XCTAssertTrue(WarmUpPlanner.specs(forGroups: groups, exercises: catalog).isEmpty)
    }

    func testPlannerDropsEvenExplicitWarmUpsForHolds() {
        let explicit = [WarmUpSet(id: "w1", percentageOf1RM: 0.5, reps: 8, label: "50%")]
        let groups = [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "plank", warmUpSets: explicit),
            ], restBetweenRoundsSeconds: nil),
        ]
        let catalog = ["plank": makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)]

        XCTAssertEqual(WarmUpPlanner.specs(forGroups: groups, exercises: catalog)["plank"]?.count, nil)
    }

    func testSessionCreateMakesNoWarmUpRowsForUnloadedOpener() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-ups", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let session = WorkoutSession.create(
            from: template,
            userId: "u1",
            planId: nil,
            exercises: ["pull-ups": makeExercise(id: "pull-ups", equipment: [.pullUpBar, .bodyweight])]
        )
        XCTAssertEqual(session.exerciseLogs[0].sets.map(\.setType), [.working, .working, .working])
    }

    func testViewModelInitUsesCatalogSoUnloadedOpenerGetsNoWarmUps() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-ups", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "pull-ups", equipment: [.pullUpBar, .bodyweight]),
        ])
        let vm = makeVM(template: template, exercise: exercise)
        defer { vm.stopTimers() }

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setType), [.working, .working, .working])
    }

    func testStartPrunesWarmUpsCreatedBeforeTheCatalogLoadedButKeepsCompletedOnes() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "pull-ups", sets: 2),
            ], restBetweenRoundsSeconds: nil),
        ])
        // A session built with no catalog (an older build, or a cold start)
        // carries the synthesized ramp.
        var existing = WorkoutSession.create(from: template, userId: "u1", planId: nil)
        XCTAssertEqual(existing.exerciseLogs[0].sets.map(\.setType), [.warmUp, .warmUp, .working, .working])
        existing.exerciseLogs[0].sets[0].reps = 8
        existing.exerciseLogs[0].sets[0].completedAt = Date()
        let keptId = existing.exerciseLogs[0].sets[0].id
        let prunedId = existing.exerciseLogs[0].sets[1].id

        let workout = FakeWorkoutService()
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "pull-ups", equipment: [.pullUpBar, .bodyweight]),
        ])
        let vm = WorkoutExecutionViewModel(
            existingSession: existing,
            workoutService: workout,
            exerciseService: exercise,
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }

        await vm.start(userUnitSystem: .metric)

        let types = vm.session.exerciseLogs[0].sets.map(\.setType)
        XCTAssertEqual(types, [.warmUp, .working, .working], "only the uncompleted warm-up is dropped")
        XCTAssertTrue(vm.session.exerciseLogs[0].sets.contains { $0.id == keptId })
        XCTAssertFalse(vm.session.exerciseLogs[0].sets.contains { $0.id == prunedId })
        XCTAssertNil(vm.setInputs[prunedId])
        // The first persisted copy already has the pruned shape.
        XCTAssertEqual(workout.startedSessions.first?.exerciseLogs[0].sets.count, 3)
    }

    // MARK: - Unloaded completion

    func testBandExerciseCompletesWithRepsAlone() async {
        let workout = FakeWorkoutService()
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "band-row", sets: 2),
            ], restBetweenRoundsSeconds: nil),
        ])
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "band-row", equipment: [.bands], trackingMode: .repsOnly),
        ])
        let vm = makeVM(template: template, workout: workout, exercise: exercise)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "15", rpe: "")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].reps, 15)
        XCTAssertNotNil(vm.session.exerciseLogs[0].sets[0].completedAt)
    }

    func testUnknownExerciseStillRequiresAWeight() async {
        // No catalog entry at all: the safe assumption is an ordinary loaded
        // lift, so ✓ must not log a 0 kg bench press.
        let workout = FakeWorkoutService()
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "mystery", sets: 2),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, workout: workout)
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "10", rpe: "")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertNil(vm.session.exerciseLogs[0].sets[0].completedAt)
    }

    // MARK: - Timed holds

    private func holdVM(
        workout: FakeWorkoutService? = nil,
        progress: FakeProgressService? = nil,
        repsMin: Int = 30,
        repsMax: Int = 60
    ) -> WorkoutExecutionViewModel {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "plank", sets: 3, repsMin: repsMin, repsMax: repsMax),
            ], restBetweenRoundsSeconds: nil),
        ])
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold),
        ])
        let vm = makeVM(template: template, workout: workout, exercise: exercise, progress: progress)
        vm.unitSystem = .metric
        return vm
    }

    func testHoldCompletesWithSecondsAndNoWeight() async {
        let workout = FakeWorkoutService()
        let vm = holdVM(workout: workout)
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "", rpe: "", duration: "45")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        let set = vm.session.exerciseLogs[0].sets[0]
        XCTAssertEqual(set.durationSeconds, 45)
        XCTAssertEqual(set.reps, 0, "a hold is never a rep count")
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertNotNil(set.completedAt)
        XCTAssertEqual(workout.updatedSessions.first?.exerciseLogs[0].sets[0].durationSeconds, 45)
    }

    func testHoldRefusesWithoutSecondsEvenWhenRepsAreTyped() async {
        let vm = holdVM()
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "10", rpe: "", duration: "")
        // No prescription to fall back on.
        vm.templateGroups = []
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertNil(vm.session.exerciseLogs[0].sets[0].completedAt)
    }

    func testEmptyHoldAdoptsThePlansPrescribedSeconds() async {
        let vm = holdVM(repsMin: 40, repsMax: 60)
        defer { vm.stopTimers() }

        XCTAssertEqual(vm.targetHoldSeconds(exerciseLogIndex: 0, setIndex: 0), 40)
        XCTAssertNil(vm.targetReps(exerciseLogIndex: 0, setIndex: 0), "a hold has no rep target")

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].durationSeconds, 40)
    }

    func testHoldIsCappedSoATypoCannotBecomeATenHourPlank() async {
        let vm = holdVM()
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "", rpe: "", duration: "99999")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].durationSeconds, Constants.maxHoldSeconds)
    }

    func testHoldEarnsADurationPersonalRecord() async {
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.duration]
        let vm = holdVM(progress: progress)
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "", rpe: "", duration: "50")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(progress.savedPRs.map(\.type), [.duration])
        XCTAssertEqual(progress.savedPRs.first?.value, 50)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].isPersonalRecord, true)
    }

    func testUncompletingAHoldClearsTheSeconds() async {
        let vm = holdVM()
        defer { vm.stopTimers() }

        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.setInputs[setId] = SetInput(weight: "", reps: "", rpe: "", duration: "45")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)
        await vm.uncompleteSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertNil(vm.session.exerciseLogs[0].sets[0].durationSeconds)
        XCTAssertEqual(vm.setInputs[setId]?.duration, "")
    }

    func testHoldGhostsTheProgressionTargetNotAWeight() async {
        let workout = FakeWorkoutService()
        workout.recentLogsByExerciseId["plank"] = [workingLog(exerciseId: "plank", holds: [30, 30, 25])]
        let vm = holdVM(workout: workout, repsMin: 30, repsMax: 60)
        defer { vm.stopTimers() }

        await vm.start(userUnitSystem: .metric)

        let setId = vm.session.exerciseLogs[0].sets[0].id
        // The ceiling of the prescription, ghosted behind an empty field.
        XCTAssertEqual(vm.suggestedSetInputs[setId]?.duration, "60")
        XCTAssertEqual(vm.suggestedSetInputs[setId]?.weight ?? "", "")
        XCTAssertTrue((vm.setInputs[setId] ?? SetInput()).duration.isEmpty, "ghosts never become typed text")
    }

    // MARK: - Hold progression

    func testProgressionTargetsThePrescribedCeilingWhileBelowIt() {
        let suggestion = ProgressionService().suggest(
            for: makePlanned(exerciseId: "plank", repsMin: 30, repsMax: 60),
            previousLogs: [workingLog(exerciseId: "plank", holds: [30, 28, 25])],
            exerciseInfo: makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)
        )
        XCTAssertEqual(suggestion?.reason, .hold(bestSeconds: 30, targetSeconds: 60))
        XCTAssertEqual(suggestion?.suggestedHoldSeconds, 60)
        XCTAssertEqual(suggestion?.suggestedWeight, 0, "a hold never suggests kilos")
    }

    func testProgressionAddsAStepOnceTheCeilingIsReached() {
        let suggestion = ProgressionService().suggest(
            for: makePlanned(exerciseId: "plank", repsMin: 30, repsMax: 60),
            previousLogs: [workingLog(exerciseId: "plank", holds: [60, 60, 55])],
            exerciseInfo: makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)
        )
        XCTAssertEqual(
            suggestion?.reason,
            .hold(bestSeconds: 60, targetSeconds: 60 + Constants.holdProgressionStepSeconds)
        )
    }

    func testRepRangeInheritedByAHoldBecomesASaneSecondsPrescription() {
        // Plans written before holds were prescribed in seconds — and any
        // slot a mid-workout swap turns into a plank — carry a rep range.
        // An 8-second plank is nobody's prescription.
        let repRange = makePlanned(exerciseId: "plank", repsMin: 8, repsMax: 10)
        let hold = HoldPrescription.seconds(for: repRange)
        XCTAssertEqual(hold.min, Constants.defaultHoldSeconds)
        XCTAssertEqual(hold.max, Constants.defaultHoldSeconds * 2)

        // A real seconds prescription is left alone.
        let seconds = makePlanned(exerciseId: "plank", repsMin: 20, repsMax: 45)
        XCTAssertEqual(HoldPrescription.seconds(for: seconds).min, 20)
        XCTAssertEqual(HoldPrescription.seconds(for: seconds).max, 45)
    }

    func testHoldInheritingARepRangeGhostsTheDefaultHold() async {
        let vm = holdVM(repsMin: 10, repsMax: 12)
        defer { vm.stopTimers() }

        XCTAssertEqual(vm.targetHoldSeconds(exerciseLogIndex: 0, setIndex: 0), Constants.defaultHoldSeconds)

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].durationSeconds, Constants.defaultHoldSeconds)
    }

    func testProgressionStaysQuietUntilAHoldHasBeenLogged() {
        let suggestion = ProgressionService().suggest(
            for: makePlanned(exerciseId: "plank", repsMin: 30, repsMax: 60),
            previousLogs: [workingLog(exerciseId: "plank", holds: [0])],
            exerciseInfo: makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)
        )
        XCTAssertNil(suggestion)
    }

    func testHoldNeverReportsAStall() {
        // Holds have no weight to back off from, so the acute stall branch
        // must stay out of their way entirely.
        let logs = (0..<5).map { _ in workingLog(exerciseId: "plank", holds: [20, 20, 20]) }
        let suggestion = ProgressionService().suggest(
            for: makePlanned(exerciseId: "plank", repsMin: 30, repsMax: 60),
            previousLogs: logs,
            exerciseInfo: makeExercise(id: "plank", equipment: [.bodyweight], trackingMode: .timeHold)
        )
        XCTAssertEqual(suggestion?.isStalled, false)
    }
}
