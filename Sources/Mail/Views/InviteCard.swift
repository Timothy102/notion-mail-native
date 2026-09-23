import AppKit
import MailCore
import SwiftUI

/// Event card for a `text/calendar` (.ics) invite, embedded by ThreadView under the message
/// that carries it. Renders nothing when the file has no event.
struct InviteCard: View {
    let ics: Data

    var body: some View {
        if let event = ICS.events(ics).first {
            Card(event: event, isCancelled: ICS.method(ics) == "CANCEL")
        }
    }

    private struct Card: View {
        let event: CalendarEvent
        let isCancelled: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    DateTile(date: event.start)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .textStyle(.bodyMedium)
                            .strikethrough(isCancelled, color: Theme.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(EventTime.range(event)).textStyle(.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isCancelled {
                        Text("Cancelled").textStyle(.smallMedium).foregroundStyle(Theme.textRed)
                    }
                }
                .padding(16)
                if !details.isEmpty {
                    Hairline().padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(details, id: \.icon) { detail in
                            HStack(spacing: 8) {
                                Image(systemName: detail.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.iconSecondary)
                                    .frame(width: Theme.Metrics.iconSmall)
                                Text(detail.text).textStyle(.body).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                Hairline()
                HStack {
                    Button { NSWorkspace.shared.open(event.calendarURL) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(Theme.iconPrimary)
                            Text("Open in Google Calendar")
                        }
                    }
                    .buttonStyle(.outline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }

        private var details: [(icon: String, text: String)] {
            var rows: [(icon: String, text: String)] = []
            if let location = event.location { rows.append(("mappin.and.ellipse", location)) }
            if let organizer = event.organizer { rows.append(("person", "Organized by \(organizer.displayName)")) }
            let guests = event.attendees.filter { $0.email.lowercased() != event.organizer?.email.lowercased() }
            if !guests.isEmpty {
                let names = guests.prefix(3).map(\.displayName).joined(separator: ", ")
                let count = guests.count == 1 ? "1 guest" : "\(guests.count) guests"
                rows.append(("person.2", count + " · " + (guests.count > 3 ? "\(names) and \(guests.count - 3) more" : names)))
            }
            return rows
        }
    }

    /// Calendar-page tile: short month in red over the day number.
    private struct DateTile: View {
        let date: Date

        var body: some View {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .textStyle(.smallSemibold)
                    .foregroundStyle(Theme.textRed)
                Text(date.formatted(.dateTime.day()))
                    .textStyle(.threadTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 48, height: 48)
            .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
        }
    }
}
