import Foundation
import FirebaseFirestore

final class ExerciseRepository {
    private let db = Firestore.firestore()
    private let collection = "exercises"

    /// Fetches the catalog with Firestore's default source (server, falling
    /// back to the local cache when offline).
    func getAllExercises() async throws -> [Exercise] {
        let snapshot = try await db.collection(collection).getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Exercise.self) }
    }

    /// Fetches the catalog strictly from Firestore's on-device cache. Throws
    /// or returns empty when nothing has been cached yet.
    func getCachedExercises() async throws -> [Exercise] {
        let snapshot = try await db.collection(collection).getDocuments(source: .cache)
        return try snapshot.documents.compactMap { try $0.data(as: Exercise.self) }
    }
}
