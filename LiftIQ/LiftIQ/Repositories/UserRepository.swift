import Foundation
import FirebaseFirestore

final class UserRepository {
    private let db = Firestore.firestore()
    private let collection = "users"

    func getUser(id: String) async throws -> LiftIQUser? {
        let doc = try await db.collection(collection).document(id).getDocument()
        return try doc.data(as: LiftIQUser.self)
    }

    func saveUser(_ user: LiftIQUser) async throws {
        try db.collection(collection).document(user.id).setData(from: user)
    }

    func updateProfile(userId: String, profile: UserProfile) async throws {
        let data = try Firestore.Encoder().encode(profile)
        try await db.collection(collection).document(userId).updateData(["profile": data, "updatedAt": FieldValue.serverTimestamp()])
    }

    func deleteUser(id: String) async throws {
        try await db.collection(collection).document(id).delete()
    }
}
