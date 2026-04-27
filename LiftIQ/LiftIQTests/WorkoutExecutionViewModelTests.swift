import XCTest
@testable import LiftIQ

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

    // MARK: - createSession

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

        let session = WorkoutExecutionViewModel.createSession(
            from: template, userId: "u1", planId: "plan-1"
        )

        XCTAssertEqual(session.exerciseLogs.count, 4)
        XCTAssertEqual(session.exerciseLogs.map(\.exerciseId),
                       ["bench-press", "barbell-row", "curl", "tricep-pushdown"])
        // Set counts match planned.sets
        XCTAssertEqual(session.exerciseLogs[0].sets.count, 3)
        XCTAssertEqual(session.exerciseLogs[1].sets.count, 4)
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

        let session = WorkoutExecutionViewModel.createSession(
            from: template, userId: "u1", planId: nil
        )

        for set in session.exerciseLogs[0].sets {
            XCTAssertEqual(set.weightKg, 0)
            XCTAssertEqual(set.reps, 0)
            XCTAssertNil(set.completedAt)
            XCTAssertFalse(set.isPersonalRecord)
            XCTAssertEqual(set.setType, .working)
        }
    }

    func testCreateSessionBackfillsSessionIdIntoLogs() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        let session = WorkoutExecutionViewModel.createSession(
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
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        vm.userDefaultRestSeconds = 45 // user override should NOT win when planned is set

        // Mark all but the last set as not completed (we want rest to trigger)
        // For straight sets, "last set with everything completed" suppresses rest.
        // Sets are 3 by default; completing only set 0 triggers rest.
        vm.session.exerciseLogs[0].sets[0].weightKg = 60
        vm.session.exerciseLogs[0].sets[0].reps = 10
        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.completedSetIds.insert(setId)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 120)
    }

    func testRestFallsBackToUserDefaultWhenPlannedExerciseLookupFails() {
        // Build a template, then mutate the session so the exerciseLog points to
        // an exerciseId that no longer exists in the template's planned exercises.
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(exerciseId: "bench-press", restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        vm.userDefaultRestSeconds = 75
        // Simulate a swap that changed the exerciseId; templateGroups still hold the old id
        vm.session.exerciseLogs[0].exerciseId = "different-exercise"
        let setId = vm.session.exerciseLogs[0].sets[0].id
        vm.completedSetIds.insert(setId)

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 0)
        XCTAssertTrue(result.shouldTrigger)
        XCTAssertEqual(result.seconds, 75) // user default, not Constants.defaultRestSeconds (90)
    }

    func testRestSuppressedAfterFinalSetWhenAllCompleted() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 2, restSeconds: 120),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        // Mark both sets completed
        for s in vm.session.exerciseLogs[0].sets {
            vm.completedSetIds.insert(s.id)
        }

        let result = vm.restDuration(forExerciseLogIndex: 0, setIndex: 1) // last set
        XCTAssertFalse(result.shouldTrigger)
    }

    func testSupersetRestUsesGroupRestBetweenRounds() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .superset, exercises: [
                makePlanned(id: "p1", exerciseId: "ex-a", sets: 3, restSeconds: 30),
                makePlanned(id: "p2", exerciseId: "ex-b", sets: 3, restSeconds: 30),
            ], restBetweenRoundsSeconds: 90),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
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
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)

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
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 2)
        XCTAssertEqual(vm.weightInputs[0].count, 2)

        vm.addSet(exerciseLogIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 3)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[2].setNumber, 3)
        XCTAssertEqual(vm.weightInputs[0].count, 3)
        XCTAssertEqual(vm.repsInputs[0].count, 3)
    }

    func testRemoveSetTrimsAndRenumbers() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 3),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        vm.removeSet(exerciseLogIndex: 0, setIndex: 1)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 2)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets.map(\.setNumber), [1, 2])
        XCTAssertEqual(vm.weightInputs[0].count, 2)
    }

    func testRemoveSetRefusesToEmptyExercise() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(sets: 1),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        vm.removeSet(exerciseLogIndex: 0, setIndex: 0)

        XCTAssertEqual(vm.session.exerciseLogs[0].sets.count, 1) // unchanged
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
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)

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

    // MARK: - Scroll target

    func testScrollToExerciseLogIndexIsNilByDefault() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [makePlanned()],
                          restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        XCTAssertNil(vm.scrollToExerciseLogIndex)
    }

    func testScrollToExerciseLogIndexCanBePreservedAcrossInit() {
        let template = makeTemplate(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1"),
                makePlanned(id: "p2"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let vm = WorkoutExecutionViewModel(template: template, userId: "u1", planId: nil)
        vm.scrollToExerciseLogIndex = 1
        XCTAssertEqual(vm.scrollToExerciseLogIndex, 1)
    }
}
