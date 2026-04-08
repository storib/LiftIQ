import Foundation
import FirebaseFirestore

final class ProgressRecordRepository {
    private let db = Firestore.firestore()

    private func recordCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("progressRecords")
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
