import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Appends one beta usage event. The rules require the caller's uid, a
/// server timestamp, and exactly these fields; anything else is rejected.
/// Stateless (Firestore's shared instance is fetched per write) so it is
/// trivially Sendable for the detached logging task.
struct BetaEventRepository: BetaEventWriting {
    func write(name: String, props: [String: any Sendable], appVersion: String, build: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        var data: [String: Any] = [
            "userId": userId,
            "name": name,
            "props": props,
            "createdAt": FieldValue.serverTimestamp(),
            "appVersion": appVersion,
            "build": build,
        ]
        data["props"] = props.mapValues { $0 as Any }
        _ = try await db.collection("betaEvents").addDocument(data: data)
    }
}
