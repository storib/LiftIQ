import Foundation

enum PRType: String, Codable, CaseIterable, Identifiable {
    /// `duration` is a hold time in seconds (planks, carries); every other
    /// type is a weight-or-rep value. Mirrored by the Firestore rules'
    /// type whitelist, which caps durations higher than weights.
    case weight, reps, volume, estimated1RM, duration

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .reps: return "Reps"
        case .volume: return "Volume"
        case .estimated1RM: return "Est. 1RM"
        case .duration: return "Longest Hold"
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
