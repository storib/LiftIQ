import Foundation
import FirebaseFunctions

/// Whether an AI modification rewrites the saved plan or just one session's
/// workout. Raw values match the modifyWorkout cloud function's scope enum.
enum AIModificationScope: String {
    case plan
    case workout
}

/// Result of a modifyWorkout call: exactly one of plan/workout is set,
/// matching the requested scope.
struct AIWorkoutModification {
    let changeSummary: String
    let plan: WorkoutPlan?
    let workout: WorkoutTemplate?
}

@MainActor
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

        let callable = functions.httpsCallable("generateWorkoutPlan")
        callable.timeoutInterval = 180
        let result = try await callable.call(data)
        guard let json = result.data as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            throw AIServiceError.invalidResponse
        }
        return try Self.makeDecoder().decode(WorkoutPlan.self, from: jsonData)
    }

    /// Asks the AI to modify an existing plan (scope .plan, permanent) or a
    /// single day (scope .workout, one session). The server validates every
    /// exercise against the user's equipment and preserves identity fields.
    func modifyWorkout(
        scope: AIModificationScope,
        instruction: String,
        plan: WorkoutPlan?,
        workout: WorkoutTemplate?,
        profile: UserProfile
    ) async throws -> AIWorkoutModification {
        isGenerating = true
        defer { isGenerating = false }

        var data: [String: Any] = [
            "scope": scope.rawValue,
            "instruction": instruction,
            "availableEquipment": profile.availableEquipment.map { $0.rawValue },
            "injuries": profile.injuries.map { ["bodyPart": $0.bodyPart, "severity": $0.severity, "notes": $0.notes] },
            "experienceLevel": profile.experienceLevel.rawValue
        ]
        if let plan {
            data["plan"] = try Self.jsonObject(from: plan)
        }
        if let workout {
            data["workout"] = try Self.jsonObject(from: workout)
        }

        let callable = functions.httpsCallable("modifyWorkout")
        callable.timeoutInterval = 180
        let result = try await callable.call(data)
        guard let json = result.data as? [String: Any],
              let changeSummary = json["changeSummary"] as? String else {
            throw AIServiceError.invalidResponse
        }

        var modifiedPlan: WorkoutPlan?
        var modifiedWorkout: WorkoutTemplate?
        if let planJSON = json["plan"] {
            let planData = try JSONSerialization.data(withJSONObject: planJSON)
            modifiedPlan = try Self.makeDecoder().decode(WorkoutPlan.self, from: planData)
        }
        if let workoutJSON = json["workout"] {
            let workoutData = try JSONSerialization.data(withJSONObject: workoutJSON)
            modifiedWorkout = try Self.makeDecoder().decode(WorkoutTemplate.self, from: workoutData)
        }
        guard modifiedPlan != nil || modifiedWorkout != nil else {
            throw AIServiceError.invalidResponse
        }
        return AIWorkoutModification(changeSummary: changeSummary, plan: modifiedPlan, workout: modifiedWorkout)
    }

    /// Callable payloads are dictionaries; dates go out as ISO 8601 strings
    /// to satisfy the server's z.string().datetime() validation.
    private static func jsonObject(from value: some Encodable) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            // Created per call: ISO8601DateFormatter statics on this @MainActor
            // class can't be touched from the nonisolated decoding closure.
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
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
