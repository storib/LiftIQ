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
    /// Memory: named equipment sets, per-exercise preferences, and loadable
    /// increments. Declared last and optional so existing documents decode
    /// (synthesized Decodable requires optional for absent keys; a defaulted
    /// non-optional would fail on every pre-existing user).
    var gymSetups: [GymSetup]? = nil
    var exercisePreferences: [String: ExercisePreference]? = nil
    var weightIncrementsKg: WeightIncrements? = nil
}

/// A named set of available equipment. The default setup mirrors
/// `availableEquipment`, which is what plan generation and modification read.
struct GymSetup: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var equipment: [Equipment]
    var isDefault: Bool
}

/// What the lifter has taught the app about one exercise.
struct ExercisePreference: Codable, Hashable {
    var usualAlternativeId: String? = nil
    var avoided: Bool? = nil
    var note: String? = nil
    var lastUsedAt: Date? = nil

    var isAvoided: Bool { avoided ?? false }
    var isEmpty: Bool { usualAlternativeId == nil && !isAvoided && (note ?? "").isEmpty }
}

/// Smallest loadable step per equipment class, in kg.
struct WeightIncrements: Codable, Hashable {
    var barbellKg: Double
    var dumbbellKg: Double
    var machineKg: Double

    static let standard = WeightIncrements(
        barbellKg: Constants.barbellIncrement,
        dumbbellKg: Constants.dumbbellIncrement,
        machineKg: Constants.machineIncrement
    )

    func increment(for exercise: Exercise?) -> Double {
        guard let exercise else { return barbellKg }
        if exercise.equipment.contains(.barbell) { return barbellKg }
        if exercise.equipment.contains(.dumbbell) { return dumbbellKg }
        return machineKg
    }
}

extension UserProfile {
    var effectiveDefaultRestSeconds: Int {
        defaultRestSeconds ?? 60
    }

    /// Saved setups, or one synthesized from `availableEquipment` so every
    /// profile has a gym to swap within.
    var effectiveGymSetups: [GymSetup] {
        if let gymSetups, !gymSetups.isEmpty { return gymSetups }
        return [GymSetup(id: "profile", name: "My Gym", equipment: availableEquipment, isDefault: true)]
    }

    var effectiveGymSetup: GymSetup {
        let setups = effectiveGymSetups
        return setups.first { $0.isDefault } ?? setups[0]
    }

    var effectiveWeightIncrements: WeightIncrements {
        weightIncrementsKg ?? .standard
    }

    func preference(for exerciseId: String) -> ExercisePreference? {
        exercisePreferences?[exerciseId]
    }

    var avoidedExerciseIds: Set<String> {
        Set((exercisePreferences ?? [:]).filter { $0.value.isAvoided }.map(\.key))
    }
}

struct Injury: Codable, Hashable, Identifiable {
    var id: String
    var bodyPart: String
    var severity: String
    var notes: String
}
