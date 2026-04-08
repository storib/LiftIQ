import Foundation

struct ExerciseGroup: Codable, Identifiable, Hashable {
    var id: String
    var groupType: GroupType
    var exercises: [PlannedExercise]
    var restBetweenRoundsSeconds: Int?
}

struct PlannedExercise: Codable, Identifiable, Hashable {
    var id: String
    var exerciseId: String
    var order: Int
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var rirTarget: Int?
    var rpeTarget: Double?
    var restSeconds: Int
    var warmUpSets: [WarmUpSet]?
    var notes: String?
    var isOptional: Bool
}

struct WarmUpSet: Codable, Hashable, Identifiable {
    var id: String
    var percentageOf1RM: Double
    var reps: Int
    var label: String
}
