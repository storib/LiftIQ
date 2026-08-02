import XCTest
@testable import LiftIQ

final class ProgressOverviewTests: XCTestCase {

    private let day: TimeInterval = 86_400
    // A Monday, so weekly bucketing is stable regardless of locale week rules.
    private let start = Date(timeIntervalSince1970: 1_699_833_600) // 2023-11-13

    private func record(_ exerciseId: String, dayOffset: Double, e1RM: Double, volume: Double = 1000) -> ProgressRecord {
        ProgressRecord(
            id: "s\(dayOffset)_\(exerciseId)",
            userId: "u1",
            exerciseId: exerciseId,
            date: start.addingTimeInterval(dayOffset * day),
            estimated1RM: e1RM,
            bestSetWeight: e1RM * 0.8,
            bestSetReps: 8,
            totalVolume: volume,
            totalSets: 3
        )
    }

    func testIndexStartsAtBaselineAndTracksUniformGains() {
        // Two lifts of very different absolute strength both gain 10% by week
        // three: the index must read +10% regardless of the kg magnitudes.
        var records: [ProgressRecord] = []
        for (week, factor) in [(0, 1.0), (1, 1.0), (2, 1.1)] {
            records.append(record("squat", dayOffset: Double(week * 7), e1RM: 150 * factor))
            records.append(record("curl", dayOffset: Double(week * 7), e1RM: 20 * factor))
        }
        let overview = ProgressOverview.compute(records: records)

        XCTAssertEqual(overview.weeklyStrengthIndex.count, 3)
        XCTAssertEqual(overview.weeklyStrengthIndex.first?.value ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(overview.weeklyStrengthIndex.last?.value ?? 0, 1.1, accuracy: 0.005)
        XCTAssertEqual(overview.strengthChangePercent ?? 0, 10, accuracy: 0.5)
    }

    func testWeeklyVolumeSumsAcrossExercises() {
        let records = [
            record("squat", dayOffset: 0, e1RM: 150, volume: 3000),
            record("curl", dayOffset: 1, e1RM: 20, volume: 500),
            record("squat", dayOffset: 7, e1RM: 150, volume: 3200),
        ]
        let overview = ProgressOverview.compute(records: records, through: start.addingTimeInterval(7 * day))

        XCTAssertEqual(overview.weeklyVolume.map(\.value), [3500, 3200])
    }

    func testTrainingDaysCountDistinctDaysNotRecords() {
        // Three records across two distinct days in one week = 2 training days.
        let records = [
            record("squat", dayOffset: 0, e1RM: 150),
            record("bench", dayOffset: 0.1, e1RM: 80),
            record("curl", dayOffset: 2, e1RM: 20),
        ]
        let overview = ProgressOverview.compute(records: records, through: start)

        XCTAssertEqual(overview.weeklyTrainingDays.first?.value, 2)
    }

    func testMissedWeeksAppearAsZerosNotGaps() {
        // Two weeks off between sessions: the volume series must contain the
        // zeros, and "this week" (nothing logged yet) must read 0.
        let records = [
            record("squat", dayOffset: 0, e1RM: 150, volume: 3000),
            record("squat", dayOffset: 21, e1RM: 150, volume: 3100),
        ]
        let overview = ProgressOverview.compute(records: records, through: start.addingTimeInterval(28 * day))

        XCTAssertEqual(overview.weeklyVolume.map(\.value), [3000, 0, 0, 3100, 0])
        XCTAssertEqual(overview.weeklyTrainingDays.map(\.value), [1, 0, 0, 1, 0])
        // The strength index keeps only observed weeks — no strength
        // measurement exists for a skipped week.
        XCTAssertEqual(overview.weeklyStrengthIndex.count, 2)
    }

    func testSessionDatesDriveTrainingDaysSoBodyweightOnlyDaysCount() {
        // A bodyweight-only session produces no weighted progressRecords;
        // when session dates are supplied they define the day counts.
        let records = [record("squat", dayOffset: 0, e1RM: 150)]
        let sessionDates = [
            start,
            start.addingTimeInterval(2 * day), // bodyweight-only day
        ]
        let overview = ProgressOverview.compute(records: records, sessionDates: sessionDates, through: start)

        XCTAssertEqual(overview.weeklyTrainingDays.first?.value, 2)
    }

    func testLateAddedExerciseDoesNotDistortIndex() {
        // A new lift entering at week 2 contributes a zero delta at entry, not
        // a spike, because its baseline is its own first observations.
        var records: [ProgressRecord] = []
        for week in 0..<4 {
            records.append(record("squat", dayOffset: Double(week * 7), e1RM: 150))
        }
        records.append(record("deadlift", dayOffset: 14, e1RM: 180))
        records.append(record("deadlift", dayOffset: 21, e1RM: 180))
        let overview = ProgressOverview.compute(records: records)

        for point in overview.weeklyStrengthIndex {
            XCTAssertEqual(point.value, 1.0, accuracy: 0.001)
        }
    }

    func testZeroE1RMRecordsAreExcluded() {
        let records = [
            record("plank", dayOffset: 0, e1RM: 0, volume: 100),
            record("squat", dayOffset: 0, e1RM: 150, volume: 3000),
            record("squat", dayOffset: 7, e1RM: 150, volume: 3000),
        ]
        let overview = ProgressOverview.compute(records: records, through: start.addingTimeInterval(7 * day))

        XCTAssertEqual(overview.weeklyStrengthIndex.count, 2)
        XCTAssertEqual(overview.weeklyVolume.first?.value, 3000)
    }

    func testCompositeTrendUsesReducedNoise() {
        // 10 lifts × 26 weeks all rising 15%/yr: a single lift at σ=0.09
        // cannot call this (SE ≈ 12%/yr), but averaging 10 observations per
        // weekly point shrinks the SE enough for the composite to call it.
        var records: [ProgressRecord] = []
        for lift in 0..<10 {
            for week in 0..<26 {
                let t = Double(week * 7)
                let e1 = 100.0 * exp((0.15 / 365) * t)
                records.append(record("lift\(lift)", dayOffset: t, e1RM: e1))
            }
        }
        let overview = ProgressOverview.compute(records: records)

        XCTAssertEqual(overview.trend?.verdict, .progressing)
    }

    func testEmptyRecordsProduceEmptyOverview() {
        let overview = ProgressOverview.compute(records: [])
        XCTAssertTrue(overview.weeklyStrengthIndex.isEmpty)
        XCTAssertNil(overview.strengthChangePercent)
        XCTAssertNil(overview.trend)
    }
}
