import SwiftUI

struct WorkoutPlanListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel = WorkoutPlanListViewModel()
    @State private var planPendingDeletion: WorkoutPlan?

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
                // Resolve the plan synchronously; indices may go stale after an await.
                let plans = dependencies.workoutService.plans
                planPendingDeletion = indexSet.compactMap { plans.indices.contains($0) ? plans[$0] : nil }.first
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
                .accessibilityLabel("Add program")
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
        .confirmationDialog(
            "Delete Program?",
            isPresented: Binding(
                get: { planPendingDeletion != nil },
                set: { if !$0 { planPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: planPendingDeletion
        ) { plan in
            Button("Delete \u{201C}\(plan.name)\u{201D}", role: .destructive) {
                deletePlan(plan)
            }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            if plan.isActive {
                Text("\u{201C}\(plan.name)\u{201D} is your active program. Deleting it cannot be undone.")
            } else {
                Text("\u{201C}\(plan.name)\u{201D} will be permanently deleted. This cannot be undone.")
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .refreshable {
            if let userId = dependencies.authService.currentUserId {
                await viewModel.load(workoutService: dependencies.workoutService, userId: userId)
            }
        }
        .task {
            if let userId = dependencies.authService.currentUserId {
                await viewModel.load(workoutService: dependencies.workoutService, userId: userId)
            }
        }
    }

    private func deletePlan(_ plan: WorkoutPlan) {
        Task {
            if let userId = dependencies.authService.currentUserId {
                await viewModel.deletePlan(workoutService: dependencies.workoutService, userId: userId, planId: plan.id)
            }
        }
    }
}
