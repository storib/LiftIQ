import Foundation

enum Formatters {
    static let timerFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter
    }()

    static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func timerString(from seconds: Int) -> String {
        timerFormatter.string(from: TimeInterval(seconds)) ?? "0:00"
    }

    static func durationString(from seconds: Int) -> String {
        durationFormatter.string(from: TimeInterval(seconds)) ?? "0m"
    }
}
