import Foundation
import Observation

public struct CalendarEvent: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// sRGB hex of the event (or its calendar) color.
    public var color: UInt32
    public var organizer: EmailAddress?
    public var attendees: [EmailAddress]
    public var link: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil,
                color: UInt32 = CalendarEvent.defaultColor, organizer: EmailAddress? = nil, attendees: [EmailAddress] = [], link: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.color = color
        self.organizer = organizer
        self.attendees = attendees
        self.link = link
    }

    public static let defaultColor: UInt32 = 0x2383E2

    /// Google Calendar's event `colorId` palette.
    static let googleColors: [String: UInt32] = [
        "1": 0x7986CB, "2": 0x33B679, "3": 0x8E24AA, "4": 0xE67C73, "5": 0xF6BF26, "6": 0xF4511E,
        "7": 0x039BE5, "8": 0x616161, "9": 0x3F51B5, "10": 0x0B8043, "11": 0xD50000,
    ]

    public func hasEnded(now: Date = .now) -> Bool { end <= now }
    public func isHappening(now: Date = .now) -> Bool { start <= now && now < end }

    /// A Google Calendar day view of the event when there is no event link (e.g. an .ics invite).
    public var calendarURL: URL {
        if let link { return link }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: start)
        return URL(string: "https://calendar.google.com/calendar/r/day/\(c.year!)/\(c.month!)/\(c.day!)")!
    }
}

// MARK: - iCalendar (RFC 5545) invites

public enum ICS {
    /// The VEVENTs of an .ics file. Handles line folding, TEXT escapes, UTC / TZID / floating / DATE values.
    public static func events(_ data: Data) -> [CalendarEvent] {
        events(String(decoding: data, as: UTF8.self))
    }

    public static func events(_ text: String) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        var current: [(name: String, params: [String: String], value: String)]?
        for line in unfold(text) {
            let property = parse(line)
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT"): current = []
            case ("END", "VEVENT"):
                if let props = current, let event = event(props) { events.append(event) }
                current = nil
            default: current?.append(property)
            }
        }
        return events
    }

    /// METHOD:CANCEL invites show as cancelled.
    public static func method(_ data: Data) -> String? {
        unfold(String(decoding: data, as: UTF8.self)).map(parse).first { $0.name == "METHOD" }?.value.uppercased()
    }

    private static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines.filter { !$0.isEmpty }
    }

    /// `NAME;P1=V1;P2="V;2":value`. The value starts at the first colon outside quotes.
    private static func parse(_ line: String) -> (name: String, params: [String: String], value: String) {
        var inQuotes = false
        var split = line.endIndex
        for i in line.indices {
            if line[i] == "\"" { inQuotes.toggle() } else if line[i] == ":", !inQuotes { split = i; break }
        }
        let head = line[..<split]
        let value = split < line.endIndex ? String(line[line.index(after: split)...]) : ""
        let parts = head.split(separator: ";")
        var params: [String: String] = [:]
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return ((parts.first.map(String.init) ?? "").uppercased(), params, value)
    }

    private static func event(_ props: [(name: String, params: [String: String], value: String)]) -> CalendarEvent? {
        func first(_ name: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == name }.map { ($0.params, $0.value) }
        }
        guard let startProp = first("DTSTART"), let (start, allDay) = date(startProp.value, params: startProp.params) else { return nil }
        let end = first("DTEND").flatMap { date($0.value, params: $0.params)?.0 }
            ?? first("DURATION").flatMap { duration($0.value) }.map { start.addingTimeInterval($0) }
            ?? start.addingTimeInterval(allDay ? 86_400 : 0)
        let location = first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        return CalendarEvent(
            id: first("UID")?.value ?? UUID().uuidString,
            title: first("SUMMARY").map { unescape($0.value) } ?? "(No title)",
            start: start, end: end, isAllDay: allDay, location: location,
            organizer: first("ORGANIZER").map(address),
            attendees: props.filter { $0.name == "ATTENDEE" }.map { address(($0.params, $0.value)) },
            link: first("URL").flatMap { URL(string: $0.value) })
    }

    private static func address(_ prop: (params: [String: String], value: String)) -> EmailAddress {
        let email = prop.value.replacingOccurrences(of: "mailto:", with: "", options: [.caseInsensitive, .anchored])
        return EmailAddress(name: prop.params["CN"].map(unescape), email: email)
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                out.append(c == "n" || c == "N" ? "\n" : c)
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// Returns the date and whether it is a whole-day (VALUE=DATE) value.
    private static func date(_ value: String, params: [String: String]) -> (Date, Bool)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        if params["VALUE"] == "DATE" || value.count == 8 {
            f.timeZone = .current
            f.dateFormat = "yyyyMMdd"
            return f.date(from: value).map { ($0, true) }
        }
        if value.hasSuffix("Z") {
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            f.timeZone = params["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
            f.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return f.date(from: value).map { ($0, false) }
    }

    /// `P1DT2H30M`, `PT45M`, `P2W`.
    private static func duration(_ value: String) -> TimeInterval? {
        var seconds: TimeInterval = 0
        var number = ""
        var inTime = false
        for c in value.uppercased() {
            switch c {
            case "P", "+": continue
            case "T": inTime = true
            case "0"..."9": number.append(c)
            default:
                guard let n = Double(number) else { return nil }
                number = ""
                switch (c, inTime) {
                case ("W", _): seconds += n * 604_800
                case ("D", _): seconds += n * 86_400
                case ("H", true): seconds += n * 3600
                case ("M", true): seconds += n * 60
                case ("S", true): seconds += n
                default: return nil
                }
            }
        }
        return seconds
    }
}

// MARK: - Google Calendar (calendar.readonly)

public struct GoogleCalendarClient: Sendable {
    private let token: @Sendable (_ refresh: Bool) async throws -> String

    public init(token: @escaping @Sendable (_ refresh: Bool) async throws -> String = { try await Auth.shared.token(refresh: $0) }) {
        self.token = token
    }

    /// Single (expanded) events on the primary calendar overlapping `from..<to`, by start time.
    public func events(from: Date, to: Date) async throws -> [CalendarEvent] {
        var url = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        let iso = ISO8601DateFormatter()
        url.queryItems = [
            .init(name: "timeMin", value: iso.string(from: from)), .init(name: "timeMax", value: iso.string(from: to)),
            .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime"), .init(name: "maxResults", value: "50"),
        ]
        var refreshed = false
        while true {
            var req = URLRequest(url: url.url!)
            req.setValue("Bearer \(try await token(refreshed))", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !refreshed { refreshed = true; continue }
            guard status == 200 else { throw GmailError.http(status: status, body: String(decoding: data, as: UTF8.self)) }
            return try JSONDecoder().decode(GoogleEventList.self, from: data).items.compactMap(\.event)
        }
    }
}

struct GoogleEventList: Decodable {
    struct Time: Decodable { var dateTime: String?; var date: String? }
    struct Person: Decodable { var email: String?; var displayName: String?; var responseStatus: String?; var isSelf: Bool?
        enum CodingKeys: String, CodingKey { case email, displayName, responseStatus, isSelf = "self" } }
    struct Item: Decodable {
        var id: String
        var status: String?
        var summary: String?
        var location: String?
        var colorId: String?
        var htmlLink: String?
        var start: Time
        var end: Time
        var organizer: Person?
        var attendees: [Person]?

        var event: CalendarEvent? {
            guard status != "cancelled", attendees?.first(where: { $0.isSelf == true })?.responseStatus != "declined",
                  let (start, allDay) = Self.date(start), let (end, _) = Self.date(end) else { return nil }
            func address(_ p: Person) -> EmailAddress? { p.email.map { EmailAddress(name: p.displayName, email: $0) } }
            return CalendarEvent(id: id, title: summary ?? "(No title)", start: start, end: end, isAllDay: allDay, location: location,
                                 color: colorId.flatMap { CalendarEvent.googleColors[$0] } ?? CalendarEvent.defaultColor,
                                 organizer: organizer.flatMap(address), attendees: (attendees ?? []).compactMap(address),
                                 link: htmlLink.flatMap(URL.init(string:)))
        }

        static func date(_ t: Time) -> (Date, Bool)? {
            if let s = t.dateTime {
                let f = ISO8601DateFormatter()
                if let d = f.date(from: s) { return (d, false) }
                f.formatOptions.insert(.withFractionalSeconds)
                return f.date(from: s).map { ($0, false) }
            }
            guard let s = t.date else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s).map { ($0, true) }
        }
    }
    var items: [Item]
}

/// Today's and the next few days' events for the sidebar. Refreshes every 5 minutes.
@MainActor @Observable
public final class CalendarFeed {
    public enum Status: Equatable { case loading, loaded, failed(String) }

    public private(set) var events: [CalendarEvent] = []
    public private(set) var status: Status = .loading
    /// nil in demo mode: fixture events, no network.
    private let client: GoogleCalendarClient?
    @ObservationIgnored private var loop: Task<Void, Never>?

    public static let upcomingDays = 3

    public init(client: GoogleCalendarClient?) {
        self.client = client
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    public func refresh() async {
        let today = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: Self.upcomingDays, to: today)!
        guard let client else {
            events = CalendarFixtures.events(now: .now)
            status = .loaded
            return
        }
        do {
            events = try await client.events(from: today, to: end)
            status = .loaded
        } catch {
            if events.isEmpty { status = .failed(error.localizedDescription) }
        }
    }

    /// Days with events, from today, each with its events: all-day first, then by start.
    public func days(now: Date = .now, calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])] {
        let today = calendar.startOfDay(for: now)
        return (0..<Self.upcomingDays).compactMap { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let list = events.filter { $0.start < next && $0.end > day && (offset > 0 || !$0.isAllDay || $0.end > now) }
                .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
            return offset == 0 || !list.isEmpty ? (day, list) : nil
        }
    }
}

enum CalendarFixtures {
    static func events(now: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: dayOffset * 1440 + h * 60 + m, to: cal.startOfDay(for: now))!
        }
        let zoe = EmailAddress(name: "Zoë Müller", email: "zoe@helio.dev")
        let priya = EmailAddress(name: "Priya Raman", email: "priya@helio.dev")
        func e(_ id: String, _ title: String, _ start: Date, _ minutes: Int, _ location: String?, _ color: String?, _ organizer: EmailAddress? = nil) -> CalendarEvent {
            CalendarEvent(id: id, title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), location: location,
                          color: color.flatMap { CalendarEvent.googleColors[$0] } ?? CalendarEvent.defaultColor, organizer: organizer)
        }
        return [
            e("standup", "Mail team standup", at(0, 9, 30), 15, "Google Meet", "7", priya),
            e("live", "Search demo with Priya", Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 900).rounded(.down) * 900), 30, "Google Meet", "10", priya),
            e("focus", "Focus: search result states", at(0, 13), 120, nil, "8"),
            e("zoe-1on1", "1:1 Zoë / Tim", at(0, 15, 30), 30, "Room Tivoli", "2", zoe),
            e("offsite", "Offsite planning — Ljubljana venue shortlist and budget", at(0, 17), 45, "Google Meet", "5", priya),
            CalendarEvent(id: "ooo", title: "Marco out of office", start: at(1, 0), end: at(2, 0), isAllDay: true, color: CalendarEvent.googleColors["3"]!),
            e("planning", "Q4 planning", at(1, 10), 60, "Room Bled", "9", priya),
            e("dentist", "Dentist", at(1, 16, 15), 45, "Trubarjeva 12, Ljubljana", "4"),
        ]
    }
}
