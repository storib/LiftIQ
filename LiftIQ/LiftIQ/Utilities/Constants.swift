import Foundation

enum Constants {
    static let barbellIncrement = 2.5  // kg
    static let dumbbellIncrement = 2.0 // kg
    static let machineIncrement = 2.5  // kg
    // Consecutive rep-floor misses at the same top weight before suggesting a
    // back-off. Deliberately an acute stall signal, not a "plateau" claim:
    // per-set e1RM observations carry ~8-10% noise while trained lifters gain
    // 1-3%/year, so no per-session rule can detect a true plateau.
    static let stallThreshold = 3
    /// Seconds added to a timed hold once the prescribed ceiling is reached —
    /// the time-domain equivalent of one weight increment.
    static let holdProgressionStepSeconds = 5
    /// Longest hold the set row accepts, so a mistyped entry can't become a
    /// 10-hour plank (and stays inside the PR rules' duration cap).
    static let maxHoldSeconds = 3600
    /// Shortest prescription believable as seconds. Below this, a hold's
    /// `repsMin`/`repsMax` is a rep range that predates the seconds
    /// convention — see `HoldPrescription`.
    static let minHoldPrescriptionSeconds = 15
    static let defaultHoldSeconds = 30

    // Forgotten-session handling. The reminder fires well above any planned
    // session length so it never nags a real workout, and leaves an hour to
    // come back before the session is treated as forgotten and the dashboard
    // offers to close it out at the last set.
    static let sessionReminderDelaySeconds: TimeInterval = 2 * 3600
    static let staleSessionThresholdSeconds: TimeInterval = 3 * 3600
    /// Upper bound accepted when editing a finished session's times — long
    /// enough for any real day at the gym, short enough to catch a wrong day.
    static let maxEditableSessionDurationSeconds: TimeInterval = 12 * 3600
}
