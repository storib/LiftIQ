import Foundation

enum SetType: String, Codable, CaseIterable, Identifiable {
    case warmUp
    case working
    case dropSet
    case failureSet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warmUp: return "Warm Up"
        case .working: return "Working"
        case .dropSet: return "Drop Set"
        case .failureSet: return "Failure Set"
        }
    }
}
