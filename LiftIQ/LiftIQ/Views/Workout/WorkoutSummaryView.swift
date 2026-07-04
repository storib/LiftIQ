import SwiftUI

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let sessionPRs: [PersonalRecord]
    let unitSystem: UnitSystem
    let onSaveMoodAndNotes: (Int?, String?) -> Void
    let onDismiss: () -> Void

    @State private var notes: String = ""

    /// Slider position, 1...5. Only committed as a mood once the user has
    /// actually touched the slider, so `mood` stays nil by default.
    @State private var moodSliderValue: Double = 3
    @State private var hasRatedMood = false

    @State private var heroVisible = false

    private var selectedMood: Int? {
        hasRatedMood ? Int(moodSliderValue.rounded()) : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroHeader

                    statsGrid

                    if !sessionPRs.isEmpty {
                        newRecordsCard
                    }

                    exerciseBreakdown

                    moodCard

                    notesCard

                    doneButton
                }
            }
            .background(Color.liftBackground)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 8)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(heroVisible ? 1 : 0.4)
            .opacity(heroVisible ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Workout Complete")
                    .font(.system(.title, design: .rounded).bold())

                Text(session.workoutName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .opacity(heroVisible ? 1 : 0)
            .offset(y: heroVisible ? 0 : 8)
        }
        .padding(.top, 28)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.1)) {
                heroVisible = true
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SummaryStatCard(
                title: "Duration",
                value: Formatters.durationString(from: session.durationSeconds),
                icon: "clock.fill"
            )
            SummaryStatCard(
                title: "Volume",
                value: session.totalVolumeKg.asWeight(unit: unitSystem),
                icon: "scalemass.fill"
            )
            SummaryStatCard(
                title: session.exerciseLogs.count == 1 ? "Exercise" : "Exercises",
                value: "\(session.exerciseLogs.count)",
                icon: "dumbbell.fill"
            )
            SummaryStatCard(
                title: completedSetsCount == 1 ? "Set" : "Sets",
                value: "\(completedSetsCount)",
                icon: "checkmark.circle.fill"
            )
        }
        .padding(.horizontal)
    }

    // MARK: - New Records

    private var newRecordsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.liftPR)
                Text(sessionPRs.count == 1 ? "New Record" : "New Records")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.liftPR)
                Spacer()
            }

            ForEach(sessionPRs) { pr in
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.liftPR)
                        .frame(width: 34, height: 34)
                        .background(Color.liftPR.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.exerciseName)
                            .font(.subheadline.weight(.semibold))
                        Text(prDescription(pr))
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.liftPR.opacity(0.14), Color.liftPR.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.liftPR.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Exercise Breakdown

    private var exerciseBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Breakdown")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 0) {
                let logsWithSets = session.exerciseLogs.filter { log in
                    log.sets.contains { $0.setType == .working && $0.weightKg > 0 }
                }
                ForEach(logsWithSets) { log in
                    let workingSets = log.sets.filter { $0.setType == .working && $0.weightKg > 0 }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.exerciseName)
                                .font(.subheadline.weight(.medium))
                            if let best = workingSets.max(by: { $0.estimated1RM < $1.estimated1RM }) {
                                let w = UnitConversionService.convertWeight(best.weightKg, to: unitSystem)
                                Text("Best: \(w.formatted()) \(UnitConversionService.weightLabel(for: unitSystem)) x \(best.reps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(workingSets.count == 1 ? "1 set" : "\(workingSets.count) sets")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if log.id != logsWithSets.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color.liftCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    // MARK: - Mood

    private var moodCard: some View {
        VStack(spacing: 16) {
            Text("How did it feel?")
                .font(.headline)

            VStack(spacing: 6) {
                Image(systemName: moodSymbol)
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(hasRatedMood ? moodTint : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayedMood)

                Text(hasRatedMood ? moodLabel(displayedMood) : "Slide to rate")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(hasRatedMood ? moodTint : Color.secondary)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Slider(
                    value: $moodSliderValue,
                    in: 1...5,
                    step: 1
                ) {
                    Text("How did it feel?")
                } onEditingChanged: { _ in
                    if !hasRatedMood {
                        hasRatedMood = true
                        Haptics.selection()
                    }
                }
                .tint(hasRatedMood ? moodTint : Color.accentColor)
                .onChange(of: moodSliderValue) { _, _ in
                    // VoiceOver adjustable actions change the value without
                    // triggering onEditingChanged, so commit the rating here too.
                    hasRatedMood = true
                    Haptics.selection()
                }
                .accessibilityValue(hasRatedMood ? moodLabel(displayedMood) : "Not rated")

                HStack {
                    Text("Rough")
                    Spacer()
                    Text("Great")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    /// Mood implied by the current slider position (used for display even
    /// before the rating is committed).
    private var displayedMood: Int {
        min(5, max(1, Int(moodSliderValue.rounded())))
    }

    private var moodSymbol: String {
        switch displayedMood {
        case 1: return "gauge.with.dots.needle.0percent"
        case 2: return "gauge.with.dots.needle.33percent"
        case 3: return "gauge.with.dots.needle.50percent"
        case 4: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    private var moodTint: Color {
        switch displayedMood {
        case 1, 2: return Color.liftWarning
        case 3: return Color.accentColor
        default: return Color.liftSuccess
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .padding(.horizontal)

            TextField("How was the session?", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(14)
                .background(Color.liftCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
                .padding(.horizontal)
        }
    }

    // MARK: - Done

    private var doneButton: some View {
        Button {
            onSaveMoodAndNotes(selectedMood, notes.isEmpty ? nil : notes)
            onDismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private var completedSetsCount: Int {
        session.exerciseLogs.reduce(0) { total, log in
            total + log.sets.filter { $0.weightKg > 0 && $0.reps > 0 }.count
        }
    }

    private func prDescription(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .weight:
            return "Weight: \(pr.value.asWeight(unit: unitSystem))"
        case .estimated1RM:
            return "Est. 1RM: \(pr.value.asWeight(unit: unitSystem))"
        case .reps:
            return "\(Int(pr.value)) reps"
        case .volume:
            return "Volume: \(pr.value.asWeight(unit: unitSystem))"
        }
    }

    private func moodLabel(_ mood: Int) -> String {
        switch mood {
        case 1: return "Rough"
        case 2: return "Meh"
        case 3: return "Solid"
        case 4: return "Good"
        case 5: return "Great"
        default: return ""
        }
    }
}

// MARK: - Summary Stat Card

private struct SummaryStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded).bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
