import XCTest
@testable import LiftIQ

@MainActor
final class WorkoutExecutionViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makePlanned(
        id: String = "p1",
        exerciseId: String = "bench-press",
        sets: Int = 3,
        restSeconds: Int = 90
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
            warmUpSets: nil,
            notes: nil,
            isOptional: false
        )
    }

    private func makeTemplate(
        groups: [ExerciseGroup]
    ) -> WorkoutTemplate {
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
        planId: String? = nil,
        workout: FakeWorkoutService? = nil,
        progress: FakeProgressService? = nil,
        exercise: FakeExerciseService? = nil
    ) -> WorkoutExecutionViewModel {
        WorkoutExecutionViewModel(
            template: template,
            userId: "u1",
            planId: planId,
            workoutService: workout ?? FakeWorkoutService(),
            exerciseService: exercise ?? FakeExerciseService(),
            progressService: progress ?? FakeProgressService(),
            progressionService: ProgressionService()
        )
    }

    /// Input helpers: setInputs is keyed by SetLog.id.
    private func input(_ vm: WorkoutExecutionViewModel, exercise: Int, set: Int) -> SetInput {
        vm.setInputs[vm.session.exerciseLogs[exercise].sets[set].id] ?? SetInput()
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

    // MARK: - WorkoutSession.create

    func testCreateSessionBuildsExerciseLogsInGroupOrder() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 4),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p3", exerciseId: "curl", sets: 3),
                makePlanned(id: "p4", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])

        let session = WorkoutSession.create(
            from: template, userId: "u1", planId: "plan-1"
        )

        XCTAssertEqual(session.exerciseLogs.count, 4)
        XCTAssertEqual(session.exerciseLogs.map(\.exerciseId),
                       ["bench-press", "barbell-row", "curl", "tricep-pushdown"])
        // First exercise of the first straight group gets 2 synthesized
        // warm-ups prepended to its planned working sets.
        XCTAssertEqual(session.exerciseLogs[0].sets.count, 5)
        XCTAssertEqual(session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .warmUp, .working, .working, .working])
        // Later exercises of a group get no warm-ups; superset groups never do.
        XCTAssertEqual(session.exerciseLogs[1].sets.count, 4)
        XCTAssertTrue(session.exerciseLogs[1].sets.allSatisfy { $0.setType == .working })
        XCTAssertEqual(session.exerciseLogs[2].sets.count, 3)
        XCTAssertTrue(session.exerciseLogs[2].sets.allSatisfy { $0.setType == .working })
        XCTAssertEqual(session.exerciseLogs[3].sets.count, 3)
        XCTAssertTrue(session.exerciseLogs[3].sets.allSatisfy { $0.setType == .working })
        // Order field is sequential across groups
        XCTAssertEqual(session.exerciseLogs.map(\.order), [0, 1, 2, 3])
        // GroupType propagates from the template group
        XCTAssertEqual(session.exerciseLogs[0].groupType, .straight)
        XCTAssertEqual(session.exerciseLogs[2].groupType, .superset)
    }

    func testCreateSessionStartsAllSetsAtZero() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])

        let session = WorkoutSession.create(
            from: template, userId: "u1", planId: nil
        )

        // 2 synthesized warm-ups precede the 3 planned working sets;
        // everything starts zeroed either way.
        XCTAssertEqual(session.exerciseLogs[0].sets.count, 5)
        for set in session.exerciseLogs[0].sets {
            XCTAssertEqual(set.weightKg, 0)
            XCTAssertEqual(set.reps, 0)
            XCTAssertNil(set.completedAt)
            XCTAssertFalse(set.isPersonalRecord)
        }
        XCTAssertEqual(session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .warmUp, .working, .working, .working])
        // setNumber counts within each set type: warm-ups 1...M, working 1...N
        XCTAssertEqual(session.exerciseLogs[0].sets.map(\.setNumber), [1, 2, 1, 2, 3])
    }

    func testCreateSessionBackfillsSessionIdIntoLogs() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        let session = WorkoutSession.create(
            from: template, userId: "u1", planId: nil
        )
        XCTAssertEqual(session.exerciseLogs[0].sessionId, session.id)
    }

    // MARK: - Rest fallback hierarchy

    func testRestUsesPlannedSecondsWhenAvailable() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        vm.userDefaultRestSeconds = 45 // user default should NOT win when planned is set

        // Sets are [warmUp, warmUp, working x3]; planned rest applies to
        // working sets. Completing only the first working set triggers rest
        // ("last set with everything completed" would suppress it).
        vm.session.exerciseLogs[0].sets[2].weightKg = 60
        vm.session.exerciseLogs[0].sets[2].reps = 10
        let setId = vm.session.exerciseLogs[0].sets[2].id
        vm.completedSetIds.insert(setId)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 2)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 120)
    }

    func testRestForWarmUpSetIsShortBreatherNotPlannedRest() {
        // Warm-up sets ignore the plan's working rest and take
        // min(userDefault, 60) instead; an explicit user override still rules.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(restSeconds: 180),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        vm.userDefaultRestSeconds = 90
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].setType, .warmUp)
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[0].id)

        var result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 60) // min(90, 60), not planned 180

        vm.userDefaultRestSeconds = 45
        result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertEqual(result.seconds, 45) // min(45, 60)

        vm.userRestOverride = 120
        result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertEqual(result.seconds, 120) // explicit override wins everywhere
    }

    func testRestFallsBackToUserDefaultWhenPlannedExerciseLookupFails() {
        // Build a template, then mutate the session so the exerciseLog points to
        // an exerciseId that no longer exists in the template's planned exercises.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(exerciseId: "bench-press", restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        vm.userDefaultRestSeconds = 75
        // Simulate a swap that changed the exerciseId; templateGroups still hold the old id
        vm.session.exerciseLogs[0].exerciseId = "different-exercise"
        // Target a working set (index 2): warm-up rows have their own rest rule.
        let setId = vm.session.exerciseLogs[0].sets[2].id
        vm.completedSetIds.insert(setId)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 2)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 75) // user default, not a hardcoded fallback
    }

    func testRestSuppressedAfterFinalSetWhenAllCompleted() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 2, restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        // Mark every set (2 warm-ups + 2 working) completed
        for s in vm.session.exerciseLogs[0].sets {
            vm.completedSetIds.insert(s.id)
        }

        let lastIndex = vm.session.exerciseLogs[0].sets.count - 1
        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: lastIndex)
        XCTAssertFalse(result.shouldTrigger)
    }

    func testUserRestOverrideBeatsPlannedRest() {
        // "I asked for 1 min rest in my settings" — an explicit profile rest
        // wins over the plan's per-exercise value.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        vm.userRestOverride = 60
        // Working set (index 2): warm-up rows never see planned rest anyway.
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[2].id)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 2)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 60)
    }

    func testUserRestOverrideBeatsGroupRoundRest() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, restSeconds: 30),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3, restSeconds: 30),
            ], restBetweenRoundsSeconds: 90),
        ])
        let vm = makeVM(template: template)
        vm.userRestOverride = 45
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[0].id)
        vm.completedSetIds.insert(vm.session.exerciseLogs[1].sets[0].id)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 45)
    }

    func testSupersetRestUsesGroupRestBetweenRounds() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, restSeconds: 30),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3, restSeconds: 30),
            ], restBetweenRoundsSeconds: 90),
        ])
        let vm = makeVM(template: template)
        vm.userDefaultRestSeconds = 60

        // Complete round 0 across both exercises
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[0].id)
        vm.completedSetIds.insert(vm.session.exerciseLogs[1].sets[0].id)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 90) // group rest, not user default
    }

    func testSupersetRestSuppressedIfPartnerNotCompletedThisRound() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, restSeconds: 30),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3, restSeconds: 30),
            ], restBetweenRoundsSeconds: 90),
        ])
        let vm = makeVM(template: template)

        // Complete only the first exercise in round 0
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[0].id)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertFalse(result.shouldTrigger)
    }

    // MARK: - Set add/remove

    func testAddSetAppendsAndRenumbers() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 2),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        // 2 synthesized warm-ups + 2 planned working sets
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 4)
        XCTAssertEqual(vm.setInputs.count, 4)

        vm.addSet(exerciseLogIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 5)
        let newSet = vm.session.exerciseLogs[0].sets[4]
        XCTAssertEqual(newSet.setType, .working)
        // Numbering counts within the working type: warm-ups don't inflate it
        XCTAssertEqual(newSet.setNumber, 3)
        // The new set gets fresh (empty) input storage keyed by its id
        XCTAssertEqual(vm.setInputs[newSet.id], SetInput())
        XCTAssertEqual(vm.setInputs.count, 5)
    }

    func testRemoveSetTrimsAndRenumbers() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        // Sets are [warmUp 1, warmUp 2, working 1, working 2, working 3].
        // Remove the middle working set (index 3).
        let removedId = vm.session.exerciseLogs[0].sets[3].id
        await vm.removeSet(exerciseLogIndex: 0, setIndex: 3)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 4)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setType),
                       [.warmUp, .warmUp, .working, .working])
        // Renumbering runs within each set type
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setNumber), [1, 2, 1, 2])
        XCTAssertNil(vm.setInputs[removedId])
        XCTAssertEqual(vm.setInputs.count, 4)
    }

    func testRemoveSetRefusesToEmptyExercise() async {
        // The second exercise of a group gets no warm-ups, so with sets: 1 it
        // genuinely has a single set to defend.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 1),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        XCTAssertEqual(vm.session.exerciseLogs[1].sets.count, 1)

        await vm.removeSet(exerciseLogIndex: 1, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[1].sets.count, 1) // unchanged
    }

    // MARK: - Group mapping

    func testGroupMappingExposedHelpers() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned(id: "p1")],
                          restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2"), makePlanned(id: "p3"),
            ], restBetweenRoundsSeconds: 60),
        ])
        let vm = makeVM(template: template)

        XCTAssertEqual(vm.groupIndex(for: 0), 0)
        XCTAssertEqual(vm.groupIndex(for: 1), 1)
        XCTAssertEqual(vm.groupIndex(for: 2), 1)
        XCTAssertEqual(vm.exerciseLogIndices(forGroupIndex: 1), [1, 2])
        XCTAssertEqual(vm.groupType(for: 0), .straight)
        XCTAssertEqual(vm.groupType(for: 1), .superset)
        XCTAssertTrue(vm.isFirstInGroup(0))
        XCTAssertTrue(vm.isFirstInGroup(1))
        XCTAssertFalse(vm.isFirstInGroup(2))
    }

    // MARK: - Progression suggestions

    /// Helper: build a previous log where every working set hit max reps so
    /// ProgressionService.suggest() returns a weight-bump suggestion.
    private func makePriorLogAtMaxReps(
        exerciseId: String,
        repsMax: Int = 10,
        weightKg: Double = 60,
        setCount: Int = 3
    ) -> ExerciseLog {
        let sets = (1...setCount).map { i in
            SetLog(
                id: "prior-set-\(i)",
                setNumber: i,
                setType: .working,
                weightKg: weightKg,
                reps: repsMax,
                rpe: nil,
                isPersonalRecord: false,
                completedAt: Date()
            )
        }
        return ExerciseLog(
            id: "prior-log-1",
            sessionId: "prior-session",
            exerciseId: exerciseId,
            exerciseName: exerciseId,
            order: 1,
            groupType: .straight,
            sets: sets,
            notes: nil
        )
    }

    private func makePriorLogBelowMin(
        exerciseId: String,
        repsMin: Int = 8,
        weightKg: Double = 60,
        setCount: Int = 3
    ) -> ExerciseLog {
        let sets = (1...setCount).map { i in
            SetLog(
                id: "fail-set-\(i)",
                setNumber: i,
                setType: .working,
                weightKg: weightKg,
                reps: repsMin - 2, // below min
                rpe: nil,
                isPersonalRecord: false,
                completedAt: Date()
            )
        }
        return ExerciseLog(
            id: "fail-log",
            sessionId: "fail-session",
            exerciseId: exerciseId,
            exerciseName: exerciseId,
            order: 1,
            groupType: .straight,
            sets: sets,
            notes: nil
        )
    }

    func testComputeSuggestionsBumpsWeightWhenAllSetsHitMax() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        let priorLog = makePriorLogAtMaxReps(exerciseId: "bench-press", repsMax: 10, weightKg: 60)

        vm.computeSuggestions(recentLogs: ["bench-press": [priorLog]])

        let suggestion = vm.progressionSuggestions["bench-press"]
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5) // +2.5 kg barbell increment
        XCTAssertFalse(suggestion?.isPlateaued ?? true)
    }

    func testComputeSuggestionsEmitsPlateauWhenThreeConsecutiveFailures() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        let failLog = makePriorLogBelowMin(exerciseId: "bench-press", repsMin: 8)
        let recentLogs = Array(repeating: failLog, count: Constants.plateauThreshold)

        vm.computeSuggestions(recentLogs: ["bench-press": recentLogs])

        let suggestion = vm.progressionSuggestions["bench-press"]
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.isPlateaued ?? false)
    }

    func testComputeSuggestionsSkipsExerciseWithNoHistory() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        vm.computeSuggestions(recentLogs: [:])

        XCTAssertNil(vm.progressionSuggestions["bench-press"])
    }

    func testComputeSuggestionsClearsStaleEntries() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        // Seed a stale entry that should be cleared on next compute
        vm.progressionSuggestions["old-exercise"] = ProgressionSuggestion(
            exerciseId: "old-exercise",
            suggestedWeight: 100,
            suggestedRepsMin: 8,
            suggestedRepsMax: 10,
            message: "stale",
            isPlateaued: false
        )

        vm.computeSuggestions(recentLogs: [:])

        XCTAssertNil(vm.progressionSuggestions["old-exercise"])
    }

    // MARK: - Async flows via fakes

    private func makeExercise(id: String, name: String? = nil) -> Exercise {
        Exercise(
            id: id,
            name: name ?? id.capitalized,
            primaryMuscleGroup: .chest,
            secondaryMuscleGroups: [],
            equipment: [.barbell],
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

    private func makeBenchVM(
        sets: Int = 3,
        workout: FakeWorkoutService? = nil,
        progress: FakeProgressService? = nil,
        exercise: FakeExerciseService? = nil
    ) -> WorkoutExecutionViewModel {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: sets),
            ], restBetweenRoundsSeconds: nil),
        ])
        return makeVM(template: template, workout: workout, progress: progress, exercise: exercise)
    }

    // MARK: start()

    func testStartLoadsDetailsAndPreviousLogsExcludingInFlightSession() async throws {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        let exercise = FakeExerciseService(exercises: [makeExercise(id: "bench-press", name: "Bench Press")])
        let prior = makePriorLogAtMaxReps(exerciseId: "bench-press", repsMax: 10, weightKg: 60)
        workout.recentLogsByExerciseId["bench-press"] = [prior]
        let vm = makeBenchVM(workout: workout, progress: progress, exercise: exercise)
        defer { vm.stopTimers() }

        await vm.start(userUnitSystem: .metric)

        XCTAssertEqual(workout.startedSessions.map(\.id), [vm.session.id])
        XCTAssertEqual(vm.exerciseDetails["bench-press"]?.name, "Bench Press")
        XCTAssertEqual(vm.session.exerciseLogs[0].exerciseName, "Bench Press")
        XCTAssertEqual(vm.previousLogs["bench-press"]?.id, prior.id)
        // Suggestion computed from the batched map (all prior sets hit max reps)
        XCTAssertEqual(vm.progressionSuggestions["bench-press"]?.suggestedWeight, 62.5)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)

        // The single batched history fetch must exclude the in-flight session
        XCTAssertEqual(workout.recentLogsRequests.count, 1)
        let request = try XCTUnwrap(workout.recentLogsRequests.first)
        XCTAssertEqual(request.excludingSessionId, vm.session.id)
        XCTAssertEqual(request.exerciseIds, ["bench-press"])
        XCTAssertEqual(request.userId, "u1")
    }

    func testStartFailureSetsErrorAndAllowsRetry() async {
        let workout = FakeWorkoutService()
        let exercise = FakeExerciseService(exercises: [makeExercise(id: "bench-press")])
        let vm = makeBenchVM(workout: workout, exercise: exercise)
        defer { vm.stopTimers() }
        workout.startSessionError = FakeServiceError(message: "offline")

        await vm.start(userUnitSystem: .metric)

        XCTAssertEqual(vm.errorMessage, "offline")
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(workout.startedSessions.isEmpty)

        // hasStarted must reset on failure so a retry actually runs
        workout.startSessionError = nil
        vm.errorMessage = nil

        await vm.start(userUnitSystem: .metric)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(workout.startedSessions.count, 1)
    }

    // MARK: resume rebuild

    func testStartOnResumedSessionRebuildsTemplateGroupsFromPlan() async {
        // A resumed session (init(existingSession:)) has no template context.
        // start() must find the plan/template again so superset rest works.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, restSeconds: 30),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3, restSeconds: 30),
            ], restBetweenRoundsSeconds: 90),
        ])
        let plan = WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Test Plan",
            templateType: .fullBody,
            goal: .hypertrophy,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: [template],
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: false,
            aiPromptContext: nil
        )
        let workout = FakeWorkoutService()
        workout.plans = [plan]
        workout.recentLogsByExerciseId["ex-a"] = [makePriorLogAtMaxReps(exerciseId: "ex-a", repsMax: 10, weightKg: 40)]
        let existing = WorkoutSession.create(from: template, userId: "u1", planId: "plan-1")

        let vm = WorkoutExecutionViewModel(
            existingSession: existing,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }
        XCTAssertTrue(vm.templateGroups.isEmpty) // resume starts without context

        await vm.start(userUnitSystem: .metric)

        // Template context restored
        XCTAssertEqual(vm.templateGroups.count, 1)
        XCTAssertEqual(vm.groupIndex(for: 0), 0)
        XCTAssertEqual(vm.groupIndex(for: 1), 0)
        // Suggestions work again because plannedExercise() can resolve
        XCTAssertEqual(vm.progressionSuggestions["ex-a"]?.suggestedWeight, 42.5)

        // Superset rest logic works: rest triggers only when the round is done
        vm.completedSetIds.insert(vm.session.exerciseLogs[0].sets[0].id)
        XCTAssertFalse(vm.restDuration(forExerciseLogIndex: 0, setIndex: 0).shouldTrigger)
        vm.completedSetIds.insert(vm.session.exerciseLogs[1].sets[0].id)
        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 90)
    }

    func testStartOnResumedSessionDegradesGracefullyWhenPlanMissing() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 2),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 2),
            ], restBetweenRoundsSeconds: 90),
        ])
        let workout = FakeWorkoutService() // no plans seeded — lookup fails
        let existing = WorkoutSession.create(from: template, userId: "u1", planId: "plan-gone")

        let vm = WorkoutExecutionViewModel(
            existingSession: existing,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { vm.stopTimers() }

        await vm.start(userUnitSystem: .metric)

        // No crash, no error, just the pre-existing straight-set behavior
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.templateGroups.isEmpty)
        XCTAssertTrue(vm.exerciseGroupMap.isEmpty)
    }

    // MARK: completeSet()

    func testCompleteSetPersistsViaServiceAndMarksCompleted() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 0, weight: "100", reps: "5")

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        let set = vm.session.exerciseLogs[0].sets[0]
        XCTAssertEqual(set.weightKg, 100)
        XCTAssertEqual(set.reps, 5)
        XCTAssertNotNil(set.completedAt)
        XCTAssertTrue(vm.completedSetIds.contains(set.id))
        XCTAssertEqual(workout.updatedSessions.count, 1)
        XCTAssertEqual(workout.updatedSessions.first?.exerciseLogs[0].sets[0].weightKg, 100)
        XCTAssertNil(vm.errorMessage)
    }

    func testCompleteSetAdoptsGhostValuesWhenInputsEmpty() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        vm.previousLogs["bench-press"] = makePriorLogAtMaxReps(
            exerciseId: "bench-press", repsMax: 10, weightKg: 60
        )
        // Inputs deliberately left empty: placeholders read "repeat last time".
        // Index 2 is the first working set (warm-ups occupy 0-1); ghost values
        // come from the previous session's first working set.

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        let set = vm.session.exerciseLogs[0].sets[2]
        XCTAssertEqual(set.weightKg, 60)
        XCTAssertEqual(set.reps, 10)
        XCTAssertTrue(vm.completedSetIds.contains(set.id))
        // Inputs are backfilled so the UI shows what was logged
        XCTAssertEqual(Double(input(vm, exercise: 0, set: 2).weight), 60)
        XCTAssertEqual(input(vm, exercise: 0, set: 2).reps, "10")
        XCTAssertEqual(workout.updatedSessions.count, 1)
    }

    func testCompleteWarmUpSetDoesNotAdoptWorkingGhostValues() async {
        // The previous session logged only working sets, so a warm-up row has
        // no type-matching ghost to adopt — completing it empty must refuse
        // rather than bleed working weights into the warm-up.
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        vm.previousLogs["bench-press"] = makePriorLogAtMaxReps(
            exerciseId: "bench-press", repsMax: 10, weightKg: 60
        )
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].setType, .warmUp)

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        let set = vm.session.exerciseLogs[0].sets[0]
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertNil(set.completedAt)
        XCTAssertFalse(vm.completedSetIds.contains(set.id))
        XCTAssertTrue(workout.updatedSessions.isEmpty)
    }

    func testCompleteSetRefusesWithoutInputsOrHistory() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2) // first working set

        let set = vm.session.exerciseLogs[0].sets[2]
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertNil(set.completedAt)
        XCTAssertTrue(vm.completedSetIds.isEmpty)
        XCTAssertTrue(workout.updatedSessions.isEmpty) // nothing persisted
    }

    func testCompleteSetDetectsPRAndFlagsSet() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        progress.existingPRsByExerciseId["bench-press"] = [] // no prior records
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // first working set

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertEqual(vm.sessionPRs.count, 1)
        XCTAssertEqual(vm.newPR?.type, .weight)
        XCTAssertEqual(vm.newPR?.value, 100)
        XCTAssertTrue(vm.session.exerciseLogs[0].sets[2].isPersonalRecord)
        // The set remembers exactly which records it created
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[2].personalRecordIds, vm.sessionPRs.map(\.id))
        XCTAssertEqual(progress.savedPRs.count, 1)
        // The PR check received the session-cached existing records
        XCTAssertEqual(progress.checkForPRsCalls.count, 1)
        XCTAssertEqual(progress.checkForPRsCalls.first?.existingPRs.count, 0)
        // And the persisted session carries the flag
        XCTAssertEqual(workout.updatedSessions.first?.exerciseLogs[0].sets[2].isPersonalRecord, true)
    }

    func testCompleteWarmUpSetSkipsPRDetection() async {
        // Warm-up sets never earn PRs, even at PR-worthy loads.
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 0, weight: "100", reps: "5")
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].setType, .warmUp)

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        // The set completes and persists, but no PR machinery ran
        XCTAssertTrue(vm.completedSetIds.contains(vm.session.exerciseLogs[0].sets[0].id))
        XCTAssertEqual(workout.updatedSessions.count, 1)
        XCTAssertTrue(progress.checkForPRsCalls.isEmpty)
        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertNil(vm.newPR)
        XCTAssertFalse(vm.session.exerciseLogs[0].sets[0].isPersonalRecord)
    }

    func testCompleteSetPRCheckFailureDoesNotBlockPersistence() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.getExercisePRsError = FakeServiceError(message: "pr lookup down")
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // working set

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertNil(vm.newPR)
        XCTAssertFalse(vm.session.exerciseLogs[0].sets[2].isPersonalRecord)
        // The set still persists and completes locally
        XCTAssertEqual(workout.updatedSessions.count, 1)
        XCTAssertTrue(vm.completedSetIds.contains(vm.session.exerciseLogs[0].sets[2].id))
        XCTAssertNil(vm.errorMessage) // PR detection is best-effort
    }

    func testCompleteSetSaveFailureSetsErrorButKeepsLocalCompletion() async {
        let workout = FakeWorkoutService()
        workout.updateSessionError = FakeServiceError(message: "network down")
        let vm = makeBenchVM(workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 0, weight: "100", reps: "5")

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.errorMessage, "Failed to save: network down")
        // Local state keeps the completion so the lifter's data isn't lost
        let set = vm.session.exerciseLogs[0].sets[0]
        XCTAssertEqual(set.weightKg, 100)
        XCTAssertTrue(vm.completedSetIds.contains(set.id))
    }

    // MARK: uncompleteSet()

    func testUncompleteSetRollsBackPRAndDeletesRecord() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // working set

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        XCTAssertEqual(vm.sessionPRs.count, 1)
        let prId = vm.sessionPRs[0].id

        await vm.uncompleteSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertEqual(progress.deletedRecordIds, [prId])
        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertNil(vm.newPR)
        let set = vm.session.exerciseLogs[0].sets[2]
        XCTAssertFalse(vm.completedSetIds.contains(set.id))
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertEqual(set.reps, 0)
        XCTAssertFalse(set.isPersonalRecord)
        XCTAssertNil(set.personalRecordIds)
        XCTAssertNil(set.completedAt)
        XCTAssertEqual(input(vm, exercise: 0, set: 2).weight, "")
        // Uncompleting persists the reverted session too
        XCTAssertEqual(workout.updatedSessions.count, 2)
    }

    func testUncompleteSetDeletesOnlyItsOwnPRsWhenValuesAreIdentical() async {
        // Two working sets at the same weight each produce a "PR" record (the
        // fake detects unconditionally). Uncompleting the first must delete
        // only the record ids stored on that set — identity, not value match.
        // Working sets sit at indices 2 and 3 behind the two warm-ups.
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5")
        seedInput(vm, exercise: 0, set: 3, weight: "100", reps: "5")

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 3)
        XCTAssertEqual(vm.sessionPRs.count, 2)
        XCTAssertEqual(vm.sessionPRs[0].value, vm.sessionPRs[1].value) // identical values
        let firstSetPRIds = vm.session.exerciseLogs[0].sets[2].personalRecordIds ?? []
        let secondSetPRIds = vm.session.exerciseLogs[0].sets[3].personalRecordIds ?? []
        XCTAssertEqual(firstSetPRIds.count, 1)

        await vm.uncompleteSet(exerciseLogIndex: 0, setIndex: 2)

        // Only the first set's record was deleted
        XCTAssertEqual(progress.deletedRecordIds, firstSetPRIds)
        XCTAssertEqual(vm.sessionPRs.map(\.id), secondSetPRIds)
        // The second set keeps its PR state untouched
        XCTAssertTrue(vm.session.exerciseLogs[0].sets[3].isPersonalRecord)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[3].personalRecordIds, secondSetPRIds)
    }

    // MARK: abandonWorkout()

    func testAbandonWorkoutDeletesSessionPRsAndPersistsAbandon() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // working set

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        XCTAssertEqual(vm.sessionPRs.count, 1)
        let prId = vm.sessionPRs[0].id

        await vm.abandonWorkout()

        XCTAssertEqual(progress.deletedRecordIds, [prId])
        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertNil(vm.newPR)
        XCTAssertEqual(workout.abandonedSessions.map(\.id), [vm.session.id])
        XCTAssertNil(vm.errorMessage)
    }

    func testAbandonWorkoutStillAbandonsWhenPRDeletionFails() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // working set
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        XCTAssertEqual(vm.sessionPRs.count, 1) // a PR exists to (fail to) delete

        progress.deleteRecordError = FakeServiceError(message: "delete down")
        await vm.abandonWorkout()

        // Deletion is best effort; abandoning must still go through
        XCTAssertTrue(progress.deletedRecordIds.isEmpty)
        XCTAssertEqual(workout.abandonedSessions.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - PR rollback across resume/swap/remove

    /// Builds a resumed VM whose first *working* set (index 2, behind the two
    /// warm-ups) is completed and stamped with PR ids, mirroring a relaunch:
    /// `personalRecordIds` persisted on the session but `sessionPRs` empty
    /// because the records were never re-fetched.
    private func makeResumedVMWithStampedPRs(
        workout: FakeWorkoutService,
        progress: FakeProgressService,
        prIds: [String]
    ) -> WorkoutExecutionViewModel {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        var existing = WorkoutSession.create(from: template, userId: "u1", planId: nil)
        existing.exerciseLogs[0].sets[2].weightKg = 100
        existing.exerciseLogs[0].sets[2].reps = 5
        existing.exerciseLogs[0].sets[2].isPersonalRecord = true
        existing.exerciseLogs[0].sets[2].personalRecordIds = prIds

        return WorkoutExecutionViewModel(
            existingSession: existing,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: progress,
            progressionService: ProgressionService()
        )
    }

    func testUncompleteSetOnResumedSessionDeletesPersistedPRs() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        let vm = makeResumedVMWithStampedPRs(workout: workout, progress: progress,
                                             prIds: ["pr-1", "pr-2"])
        defer { vm.stopTimers() }
        XCTAssertTrue(vm.sessionPRs.isEmpty) // resume: records not in memory

        await vm.uncompleteSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertEqual(progress.deletedRecordIds.sorted(), ["pr-1", "pr-2"])
        XCTAssertNil(vm.session.exerciseLogs[0].sets[2].personalRecordIds)
        XCTAssertFalse(vm.session.exerciseLogs[0].sets[2].isPersonalRecord)
    }

    func testAbandonWorkoutOnResumedSessionDeletesStampedPRs() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        let vm = makeResumedVMWithStampedPRs(workout: workout, progress: progress,
                                             prIds: ["pr-1"])
        defer { vm.stopTimers() }
        XCTAssertTrue(vm.sessionPRs.isEmpty)

        await vm.abandonWorkout()

        XCTAssertEqual(progress.deletedRecordIds, ["pr-1"])
        XCTAssertEqual(workout.abandonedSessions.count, 1)
    }

    func testSwapExerciseDeletesPRDocsOfResetSets() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // working set
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        let prIds = vm.session.exerciseLogs[0].sets[2].personalRecordIds ?? []
        XCTAssertEqual(prIds.count, 1)

        vm.requestSwap(exerciseLogIndex: 0)
        await vm.swapExercise(newExercise: makeExercise(id: "incline-press", name: "Incline Press"))

        XCTAssertEqual(progress.deletedRecordIds, prIds)
        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertNil(vm.session.exerciseLogs[0].sets[2].personalRecordIds)
    }

    func testRemoveSetDeletesItsPRDocs() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let vm = makeBenchVM(workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        let lastIndex = vm.session.exerciseLogs[0].sets.count - 1
        seedInput(vm, exercise: 0, set: lastIndex, weight: "100", reps: "5")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: lastIndex)
        let prIds = vm.session.exerciseLogs[0].sets[lastIndex].personalRecordIds ?? []
        XCTAssertEqual(prIds.count, 1)

        await vm.removeSet(exerciseLogIndex: 0, setIndex: lastIndex)

        XCTAssertEqual(progress.deletedRecordIds, prIds)
        XCTAssertTrue(vm.sessionPRs.isEmpty)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, lastIndex)
    }

    // MARK: - Scroll target

    func testScrollToExerciseLogIndexIsNilByDefault() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        XCTAssertNil(vm.scrollToExerciseLogIndex)
    }

    func testScrollToExerciseLogIndexCanBePreservedAcrossInit() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1"),
                makePlanned(id: "p2"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        vm.scrollToExerciseLogIndex = 1
        XCTAssertEqual(vm.scrollToExerciseLogIndex, 1)
    }
}
