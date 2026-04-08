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
}
