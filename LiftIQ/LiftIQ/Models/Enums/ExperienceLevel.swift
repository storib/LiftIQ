import Foundation

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .beginner:
            return "Less than 1 year of consistent training. Focus on learning proper form and building a foundation."
        case .intermediate:
            return "1-3 years of consistent training. Comfortable with compound lifts and ready for periodized programming."
        case .advanced:
            return "3+ years of consistent training. Experienced with various training methodologies and pushing toward peak performance."
        }
    }
}
