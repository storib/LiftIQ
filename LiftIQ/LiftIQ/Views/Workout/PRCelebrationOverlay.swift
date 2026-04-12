import SwiftUI

struct PRCelebrationOverlay: View {
    let personalRecord: PersonalRecord
    let unitSystem: UnitSystem
    let onDismiss: () -> Void

    @State private var showConfetti = false
    @State private var showCard = false

    private struct ConfettiData: Identifiable {
        let id: Int
        let xOffset: CGFloat
        let size: CGFloat
        let targetY: CGFloat
        let animationDuration: Double
    }

    private let confettiPieces: [ConfettiData] = (0..<25).map { i in
        ConfettiData(
            id: i,
            xOffset: CGFloat.random(in: -150...150),
            size: CGFloat.random(in: 6...12),
            targetY: CGFloat.random(in: 100...400),
            animationDuration: Double.random(in: 1.5...2.5)
        )
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Confetti particles
            if showConfetti {
                ForEach(confettiPieces) { piece in
                    ConfettiParticle(
                        index: piece.id,
                        xOffset: piece.xOffset,
                        size: piece.size,
                        targetY: piece.targetY,
                        animationDuration: piece.animationDuration
                    )
                }
            }

            // PR Card
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.liftPR)

                Text("New PR!")
                    .font(.title.bold())
                    .foregroundStyle(Color.liftPR)

                Text(personalRecord.exerciseName)
                    .font(.headline)

                Text(prDescription)
                    .font(.title2.weight(.semibold))

                if let previous = personalRecord.previousValue {
                    let improvement = personalRecord.value - previous
                    Text("+ \(improvement.formatted()) \(prUnit)")
                        .font(.subheadline)
                        .foregroundStyle(Color.liftSuccess)
                }
            }
            .padding(32)
            .background(Color.liftCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.liftPR.opacity(0.3), radius: 20)
            .scaleEffect(showCard ? 1 : 0.5)
            .opacity(showCard ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showCard = true
            }
            withAnimation(.easeOut(duration: 0.3)) {
                showConfetti = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            onDismiss()
        }
    }

    private var prDescription: String {
        switch personalRecord.type {
        case .weight:
            return personalRecord.value.asWeight(unit: unitSystem)
        case .estimated1RM:
            return "Est. 1RM: \(personalRecord.value.asWeight(unit: unitSystem))"
        case .reps:
            return "\(Int(personalRecord.value)) reps"
        case .volume:
            return "\(personalRecord.value.asWeight(unit: unitSystem)) volume"
        }
    }

    private var prUnit: String {
        switch personalRecord.type {
        case .weight, .estimated1RM, .volume:
            return UnitConversionService.weightLabel(for: unitSystem)
        case .reps:
            return "reps"
        }
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle: View {
    let index: Int
    let xOffset: CGFloat
    let size: CGFloat
    let targetY: CGFloat
    let animationDuration: Double

    @State private var yOffset: CGFloat = -200
    @State private var opacity: Double = 1

    private let colors: [Color] = [.yellow, .orange, .red, .blue, .green, .purple, .pink]

    var body: some View {
        Circle()
            .fill(colors[index % colors.count])
            .frame(width: size, height: size)
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: animationDuration)) {
                    yOffset = targetY
                    opacity = 0
                }
            }
    }
}
