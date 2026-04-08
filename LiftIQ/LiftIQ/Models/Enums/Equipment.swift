import Foundation

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case cables
    case machines
    case bodyweight
    case bands
    case kettlebell
    case smithMachine
    case pullUpBar
    case bench
    case ezBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .cables: return "Cables"
        case .machines: return "Machines"
        case .bodyweight: return "Bodyweight"
        case .bands: return "Bands"
        case .kettlebell: return "Kettlebell"
        case .smithMachine: return "Smith Machine"
        case .pullUpBar: return "Pull-Up Bar"
        case .bench: return "Bench"
        case .ezBar: return "EZ Bar"
        }
    }

    var icon: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .cables: return "cable.connector"
        case .machines: return "gearshape.fill"
        case .bodyweight: return "figure.stand"
        case .bands: return "circle.dotted"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .smithMachine: return "square.stack.3d.up.fill"
        case .pullUpBar: return "figure.climbing"
        case .bench: return "rectangle.fill"
        case .ezBar: return "figure.curling"
        }
    }
}
