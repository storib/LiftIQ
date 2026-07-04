import SwiftUI

@MainActor
@Observable
final class WorkoutPlanListViewModel {
    var isLoading = false
    var errorMessage: String?

    func load(workoutService: any WorkoutServicing, userId: String) async {
        isLoading = true
        do {
            try await workoutService.loadPlans(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deletePlan(workoutService: any WorkoutServicing, userId: String, planId: String) async {
        do {
            try await workoutService.deletePlan(userId: userId, planId: planId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
