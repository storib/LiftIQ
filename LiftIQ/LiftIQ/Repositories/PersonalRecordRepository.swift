import Foundation
import FirebaseFirestore

final class PersonalRecordRepository {
    private let db = Firestore.firestore()

    private func prCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("personalRecords")
    }

    func getRecords(userId: String, limit: Int = 50) async throws -> [PersonalRecord] {
        let snapshot = try await prCollection(userId: userId)
            .order(by: "achievedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: PersonalRecord.self) }
    }

    func getRecords(userId: String, exerciseId: String, limit: Int = 50) async throws -> [PersonalRecord] {
        let snapshot = try await prCollection(userId: userId)
            .whereField("exerciseId", isEqualTo: exerciseId)
            .order(by: "achievedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: PersonalRecord.self) }
    }

    func saveRecord(_ record: PersonalRecord) async throws {
        try prCollection(userId: record.userId).document(record.id).setData(from: record)
    }

    func deleteRecord(userId: String, recordId: String) async throws {
        try await prCollection(userId: userId).document(recordId).delete()
    }
}
