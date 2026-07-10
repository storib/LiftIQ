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
    /// Ids of the PersonalRecords this set produced, so uncompleting the set
    /// can roll back exactly those records. Optional so documents written
    /// before this field existed keep decoding (decodeIfPresent).
    var personalRecordIds: [String]? = nil

    var estimated1RM: Double {
        Epley.estimated1RM(weight: weightKg, reps: reps)
    }
}

// MARK: - Session Factory

extension WorkoutSession {
    /// Builds a fresh in-progress session from a template, one exercise log
    /// per planned exercise in group order, with all sets zeroed. Warm-up
    /// sets (from the plan, or synthesized by WarmUpPlanner for the opening
    /// exercises) precede the working sets; setNumber counts within each set
    /// type so working sets always read 1...N.
    static func create(from template: WorkoutTemplate, userId: String, planId: String?) -> WorkoutSession {
        var exerciseLogs: [ExerciseLog] = []
        var order = 0
        let warmUpSpecs = WarmUpPlanner.specs(forGroups: template.exerciseGroups)

        for group in template.exerciseGroups {
            for planned in group.exercises {
                var sets: [SetLog] = []
                for (warmUpIndex, _) in (warmUpSpecs[planned.exerciseId] ?? []).enumerated() {
                    sets.append(SetLog(
                        id: UUID().uuidString,
                        setNumber: warmUpIndex + 1,
                        setType: .warmUp,
                        weightKg: 0,
                        reps: 0,
                        rpe: nil,
                        isPersonalRecord: false,
                        completedAt: nil
                    ))
                }
                for setNum in 1...planned.sets {
                    sets.append(SetLog(
                        id: UUID().uuidString,
                        setNumber: setNum,
                        setType: .working,
                        weightKg: 0,
                        reps: 0,
                        rpe: nil,
                        isPersonalRecord: false,
                        completedAt: nil
                    ))
                }

                let fallbackName = planned.exerciseId
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized

                exerciseLogs.append(ExerciseLog(
                    id: UUID().uuidString,
                    sessionId: "",
                    exerciseId: planned.exerciseId,
                    exerciseName: fallbackName,
                    order: order,
                    groupType: group.groupType,
                    sets: sets,
                    notes: nil
                ))
                order += 1
            }
        }

        let sessionId = UUID().uuidString
        // Backfill sessionId into exercise logs
        for i in exerciseLogs.indices {
            exerciseLogs[i].sessionId = sessionId
        }

        return WorkoutSession(
            id: sessionId,
            userId: userId,
            planId: planId,
            workoutTemplateId: template.id,
            workoutName: template.name,
            startedAt: Date(),
            completedAt: nil,
            status: .inProgress,
            exerciseLogs: exerciseLogs,
            durationSeconds: 0,
            notes: nil,
            mood: nil
        )
    }
}
