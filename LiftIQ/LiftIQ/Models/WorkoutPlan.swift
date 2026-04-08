import Foundation

struct WorkoutPlan: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var name: String
    var templateType: TemplateType
    var goal: Goal
    var weekCount: Int
    var currentWeek: Int
    var workoutsPerWeek: Int
    var workouts: [WorkoutTemplate]
    var deloadWeek: Int?
    var isActive: Bool
    var createdAt: Date
    var aiGenerated: Bool
    var aiPromptContext: String?
}
