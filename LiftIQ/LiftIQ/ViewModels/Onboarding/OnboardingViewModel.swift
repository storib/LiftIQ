import SwiftUI

@MainActor
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
    var unitSystem: UnitSystem = .imperial
    var bodyWeight: String = ""
    var height: String = ""

    // State
    var isLoading = false
    var errorMessage: String?
    /// Set when the user declines AI consent so the final step can finish
    /// onboarding honestly instead of promising a generated program.
    var declinedAIConsent = false

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
            return UnitConversionService.convertToKg(value, from: unitSystem)
        }()

        let heightCm: Double? = {
            guard let value = Double(height), value > 0 else { return nil }
            return UnitConversionService.convertToCm(value, from: unitSystem)
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
            unitSystem: unitSystem,
            defaultRestSeconds: 60
        )
    }

    /// Best-fit template based on the user's chosen training days.
    var recommendedTemplate: TemplateType {
        switch trainingDaysPerWeek {
        case 1...3: return .fullBody
        case 4:     return .upperLower
        case 5:     return .broSplit
        default:    return .ppl // 6-7
        }
    }

    func saveProfileAndGeneratePlan(
        authService: AuthService,
        aiService: AIService,
        workoutService: any WorkoutServicing
    ) async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = buildProfile()

            // Generate and save the plan BEFORE marking onboarding complete.
            // updateProfile flips needsOnboarding to false, which unmounts this
            // view — so anything awaited after it can't surface errors here.
            if AIConsentManager.hasConsented, let userId = authService.currentUserId {
                var plan = try await aiService.generateWorkoutPlan(
                    profile: profile,
                    templateType: recommendedTemplate
                )
                plan.userId = userId
                plan.isActive = true
                try await workoutService.savePlan(plan)
            }

            try await authService.updateProfile(profile)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
