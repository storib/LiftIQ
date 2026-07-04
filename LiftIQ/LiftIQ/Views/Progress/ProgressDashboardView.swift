import SwiftUI

struct ProgressDashboardView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var unitSystem: UnitSystem {
        dependencies.authService.currentUser?.profile.unitSystem ?? .imperial
    }

    var body: some View {
        Group {
            if isLoading && !hasLoaded {
                LoadingView()
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .task {
            await load()
        }
    }

    private var content: some View {
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
                                    Text(prDescription(pr))
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
        .refreshable {
            await load()
        }
    }

    private func prDescription(_ pr: PersonalRecord) -> String {
        switch pr.type {
        case .reps:
            return "\(pr.type.displayName): \(Int(pr.value))"
        case .weight, .estimated1RM, .volume:
            let value = UnitConversionService.convertWeight(pr.value, to: unitSystem)
            return "\(pr.type.displayName): \(value.formatted()) \(UnitConversionService.weightLabel(for: unitSystem))"
        }
    }

    private func load() async {
        guard let userId = dependencies.authService.currentUserId else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await dependencies.progressService.loadRecentPRs(userId: userId)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
