import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@Observable
final class AuthService {
    var isAuthenticated = false
    var currentUserId: String?
    var currentUser: LiftIQUser?
    var needsOnboarding = false
    var isLoading = true
    var errorMessage: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let userRepository = UserRepository()

    init() {
        listenToAuthState()
    }

    private func listenToAuthState() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user {
                    self.currentUserId = user.uid
                    self.isAuthenticated = true
                    await self.loadUser(id: user.uid)
                } else {
                    self.currentUserId = nil
                    self.currentUser = nil
                    self.isAuthenticated = false
                    self.needsOnboarding = false
                }
                self.isLoading = false
            }
        }
    }

    private func loadUser(id: String) async {
        do {
            if let user = try await userRepository.getUser(id: id) {
                self.currentUser = user
                self.needsOnboarding = user.profile.goals.isEmpty
            } else {
                self.needsOnboarding = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.currentUserId = result.user.uid
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let newUser = LiftIQUser(
            id: result.user.uid,
            email: email,
            displayName: displayName,
            profile: UserProfile(
                experienceLevel: .beginner,
                goals: [],
                availableEquipment: [],
                trainingDaysPerWeek: 3,
                sessionDurationMinutes: 60,
                injuries: [],
                bodyWeightKg: nil,
                heightCm: nil,
                dateOfBirth: nil,
                unitSystem: .metric
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
        try await userRepository.saveUser(newUser)
        self.currentUser = newUser
        self.needsOnboarding = true
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        guard let userId = currentUserId else { return }
        try await userRepository.updateProfile(userId: userId, profile: profile)
        currentUser?.profile = profile
        currentUser?.updatedAt = Date()
        needsOnboarding = false
    }

    /// Deletes all user data from Firestore, then deletes the Firebase Auth account.
    /// Requires a recent sign-in; caller should handle `AuthErrorCode.requiresRecentLogin`
    /// by prompting reauthentication and retrying.
    func deleteAccount() async throws {
        guard let userId = currentUserId else { return }

        let db = Firestore.firestore()
        let userDocRef = db.collection("users").document(userId)

        // Delete all subcollections in a batch per collection
        let subcollections = [
            "workoutPlans",
            "workoutSessions",
            "progressRecords",
            "personalRecords",
            "bodyMeasurements"
        ]

        for collection in subcollections {
            let snapshot = try await userDocRef.collection(collection).getDocuments()
            if snapshot.documents.isEmpty { continue }
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // Delete the user document itself
        try await userDocRef.delete()

        // Delete the Firebase Auth account (must be last — irreversible)
        try await Auth.auth().currentUser?.delete()
    }
}
