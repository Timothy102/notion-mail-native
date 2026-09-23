import MailCore
import SwiftUI

/// SPEC §4.3. Owner: inbox/triage feature. Publishes its row order to `app.visibleThreadIds`.
struct InboxList: View {
    @Environment(AppState.self) private var app
    @State private var threads = Live<[MailThread]>([])
    @State private var labels = Live<[MailLabel]>([])

    var body: some View {
        GeometryReader { geo in
            let layout = RowLayout(paneWidth: geo.size.width, windowWidth: geo.size.width + (app.isSidebarVisible ? Theme.Metrics.sidebarWidth : 0))
            VStack(spacing: 0) {
                PaneHeader(title: title, icon: icon)
                content(layout)
            }
        }
        .onChange(of: app.mailbox, initial: true) {
            let box = app.mailbox
            threads.observe(app.store) { try Store.threads($0, in: box) }
        }
        .onAppear { labels.observe(app.store) { try Store.labels($0) } }
        .onChange(of: threads.value.map(\.id), initial: true) { app.visibleThreadIds = threads.value.map(\.id) }
    }

    @ViewBuilder
    private func content(_ layout: RowLayout) -> some View {
        if let error = threads.error {
            EmptyState(title: "Couldn't load mail", message: error.localizedDescription, symbol: nil) {
                let box = app.mailbox
                threads.observe(app.store) { try Store.threads($0, in: box) }
            }
        } else if !threads.isLoaded {
            SkeletonRows(senderX: layout.senderX, subjectX: layout.subjectX).padding(.top, 8)
            Spacer()
        } else if threads.value.isEmpty {
            EmptyState(title: "No mail here!", message: "Rest easy, no mail carriers in sight.")
        } else {
            let byId = Dictionary(uniqueKeysWithValues: labels.value.map { ($0.id, $0) })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            if let title = group.title { GroupHeader(title: title) }
                            ForEach(Array(group.threads.enumerated()), id: \.element.id) { i, thread in
                                ThreadRow(thread: thread, labels: byId, layout: layout,
                                          isLast: i == group.threads.count - 1)
                                    .id(thread.id)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .onChange(of: app.focusedThreadId) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private struct Group: Identifiable {
        var title: String?
        var threads: [MailThread]
        var id: String { title ?? "today" }
    }

    private var groups: [Group] {
        var out: [Group] = []
        let now = Date.now
        for t in threads.value {
            let title = MailDate.group(t.lastDate, now: now)
            if out.last?.title == title, !out.isEmpty { out[out.count - 1].threads.append(t) } else { out.append(Group(title: title, threads: [t])) }
        }
        return out
    }

    private var title: String {
        if case .label(let id) = app.mailbox { return labels.value.first { $0.id == id }?.name ?? "Label" }
        return app.mailbox.title
    }

    private var icon: String {
        switch app.mailbox {
        case .inbox: "tray.fill"
        case .starred: "star"
        case .sent: "paperplane"
        case .drafts: "pencil.circle"
        case .all: "tray.2"
        case .spam: "exclamationmark.octagon"
        case .trash: "trash"
        case .label: "tag"
        }
    }
}

/// Pane header, 48 tall (§4.3). Shared by the inbox and search result lists.
struct PaneHeader<Accessory: View>: View {
    var title: String
    var icon: String
    var iconTint: Color = Theme.iconSecondary
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(iconTint).frame(width: 16, height: 16)
            Text(title).textStyle(.bodyMedium).lineLimit(1)
            accessory
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                IconButton(systemName: "line.3.horizontal.decrease", help: "Filter") {}
                IconButton(systemName: "slider.horizontal.3", help: "Display") {}
                IconButton(systemName: "arrow.clockwise", help: "Refresh") {}
            }
        }
        .padding(.leading, 74)
        .padding(.trailing, 18)
        .frame(height: Theme.Metrics.paneHeaderHeight)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String, icon: String, iconTint: Color = Theme.iconSecondary) {
        self.init(title: title, icon: icon, iconTint: iconTint) { EmptyView() }
    }
}

/// Column geometry of a row in pane coordinates (§4.3).
struct RowLayout {
    var paneWidth: CGFloat
    var windowWidth: CGFloat
    var senderX: CGFloat { Theme.Metrics.senderX }
    var senderWidth: CGFloat { Theme.Metrics.senderWidth(windowWidth: windowWidth) }
    var subjectX: CGFloat { senderX + senderWidth + Theme.Metrics.senderGap }
}

struct GroupHeader: View {
    let title: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .textStyle(.groupHeader)
                .frame(height: 16)
                .offset(x: 71, y: 20)
            Hairline()
                .padding(.leading, 55)
                .padding(.trailing, 38)
                .offset(y: Theme.Metrics.groupHairlineY)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.groupHeaderHeight, maxHeight: Theme.Metrics.groupHeaderHeight, alignment: .topLeading)
    }
}

/// One thread row (§5.2). Search results reuse it.
struct ThreadRow: View {
    let thread: MailThread
    let labels: [String: MailLabel]
    let layout: RowLayout
    var isLast = false
    /// Search results: words to mark, and the body excerpt around the hit that replaces the snippet.
    var terms: [String] = []
    var excerpt: String?
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        let selected = app.selectedThreadIds.contains(thread.id)
        let highlighted = hovering || app.focusedThreadId == thread.id || app.openThreadId == thread.id
        let chips = thread.userLabelIds.compactMap { labels[$0] }
        HStack(spacing: 0) {
            Checkbox(isOn: selected)
                .opacity(hovering || selected || !app.selectedThreadIds.isEmpty ? 1 : 0)
                .padding(.leading, Theme.Metrics.checkboxX - Theme.Metrics.rowInset)
            Circle().fill(Theme.accent)
                .frame(width: Theme.Metrics.unreadDotSize, height: Theme.Metrics.unreadDotSize)
                .opacity(thread.isUnread ? 1 : 0)
                .padding(.leading, Theme.Metrics.unreadDotCenterX - Theme.Metrics.unreadDotSize / 2 - Theme.Metrics.checkboxX - Theme.Metrics.checkboxSize)
            HStack(spacing: 0) {
                Text(thread.participants).lineLimit(1)
                if thread.messageCount > 1 {
                    Text(" \(thread.messageCount)").textStyle(.listSecondary).foregroundStyle(Theme.textTertiary).fixedSize()
                }
                if thread.hasDraft {
                    Text("Draft").textStyle(.list).foregroundStyle(Theme.textRed).padding(.leading, 6).fixedSize()
                }
            }
            .textStyle(thread.isUnread ? .listUnread : .list)
            .foregroundStyle(thread.isUnread ? Theme.textPrimary : Theme.textRead)
            .frame(width: layout.senderWidth, alignment: .leading)
            .padding(.leading, Theme.Metrics.senderX - (Theme.Metrics.unreadDotCenterX + Theme.Metrics.unreadDotSize / 2))
            let subject = MarkedText(text: thread.subject.isEmpty ? "(no subject)" : thread.subject, terms: terms)
                .textStyle(thread.isUnread ? .listUnread : .list)
                .foregroundStyle(thread.isUnread ? Theme.textPrimary : Theme.textRead)
                .lineLimit(1)
            SubjectSnippetLayout {
                subject
                MarkedText(text: excerpt ?? thread.snippet, terms: terms).textStyle(.listSecondary).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Theme.Metrics.senderGap)
            HStack(spacing: 4) {
                ForEach(chips.prefix(3)) { LabelChip(label: $0) }
                if chips.count > 3 { Text("+\(chips.count - 3)").textStyle(.listSecondary).foregroundStyle(Theme.textTertiary) }
            }
            .padding(.leading, 8)
            HStack(spacing: 6) {
                if thread.hasAttachments {
                    Image(systemName: "paperclip").font(.system(size: 12)).foregroundStyle(Theme.iconSecondary)
                }
                Text(MailDate.list(thread.lastDate)).textStyle(.listSecondary).foregroundStyle(Theme.textTertiary)
            }
            .frame(width: Theme.Metrics.dateColumnWidth, alignment: .trailing)
            .padding(.trailing, Theme.Metrics.dateTrailing - Theme.Metrics.rowInset)
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(selected ? (hovering ? Theme.rowSelectedHover : Theme.rowSelected) : highlighted ? Theme.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            if !isLast && !highlighted && !selected {
                Hairline()
                    .padding(.leading, Theme.Metrics.senderX - Theme.Metrics.rowInset)
                    .padding(.trailing, Theme.Metrics.dateTrailing - Theme.Metrics.rowInset)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, Theme.Metrics.rowInset)
        .onHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
        .onTapGesture { app.open(thread.id) }
    }
}

/// Subject at its natural width (truncating if needed), then the snippet in whatever is left;
/// the snippet is dropped rather than shown as a sliver of a few characters.
struct SubjectSnippetLayout: Layout {
    var spacing: CGFloat = 6
    var minSnippet: CGFloat = 48

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let subjectWidth = min(subviews[0].sizeThatFits(.unspecified).width, bounds.width)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: subjectWidth, height: bounds.height))
        let rest = bounds.width - subjectWidth - spacing
        let snippet = rest >= minSnippet ? rest : 0
        subviews[1].place(at: CGPoint(x: bounds.minX + subjectWidth + spacing, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: snippet, height: bounds.height))
    }
}
