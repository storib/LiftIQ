import Foundation

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }

    var weightUnit: String {
        switch self {
        case .metric: return "kg"
        case .imperial: return "lbs"
        }
    }

    var lengthUnit: String {
        switch self {
        case .metric: return "cm"
        case .imperial: return "in"
        }
    }
}
