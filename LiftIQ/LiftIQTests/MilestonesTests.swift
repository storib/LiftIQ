import XCTest
@testable import LiftIQ

final class MilestonesTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Monday 2026-08-03 00:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_785_715_200)

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        monday.addingTimeInterval(TimeInterval(offset * 86_400 + hour * 3600))
    }

    /// `n` sessions in each of the `weeks` weeks ending at `monday`'s week.
    private func sessions(weeks: Int, perWeek n: Int) -> [Date] {
        (0..<weeks).flatMap { w in (0..<n).map { day(-7 * w + $0) } }
    }

    func testWorkoutCountFiresOnlyAtExactThreshold() {
        XCTAssertFalse(Milestones.isWorkoutMilestone(9))
        XCTAssertTrue(Milestones.isWorkoutMilestone(10))
        XCTAssertFalse(Milestones.isWorkoutMilestone(11))
        XCTAssertTrue(Milestones.isWorkoutMilestone(25))
        XCTAssertTrue(Milestones.isWorkoutMilestone(50))
        XCTAssertFalse(Milestones.isWorkoutMilestone(75))
        XCTAssertTrue(Milestones.isWorkoutMilestone(100))
        XCTAssertTrue(Milestones.isWorkoutMilestone(150))
        XCTAssertFalse(Milestones.isWorkoutMilestone(151))
    }

    func testWeekStreakCountsConsecutiveQualifyingWeeks() {
        let dates = sessions(weeks: 5, perWeek: 3)
        XCTAssertEqual(Milestones.weekStreak(completedSessionDates: dates, weeklyTarget: 3, now: day(6), calendar: calendar), 5)
    }

    func testCurrentWeekInProgressDoesNotBreakStreak() {
        // Four full prior weeks, and only one session so far this week.
        var dates = (1...4).flatMap { w in (0..<3).map { day(-7 * w + $0) } }
        dates.append(day(0))
        XCTAssertEqual(Milestones.weekStreak(completedSessionDates: dates, weeklyTarget: 3, now: day(1), calendar: calendar), 4)
    }

    func testStreakBreaksOnAMissedWeek() {
        // This week and last week qualify; the week before is empty; older weeks qualify.
        var dates = sessions(weeks: 2, perWeek: 3)
        dates += (3...5).flatMap { w in (0..<3).map { day(-7 * w + $0) } }
        XCTAssertEqual(Milestones.weekStreak(completedSessionDates: dates, weeklyTarget: 3, now: day(6), calendar: calendar), 2)
    }

    func testStreakMilestoneFiresOnlyWhenThisSessionCompletesTheWeek() {
        // Three prior qualifying weeks; this week the third session makes four.
        var dates = (1...3).flatMap { w in (0..<3).map { day(-7 * w + $0) } }
        dates += [day(0), day(2)]
        let notYet = Milestones.evaluate(totalCompletedCount: 11, completedSessionDates: dates, weeklyTarget: 3, now: day(2), calendar: calendar)
        XCTAssertTrue(notYet.isEmpty)

        dates.append(day(4))
        let crossed = Milestones.evaluate(totalCompletedCount: 12, completedSessionDates: dates, weeklyTarget: 3, now: day(4), calendar: calendar)
        XCTAssertEqual(crossed, [.weekStreak(4)])

        // A bonus fourth session that week must not fire it again.
        dates.append(day(5))
        let bonus = Milestones.evaluate(totalCompletedCount: 13, completedSessionDates: dates, weeklyTarget: 3, now: day(5), calendar: calendar)
        XCTAssertTrue(bonus.isEmpty)
    }

    func testEvaluateReturnsBothWhenBothCross() {
        var dates = (1...7).flatMap { w in (0..<3).map { day(-7 * w + $0) } }
        dates += [day(0), day(2), day(4)]
        let result = Milestones.evaluate(totalCompletedCount: 25, completedSessionDates: dates, weeklyTarget: 3, now: day(4), calendar: calendar)
        XCTAssertEqual(result, [.workoutCount(25), .weekStreak(8)])
    }
}

final class BlockProgressTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePlan(weekCount: Int = 6, perWeek: Int = 3, blockStartedAt: Date? = nil, blockNumber: Int? = nil) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1", userId: "u1", name: "Plan", templateType: .fullBody, goal: .hypertrophy,
            weekCount: weekCount, currentWeek: 1, workoutsPerWeek: perWeek, workouts: [],
            deloadWeek: 5, isActive: true, createdAt: t0, aiGenerated: true, aiPromptContext: nil,
            blockStartedAt: blockStartedAt, blockNumber: blockNumber
        )
    }

    private func makeSession(planId: String? = "plan-1", status: SessionStatus = .completed, at: Date) -> WorkoutSession {
        WorkoutSession(
            id: UUID().uuidString, userId: "u1", planId: planId, workoutTemplateId: nil, workoutName: "Day",
            startedAt: at, completedAt: at.addingTimeInterval(3600), status: status, exerciseLogs: [],
            durationSeconds: 3600, notes: nil, mood: nil
        )
    }

    func testWeekAdvancesPerSessionsNotCalendar() {
        let plan = makePlan()
        // Seven sessions spread over three months: still week 3 of 6.
        let sessions = (0..<7).map { makeSession(at: t0.addingTimeInterval(Double($0) * 12 * 86_400)) }
        let progress = BlockProgress.compute(plan: plan, sessions: sessions)
        XCTAssertEqual(progress.currentWeek, 3)
        XCTAssertFalse(progress.isComplete)
        XCTAssertEqual(progress.blockNumber, 1)
    }

    func testOtherPlanAbandonedAndPreBlockSessionsIgnored() {
        let plan = makePlan(blockStartedAt: t0.addingTimeInterval(86_400 * 10), blockNumber: 2)
        let sessions = [
            makeSession(at: t0),                                                  // before block start
            makeSession(planId: "other", at: t0.addingTimeInterval(86_400 * 11)), // other plan
            makeSession(status: .abandoned, at: t0.addingTimeInterval(86_400 * 12)),
            makeSession(at: t0.addingTimeInterval(86_400 * 13)),
        ]
        let progress = BlockProgress.compute(plan: plan, sessions: sessions)
        XCTAssertEqual(progress.completedSessions, 1)
        XCTAssertEqual(progress.blockNumber, 2)
    }

    func testCompleteAtWeekCountTimesWorkoutsPerWeek() {
        let plan = makePlan(weekCount: 6, perWeek: 3)
        let seventeen = (0..<17).map { makeSession(at: t0.addingTimeInterval(Double($0) * 86_400)) }
        XCTAssertFalse(BlockProgress.compute(plan: plan, sessions: seventeen).isComplete)
        XCTAssertEqual(BlockProgress.compute(plan: plan, sessions: seventeen).currentWeek, 6)
        let eighteen = seventeen + [makeSession(at: t0.addingTimeInterval(17 * 86_400))]
        XCTAssertTrue(BlockProgress.compute(plan: plan, sessions: eighteen).isComplete)
    }

    func testDeloadWeekMatchesDerivedWeekOnly() {
        let plan = makePlan(weekCount: 6, perWeek: 3)
        let twelve = (0..<12).map { makeSession(at: t0.addingTimeInterval(Double($0) * 86_400)) }
        XCTAssertEqual(BlockProgress.compute(plan: plan, sessions: twelve).currentWeek, 5)
        XCTAssertTrue(BlockProgress.compute(plan: plan, sessions: twelve).isDeloadWeek(5))
        XCTAssertFalse(BlockProgress.compute(plan: plan, sessions: twelve).isDeloadWeek(nil))
        XCTAssertFalse(BlockProgress.compute(plan: plan, sessions: Array(twelve.prefix(9))).isDeloadWeek(5))
    }

    @MainActor
    func testStartNextBlockStampsBlockFieldsAndSaves() async throws {
        let workout = FakeWorkoutService()
        let plan = makePlan()
        let vm = DashboardViewModel(referenceDate: t0)
        let now = t0.addingTimeInterval(50 * 86_400)

        try await vm.startNextBlock(plan: plan, workoutService: workout, now: now)

        XCTAssertEqual(workout.savedPlans.count, 1)
        XCTAssertEqual(workout.savedPlans.first?.blockStartedAt, now)
        XCTAssertEqual(workout.savedPlans.first?.blockNumber, 2)
        XCTAssertNil(vm.blockReview)
        XCTAssertEqual(vm.blockProgress?.blockNumber, 2)
        XCTAssertEqual(vm.blockProgress?.completedSessions, 0)
    }

    @MainActor
    func testStartNextBlockWithTweakedPlanRepointsUpNext() async throws {
        let workout = FakeWorkoutService()
        let oldDay = WorkoutTemplate(id: "old-day", planId: "plan-1", dayNumber: 1, name: "Old Upper",
                                     targetMuscleGroups: [.chest], estimatedDurationMinutes: 45, exerciseGroups: [], notes: nil)
        var plan = makePlan()
        plan.workouts = [oldDay]
        workout.plans = [plan]
        workout.activePlan = plan
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", referenceDate: t0)
        XCTAssertEqual(vm.todayWorkout?.id, "old-day")

        var tweaked = plan
        tweaked.workouts = [WorkoutTemplate(id: "new-day", planId: "plan-1", dayNumber: 1, name: "New Upper",
                                            targetMuscleGroups: [.chest], estimatedDurationMinutes: 45, exerciseGroups: [], notes: nil)]
        try await vm.startNextBlock(plan: tweaked, workoutService: workout, now: t0.addingTimeInterval(86_400))

        XCTAssertEqual(vm.todayWorkout?.id, "new-day")
    }

    @MainActor
    func testLoadBuildsBlockReviewWhenBlockComplete() async {
        let workout = FakeWorkoutService()
        let plan = makePlan(weekCount: 2, perWeek: 2)
        workout.plans = [plan]
        workout.activePlan = plan
        workout.recentSessions = (0..<4).map { makeSession(at: t0.addingTimeInterval(Double($0) * 86_400)) }
        let vm = DashboardViewModel(referenceDate: t0)

        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(5 * 86_400))

        XCTAssertEqual(vm.blockProgress?.isComplete, true)
        XCTAssertEqual(vm.blockReview?.sessions, 4)
        XCTAssertEqual(vm.blockReview?.weeks, 2)
        XCTAssertEqual(vm.blockReview?.blockNumber, 1)
    }
}
