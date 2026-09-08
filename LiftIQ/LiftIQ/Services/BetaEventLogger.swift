import Foundation

/// Where beta events end up. `BetaEventRepository` writes to Firestore;
/// tests record.
protocol BetaEventWriting: Sendable {
    func write(name: String, props: [String: any Sendable], appVersion: String, build: String) async throws
}

/// Fire-and-forget usage signal for the beta: which flows get used, which
/// suggestions get overridden, whether lifters come back. Never blocks the
/// caller and never surfaces an error. Nothing here goes to Anthropic.
protocol BetaEventLogging: Sendable {
    func log(_ name: String, _ props: [String: any Sendable])
}

extension BetaEventLogging {
    func log(_ name: String) { log(name, [:]) }
}

struct NoopBetaEventLogger: BetaEventLogging {
    func log(_ name: String, _ props: [String: any Sendable]) {}
}

struct BetaEventLogger: BetaEventLogging {
    static let enabledKey = "liftiq.betaEventsEnabled"

    /// TestFlight and debug builds; App Store builds default to off.
    static var isBetaBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Device-local preference (Profile → Data & Privacy).
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? isBetaBuild }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let writer: any BetaEventWriting
    private let isEnabledNow: @Sendable () -> Bool
    private let appVersion: String
    private let build: String

    init(
        writer: any BetaEventWriting,
        isEnabled: @escaping @Sendable () -> Bool = { BetaEventLogger.isEnabled },
        bundle: Bundle = .main
    ) {
        self.writer = writer
        self.isEnabledNow = isEnabled
        self.appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        self.build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    func log(_ name: String, _ props: [String: any Sendable]) {
        guard isEnabledNow() else { return }
        let writer = writer
        let appVersion = appVersion
        let build = build
        Task.detached(priority: .utility) {
            try? await writer.write(name: name, props: props, appVersion: appVersion, build: build)
        }
    }
}
