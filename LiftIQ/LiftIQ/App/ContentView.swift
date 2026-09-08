import SwiftUI

struct ContentView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

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
        .task(id: dependencies.authService.isAuthenticated) {
            guard dependencies.authService.isAuthenticated else { return }
            dependencies.betaEvents.log("app_open")
            try? await dependencies.exerciseService.loadExercises()
        }
        .onChange(of: scenePhase) { previous, phase in
            // Returning from the background counts as an open; the initial
            // launch is covered by the task above.
            if phase == .active, previous == .background, dependencies.authService.isAuthenticated {
                dependencies.betaEvents.log("app_open")
            }
        }
    }
}
