import SwiftUI

/// Breakdown of a finished session with in-place editing of logged sets.
struct SessionDetailView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SessionDetailViewModel
    @State private var showDeleteConfirmation = false

    init(session: WorkoutSession) {
        _viewModel = State(initialValue: SessionDetailViewModel(session: session))
    }

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    private var weightUnit: String {
        UnitConversionService.weightLabel(for: unitSystem)
    }

    var body: some View {
        List {
            summarySection

            ForEach(viewModel.session.exerciseLogs.sorted(by: { $0.order < $1.order })) { log in
                exerciseSection(log)
            }

            if !viewModel.isEditing {
                Section {
                    Button("Delete Workout", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.session.workoutName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isEditing {
                    HStack {
                        Button("Cancel") { viewModel.cancelEditing() }
                        Button("Save") {
                            Task {
                                await viewModel.save(
                                    workoutService: dependencies.workoutService,
                                    unitSystem: unitSystem
                                )
                            }
                        }
                        .font(.body.weight(.semibold))
                        .disabled(viewModel.isSaving)
                    }
                } else {
                    Button("Edit") { viewModel.beginEditing(unitSystem: unitSystem) }
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                Task {
                    await viewModel.delete(workoutService: dependencies.workoutService)
                    if viewModel.isDeleted { dismiss() }
                }
            }
        } message: {
            Text("This removes the workout and any records it set. This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                summaryStat(
                    value: viewModel.session.startedAt.shortDate,
                    label: "Date"
                )
                summaryStat(
                    value: Formatters.durationString(from: viewModel.session.durationSeconds),
                    label: "Duration"
                )
                summaryStat(
                    value: "\(Int(UnitConversionService.convertWeight(viewModel.session.totalVolumeKg, to: unitSystem)))",
                    label: "\(weightUnit) total"
                )
            }
        }
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseSection(_ log: ExerciseLog) -> some View {
        Section(log.exerciseName) {
            ForEach(log.sets) { set in
                if viewModel.isEditing {
                    editableSetRow(set)
                } else {
                    setRow(set)
                }
            }
        }
    }

    private func setRow(_ set: SetLog) -> some View {
        HStack {
            Text("Set \(set.setNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if set.isPersonalRecord {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(Color.liftPR)
                    .accessibilityLabel("Personal record")
            }
            Text("\(UnitConversionService.convertWeight(set.weightKg, to: unitSystem).formatted(decimals: 1)) \(weightUnit) \u{00D7} \(set.reps)")
                .font(.subheadline.weight(.medium))
        }
    }

    private func editableSetRow(_ set: SetLog) -> some View {
        HStack(spacing: 12) {
            Text("Set \(set.setNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()

            TextField("0", text: Binding(
                get: { viewModel.weightInputs[set.id] ?? "" },
                set: { viewModel.weightInputs[set.id] = $0 }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 70)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Weight in \(weightUnit), set \(set.setNumber)")

            Text(weightUnit)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("0", text: Binding(
                get: { viewModel.repsInputs[set.id] ?? "" },
                set: { viewModel.repsInputs[set.id] = $0 }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 50)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Reps, set \(set.setNumber)")

            Text("reps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
