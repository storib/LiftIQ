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

    func getActivePlan(userId: String) async throws -> WorkoutPlan? {
        let snapshot = try await planCollection(userId: userId).whereField("isActive", isEqualTo: true).limit(to: 1).getDocuments()
        return try snapshot.documents.first.map { try $0.data(as: WorkoutPlan.self) }
    }

    func savePlan(_ plan: WorkoutPlan) async throws {
        try planCollection(userId: plan.userId).document(plan.id).setData(from: plan)
    }

    func updatePlan(_ plan: WorkoutPlan) async throws {
        try planCollection(userId: plan.userId).document(plan.id).setData(from: plan, merge: true)
    }

    func deletePlan(userId: String, planId: String) async throws {
        try await planCollection(userId: userId).document(planId).delete()
    }

    func deactivateAllPlans(userId: String) async throws {
        let plans = try await getPlans(userId: userId).filter { $0.isActive }
        for plan in plans {
            try await planCollection(userId: userId).document(plan.id).updateData(["isActive": false])
        }
    }
}
