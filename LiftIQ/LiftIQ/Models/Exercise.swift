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

    /// True when the movement is loaded by the lifter's own body rather than
    /// an external implement, so a set can be completed with reps alone and
    /// any entered weight means *added* load (dip belt, weighted vest).
    var isBodyweight: Bool {
        let unloaded: Set<Equipment> = [.bodyweight, .pullUpBar, .bench]
        return equipment.contains(.bodyweight)
            && equipment.allSatisfy { unloaded.contains($0) }
    }
}
