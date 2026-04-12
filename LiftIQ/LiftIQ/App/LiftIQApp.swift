import SwiftUI
import FirebaseCore
import FirebaseAppCheck

@main
struct LiftIQApp: App {
    @State private var dependencies: AppDependencies
    private static var didConfigureFirebase = false

    init() {
        Self.configureFirebase()
        _dependencies = State(initialValue: AppDependencies())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dependencies)
        }
    }

    private static func configureFirebase() {
        guard !didConfigureFirebase else { return }
        defer { didConfigureFirebase = true }

        let hasRealConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

        // Configure App Check BEFORE FirebaseApp.configure()
        // Skip when using placeholder config — there's no real project to validate against
        if hasRealConfig {
            #if DEBUG
            let providerFactory = AppCheckDebugProviderFactory()
            #else
            let providerFactory = LiftIQAppCheckProviderFactory()
            #endif
            AppCheck.setAppCheckProviderFactory(providerFactory)
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            return
        }

        #if DEBUG
        let options = FirebaseOptions(
            googleAppID: "1:000000000000:ios:0000000000000000",
            gcmSenderID: "000000000000"
        )
        options.apiKey = "AIzaSy000000000000000000000000000000000"
        options.projectID = "liftiq-debug"
        options.bundleID = Bundle.main.bundleIdentifier ?? "com.liftiq.app"
        FirebaseApp.configure(options: options)
        #else
        FirebaseApp.configure()
        #endif
    }
}

/// Production App Check provider: App Attest with DeviceCheck fallback.
final class LiftIQAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> (any AppCheckProvider)? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app) ?? DeviceCheckProvider(app: app)
        #endif
    }
}
