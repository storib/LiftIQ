import Foundation
import FirebaseFirestore

final class ExerciseRepository {
    private let db = Firestore.firestore()
    private let collection = "exercises"

    func getAllExercises() async throws -> [Exercise] {
        let snapshot = try await db.collection(collection).getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Exercise.self) }
    }

    func getExercise(id: String) async throws -> Exercise? {
        let doc = try await db.collection(collection).document(id).getDocument()
        return try doc.data(as: Exercise.self)
    }

    func getExercises(forMuscleGroup muscleGroup: MuscleGroup) async throws -> [Exercise] {
        let snapshot = try await db.collection(collection)
            .whereField("primaryMuscleGroup", isEqualTo: muscleGroup.rawValue)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Exercise.self) }
    }

    func getExercises(forEquipment equipment: [Equipment]) async throws -> [Exercise] {
        let equipmentStrings = equipment.map { $0.rawValue }
        let snapshot = try await db.collection(collection)
            .whereField("equipment", arrayContainsAny: equipmentStrings)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Exercise.self) }
    }
}
