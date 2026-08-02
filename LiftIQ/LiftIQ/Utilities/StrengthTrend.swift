import Foundation

/// Long-window strength trend from per-session e1RM observations.
///
/// Formula-based e1RM carries ~9-10% per-observation scatter (log-space SD
/// ≈ 0.085-0.103 measured on ~300k near-failure sets), while a trained
/// lifter's true gain is only ~1-3%/year — the noise dwarfs the signal on
/// any short window. So this estimator fits a log-linear trend with a FIXED
/// observation noise (the per-user sample is far too small to estimate its
/// own variance) and only makes a directional claim when the confidence
/// interval actually clears zero. Everything else is honestly "can't tell
/// yet", which is the common case and the correct answer.
struct StrengthTrend {
    /// Annualized fractional rate of change (0.02 = +2%/year).
    let annualRate: Double
    /// One standard error of `annualRate`.
    let annualRateSE: Double
    let observationCount: Int
    let spanDays: Int

    /// Log-space SD of a single best-set e1RM observation. Epley-class
    /// formulas measure ≈ 0.103; best-set-per-session filtering removes some
    /// within-session scatter, so split toward the best-case 0.085.
    static let observationSD = 0.09

    static let minObservations = 8
    static let minSpanDays = 56

    enum Verdict {
        /// Too few sessions or too short a span to say anything.
        case insufficientData
        /// The interval spans both healthy progress and decline.
        case unclear
        /// ~90% confident the true trend is positive.
        case progressing
        /// ~90% confident the true trend is negative.
        case declining
    }

    var verdict: Verdict {
        guard observationCount >= Self.minObservations, spanDays >= Self.minSpanDays else {
            return .insufficientData
        }
        // One-sided z at ~90% confidence.
        let z = 1.28
        if annualRate - z * annualRateSE > 0 { return .progressing }
        if annualRate + z * annualRateSE < 0 { return .declining }
        return .unclear
    }

    /// OLS fit of ln(value) against time. Returns nil when a slope isn't even
    /// computable (fewer than 2 distinct dates or non-positive values).
    /// `observationSD` defaults to single-lift e1RM noise; series that average
    /// several lifts per point (the overview's strength index) pass a smaller
    /// value.
    static func fit(dates: [Date], e1RMs: [Double], observationSD: Double = Self.observationSD) -> StrengthTrend? {
        let points = zip(dates, e1RMs)
            .filter { $0.1 > 0 }
            .map { (t: $0.0.timeIntervalSince1970 / 86_400, y: log($0.1)) }
            .sorted { $0.t < $1.t }
        guard points.count >= 2 else { return nil }

        let n = Double(points.count)
        let meanT = points.reduce(0) { $0 + $1.t } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        let sxx = points.reduce(0) { $0 + ($1.t - meanT) * ($1.t - meanT) }
        guard sxx > 0 else { return nil }
        let sxy = points.reduce(0) { $0 + ($1.t - meanT) * ($1.y - meanY) }

        let slopePerDay = sxy / sxx
        let sePerDay = observationSD / sxx.squareRoot()
        return StrengthTrend(
            annualRate: slopePerDay * 365,
            annualRateSE: sePerDay * 365,
            observationCount: points.count,
            spanDays: Int((points.last!.t - points.first!.t).rounded())
        )
    }
}
