import SwiftUI
import FirebaseAuth
import FirebaseFunctions

@MainActor
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
    private let functions = Functions.functions()

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

    /// Deletes all user data and the Firebase Auth account through a trusted backend.
    func deleteAccount() async throws {
        guard let userId = currentUserId else { return }
        guard let authUser = Auth.auth().currentUser else {
            throw AuthServiceError.missingCurrentUser
        }
        guard authUser.uid == userId else {
            throw AuthServiceError.userMismatch
        }

        _ = try await functions.httpsCallable("deleteAccount").call([:])
        try? Auth.auth().signOut()

        currentUserId = nil
        currentUser = nil
        isAuthenticated = false
        needsOnboarding = false
    }
}

enum AuthServiceError: LocalizedError {
    case missingCurrentUser
    case userMismatch

    var errorDescription: String? {
        switch self {
        case .missingCurrentUser:
            return "No signed-in Firebase user was found."
        case .userMismatch:
            return "The signed-in Firebase user does not match the loaded LiftIQ account."
        }
    }
}
