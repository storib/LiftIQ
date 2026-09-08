import SwiftUI

struct ExerciseCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Bindable var viewModel: WorkoutExecutionViewModel
    let exerciseLogIndex: Int
    let groupColor: Color?
    var focusedField: FocusState<SetFieldFocus?>.Binding

    @State private var showGuidance = false
    @State private var showingRemoveConfirmation = false

    /// Nil when the index no longer addresses a log — a removal shrinks
    /// `exerciseLogs` while SwiftUI may still render the outgoing row, and a
    /// resumed session can outlive part of the template it was built from.
    /// Reading it as an optional keeps that a blank row instead of a trap.
    private var exerciseLog: ExerciseLog? {
        let logs = viewModel.session.exerciseLogs
        return logs.indices.contains(exerciseLogIndex) ? logs[exerciseLogIndex] : nil
    }

    private var exerciseDetail: Exercise? {
        exerciseLog.flatMap { viewModel.exerciseDetails[$0.exerciseId] }
    }

    private var previousLog: ExerciseLog? {
        exerciseLog.flatMap { viewModel.previousLogs[$0.exerciseId] }
    }

    private var suggestion: ProgressionSuggestion? {
        exerciseLog.flatMap { viewModel.progressionSuggestions[$0.exerciseId] }
    }

    var body: some View {
        if let exerciseLog {
            card(exerciseLog)
        }
    }

    private func card(_ exerciseLog: ExerciseLog) -> some View {
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
                        if let note = viewModel.exercisePreferences[exerciseLog.exerciseId]?.note, !note.isEmpty {
                            Label(note, systemImage: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .accessibilityLabel("Your note: \(note)")
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
                        ExerciseGuidanceView(
                            exercise: exerciseDetail,
                            note: viewModel.exercisePreferences[exerciseDetail.id]?.note,
                            onSaveNote: { note in
                                Task { await viewModel.setNote(exerciseId: exerciseDetail.id, note: note) }
                            },
                            isAvoided: viewModel.exercisePreferences[exerciseDetail.id]?.isAvoided ?? false,
                            onToggleAvoid: { avoided in
                                Task { await viewModel.setAvoided(exerciseId: exerciseDetail.id, avoided: avoided) }
                            }
                        )
                        .padding(.top, 8)
                    } label: {
                        Label("Form, cues, and video", systemImage: "play.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Previous session data, or first-time coaching when there is
                // no history to repeat.
                if let prevLog = previousLog {
                    previousSessionLine(prevLog)
                } else if let planned = viewModel.plannedExercise(for: exerciseLog.exerciseId) {
                    firstTimeGuidance(planned)
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
                        suggestedWeight: viewModel.suggestedSetInputs[setLog.id]?.weight,
                        suggestedReps: viewModel.suggestedSetInputs[setLog.id]?.reps,
                        targetReps: viewModel.targetReps(exerciseLogIndex: exerciseLogIndex, setIndex: setIndex),
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
        .contextMenu {
            Button {
                viewModel.requestSwap(exerciseLogIndex: exerciseLogIndex)
            } label: {
                Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
            }

            if viewModel.session.exerciseLogs.count > 1 {
                Button(role: .destructive) {
                    showingRemoveConfirmation = true
                } label: {
                    Label("Remove Exercise", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Remove \(exerciseLog.exerciseName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Exercise", role: .destructive) {
                Task {
                    await viewModel.removeExercise(exerciseLogIndex: exerciseLogIndex)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(completedSetCount > 0
                 ? "This deletes \(completedSetCount) completed set\(completedSetCount == 1 ? "" : "s") and any PRs they earned."
                 : "Removes this exercise from the current workout.")
        }
    }

    private var completedSetCount: Int {
        exerciseLog?.sets.count { viewModel.completedSetIds.contains($0.id) } ?? 0
    }

    // MARK: - Subviews

    private func pillStyle(_ reason: ProgressionReason) -> (tint: Color, icon: String) {
        switch reason {
        case .increase: return (.green, "arrow.up.right.circle.fill")
        case .stall: return (.orange, "arrow.uturn.down.circle.fill")
        case .holdRebuilding: return (.secondary, "arrow.up.circle")
        case .holdNearTarget, .holdFloorMissed, .bodyweight: return (.secondary, "equal.circle.fill")
        }
    }

    @ViewBuilder
    private func suggestionPill(_ suggestion: ProgressionSuggestion) -> some View {
        let (tint, icon) = pillStyle(suggestion.reason)

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(suggestionText(suggestion))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Hide the pill when there's no meaningful guidance to show: a
    /// bodyweight suggestion with no previous data has nothing to say yet.
    private func shouldShowSuggestionPill(_ s: ProgressionSuggestion) -> Bool {
        if case .bodyweight = s.reason { return previousLog != nil }
        return true
    }

    /// Copy is encouraging by design: a hold shows what the lifter just did
    /// and exactly what moves them up, never just "hold".
    private func suggestionText(_ s: ProgressionSuggestion) -> String {
        let unit = viewModel.unitSystem
        let unitLabel = unit == .metric ? "kg" : "lb"
        func weight(_ kg: Double) -> String {
            "\(UnitConversionService.convertWeight(kg, to: unit).formatted(decimals: 1)) \(unitLabel)"
        }
        func reps(_ values: [Int]) -> String {
            values.map(String.init).joined(separator: " · ")
        }
        let target = weight(s.suggestedWeight)

        switch s.reason {
        case .bodyweight:
            return "Hit \(s.suggestedRepsMax) reps to progress"

        case .increase(let previousTopKg):
            let previousDisplay = UnitConversionService.convertWeight(previousTopKg, to: unit)
            let delta = UnitConversionService.convertWeight(s.suggestedWeight, to: unit) - previousDisplay
            // A jump of more than one step means the recent-best floor is
            // pulling the lifter back up after a light week.
            if s.suggestedWeight - previousTopKg > viewModel.weightIncrements.increment(for: exerciseDetail) + 0.001 {
                return "Back to \(target) — your recent best"
            }
            return "Try \(target) (+\(delta.formatted(decimals: 1)) from last)"

        case .holdNearTarget(let previousTopKg, let topReps, _):
            if let back = backToRecentBest(previousTopKg, suggestedKg: s.suggestedWeight) {
                return "\(reps(topReps)) at \(weight(previousTopKg)) last time — \(back)"
            }
            return "\(reps(topReps)) at \(target) — hit \(s.suggestedRepsMax) on your first set to move up"

        case .holdFloorMissed(let previousTopKg, let topReps, let bestReps):
            if let back = backToRecentBest(previousTopKg, suggestedKg: s.suggestedWeight) {
                return "\(reps(topReps)) at \(weight(previousTopKg)) last time — \(back)"
            }
            if bestReps >= s.suggestedRepsMax {
                return "Best set hit \(bestReps) at \(target) — keep every set ≥ \(s.suggestedRepsMin) and you're up"
            }
            return "\(reps(topReps)) at \(target) — hit \(s.suggestedRepsMax) and keep every set ≥ \(s.suggestedRepsMin)"

        case .holdRebuilding(let previousTopKg, let topReps, _):
            if let back = backToRecentBest(previousTopKg, suggestedKg: s.suggestedWeight) {
                return "\(reps(topReps)) at \(weight(previousTopKg)) last time — \(back)"
            }
            return "New weight — \(reps(topReps)) at \(target), build to \(s.suggestedRepsMax) to move up"

        case .stall(let stuckKg, let sessions):
            // The back-off is a probe (if reps jump it was fatigue, if flat
            // it's a real stall) — not an alarm, and the stuck weight stays
            // in view so the lifter knows what they just did.
            return "\(sessions) sessions stuck at \(weight(stuckKg)) — try \(target) and build back up"
        }
    }

    /// After a light week the recent-best floor lifts the suggestion above
    /// the weight the last reps were done at; say so rather than attribute
    /// those reps to a weight the lifter didn't touch.
    private func backToRecentBest(_ previousTopKg: Double, suggestedKg: Double) -> String? {
        guard suggestedKg > previousTopKg + 0.001 else { return nil }
        let unitLabel = viewModel.unitSystem == .metric ? "kg" : "lb"
        let display = UnitConversionService.convertWeight(suggestedKg, to: viewModel.unitSystem)
        return "back to \(display.formatted(decimals: 1)) \(unitLabel), your recent best"
    }

    /// First-session coaching: surfaces the plan's prescription (which the
    /// empty input fields otherwise hide) and tells a new user how to choose
    /// a starting weight.
    private func firstTimeGuidance(_ planned: PlannedExercise) -> some View {
        let repRange = planned.repsMin == planned.repsMax
            ? "\(planned.repsMin)"
            : "\(planned.repsMin)-\(planned.repsMax)"
        return VStack(alignment: .leading, spacing: 4) {
            Label("First time — aim for \(planned.sets)×\(repRange) reps", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(firstTimeBody(planned))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func firstTimeBody(_ planned: PlannedExercise) -> String {
        if exerciseDetail?.isBodyweight == true {
            return "Log your reps and tap the circle — enter a weight only if you add extra load."
        }
        // Anchored to repsMin because that's what ✓ adopts on a first
        // workout: an (repsMin + rir)RM weight leaves ~rir reps in reserve
        // after a set of repsMin.
        let rir = planned.rirTarget ?? 2
        return "Start with a weight you could lift about \(planned.repsMin + rir) times, "
            + "so a set of \(planned.repsMin) ends with \(rir)-\(rir + 1) reps left in the tank. "
            + "LiftIQ remembers it and suggests progressions from here."
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
