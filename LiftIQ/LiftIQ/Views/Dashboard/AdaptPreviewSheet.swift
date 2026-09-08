import SwiftUI

/// Walks one adaptation from choice to preview. Nothing is applied until
/// the lifter taps Use this workout; every change shows its reason.
struct AdaptPreviewSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: AdaptWorkoutViewModel
    let onAccept: (AdaptedWorkout) -> Void

    @State private var showingConsent = false

    private var unitSystem: UnitSystem { viewModel.profile.unitSystem }

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.step {
                case .pickMinutes: minutesSection
                case .pickBusyExercise: busyExerciseSection
                case .pickCandidate(let exerciseId): candidateSection(exerciseId)
                case .pickSetup: setupSection
                case .needsConsent: consentSection
                case .loadingAI: loadingSection
                case .preview: previewSections
                case .error(let message): errorSection(message)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .task { await viewModel.prepare() }
            .sheet(isPresented: $showingConsent) {
                AIConsentSheet(
                    onAccept: {
                        showingConsent = false
                        Task { await viewModel.runAIFallback() }
                    },
                    onDecline: { showingConsent = false }
                )
                .interactiveDismissDisabled()
            }
        }
    }

    private var title: String {
        switch viewModel.kind {
        case .shortOnTime: return "Short on time"
        case .equipmentBusy: return "Equipment is busy"
        case .differentGym: return "Somewhere else"
        }
    }

    // MARK: - Steps

    private var minutesSection: some View {
        Section {
            Picker("Time available", selection: $viewModel.targetMinutes) {
                ForEach(AdaptWorkoutViewModel.minuteChoices, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.segmented)
            Stepper("Or exactly \(viewModel.targetMinutes) min", value: $viewModel.targetMinutes, in: 10...120, step: 5)
            Button {
                viewModel.applyMinutes()
            } label: {
                Text("Fit it in").font(.headline).frame(maxWidth: .infinity)
            }
        } header: {
            Text("Today's plan is about \(viewModel.minutesBefore) min")
        } footer: {
            Text("Optional exercises go first, then isolation sets and rest. Your first big lift always stays.")
        }
    }

    private var busyExerciseSection: some View {
        Section("Which one is taken?") {
            ForEach(viewModel.workoutExercises, id: \.planned.id) { entry in
                Button {
                    viewModel.chooseBusy(exerciseId: entry.planned.exerciseId)
                } label: {
                    HStack {
                        Text(entry.exercise?.name ?? entry.planned.exerciseId)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(entry.exercise?.equipment.map(\.displayName).joined(separator: ", ") ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func candidateSection(_ exerciseId: String) -> some View {
        Section {
            if viewModel.candidates.isEmpty {
                Text("Nothing else in your gym targets this muscle. Try Swap on the exercise during the workout to search the full catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.candidates.prefix(6)) { candidate in
                Button {
                    viewModel.chooseCandidate(candidate)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: candidate.isUsualAlternative ? "star.fill" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(candidate.isUsualAlternative ? Color.liftPR : Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.exercise.name).foregroundStyle(.primary)
                            if !candidate.reasons.isEmpty {
                                Text(candidate.reasons.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let last = lastLine(candidate.lastLog) {
                                Text(last).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Instead, do…")
        }
    }

    private var setupSection: some View {
        Section {
            if viewModel.otherSetups.isEmpty {
                Text("Add another gym in Profile → Equipment and it will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.otherSetups) { setup in
                Button {
                    Task { await viewModel.chooseSetup(setup) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setup.name).foregroundStyle(.primary)
                        Text(setup.equipment.map(\.displayName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        } header: {
            Text("Where are you training?")
        }
    }

    private var consentSection: some View {
        Section {
            Text("\(viewModel.unresolved.count) exercise\(viewModel.unresolved.count == 1 ? " has" : "s have") no match in this gym's equipment. Claude can pick replacements, or they can be left out.")
                .font(.subheadline)
            Button {
                showingConsent = true
            } label: {
                Label("Enable AI sharing and replace them", systemImage: "wand.and.stars")
            }
            Button("Remove them instead") {
                viewModel.dropUnresolved()
            }
        } header: {
            Text("Needs a hand")
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Finding replacements…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(Color.liftDanger)
            Button("Try again") { viewModel.retryFromError() }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSections: some View {
        if let result = viewModel.result {
            Section {
                HStack {
                    Label("~\(result.minutesBefore) min", systemImage: "clock")
                    Image(systemName: "arrow.right")
                    Label("~\(result.minutesAfter) min", systemImage: "clock.badge.checkmark")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                if let target = result.record.targetMinutes, result.minutesAfter > target {
                    Text("Closest we can get without cutting your first big lift: \(result.minutesAfter) min.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if result.changes.isEmpty {
                    Text("Already fits — nothing to change.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !result.changes.isEmpty {
                Section("What changes and why") {
                    ForEach(result.changes) { change in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: change.kind))
                                .foregroundStyle(tint(for: change.kind))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(headline(for: change))
                                    .font(.subheadline.weight(.semibold))
                                Text(change.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    Task {
                        if let accepted = await viewModel.accept() {
                            onAccept(accepted)
                        }
                        dismiss()
                    }
                } label: {
                    Text("Use this workout").font(.headline).frame(maxWidth: .infinity)
                }
                .disabled(result.changes.isEmpty)
            } footer: {
                Text("Only today's session changes. Your saved plan stays as it is.")
            }
        }
    }

    // MARK: - Helpers

    private func headline(for change: WorkoutChange) -> String {
        switch change.kind {
        case .removedExercise: return "Skip \(change.exerciseName)"
        case .reducedSets: return "\(change.exerciseName): \(change.fromValue ?? 0) → \(change.toValue ?? 0) sets"
        case .swappedExercise: return "\(change.exerciseName) → \(change.replacementName ?? "")"
        case .restShortened: return "\(change.exerciseName): shorter rest"
        case .addedExercise: return "Add \(change.exerciseName)"
        }
    }

    private func icon(for kind: WorkoutChangeKind) -> String {
        switch kind {
        case .removedExercise: return "minus.circle.fill"
        case .reducedSets: return "arrow.down.circle.fill"
        case .swappedExercise: return "arrow.triangle.2.circlepath.circle.fill"
        case .restShortened: return "timer"
        case .addedExercise: return "plus.circle.fill"
        }
    }

    private func tint(for kind: WorkoutChangeKind) -> Color {
        switch kind {
        case .removedExercise: return Color.liftWarning
        case .reducedSets, .restShortened: return .secondary
        case .swappedExercise, .addedExercise: return Color.accentColor
        }
    }

    private func lastLine(_ log: ExerciseLog?) -> String? {
        guard let log else { return nil }
        let working = log.sets.filter { $0.setType == .working && $0.weightKg > 0 && $0.reps > 0 }
        guard let top = working.max(by: { $0.weightKg < $1.weightKg }) else { return nil }
        let weight = UnitConversionService.convertWeight(top.weightKg, to: unitSystem)
        return "Last: \(working.count)×\(top.reps) @ \(weight.formatted(decimals: 1)) \(UnitConversionService.weightLabel(for: unitSystem))"
    }
}
