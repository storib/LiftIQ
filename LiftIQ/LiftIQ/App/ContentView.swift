import SwiftUI

struct ContentView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.authService.isAuthenticated {
                if dependencies.authService.needsOnboarding {
                    OnboardingContainerView()
                } else {
                    MainTabView()
                }
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut, value: dependencies.authService.isAuthenticated)
    }
}
