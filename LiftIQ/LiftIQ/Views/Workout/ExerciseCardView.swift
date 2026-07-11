import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var viewModel: WorkoutExecutionViewModel
    let exerciseLogIndex: Int
    let groupColor: Color?
    var focusedField: FocusState<SetFieldFocus?>.Binding

    @State private var showGuidance = false

    private var exerciseLog: ExerciseLog {
        viewModel.session.exerciseLogs[exerciseLogIndex]
    }

    private var exerciseDetail: Exercise? {
        viewModel.exerciseDetails[exerciseLog.exerciseId]
    }

    private var previousLog: ExerciseLog? {
        viewModel.previousLogs[exerciseLog.exerciseId]
    }

    private var suggestion: ProgressionSuggestion? {
        viewModel.progressionSuggestions[exerciseLog.exerciseId]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Superset color bar
            if let groupColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(groupColor)
                    .frame(width: 4)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exerciseLog.exerciseName)
                            .font(.system(.headline, design: .rounded))

                        if let exerciseDetail {
                            HStack(spacing: 8) {
                                Label(exerciseDetail.primaryMuscleGroup.displayName, systemImage: "target")
                                Label(exerciseDetail.movementPattern.displayName, systemImage: "arrow.up.and.down")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        viewModel.requestSwap(exerciseLogIndex: exerciseLogIndex)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            // 44pt hit area; top-trailing alignment keeps the glyph
                            // in its original corner position.
                            .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Swap exercise")
                }

                if let suggestion, shouldShowSuggestionPill(suggestion) {
                    suggestionPill(suggestion)
                }

                // Collapsible exercise guidance
                if let exerciseDetail {
                    Divider()

                    DisclosureGroup(isExpanded: $showGuidance) {
                        ExerciseGuidanceView(exercise: exerciseDetail)
                            .padding(.top, 8)
                    } label: {
                        Label("Form, cues, and video", systemImage: "play.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Previous session data
                if let prevLog = previousLog {
                    previousSessionLine(prevLog)
                } else {
                    Text("No previous data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Column headers
                HStack(spacing: 8) {
                    Text("SET")
                        .frame(width: 32)
                    Text("WEIGHT")
                        .frame(width: 78)
                    Spacer().frame(width: 18)
                    Text("REPS")
                        .frame(width: 60)
                    Text("RPE")
                        .frame(width: 48)
                    Spacer()
                    Image(systemName: "checkmark")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

                // Set rows
                ForEach(Array(exerciseLog.sets.enumerated()), id: \.element.id) { setIndex, setLog in
                    let prevSet = viewModel.previousSet(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex)
                    let prevWeight: Double? = prevSet.map {
                        UnitConversionService.convertWeight($0.weightKg, to: viewModel.unitSystem)
                    }

                    SetRowView(
                        exerciseLogIndex: exerciseLogIndex,
                        setIndex: setIndex,
                        setNumber: setLog.setNumber,
                        setType: setLog.setType,
                        weightText: $viewModel.setInputs[setId: setLog.id].weight,
                        repsText: $viewModel.setInputs[setId: setLog.id].reps,
                        rpeText: $viewModel.setInputs[setId: setLog.id].rpe,
                        previousWeight: prevWeight,
                        previousReps: prevSet?.reps,
                        isBodyweight: exerciseDetail?.isBodyweight ?? false,
                        unitSystem: viewModel.unitSystem,
                        isCompleted: viewModel.completedSetIds.contains(setLog.id),
                        isPersonalRecord: setLog.isPersonalRecord,
                        focusedField: focusedField,
                        onComplete: {
                            Task {
                                await viewModel.completeSet(
                                    exerciseLogIndex: exerciseLogIndex,
                                    setIndex: setIndex
                                )
                            }
                        },
                        onUncomplete: {
                            Task {
                                await viewModel.uncompleteSet(
                                    exerciseLogIndex: exerciseLogIndex,
                                    setIndex: setIndex
                                )
                            }
                        },
                        onSetTypeChange: { newType in
                            viewModel.updateSetType(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex, newType: newType)
                        }
                    )
                }

                // Add/Remove set buttons
                HStack {
                    Button {
                        viewModel.addSet(exerciseLogIndex: exerciseLogIndex)
                    } label: {
                        Label("Add Set", systemImage: "plus.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    if exerciseLog.sets.count > 1 {
                        Button {
                            Task {
                                await viewModel.removeSet(
                                    exerciseLogIndex: exerciseLogIndex,
                                    setIndex: exerciseLog.sets.count - 1
                                )
                            }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.035),
                    lineWidth: 1
                )
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.07),
            radius: colorScheme == .dark ? 12 : 8,
            y: colorScheme == .dark ? 5 : 3
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private func suggestionPill(_ suggestion: ProgressionSuggestion) -> some View {
        let tint: Color = suggestion.isPlateaued ? .orange : (suggestionIsProgression(suggestion) ? .green : .secondary)
        let icon = suggestion.isPlateaued ? "exclamationmark.triangle.fill"
            : (suggestionIsProgression(suggestion) ? "arrow.up.right.circle.fill" : "equal.circle.fill")

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(suggestionText(suggestion))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
            Spacer()
            if suggestion.isPlateaued {
                Button("Swap") {
                    viewModel.requestSwap(exerciseLogIndex: exerciseLogIndex)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tint.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func suggestionIsProgression(_ s: ProgressionSuggestion) -> Bool {
        guard let prevWeight = topPreviousWorkingWeightKg else { return false }
        return s.suggestedWeight > prevWeight + 0.001
    }

    private var topPreviousWorkingWeightKg: Double? {
        previousLog?.sets
            .filter { $0.setType == .working && $0.weightKg > 0 }
            .map(\.weightKg)
            .first
    }

    /// Hide the pill when there's no meaningful guidance to show: a
    /// zero-weight suggestion with no previous data would read as "Hold at
    /// 0 lb", which looks broken.
    private func shouldShowSuggestionPill(_ s: ProgressionSuggestion) -> Bool {
        if s.isPlateaued { return true }
        if s.suggestedWeight > 0.001 { return true }
        return previousLog != nil
    }

    private func suggestionText(_ s: ProgressionSuggestion) -> String {
        if s.isPlateaued {
            return "Plateau detected — try swapping this exercise"
        }
        let unitLabel = viewModel.unitSystem == .metric ? "kg" : "lb"
        // Bodyweight / unweighted movements: no weight to hold, so lead with
        // the rep target instead of a "0 lb" callout.
        guard s.suggestedWeight > 0.001 else {
            return "Hit \(s.suggestedRepsMax) reps to progress"
        }
        let displayWeight = UnitConversionService.convertWeight(s.suggestedWeight, to: viewModel.unitSystem)
        if let prevKg = topPreviousWorkingWeightKg, s.suggestedWeight > prevKg + 0.001 {
            let prevDisplay = UnitConversionService.convertWeight(prevKg, to: viewModel.unitSystem)
            let delta = displayWeight - prevDisplay
            return "Try \(displayWeight.formatted(decimals: 1)) \(unitLabel) (+\(delta.formatted(decimals: 1)) from last)"
        }
        return "Hold at \(displayWeight.formatted(decimals: 1)) \(unitLabel) — hit \(s.suggestedRepsMax) reps to progress"
    }

    private func previousSessionLine(_ prevLog: ExerciseLog) -> some View {
        let workingSets = prevLog.sets.filter { $0.setType == .working && $0.weightKg > 0 }
        let descriptions = workingSets.map { set in
            let w = UnitConversionService.convertWeight(set.weightKg, to: viewModel.unitSystem)
            return "\(w.formatted()) x \(set.reps)"
        }
        return Text("Last: \(descriptions.joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
