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
        // for the rep floor. Suggest 80 again, not 42.5.
        let deload = makeLog(id: "log-1", sets: [(40, 12), (40, 12)])
        let heavy = makeLog(id: "log-2", sets: [(80, 9), (80, 8)])
        let suggestion = service.suggest(for: makePlanned(), previousLogs: [deload, heavy], exerciseInfo: nil)
        XCTAssertEqual(suggestion?.suggestedWeight, 80)
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
}
