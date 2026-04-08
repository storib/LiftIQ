import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

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
    }
}
