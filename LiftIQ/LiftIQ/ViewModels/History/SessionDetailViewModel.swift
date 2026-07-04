import Foundation
import Observation

/// Read/edit state for a finished (completed or abandoned) session. Editing a
/// completed session and saving rewrites the same document, which triggers the
/// server-side progressRecords recompute. PR flags on edited sets are left
/// as-is — the same best-effort tradeoff as elsewhere.
@MainActor
@Observable
final class SessionDetailViewModel {
    var session: WorkoutSession
    var isEditing = false
    var isSaving = false
    var isDeleted = false
    var errorMessage: String?

    /// Keyed by SetLog.id — set inputs are never index-addressed.
    var weightInputs: [String: String] = [:]
    var repsInputs: [String: String] = [:]

    init(session: WorkoutSession) {
        self.session = session
    }

    func beginEditing(unitSystem: UnitSystem) {
        weightInputs = [:]
        repsInputs = [:]
        for set in session.exerciseLogs.flatMap(\.sets) {
            let display = UnitConversionService.convertWeight(set.weightKg, to: unitSystem)
            weightInputs[set.id] = display.formatted(decimals: 1)
            repsInputs[set.id] = String(set.reps)
        }
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
        errorMessage = nil
    }

    func save(workoutService: any WorkoutServicing, unitSystem: UnitSystem) async {
        isSaving = true
        errorMessage = nil

        var updated = session
        for logIndex in updated.exerciseLogs.indices {
            for setIndex in updated.exerciseLogs[logIndex].sets.indices {
                let setId = updated.exerciseLogs[logIndex].sets[setIndex].id
                if let text = weightInputs[setId], let value = Double(text.replacingOccurrences(of: ",", with: ".")), value >= 0 {
                    updated.exerciseLogs[logIndex].sets[setIndex].weightKg =
                        UnitConversionService.convertToKg(value, from: unitSystem)
                }
                if let text = repsInputs[setId], let reps = Int(text), reps >= 0 {
                    updated.exerciseLogs[logIndex].sets[setIndex].reps = reps
                }
            }
        }

        do {
            try await workoutService.updateSession(updated)
            session = updated
            isEditing = false
        } catch {
            errorMessage = "Couldn't save changes: \(error.localizedDescription)"
        }
        isSaving = false
    }

    func delete(workoutService: any WorkoutServicing) async {
        errorMessage = nil
        do {
            try await workoutService.deleteSession(session)
            isDeleted = true
        } catch {
            errorMessage = "Couldn't delete workout: \(error.localizedDescription)"
        }
    }
}
