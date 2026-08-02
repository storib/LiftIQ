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

    /// Completed-session start dates inside a window, oldest first, paginated
    /// so no fixed limit can understate a high-frequency lifter's training
    /// days. Status is filtered client-side to avoid needing a composite
    /// index (same trade as `getRecentExerciseLogs`' session fetch).
    func getCompletedSessionDates(userId: String, since: Date) async throws -> [Date] {
        var dates: [Date] = []
        var lastDocument: DocumentSnapshot?
        let pageSize = 100
        // 20 pages = 2,000 sessions in-window; a safety cap, not a real bound.
        for _ in 0..<20 {
            var query = sessionCollection(userId: userId)
                .whereField("startedAt", isGreaterThanOrEqualTo: since)
                .order(by: "startedAt", descending: false)
                .limit(to: pageSize)
            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }
            let snapshot = try await query.getDocuments()
            let sessions = try snapshot.documents.compactMap { try $0.data(as: WorkoutSession.self) }
            dates += sessions.filter { $0.status == .completed }.map(\.startedAt)
            guard snapshot.documents.count == pageSize, let last = snapshot.documents.last else { break }
            lastDocument = last
        }
        return dates
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

    func deleteSession(userId: String, sessionId: String) async throws {
        try await sessionCollection(userId: userId).document(sessionId).delete()
    }
}
