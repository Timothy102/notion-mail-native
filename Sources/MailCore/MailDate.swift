import Foundation

/// Date strings used across the list, search and palette (SPEC §4.3, §5.2).
public enum MailDate {
    /// "11:32 PM" today, "Mar 6" this year, "Dec 25, 2024" before.
    public static func list(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let style: Date.FormatStyle
        if calendar.isDate(date, inSameDayAs: now) {
            style = .dateTime.hour().minute()
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = .dateTime.month(.abbreviated).day()
        } else {
            style = .dateTime.month(.abbreviated).day().year()
        }
        return date.formatted(style.locale(calendar.locale ?? .current)).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// Date-group title: nil for today, then "Yesterday", "Last 7 days", "Last 30 days",
    /// "March" (this year) or "Dec 2024" (earlier years).
    public static func group(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return nil
        case 1: return "Yesterday"
        case 2..<7: return "Last 7 days"
        case 7..<30: return "Last 30 days"
        default:
            let locale = calendar.locale ?? .current
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                return date.formatted(.dateTime.month(.wide).locale(locale))
            }
            return date.formatted(.dateTime.month(.abbreviated).year().locale(locale))
        }
    }

    /// Remind-me choices (SPEC §5.2): in three hours, tomorrow at 9, next Monday at 9.
    public static func reminderOptions(now: Date = .now, calendar: Calendar = .current) -> [(title: String, date: Date)] {
        let laterToday = calendar.date(byAdding: .hour, value: 3, to: now) ?? now
        let tomorrow = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: now) ?? now) ?? now
        let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, weekday: 2), matchingPolicy: .nextTime) ?? now
        return [("Later today", laterToday), ("Tomorrow", tomorrow), ("Next week", monday)]
    }
}
