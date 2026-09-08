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
    /// Training-block boundaries, stamped by "Keep going" on the block review.
    /// Declared last with defaults so the memberwise init stays
    /// source-compatible and existing documents decode unchanged.
    var blockStartedAt: Date? = nil
    var blockNumber: Int? = nil

    var effectiveBlockStart: Date { blockStartedAt ?? createdAt }
    var effectiveBlockNumber: Int { blockNumber ?? 1 }
}
