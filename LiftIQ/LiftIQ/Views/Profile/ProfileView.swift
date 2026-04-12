import SwiftUI

struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFinalConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        List {
            if let user = dependencies.authService.currentUser {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.title3.bold())
                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Training Profile") {
                    LabeledContent("Experience", value: user.profile.experienceLevel.displayName)
                    LabeledContent("Goals", value: user.profile.goals.map { $0.displayName }.joined(separator: ", "))
                    LabeledContent("Schedule", value: "\(user.profile.trainingDaysPerWeek) days/week")
                    LabeledContent("Session Length", value: "\(user.profile.sessionDurationMinutes) min")
                    LabeledContent("Units", value: user.profile.unitSystem == .metric ? "Metric" : "Imperial")
                }

                Section("Equipment") {
                    let equipmentList = user.profile.availableEquipment.map { $0.displayName }.joined(separator: ", ")
                    Text(equipmentList)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data & Privacy") {
                Toggle("AI Data Sharing", isOn: Binding(
                    get: { AIConsentManager.hasConsented },
                    set: { newValue in
                        if newValue {
                            AIConsentManager.recordConsent()
                        } else {
                            AIConsentManager.revokeConsent()
                        }
                    }
                ))

                if AIConsentManager.hasConsented {
                    Text("Training profile and injury data may be sent to Anthropic (Claude AI) when generating workout plans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("AI-powered program generation is disabled. You can still create manual programs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    try? dependencies.authService.signOut()
                }
            }

            Section {
                Button("Delete Account", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(isDeletingAccount)
            } footer: {
                Text("Permanently removes your account, workout history, personal records, and all associated data. This cannot be undone.")
            }
        }
        .navigationTitle("Profile")
        .alert("Delete Account?", isPresented: $showingDeleteConfirmation) {
            Button("Continue", role: .destructive) {
                showingDeleteFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all data including workout history, personal records, body measurements, and programs. This action cannot be undone.")
        }
        .alert("Are you sure?", isPresented: $showingDeleteFinalConfirmation) {
            Button("Delete Everything", role: .destructive) {
                performAccountDeletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Last chance. All your data will be permanently deleted.")
        }
        .alert("Deletion Failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .overlay {
            if isDeletingAccount {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Deleting account...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func performAccountDeletion() {
        isDeletingAccount = true
        Task {
            do {
                try await dependencies.authService.deleteAccount()
            } catch {
                deleteError = error.localizedDescription
            }
            isDeletingAccount = false
        }
    }
}
