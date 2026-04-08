import Foundation

enum PRType: String, Codable, CaseIterable, Identifiable {
    case weight, reps, volume, estimated1RM

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .volume: return "Volume"
        case .estimated1RM: return "Est. 1RM"
        }
    }
}

struct PersonalRecord: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var exerciseId: String
    var exerciseName: String
    var type: PRType
    var value: Double
    var previousValue: Double?
    var achievedAt: Date
    var sessionId: String
}
