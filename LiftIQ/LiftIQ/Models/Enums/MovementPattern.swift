import Foundation

enum MovementPattern: String, Codable, CaseIterable, Identifiable {
    case horizontalPush
    case horizontalPull
    case verticalPush
    case verticalPull
    case hipHinge
    case squat
    case lunge
    case isolation
    case carry
    case core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontalPush: return "Horizontal Push"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPush: return "Vertical Push"
        case .verticalPull: return "Vertical Pull"
        case .hipHinge: return "Hip Hinge"
        case .squat: return "Squat"
        case .lunge: return "Lunge"
        case .isolation: return "Isolation"
        case .carry: return "Carry"
        case .core: return "Core"
        }
    }
}
