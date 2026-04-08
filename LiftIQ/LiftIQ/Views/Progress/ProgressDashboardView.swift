import SwiftUI

struct ProgressDashboardView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // PRs section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent PRs")
                        .font(.headline)

                    if dependencies.progressService.recentPRs.isEmpty {
                        Text("No personal records yet. Start lifting!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(dependencies.progressService.recentPRs.prefix(5)) { pr in
                            HStack {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.exerciseName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(pr.type.displayName): \(pr.value.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(pr.achievedAt.shortDate)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)

                // Placeholder for charts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Strength Trends")
                        .font(.headline)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(height: 200)
                        .overlay {
                            Text("Charts coming soon")
                                .foregroundStyle(.secondary)
                        }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .task {
            if let userId = dependencies.authService.currentUserId {
                try? await dependencies.progressService.loadRecentPRs(userId: userId)
            }
        }
    }
}
