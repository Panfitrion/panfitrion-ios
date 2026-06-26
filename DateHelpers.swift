import Foundation

enum DateHelpers {
    static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateStyle = .medium
        return formatter
    }()

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_MX")
        calendar.firstWeekday = 2
        return calendar
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func addWeeks(_ weeks: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: weeks * 7, to: date) ?? date
    }

    static func weekStart(for date: Date) -> Date {
        let start = startOfDay(date)
        let weekday = calendar.component(.weekday, from: start)
        let distanceFromMonday = (weekday + 5) % 7
        return addDays(-distanceFromMonday, to: start)
    }

    static func weekEnd(for weekStart: Date) -> Date {
        addDays(5, to: weekStart)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isDate(_ date: Date, inWeekStarting weekStart: Date) -> Bool {
        let day = startOfDay(date)
        let end = weekEnd(for: weekStart)
        return day >= weekStart && day <= end
    }

    static func periodLabel(weekStart: Date) -> String {
        "\(displayFormatter.string(from: weekStart)) - \(displayFormatter.string(from: weekEnd(for: weekStart)))"
    }
}

