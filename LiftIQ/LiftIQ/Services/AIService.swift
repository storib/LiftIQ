import Foundation
import FirebaseFunctions

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

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            if let date = iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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
