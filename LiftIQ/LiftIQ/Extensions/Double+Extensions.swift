import Foundation

extension Double {
    func formatted(decimals: Int = 1) -> String {
        if self == floor(self) {
            return String(format: "%.0f", self)
        }
        return String(format: "%.\(decimals)f", self)
    }

    /// Formats a kg value in the given unit system, delegating the conversion
    /// to `UnitConversionService` (the single source of truth for factors).
    func asWeight(unit: UnitSystem) -> String {
        let value = UnitConversionService.convertWeight(self, to: unit)
        return "\(value.formatted()) \(UnitConversionService.weightLabel(for: unit))"
    }
}
