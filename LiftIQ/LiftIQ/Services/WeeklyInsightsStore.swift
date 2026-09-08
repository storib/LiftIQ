import Foundation

/// Device-local cache of weekly check-ins, keyed by user and the reviewed
/// week's start date. Like AI consent and the Getting Started flag this
/// stays in UserDefaults: the result is disposable and needs no rules or
/// server delete path. Keys carry the user id so two accounts on one device
/// never see each other's training insights.
struct WeeklyInsightsStore {
    private static let prefix = "liftiq_weekly_insights_"
    private static let dismissedSuffix = "_dismissed"
    private static let keepWeeks = 4

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    func load(userId: String, weekStart: Date) -> WeeklyInsights? {
        guard let data = defaults.data(forKey: key(userId, weekStart)) else { return nil }
        return try? JSONDecoder().decode(WeeklyInsights.self, from: data)
    }

    func save(_ insights: WeeklyInsights, userId: String, weekStart: Date) {
        if let data = try? JSONEncoder().encode(insights) {
            defaults.set(data, forKey: key(userId, weekStart))
        }
        prune(userId: userId, before: weekStart)
    }

    func isDismissed(userId: String, weekStart: Date) -> Bool {
        defaults.bool(forKey: key(userId, weekStart) + Self.dismissedSuffix)
    }

    func dismiss(userId: String, weekStart: Date) {
        defaults.set(true, forKey: key(userId, weekStart) + Self.dismissedSuffix)
        prune(userId: userId, before: weekStart)
    }

    /// Drops this user's entries older than a month before `weekStart`.
    func prune(userId: String, before weekStart: Date) {
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -Self.keepWeeks, to: weekStart) else { return }
        let userPrefix = Self.userPrefix(userId)
        let cutoffKey = userPrefix + Self.dayString(cutoff, calendar: calendar)
        for storedKey in defaults.dictionaryRepresentation().keys
        where storedKey.hasPrefix(userPrefix) && storedKey < cutoffKey {
            defaults.removeObject(forKey: storedKey)
        }
    }

    /// Removes everything cached for a user — called on account deletion.
    func clear(userId: String) {
        let userPrefix = Self.userPrefix(userId)
        for storedKey in defaults.dictionaryRepresentation().keys where storedKey.hasPrefix(userPrefix) {
            defaults.removeObject(forKey: storedKey)
        }
    }

    private func key(_ userId: String, _ weekStart: Date) -> String {
        Self.userPrefix(userId) + Self.dayString(weekStart, calendar: calendar)
    }

    private static func userPrefix(_ userId: String) -> String {
        prefix + userId + "_"
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
