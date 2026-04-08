import Foundation

enum UnitConversionService {
    static func convertWeight(_ kg: Double, to unit: UnitSystem) -> Double {
        unit == .imperial ? kg * 2.20462 : kg
    }

    static func convertToKg(_ value: Double, from unit: UnitSystem) -> Double {
        unit == .imperial ? value / 2.20462 : value
    }

    static func convertLength(_ cm: Double, to unit: UnitSystem) -> Double {
        unit == .imperial ? cm / 2.54 : cm
    }

    static func convertToCm(_ value: Double, from unit: UnitSystem) -> Double {
        unit == .imperial ? value * 2.54 : value
    }

    static func weightLabel(for unit: UnitSystem) -> String {
        unit == .imperial ? "lb" : "kg"
    }

    static func lengthLabel(for unit: UnitSystem) -> String {
        unit == .imperial ? "in" : "cm"
    }

    static func nearestIncrement(_ weight: Double, increment: Double) -> Double {
        (weight / increment).rounded() * increment
    }
}
