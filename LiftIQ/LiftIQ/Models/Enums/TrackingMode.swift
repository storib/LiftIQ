import Foundation

/// How one set of an exercise is measured.
///
/// Explicit in the catalog because nothing else in `Exercise` separates a
/// 45-second plank from a rep-counted dead bug — both are `bodyweight`
/// equipment with a `core` pattern. `Exercise.effectiveTrackingMode` derives
/// a sensible value for documents seeded before the field existed, so the
/// catalog can be filled in gradually.
enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    /// External load, counted reps — the default, and what warm-up ramps
    /// are for.
    case weightAndReps
    /// Reps are the measure and load is optional: bodyweight movements
    /// (where an entered weight is *added* load — dip belt, vest) and band
    /// work (where there is no kg to enter at all).
    case repsOnly
    /// An isometric hold measured in seconds (plank). Weight is added load.
    case timeHold
    /// Load held or carried for time (farmer's walk).
    case weightAndTime

    var id: String { rawValue }

    /// Sets are logged in seconds rather than reps.
    var tracksTime: Bool { self == .timeHold || self == .weightAndTime }

    /// A set is meaningless without a weight, so ✓ must refuse an empty
    /// weight field.
    var requiresWeight: Bool { self == .weightAndReps || self == .weightAndTime }

    /// Percentage-of-working-weight warm-up ramps only make sense for
    /// externally loaded, rep-counted lifts. A 50%-of-nothing pull-up ramp
    /// is the bug this exists to prevent.
    var allowsWarmUpSets: Bool { self == .weightAndReps }

    var displayName: String {
        switch self {
        case .weightAndReps: return "Weight and reps"
        case .repsOnly: return "Reps, load optional"
        case .timeHold: return "Timed hold"
        case .weightAndTime: return "Weighted carry"
        }
    }
}
