import Foundation

enum Goal: String, Codable, CaseIterable, Identifiable {
    case strength
    case hypertrophy
    case endurance
    case generalFitness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strength: return "Get Stronger"
        case .hypertrophy: return "Build Muscle"
        case .endurance: return "Boost Endurance"
        case .generalFitness: return "Stay Fit"
        }
    }

    var subtitle: String {
        switch self {
        case .strength:
            return "Lift heavier and build raw power"
        case .hypertrophy:
            return "Grow and tone your muscles"
        case .endurance:
            return "Last longer with higher stamina"
        case .generalFitness:
            return "All-around health and wellness"
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
