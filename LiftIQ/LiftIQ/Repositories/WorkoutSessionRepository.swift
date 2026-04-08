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

    func getSessionsForExercise(userId: String, exerciseId: String, limit: Int = 10) async throws -> [WorkoutSession] {
        let sessions = try await getSessions(userId: userId, limit: 100)
        return sessions.filter { session in
            session.exerciseLogs.contains { $0.exerciseId == exerciseId }
        }.prefix(limit).map { $0 }
    }

    func saveSession(_ session: WorkoutSession) async throws {
        try sessionCollection(userId: session.userId).document(session.id).setData(from: session)
    }

    func deleteSession(userId: String, sessionId: String) async throws {
        try await sessionCollection(userId: userId).document(sessionId).delete()
    }
}
