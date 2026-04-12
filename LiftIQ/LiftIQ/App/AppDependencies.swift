import SwiftUI

@Observable
final class AppDependencies {
    let authService: AuthService
    let workoutService: WorkoutService
    let exerciseService: ExerciseService
    let progressService: ProgressService
    let aiService: AIService
    let progressionService: ProgressionService

    init() {
        let planRepo = WorkoutPlanRepository()
        let sessionRepo = WorkoutSessionRepository()
        let exerciseRepo = ExerciseRepository()
        let progressRepo = ProgressRecordRepository()
        let prRepo = PersonalRecordRepository()
        let bodyRepo = BodyMeasurementRepository()

        self.authService = AuthService()
        self.workoutService = WorkoutService(planRepository: planRepo, sessionRepository: sessionRepo)
        self.exerciseService = ExerciseService(repository: exerciseRepo)
        self.progressService = ProgressService(progressRepository: progressRepo, prRepository: prRepo, bodyRepository: bodyRepo)
        self.aiService = AIService()
        self.progressionService = ProgressionService()
    }
}
