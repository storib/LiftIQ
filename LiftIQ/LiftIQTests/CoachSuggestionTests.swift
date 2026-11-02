import XCTest
@testable import LiftIQ

final class CoachSuggestionTests: XCTestCase {

    private func slot(_ exerciseId: String, day: String = "day-1", _ reason: ProgressionReason) -> PlanSlotSuggestion {
        PlanSlotSuggestion(
            dayId: day, dayName: "Day \(day)",
            planned: PlannedExercise(
                id: "slot-\(day)-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: 3, repsMin: 8, repsMax: 12,
                rirTarget: nil, rpeTarget: nil, restSeconds: 90, warmUpSets: nil, notes: nil, isOptional: false
            ),
            suggestion: ProgressionSuggestion(exerciseId: exerciseId, suggestedWeight: 50, suggestedRepsMin: 8,
                                              suggestedRepsMax: 12, reason: reason)
        )
    }

    func testOnlyStallsTriggerInPlanOrderAndTheInstructionNamesTheDay() {
        let stalled = CoachSuggestion.stalledLifts(
            slots: [
                slot("front-squat", .stall(stuckKg: 70, sessions: 3)),
                slot("bench", .holdFloorMissed(previousTopKg: 60, topReps: [9, 7], bestReps: 9)),
                slot("rear-delt", day: "day-2", .stall(stuckKg: 7.5, sessions: 4)),
            ],
            names: ["front-squat": "Front Squat", "rear-delt": "Cable Rear Delt Fly"]
        )
        let result = CoachSuggestion.evaluate(planId: "p", stalled: stalled) { _ in false }
        XCTAssertEqual(result?.lifts.map(\.exerciseId), ["front-squat", "rear-delt"])
        XCTAssertEqual(result?.title, "2 lifts have been stuck")
        XCTAssertTrue(result?.instruction.contains("Front Squat on Day day-1 (8-12 reps, 3 sessions)") ?? false)
        XCTAssertTrue(result?.instruction.contains("change only that exercise on that day") ?? false)
    }

    func testNoStallMeansNoCard() {
        let stalled = CoachSuggestion.stalledLifts(slots: [slot("bench", .increase(previousTopKg: 60))], names: [:])
        XCTAssertNil(CoachSuggestion.evaluate(planId: "p", stalled: stalled) { _ in false })
    }

    func testCapsTheLiftsSkipsSnoozedOnesAndFallsBackToTheId() {
        let stalled = CoachSuggestion.stalledLifts(
            slots: (1...6).map { slot("lift-\($0)", .stall(stuckKg: 50, sessions: 3)) }, names: [:]
        )
        let snoozed = stalled[0].snoozeKey(planId: "p")
        let result = CoachSuggestion.evaluate(planId: "p", stalled: stalled) { $0 == snoozed }
        XCTAssertEqual(result?.lifts.count, CoachSuggestion.maxLifts)
        XCTAssertEqual(result?.lifts.first?.name, "lift-2")
    }

    func testSnoozeExpiresRecoveryClearsItAndUsersAreSeparate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoachSuggestionTests"))
        defaults.removePersistentDomain(forName: "CoachSuggestionTests")
        let store = CoachSuggestionStore(defaults: defaults)
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let key = CoachSuggestion.snoozeKey(planId: "p", dayId: "d", slot: "s", exerciseId: "x", repsMin: 8, repsMax: 12)
        let otherPlanKey = CoachSuggestion.snoozeKey(planId: "q", dayId: "d", slot: "s", exerciseId: "x", repsMin: 8, repsMax: 12)

        store.snooze([key, otherPlanKey], userId: "u1", now: t0)
        XCTAssertTrue(store.isSnoozed(key, userId: "u1", now: t0.addingTimeInterval(86_400 * 20)))
        XCTAssertFalse(store.isSnoozed(key, userId: "u1", now: t0.addingTimeInterval(86_400 * 22)), "not now isn't never")
        XCTAssertFalse(store.isSnoozed(key, userId: "u2", now: t0), "another account on the device is unaffected")

        store.forgetRecovered(planId: "p", stillStalled: [], userId: "u1")
        XCTAssertFalse(store.isSnoozed(key, userId: "u1", now: t0), "a recovered lift loses its snooze")
        XCTAssertTrue(store.isSnoozed(otherPlanKey, userId: "u1", now: t0), "other plans are left alone")

        store.clear(userId: "u1")
        XCTAssertFalse(store.isSnoozed(otherPlanKey, userId: "u1", now: t0))
    }
}

/// Dashboard wiring: the card appears for a stalled slot, judges each slot
/// on its own history, and "Not now" snoozes rather than hides forever.
@MainActor
final class CoachSuggestionDashboardTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CoachSuggestionDashboardTests")
        defaults.removePersistentDomain(forName: "CoachSuggestionDashboardTests")
    }

    private func planned(_ exerciseId: String, day: String, repsMin: Int = 8, repsMax: Int = 12) -> PlannedExercise {
        PlannedExercise(
            id: "slot-\(day)-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: 3, repsMin: repsMin, repsMax: repsMax,
            rirTarget: nil, rpeTarget: nil, restSeconds: 90, warmUpSets: nil, notes: nil, isOptional: false
        )
    }

    private func day(_ id: String, _ name: String, _ slots: [PlannedExercise], number: Int = 1) -> WorkoutTemplate {
        WorkoutTemplate(
            id: id, planId: "plan-1", dayNumber: number, name: name, targetMuscleGroups: [.quads],
            estimatedDurationMinutes: 60,
            exerciseGroups: slots.map {
                ExerciseGroup(id: "g-\($0.id)", groupType: .straight, exercises: [$0], restBetweenRoundsSeconds: nil)
            },
            notes: nil
        )
    }

    private func makePlan(_ days: [WorkoutTemplate]) -> WorkoutPlan {
        WorkoutPlan(
            id: "plan-1", userId: "u1", name: "Plan", templateType: .ppl, goal: .hypertrophy,
            weekCount: 6, currentWeek: 1, workoutsPerWeek: days.count, workouts: days, deloadWeek: nil,
            isActive: true, createdAt: t0.addingTimeInterval(-86_400 * 120), aiGenerated: true, aiPromptContext: nil
        )
    }

    private var squatPlan: WorkoutPlan { makePlan([day("day-1", "Legs", [planned("front-squat", day: "day-1")])]) }

    /// A completed session on `dayId` with one log of `exerciseId` at
    /// `weight` for `reps`. `slotId` nil = a session from before logs
    /// carried their plan slot.
    private func session(daysAgo: Double, dayId: String = "day-1", exerciseId: String = "front-squat",
                         name: String = "Front Squat", slotId: String? = nil,
                         weight: Double = 70, reps: [Int] = [6, 6, 5]) -> WorkoutSession {
        let at = t0.addingTimeInterval(-86_400 * daysAgo)
        let id = "s-\(dayId)-\(daysAgo)"
        var log = ExerciseLog(
            id: "\(id)-log", sessionId: id, exerciseId: exerciseId, exerciseName: name,
            order: 1, groupType: .straight,
            sets: reps.enumerated().map { i, r in
                SetLog(id: "\(id)-\(i)", setNumber: i + 1, setType: .working, weightKg: weight, reps: r,
                       rpe: nil, isPersonalRecord: false, completedAt: at)
            },
            notes: nil
        )
        log.plannedExerciseId = slotId
        return WorkoutSession(
            id: id, userId: "u1", planId: "plan-1", workoutTemplateId: dayId, workoutName: "Day",
            startedAt: at, completedAt: at.addingTimeInterval(3600), status: .completed, exerciseLogs: [log],
            durationSeconds: 3600, notes: nil, mood: nil
        )
    }

    private func makeVM(_ workout: FakeWorkoutService, plan: WorkoutPlan, sessions: [WorkoutSession]) -> DashboardViewModel {
        workout.plans = [plan]
        workout.activePlan = plan
        workout.recentSessions = sessions
        return DashboardViewModel(referenceDate: t0, coachSuggestionStore: CoachSuggestionStore(defaults: defaults))
    }

    private func load(_ vm: DashboardViewModel, _ workout: FakeWorkoutService, at date: Date? = nil) async {
        await vm.load(
            workoutService: workout, healthKitService: FakeHealthKitService(), userId: "u1",
            referenceDate: date ?? t0, progressionService: ProgressionService()
        )
    }

    private var threeMisses: [WorkoutSession] {
        [session(daysAgo: 2), session(daysAgo: 5), session(daysAgo: 9)]
    }

    func testStalledLiftShowsTheCard() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: threeMisses)
        await load(vm, workout)
        XCTAssertEqual(vm.coachSuggestion?.lifts.map(\.name), ["Front Squat"])
        XCTAssertEqual(vm.coachSuggestion?.lifts.first?.sessions, 3)
        XCTAssertEqual(vm.coachSuggestion?.lifts.first?.dayName, "Legs")
    }

    func testTwoMissesAreNotEnough() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: Array(threeMisses.prefix(2)))
        await load(vm, workout)
        XCTAssertNil(vm.coachSuggestion)
    }

    func testHeavyDaySetsAreNotGradedAgainstTheVolumeDayRange() async {
        // Bench twice a week: volume day 10-12 first in the plan, heavy day
        // 3-5. Three heavy sessions at 100 x 5 are fine for 3-5 but would be
        // three "misses" against 10-12 if the histories were pooled. One
        // generation of logs carries slot ids, the older one doesn't.
        let volume = planned("bench", day: "day-1", repsMin: 10, repsMax: 12)
        let heavy = planned("bench", day: "day-2", repsMin: 3, repsMax: 5)
        let plan = makePlan([day("day-1", "Volume", [volume]), day("day-2", "Heavy", [heavy], number: 2)])
        let sessions = [
            session(daysAgo: 1, dayId: "day-2", exerciseId: "bench", name: "Bench", slotId: heavy.id, weight: 100, reps: [5, 5, 5]),
            session(daysAgo: 4, dayId: "day-2", exerciseId: "bench", name: "Bench", slotId: heavy.id, weight: 100, reps: [5, 5, 4]),
            session(daysAgo: 8, dayId: "day-2", exerciseId: "bench", name: "Bench", weight: 100, reps: [5, 4, 4]),
            session(daysAgo: 12, dayId: "day-1", exerciseId: "bench", name: "Bench", slotId: volume.id, weight: 70, reps: [12, 11, 10]),
        ]
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: plan, sessions: sessions)
        await load(vm, workout)
        XCTAssertNil(vm.coachSuggestion, "neither slot is stalled on its own history")

        let slots = DashboardViewModel.currentSuggestions(
            plan: plan, sessions: sessions, progressionService: ProgressionService(), exercises: [:]
        )
        XCTAssertEqual(slots.map(\.dayId), ["day-1", "day-2"])
        XCTAssertFalse(slots.contains { $0.suggestion.isStalled })
    }

    func testNotNowSnoozesThenTheCardReturns() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: threeMisses)
        await load(vm, workout)
        vm.dismissCoachSuggestion(userId: "u1", now: t0)
        XCTAssertNil(vm.coachSuggestion)

        await load(vm, workout, at: t0.addingTimeInterval(86_400 * 7))
        XCTAssertNil(vm.coachSuggestion, "still snoozed a week later")

        await load(vm, workout, at: t0.addingTimeInterval(86_400 * 22))
        XCTAssertNotNil(vm.coachSuggestion, "not now isn't never: still stuck after the snooze")
    }

    func testRecoveryClearsTheSnoozeSoANewStallShowsAgain() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: threeMisses)
        await load(vm, workout)
        vm.dismissCoachSuggestion(userId: "u1", now: t0)

        // The lifter breaks through: 10 reps at 70 is back inside the range.
        workout.recentSessions = [session(daysAgo: 0, reps: [10, 9, 8])] + threeMisses
        await load(vm, workout)
        XCTAssertNil(vm.coachSuggestion)

        // ...and stalls again inside what would have been the snooze window.
        workout.recentSessions = [session(daysAgo: -9), session(daysAgo: -5), session(daysAgo: -2)]
            + workout.recentSessions
        await load(vm, workout, at: t0.addingTimeInterval(86_400 * 10))
        XCTAssertNotNil(vm.coachSuggestion, "a new stall after recovery is a new suggestion")
    }

    func testApplyingARepRangeEditRetiresTheCardWithoutReofferingIt() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: threeMisses)
        await load(vm, workout)
        XCTAssertNotNil(vm.coachSuggestion)

        // The AI kept the exercise but moved it to 7-9: the old 6/6/5
        // sessions still miss that floor, but they were logged under 8-12.
        let edited = makePlan([day("day-1", "Legs", [planned("front-squat", day: "day-1", repsMin: 7, repsMax: 9)])])
        vm.applyCoachSuggestion(plan: edited, userId: "u1", workoutService: workout, now: t0)
        XCTAssertNil(vm.coachSuggestion)
        workout.activePlan = edited
        workout.plans = [edited]
        await load(vm, workout)
        XCTAssertNil(vm.coachSuggestion, "the edited slot isn't re-offered on the old prescription's history")
    }

    func testApplyingAnEditRepointsUpNext() async {
        let workout = FakeWorkoutService()
        let vm = makeVM(workout, plan: squatPlan, sessions: threeMisses)
        await load(vm, workout)

        let edited = makePlan([day("day-9", "Legs", [planned("hack-squat", day: "day-9")])])
        vm.applyCoachSuggestion(plan: edited, userId: "u1", workoutService: workout, now: t0)

        XCTAssertNil(vm.coachSuggestion)
        XCTAssertEqual(vm.todayWorkout?.id, "day-9")
        XCTAssertEqual(vm.effectiveTodayWorkout?.id, "day-9")
    }
}

final class AIServiceErrorCodeTests: XCTestCase {
    func testErrorCodesCarryNoContent() {
        XCTAssertEqual(AIService.errorCode(AIServiceError.invalidResponse), "invalidResponse")
        let ns = NSError(domain: "com.firebase.functions", code: 13, userInfo: [NSLocalizedDescriptionKey: "secret text"])
        XCTAssertEqual(AIService.errorCode(ns), "com.firebase.functions#13")
    }
}
