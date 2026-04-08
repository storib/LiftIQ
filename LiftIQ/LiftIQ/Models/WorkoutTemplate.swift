import Foundation

struct WorkoutTemplate: Codable, Identifiable, Hashable {
    var id: String
    var planId: String
    var dayNumber: Int
    var name: String
    var targetMuscleGroups: [MuscleGroup]
    var estimatedDurationMinutes: Int
    var exerciseGroups: [ExerciseGroup]
    var notes: String?
}
