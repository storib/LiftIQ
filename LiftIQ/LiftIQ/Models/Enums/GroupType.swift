import Foundation

enum GroupType: String, Codable, CaseIterable, Identifiable {
    case straight
    case superset
    case triset
    case circuit
    case dropSet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .straight: return "Straight Sets"
        case .superset: return "Superset"
        case .triset: return "Triset"
        case .circuit: return "Circuit"
        case .dropSet: return "Drop Set"
        }
    }
}
