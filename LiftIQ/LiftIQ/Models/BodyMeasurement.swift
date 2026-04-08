import Foundation

struct BodyMeasurement: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var date: Date
    var bodyWeightKg: Double?
    var bodyFatPercentage: Double?
    var measurements: [String: Double]  // chest, waist, hips, arms, thighs, calves in cm
    var notes: String?
}
