import Foundation

/// Why today's workout was adapted, and what changed. Persisted on the
/// session (`WorkoutSession.adaptation`) so the beta can see which
/// adaptations get used and whether they stick. Flat, string-keyed
/// enums — no payload enums — so Firestore encoding stays trivial.
enum WorkoutAdaptationKind: String, Codable {
    case shortOnTime
    case equipmentBusy
    case differentGym
}

enum WorkoutChangeKind: String, Codable {
    case removedExercise
    case reducedSets
    case swappedExercise
    case restShortened
    case addedExercise
}

struct WorkoutChange: Codable, Hashable, Identifiable {
    var id: String
    var kind: WorkoutChangeKind
    var exerciseId: String
    var exerciseName: String
    var replacementExerciseId: String? = nil
    var replacementName: String? = nil
    /// Sets or rest seconds, depending on `kind`.
    var fromValue: Int? = nil
    var toValue: Int? = nil
    /// Rule-derived, shown to the lifter as the "why".
    var reason: String
}

struct WorkoutAdaptation: Codable, Hashable {
    var kind: WorkoutAdaptationKind
    var targetMinutes: Int? = nil
    var busyExerciseId: String? = nil
    var gymSetupId: String? = nil
    var changes: [WorkoutChange]
    var usedAI: Bool
    var acceptedAt: Date
}

/// In-memory result of an adaptation, before the lifter accepts it.
struct AdaptedWorkout: Hashable {
    var template: WorkoutTemplate
    var changes: [WorkoutChange]
    var record: WorkoutAdaptation
    var minutesBefore: Int
    var minutesAfter: Int
    var sourceTemplateId: String
    var planId: String?
}
