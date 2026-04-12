import Foundation

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var planId: String?
    var workoutTemplateId: String?
    var workoutName: String
    var startedAt: Date
    var completedAt: Date?
    var status: SessionStatus
    var exerciseLogs: [ExerciseLog]
    var durationSeconds: Int
    var notes: String?
    var mood: Int?

    var totalVolumeKg: Double {
        exerciseLogs.reduce(0) { $0 + $1.totalVolume }
    }
}

struct ExerciseLog: Codable, Identifiable, Hashable {
    var id: String
    var sessionId: String
    var exerciseId: String
    var exerciseName: String
    var order: Int
    var groupType: GroupType
    var sets: [SetLog]
    var notes: String?

    var totalVolume: Double {
        sets.filter { $0.setType == .working }.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

struct SetLog: Codable, Identifiable, Hashable {
    var id: String
    var setNumber: Int
    var setType: SetType
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var isPersonalRecord: Bool
    var completedAt: Date?

    var estimated1RM: Double {
        guard reps > 0 else { return weightKg }
        return weightKg * (1 + Double(reps) / 30.0)  // Epley formula
    }
}
