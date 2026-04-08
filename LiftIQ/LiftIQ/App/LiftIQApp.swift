import SwiftUI
import FirebaseCore

@main
struct LiftIQApp: App {
    @State private var dependencies = AppDependencies()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
        }
    }
}
