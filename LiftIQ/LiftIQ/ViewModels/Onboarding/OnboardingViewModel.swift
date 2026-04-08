import SwiftUI

@Observable
final class OnboardingViewModel {
    var currentStep = 0
    let totalSteps = 8

    // Step 1: Experience
    var experienceLevel: ExperienceLevel = .beginner

    // Step 2: Goals
    var selectedGoals: Set<Goal> = []

    // Step 3: Equipment
    var selectedEquipment: Set<Equipment> = []

    // Step 4: Schedule
    var trainingDaysPerWeek = 3
    var sessionDurationMinutes = 60

    // Step 5: Injuries
    var injuries: [Injury] = []
    var newInjuryBodyPart = ""
    var newInjurySeverity = "Mild"
    var newInjuryNotes = ""

    // Step 6: Body Metrics
    var unitSystem: UnitSystem = .metric
    var bodyWeight: String = ""
    var height: String = ""

    // State
    var isLoading = false
    var errorMessage: String?

    var canAdvance: Bool {
        switch currentStep {
        case 0: return true // welcome
        case 1: return true // experience always has a default
        case 2: return !selectedGoals.isEmpty
        case 3: return !selectedEquipment.isEmpty
        case 4: return true // schedule always valid
        case 5: return true // injuries are optional
        case 6: return true // body metrics are optional
        case 7: return true // summary
        default: return false
        }
    }

    var progress: Double {
        Double(currentStep) / Double(totalSteps - 1)
    }

    func next() {
        if currentStep < totalSteps - 1 {
            withAnimation { currentStep += 1 }
        }
    }

    func back() {
        if currentStep > 0 {
            withAnimation { currentStep -= 1 }
        }
    }

    func addInjury() {
        guard !newInjuryBodyPart.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let injury = Injury(
            id: UUID().uuidString,
            bodyPart: newInjuryBodyPart.trimmingCharacters(in: .whitespaces),
            severity: newInjurySeverity,
            notes: newInjuryNotes.trimmingCharacters(in: .whitespaces)
        )
        injuries.append(injury)
        newInjuryBodyPart = ""
        newInjurySeverity = "Mild"
        newInjuryNotes = ""
    }

    func removeInjury(_ injury: Injury) {
        injuries.removeAll { $0.id == injury.id }
    }

    func buildProfile() -> UserProfile {
        let weightKg: Double? = {
            guard let value = Double(bodyWeight), value > 0 else { return nil }
            return unitSystem == .imperial ? value / 2.20462 : value
        }()

        let heightCm: Double? = {
            guard let value = Double(height), value > 0 else { return nil }
            return unitSystem == .imperial ? value * 2.54 : value
        }()

        return UserProfile(
            experienceLevel: experienceLevel,
            goals: Array(selectedGoals),
            availableEquipment: Array(selectedEquipment),
            trainingDaysPerWeek: trainingDaysPerWeek,
            sessionDurationMinutes: sessionDurationMinutes,
            injuries: injuries,
            bodyWeightKg: weightKg,
            heightCm: heightCm,
            dateOfBirth: nil,
            unitSystem: unitSystem
        )
    }

    func saveProfile(authService: AuthService) async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = buildProfile()
            try await authService.updateProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
