import SwiftUI

struct GoalSelectionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Training Goals")
                .font(.title2.bold())
            Text("Select one or more goals")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(Goal.allCases) { goal in
                    Button {
                        if viewModel.selectedGoals.contains(goal) {
                            viewModel.selectedGoals.remove(goal)
                        } else {
                            viewModel.selectedGoals.insert(goal)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.displayName)
                                    .font(.headline)
                                Text(goal.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: viewModel.selectedGoals.contains(goal) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(viewModel.selectedGoals.contains(goal) ? Color.accentColor : Color.secondary)
                                .font(.title3)
                        }
                        .padding()
                        .background(viewModel.selectedGoals.contains(goal) ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.selectedGoals.contains(goal) ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
    }
}
