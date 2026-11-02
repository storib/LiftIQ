import SwiftUI

/// Dashboard card offering an AI change for stalled lifts. The primary
/// button opens `AIModifySheet` with the request pre-filled and already
/// sent, so the lifter lands on a proposal to review — nothing changes until
/// they tap Save Plan there. See `CoachSuggestion` for the trigger.
struct CoachSuggestionCard: View {
    let suggestion: CoachSuggestion
    let plan: WorkoutPlan
    let onPlanModified: (WorkoutPlan) -> Void
    let onDismiss: () -> Void
    /// Beta signal: "shown", "open".
    var onAction: ((String) -> Void)? = nil

    @State private var showingModify = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(.headline, design: .rounded))
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Text("Backing off the weight is one way through. Another is a different exercise or rep range — the AI can propose one, and nothing changes until you save it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(suggestion.lifts.count == 1 ? "Suggest a change" : "Suggest changes") {
                onAction?("open")
                showingModify = true
            }
            .buttonStyle(.liftTinted)

            Button("Not now", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .liftCard()
        .padding(.horizontal)
        .onAppear { onAction?("shown") }
        .sheet(isPresented: $showingModify) {
            AIModifySheet(
                plan: plan,
                workout: nil,
                source: .coachSuggestion,
                onApplyPlan: onPlanModified,
                initialInstruction: suggestion.instruction,
                autoSubmit: true
            )
        }
    }
}
