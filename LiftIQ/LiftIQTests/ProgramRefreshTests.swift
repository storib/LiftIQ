import XCTest
@testable import LiftIQ

/// Covers the opt-in "switch it up" checkpoint: when it comes due, when it
/// stays quiet, and that dismissing it buys another full cadence.
final class ProgramRefreshTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func makePlan(
        createdWeeksAgo: Int,
        refreshPromptedWeeksAgo: Int? = nil
    ) -> WorkoutPlan {
        let created = calendar.date(byAdding: .weekOfYear, value: -createdWeeksAgo, to: now)!
        var plan = WorkoutPlan(
            id: "plan-1",
            userId: "u1",
            name: "Test Plan",
            templateType: .custom,
            goal: .hypertrophy,
            weekCount: 4,
            currentWeek: 1,
            workoutsPerWeek: 3,
            workouts: [],
            deloadWeek: nil,
            isActive: true,
            createdAt: created,
            aiGenerated: false,
            aiPromptContext: nil
        )
        if let refreshPromptedWeeksAgo {
            plan.refreshPromptedAt = calendar.date(byAdding: .weekOfYear, value: -refreshPromptedWeeksAgo, to: now)
        }
        return plan
    }

    /// One session a week for `weeks`, the most recent `daysAgo` ago.
    private func sessionDates(weeks: Int, mostRecentDaysAgo: Int = 2) -> [Date] {
        let latest = calendar.date(byAdding: .day, value: -mostRecentDaysAgo, to: now)!
        return (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: latest) }
    }

    func testOffByDefault() {
        XCTAssertNil(ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 40),
            cadenceWeeks: nil,
            planSessionDates: sessionDates(weeks: 20),
            now: now,
            calendar: calendar
        ))
        XCTAssertNil(ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 40),
            cadenceWeeks: 0,
            planSessionDates: sessionDates(weeks: 20),
            now: now,
            calendar: calendar
        ))
    }

    func testNotDueBeforeTheChosenCadence() {
        XCTAssertNil(ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 11),
            cadenceWeeks: 12,
            planSessionDates: sessionDates(weeks: 11),
            now: now,
            calendar: calendar
        ))
    }

    func testDueOnceTheCadencePassesWithRecentTraining() {
        let refresh = ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 13),
            cadenceWeeks: 12,
            planSessionDates: sessionDates(weeks: 13),
            holdingLifts: 2,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(refresh?.weeksOnProgram, 13)
        XCTAssertEqual(refresh?.cadenceWeeks, 12)
        XCTAssertEqual(refresh?.sessionsOnProgram, 13)
        XCTAssertEqual(refresh?.holdingLifts, 2)
    }

    func testStaysQuietWhenTheProgramIsntBeingUsed() {
        // Twelve weeks have passed, but the last session was two months ago:
        // "12 weeks on this program" would be nonsense to come back to.
        XCTAssertNil(ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 20),
            cadenceWeeks: 12,
            planSessionDates: sessionDates(weeks: 4, mostRecentDaysAgo: 60),
            now: now,
            calendar: calendar
        ))
    }

    func testStaysQuietWithNoSessionsOnThisPlanAtAll() {
        XCTAssertNil(ProgramRefresh.due(
            plan: makePlan(createdWeeksAgo: 30),
            cadenceWeeks: 8,
            planSessionDates: [],
            now: now,
            calendar: calendar
        ))
    }

    func testDismissalBuysAnotherFullCadence() {
        let plan = makePlan(createdWeeksAgo: 30, refreshPromptedWeeksAgo: 3)
        XCTAssertEqual(ProgramRefresh.anchorDate(for: plan), plan.refreshPromptedAt)

        XCTAssertNil(ProgramRefresh.due(
            plan: plan,
            cadenceWeeks: 8,
            planSessionDates: sessionDates(weeks: 20),
            now: now,
            calendar: calendar
        ))

        let laterPlan = makePlan(createdWeeksAgo: 30, refreshPromptedWeeksAgo: 9)
        let refresh = ProgramRefresh.due(
            plan: laterPlan,
            cadenceWeeks: 8,
            planSessionDates: sessionDates(weeks: 20),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(refresh?.weeksOnProgram, 9, "weeks are counted from the dismissal, not the plan's birth")
    }

    func testSessionsBeforeTheAnchorDontCount() {
        let plan = makePlan(createdWeeksAgo: 40, refreshPromptedWeeksAgo: 10)
        let refresh = ProgramRefresh.due(
            plan: plan,
            cadenceWeeks: 8,
            planSessionDates: sessionDates(weeks: 30),
            now: now,
            calendar: calendar
        )
        // 30 weekly sessions exist, but only those after the dismissal are
        // part of this stretch.
        XCTAssertEqual(refresh?.sessionsOnProgram, 10)
    }

    func testHoldingLiftCountOnlyCountsStalls() {
        let stalled = ProgressionSuggestion(
            exerciseId: "bench-press",
            suggestedWeight: 55,
            suggestedRepsMin: 8,
            suggestedRepsMax: 10,
            reason: .stall(stuckKg: 60, sessions: 3)
        )
        let holding = ProgressionSuggestion(
            exerciseId: "squat",
            suggestedWeight: 100,
            suggestedRepsMin: 5,
            suggestedRepsMax: 8,
            reason: .holdNearTarget(previousTopKg: 100, topReps: [7, 6], repsToGo: 1)
        )
        XCTAssertEqual(ProgramRefresh.holdingLiftCount([stalled, holding, stalled]), 2)
        XCTAssertEqual(ProgramRefresh.holdingLiftCount([holding]), 0)
    }
}

/// Dashboard behaviour around the switch-it-up card: what the three choices
/// leave the dashboard pointing at.
@MainActor
final class ProgramRefreshDashboardTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private func planned(_ exerciseId: String) -> PlannedExercise {
        PlannedExercise(
            id: "slot-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: 3, repsMin: 8, repsMax: 12,
            rirTarget: nil, rpeTarget: nil, restSeconds: 90, warmUpSets: nil, notes: nil, isOptional: false
        )
    }

    private func template(id: String, name: String, _ exerciseIds: [String]) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id, planId: "plan-1", dayNumber: 1, name: name, targetMuscleGroups: [.chest],
            estimatedDurationMinutes: 60,
            exerciseGroups: exerciseIds.map {
                ExerciseGroup(id: "g-\($0)", groupType: .straight, exercises: [planned($0)], restBetweenRoundsSeconds: nil)
            },
            notes: nil
        )
    }

    private func makePlan(workouts: [WorkoutTemplate]) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1", userId: "u1", name: "Plan", templateType: .ppl, goal: .hypertrophy,
            weekCount: 6, currentWeek: 1, workoutsPerWeek: max(1, workouts.count), workouts: workouts,
            deloadWeek: nil, isActive: true, createdAt: t0.addingTimeInterval(-86_400 * 120),
            aiGenerated: true, aiPromptContext: nil
        )
    }

    func testKeepGoingOnlyStampsTheDismissal() async throws {
        let workout = FakeWorkoutService()
        let day = template(id: "day-1", name: "Push", ["bench"])
        let plan = makePlan(workouts: [day])
        workout.plans = [plan]
        workout.activePlan = plan
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertEqual(vm.todayWorkout?.id, "day-1")

        try await vm.keepProgram(plan: plan, workoutService: workout, now: t0)

        XCTAssertNil(vm.programRefresh)
        XCTAssertEqual(workout.savedPlans.last?.refreshPromptedAt, t0)
        XCTAssertEqual(
            workout.savedPlans.last?.workouts.map(\.id), plan.workouts.map(\.id),
            "the program itself is untouched"
        )
        XCTAssertEqual(vm.todayWorkout?.id, "day-1", "Up Next is untouched")
    }

    func testKeepGoingLeavesTodaysChoicesAlone() async throws {
        let workout = FakeWorkoutService()
        let day1 = template(id: "day-1", name: "Push", ["bench"])
        let day2 = template(id: "day-2", name: "Pull", ["row"])
        let plan = makePlan(workouts: [day1, day2])
        workout.plans = [plan]
        workout.activePlan = plan
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)

        // The lifter picked tomorrow's day from "Change" and accepted a
        // shortened version of it.
        vm.selectWorkout(day2)
        vm.adaptedWorkout = AdaptedWorkout(
            template: day2, changes: [],
            record: WorkoutAdaptation(
                kind: .shortOnTime, targetMinutes: 30, changes: [], usedAI: false, acceptedAt: t0
            ),
            minutesBefore: 60, minutesAfter: 30,
            sourceTemplateId: day2.id, planId: plan.id
        )

        try await vm.keepProgram(plan: plan, workoutService: workout, now: t0)

        XCTAssertNil(vm.programRefresh)
        XCTAssertEqual(vm.todayWorkout?.id, "day-2", "the chosen day survives keeping the program")
        XCTAssertNotNil(vm.adaptedWorkout, "so does the adaptation of it")
        XCTAssertEqual(vm.effectiveTodayWorkout?.exerciseGroups.count, day2.exerciseGroups.count)
    }

    func testAcceptingTheAIEditRepointsUpNextAndDropsTheAdaptation() async throws {
        let workout = FakeWorkoutService()
        let oldDay = template(id: "day-1", name: "Push", ["bench"])
        let original = makePlan(workouts: [oldDay])
        workout.plans = [original]
        workout.activePlan = original
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertEqual(vm.todayWorkout?.id, "day-1")

        // An adaptation of the old day is accepted and waiting for Start.
        vm.adaptedWorkout = AdaptedWorkout(
            template: oldDay, changes: [],
            record: WorkoutAdaptation(
                kind: .shortOnTime, targetMinutes: 30, changes: [], usedAI: false, acceptedAt: t0
            ),
            minutesBefore: 60, minutesAfter: 30,
            sourceTemplateId: oldDay.id, planId: original.id
        )
        XCTAssertNotNil(vm.effectiveTodayWorkout)

        // The AI sheet saved a rewritten plan whose days are different.
        let rewritten = makePlan(workouts: [template(id: "day-9", name: "Upper", ["db-press"])])
        try await vm.applyRefreshedProgram(plan: rewritten, workoutService: workout, now: t0)

        XCTAssertNil(vm.programRefresh)
        XCTAssertNil(vm.adaptedWorkout, "an adaptation of a day that no longer exists can't start")
        XCTAssertEqual(vm.todayWorkout?.id, "day-9")
        XCTAssertEqual(vm.effectiveTodayWorkout?.id, "day-9", "Start runs the edited workout, not the old one")
        XCTAssertEqual(workout.savedPlans.last?.refreshPromptedAt, t0)
    }
}
