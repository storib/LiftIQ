import Foundation

struct Exercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var primaryMuscleGroup: MuscleGroup
    var secondaryMuscleGroups: [MuscleGroup]
    var equipment: [Equipment]
    var movementPattern: MovementPattern
    var difficulty: ExperienceLevel
    var youtubeVideoId: String
    var instructions: String
    var tips: [String]
    var alternatives: [String]
    var isCompound: Bool
    var tags: [String]
    /// How a set is measured. Optional-and-last so catalog documents written
    /// before the field existed keep decoding; `effectiveTrackingMode`
    /// derives the value when it's absent.
    var trackingMode: TrackingMode? = nil

    /// True when the movement is loaded by the lifter's own body rather than
    /// an external implement, so a set can be completed with reps alone and
    /// any entered weight means *added* load (dip belt, weighted vest).
    var isBodyweight: Bool {
        let unloaded: Set<Equipment> = [.bodyweight, .pullUpBar, .bench]
        return equipment.contains(.bodyweight)
            && equipment.allSatisfy { unloaded.contains($0) }
    }

    /// The catalog's declared mode, or one derived from the equipment for
    /// exercises seeded before `trackingMode` existed. Equipment can tell
    /// loaded from unloaded; it cannot tell a hold from a rep, so isometrics
    /// need the explicit field.
    var effectiveTrackingMode: TrackingMode {
        trackingMode ?? (isBodyweight ? .repsOnly : .weightAndReps)
    }

    /// Sets are logged in seconds held rather than reps performed.
    var tracksTime: Bool { effectiveTrackingMode.tracksTime }

    /// ✓ can complete a set with an empty weight field.
    var allowsUnloadedSets: Bool { !effectiveTrackingMode.requiresWeight }

    /// Whether a percentage-of-working-weight warm-up ramp makes sense here.
    var allowsWarmUpSets: Bool { effectiveTrackingMode.allowsWarmUpSets }
}
