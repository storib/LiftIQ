import Foundation
import FirebaseFirestore

final class ProgressRecordRepository {
    private let db = Firestore.firestore()

    private func recordCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("progressRecords")
    }

    /// Every exercise's records inside a bounded window, oldest first,
    /// paginated — feeds the cross-exercise overview. Pagination makes the
    /// window semantics unconditional: neither the baselines (earliest) nor
    /// "this week" (newest) can be silently truncated by a fetch limit.
    /// Range + order on the same field needs no composite index.
    func getAllRecords(userId: String, since: Date) async throws -> [ProgressRecord] {
        var records: [ProgressRecord] = []
        var lastDocument: DocumentSnapshot?
        let pageSize = 500
        // 20 pages = 10,000 in-window records; a safety cap, not a real bound.
        for _ in 0..<20 {
            var query = recordCollection(userId: userId)
                .whereField("date", isGreaterThanOrEqualTo: since)
                .order(by: "date", descending: false)
                .limit(to: pageSize)
            if let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }
            let snapshot = try await query.getDocuments()
            records += try snapshot.documents.compactMap { try $0.data(as: ProgressRecord.self) }
            guard snapshot.documents.count == pageSize, let last = snapshot.documents.last else { break }
            lastDocument = last
        }
        return records
    }

    func getRecords(userId: String, exerciseId: String, limit: Int = 90) async throws -> [ProgressRecord] {
        let snapshot = try await recordCollection(userId: userId)
            .whereField("exerciseId", isEqualTo: exerciseId)
            .order(by: "date", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: ProgressRecord.self) }
    }

    func saveRecord(_ record: ProgressRecord) async throws {
        try recordCollection(userId: record.userId).document(record.id).setData(from: record)
    }
}
