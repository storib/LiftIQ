import SwiftUI

struct WorkoutSummaryView: View {
    let session: WorkoutSession
    let sessionPRs: [PersonalRecord]
    let unitSystem: UnitSystem
    let onSaveMoodAndNotes: (Int?, String?) -> Void
    let onDismiss: () -> Void

    @State private var selectedMood: Int?
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.liftSuccess)

                        Text("Workout Complete!")
                            .font(.title2.bold())

                        Text(session.workoutName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    // Stats grid
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
                            title: "Exercises",
                            value: "\(session.exerciseLogs.count)",
                            icon: "dumbbell.fill"
                        )
                        SummaryStatCard(
                            title: "Sets",
                            value: "\(completedSetsCount)",
                            icon: "checkmark.circle.fill"
                        )
                    }
                    .padding(.horizontal)

                    // PR Highlights
                    if !sessionPRs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Personal Records")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(sessionPRs) { pr in
                                HStack(spacing: 12) {
                                    Image(systemName: "trophy.fill")
                                        .foregroundStyle(Color.liftPR)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pr.exerciseName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(prDescription(pr))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding()
                                .background(Color.liftPR.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Exercise breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Exercise Breakdown")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(session.exerciseLogs) { log in
                            let workingSets = log.sets.filter { $0.setType == .working && $0.weightKg > 0 }
                            if !workingSets.isEmpty {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.exerciseName)
                                            .font(.subheadline.weight(.medium))
                                        let bestSet = workingSets.max(by: { $0.estimated1RM < $1.estimated1RM })
                                        if let best = bestSet {
                                            let w = UnitConversionService.convertWeight(best.weightKg, to: unitSystem)
                                            Text("Best: \(w.formatted()) \(UnitConversionService.weightLabel(for: unitSystem)) x \(best.reps)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text("\(workingSets.count) sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color.liftCardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Mood selector
                    VStack(spacing: 12) {
                        Text("How did it feel?")
                            .font(.headline)

                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { mood in
                                Button {
                                    selectedMood = selectedMood == mood ? nil : mood
                                    Haptics.selection()
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(moodEmoji(mood))
                                            .font(.title)
                                        Text(moodLabel(mood))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(selectedMood == mood ? Color.accentColor.opacity(0.15) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                            .padding(.horizontal)

                        TextField("How was the session?", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding()
                            .background(Color.liftCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                    }

                    // Done button
                    Button {
                        onSaveMoodAndNotes(selectedMood, notes.isEmpty ? nil : notes)
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(Color.liftBackground)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
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

    private func moodEmoji(_ mood: Int) -> String {
        switch mood {
        case 1: return "\u{1F629}"
        case 2: return "\u{1F615}"
        case 3: return "\u{1F610}"
        case 4: return "\u{1F60A}"
        case 5: return "\u{1F525}"
        default: return "\u{1F610}"
        }
    }

    private func moodLabel(_ mood: Int) -> String {
        switch mood {
        case 1: return "Rough"
        case 2: return "Meh"
        case 3: return "OK"
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.liftCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
