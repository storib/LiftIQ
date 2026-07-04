import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("LiftIQ")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("Train Smarter. Lift Stronger.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                TutorialCarousel()

                VStack(spacing: 12) {
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    NavigationLink {
                        SignInView()
                    } label: {
                        Text("Already have an account? **Sign In**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

/// Swipeable "how it works" tour shown before sign-up.
struct TutorialCarousel: View {
    @State private var currentPage = 0

    private let slides: [TutorialSlide] = [
        TutorialSlide(
            icon: "brain.head.profile",
            title: "AI-Powered Programs",
            description: "Tell LiftIQ your goals, schedule, and equipment — get a personalized training plan in seconds."
        ),
        TutorialSlide(
            icon: "timer",
            title: "Guided Workouts",
            description: "Log sets with one tap, see last session's numbers as you go, and let the rest timer run even in the background."
        ),
        TutorialSlide(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Progress",
            description: "Estimated 1RM trends and weekly volume charts for every exercise, built automatically from your workouts."
        ),
        TutorialSlide(
            icon: "trophy",
            title: "PRs & Smart Progression",
            description: "Automatic weight and rep suggestions each session, with a celebration every time you set a personal record."
        )
    ]

    var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $currentPage) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    TutorialSlideView(slide: slide)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(currentPage + 1) of \(slides.count)")
        }
    }
}

struct TutorialSlide {
    let icon: String
    let title: String
    let description: String
}

struct TutorialSlideView: View {
    let slide: TutorialSlide

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: slide.icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .frame(width: 96, height: 96)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())

            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.title3.weight(.semibold))
                Text(slide.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    WelcomeView()
}
