import Foundation
import Observation

/// What the app remembers about how this lifter trains: gym setups, usual
/// substitutions, avoided exercises, per-exercise notes, and loadable
/// increments. Everything lives inside `UserProfile` (no rules change; the
/// profile is validated as an opaque map) and is written through the same
/// whole-profile update the rest of the app uses — last write wins across
/// devices, which is acceptable for a beta.
@MainActor
@Observable
final class MemoryService {
    private let profileStore: any ProfileStoring

    init(profileStore: any ProfileStoring) {
        self.profileStore = profileStore
    }

    var preferences: [String: ExercisePreference] {
        profileStore.currentProfile?.exercisePreferences ?? [:]
    }

    var activeEquipment: Set<Equipment> {
        Set(profileStore.currentProfile?.effectiveGymSetup.equipment ?? Equipment.allCases)
    }

    var weightIncrements: WeightIncrements {
        profileStore.currentProfile?.effectiveWeightIncrements ?? .standard
    }

    /// Best-effort: a swap that isn't remembered costs nothing but the next
    /// suggestion, so this never surfaces an error.
    func recordUsualAlternative(for exerciseId: String, replacement: String) async {
        try? await mutatePreference(for: exerciseId) {
            $0.usualAlternativeId = replacement
            $0.lastUsedAt = Date()
        }
    }

    func setNote(_ note: String?, for exerciseId: String) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await mutatePreference(for: exerciseId) {
            $0.note = (trimmed ?? "").isEmpty ? nil : trimmed
        }
    }

    func setAvoided(_ avoided: Bool, for exerciseId: String) async throws {
        try await mutatePreference(for: exerciseId) {
            $0.avoided = avoided ? true : nil
        }
    }

    /// Saves the setups and keeps `availableEquipment` equal to the default
    /// setup's equipment, so AI generation and modification — which read
    /// `availableEquipment` — follow the default gym without payload changes.
    func saveGymSetups(_ setups: [GymSetup]) async throws {
        guard var profile = profileStore.currentProfile else { return }
        var normalized = setups
        if !normalized.isEmpty, !normalized.contains(where: \.isDefault) {
            normalized[0].isDefault = true
        }
        // Exactly one default.
        var seenDefault = false
        for index in normalized.indices {
            if normalized[index].isDefault {
                if seenDefault { normalized[index].isDefault = false }
                seenDefault = true
            }
        }
        profile.gymSetups = normalized.isEmpty ? nil : normalized
        if let defaultSetup = normalized.first(where: \.isDefault) {
            profile.availableEquipment = defaultSetup.equipment
        }
        try await profileStore.updateProfile(profile)
    }

    func setWeightIncrements(_ increments: WeightIncrements?) async throws {
        guard var profile = profileStore.currentProfile else { return }
        profile.weightIncrementsKg = increments
        try await profileStore.updateProfile(profile)
    }

    private func mutatePreference(for exerciseId: String, _ change: (inout ExercisePreference) -> Void) async throws {
        guard var profile = profileStore.currentProfile else { return }
        var prefs = profile.exercisePreferences ?? [:]
        var pref = prefs[exerciseId] ?? ExercisePreference()
        change(&pref)
        if pref.isEmpty { prefs.removeValue(forKey: exerciseId) } else { prefs[exerciseId] = pref }
        profile.exercisePreferences = prefs.isEmpty ? nil : prefs
        try await profileStore.updateProfile(profile)
    }
}
