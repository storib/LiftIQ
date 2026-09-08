import SwiftUI

/// Swap picker: what the app already knows fits first (usual alternative,
/// same pattern, done before — with the last working set), then the whole
/// catalog to search.
struct ExerciseSwapSheet: View {
    let currentExercise: Exercise?
    var candidates: [WorkoutAdapter.SwapCandidate] = []
    var unitSystem: UnitSystem = .imperial
    let onSelect: (Exercise) -> Void
    var onAvoid: ((Exercise) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var suggested: [WorkoutAdapter.SwapCandidate] { Array(candidates.prefix(5)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !suggested.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggested")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        ForEach(suggested) { candidate in
                            candidateRow(candidate)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color.liftBackground)
                    Divider()
                }
                ExerciseSearchView { exercise in
                    onSelect(exercise)
                    dismiss()
                }
            }
            .navigationTitle(currentExercise.map { "Swap \($0.name)" } ?? "Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func candidateRow(_ candidate: WorkoutAdapter.SwapCandidate) -> some View {
        Button {
            onSelect(candidate.exercise)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: candidate.isUsualAlternative ? "star.fill" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(candidate.isUsualAlternative ? Color.liftPR : Color.accentColor)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if !candidate.reasons.isEmpty {
                        Text(candidate.reasons.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let last = lastLine(candidate.lastLog) {
                        Text(last)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onAvoid {
                Button(role: .destructive) {
                    onAvoid(candidate.exercise)
                } label: {
                    Label("Avoid this exercise", systemImage: "hand.raised")
                }
            }
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
