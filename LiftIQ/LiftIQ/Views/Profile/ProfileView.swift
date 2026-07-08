import SwiftUI

struct ProfileView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFinalConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var defaultRestSeconds: Int = 60
    @State private var customRestEnabled = false
    @State private var saveRestTask: Task<Void, Never>?
    @State private var settingsError: String?

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

                Section {
                    Toggle("Custom Rest Timer", isOn: $customRestEnabled)
                    if customRestEnabled {
                        Stepper(value: $defaultRestSeconds, in: 30...300, step: 15) {
                            HStack {
                                Text("Rest Duration")
                                Spacer()
                                Text(restLabel(defaultRestSeconds))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        LabeledContent("Rest Duration", value: "Program default")
                    }
                } header: {
                    Text("Workout Settings")
                } footer: {
                    Text(customRestEnabled
                        ? "Your rest duration applies to every exercise, overriding the rest times in your program."
                        : "Rest follows your program's per-exercise values, with 60s when an exercise doesn't specify one.")
                }
            }

            if dependencies.healthKitService.isAvailable {
                Section {
                    Toggle("Sync to Apple Health", isOn: healthSyncBinding)
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Saves completed workouts to Apple Health as strength training, with start time and duration.")
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
        .onAppear {
            if let profile = dependencies.authService.currentUser?.profile {
                defaultRestSeconds = profile.effectiveDefaultRestSeconds
                customRestEnabled = profile.defaultRestSeconds != nil
            }
        }
        .onChange(of: defaultRestSeconds) { _, newValue in
            guard customRestEnabled else { return }
            scheduleRestSave(newValue)
        }
        .onChange(of: customRestEnabled) { _, enabled in
            // Toggling is a deliberate action — persist immediately rather
            // than debouncing, so a quick exit can't drop the change.
            saveRestTask?.cancel()
            let value = enabled ? defaultRestSeconds : nil
            saveRestTask = Task { await persistDefaultRest(value) }
        }
        .onDisappear {
            flushPendingRestSave()
        }
        .alert("Couldn't Save Setting", isPresented: Binding(
            get: { settingsError != nil },
            set: { if !$0 { settingsError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingsError ?? "")
        }
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

    private var healthSyncBinding: Binding<Bool> {
        Binding(
            get: { dependencies.healthKitService.isSyncEnabled },
            set: { enabled in
                if enabled {
                    Task {
                        do {
                            try await dependencies.healthKitService.enableSync()
                        } catch {
                            settingsError = error.localizedDescription
                        }
                    }
                } else {
                    dependencies.healthKitService.disableSync()
                }
            }
        )
    }

    private func restLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private func scheduleRestSave(_ seconds: Int?) {
        saveRestTask?.cancel()
        saveRestTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await persistDefaultRest(seconds)
        }
    }

    /// Persists a debounced change right away (leaving the screen mid-debounce
    /// used to silently drop the new rest duration).
    private func flushPendingRestSave() {
        saveRestTask?.cancel()
        let value = customRestEnabled ? defaultRestSeconds : nil
        saveRestTask = Task { await persistDefaultRest(value) }
    }

    /// nil means "follow the program's rest values"; a value overrides them.
    private func persistDefaultRest(_ seconds: Int?) async {
        guard var profile = dependencies.authService.currentUser?.profile,
              profile.defaultRestSeconds != seconds else { return }
        profile.defaultRestSeconds = seconds
        do {
            try await dependencies.authService.updateProfile(profile)
        } catch {
            settingsError = "Your rest timer setting couldn't be saved. Check your connection and try again."
            if let saved = dependencies.authService.currentUser?.profile {
                defaultRestSeconds = saved.effectiveDefaultRestSeconds
                customRestEnabled = saved.defaultRestSeconds != nil
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
