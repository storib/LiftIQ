import Foundation
import FirebaseFirestore

final class WorkoutPlanRepository {
    private let db = Firestore.firestore()

    private func planCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("workoutPlans")
    }

    func getPlans(userId: String) async throws -> [WorkoutPlan] {
        let snapshot = try await planCollection(userId: userId).order(by: "createdAt", descending: true).getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: WorkoutPlan.self) }
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        try planCollection(userId: plan.userId).document(plan.id).setData(from: plan)
    }

    /// Atomically deactivates every other active plan and writes `plan` in a
    /// single batch, so there is never a moment with zero or two active plans.
    func saveAndActivate(_ plan: WorkoutPlan) async throws {
        let collection = planCollection(userId: plan.userId)
        let otherActivePlans = try await getPlans(userId: plan.userId)
            .filter { $0.isActive && $0.id != plan.id }

        let batch = db.batch()
        for activePlan in otherActivePlans {
            batch.updateData(["isActive": false], forDocument: collection.document(activePlan.id))
        }
        try batch.setData(from: plan, forDocument: collection.document(plan.id))
        try await batch.commit()
    }

    func deletePlan(userId: String, planId: String) async throws {
        try await planCollection(userId: userId).document(planId).delete()
    }
}
