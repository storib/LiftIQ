import SwiftUI

/// Free-text AI workout modification. Launched with a plan (permanent edits),
/// optionally scoped to one workout day (one-session edits). The user reviews
/// the AI's change summary before anything is applied.
struct AIModifySheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    /// Plan to modify; required for the "Entire plan" scope.
    let plan: WorkoutPlan?
    /// Day to modify; enables the "Just this workout" scope.
    let workout: WorkoutTemplate?
    /// One-session apply: hand the modified day back to the presenter.
    var onApplyWorkout: ((WorkoutTemplate) -> Void)? = nil
    /// Permanent apply: called after the modified plan is saved.
    var onApplyPlan: ((WorkoutPlan) -> Void)? = nil

    @State private var instruction = ""
    @State private var scope: AIModificationScope = .workout
    @State private var result: AIWorkoutModification?
    @State private var isSubmitting = false
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showingConsent = false

    private var scopeChoices: [AIModificationScope] {
        var choices: [AIModificationScope] = []
        if workout != nil { choices.append(.workout) }
        if plan != nil { choices.append(.plan) }
        return choices
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSections(result)
                } else {
                    requestSections
                }
            }
            .navigationTitle("Modify with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isSubmitting || isApplying)
            .onAppear {
                if let first = scopeChoices.first { scope = first }
                showingConsent = !AIConsentManager.hasConsented
            }
            .sheet(isPresented: $showingConsent) {
                AIConsentSheet(
                    onAccept: { showingConsent = false },
                    onDecline: {
                        showingConsent = false
                        dismiss()
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }

    // MARK: - Request

    @ViewBuilder
    private var requestSections: some View {
        Section {
            TextField(
                "e.g. Replace the chest exercises — I have a chest disability.",
                text: $instruction,
                axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("What should change?")
        } footer: {
            Text("Describe the change in your own words. Mention any pain, injury, or disability so exercises that load that area are removed entirely.")
        }

        if scopeChoices.count > 1 {
            Section {
                Picker("Apply to", selection: $scope) {
                    Text("Just this workout").tag(AIModificationScope.workout)
                    Text("Entire plan").tag(AIModificationScope.plan)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(scope == .workout
                     ? "A one-time change for this session. Your saved plan stays as it is."
                     : "Permanently rewrites your saved plan.")
            }
        }

        Section {
            Button {
                submit()
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .padding(.trailing, 6)
                    }
                    Text(isSubmitting ? "Thinking…" : "Suggest Changes")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isSubmitting || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.liftDanger)
            }
        }
    }

    // MARK: - Review

    @ViewBuilder
    private func resultSections(_ result: AIWorkoutModification) -> some View {
        Section("Proposed changes") {
            Label {
                Text(result.changeSummary)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color.accentColor)
            }
        }

        if let modifiedWorkout = result.workout {
            workoutPreview(modifiedWorkout)
        } else if let modifiedPlan = result.plan {
            ForEach(modifiedPlan.workouts) { day in
                workoutPreview(day)
            }
        }

        Section {
            Button {
                apply(result)
            } label: {
                HStack {
                    if isApplying {
                        ProgressView()
                            .padding(.trailing, 6)
                    }
                    Text(result.workout != nil ? "Use for This Workout" : "Save Plan")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isApplying)

            Button("Discard", role: .destructive) {
                self.result = nil
            }
            .frame(maxWidth: .infinity)
        } footer: {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Color.liftDanger)
            }
        }
    }

    private func workoutPreview(_ day: WorkoutTemplate) -> some View {
        Section(day.name) {
            ForEach(day.exerciseGroups.flatMap(\.exercises)) { planned in
                let name = dependencies.exerciseService.getExercise(id: planned.exerciseId)?.name
                HStack {
                    Text(name ?? planned.exerciseId)
                        .font(.subheadline)
                    Spacer()
                    Text("\(planned.sets) x \(planned.repsMin)-\(planned.repsMax)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        guard let profile = dependencies.authService.currentUser?.profile else {
            errorMessage = "Profile not loaded yet — try again in a moment."
            return
        }
        errorMessage = nil
        isSubmitting = true
        Task {
            do {
                result = try await dependencies.aiService.modifyWorkout(
                    scope: scope,
                    instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                    plan: plan,
                    workout: scope == .workout ? workout : nil,
                    profile: profile
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func apply(_ result: AIWorkoutModification) {
        errorMessage = nil
        if let modifiedWorkout = result.workout {
            onApplyWorkout?(modifiedWorkout)
            dismiss()
            return
        }
        guard let modifiedPlan = result.plan else { return }
        isApplying = true
        Task {
            do {
                try await dependencies.workoutService.savePlan(modifiedPlan)
                onApplyPlan?(modifiedPlan)
                dismiss()
            } catch {
                errorMessage = "Couldn't save the plan: \(error.localizedDescription)"
            }
            isApplying = false
        }
    }
}
