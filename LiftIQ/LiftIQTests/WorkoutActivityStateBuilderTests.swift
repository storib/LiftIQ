import XCTest
@testable import LiftIQ

final class WorkoutActivityStateBuilderTests: XCTestCase {

    private func set(_ id: String, _ type: SetType = .working) -> SetLog {
        SetLog(id: id, setNumber: 1, setType: type, weightKg: 0, reps: 0, rpe: nil, isPersonalRecord: false, completedAt: nil)
    }

    private func log(_ id: String, name: String, exerciseId: String, sets: [SetLog], group: GroupType = .straight) -> ExerciseLog {
        ExerciseLog(id: id, sessionId: "s", exerciseId: exerciseId, exerciseName: name, order: 1, groupType: group, sets: sets, notes: nil)
    }

    private func session(_ logs: [ExerciseLog]) -> WorkoutSession {
        WorkoutSession(id: "s", userId: "u", planId: nil, workoutTemplateId: nil, workoutName: "Push",
                       startedAt: Date(), completedAt: nil, status: .inProgress, exerciseLogs: logs,
                       durationSeconds: 0, notes: nil, mood: nil)
    }

    private func planned(_ exerciseId: String, repsMin: Int = 8, repsMax: Int = 12) -> PlannedExercise {
        PlannedExercise(id: "p-\(exerciseId)", exerciseId: exerciseId, order: 1, sets: 3, repsMin: repsMin, repsMax: repsMax,
                        rirTarget: nil, rpeTarget: nil, restSeconds: 90, warmUpSets: nil, notes: nil, isOptional: false)
    }

    private func refs(_ ordered: [WorkoutActivityStateBuilder.SetRef]) -> [String] {
        ordered.map { "\($0.logIndex).\($0.setIndex)" }
    }

    func testStraightGroupsOrderSetBySet() {
        let s = session([
            log("a", name: "Bench", exerciseId: "bench", sets: [set("a1", .warmUp), set("a2"), set("a3")]),
            log("b", name: "Row", exerciseId: "row", sets: [set("b1"), set("b2")]),
        ])
        let groups = [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench")], restBetweenRoundsSeconds: nil),
                      ExerciseGroup(id: "g2", groupType: .straight, exercises: [planned("row")], restBetweenRoundsSeconds: nil)]
        let ordered = WorkoutActivityStateBuilder.orderedSets(session: s, groupMap: [0: 0, 1: 1], groups: groups)
        XCTAssertEqual(refs(ordered), ["0.0", "0.1", "0.2", "1.0", "1.1"])
    }

    func testSupersetOrdersRoundByRoundWithWarmUpsFirst() {
        let s = session([
            log("a", name: "Curl", exerciseId: "curl", sets: [set("a-w1", .warmUp), set("a1"), set("a2")], group: .superset),
            log("b", name: "Pushdown", exerciseId: "pushdown", sets: [set("b1"), set("b2"), set("b3")], group: .superset),
        ])
        let groups = [ExerciseGroup(id: "g1", groupType: .superset, exercises: [planned("curl"), planned("pushdown")], restBetweenRoundsSeconds: 60)]
        let ordered = WorkoutActivityStateBuilder.orderedSets(session: s, groupMap: [0: 0, 1: 0], groups: groups)
        // Warm-up round (only curl has one), then working rounds paired by position; pushdown's extra 3rd set trails.
        XCTAssertEqual(refs(ordered), ["0.0", "0.1", "1.0", "0.2", "1.1", "1.2"])
    }

    func testCurrentIsFirstIncompleteAndNextCrossesExercises() {
        let s = session([
            log("a", name: "Bench", exerciseId: "bench", sets: [set("a1"), set("a2")]),
            log("b", name: "Row", exerciseId: "row", sets: [set("b1")]),
        ])
        let groups = [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench")], restBetweenRoundsSeconds: nil),
                      ExerciseGroup(id: "g2", groupType: .straight, exercises: [planned("row")], restBetweenRoundsSeconds: nil)]
        let ordered = WorkoutActivityStateBuilder.orderedSets(session: s, groupMap: [0: 0, 1: 1], groups: groups)
        let (current, next) = WorkoutActivityStateBuilder.currentAndNext(ordered: ordered, session: s, completedSetIds: ["a1"])
        XCTAssertEqual(current, .init(logIndex: 0, setIndex: 1))
        XCTAssertEqual(next, .init(logIndex: 1, setIndex: 0))

        let state = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: ["a1"], groupMap: [0: 0, 1: 1], groups: groups,
            setInputs: [:], suggestedSetInputs: [:], unitSystem: .imperial, restEndDate: nil, restTotalSeconds: nil
        )
        XCTAssertEqual(state.exerciseName, "Bench")
        XCTAssertEqual(state.setLabel, "Set 2 of 2 · 8-12 reps")
        XCTAssertEqual(state.nextUpLabel, "Next: Row")
        XCTAssertEqual(state.completedSets, 1)
        XCTAssertEqual(state.totalSets, 3)
    }

    func testAllDoneState() {
        let s = session([log("a", name: "Bench", exerciseId: "bench", sets: [set("a1")])])
        let state = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: ["a1"], groupMap: [0: 0],
            groups: [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench")], restBetweenRoundsSeconds: nil)],
            setInputs: [:], suggestedSetInputs: [:], unitSystem: .metric, restEndDate: nil, restTotalSeconds: nil
        )
        XCTAssertEqual(state.exerciseName, "All sets done")
        XCTAssertNil(state.nextUpLabel)
        XCTAssertEqual(state.completedSets, 1)
    }

    func testSetLabelPrefersTypedWeightOverGhostInDisplayUnits() {
        let s = session([log("a", name: "Bench", exerciseId: "bench", sets: [set("a1"), set("a2")])])
        let groups = [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench", repsMin: 10, repsMax: 10)], restBetweenRoundsSeconds: nil)]
        let ghostOnly = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: [], groupMap: [0: 0], groups: groups,
            setInputs: [:], suggestedSetInputs: ["a1": SetInput(weight: "185", reps: "10"), "a2": SetInput(weight: "185", reps: "10")],
            unitSystem: .imperial, restEndDate: nil, restTotalSeconds: nil
        )
        XCTAssertEqual(ghostOnly.setLabel, "Set 1 of 2 · 10 reps · 185 lb")
        XCTAssertEqual(ghostOnly.nextUpLabel, "Next: Set 2 of 2 · 185 lb")

        let typed = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: [], groupMap: [0: 0], groups: groups,
            setInputs: ["a1": SetInput(weight: "190", reps: "")], suggestedSetInputs: ["a1": SetInput(weight: "185", reps: "10")],
            unitSystem: .imperial, restEndDate: nil, restTotalSeconds: nil
        )
        XCTAssertEqual(typed.setLabel, "Set 1 of 2 · 10 reps · 190 lb")
    }

    func testWarmUpLabelCountsWithinType() {
        let s = session([log("a", name: "Bench", exerciseId: "bench", sets: [set("w1", .warmUp), set("w2", .warmUp), set("a1")])])
        let groups = [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench")], restBetweenRoundsSeconds: nil)]
        let state = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: ["w1"], groupMap: [0: 0], groups: groups,
            setInputs: [:], suggestedSetInputs: ["w2": SetInput(weight: "40", reps: "5")],
            unitSystem: .metric, restEndDate: nil, restTotalSeconds: nil
        )
        XCTAssertEqual(state.setLabel, "Warm-up 2 of 2 · 5 reps · 40 kg")
    }

    func testUnmappedLogsAppendAsStraightAndRestIsPassedThrough() {
        let s = session([
            log("a", name: "Bench", exerciseId: "bench", sets: [set("a1")]),
            log("b", name: "Extra", exerciseId: "extra", sets: [set("b1"), set("b2")]),
        ])
        let groups = [ExerciseGroup(id: "g1", groupType: .straight, exercises: [planned("bench")], restBetweenRoundsSeconds: nil)]
        let ordered = WorkoutActivityStateBuilder.orderedSets(session: s, groupMap: [0: 0], groups: groups)
        XCTAssertEqual(refs(ordered), ["0.0", "1.0", "1.1"])

        let end = Date().addingTimeInterval(90)
        let state = WorkoutActivityStateBuilder.contentState(
            session: s, completedSetIds: ["a1"], groupMap: [0: 0], groups: groups,
            setInputs: [:], suggestedSetInputs: [:], unitSystem: .metric, restEndDate: end, restTotalSeconds: 90
        )
        XCTAssertEqual(state.restEndDate, end)
        XCTAssertEqual(state.restTotalSeconds, 90)
        XCTAssertTrue(state.isResting)
    }

    func testRestRangeIsStableAndNilOnceExpired() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let end = now.addingTimeInterval(30)
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: "Bench", setLabel: "Set 1 of 3", nextUpLabel: nil,
            completedSets: 1, totalSets: 3, restEndDate: end, restTotalSeconds: 90
        )
        // Mid-rest: lower bound is the rest start, not "now".
        XCTAssertEqual(state.restRange(now: now), end.addingTimeInterval(-90)...end)
        // Rendered after the rest ended (app suspended): no inverted range, no trap.
        XCTAssertNil(state.restRange(now: end.addingTimeInterval(1)))
        XCTAssertNil(state.restRange(now: end))
        XCTAssertTrue(state.isResting)
        // Not resting at all.
        var idle = state
        idle.restEndDate = nil
        XCTAssertNil(idle.restRange(now: now))
    }
}
