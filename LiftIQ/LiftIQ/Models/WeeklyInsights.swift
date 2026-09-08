import Foundation

/// Request body for the generateWeeklyInsights function. Field names and
/// bounds mirror `WeeklyInsightsRequestSchema` on the server; weights are
/// already in the user's display unit (a display boundary, declared by
/// `weightUnit`). Optionals encode as absent, which the server accepts.
struct WeeklyInsightsRequest: Encodable, Equatable {
    struct WeekSummary: Encodable, Equatable {
        let weekStart: String
        let sessionsCompleted: Int
        let totalVolume: Double
        let distinctDays: Int
        let prCount: Int
        let averageDifficulty: Double?
    }

    struct LiftWeek: Encodable, Equatable {
        let weight: Double
        let reps: Int
    }

    struct Lift: Encodable, Equatable {
        let name: String
        let lastWeek: LiftWeek
        let priorWeek: LiftWeek?
    }

    let weightUnit: String
    let plannedSessionsPerWeek: Int?
    let goal: String?
    let experienceLevel: String?
    let lastWeek: WeekSummary
    let priorWeek: WeekSummary?
    let lifts: [Lift]
}

struct WeeklyInsights: Codable, Equatable {
    enum Rating: String, Codable {
        case great
        case good
        case needsAttention
    }

    let insights: [String]
    let actionItem: String
    let overallRating: Rating
}
