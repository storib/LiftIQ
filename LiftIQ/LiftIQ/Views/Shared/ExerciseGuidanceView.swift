import SwiftUI

struct ExerciseGuidanceView: View {
    let exercise: Exercise
    var showsVideo: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if showsVideo, !exercise.youtubeVideoId.isEmpty {
                YouTubePlayerView(videoId: exercise.youtubeVideoId)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            guidanceSection(
                title: "How to do it",
                systemImage: "figure.strengthtraining.traditional"
            ) {
                Text(exercise.instructions)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !exercise.tips.isEmpty {
                guidanceSection(
                    title: "Form cues",
                    systemImage: "checkmark.seal"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(exercise.tips, id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(exercise.difficulty.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GuidanceChip(
                        title: exercise.primaryMuscleGroup.displayName,
                        systemImage: "target",
                        tint: .orange
                    )
                    GuidanceChip(
                        title: exercise.movementPattern.displayName,
                        systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                        tint: .teal
                    )
                    ForEach(exercise.equipment, id: \.self) { equipment in
                        GuidanceChip(
                            title: equipment.displayName,
                            systemImage: equipment.icon,
                            tint: .blue
                        )
                    }
                }
            }
        }
    }

    private func guidanceSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
        }
    }
}

private struct GuidanceChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
