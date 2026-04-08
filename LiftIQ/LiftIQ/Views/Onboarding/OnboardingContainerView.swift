import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: viewModel.progress)
                .tint(.accentColor)
                .padding(.horizontal)
                .padding(.top, 8)

            // Step indicator
            Text("Step \(viewModel.currentStep + 1) of \(viewModel.totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Content
            TabView(selection: $viewModel.currentStep) {
                OnboardingWelcomeStep()
                    .tag(0)
                ExperienceLevelView(viewModel: viewModel)
                    .tag(1)
                GoalSelectionView(viewModel: viewModel)
                    .tag(2)
                EquipmentView(viewModel: viewModel)
                    .tag(3)
                ScheduleView(viewModel: viewModel)
                    .tag(4)
                InjuryView(viewModel: viewModel)
                    .tag(5)
                BodyMetricsView(viewModel: viewModel)
                    .tag(6)
                OnboardingSummaryView(viewModel: viewModel)
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: viewModel.currentStep)

            // Navigation buttons
            HStack {
                if viewModel.currentStep > 0 {
                    Button("Back") {
                        viewModel.back()
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.currentStep < viewModel.totalSteps - 1 {
                    Button {
                        viewModel.next()
                    } label: {
                        Text("Next")
                            .font(.headline)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(viewModel.canAdvance ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!viewModel.canAdvance)
                } else {
                    Button {
                        Task { await viewModel.saveProfile(authService: dependencies.authService) }
                    } label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Generate My Program")
                            }
                        }
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Let's Build Your Program")
                .font(.title.bold())

            Text("Answer a few questions so we can create a personalized workout plan just for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }
}
