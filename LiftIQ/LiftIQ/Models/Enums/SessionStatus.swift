import Foundation

enum SessionStatus: String, Codable, CaseIterable, Identifiable {
    case inProgress
    case completed
    case abandoned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        }
    }
}
