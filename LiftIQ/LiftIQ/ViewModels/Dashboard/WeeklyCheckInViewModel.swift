import Foundation
import Observation

/// The on-demand Monday check-in: reviews last week, cached per week,
/// dismissable. Nothing is scheduled or pushed — the card simply appears
/// during the week after a trained one.
@MainActor
@Observable
final class WeeklyCheckInViewModel {
    enum State: Equatable {
        case hidden
        case ready
        case loading
        case result(WeeklyInsights)
        case failed(String)
    }

    private(set) var state: State = .hidden
    /// Start of the week being reviewed (last week).
    private(set) var reviewWeekStart: Date = .distantPast
    private(set) var request: WeeklyInsightsRequest?
    private var userId: String?

    private let store: WeeklyInsightsStore
    private let calendar: Calendar

    init(store: WeeklyInsightsStore = WeeklyInsightsStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    func prepare(
        userId: String?,
        sessions: [WorkoutSession],
        plan: WorkoutPlan?,
        profile: UserProfile?,
        unitSystem: UnitSystem,
        now: Date = Date()
    ) {
        // A different account on the same device starts from scratch: no
        // in-flight state, no error, and — via the user-keyed store — no
        // cached insights that belong to someone else.
        if userId != self.userId {
            self.userId = userId
            state = .hidden
        }
        guard let userId else {
            state = .hidden
            return
        }
        let thisWeek = now.startOfWeek(using: calendar)
        guard let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) else {
            state = .hidden
            return
        }
        reviewWeekStart = lastWeek
        request = WeeklySummaryBuilder.build(
            sessions: sessions, plan: plan, profile: profile,
            unitSystem: unitSystem, reviewWeekStart: lastWeek, calendar: calendar
        )
        guard request != nil, !store.isDismissed(userId: userId, weekStart: lastWeek) else {
            state = .hidden
            return
        }
        if let cached = store.load(userId: userId, weekStart: lastWeek) {
            state = .result(cached)
        } else if case .loading = state {
            // A generate is in flight; leave it alone.
        } else if case .failed = state {
            // Keep the error visible until the user retries or dismisses.
        } else {
            state = .ready
        }
    }

    func generate(aiService: AIService) async {
        guard let request, let userId else { return }
        state = .loading
        do {
            let insights = try await aiService.generateWeeklyInsights(request)
            store.save(insights, userId: userId, weekStart: reviewWeekStart)
            state = .result(insights)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func dismiss() {
        if let userId { store.dismiss(userId: userId, weekStart: reviewWeekStart) }
        state = .hidden
    }
}
