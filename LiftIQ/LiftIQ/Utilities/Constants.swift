import Foundation

enum Constants {
    static let barbellIncrement = 2.5  // kg
    static let dumbbellIncrement = 2.0 // kg
    static let machineIncrement = 2.5  // kg
    // Consecutive rep-floor misses at the same top weight before suggesting a
    // back-off. Deliberately an acute stall signal, not a "plateau" claim:
    // per-set e1RM observations carry ~8-10% noise while trained lifters gain
    // 1-3%/year, so no per-session rule can detect a true plateau.
    static let stallThreshold = 3

}
