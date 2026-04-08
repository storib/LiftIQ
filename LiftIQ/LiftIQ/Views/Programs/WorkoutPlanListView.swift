import SwiftUI

struct WorkoutPlanListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = WorkoutPlanListViewModel()

    var body: some View {
        List {
            if dependencies.workoutService.plans.isEmpty && !viewModel.isLoading {
                ContentUnavailableView {
                    Label("No Programs", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Create your first workout program")
                } actions: {
                    NavigationLink("Browse Templates") {
                        TemplateBrowserView()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ForEach(dependencies.workoutService.plans) { plan in
                NavigationLink {
                    WorkoutPlanDetailView(plan: plan)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(plan.name)
                                    .font(.headline)
                                if plan.isActive {
                                    Text("Active")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(plan.templateType.displayName) \u{2022} \(plan.workoutsPerWeek)x/week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Week \(plan.currentWeek) of \(plan.weekCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        let plan = dependencies.workoutService.plans[index]
                        if let userId = dependencies.authService.currentUserId {
                            await viewModel.deletePlan(workoutService: dependencies.workoutService, userId: userId, planId: plan.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Programs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TemplateBrowserView()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            if let userId = dependencies.authService.currentUserId {
                await viewModel.load(workoutService: dependencies.workoutService, userId: userId)
            }
        }
    }
}
