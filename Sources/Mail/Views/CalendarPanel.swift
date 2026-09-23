import AppKit
import MailCore
import SwiftUI

/// "Calendar" section at the bottom of the sidebar (SPEC §4.2 item 5, §5.10): today's events,
/// then the next days that have any. Demo mode shows fixture events.
struct CalendarPanel: View {
    @Environment(AppState.self) private var app
    @State private var feed: CalendarFeed?

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                header(now: context.date)
                if let feed { content(feed, now: context.date) }
            }
        }
        .task {
            let feed = CalendarFeed(client: app.gmail.map { GoogleCalendarClient(token: $0.token) })
            self.feed = feed
            feed.start()
        }
    }

    private func header(now: Date) -> some View {
        HStack {
            Text("Calendar").textStyle(.smallMedium).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .textStyle(.small).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 30, alignment: .bottom)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func content(_ feed: CalendarFeed, now: Date) -> some View {
        switch feed.status {
        case .loading:
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.skeleton).frame(width: 30, height: 12)
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.skeleton).frame(width: i == 0 ? 120 : 92, height: 12)
                }
                .padding(.leading, 27)
                .frame(height: Self.rowHeight)
            }
        case .failed:
            note("Couldn't load events") {
                Button("Retry") { Task { await feed.refresh() } }
                    .buttonStyle(.plain)
                    .textStyle(.small)
                    .foregroundStyle(Theme.textBlue)
            }
        case .loaded:
            ForEach(feed.days(now: now), id: \.day) { day, events in
                if !Calendar.current.isDateInToday(day) {
                    Text(dayTitle(day))
                        .textStyle(.small)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, 18)
                        .frame(height: 26, alignment: .bottom)
                        .padding(.top, 4)
                }
                if events.isEmpty {
                    note(Calendar.current.isDateInToday(day) && !feed.events.isEmpty ? "No more events today" : "No events today") { EmptyView() }
                }
                ForEach(events) { CalendarEventRow(event: $0, now: now) }
            }
        }
    }

    private func note(_ text: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(text).textStyle(.small).foregroundStyle(Theme.textTertiary)
            trailing()
        }
        .padding(.leading, 18)
        .frame(height: Theme.Metrics.sidebarItemPitch)
    }

    private func dayTitle(_ day: Date) -> String {
        Calendar.current.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static let rowHeight: CGFloat = 44
}

/// §5.10 calendar sidebar item: color bar, start time, title and location. Opens the event in Google Calendar.
private struct CalendarEventRow: View {
    let event: CalendarEvent
    let now: Date
    @State private var hovering = false

    var body: some View {
        let ended = !event.isAllDay && event.hasEnded(now: now)
        let live = !event.isAllDay && event.isHappening(now: now)
        Button { NSWorkspace.shared.open(event.calendarURL) } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(event.color, dark: event.color))
                    .frame(width: 3, height: 16)
                    .padding(.trailing, 7)
                Text(time)
                    .textStyle(live ? .smallMedium : .small)
                    .monospacedDigit()
                    .foregroundStyle(live ? Theme.textBlue : Theme.textTertiary)
                    .lineLimit(1)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(event.title).textStyle(.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if let location = event.isAllDay ? "All day" : event.location {
                        Text(location).textStyle(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .opacity(ended ? 0.55 : 1)
            .padding(.leading, 9)
            .padding(.trailing, 9)
            .frame(height: CalendarPanel.rowHeight)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Metrics.sidebarItemInset)
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
        .help(event.title + "\n" + EventTime.range(event))
    }

    private var time: String {
        event.isAllDay ? "" : Self.clock.string(from: event.start)
            .replacingOccurrences(of: Self.clock.amSymbol, with: "")
            .replacingOccurrences(of: Self.clock.pmSymbol, with: "")
            .trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\u{202F}")))
    }

    /// "9:30" or "21:30" by locale, without AM/PM.
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()
}

enum EventTime {
    /// "Thu, Sep 24 · 2:00 – 3:00 PM", "Thu, Sep 24 · All day", "Oct 19 – 21".
    static func range(_ event: CalendarEvent) -> String {
        let cal = Calendar.current
        let day = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if event.isAllDay {
            let last = cal.date(byAdding: .day, value: -1, to: event.end) ?? event.start
            if cal.isDate(last, inSameDayAs: event.start) || last < event.start { return event.start.formatted(day) + " · All day" }
            return (event.start..<last).formatted(.interval.month(.abbreviated).day())
        }
        if cal.isDate(event.start, inSameDayAs: event.end) || event.end == event.start {
            return event.start.formatted(day) + " · " + (event.start..<event.end).formatted(.interval.hour().minute())
        }
        return (event.start..<event.end).formatted(.interval.month(.abbreviated).day().hour().minute())
    }
}
