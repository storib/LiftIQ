import XCTest
@testable import LiftIQ

/// Staleness helpers on WorkoutSession, the reminder's fire-delay math, and
/// SessionDetailViewModel's time editing.
@MainActor
final class ForgottenSessionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSession(
        status: SessionStatus = .inProgress,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        setTimes: [Date?] = []
    ) -> WorkoutSession {
        let sets = setTimes.enumerated().map { index, completed in
            SetLog(
                id: "set-\(index)",
                setNumber: index + 1,
                setType: .working,
                weightKg: 60,
                reps: 10,
                rpe: nil,
                isPersonalRecord: false,
                completedAt: completed
            )
        }
        let log = ExerciseLog(
            id: "log-1",
            sessionId: "s1",
            exerciseId: "bench-press",
            exerciseName: "Bench Press",
            order: 1,
            groupType: .straight,
            sets: sets,
            notes: nil
        )
        return WorkoutSession(
            id: "s1",
            userId: "u1",
            planId: nil,
            workoutTemplateId: nil,
            workoutName: "Push",
            startedAt: startedAt ?? t0,
            completedAt: completedAt,
            status: status,
            exerciseLogs: [log],
            durationSeconds: 0,
            notes: nil,
            mood: nil
        )
    }

    // MARK: - Staleness

    func testIsLikelyForgottenOnlyPastThresholdAndOnlyInProgress() {
        let session = makeSession()
        let threshold = Constants.staleSessionThresholdSeconds
        XCTAssertFalse(session.isLikelyForgotten(at: t0.addingTimeInterval(threshold)))
        XCTAssertTrue(session.isLikelyForgotten(at: t0.addingTimeInterval(threshold + 1)))

        let done = makeSession(status: .completed, completedAt: t0.addingTimeInterval(3600))
        XCTAssertFalse(done.isLikelyForgotten(at: t0.addingTimeInterval(48 * 3600)))
    }

    func testLastCompletedSetAtPicksLatestAcrossSets() {
        let session = makeSession(setTimes: [t0.addingTimeInterval(600), nil, t0.addingTimeInterval(2400)])
        XCTAssertEqual(session.lastCompletedSetAt, t0.addingTimeInterval(2400))
        XCTAssertNil(makeSession(setTimes: [nil, nil]).lastCompletedSetAt)
    }

    func testRepairEndDateUsesLastSetOrCappedFallback() {
        let now = t0.addingTimeInterval(30 * 3600)
        let withSets = makeSession(setTimes: [t0.addingTimeInterval(1800), t0.addingTimeInterval(3000)])
        XCTAssertEqual(withSets.repairEndDate(now: now), t0.addingTimeInterval(3000))

        let noSets = makeSession()
        XCTAssertEqual(noSets.repairEndDate(now: now), t0.addingTimeInterval(Constants.staleSessionThresholdSeconds))

        // Fallback can't land in the future.
        let soon = t0.addingTimeInterval(600)
        XCTAssertEqual(noSets.repairEndDate(now: soon), soon)
    }

    func testInferredFinishDate() {
        let fresh = makeSession(setTimes: [t0.addingTimeInterval(600)])
        let soon = t0.addingTimeInterval(3000)
        XCTAssertEqual(fresh.inferredFinishDate(now: soon), soon)

        // Forgotten and idle: ends at the last set.
        let stale = makeSession(setTimes: [t0.addingTimeInterval(2400)])
        let dayLater = t0.addingTimeInterval(30 * 3600)
        XCTAssertEqual(stale.inferredFinishDate(now: dayLater), t0.addingTimeInterval(2400))

        // Forgotten, but the lifter resumed and logged a set just now: ends now.
        let resumed = makeSession(setTimes: [t0.addingTimeInterval(2400), dayLater.addingTimeInterval(-300)])
        XCTAssertEqual(resumed.inferredFinishDate(now: dayLater), dayLater)
    }

    // MARK: - Reminder delay

    func testReminderFireDelay() {
        XCTAssertEqual(SessionReminderScheduler.fireDelay(startedAt: t0, now: t0), Constants.sessionReminderDelaySeconds)
        XCTAssertEqual(SessionReminderScheduler.fireDelay(startedAt: t0, now: t0.addingTimeInterval(3600)),
                       Constants.sessionReminderDelaySeconds - 3600)
        XCTAssertNil(SessionReminderScheduler.fireDelay(startedAt: t0, now: t0.addingTimeInterval(Constants.sessionReminderDelaySeconds)))
        XCTAssertNil(SessionReminderScheduler.fireDelay(startedAt: t0, now: t0.addingTimeInterval(10 * 3600)))
    }

    // MARK: - SessionDetailViewModel time editing

    func testValidateTimes() {
        let now = t0.addingTimeInterval(24 * 3600)
        XCTAssertNil(SessionDetailViewModel.validateTimes(start: t0, end: t0.addingTimeInterval(3600), now: now))
        XCTAssertEqual(SessionDetailViewModel.validateTimes(start: t0, end: t0, now: now), "End must be after start")
        XCTAssertEqual(SessionDetailViewModel.validateTimes(start: t0, end: now.addingTimeInterval(60), now: now),
                       "Workout can't end in the future")
        XCTAssertEqual(SessionDetailViewModel.validateTimes(start: t0, end: t0.addingTimeInterval(13 * 3600), now: now),
                       "Workouts longer than 12 hours can't be saved")
    }

    func testEditingTimesRoutesThroughUpdateSessionTimes() async {
        let completedAt = t0.addingTimeInterval(40 * 3600) // a forgotten session, closed late
        let session = makeSession(status: .completed, completedAt: completedAt, setTimes: [t0.addingTimeInterval(600)])
        let now = completedAt.addingTimeInterval(3600)
        let vm = SessionDetailViewModel(session: session, now: { now })
        let workout = FakeWorkoutService()
        workout.recentSessions = [session]

        vm.beginEditing(unitSystem: .metric)
        XCTAssertTrue(vm.canEditTimes)
        vm.endInput = t0.addingTimeInterval(3600)
        XCTAssertEqual(vm.editedDurationSeconds, 3600)
        XCTAssertTrue(vm.timesChanged)
        XCTAssertNil(vm.timeValidationMessage)
        vm.repsInputs["set-0"] = "12"

        await vm.save(workoutService: workout, unitSystem: .metric)

        XCTAssertEqual(workout.timeUpdates.count, 1)
        XCTAssertTrue(workout.updatedSessions.isEmpty)
        XCTAssertEqual(workout.timeUpdates.first?.completedAt, t0.addingTimeInterval(3600))
        // Set edits ride along in the same write.
        XCTAssertEqual(workout.timeUpdates.first?.session.exerciseLogs[0].sets[0].reps, 12)
        XCTAssertEqual(vm.session.durationSeconds, 3600)
        XCTAssertEqual(vm.session.completedAt, t0.addingTimeInterval(3600))
        XCTAssertFalse(vm.isEditing)
    }

    func testUnchangedTimesUseRegularUpdate() async {
        let session = makeSession(status: .completed, completedAt: t0.addingTimeInterval(3600), setTimes: [t0])
        let vm = SessionDetailViewModel(session: session, now: { self.t0.addingTimeInterval(7200) })
        let workout = FakeWorkoutService()

        vm.beginEditing(unitSystem: .metric)
        vm.repsInputs["set-0"] = "11"
        await vm.save(workoutService: workout, unitSystem: .metric)

        XCTAssertTrue(workout.timeUpdates.isEmpty)
        XCTAssertEqual(workout.updatedSessions.count, 1)
        XCTAssertEqual(vm.session.exerciseLogs[0].sets[0].reps, 11)
    }

    func testInvalidTimesBlockSaveWithoutServiceCall() async {
        let session = makeSession(status: .completed, completedAt: t0.addingTimeInterval(3600))
        let vm = SessionDetailViewModel(session: session, now: { self.t0.addingTimeInterval(7200) })
        let workout = FakeWorkoutService()

        vm.beginEditing(unitSystem: .metric)
        vm.endInput = t0.addingTimeInterval(-60)
        XCTAssertFalse(vm.canSave)

        await vm.save(workoutService: workout, unitSystem: .metric)

        XCTAssertTrue(workout.timeUpdates.isEmpty)
        XCTAssertTrue(workout.updatedSessions.isEmpty)
        XCTAssertEqual(vm.errorMessage, "End must be after start")
        XCTAssertTrue(vm.isEditing)
    }

    func testAbandonedSessionCannotEditTimes() {
        let session = makeSession(status: .abandoned, completedAt: t0.addingTimeInterval(600))
        let vm = SessionDetailViewModel(session: session)
        XCTAssertFalse(vm.canEditTimes)
        vm.beginEditing(unitSystem: .metric)
        vm.endInput = t0.addingTimeInterval(-60)
        XCTAssertNil(vm.timeValidationMessage)
        XCTAssertTrue(vm.canSave)
    }
}

// MARK: - Dashboard repair flow

@MainActor
final class DashboardStaleSessionTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStaleSession(withSet: Bool) -> WorkoutSession {
        let set = SetLog(
            id: "set-0", setNumber: 1, setType: .working, weightKg: 60, reps: 10,
            rpe: nil, isPersonalRecord: false, completedAt: withSet ? t0.addingTimeInterval(1800) : nil
        )
        let log = ExerciseLog(
            id: "log-1", sessionId: "s1", exerciseId: "bench-press", exerciseName: "Bench Press",
            order: 1, groupType: .straight, sets: [set], notes: nil
        )
        return WorkoutSession(
            id: "s1", userId: "u1", planId: nil, workoutTemplateId: nil, workoutName: "Push",
            startedAt: t0, completedAt: nil, status: .inProgress, exerciseLogs: [log],
            durationSeconds: 0, notes: nil, mood: nil
        )
    }

    func testLoadFlagsForgottenSessionOnly() async {
        let workout = FakeWorkoutService()
        workout.activeSession = makeStaleSession(withSet: true)
        let vm = DashboardViewModel(referenceDate: t0)

        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(3600))
        XCTAssertNil(vm.staleSession)

        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(30 * 3600))
        XCTAssertEqual(vm.staleSession?.id, "s1")
    }

    func testFinishAtLastSetCompletesAtLastSetTime() async {
        let workout = FakeWorkoutService()
        workout.activeSession = makeStaleSession(withSet: true)
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(30 * 3600))

        await vm.finishStaleSessionAtLastSet(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1")

        XCTAssertEqual(workout.completedSessions.count, 1)
        XCTAssertEqual(workout.completedSessions.first?.completedAt, t0.addingTimeInterval(1800))
        XCTAssertEqual(workout.completedSessions.first?.durationSeconds, 1800)
        XCTAssertNil(vm.staleSession)
        XCTAssertNil(vm.repairError)
    }

    func testDiscardAbandonsSession() async {
        let workout = FakeWorkoutService()
        workout.activeSession = makeStaleSession(withSet: false)
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(30 * 3600))

        await vm.discardStaleSession(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1")

        XCTAssertEqual(workout.abandonedSessions.map(\.id), ["s1"])
        XCTAssertTrue(workout.completedSessions.isEmpty)
        XCTAssertNil(vm.staleSession)
    }

    func testRefreshStalenessFlagsSessionAfterThresholdWithoutReload() async {
        let workout = FakeWorkoutService()
        workout.activeSession = makeStaleSession(withSet: true)
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(3600))
        XCTAssertNil(vm.staleSession)
        XCTAssertEqual(vm.secondsUntilStale(workoutService: workout, now: t0.addingTimeInterval(3600)),
                       Constants.staleSessionThresholdSeconds - 3600)

        vm.refreshStaleness(workoutService: workout, now: t0.addingTimeInterval(Constants.staleSessionThresholdSeconds + 1))

        XCTAssertEqual(vm.staleSession?.id, "s1")
        XCTAssertNil(vm.secondsUntilStale(workoutService: workout, now: t0.addingTimeInterval(Constants.staleSessionThresholdSeconds + 1)))
    }

    func testRepairPathsEndAllLiveActivities() async {
        let workout = FakeWorkoutService()
        workout.activeSession = makeStaleSession(withSet: true)
        let live = FakeLiveActivityController()
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0.addingTimeInterval(30 * 3600), liveActivity: live)
        XCTAssertEqual(live.endAllCount, 0, "an active session keeps its banner")

        await vm.finishStaleSessionAtLastSet(workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1", liveActivity: live)
        XCTAssertEqual(live.endAllCount, 2, "repair ends it, and the reload with no active session ends orphans")
    }

    func testLoadWithNoActiveSessionEndsOrphanActivities() async {
        let live = FakeLiveActivityController()
        let vm = DashboardViewModel(referenceDate: t0)
        await vm.load(workoutService: FakeWorkoutService(), healthKitService: FakeHealthKitService(), userId: "u1",
                      referenceDate: t0, liveActivity: live)
        XCTAssertEqual(live.endAllCount, 1)
    }
}
