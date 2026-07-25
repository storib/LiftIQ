import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    // Device-local like the AI consent keys; the tutorial reappears after a
    // reinstall, which is the desired behavior for a "how the app works" tour.
    @AppStorage("liftiq_seen_getting_started") private var hasSeenGettingStarted = false
    @State private var showingGettingStarted = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(0)

            NavigationStack {
                WorkoutPlanListView()
            }
            .tabItem {
                Label("Programs", systemImage: "list.bullet.clipboard.fill")
            }
            .tag(1)

            NavigationStack {
                ProgressDashboardView()
            }
            .tabItem {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(2)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(3)
        }
        .tint(.blue)
        .onAppear {
            if !hasSeenGettingStarted {
                showingGettingStarted = true
            }
        }
        .sheet(isPresented: $showingGettingStarted, onDismiss: {
            // Skipping counts as seen — the tour stays replayable from Profile.
            hasSeenGettingStarted = true
        }) {
            GettingStartedView()
        }
    }
}
