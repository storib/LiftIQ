import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case traps
    case lats
    case rearDelts
    case sideDelts
    case frontDelts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .core: return "Core"
        case .traps: return "Traps"
        case .lats: return "Lats"
        case .rearDelts: return "Rear Delts"
        case .sideDelts: return "Side Delts"
        case .frontDelts: return "Front Delts"
        }
    }

    var category: String {
        switch self {
        case .chest, .back, .shoulders, .biceps, .triceps, .forearms, .traps, .lats, .rearDelts, .sideDelts, .frontDelts:
            return "Upper"
        case .quads, .hamstrings, .glutes, .calves:
            return "Lower"
        case .core:
            return "Core"
        }
    }
}
