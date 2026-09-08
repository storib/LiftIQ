import XCTest
@testable import LiftIQ

final class ProgressionServiceTests: XCTestCase {

    private let service = ProgressionService()

    private func makePlanned(repsMin: Int = 8, repsMax: Int = 12) -> PlannedExercise {
        PlannedExercise(
            id: "test",
            exerciseId: "bench-press",
            order: 1,
            sets: 3,
            repsMin: repsMin,
            repsMax: repsMax,
            rirTarget: nil,
            rpeTarget: nil,
            restSeconds: 90,
            warmUpSets: nil,
            notes: nil,
            isOptional: false
        )
    }

    /// One prior session: each (weightKg, reps) pair becomes a working set.
    private func makeLog(id: String = "log-1", sets: [(Double, Int)]) -> ExerciseLog {
        ExerciseLog(
            id: id,
            sessionId: "session-\(id)",
            exerciseId: "bench-press",
            exerciseName: "Bench Press",
            order: 1,
            groupType: .straight,
            sets: sets.enumerated().map { i, pair in
                SetLog(
                    id: "\(id)-set-\(i)",
                    setNumber: i + 1,
                    setType: .working,
                    weightKg: pair.0,
                    reps: pair.1,
                    rpe: nil,
                    isPersonalRecord: false,
                    completedAt: Date()
                )
            },
            notes: nil
        )
    }

    func testAllSetsAtMaxRepsSuggestsIncrease() {
        let log = makeLog(sets: [(60, 12), (60, 12), (60, 12)])
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5) // 60 + 2.5 barbell increment
        XCTAssertFalse(suggestion?.isStalled ?? true)
    }

    func testRampingSetsAnchorToTopSetNotFirstSet() {
        // Lifter ramps 50→55→60 and maxes reps at the top: progression must
        // build on 60, not on the opening 50.
        let log = makeLog(sets: [(50, 12), (55, 12), (60, 12)])
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5)
    }

    func testTopSetShortOfMaxHoldsAtTopWeight() {
        let log = makeLog(sets: [(50, 12), (60, 9)])
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 60)
        XCTAssertFalse(suggestion?.isStalled ?? true)
    }

    func testDeloadSessionDoesNotDragSuggestionBelowRecentBest() {
        // Last session was a light one; the week before, 80 kg was handled
        // for the rep floor. Suggest 80 again, not 42.5 — and the reason
        // still names 40 kg as where those reps happened.
        let deload = makeLog(id: "log-1", sets: [(40, 12), (40, 12)])
        let heavy = makeLog(id: "log-2", sets: [(80, 9), (80, 8)])
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [deload, heavy], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 80)
        XCTAssertEqual(suggestion?.reason, .increase(previousTopKg: 40))

        let partial = makeLog(id: "log-1", sets: [(40, 12), (40, 11), (40, 10)])
        let held = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: [partial, heavy], exerciseInfo: nil)
        XCTAssertEqual(held?.suggestedWeight, 80)
        XCTAssertEqual(held?.reason, .holdNearTarget(previousTopKg: 40, topReps: [12, 11, 10], repsToGo: 3))
    }

    func testThreeFloorMissesAtSameWeightSuggestsBackOff() {
        let fail = { (id: String) in self.makeLog(id: id, sets: [(60, 6), (60, 6), (60, 5)]) }
        let logs = [fail("log-1"), fail("log-2"), fail("log-3")]
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil)
        XCTAssertTrue(suggestion?.isStalled ?? false)
        // ~10% back-off rounded down to a 2.5 kg increment: 60 * 0.9 = 54 → 52.5.
        XCTAssertEqual(suggestion?.suggestedWeight, 52.5)
    }

    func testFloorMissesAtDifferentWeightsAreNotAStall() {
        // The lifter just moved up to 62.5 and missed the floor once; the
        // earlier misses were at 60. Rebuilding after an increase is normal
        // double progression, not a stall.
        let logs = [
            makeLog(id: "log-1", sets: [(62.5, 6), (62.5, 6)]),
            makeLog(id: "log-2", sets: [(60, 7), (60, 6)]),
            makeLog(id: "log-3", sets: [(60, 6), (60, 6)]),
        ]
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil)
        XCTAssertFalse(suggestion?.isStalled ?? true)
    }

    func testRepsWithinRangeNeverStalls() {
        // Holding a weight inside the rep range for many sessions is a hold,
        // not a stall warning.
        let hold = { (id: String) in self.makeLog(id: id, sets: [(60, 10), (60, 9), (60, 8)]) }
        let logs = (1...5).map { hold("log-\($0)") }
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil)
        XCTAssertFalse(suggestion?.isStalled ?? true)
        XCTAssertEqual(suggestion?.suggestedWeight, 60)
    }

    // MARK: - Top set drives progression

    func testMixedSetsWithBestAtCeilingIncrease() {
        // 15/12/9 on an 8-15 plan: the first set reached the ceiling and no
        // set fell under the floor — that is a lifter ready to move up.
        let log = makeLog(sets: [(60, 15), (60, 12), (60, 9)])
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5)
        XCTAssertEqual(suggestion?.reason, .increase(previousTopKg: 60))
    }

    func testAllAboveFloorButShortOfCeilingHoldsNearTarget() {
        let log = makeLog(sets: [(60, 12), (60, 11), (60, 10)])
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 60)
        XCTAssertEqual(suggestion?.reason, .holdNearTarget(previousTopKg: 60, topReps: [12, 11, 10], repsToGo: 3))
    }

    func testFloorMissOnLaterSetHoldsNotStall() {
        // One tired last set under the floor is drop-off, not a stall — even
        // three sessions in a row, because the best set keeps meeting it.
        let session = { (id: String) in self.makeLog(id: id, sets: [(60, 15), (60, 12), (60, 7)]) }
        let logs = [session("log-1"), session("log-2"), session("log-3")]
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: logs, exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 60)
        XCTAssertEqual(suggestion?.reason, .holdFloorMissed(previousTopKg: 60, topReps: [15, 12, 7], bestReps: 15))
        XCTAssertFalse(suggestion?.isStalled ?? true)
    }

    func testThreeSessionsAllBelowFloorStall() {
        let fail = { (id: String) in self.makeLog(id: id, sets: [(60, 7), (60, 6), (60, 6)]) }
        let logs = [fail("log-1"), fail("log-2"), fail("log-3")]
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: logs, exerciseInfo: nil)
        XCTAssertEqual(suggestion?.reason, .stall(stuckKg: 60, sessions: 3))
        XCTAssertEqual(suggestion?.suggestedWeight, 52.5)
    }

    func testBestSetAtFloorNeverStalls() {
        let session = { (id: String) in self.makeLog(id: id, sets: [(60, 9), (60, 7), (60, 7)]) }
        let logs = [session("log-1"), session("log-2"), session("log-3")]
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: logs, exerciseInfo: nil)
        XCTAssertFalse(suggestion?.isStalled ?? true)
        XCTAssertEqual(suggestion?.suggestedWeight, 60)
    }

    func testStallNeedsALoadableBackoff() {
        // At one increment there is nothing to back off to; flagging a stall
        // that can't change the weight would just be noise.
        let fail = { (id: String) in self.makeLog(id: id, sets: [(2.5, 5), (2.5, 5), (2.5, 5)]) }
        let logs = [fail("log-1"), fail("log-2"), fail("log-3")]
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil)
        XCTAssertFalse(suggestion?.isStalled ?? true)
        XCTAssertEqual(suggestion?.suggestedWeight, 2.5)
    }

    func testFirstSessionAtHigherWeightIsRebuilding() {
        let logs = [
            makeLog(id: "log-1", sets: [(62.5, 9), (62.5, 8), (62.5, 8)]),
            makeLog(id: "log-2", sets: [(60, 12), (60, 12), (60, 12)]),
        ]
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5)
        XCTAssertEqual(suggestion?.reason, .holdRebuilding(previousTopKg: 62.5, topReps: [9, 8, 8], repsToGo: 3))
    }

    func testBodyweightAtCeilingSuggestsNoLoad() {
        let log = makeLog(sets: [(0, 15), (0, 15), (0, 15)])
        let suggestion = service.suggest(for: makePlanned(repsMin: 8, repsMax: 15), previousLogs: [log], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 0)
        XCTAssertEqual(suggestion?.reason, .bodyweight(bestReps: 15))
    }

    // MARK: - Custom increments

    func testIncreaseUsesCustomBarbellIncrement() {
        let log = makeLog(sets: [(60, 12), (60, 12), (60, 12)])
        let custom = WeightIncrements(barbellKg: 1.25, dumbbellKg: 1, machineKg: 5)
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [log], exerciseInfo: nil, increments: custom)
        XCTAssertEqual(suggestion?.suggestedWeight, 61.25)
    }

    func testBackoffUsesCustomIncrement() {
        let fail = { (id: String) in self.makeLog(id: id, sets: [(60, 6), (60, 6), (60, 5)]) }
        let logs = [fail("log-1"), fail("log-2"), fail("log-3")]
        let custom = WeightIncrements(barbellKg: 5, dumbbellKg: 1, machineKg: 5)
        let suggestion = service.suggest(for: makePlanned(), previousLogs: logs, exerciseInfo: nil, increments: custom)
        // 60 * 0.9 = 54 → rounded down to a 5 kg step = 50.
        XCTAssertEqual(suggestion?.suggestedWeight, 50)
        XCTAssertTrue(suggestion?.isStalled ?? false)
    }
}
