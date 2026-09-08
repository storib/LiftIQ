import XCTest
@testable import LiftIQ

final class WeeklySummaryBuilderTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Monday 2026-08-31 00:00 UTC — the reviewed week.
    private let reviewWeek = Date(timeIntervalSince1970: 1_788_134_400)

    private func at(dayOffset: Int, hour: Int = 9) -> Date {
        reviewWeek.addingTimeInterval(TimeInterval(dayOffset * 86_400 + hour * 3600))
    }

    private func set(_ weightKg: Double, _ reps: Int, prIds: [String]? = nil) -> SetLog {
        SetLog(id: UUID().uuidString, setNumber: 1, setType: .working, weightKg: weightKg, reps: reps,
               rpe: nil, isPersonalRecord: prIds != nil, completedAt: Date(), personalRecordIds: prIds)
    }

    private func session(at date: Date, mood: Int? = nil, lifts: [(id: String, name: String, sets: [SetLog])]) -> WorkoutSession {
        let logs = lifts.enumerated().map { index, lift in
            ExerciseLog(id: UUID().uuidString, sessionId: "s", exerciseId: lift.id, exerciseName: lift.name,
                        order: index + 1, groupType: .straight, sets: lift.sets, notes: nil)
        }
        return WorkoutSession(id: UUID().uuidString, userId: "u1", planId: "plan-1", workoutTemplateId: nil,
                              workoutName: "Day", startedAt: date, completedAt: date.addingTimeInterval(3600),
                              status: .completed, exerciseLogs: logs, durationSeconds: 3600, notes: nil, mood: mood)
    }

    private func makePlan(perWeek: Int) -> WorkoutPlan {
        WorkoutPlan(id: "plan-1", userId: "u1", name: "P", templateType: .fullBody, goal: .strength,
                    weekCount: 6, currentWeek: 1, workoutsPerWeek: perWeek, workouts: [], deloadWeek: nil,
                    isActive: true, createdAt: reviewWeek, aiGenerated: true, aiPromptContext: nil)
    }

    func testReturnsNilWhenReviewedWeekHasNoSessions() {
        let sessions = [session(at: at(dayOffset: -3), lifts: [("bench", "Bench", [set(60, 8)])])]
        XCTAssertNil(WeeklySummaryBuilder.build(sessions: sessions, plan: nil, profile: nil,
                                                unitSystem: .metric, reviewWeekStart: reviewWeek, calendar: calendar))
    }

    func testCountsDistinctDaysConvertsVolumeAndAveragesMood() throws {
        let sessions = [
            session(at: at(dayOffset: 0, hour: 7), mood: 3, lifts: [("bench", "Bench", [set(100, 10)])]), // 1000 kg
            session(at: at(dayOffset: 0, hour: 18), mood: 4, lifts: [("row", "Row", [set(50, 10)])]),     // 500 kg
            session(at: at(dayOffset: 2), mood: nil, lifts: [("squat", "Squat", [set(100, 5, prIds: ["pr-1"])])]), // 500 kg
            session(at: at(dayOffset: -2), lifts: [("bench", "Bench", [set(95, 10)])]),                 // prior week
        ]
        let request = try XCTUnwrap(WeeklySummaryBuilder.build(
            sessions: sessions, plan: makePlan(perWeek: 3), profile: nil,
            unitSystem: .imperial, reviewWeekStart: reviewWeek, calendar: calendar
        ))

        XCTAssertEqual(request.weightUnit, "lb")
        XCTAssertEqual(request.plannedSessionsPerWeek, 3)
        XCTAssertEqual(request.lastWeek.weekStart, "2026-08-31")
        XCTAssertEqual(request.lastWeek.sessionsCompleted, 3)
        XCTAssertEqual(request.lastWeek.distinctDays, 2)
        XCTAssertEqual(request.lastWeek.prCount, 1)
        XCTAssertEqual(request.lastWeek.averageDifficulty, 3.5)
        XCTAssertEqual(request.lastWeek.totalVolume, (2000 * 2.20462).rounded(), accuracy: 1)
        XCTAssertEqual(request.priorWeek?.weekStart, "2026-08-24")
        XCTAssertEqual(request.priorWeek?.sessionsCompleted, 1)
        XCTAssertNil(request.priorWeek?.averageDifficulty)
    }

    func testLiftsUseBestE1RMSetAndPairWithPriorWeek() throws {
        let sessions = [
            session(at: at(dayOffset: 1), lifts: [("bench", "Bench Press", [set(100, 5), set(90, 12)])]), // 90x12 has the higher e1RM
            session(at: at(dayOffset: -4), lifts: [("bench", "Bench Press", [set(95, 8)])]),
            session(at: at(dayOffset: 3), lifts: [("curl", "Curl", [set(20, 12)])]),
        ]
        let request = try XCTUnwrap(WeeklySummaryBuilder.build(
            sessions: sessions, plan: nil, profile: nil,
            unitSystem: .metric, reviewWeekStart: reviewWeek, calendar: calendar
        ))

        XCTAssertEqual(request.lifts.map(\.name), ["Bench Press", "Curl"]) // sorted by e1RM desc
        XCTAssertEqual(request.lifts[0].lastWeek, .init(weight: 90, reps: 12))
        XCTAssertEqual(request.lifts[0].priorWeek, .init(weight: 95, reps: 8))
        XCTAssertNil(request.lifts[1].priorWeek)
    }

    func testLiftsCappedAtTen() throws {
        let lifts = (0..<14).map { i in (id: "ex-\(i)", name: "Ex \(i)", sets: [set(Double(20 + i), 10)]) }
        let request = try XCTUnwrap(WeeklySummaryBuilder.build(
            sessions: [session(at: at(dayOffset: 0), lifts: lifts)], plan: nil, profile: nil,
            unitSystem: .metric, reviewWeekStart: reviewWeek, calendar: calendar
        ))
        XCTAssertEqual(request.lifts.count, WeeklySummaryBuilder.maxLifts)
        XCTAssertEqual(request.lifts.first?.name, "Ex 13") // heaviest first
    }
}

final class WeeklyInsightsStoreTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private let week = Date(timeIntervalSince1970: 1_788_134_400) // 2026-08-31
    private let sample = WeeklyInsights(insights: ["a", "b", "c"], actionItem: "do", overallRating: .good)

    private func makeStore() -> (WeeklyInsightsStore, UserDefaults) {
        let suite = "WeeklyInsightsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (WeeklyInsightsStore(defaults: defaults, calendar: calendar), defaults)
    }

    func testSaveLoadRoundTripIsKeyedByWeek() {
        let (store, _) = makeStore()
        store.save(sample, userId: "u1", weekStart: week)
        XCTAssertEqual(store.load(userId: "u1", weekStart: week), sample)
        XCTAssertNil(store.load(userId: "u2", weekStart: week))
        XCTAssertNil(store.load(userId: "u1", weekStart: week.addingTimeInterval(-7 * 86_400)))
    }

    func testDismissIsPerWeek() {
        let (store, _) = makeStore()
        store.dismiss(userId: "u1", weekStart: week)
        XCTAssertTrue(store.isDismissed(userId: "u1", weekStart: week))
        XCTAssertFalse(store.isDismissed(userId: "u2", weekStart: week))
        XCTAssertFalse(store.isDismissed(userId: "u1", weekStart: week.addingTimeInterval(7 * 86_400)))
    }

    func testPruneDropsEntriesOlderThanFourWeeks() {
        let (store, _) = makeStore()
        let old = week.addingTimeInterval(-6 * 7 * 86_400)
        let recent = week.addingTimeInterval(-2 * 7 * 86_400)
        store.save(sample, userId: "u1", weekStart: old)
        store.save(sample, userId: "u1", weekStart: recent)
        store.dismiss(userId: "u1", weekStart: old)
        store.save(sample, userId: "u2", weekStart: old)

        store.save(sample, userId: "u1", weekStart: week)

        XCTAssertNil(store.load(userId: "u1", weekStart: old))
        XCTAssertFalse(store.isDismissed(userId: "u1", weekStart: old))
        XCTAssertEqual(store.load(userId: "u1", weekStart: recent), sample)
        XCTAssertEqual(store.load(userId: "u1", weekStart: week), sample)
        // Pruning is per user.
        XCTAssertEqual(store.load(userId: "u2", weekStart: old), sample)
    }

    func testClearRemovesOnlyThatUser() {
        let (store, _) = makeStore()
        store.save(sample, userId: "u1", weekStart: week)
        store.dismiss(userId: "u1", weekStart: week.addingTimeInterval(-7 * 86_400))
        store.save(sample, userId: "u2", weekStart: week)

        store.clear(userId: "u1")

        XCTAssertNil(store.load(userId: "u1", weekStart: week))
        XCTAssertFalse(store.isDismissed(userId: "u1", weekStart: week.addingTimeInterval(-7 * 86_400)))
        XCTAssertEqual(store.load(userId: "u2", weekStart: week), sample)
    }
}

@MainActor
final class WeeklyCheckInViewModelTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private let thisMonday = Date(timeIntervalSince1970: 1_788_739_200) // 2026-09-07

    private func makeStore() -> WeeklyInsightsStore {
        let suite = "WeeklyCheckInViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return WeeklyInsightsStore(defaults: defaults, calendar: calendar)
    }

    private func lastWeekSession() -> WorkoutSession {
        let set = SetLog(id: "s", setNumber: 1, setType: .working, weightKg: 60, reps: 8, rpe: nil,
                         isPersonalRecord: false, completedAt: Date())
        let log = ExerciseLog(id: "l", sessionId: "x", exerciseId: "bench", exerciseName: "Bench",
                              order: 1, groupType: .straight, sets: [set], notes: nil)
        let date = thisMonday.addingTimeInterval(-4 * 86_400)
        return WorkoutSession(id: "x", userId: "u1", planId: nil, workoutTemplateId: nil, workoutName: "Day",
                              startedAt: date, completedAt: date, status: .completed, exerciseLogs: [log],
                              durationSeconds: 0, notes: nil, mood: nil)
    }

    func testHiddenWithoutSessionsReadyWithThem() {
        let vm = WeeklyCheckInViewModel(store: makeStore(), calendar: calendar)
        vm.prepare(userId: "u1", sessions: [], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .hidden)

        vm.prepare(userId: "u1", sessions: [lastWeekSession()], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .ready)
        XCTAssertEqual(vm.reviewWeekStart, thisMonday.addingTimeInterval(-7 * 86_400))
    }

    func testCachedResultAndDismissal() {
        let store = makeStore()
        let cached = WeeklyInsights(insights: ["a", "b", "c"], actionItem: "go", overallRating: .great)
        store.save(cached, userId: "u1", weekStart: thisMonday.addingTimeInterval(-7 * 86_400))
        let vm = WeeklyCheckInViewModel(store: store, calendar: calendar)

        vm.prepare(userId: "u1", sessions: [lastWeekSession()], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .result(cached))

        vm.dismiss()
        XCTAssertEqual(vm.state, .hidden)
        vm.prepare(userId: "u1", sessions: [lastWeekSession()], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .hidden)
    }

    func testAnotherAccountOnTheSameDeviceSeesNothingOfTheFirst() {
        let store = makeStore()
        let cached = WeeklyInsights(insights: ["a", "b", "c"], actionItem: "go", overallRating: .great)
        store.save(cached, userId: "u1", weekStart: thisMonday.addingTimeInterval(-7 * 86_400))
        let vm = WeeklyCheckInViewModel(store: store, calendar: calendar)
        vm.prepare(userId: "u1", sessions: [lastWeekSession()], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .result(cached))

        vm.prepare(userId: "u2", sessions: [lastWeekSession()], plan: nil, profile: nil, unitSystem: .metric, now: thisMonday.addingTimeInterval(3600))
        XCTAssertEqual(vm.state, .ready)
    }
}
