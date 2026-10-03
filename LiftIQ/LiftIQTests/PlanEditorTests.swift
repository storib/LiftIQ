import XCTest
@testable import LiftIQ

/// Covers permanent exercise removal: the pure plan edit, and the
/// mid-workout "remove from my plan" scope that uses it.
@MainActor
final class PlanEditorTests: XCTestCase {

    // MARK: - Helpers

    private func makePlanned(
        id: String,
        exerciseId: String,
        order: Int = 0
    ) -> PlannedExercise {
        PlannedExercise(
            id: id,
            exerciseId: exerciseId,
            order: order,
            sets: 3,
            repsMin: 8,
            repsMax: 10,
            rirTarget: nil,
            rpeTarget: nil,
            restSeconds: 90,
            warmUpSets: nil,
            notes: nil,
            isOptional: false
        )
    }

    private func makeDay(id: String = "day-1", groups: [ExerciseGroup]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            planId: "plan-1",
            dayNumber: 1,
            name: "Push",
            targetMuscleGroups: [.chest],
            estimatedDurationMinutes: 60,
            exerciseGroups: groups,
            notes: nil
        )
    }

    private func makePlan(days: [WorkoutTemplate]) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Test Plan",
            templateType: .custom,
            goal: .hypertrophy,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: days,
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            aiGenerated: false,
            aiPromptContext: nil
        )
    }

    private var threeExerciseDay: WorkoutTemplate {
        makeDay(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press", order: 0),
            ], restBetweenRoundsSeconds: nil),
            ExerciseGroup(id: "g2", groupType: .superset, exercises: [
                makePlanned(id: "p2", exerciseId: "cable-fly", order: 1),
                makePlanned(id: "p3", exerciseId: "tricep-pushdown", order: 2),
            ], restBetweenRoundsSeconds: 90),
        ])
    }

    // MARK: - PlanEditor

    func testRemovingBySlotIdDropsOnlyThatSlot() {
        let plan = makePlan(days: [threeExerciseDay])

        let updated = PlanEditor.removingExercise(
            plannedExerciseId: "p1",
            exerciseId: "bench-press",
            fromDayId: "day-1",
            in: plan
        )

        let remaining = updated?.workouts[0].exerciseGroups.flatMap(\.exercises) ?? []
        XCTAssertEqual(remaining.map(\.id), ["p2", "p3"])
        XCTAssertEqual(remaining.map(\.order), [0, 1], "order is positional and renumbered")
    }

    func testRemovingEmptiedGroupDropsTheGroup() {
        let plan = makePlan(days: [threeExerciseDay])

        let updated = PlanEditor.removingExercise(
            plannedExerciseId: "p1",
            exerciseId: nil,
            fromDayId: "day-1",
            in: plan
        )

        XCTAssertEqual(updated?.workouts[0].exerciseGroups.map(\.id), ["g2"])
    }

    func testSupersetLeftWithOneExerciseDegradesToStraightSets() {
        let plan = makePlan(days: [threeExerciseDay])

        let updated = PlanEditor.removingExercise(
            plannedExerciseId: "p2",
            exerciseId: nil,
            fromDayId: "day-1",
            in: plan
        )

        let group = updated?.workouts[0].exerciseGroups.first { $0.id == "g2" }
        XCTAssertEqual(group?.exercises.map(\.id), ["p3"])
        XCTAssertEqual(group?.groupType, .straight)
    }

    func testRemovingFallsBackToExerciseIdWhenTheSlotIdIsUnknown() {
        let plan = makePlan(days: [threeExerciseDay])

        let updated = PlanEditor.removingExercise(
            plannedExerciseId: nil,
            exerciseId: "tricep-pushdown",
            fromDayId: "day-1",
            in: plan
        )

        XCTAssertEqual(
            updated?.workouts[0].exerciseGroups.flatMap(\.exercises).map(\.id),
            ["p1", "p2"]
        )
    }

    func testRemovingRefusesToEmptyADay() {
        let plan = makePlan(days: [
            makeDay(groups: [
                ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                    makePlanned(id: "p1", exerciseId: "bench-press"),
                ], restBetweenRoundsSeconds: nil),
            ]),
        ])

        XCTAssertNil(PlanEditor.removingExercise(
            plannedExerciseId: "p1",
            exerciseId: "bench-press",
            fromDayId: "day-1",
            in: plan
        ))
        XCTAssertFalse(PlanEditor.canRemoveExercise(
            plannedExerciseId: "p1",
            exerciseId: "bench-press",
            fromDayId: "day-1",
            in: plan
        ))
    }

    func testRemovingReturnsNilForAMissingDayOrSlot() {
        let plan = makePlan(days: [threeExerciseDay])

        XCTAssertNil(PlanEditor.removingExercise(
            plannedExerciseId: "p1", exerciseId: nil, fromDayId: "day-9", in: plan
        ))
        XCTAssertNil(PlanEditor.removingExercise(
            plannedExerciseId: "nope", exerciseId: "also-nope", fromDayId: "day-1", in: plan
        ))
    }

    func testRemovingLeavesOtherDaysUntouched() {
        let otherDay = makeDay(id: "day-2", groups: [
            ExerciseGroup(id: "g9", groupType: .straight, exercises: [
                makePlanned(id: "p9", exerciseId: "deadlift"),
            ], restBetweenRoundsSeconds: nil),
        ])
        let plan = makePlan(days: [threeExerciseDay, otherDay])

        let updated = PlanEditor.removingExercise(
            plannedExerciseId: "p1", exerciseId: nil, fromDayId: "day-1", in: plan
        )

        XCTAssertEqual(updated?.workouts[1], otherDay)
        XCTAssertEqual(updated?.id, plan.id)
        XCTAssertEqual(updated?.isActive, true)
        XCTAssertEqual(updated?.createdAt, plan.createdAt)
    }

    // MARK: - Mid-workout removal scope

    private func makeVM(
        day: WorkoutTemplate,
        workout: FakeWorkoutService
    ) -> WorkoutExecutionViewModel {
        WorkoutExecutionViewModel(
            template: day,
            userId: "u1",
            planId: "plan-1",
            workoutService: workout,
            exerciseService: FakeExerciseService(),
            progressService: FakeProgressService(),
            progressionService: ProgressionService()
        )
    }

    /// A Task created on the main actor only runs once its creator suspends,
    /// so "the save was enqueued" needs a yield — which is also exactly why
    /// today's removal never waits for it.
    private func awaitSaveAttempts(_ workout: FakeWorkoutService, count: Int) async {
        for _ in 0..<100 where workout.savePlanAttempts.count < count {
            await Task.yield()
        }
    }

    func testSessionScopedRemovalLeavesThePlanAlone() async {
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        await vm.removeExercise(exerciseLogIndex: 0, scope: .session)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["cable-fly", "tricep-pushdown"])
        XCTAssertTrue(workout.savedPlans.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testPlanScopedRemovalSavesThePlanWithoutTheSlot() async {
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        XCTAssertTrue(vm.canRemoveFromPlan(exerciseLogIndex: 0))
        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["cable-fly", "tricep-pushdown"])
        await vm.planRemovalSaveTask?.value
        XCTAssertEqual(workout.savedPlans.count, 1)
        XCTAssertEqual(
            workout.savedPlans.first?.workouts[0].exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["cable-fly", "tricep-pushdown"]
        )
        XCTAssertNil(vm.errorMessage)
    }

    func testPlanScopedRemovalStillRemovesForTodayWhenTheSaveFails() async {
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        workout.savePlanError = FakeServiceError(message: "offline")
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertEqual(vm.session.exerciseLogs.count, 2, "today's removal is never held hostage")
        await vm.planRemovalSaveTask?.value
        XCTAssertNotNil(vm.errorMessage)
    }

    func testPlanScopedRemovalDoesNotWaitForTheServerAcknowledgement() async {
        // An active-plan save ends in a WriteBatch commit, whose completion
        // never arrives offline. Today's removal must not sit behind it.
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        workout.savePlanNeverAcknowledges = true
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertEqual(
            vm.session.exerciseLogs.map(\.exerciseId), ["cable-fly", "tricep-pushdown"],
            "the removal is on screen before any acknowledgement"
        )
        // The write is still enqueued (Firestore keeps it locally) even
        // though it will never be acknowledged.
        await awaitSaveAttempts(workout, count: 1)
        XCTAssertEqual(workout.savePlanAttempts.count, 1)
        XCTAssertEqual(
            workout.savePlanAttempts.first?.workouts[0].exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["cable-fly", "tricep-pushdown"]
        )
        XCTAssertNil(vm.errorMessage)

        vm.planRemovalSaveTask?.cancel()
        await vm.planRemovalSaveTask?.value
    }

    func testSecondPlanScopedRemovalBuildsOnTheFirstNotOnTheStaleCopy() async {
        // The service's plan list only refreshes once a save is acknowledged,
        // so the second removal has to work from this session's own copy or
        // it would write the first exercise back.
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        workout.savePlanNeverAcknowledges = true
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)
        let first = vm.planRemovalSaveTask
        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["tricep-pushdown"])
        await awaitSaveAttempts(workout, count: 2)
        XCTAssertEqual(workout.savePlanAttempts.count, 2)
        XCTAssertEqual(
            workout.savePlanAttempts.last?.workouts[0].exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["tricep-pushdown"]
        )

        first?.cancel()
        vm.planRemovalSaveTask?.cancel()
        await first?.value
        await vm.planRemovalSaveTask?.value
    }

    func testTheAIEditorSeesThePlanWithThePendingRemovalAlreadyApplied() async {
        // The AI sheet reads planForAIModification. If that returned the
        // service's copy while a removal save was still unacknowledged, the
        // model would be handed a plan still listing the exercise — and
        // accepting the edit would write it straight back.
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        workout.plans = [makePlan(days: [day])]
        workout.savePlanNeverAcknowledges = true
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertEqual(
            vm.planForAIModification?.workouts[0].exerciseGroups.flatMap(\.exercises).map(\.exerciseId),
            ["cable-fly", "tricep-pushdown"]
        )

        await awaitSaveAttempts(workout, count: 1)
        vm.planRemovalSaveTask?.cancel()
        await vm.planRemovalSaveTask?.value
    }

    func testPlanScopeIsUnavailableWithoutALoadedPlan() async {
        let workout = FakeWorkoutService()
        let day = threeExerciseDay
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = day.id

        XCTAssertFalse(vm.canRemoveFromPlan(exerciseLogIndex: 0))
    }

    func testPlanScopeIsUnavailableForADaysLastExercise() async {
        let workout = FakeWorkoutService()
        let day = makeDay(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
                makePlanned(id: "p2", exerciseId: "cable-fly"),
            ], restBetweenRoundsSeconds: nil),
        ])
        // The plan day holds one exercise; the session holds two, so the
        // session-scope guard alone wouldn't catch this.
        let planDay = makeDay(groups: [
            ExerciseGroup(id: "g1", groupType: .straight, exercises: [
                makePlanned(id: "p1", exerciseId: "bench-press"),
            ], restBetweenRoundsSeconds: nil),
        ])
        workout.plans = [makePlan(days: [planDay])]
        let vm = makeVM(day: day, workout: workout)
        defer { vm.stopTimers() }
        vm.session.workoutTemplateId = planDay.id

        XCTAssertFalse(vm.canRemoveFromPlan(exerciseLogIndex: 0))

        await vm.removeExercise(exerciseLogIndex: 0, scope: .plan)

        XCTAssertTrue(workout.savedPlans.isEmpty)
        XCTAssertEqual(vm.session.exerciseLogs.map(\.exerciseId), ["cable-fly"])
        XCTAssertNotNil(vm.errorMessage, "the lifter is told the plan is unchanged")
    }
}
