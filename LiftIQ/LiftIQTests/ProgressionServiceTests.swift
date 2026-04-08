import XCTest
@testable import LiftIQ

final class ProgressionServiceTests: XCTestCase {

    func testProgressionSuggestsWeightIncrease() {
        let service = ProgressionService()

        let planned = PlannedExercise(
            id: "test",
            exerciseId: "bench-press",
            order: 1,
            sets: 3,
            repsMin: 8,
            repsMax: 12,
            rirTarget: nil,
            rpeTarget: nil,
            restSeconds: 90,
            warmUpSets: nil,
            notes: nil,
            isOptional: false
        )

        let sets = (1...3).map { i in
            SetLog(
                id: "set-\(i)",
                setNumber: i,
                setType: .working,
                weightKg: 60,
                reps: 12, // Hit max reps
                rpe: nil,
                isPersonalRecord: false,
                completedAt: Date()
            )
        }

        let log = ExerciseLog(
            id: "log-1",
            sessionId: "session-1",
            exerciseId: "bench-press",
            exerciseName: "Bench Press",
            order: 1,
            groupType: .straight,
            sets: sets,
            notes: nil
        )

        let suggestion = service.suggest(for: planned, previousLogs: [log], exerciseInfo: nil)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.suggestedWeight, 62.5) // 60 + 2.5 barbell increment
        XCTAssertFalse(suggestion?.isPlateaued ?? true)
    }
}
