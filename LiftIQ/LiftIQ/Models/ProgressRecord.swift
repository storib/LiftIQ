import Foundation

struct ProgressRecord: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var exerciseId: String
    var date: Date
    var estimated1RM: Double
    var bestSetWeight: Double
    var bestSetReps: Int
    var totalVolume: Double
    var totalSets: Int
}
