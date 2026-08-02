import XCTest
@testable import LiftIQ

final class StrengthTrendTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Deterministic ±scatter pattern standing in for e1RM noise.
    private let noise: [Double] = [0.04, -0.06, 0.08, -0.03, 0.05, -0.08, 0.02, -0.04, 0.07, -0.02, 0.03, -0.05]

    private func series(sessions: Int, daysApart: Double, startE1RM: Double, annualRate: Double, noisy: Bool) -> ([Date], [Double]) {
        var dates: [Date] = []
        var values: [Double] = []
        for i in 0..<sessions {
            let t = Double(i) * daysApart
            dates.append(start.addingTimeInterval(t * day))
            let trend = log(startE1RM) + (annualRate / 365) * t
            let e = noisy ? noise[i % noise.count] : 0
            values.append(exp(trend + e))
        }
        return (dates, values)
    }

    func testTooFewSessionsIsInsufficient() {
        let (dates, values) = series(sessions: 5, daysApart: 7, startE1RM: 100, annualRate: 0, noisy: true)
        let trend = StrengthTrend.fit(dates: dates, e1RMs: values)
        XCTAssertEqual(trend?.verdict, .insufficientData)
    }

    func testTypicalTrainedProgressReadsAsUnclearNotDecline() {
        // 12 weekly sessions at a true +2%/yr with realistic noise: the
        // honest answer is "can't tell", never "plateau" or "decline".
        let (dates, values) = series(sessions: 12, daysApart: 7, startE1RM: 100, annualRate: 0.02, noisy: true)
        let trend = StrengthTrend.fit(dates: dates, e1RMs: values)
        XCTAssertEqual(trend?.verdict, .unclear)
    }

    func testFlatSeriesIsUnclearNotDeclining() {
        let (dates, values) = series(sessions: 12, daysApart: 7, startE1RM: 100, annualRate: 0, noisy: true)
        let trend = StrengthTrend.fit(dates: dates, e1RMs: values)
        XCTAssertEqual(trend?.verdict, .unclear)
    }

    func testStrongCleanDeclineIsDetected() {
        // A genuine regression (injury/detraining scale, −60%/yr) over six
        // months of weekly data clears the confidence gate.
        let (dates, values) = series(sessions: 26, daysApart: 7, startE1RM: 100, annualRate: -0.6, noisy: true)
        let trend = StrengthTrend.fit(dates: dates, e1RMs: values)
        XCTAssertEqual(trend?.verdict, .declining)
        XCTAssertLessThan(trend?.annualRate ?? 0, 0)
    }

    func testNoviceScaleProgressIsDetected() {
        // First-year gains (~40%/yr here) over six months are detectable.
        let (dates, values) = series(sessions: 26, daysApart: 7, startE1RM: 60, annualRate: 0.4, noisy: true)
        let trend = StrengthTrend.fit(dates: dates, e1RMs: values)
        XCTAssertEqual(trend?.verdict, .progressing)
    }

    func testNonPositiveValuesAndSingletonReturnNil() {
        XCTAssertNil(StrengthTrend.fit(dates: [start], e1RMs: [100]))
        XCTAssertNil(StrengthTrend.fit(dates: [start, start.addingTimeInterval(day)], e1RMs: [0, -5]))
    }
}
