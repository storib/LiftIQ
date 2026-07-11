import Foundation

extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isYesterday: Bool { Calendar.current.isDateInYesterday(self) }

    var relativeDescription: String {
        if isToday { return "Today" }
        if isYesterday { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: self)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    func startOfWeek(using calendar: Calendar = .current) -> Date {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        return mondayCalendar.dateInterval(of: .weekOfYear, for: self)?.start ?? self
    }
}
