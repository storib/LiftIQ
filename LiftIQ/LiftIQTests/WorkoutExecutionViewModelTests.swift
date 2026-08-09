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

    private func makePlan(workouts: [WorkoutTemplate]) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Test Plan",
            templateType: .fullBody,
            goal: .hypertrophy,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: workouts,
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: false,
            aiPromptContext: nil
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
        XCTAssertFalse(suggestion?.isStalled ?? true)
    }

    func testComputeSuggestionsEmitsStallWhenThreeConsecutiveFailuresAtSameWeight() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)
        let failLog = makePriorLogBelowMin(exerciseId: "bench-press", repsMin: 8)
        let recentLogs = Array(repeating: failLog, count: Constants.stallThreshold)

        vm.computeSuggestions(recentLogs: ["bench-press": recentLogs])

        let suggestion = vm.progressionSuggestions["bench-press"]
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.isStalled ?? false)
        // The stall response is a back-off probe, not a hold at the stuck
        // weight: 60 * 0.9 = 54 → rounded down to the 2.5 kg increment.
        XCTAssertEqual(suggestion?.suggestedWeight, 52.5)
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
            isStalled: false
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

    // MARK: - applyModifiedWorkout()

    func testWorkoutForAIModificationReflectsLiveExerciseAndSetEdits() {
        let vm = makeBenchVM(sets: 3)
        defer { vm.stopTimers() }
        vm.session.exerciseLogs[0].exerciseId = "incline-press"
        vm.addSet(exerciseLogIndex: 0)

        let current = vm.workoutForAIModification

        XCTAssertEqual(current?.exerciseGroups[0].exercises[0].exerciseId, "incline-press")
        XCTAssertEqual(current?.exerciseGroups[0].exercises[0].sets, 4)
    }

    func testApplyModifiedWorkoutGrowsWorkingSetsAndKeepsCompletedWork() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // first working set
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        let completedSetId = vm.session.exerciseLogs[0].sets[2].id

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 5),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        // 2 original warm-ups survive; working sets grew 3 -> 5.
        let sets = vm.session.exerciseLogs[0].sets
        XCTAssertEqual(sets.count { $0.setType == .warmUp }, 2)
        XCTAssertEqual(sets.count { $0.setType == .working }, 5)
        // The completed set is untouched, id and all.
        XCTAssertEqual(sets[2].id, completedSetId)
        XCTAssertEqual(sets[2].weightKg, 100)
        XCTAssertTrue(vm.completedSetIds.contains(completedSetId))
        // Working sets renumber 1...5 within their type.
        XCTAssertEqual(sets.filter { $0.setType == .working }.map(\.setNumber), [1, 2, 3, 4, 5])
        // The change persisted (completeSet saved once before).
        XCTAssertEqual(workout.updatedSessions.count, 2)
        XCTAssertEqual(vm.template?.id, modified.id)
    }

    func testApplyModifiedWorkoutTrimsOnlyUncompletedWorkingSets() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        let completedSetId = vm.session.exerciseLogs[0].sets[2].id

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 1),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        // The two uncompleted working sets were trimmed; the completed one stays.
        let working = vm.session.exerciseLogs[0].sets.filter { $0.setType == .working }
        XCTAssertEqual(working.map(\.id), [completedSetId])
        XCTAssertEqual(working[0].weightKg, 100)
    }

    func testApplyModifiedWorkoutKeepsRemovedExerciseWithCompletedWorkAsStraightSets() async {
        let workout = FakeWorkoutService()
        let progress = FakeProgressService()
        progress.prTypesToDetect = [.weight]
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, workout: workout, progress: progress)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "5") // bench working set
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)
        let benchPRIds = vm.session.exerciseLogs[0].sets[2].personalRecordIds ?? []
        XCTAssertEqual(benchPRIds.count, 1)

        // The AI removes bench-press entirely.
        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        // Row leads (template order); the completed bench work survives at the
        // end, holding only its completed set, and its PR stamp is untouched.
        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["barbell-row", "bench-press"])
        let orphan = vm.session.exerciseLogs[1]
        XCTAssertEqual(orphan.sets.count, 1)
        XCTAssertEqual(orphan.sets[0].weightKg, 100)
        XCTAssertEqual(orphan.sets[0].personalRecordIds, benchPRIds)
        XCTAssertEqual(orphan.groupType, .straight)
        XCTAssertTrue(progress.deletedRecordIds.isEmpty)
        XCTAssertEqual(vm.session.exerciseLogs.map(\.order), [0, 1])
    }

    func testApplyModifiedWorkoutDropsRemovedExerciseWithoutCompletedWork() async {
        let workout = FakeWorkoutService()
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, workout: workout)
        defer { vm.stopTimers() }
        let rowSetIds = vm.session.exerciseLogs[1].sets.map(\.id)

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["bench-press"])
        // The dropped sets' inputs went with them.
        for setId in rowSetIds {
            XCTAssertNil(vm.setInputs[setId])
        }
        XCTAssertEqual(workout.updatedSessions.count, 1)
    }

    func testApplyModifiedWorkoutAddsNewExerciseWithGhostsAndPrefill() async {
        let workout = FakeWorkoutService()
        workout.recentLogsByExerciseId["incline-press"] = [
            makePriorLogAtMaxReps(exerciseId: "incline-press", repsMax: 10, weightKg: 40)
        ]
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "bench-press", name: "Bench Press"),
            makeExercise(id: "incline-press", name: "Incline Press"),
        ])
        let vm = makeBenchVM(sets: 3, workout: workout, exercise: exercise)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p3", exerciseId: "incline-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["bench-press", "incline-press"])
        let added = vm.session.exerciseLogs[1]
        XCTAssertEqual(added.exerciseName, "Incline Press")
        XCTAssertEqual(added.sessionId, vm.session.id)
        XCTAssertEqual(added.sets.count { $0.setType == .working }, 3)
        // History ghost and progression state arrived for the new exercise.
        XCTAssertNotNil(vm.previousLogs["incline-press"])
        XCTAssertNotNil(vm.exerciseDetails["incline-press"])
        // The suggestion (40 kg + 2.5 bump) lands in the ghost layer; the
        // editable field itself stays empty so the user never has to delete
        // pre-filled text.
        let firstWorking = added.sets.first { $0.setType == .working }!
        XCTAssertTrue((vm.setInputs[firstWorking.id] ?? SetInput()).weight.isEmpty)
        XCTAssertEqual(vm.suggestedSetInputs[firstWorking.id]?.weight, "42.5")
    }

    func testCompleteSetAdoptsSuggestedGhostWeight() async {
        let workout = FakeWorkoutService()
        workout.recentLogsByExerciseId["incline-press"] = [
            makePriorLogAtMaxReps(exerciseId: "incline-press", repsMax: 10, weightKg: 40)
        ]
        let exercise = FakeExerciseService(exercises: [
            makeExercise(id: "bench-press", name: "Bench Press"),
            makeExercise(id: "incline-press", name: "Incline Press"),
        ])
        let vm = makeBenchVM(sets: 3, workout: workout, exercise: exercise)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p3", exerciseId: "incline-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        let inclineIndex = vm.session.exerciseLogs.firstIndex { $0.exerciseId == "incline-press" }!
        let setIndex = vm.session.exerciseLogs[inclineIndex].sets.firstIndex { $0.setType == .working }!
        await vm.completeSet(exerciseLogIndex: inclineIndex, setIndex: setIndex)

        // ✓ on empty fields adopts the suggested ghost weight (42.5 kg) and
        // the previous-session ghost reps.
        XCTAssertEqual(vm.session.exerciseLogs[inclineIndex].sets[setIndex].weightKg, 42.5, accuracy: 0.001)
        XCTAssertEqual(vm.session.exerciseLogs[inclineIndex].sets[setIndex].reps, 10)
    }

    func testApplyModifiedWorkoutRebuildsGroupContext() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }

        // The AI pairs bench with a new row as a superset.
        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        await vm.applyModifiedWorkout(modified)

        XCTAssertEqual(vm.groupIndex(for: 0), 0)
        XCTAssertEqual(vm.groupIndex(for: 1), 0)
        XCTAssertEqual(vm.groupType(for: 0), .superset)
        XCTAssertEqual(vm.session.exerciseLogs[0].groupType, .superset)
        XCTAssertEqual(vm.session.workoutName, modified.name)
    }

    func testApplyModifiedWorkoutRemovesPendingWarmUpsWhenExerciseBecomesSuperset() async {
        let workout = FakeWorkoutService()
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 0, weight: "20", reps: "8")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 0)
        let completedWarmUpId = vm.session.exerciseLogs[0].sets[0].id

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        await vm.applyModifiedWorkout(modified)

        let bench = vm.session.exerciseLogs[0]
        XCTAssertEqual(bench.sets.filter { $0.setType == .warmUp }.map(\.id), [completedWarmUpId])
        XCTAssertEqual(bench.sets.count { $0.setType == .working }, 3)
        XCTAssertTrue(vm.session.exerciseLogs[1].sets.allSatisfy { $0.setType == .working })

        let benchWorkingIndex = bench.sets.firstIndex { $0.setType == .working }!
        let benchWorkingId = bench.sets[benchWorkingIndex].id
        let rowWorkingId = vm.session.exerciseLogs[1].sets[0].id
        vm.completedSetIds.insert(benchWorkingId)
        vm.completedSetIds.insert(rowWorkingId)
        let rest = vm.restDuration(forExerciseLogIndex: 0, setIndex: benchWorkingIndex)
        XCTAssertTrue(rest.shouldTrigger)
        XCTAssertEqual(rest.seconds, 60)
    }

    func testApplyModifiedWorkoutPreservesTypedWeightDuringPrefill() async {
        let workout = FakeWorkoutService()
        workout.recentLogsByExerciseId["bench-press"] = [
            makePriorLogAtMaxReps(exerciseId: "bench-press", repsMax: 10, weightKg: 40)
        ]
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }
        vm.unitSystem = .metric
        seedInput(vm, exercise: 0, set: 2, weight: "37.5", reps: "8")

        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 4),
            ], restBetweenRoundsSeconds: nil),
        ])
        await vm.applyModifiedWorkout(modified)

        XCTAssertEqual(input(vm, exercise: 0, set: 2).weight, "37.5")
    }

    func testApplyModifiedWorkoutRecomputesSuggestionForNewRepRange() async {
        let workout = FakeWorkoutService()
        let recent = makePriorLogAtMaxReps(
            exerciseId: "bench-press",
            repsMax: 10,
            weightKg: 40
        )
        workout.recentLogsByExerciseId["bench-press"] = [recent]
        let vm = makeBenchVM(sets: 3, workout: workout)
        defer { vm.stopTimers() }
        vm.computeSuggestions(recentLogs: ["bench-press": [recent]])
        XCTAssertEqual(vm.progressionSuggestions["bench-press"]?.suggestedWeight, 42.5)

        var planned = makePlanned(id: "p1", exerciseId: "bench-press", sets: 3)
        planned.repsMax = 12
        let modified = makeTemplate(groups: [
            ExerciseGroup(
                id: "g1",
                groupType: .straight,
                exercises: [planned],
                restBetweenRoundsSeconds: nil
            ),
        ])
        await vm.applyModifiedWorkout(modified)

        XCTAssertEqual(vm.progressionSuggestions["bench-press"]?.suggestedWeight, 40)
        XCTAssertEqual(vm.progressionSuggestions["bench-press"]?.suggestedRepsMax, 12)
        XCTAssertEqual(workout.recentLogsRequests.last?.exerciseIds, ["bench-press"])
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

    // MARK: - First-workout rep targets

    func testTargetRepsComesFromPlanForWorkingSetsOnly() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned(sets: 3)],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        // Sets 0-1 are synthesized warm-ups; 2-4 are working sets.
        XCTAssertNil(vm.targetReps(exerciseLogIndex: 0, setIndex: 0))
        XCTAssertEqual(vm.targetReps(exerciseLogIndex: 0, setIndex: 2), 8)
    }

    func testCompleteSetAdoptsPlanTargetRepsWhenNoHistory() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned(sets: 3)],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        // Weight typed, reps left empty, no previous session: the checkmark
        // should adopt the plan's repsMin instead of erroring out.
        seedInput(vm, exercise: 0, set: 2, weight: "100")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets[2].reps, 8)
        XCTAssertEqual(input(vm, exercise: 0, set: 2).reps, "8")
        XCTAssertTrue(vm.completedSetIds.contains(vm.session.exerciseLogs[0].sets[2].id))
    }

    func testCompleteSetStillRequiresWeightForWeightedExercise() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned(sets: 3)],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        // No weight, no history: adopting the rep target alone must not
        // complete a weighted set.
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        XCTAssertTrue(vm.completedSetIds.isEmpty)
        XCTAssertNil(vm.session.exerciseLogs[0].sets[2].completedAt)
    }

    func testPreviousSessionRepsWinOverPlanTarget() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned(sets: 3)],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        var prevLog = vm.session.exerciseLogs[0]
        prevLog.sets = vm.session.exerciseLogs[0].sets.map { set in
            var s = set
            s.id = UUID().uuidString
            s.weightKg = 90
            s.reps = 10
            return s
        }
        vm.previousLogs["bench-press"] = prevLog

        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        // Ghost precedence: repeat last session (10 reps), not the plan's 8.
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[2].reps, 10)
    }

    // MARK: - Remove exercise

    func testRemoveExerciseDropsLogSetsInputsAndTemplateSlot() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
                makePlanned(id: "p2", exerciseId: "barbell-row", sets: 4),
            ], restBetweenRoundsSeconds: nil),
        ])
        let workout = FakeWorkoutService()
        let vm = makeVM(template: template, workout: workout)
        let removedSetIds = vm.session.exerciseLogs[0].sets.map(\.id)
        seedInput(vm, exercise: 0, set: 2, weight: "100", reps: "8")
        await vm.completeSet(exerciseLogIndex: 0, setIndex: 2)

        await vm.removeExercise(exerciseLogIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["barbell-row"])
        XCTAssertEqual(vm.session.exerciseLogs[0].order, 0)
        for id in removedSetIds {
            XCTAssertNil(vm.setInputs[id])
            XCTAssertFalse(vm.completedSetIds.contains(id))
        }
        // The template group lost the exercise, keeping the position-based
        // group map and AI-modify projection aligned.
        XCTAssertEqual(vm.templateGroups[0].exercises.map(\.exerciseId), ["barbell-row"])
        XCTAssertEqual(vm.exerciseGroupMap, [0: 0])
        XCTAssertEqual(
            vm.workoutForAIModification?.exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["barbell-row"]
        )
        XCTAssertNotNil(workout.updatedSessions.last)
    }

    func testRemoveExerciseRemovesEmptiedGroupAndKeepsLaterGroupsMapped() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let vm = makeVM(template: template)

        await vm.removeExercise(exerciseLogIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["curl", "tricep-pushdown"])
        XCTAssertEqual(vm.templateGroups.count, 1)
        XCTAssertEqual(vm.templateGroups[0].groupType, .superset)
        // Both remaining logs map to the (now first) superset group.
        XCTAssertEqual(vm.exerciseGroupMap, [0: 0, 1: 0])
    }

    func testRemoveExerciseDegradesTwoExerciseSupersetToStraightSets() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "curl", sets: 2),
                makePlanned(id: "p2", exerciseId: "tricep-pushdown", sets: 2),
            ], restBetweenRoundsSeconds: 60),
        ])
        let vm = makeVM(template: template)

        await vm.removeExercise(exerciseLogIndex: 1)

        // The surviving half is straight sets everywhere: template group,
        // session log, and group map.
        XCTAssertEqual(vm.templateGroups[0].groupType, .straight)
        XCTAssertEqual(vm.session.exerciseLogs[0].groupType, .straight)
        XCTAssertEqual(vm.groupType(for: 0), .straight)

        // Straight-set rest semantics apply: rest fires mid-exercise but is
        // suppressed after the final completed set (the superset round path
        // would have kept firing it).
        XCTAssertTrue(vm.restDuration(forExerciseLogIndex: 0, setIndex: 0).shouldTrigger)
        for set in vm.session.exerciseLogs[0].sets {
            vm.completedSetIds.insert(set.id)
        }
        let lastIndex = vm.session.exerciseLogs[0].sets.count - 1
        XCTAssertFalse(vm.restDuration(forExerciseLogIndex: 0, setIndex: lastIndex).shouldTrigger)
    }

    func testRemoveExerciseRefusesToEmptyTheSession() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template)

        await vm.removeExercise(exerciseLogIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs.count, 1)
    }

    func testResumeAfterMidWorkoutRemovalNeverMapsMissingExerciseLogs() async {
        // Removing an exercise mid-workout shrinks the session's logs but not
        // the saved plan. On resume, rebuildTemplateContextIfNeeded() rebuilds
        // the group map from the full template, so the map can hold a log
        // index the session no longer has. The view hands those indices
        // straight to ExerciseCardView, which subscripts exerciseLogs.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
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

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        await first.removeExercise(exerciseLogIndex: 0)
        XCTAssertEqual(first.session.exerciseLogs.count, 2)

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        let logCount = resumed.session.exerciseLogs.count
        for logIndex in resumed.session.exerciseLogs.indices {
            guard let gi = resumed.groupIndex(for: logIndex) else { continue }
            for mapped in resumed.exerciseLogIndices(forGroupIndex: gi) {
                XCTAssertLessThan(
                    mapped, logCount,
                    "group \(gi) maps log index \(mapped) but the session has only \(logCount) logs"
                )
            }
        }

        // Not just in-bounds — the surviving superset keeps both its members
        // paired, so round-based rest still works after the resume.
        XCTAssertEqual(resumed.session.exerciseLogs.map(\.exerciseId), ["curl", "tricep-pushdown"])
        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 0])
        XCTAssertEqual(resumed.groupType(for: 0), .superset)
        XCTAssertEqual(resumed.restDuration(forExerciseLogIndex: 0, setIndex: 0).shouldTrigger, false)
    }

    func testResumeAfterMidWorkoutSwapKeepsGroupsAndPrescriptions() async {
        // A swap rewrites the session log's exerciseId but deliberately leaves
        // the saved plan alone, so on resume the plan and the session disagree
        // on that exercise without anything having been removed. Reconciling
        // must read that as a substitution, not a deletion.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        first.requestSwap(exerciseLogIndex: 0)
        await first.swapExercise(newExercise: makeExercise(id: "incline-press", name: "Incline Press"))

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        // Nothing was removed, so nothing may be dropped.
        XCTAssertEqual(resumed.templateGroups.count, 2)
        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 1, 2: 1])
        XCTAssertEqual(resumed.groupType(for: 1), .superset)
        // The swapped-in exercise inherits the plan slot's prescription.
        XCTAssertEqual(resumed.plannedExercise(for: "incline-press")?.repsMin, 8)
        XCTAssertNil(resumed.plannedExercise(for: "bench-press"))
        // Last set is always a working one; warm-ups carry no plan target.
        let lastSet = resumed.session.exerciseLogs[0].sets.count - 1
        XCTAssertEqual(resumed.targetReps(exerciseLogIndex: 0, setIndex: lastSet), 8)
    }

    func testResumeAfterSwapOfLaterExerciseKeepsTrailingGroups() async {
        // A swap in the middle must not discard everything after it.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        first.requestSwap(exerciseLogIndex: 1)
        await first.swapExercise(newExercise: makeExercise(id: "hammer-curl", name: "Hammer Curl"))

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 1, 2: 1])
        XCTAssertEqual(resumed.groupType(for: 2), .superset)
        XCTAssertEqual(resumed.plannedExercise(for: "hammer-curl")?.repsMin, 8)
        // The untouched partner keeps its own slot, not the swapped one's.
        XCTAssertEqual(resumed.plannedExercise(for: "tricep-pushdown")?.id, "p3")
        // Round-based rest still pairs the superset.
        XCTAssertFalse(resumed.restDuration(forExerciseLogIndex: 1, setIndex: 0).shouldTrigger)
    }

    func testResumeAfterBothSwapAndRemovalReconcilesEachCorrectly() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        // Swap the first exercise, then remove one half of the superset.
        first.requestSwap(exerciseLogIndex: 0)
        await first.swapExercise(newExercise: makeExercise(id: "incline-press", name: "Incline Press"))
        await first.removeExercise(exerciseLogIndex: 2)
        XCTAssertEqual(first.session.exerciseLogs.map(\.exerciseId), ["incline-press", "curl"])

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        // Swap kept its slot; the removed superset half is gone and the
        // survivor degraded to straight sets.
        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 1])
        XCTAssertEqual(resumed.plannedExercise(for: "incline-press")?.repsMin, 8)
        XCTAssertEqual(resumed.plannedExercise(for: "curl")?.id, "p2")
        XCTAssertNil(resumed.plannedExercise(for: "tricep-pushdown"))
        XCTAssertEqual(resumed.groupType(for: 1), .straight)
    }

    func testResumeAfterRemoveThenSwapKeepsSurvivingSuperset() async {
        // The ambiguous case exercise ids cannot resolve: plan A straight,
        // then B+C as a superset. Remove A, swap B -> X, and the session holds
        // [X, C] — identical to what "swap A, remove B" would leave, which
        // reconstructs as two straight exercises instead of an X+C superset.
        // Slot identity distinguishes them.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        await first.removeExercise(exerciseLogIndex: 0)
        first.requestSwap(exerciseLogIndex: 0)
        await first.swapExercise(newExercise: makeExercise(id: "hammer-curl", name: "Hammer Curl"))
        XCTAssertEqual(first.session.exerciseLogs.map(\.exerciseId), ["hammer-curl", "tricep-pushdown"])

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        // Both survivors stay in the one superset, not two straight slots.
        XCTAssertEqual(resumed.templateGroups.count, 1)
        XCTAssertEqual(resumed.templateGroups[0].id, "g2")
        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 0])
        XCTAssertEqual(resumed.groupType(for: 0), .superset)
        // The swapped-in exercise inherits p2's prescription, not p1's.
        XCTAssertEqual(resumed.plannedExercise(for: "hammer-curl")?.id, "p2")
        XCTAssertNil(resumed.plannedExercise(for: "bench-press"))
        // Superset round rest, not straight-set rest.
        XCTAssertFalse(resumed.restDuration(forExerciseLogIndex: 0, setIndex: 0).shouldTrigger)
        for log in resumed.session.exerciseLogs {
            resumed.completedSetIds.insert(log.sets[0].id)
        }
        XCTAssertEqual(resumed.restDuration(forExerciseLogIndex: 0, setIndex: 0).seconds, 60)
    }

    func testResumeFallsBackToExerciseIdAlignmentForPreFieldSessions() async {
        // Sessions written before ExerciseLog carried plannedExerciseId decode
        // it as nil and must still reconcile through the legacy heuristic.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        await first.removeExercise(exerciseLogIndex: 0)

        // Strip the field the way an older document would decode.
        var legacy = first.session
        for i in legacy.exerciseLogs.indices {
            legacy.exerciseLogs[i].plannedExerciseId = nil
        }

        let resumed = WorkoutExecutionViewModel(
            existingSession: legacy,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 0])
        XCTAssertEqual(resumed.groupType(for: 0), .superset)
        XCTAssertEqual(resumed.plannedExercise(for: "curl")?.id, "p2")
    }

    func testResumeAfterWorkoutScopeReplacementFallsBackWhenNoSlotIdMatchesPlan() async {
        // A workout-scope AI edit re-points every log at the modified
        // template's slots, but leaves the saved plan alone. On resume the
        // logs all carry slot ids the plan has never heard of, so slot
        // alignment matches nothing and must hand off to the legacy path
        // rather than reporting a clean trim to zero groups.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl", sets: 3),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        // Same exercises and shape, entirely fresh slot ids.
        let modified = makeTemplate(groups: [
            ExerciseGroup(id: "gA", groupType: .straight, exercises: [
                makePlanned(id: "fresh-1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "gB", groupType: .superset, exercises: [
                makePlanned(id: "fresh-2", exerciseId: "curl", sets: 3),
                makePlanned(id: "fresh-3", exerciseId: "tricep-pushdown", sets: 3),
            ], restBetweenRoundsSeconds: 60),
        ])
        let workout = FakeWorkoutService()
        workout.plans = [makePlan(workouts: [template])]

        let first = makeVM(template: template, planId: "plan-1", workout: workout)
        defer { first.stopTimers() }
        await first.applyModifiedWorkout(modified)
        XCTAssertEqual(
            first.session.exerciseLogs.map(\.plannedExerciseId),
            ["fresh-1", "fresh-2", "fresh-3"]
        )

        let resumed = WorkoutExecutionViewModel(
            existingSession: first.session,
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
        defer { resumed.stopTimers() }
        await resumed.start(userUnitSystem: .metric)

        // Recovered by exercise id instead of collapsing to no groups.
        XCTAssertEqual(resumed.templateGroups.count, 2)
        XCTAssertEqual(resumed.exerciseGroupMap, [0: 0, 1: 1, 2: 1])
        XCTAssertEqual(resumed.groupType(for: 1), .superset)
        XCTAssertEqual(resumed.plannedExercise(for: "curl")?.id, "p2")
    }

    func testCreateSessionStampsOriginatingPlanSlotOnEachLog() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "curl", sets: 2),
                makePlanned(id: "p2", exerciseId: "tricep-pushdown", sets: 2),
            ], restBetweenRoundsSeconds: 60),
        ])
        let session = WorkoutSession.create(from: template, userId: "u1", planId: "plan-1")
        XCTAssertEqual(session.exerciseLogs.map(\.plannedExerciseId), ["p1", "p2"])
    }

    func testReconcileGroupsTrimsPlannedExercisesWithNoRemainingLog() {
        let groups = [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "curl"),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown"),
            ], restBetweenRoundsSeconds: 60),
        ]
        let logs = WorkoutSession.create(
            from: makeTemplate(groups: groups), userId: "u1", planId: nil
        ).exerciseLogs

        // Whole group gone: the emptied group is dropped, later groups survive.
        let withoutBench = WorkoutExecutionViewModel.reconcileGroups(
            groups, with: Array(logs.dropFirst())
        )
        XCTAssertEqual(withoutBench.map(\.id), ["g2"])
        XCTAssertEqual(withoutBench[0].groupType, .superset)

        // Half a superset gone: it degrades to straight sets, like a live removal.
        let withoutPushdown = WorkoutExecutionViewModel.reconcileGroups(
            groups, with: Array(logs.dropLast())
        )
        XCTAssertEqual(withoutPushdown.map(\.id), ["g1", "g2"])
        XCTAssertEqual(withoutPushdown[1].exercises.map(\.exerciseId), ["curl"])
        XCTAssertEqual(withoutPushdown[1].groupType, .straight)

        // Untouched session: groups pass through unchanged, keeping their types.
        let unchanged = WorkoutExecutionViewModel.reconcileGroups(groups, with: logs)
        XCTAssertEqual(unchanged, groups)
    }

    func testSwapExerciseKeepsPlanSlotPrescriptionForNewExercise() async {
        let vm = makeBenchVM()
        defer { vm.stopTimers() }

        vm.requestSwap(exerciseLogIndex: 0)
        await vm.swapExercise(newExercise: makeExercise(id: "incline-press", name: "Incline Press"))

        // The template slot is renamed, so rep targets and first-time
        // guidance keep working for the swapped-in exercise.
        XCTAssertEqual(vm.plannedExercise(for: "incline-press")?.repsMin, 8)
        XCTAssertNil(vm.plannedExercise(for: "bench-press"))
        XCTAssertEqual(vm.targetReps(exerciseLogIndex: 0, setIndex: 2), 8)
        XCTAssertEqual(
            vm.workoutForAIModification?.exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["incline-press"]
        )
    }

    // MARK: - Plan-scope AI modification mid-workout

    func testApplyModifiedPlanMergesThisSessionsDay() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, planId: "plan-1")

        var modifiedDay = template
        modifiedDay.name = "Modified Day"
        modifiedDay.exerciseGroups[0].exercises[0].sets = 5
        let plan = WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Plan",
            templateType: .fullBody,
            goal: .strength,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: [modifiedDay],
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: true,
            aiPromptContext: nil
        )

        await vm.applyModifiedPlan(plan)

        XCTAssertEqual(vm.session.workoutName, "Modified Day")
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count { $0.setType == .working }, 5)
    }

    func testApplyModifiedPlanFallsBackToDayNumberWhenIdWasReminted() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, planId: "plan-1")

        // Simulates an older deployed function that let the model mint a new
        // id for this day; only dayNumber still identifies it.
        var remintedDay = template
        remintedDay.id = "model-fresh-id"
        remintedDay.name = "Reminted Day"
        let plan = WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Plan",
            templateType: .fullBody,
            goal: .strength,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 1,
            workouts: [remintedDay],
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: true,
            aiPromptContext: nil
        )

        await vm.applyModifiedPlan(plan)

        XCTAssertEqual(vm.session.workoutName, "Reminted Day")
        // The session repoints at the matched day so resume finds it again.
        XCTAssertEqual(vm.session.workoutTemplateId, "model-fresh-id")
    }

    func testApplyModifiedPlanIgnoresPlansWithoutThisDay() async {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = makeVM(template: template, planId: "plan-1")

        // A genuinely different remaining day: neither this session's id nor
        // its dayNumber — the running day was removed from the plan.
        var otherDay = template
        otherDay.id = "some-other-day"
        otherDay.dayNumber = 2
        let plan = WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Plan",
            templateType: .fullBody,
            goal: .strength,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: [otherDay],
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: true,
            aiPromptContext: nil
        )

        await vm.applyModifiedPlan(plan)

        // The running session's day is gone from the plan: leave it untouched.
        XCTAssertEqual(vm.session.workoutName, "Test Day")
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count { $0.setType == .working }, 3)
    }
}
