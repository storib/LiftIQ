import Foundation

extension Double {
    func formatted(decimals: Int = 1) -> String {
        if self == floor(self) {
            return String(format: "%.0f", self)
        }
        return String(format: "%.\(decimals)f", self)
    }

    func asWeight(unit: UnitSystem) -> String {
        let value = unit == .imperial ? self * 2.20462 : self
        let unitLabel = unit == .imperial ? "lb" : "kg"
        return "\(value.formatted()) \(unitLabel)"
    }

    func asLength(unit: UnitSystem) -> String {
        let value = unit == .imperial ? self / 2.54 : self
        let unitLabel = unit == .imperial ? "in" : "cm"
        return "\(value.formatted()) \(unitLabel)"
    }

    var kgToLb: Double { self * 2.20462 }
    var lbToKg: Double { self / 2.20462 }
}
