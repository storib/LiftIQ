import SwiftUI

struct ExperienceLevelView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Experience Level")
                .font(.title2.bold())
            Text("How long have you been lifting?")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(ExperienceLevel.allCases) { level in
                    Button {
                        viewModel.experienceLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.displayName)
                                    .font(.headline)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.experienceLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.title3)
                            }
                        }
                        .padding()
                        .background(viewModel.experienceLevel == level ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.experienceLevel == level ? Color.accentColor : Color.clear, lineWidth: 2)
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
