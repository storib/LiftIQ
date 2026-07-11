import Foundation

/// A device-local workout read from Apple Health. External activities stay
/// separate from WorkoutSession so they never affect LiftIQ programming,
/// progression, personal records, or lifting volume.
struct ExternalActivity: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case walking
        case running
        case cycling
        case hiking
        case swimming
        case strengthTraining
        case highIntensityIntervalTraining
        case yoga
        case pilates
        case rowing
        case elliptical
        case stairClimbing
        case dance
        case coreTraining
        case other

        var displayName: String {
            switch self {
            case .walking: return "Walk"
            case .running: return "Run"
            case .cycling: return "Cycling"
            case .hiking: return "Hike"
            case .swimming: return "Swim"
            case .strengthTraining: return "Strength Training"
            case .highIntensityIntervalTraining: return "HIIT"
            case .yoga: return "Yoga"
            case .pilates: return "Pilates"
            case .rowing: return "Rowing"
            case .elliptical: return "Elliptical"
            case .stairClimbing: return "Stair Climbing"
            case .dance: return "Dance"
            case .coreTraining: return "Core Training"
            case .other: return "Workout"
            }
        }

        var systemImage: String {
            switch self {
            case .walking: return "figure.walk"
            case .running: return "figure.run"
            case .cycling: return "figure.outdoor.cycle"
            case .hiking: return "figure.hiking"
            case .swimming: return "figure.pool.swim"
            case .strengthTraining: return "figure.strengthtraining.traditional"
            case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
            case .yoga: return "figure.yoga"
            case .pilates: return "figure.pilates"
            case .rowing: return "figure.rower"
            case .elliptical: return "figure.elliptical"
            case .stairClimbing: return "figure.stair.stepper"
            case .dance: return "figure.dance"
            case .coreTraining: return "figure.core.training"
            case .other: return "figure.mixed.cardio"
            }
        }
    }

    let id: String
    let kind: Kind
    let startedAt: Date
    let endedAt: Date
    let sourceName: String
    let activeEnergyKilocalories: Double?
    let distanceMeters: Double?

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}
