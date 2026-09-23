import MailCore
import SwiftUI

/// SPEC §4.2. Owner: sidebar feature.
struct Sidebar: View {
    @Environment(AppState.self) private var app
    @State private var counts = Live<[String: Int]>([:])
    @State private var labels = Live<[MailLabel]>([])

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Theme.Metrics.titleBarHeight)
            accountRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarItem(title: "Search", icon: { SlotIcon(systemName: "magnifyingglass") }) { app.palette = .search }
                    section("Views")
                    mailbox(.inbox, tint: Theme.inboxRed)
                    mailbox(.starred)
                    section("Mail")
                    mailbox(.all)
                    mailbox(.sent)
                    mailbox(.drafts)
                    mailbox(.spam)
                    mailbox(.trash)
                    if !labels.value.isEmpty {
                        section("Labels")
                        ForEach(labels.value) { label in
                            SidebarItem(title: label.name, count: counts.value[label.id] ?? 0, isSelected: isCurrent(.label(label.id)),
                                        icon: { Circle().fill(LabelColor(named: label.color).dot).frame(width: 10, height: 10) }) {
                                app.go(to: .label(label.id))
                            }
                        }
                    }
                    CalendarPanel()
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            footer
        }
        .onAppear {
            counts.observe(app.store) { try Store.unreadCounts($0) }
            labels.observe(app.store) { try Store.labels($0) }
        }
    }

    private var accountRow: some View {
        HStack(spacing: 0) {
            Avatar(name: app.account?.name ?? "?", size: 20, fill: Theme.accent)
                .padding(.leading, 18)
            Text(app.account?.name ?? "")
                .textStyle(.bodyMedium)
                .lineLimit(1)
                .padding(.leading, 6)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.iconSecondary)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            IconButton(systemName: "square.and.pencil", glyph: Theme.Metrics.iconMedium, help: "Compose") {
                app.commands.run("inbox.compose")
            }
            .padding(.trailing, 12)
        }
        .frame(height: 44)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .textStyle(.smallMedium)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 18)
            .frame(height: 30)
            .padding(.top, 14)
    }

    private func mailbox(_ box: Mailbox, tint: Color = Theme.iconSecondary) -> some View {
        SidebarItem(title: box.title, count: box.labelId.flatMap { box == .sent ? nil : counts.value[$0] } ?? 0,
                    isSelected: isCurrent(box), icon: { SlotIcon(systemName: box.symbol, tint: tint) }) {
            app.go(to: box)
        }
    }

    private func isCurrent(_ box: Mailbox) -> Bool {
        app.searchQuery == nil && app.mailbox == box
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Spacer()
            IconButton(systemName: "gearshape", help: "Settings") { app.settings = .inbox }
            IconButton(systemName: "questionmark.circle", help: "Shortcuts") { app.settings = .shortcuts }
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.sidebarFooterHeight)
        .overlay(alignment: .top) { Hairline() }
    }
}
