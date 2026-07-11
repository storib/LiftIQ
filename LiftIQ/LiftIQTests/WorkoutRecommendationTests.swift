import XCTest
@testable import LiftIQ

final class WorkoutRecommendationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTemplate(id: String, day: Int, name: String) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id,
            planId: "plan-1",
            dayNumber: day,
            name: name,
            targetMuscleGroups: [.chest],
            estimatedDurationMinutes: 45,
            exerciseGroups: [],
            notes: nil
        )
    }

    private func makePlan(workouts: [WorkoutTemplate], workoutsPerWeek: Int = 3) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1",
            userId: "user-1",
            name: "Test Plan",
            templateType: .fullBody,
            goal: .strength,
            weekCount: 8,
            currentWeek: 1,
            workoutsPerWeek: workoutsPerWeek,
            workouts: workouts,
            deloadWeek: nil,
            isActive: true,
            createdAt: Date(),
            aiGenerated: false,
            aiPromptContext: nil
        )
    }

    private func makeSession(
        templateId: String?,
        status: SessionStatus = .completed,
        completedAt: Date? = Date()
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID().uuidString,
            userId: "user-1",
            planId: "plan-1",
            workoutTemplateId: templateId,
            workoutName: "Session",
            startedAt: completedAt ?? Date(),
            completedAt: completedAt,
            status: status,
            exerciseLogs: [],
            durationSeconds: 1800,
            notes: nil,
            mood: nil
        )
    }

    private var threeDay: [WorkoutTemplate] {
        [
            makeTemplate(id: "day1", day: 1, name: "Upper 1"),
            makeTemplate(id: "day2", day: 2, name: "Lower 1"),
            makeTemplate(id: "day3", day: 3, name: "Upper 2")
        ]
    }

    // MARK: - nextWorkout

    @MainActor
    func testNoSessionsRecommendsFirstDay() {
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: [])
        XCTAssertEqual(next?.id, "day1")
    }

    @MainActor
    func testCompletingDayOneRecommendsDayTwo() {
        let sessions = [makeSession(templateId: "day1")]
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: sessions)
        XCTAssertEqual(next?.id, "day2")
    }

    @MainActor
    func testRotationCyclesBackToDayOne() {
        let sessions = [makeSession(templateId: "day3")]
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: sessions)
        XCTAssertEqual(next?.id, "day1")
    }

    @MainActor
    func testUsesMostRecentCompletionNotListOrder() {
        let sessions = [
            makeSession(templateId: "day2", completedAt: Date()),
            makeSession(templateId: "day1", completedAt: Date().addingTimeInterval(-86_400))
        ]
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: sessions)
        XCTAssertEqual(next?.id, "day3")
    }

    @MainActor
    func testAbandonedAndInProgressSessionsDoNotAdvance() {
        let sessions = [
            makeSession(templateId: "day1", status: .abandoned),
            makeSession(templateId: "day2", status: .inProgress, completedAt: nil)
        ]
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: sessions)
        XCTAssertEqual(next?.id, "day1")
    }

    @MainActor
    func testSessionsFromOtherPlansAreIgnored() {
        let sessions = [makeSession(templateId: "other-plan-day")]
        let next = DashboardViewModel.nextWorkout(plan: makePlan(workouts: threeDay), sessions: sessions)
        XCTAssertEqual(next?.id, "day1")
    }

    @MainActor
    func testUpcomingRotationContinuesFromNext() {
        let sessions = [makeSession(templateId: "day2")]
        let rotation = DashboardViewModel.upcomingRotation(
            plan: makePlan(workouts: threeDay),
            sessions: sessions,
            count: 3
        )
        XCTAssertEqual(rotation.map(\.id), ["day3", "day1", "day2"])
    }

    // MARK: - Dashboard week

    @MainActor
    func testDashboardWeekRunsMondayThroughSunday() {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 12))!
        let vm = DashboardViewModel(referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(vm.weekDays.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: vm.weekDays.first!), 2)
        XCTAssertEqual(calendar.component(.weekday, from: vm.weekDays.last!), 1)
    }

    @MainActor
    func testExternalActivitiesGroupByDayWithoutAffectingLiftingStatsOrRotation() async {
        let calendar = Calendar.current
        let referenceDate = calendar.startOfDay(for: Date())
        let workoutService = FakeWorkoutService()
        workoutService.activePlan = makePlan(workouts: threeDay)

        let healthService = FakeHealthKitService()
        healthService.isActivityImportEnabled = true
        let walk = ExternalActivity(
            id: "walk-1",
            kind: .walking,
            startedAt: referenceDate.addingTimeInterval(9 * 3_600),
            endedAt: referenceDate.addingTimeInterval(9.5 * 3_600),
            sourceName: "Oura",
            activeEnergyKilocalories: 180,
            distanceMeters: 3_200
        )
        healthService.activities = [walk]

        let vm = DashboardViewModel(referenceDate: referenceDate, calendar: calendar)
        await vm.load(workoutService: workoutService, healthKitService: healthService, userId: "user-1")

        XCTAssertEqual(vm.activities(on: referenceDate), [walk])
        XCTAssertTrue(vm.sessions(on: referenceDate, from: workoutService.recentSessions).isEmpty)
        XCTAssertEqual(vm.weeklySessionCount, 0)
        XCTAssertEqual(vm.weeklyVolume, 0)
        XCTAssertEqual(vm.todayWorkout?.id, "day1")
    }

    @MainActor
    func testDashboardWeekRollsOverOnReload() async {
        let calendar = Calendar(identifier: .gregorian)
        let lastWeek = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 8))!
        let vm = DashboardViewModel(referenceDate: lastWeek, calendar: calendar)
        let healthService = FakeHealthKitService()
        healthService.isActivityImportEnabled = true

        await vm.load(
            workoutService: FakeWorkoutService(),
            healthKitService: healthService,
            userId: "user-1",
            referenceDate: today
        )

        XCTAssertEqual(vm.weekDays.first, today.startOfWeek(using: calendar))
        XCTAssertEqual(vm.selectedDate, calendar.startOfDay(for: today))
        XCTAssertEqual(healthService.fetchRanges.last?.start, today.startOfWeek(using: calendar))
    }

    // MARK: - History deletion

    @MainActor
    func testDeleteSessionRemovesFromServiceAndSurfacesNoError() async {
        let service = FakeWorkoutService()
        let session = makeSession(templateId: "day1")
        service.recentSessions = [session]

        let vm = WorkoutHistoryViewModel()
        await vm.delete(session: session, workoutService: service)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(service.deletedSessions.map(\.id), [session.id])
        XCTAssertTrue(service.recentSessions.isEmpty)
    }

    @MainActor
    func testDeleteFailureSurfacesError() async {
        let service = FakeWorkoutService()
        service.deleteSessionError = NSError(domain: "test", code: 1)
        let vm = WorkoutHistoryViewModel()

        await vm.delete(session: makeSession(templateId: "day1"), workoutService: service)

        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testEditingFinishedSessionRefreshesServiceRecentSessions() async {
        let service = FakeWorkoutService()
        var session = makeSession(templateId: "day1")
        session.exerciseLogs = [
            ExerciseLog(
                id: "log-1",
                sessionId: session.id,
                exerciseId: "bench",
                exerciseName: "Bench Press",
                order: 0,
                groupType: .straight,
                sets: [
                    SetLog(
                        id: "set-1",
                        setNumber: 1,
                        setType: .working,
                        weightKg: 50,
                        reps: 5,
                        rpe: nil,
                        isPersonalRecord: false,
                        completedAt: Date()
                    )
                ],
                notes: nil
            )
        ]
        service.recentSessions = [session]

        let vm = SessionDetailViewModel(session: session)
        vm.beginEditing(unitSystem: .metric)
        vm.weightInputs["set-1"] = "80"
        vm.repsInputs["set-1"] = "8"

        await vm.save(workoutService: service, unitSystem: .metric)

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(service.recentSessions.first?.exerciseLogs[0].sets[0].weightKg, 80)
        XCTAssertEqual(service.recentSessions.first?.exerciseLogs[0].sets[0].reps, 8)
    }

    // MARK: - Weekly projection

    @MainActor
    func testPlannedEntriesFillRemainingDaysOfCurrentWeek() {
        let calendar = Calendar.current
        let weekStart = Date().startOfWeek()
        let vm = WorkoutHistoryViewModel(weekStart: weekStart)

        // One workout completed today → 2 of 3 weekly slots remain.
        let completedToday = makeSession(templateId: "day1")
        let planned = vm.plannedEntries(
            plan: makePlan(workouts: threeDay, workoutsPerWeek: 3),
            sessions: [completedToday]
        )

        XCTAssertEqual(planned.count, min(2, remainingFutureDays(weekStart: weekStart, calendar: calendar)))
        // Projection continues the rotation after the completed day.
        if let firstDay = planned.keys.sorted().first {
            XCTAssertEqual(planned[firstDay]?.id, "day2")
        }
    }

    @MainActor
    func testNoProjectionOncePastWeekIsShown() {
        let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date().startOfWeek())!
        let vm = WorkoutHistoryViewModel(weekStart: lastWeek)
        let planned = vm.plannedEntries(plan: makePlan(workouts: threeDay), sessions: [])
        XCTAssertTrue(planned.isEmpty)
    }

    /// Days from tomorrow through the end of the shown week (today is excluded
    /// because the fixture completes a workout today).
    private func remainingFutureDays(weekStart: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        return days.filter { $0 > today }.count
    }
}
