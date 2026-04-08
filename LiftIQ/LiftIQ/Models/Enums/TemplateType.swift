import Foundation

enum TemplateType: String, Codable, CaseIterable, Identifiable {
    case ppl
    case upperLower
    case fullBody
    case broSplit
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ppl: return "Push Pull Legs"
        case .upperLower: return "Upper Lower"
        case .fullBody: return "Full Body"
        case .broSplit: return "Bro Split"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .ppl:
            return "A six-day split dividing workouts into push, pull, and leg days, each trained twice per week."
        case .upperLower:
            return "A four-day split alternating between upper body and lower body sessions."
        case .fullBody:
            return "Each session targets all major muscle groups, ideal for 2-4 days per week."
        case .broSplit:
            return "A five-day split dedicating each day to a single muscle group for maximum volume."
        case .custom:
            return "A fully customizable split tailored to your specific needs and schedule."
        }
    }

    var recommendedDaysPerWeek: Int {
        switch self {
        case .ppl: return 6
        case .upperLower: return 4
        case .fullBody: return 3
        case .broSplit: return 5
        case .custom: return 0
        }
    }
}
