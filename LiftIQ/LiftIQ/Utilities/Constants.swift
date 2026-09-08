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
