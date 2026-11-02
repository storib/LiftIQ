import SwiftUI

@MainActor
@Observable
final class AppDependencies {
    let authService: AuthService
    let workoutService: WorkoutService
    let exerciseService: ExerciseService
    let progressService: ProgressService
    let aiService: AIService
    let progressionService: ProgressionService
    let healthKitService: HealthKitService
    let memoryService: MemoryService
    let betaEvents: BetaEventLogger
    let liveActivityController: WorkoutLiveActivityController

    init() {
        let userRepo = UserRepository()
        let planRepo = WorkoutPlanRepository()
        let sessionRepo = WorkoutSessionRepository()
        let exerciseRepo = ExerciseRepository()
        let progressRepo = ProgressRecordRepository()
        let prRepo = PersonalRecordRepository()

        self.authService = AuthService(userRepository: userRepo)
        self.healthKitService = HealthKitService()
        self.workoutService = WorkoutService(planRepository: planRepo, sessionRepository: sessionRepo, prRepository: prRepo, healthKitService: healthKitService)
        self.exerciseService = ExerciseService(repository: exerciseRepo)
        self.progressService = ProgressService(progressRepository: progressRepo, prRepository: prRepo)
        let betaEvents = BetaEventLogger(writer: BetaEventRepository())
        self.betaEvents = betaEvents
        self.aiService = AIService(betaEvents: betaEvents)
        self.progressionService = ProgressionService()
        self.memoryService = MemoryService(profileStore: authService)
        self.liveActivityController = WorkoutLiveActivityController()
    }
}
