import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = OnboardingViewModel()
    @State private var showingAIConsent = false

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
            // Steps advance only through the validated Next button; swiping
            // could skip past steps that fail validation.
            .highPriorityGesture(DragGesture())
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
                        requestCompletion()
                    } label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(viewModel.declinedAIConsent ? "Finish Setup" : "Generate My Program")
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
        .sheet(isPresented: $showingAIConsent) {
            AIConsentSheet(
                onAccept: {
                    showingAIConsent = false
                    completeOnboarding()
                },
                onDecline: {
                    showingAIConsent = false
                    // Without consent we can't generate a plan. Return to the
                    // summary so the CTA and copy can explain what happens next
                    // instead of silently ending onboarding without a program.
                    viewModel.declinedAIConsent = true
                }
            )
            .presentationDetents([.large])
        }
    }

    private func requestCompletion() {
        if AIConsentManager.hasConsented || viewModel.declinedAIConsent {
            completeOnboarding()
        } else {
            showingAIConsent = true
        }
    }

    /// Saves the profile and, when AI consent was granted, generates the plan.
    private func completeOnboarding() {
        Task {
            await viewModel.saveProfileAndGeneratePlan(
                authService: dependencies.authService,
                aiService: dependencies.aiService,
                workoutService: dependencies.workoutService
            )
        }
    }
}

struct OnboardingWelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 20)

                // App icon / hero
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    Text("Welcome to LiftIQ")
                        .font(.title.bold())
                    Text("Your intelligent lifting companion")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Feature highlights
                VStack(spacing: 20) {
                    OnboardingFeatureRow(
                        icon: "brain.head.profile",
                        title: "AI-Powered Plans",
                        description: "Get a workout program built around your goals, experience, and available equipment."
                    )
                    OnboardingFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Smart Progression",
                        description: "Automatically adjusts weights and volume so you keep making gains week over week."
                    )
                    OnboardingFeatureRow(
                        icon: "play.rectangle.fill",
                        title: "Form Videos",
                        description: "Watch proper technique for every exercise right from your workout screen."
                    )
                    OnboardingFeatureRow(
                        icon: "trophy.fill",
                        title: "Track Your Records",
                        description: "Log every set, see personal records, and watch your progress over time."
                    )
                }
                .padding(.horizontal, 8)

                Text("Let's set up your profile so we can build a program just for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
