import Foundation
import FirebaseFirestore

final class WorkoutSessionRepository {
    private let db = Firestore.firestore()

    private func sessionCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("workoutSessions")
    }

    func getSessions(userId: String, limit: Int = 50) async throws -> [WorkoutSession] {
        let snapshot = try await sessionCollection(userId: userId)
            .order(by: "startedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: WorkoutSession.self) }
    }

    func getActiveSession(userId: String) async throws -> WorkoutSession? {
        let snapshot = try await sessionCollection(userId: userId)
            .whereField("status", isEqualTo: SessionStatus.inProgress.rawValue)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first.map { try $0.data(as: WorkoutSession.self) }
    }

    func saveSession(_ session: WorkoutSession) async throws {
        try sessionCollection(userId: session.userId).document(session.id).setData(from: session)
    }
}
