import Foundation
import FirebaseFunctions

@Observable
final class AIService {
    private let functions = Functions.functions()
    var isGenerating = false
    var error: String?

    func generateWorkoutPlan(profile: UserProfile, templateType: TemplateType) async throws -> WorkoutPlan {
        isGenerating = true
        defer { isGenerating = false }

        let data: [String: Any] = [
            "experienceLevel": profile.experienceLevel.rawValue,
            "goals": profile.goals.map { $0.rawValue },
            "availableEquipment": profile.availableEquipment.map { $0.rawValue },
            "trainingDaysPerWeek": profile.trainingDaysPerWeek,
            "sessionDurationMinutes": profile.sessionDurationMinutes,
            "injuries": profile.injuries.map { ["bodyPart": $0.bodyPart, "severity": $0.severity, "notes": $0.notes] },
            "templateType": templateType.rawValue
        ]

        let result = try await functions.httpsCallable("generateWorkoutPlan").call(data)
        guard let json = result.data as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            throw AIServiceError.invalidResponse
        }
        return try JSONDecoder().decode(WorkoutPlan.self, from: jsonData)
    }

    func suggestExerciseSwap(
        currentExercise: Exercise,
        availableEquipment: [Equipment],
        otherExercisesInWorkout: [String]
    ) async throws -> [Exercise] {
        let data: [String: Any] = [
            "currentExercise": [
                "name": currentExercise.name,
                "primaryMuscle": currentExercise.primaryMuscleGroup.rawValue,
                "movementPattern": currentExercise.movementPattern.rawValue
            ],
            "availableEquipment": availableEquipment.map { $0.rawValue },
            "otherExercisesInWorkout": otherExercisesInWorkout
        ]

        let result = try await functions.httpsCallable("suggestExerciseSwap").call(data)
        guard let json = result.data as? [[String: Any]],
              let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            throw AIServiceError.invalidResponse
        }
        return try JSONDecoder().decode([Exercise].self, from: jsonData)
    }
}

enum AIServiceError: LocalizedError {
    case invalidResponse
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI service"
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        }
    }
}
