import SwiftUI

/// One-time in-app tutorial shown on first arrival at the main tabs (after
/// onboarding), replayable from Profile. Distinct from the pre-sign-up
/// carousel in WelcomeView: this one teaches the mechanics of using the app.
struct GettingStartedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let body: String
    }

    private static let slides: [Slide] = [
        Slide(
            icon: "house.fill",
            tint: .blue,
            title: "Start from the Dashboard",
            body: "The Up Next card always knows which workout in your program comes next. Tap Start to begin — or use Change to pick a different day. The week strip up top shows everything you've done."
        ),
        Slide(
            icon: "checkmark.circle.fill",
            tint: .green,
            title: "Log Sets in One Tap",
            body: "Enter your weight and reps, then tap the circle to complete a set. Gray values are suggestions — leave a field empty and the checkmark adopts them for you. The rest timer starts automatically and keeps counting even if you switch apps."
        ),
        Slide(
            icon: "flag.checkered",
            tint: .orange,
            title: "Your First Workouts",
            body: "New exercises show a target like 3×8 and tips for picking a starting weight: choose one you could lift a couple of reps past the target. LiftIQ remembers every set and suggests when to add weight."
        ),
        Slide(
            icon: "wand.and.stars",
            tint: .purple,
            title: "Make Any Workout Yours",
            body: "Mid-workout, tap Modify with AI to change today's session or your whole plan in plain English. Tap the arrows on a card to swap an exercise, or long-press a card to remove it."
        ),
        Slide(
            icon: "chart.line.uptrend.xyaxis",
            tint: .pink,
            title: "Watch Yourself Get Stronger",
            body: "Personal records pop up the moment you set them. The Progress tab charts your estimated one-rep max and weekly volume for every exercise you train."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding()
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }

            TabView(selection: $pageIndex) {
                ForEach(Array(Self.slides.enumerated()), id: \.element.id) { index, slide in
                    slideView(slide)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: pageIndex)

            // Custom capsule dots (matches the welcome carousel styling).
            HStack(spacing: 8) {
                ForEach(Self.slides.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == pageIndex ? 20 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: pageIndex)
                }
            }
            .padding(.bottom, 24)

            Button {
                if isLastPage {
                    dismiss()
                } else {
                    pageIndex += 1
                }
            } label: {
                Text(isLastPage ? "Let's Lift" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.liftBackground)
        .interactiveDismissDisabled(false)
    }

    private var isLastPage: Bool {
        pageIndex == Self.slides.count - 1
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(slide.tint.opacity(0.14))
                    .frame(width: 120, height: 120)
                Image(systemName: slide.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(slide.tint)
            }

            Text(slide.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)

            Text(slide.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    GettingStartedView()
}
