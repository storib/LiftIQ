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
    /// Which screen opened the sheet (beta events only).
    let source: AIModifySource
    /// Presented from a running workout: plan-scope edits also merge into the
    /// live session, so the scope copy must say so.
    var appliesToLiveSession = false
    /// One-session apply: hand the modified day back to the presenter.
    var onApplyWorkout: ((WorkoutTemplate) -> Void)? = nil
    /// Permanent apply: called after the modified plan is saved.
    var onApplyPlan: ((WorkoutPlan) -> Void)? = nil
    /// Pre-filled request (e.g. from the block review); editable.
    var initialInstruction: String = ""
    /// Send `initialInstruction` as soon as the sheet opens (after consent),
    /// so the lifter lands on a ready proposal instead of a text box.
    var autoSubmit = false

    @State private var instruction = ""
    @State private var scope: AIModificationScope = .workout
    @State private var result: AIWorkoutModification?
    @State private var isSubmitting = false
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var showingConsent = false
    @State private var hasAppeared = false
    @State private var didApply = false

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
                guard !hasAppeared else { return }
                hasAppeared = true
                if let first = scopeChoices.first { scope = first }
                if instruction.isEmpty { instruction = initialInstruction }
                dependencies.betaEvents.log("ai_modify_opened", [
                    "source": source.rawValue,
                    "prefilled": !initialInstruction.isEmpty,
                    "autoSubmit": autoSubmit
                ])
                showingConsent = !AIConsentManager.hasConsented
                if !showingConsent { submitIfAutomatic() }
            }
            .onDisappear {
                // One closing event covers Cancel, swipe-down and apply, so
                // an abandoned sheet is visible in the data too.
                dependencies.betaEvents.log("ai_modify_closed", [
                    "source": source.rawValue,
                    "stage": closingStage,
                    "applied": didApply
                ])
            }
            .sheet(isPresented: $showingConsent) {
                AIConsentSheet(
                    onAccept: {
                        showingConsent = false
                        submitIfAutomatic()
                    },
                    onDecline: {
                        showingConsent = false
                        dependencies.betaEvents.log("ai_modify_consent_declined", ["source": source.rawValue])
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
                if scope == .workout {
                    Text("A one-time change for this session. Your saved plan stays as it is.")
                } else if appliesToLiveSession {
                    Text("Permanently rewrites your saved plan and applies the change to this workout too.")
                } else {
                    Text("Permanently rewrites your saved plan.")
                }
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
                    Text(result.workout != nil
                         ? "Use for This Workout"
                         : (appliesToLiveSession ? "Save Plan & Apply Now" : "Save Plan"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isApplying)

            Button("Discard", role: .destructive) {
                dependencies.betaEvents.log("ai_modify_discarded", [
                    "source": source.rawValue,
                    "scope": result.workout != nil ? AIModificationScope.workout.rawValue : AIModificationScope.plan.rawValue
                ])
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

    private var closingStage: String {
        if didApply { return "applied" }
        if result != nil { return "review" }
        if isSubmitting { return "submitting" }
        if errorMessage != nil { return "error" }
        return "request"
    }

    private func submitIfAutomatic() {
        guard autoSubmit, result == nil, !isSubmitting,
              !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
    }

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
                    profile: profile,
                    source: source
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
            logApplied(scope: .workout)
            dismiss()
            return
        }
        guard let modifiedPlan = result.plan else { return }
        isApplying = true
        Task {
            do {
                try await dependencies.workoutService.savePlan(modifiedPlan)
                onApplyPlan?(modifiedPlan)
                logApplied(scope: .plan)
                dismiss()
            } catch {
                errorMessage = "Couldn't save the plan: \(error.localizedDescription)"
            }
            isApplying = false
        }
    }

    private func logApplied(scope: AIModificationScope) {
        didApply = true
        dependencies.betaEvents.log("ai_modify_applied", [
            "source": source.rawValue,
            "scope": scope.rawValue
        ])
    }
}
