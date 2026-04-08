import Foundation
import FirebaseFirestore

final class BodyMeasurementRepository {
    private let db = Firestore.firestore()

    private func measurementCollection(userId: String) -> CollectionReference {
        db.collection("users").document(userId).collection("bodyMeasurements")
    }

    func getMeasurements(userId: String, limit: Int = 90) async throws -> [BodyMeasurement] {
        let snapshot = try await measurementCollection(userId: userId)
            .order(by: "date", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: BodyMeasurement.self) }
    }

    func saveMeasurement(_ measurement: BodyMeasurement) async throws {
        try measurementCollection(userId: measurement.userId).document(measurement.id).setData(from: measurement)
    }

    func deleteMeasurement(userId: String, measurementId: String) async throws {
        try await measurementCollection(userId: userId).document(measurementId).delete()
    }
}
