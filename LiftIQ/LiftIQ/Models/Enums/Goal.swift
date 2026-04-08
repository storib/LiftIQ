import Foundation

enum Goal: String, Codable, CaseIterable, Identifiable {
    case strength
    case hypertrophy
    case endurance
    case generalFitness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .endurance: return "Endurance"
        case .generalFitness: return "General Fitness"
        }
    }

    var repRangeDescription: String {
        switch self {
        case .strength:
            return "1-5 reps per set with heavy weight"
        case .hypertrophy:
            return "8-12 reps per set with moderate weight"
        case .endurance:
            return "15-25 reps per set with lighter weight"
        case .generalFitness:
            return "8-15 reps per set with moderate weight"
        }
    }

    var restSecondsRange: ClosedRange<Int> {
        switch self {
        case .strength:
            return 180...300
        case .hypertrophy:
            return 60...120
        case .endurance:
            return 30...60
        case .generalFitness:
            return 60...90
        }
    }
}
