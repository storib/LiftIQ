import Foundation

struct LiftIQUser: Codable, Identifiable, Hashable {
    var id: String
    var email: String
    var displayName: String
    var profile: UserProfile
    var createdAt: Date
    var updatedAt: Date
}

struct UserProfile: Codable, Hashable {
    var experienceLevel: ExperienceLevel
    var goals: [Goal]
    var availableEquipment: [Equipment]
    var trainingDaysPerWeek: Int
    var sessionDurationMinutes: Int
    var injuries: [Injury]
    var bodyWeightKg: Double?
    var heightCm: Double?
    var dateOfBirth: Date?
    var unitSystem: UnitSystem
    var defaultRestSeconds: Int?
}

extension UserProfile {
    var effectiveDefaultRestSeconds: Int {
        defaultRestSeconds ?? 60
    }
}

struct Injury: Codable, Hashable, Identifiable {
    var id: String
    var bodyPart: String
    var severity: String
    var notes: String
}
