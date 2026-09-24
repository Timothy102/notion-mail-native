import AppKit
import MailCore
import SwiftUI

/// SPEC §4.3. Owner: inbox/triage feature. Publishes its row order to `app.visibleThreadIds`.
struct InboxList: View {
    @Environment(AppState.self) private var app
    @State private var threads = Live<[MailThread]>([])
    @State private var extras = Live<[String: ThreadRowExtras]>([:])
    @State private var labels = Live<[MailLabel]>([])
    @State private var collapsedGroups: Set<String> = []
    @State private var unreadOnly = false
    @State private var mouseFocusId: String?
    @State private var headerHovered = false
    @AppStorage("list.groupByDate") private var groupByDate = true

    var body: some View {
        GeometryReader { geo in
            let layout = RowLayout(paneWidth: geo.size.width, windowWidth: geo.size.width + (app.isSidebarVisible ? Theme.Metrics.sidebarWidth : 0))
            let listHeight = geo.size.height - Theme.Metrics.paneHeaderHeight
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .bottom) {
                        if isLoading {
                            LinearProgressBar(fraction: app.syncStatus.backfillFraction).transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.5), value: isLoading)
                    .zIndex(1)
                content(layout, height: listHeight)
            }
        }
        .overlay(alignment: .top) {
            if app.isLabelPickerOpen, app.openThreadId == nil {
                LabelPickerLayer(alignment: .top).padding(.top, Theme.Metrics.paneHeaderHeight)
            }
        }
        .onChange(of: app.mailbox, initial: true) {
            let box = app.mailbox
            collapsedGroups = []
            threads.observe(app.store) { try Store.threads($0, in: box) }
            extras.observe(app.store) { try Store.rowExtras($0, threadIds: Store.threads($0, in: box).map(\.id)) }
        }
        .onAppear { labels.observe(app.store) { try Store.labels($0) } }
        .onChange(of: visibleIds, initial: true) { app.visibleThreadIds = visibleIds }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if app.selectedThreadIds.isEmpty {
            PaneHeader(title: title, icon: icon.name, iconTint: icon.tint, unreadOnly: $unreadOnly, groupByDate: $groupByDate) { EmptyView() }
                .overlay(alignment: .leading) {
                    if headerHovered, !visibleIds.isEmpty {
                        SelectAllBox(ids: visibleIds).padding(.leading, Theme.Metrics.checkboxX - 7)
                    }
                }
                .onLiveHover { headerHovered = $0 }
        } else {
            BulkHeader(ids: visibleIds)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func content(_ layout: RowLayout, height: CGFloat) -> some View {
        if let error = threads.error {
            EmptyState(title: "Couldn't load mail", message: error.localizedDescription, art: false) {
                let box = app.mailbox
                threads.observe(app.store) { try Store.threads($0, in: box) }
            }
        } else if !threads.isLoaded || (filtered.isEmpty && isLoading) {
            SkeletonRows(layout: layout, count: skeletonCount(height - Theme.Metrics.listTopInset))
                .padding(.top, Theme.Metrics.listTopInset)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
        } else if filtered.isEmpty {
            if unreadOnly, !threads.value.isEmpty {
                EmptyState(title: "No unread mail", message: "Everything in \(title) has been read.")
            } else {
                EmptyState(title: "No mail here!", message: "Rest easy, no mail carriers in sight.")
            }
        } else {
            list(layout, height: height)
        }
    }

    /// First sync (or a resync) is still filling the store, so the list isn't the whole story yet.
    private var isLoading: Bool { app.syncStatus.isBackfilling || app.isAwaitingFirstSync }

    private func skeletonCount(_ height: CGFloat) -> Int {
        max(0, Int((height / Theme.Metrics.rowHeight).rounded(.up)))
    }

    /// Height of the real rows and group headers, to know how many skeletons fill the rest of the pane.
    private func rowsHeight(_ groups: [Group]) -> CGFloat {
        groups.reduce(Theme.Metrics.listTopInset) { sum, group in
            sum + (group.title == nil ? 0 : Theme.Metrics.groupHeaderHeight)
                + (collapsedGroups.contains(group.id) ? 0 : CGFloat(group.threads.count) * Theme.Metrics.rowHeight)
        }
    }

    private func list(_ layout: RowLayout, height: CGFloat) -> some View {
        let byId = Dictionary(uniqueKeysWithValues: labels.value.map { ($0.id, $0) })
        let groups = self.groups
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        let collapsed = collapsedGroups.contains(group.id)
                        if let title = group.title {
                            GroupHeader(title: title, isCollapsed: collapsed) {
                                withAnimation(Theme.Motion.standard) {
                                    if collapsed { collapsedGroups.remove(group.id) } else { collapsedGroups.insert(group.id) }
                                }
                            }
                        }
                        if !collapsed {
                            let ids = group.threads.map(\.id)
                            ForEach(Array(group.threads.enumerated()), id: \.element.id) { i, thread in
                                let filled = isFilled(thread.id)
                                ThreadRow(thread: thread, extras: extras.value[thread.id], labels: byId, layout: layout,
                                          isLast: i == ids.count - 1,
                                          mergeTop: filled && i > 0 && isFilled(ids[i - 1]),
                                          mergeBottom: filled && i < ids.count - 1 && isFilled(ids[i + 1]),
                                          nextFilled: i < ids.count - 1 && isFilled(ids[i + 1])) { hovering in
                                    if hovering, app.focusedThreadId != thread.id {
                                        mouseFocusId = thread.id
                                        app.focusedThreadId = thread.id
                                    }
                                }
                                .id(thread.id)
                                .transition(.opacity)
                            }
                        }
                    }
                    if isLoading {
                        SkeletonRows(layout: layout, count: max(3, skeletonCount(height - rowsHeight(groups))))
                            .transition(.opacity)
                    }
                }
                .padding(.top, Theme.Metrics.listTopInset)
                .padding(.bottom, 24)
                .animation(Theme.Motion.standard, value: visibleIds)
                .animation(.easeOut(duration: 0.4), value: isLoading)
            }
            .onChange(of: app.focusedThreadId) { _, id in
                guard let id, id != mouseFocusId else { return }
                mouseFocusId = nil
                proxy.scrollTo(id)
            }
        }
    }

    private func isFilled(_ id: String) -> Bool {
        app.selectedThreadIds.contains(id) || app.focusedThreadId == id || app.openThreadId == id
    }

    // MARK: Data

    private struct Group: Identifiable {
        var title: String?
        var threads: [MailThread]
        var id: String { title ?? "today" }
    }

    private var filtered: [MailThread] {
        unreadOnly ? threads.value.filter(\.isUnread) : threads.value
    }

    private var groups: [Group] {
        guard groupByDate else { return [Group(title: nil, threads: filtered)] }
        var out: [Group] = []
        let now = Date.now
        for t in filtered {
            let title = MailDate.group(t.lastDate, now: now)
            if let last = out.last, last.title == title { out[out.count - 1].threads.append(t) } else { out.append(Group(title: title, threads: [t])) }
        }
        return out
    }

    private var visibleIds: [String] {
        groups.filter { !collapsedGroups.contains($0.id) }.flatMap { $0.threads.map(\.id) }
    }

    private var title: String {
        if case .label(let id) = app.mailbox { return labels.value.first { $0.id == id }?.name ?? "Label" }
        return app.mailbox.title
    }

    private var icon: (name: String, tint: Color) {
        if case .label(let id) = app.mailbox {
            return ("tag", LabelColor(named: labels.value.first { $0.id == id }?.color).dot)
        }
        return (app.mailbox.symbol, app.mailbox == .inbox ? Theme.inboxRed : Theme.iconSecondary)
    }
}

extension SyncStatus {
    /// Backfill progress 0...1, or nil while the total is still unknown.
    var backfillFraction: Double? {
        guard case .backfilling(let fetched, let total) = self, total > 0 else { return nil }
        return Double(fetched) / Double(total)
    }
}

extension Mailbox {
    var symbol: String {
        switch self {
        case .inbox: InboxTray.symbol
        case .starred: "star"
        case .sent: "paperplane"
        case .drafts: "pencil.and.outline"
        case .all: "tray.2"
        case .spam: "exclamationmark.square"
        case .trash: "trash"
        case .label: "tag"
        }
    }
}

// MARK: - Header

/// Pane header, 48 tall (§4.3). Shared by the inbox and search result lists. Filter and Display
/// only appear when their bindings are given.
struct PaneHeader<Accessory: View>: View {
    var title: String
    var icon: String
    var iconTint: Color = Theme.iconSecondary
    var unreadOnly: Binding<Bool>?
    var groupByDate: Binding<Bool>?
    /// Makes the icon and title a button (search reopens the palette with its query).
    var onTitle: (() -> Void)?
    @ViewBuilder var accessory: Accessory
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 8) {
            if let onTitle {
                Button(action: onTitle) {
                    titleLabel.padding(.horizontal, 6).frame(height: Theme.Metrics.iconButton).hoverFill().contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .help("Edit search")
            } else {
                titleLabel
            }
            accessory
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                if let unreadOnly {
                    IconButton(systemName: "line.3.horizontal.decrease", tint: unreadOnly.wrappedValue ? Theme.accent : Theme.iconSecondary,
                               help: unreadOnly.wrappedValue ? "Show all mail" : "Show unread only") {
                        unreadOnly.wrappedValue.toggle()
                    }
                }
                if let groupByDate {
                    MenuButton(systemName: "slider.horizontal.3", help: "Display") {
                        Toggle("Group by date", isOn: groupByDate)
                    }
                }
                IconButton(systemName: "arrow.clockwise", help: "Refresh") {
                    if app.isDemo { app.show(Toast("Demo mode: nothing to sync")) } else { app.syncNow() }
                }
                .disabled(app.syncStatus == .syncing || app.syncStatus.isBackfilling)
            }
        }
        .padding(.leading, 74)
        .padding(.trailing, 18)
        .frame(height: Theme.Metrics.paneHeaderHeight)
        .contentShape(Rectangle())
    }

    private var titleLabel: some View {
        HStack(spacing: 8) {
            SlotIcon(systemName: icon, tint: iconTint).frame(width: 16, height: 16)
            Text(title).textStyle(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
        }
    }
}

/// Header checkbox that selects every visible row; shown while the header is hovered.
private struct SelectAllBox: View {
    let ids: [String]
    @Environment(AppState.self) private var app

    var body: some View {
        Button { app.selectedThreadIds = Set(ids) } label: {
            Checkbox(isOn: false)
                .frame(width: 28, height: Theme.Metrics.paneHeaderHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Select all")
    }
}

/// Replaces the title while rows are selected (§4.3 bulk mode).
private struct BulkHeader: View {
    let ids: [String]
    @Environment(AppState.self) private var app

    var body: some View {
        let selected = app.selectedThreadIds
        let all = !ids.isEmpty && ids.allSatisfy(selected.contains)
        HStack(spacing: 0) {
            Button { app.selectedThreadIds = all ? [] : Set(ids) } label: {
                Checkbox(isOn: true)
                    .overlay {
                        if !all {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Theme.accent)
                                .overlay(Capsule().fill(Theme.textContrast).frame(width: 8, height: 1.5))
                        }
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(all ? "Deselect all" : "Select all")
            MenuButton(systemName: "chevron.down", glyph: 12, help: "Select") {
                Button("All") { app.selectedThreadIds = Set(ids) }
                Button("None") { app.selectedThreadIds = [] }
                Button("Read") { select(read: true) }
                Button("Unread") { select(read: false) }
            }
            Hairline(vertical: true).frame(height: 16).padding(.horizontal, 8)
            HStack(spacing: 2) {
                IconButton(systemName: "envelope.open", help: "Mark as read  ⇧I") { app.commands.run("thread.markRead") }
                IconButton(systemName: "app.badge", help: "Mark as unread  ⇧U") { app.commands.run("thread.markUnread") }
                IconButton(systemName: "archivebox", help: "Archive  E") { app.commands.run("thread.archive") }
                RemindMenu(ids: app.targetThreadIds)
                IconButton(systemName: "trash", help: "Trash  #") { app.commands.run("thread.trash") }
                IconButton(systemName: "exclamationmark.octagon", help: "Report spam  !") { app.commands.run("thread.spam") }
                IconButton(systemName: "tag", help: "Label  L") { app.commands.run("thread.label") }
            }
            Spacer(minLength: 12)
            Text("\(selected.count) selected").textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
        }
        .padding(.leading, Theme.Metrics.checkboxX - 7)
        .padding(.trailing, 24)
        .frame(height: Theme.Metrics.paneHeaderHeight)
    }

    private func select(read: Bool) {
        let ids = self.ids
        let unread = (try? app.store.db.read { try MailThread.filter(keys: ids).fetchAll($0) }) ?? []
        app.selectedThreadIds = Set(unread.filter { $0.isUnread != read }.map(\.id))
    }
}

/// Ghost icon button that opens a native menu.
struct MenuButton<Content: View>: View {
    let systemName: String
    var glyph: CGFloat = Theme.Metrics.iconSmall
    var help: String
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Menu { content } label: {
            Image(systemName: systemName)
                .font(.glyph(glyph))
                .foregroundStyle(Theme.iconSecondary)
                .frame(width: Theme.Metrics.iconButton, height: Theme.Metrics.iconButton)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
        .help(help)
    }
}

// MARK: - Rows

/// Column geometry of a row in pane coordinates (§4.3).
struct RowLayout {
    var paneWidth: CGFloat
    var windowWidth: CGFloat
    var senderX: CGFloat { Theme.Metrics.senderX }
    var senderWidth: CGFloat { Theme.Metrics.senderWidth(windowWidth: windowWidth) }
    var subjectX: CGFloat { senderX + senderWidth + Theme.Metrics.senderGap }
}

/// Date-group header (§5.3): label at x 71, hairline at `groupHairlineY`, "Collapse" on hover.
struct GroupHeader: View {
    let title: String
    var isCollapsed = false
    var onToggle: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(title).textStyle(.groupHeader).foregroundStyle(Theme.textPrimary)
                if let onToggle, hovering || isCollapsed {
                    Button(isCollapsed ? "Expand" : "Collapse", action: onToggle)
                        .buttonStyle(.plain)
                        .textStyle(.groupHeader)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 16)
            .offset(x: 71, y: Theme.Metrics.groupLabelY)
            Hairline()
                .padding(.leading, 55)
                .padding(.trailing, 38)
                .offset(y: Theme.Metrics.groupHairlineY)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.groupHeaderHeight, maxHeight: Theme.Metrics.groupHeaderHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onLiveHover { hovering = $0 }
    }
}

/// One thread row (§5.2). Search results reuse it. The list passes neighbour state so filled
/// runs merge into one shape and separators hide next to fills.
struct ThreadRow: View {
    let thread: MailThread
    var extras: ThreadRowExtras?
    let labels: [String: MailLabel]
    let layout: RowLayout
    var isLast = false
    var mergeTop = false
    var mergeBottom = false
    var nextFilled = false
    var terms: [String] = []
    var excerpt: String?
    var onHover: ((Bool) -> Void)?
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        let selected = app.selectedThreadIds.contains(thread.id)
        let filled = selected || app.focusedThreadId == thread.id || app.openThreadId == thread.id
            || (isHovering && app.focusedThreadId == nil)
        VStack(alignment: .leading, spacing: 0) {
            mainLine(selected: selected)
            if extras?.code != nil || !(extras?.files.isEmpty ?? true) {
                HStack(spacing: 6) {
                    if let code = extras?.code { CodeChip(code: code) }
                    if let files = extras?.files, !files.isEmpty { AttachmentChips(files: files) }
                }
                .padding(.leading, layout.subjectX - Theme.Metrics.rowInset)
                .padding(.top, -3)
                .padding(.bottom, 10)
            }
        }
        .background(fill(selected: selected, filled: filled), in: shape)
        .overlay(alignment: .bottom) {
            if !isLast && !filled && !nextFilled {
                Hairline()
                    .padding(.leading, Theme.Metrics.senderX - Theme.Metrics.rowInset)
                    .padding(.trailing, Theme.Metrics.dateTrailing - Theme.Metrics.rowInset)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                HoverActions(thread: thread).padding(.trailing, 17 - Theme.Metrics.rowInset).frame(height: Theme.Metrics.rowHeight)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tap() }
        .padding(.horizontal, Theme.Metrics.rowInset)
        .onLiveHover { h in
            withAnimation(h ? Theme.Motion.hover : nil) { hovering = h }
            onHover?(h)
        }
    }

    private func mainLine(selected: Bool) -> some View {
        HStack(spacing: 0) {
            Button { app.toggleSelection(thread.id) } label: {
                Checkbox(isOn: selected)
                    .frame(width: 30, height: Theme.Metrics.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || selected || !app.selectedThreadIds.isEmpty ? 1 : 0)
            .padding(.leading, Theme.Metrics.checkboxX - Theme.Metrics.rowInset - 8)
            Circle().fill(Theme.accent)
                .frame(width: Theme.Metrics.unreadDotSize, height: Theme.Metrics.unreadDotSize)
                .opacity(thread.isUnread ? 1 : 0)
                .animation(Theme.Motion.fast, value: thread.isUnread)
                .padding(.leading, Theme.Metrics.unreadDotCenterX - Theme.Metrics.unreadDotSize / 2 - Theme.Metrics.checkboxX - Theme.Metrics.checkboxSize - 8)
            sender
                .frame(width: layout.senderWidth, alignment: .leading)
                .padding(.leading, Theme.Metrics.senderX - (Theme.Metrics.unreadDotCenterX + Theme.Metrics.unreadDotSize / 2))
            SubjectSnippetLayout {
                MarkedText(text: thread.subject.isEmpty ? "(no subject)" : thread.subject, terms: terms)
                    .textStyle(thread.isUnread ? .listUnread : .list)
                    .foregroundStyle(thread.isUnread ? Theme.textPrimary : Theme.textRead)
                    .lineLimit(1)
                    .mask(Rectangle().padding(.vertical, -6))
                MarkedText(text: excerpt ?? thread.snippet.listPreview, terms: terms).textStyle(.listSecondary).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    .mask(Rectangle().padding(.vertical, -6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Theme.Metrics.senderGap)
            chips
            ZStack(alignment: .trailing) {
                Text(MailDate.list(thread.lastDate))
                    .textStyle(.listSecondary)
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(isHovering ? 0 : 1)
            }
            .frame(width: Theme.Metrics.dateColumnWidth, alignment: .trailing)
            .padding(.trailing, Theme.Metrics.dateTrailing - Theme.Metrics.rowInset)
        }
        .frame(height: Theme.Metrics.rowHeight)
    }

    private var isHovering: Bool { hovering || Self.snapshotHoverId == thread.id }

    /// Set by the snapshot harness to render one row in its hover state.
    @MainActor static var snapshotHoverId: String?

    private var sender: some View {
        HStack(spacing: 0) {
            Text(thread.participants.isEmpty ? "(no sender)" : thread.participants).lineLimit(1)
            if thread.hasDraft {
                Text("Draft").textStyle(.list).foregroundStyle(Theme.textRed).padding(.leading, 6).fixedSize()
            }
            if thread.messageCount > 1 {
                Text(" \(thread.messageCount)").textStyle(.listSecondary).foregroundStyle(Theme.textTertiary).fixedSize()
            }
        }
        .textStyle(thread.isUnread ? .listUnread : .list)
        .foregroundStyle(thread.isUnread ? Theme.textPrimary : Theme.textRead)
    }

    @ViewBuilder
    private var chips: some View {
        let chips = thread.userLabelIds.compactMap { labels[$0] }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !chips.isEmpty || thread.isStarred {
            HStack(spacing: 4) {
                ForEach(chips.prefix(3)) { ListChip(label: $0) }
                if chips.count > 3 {
                    Text("+\(chips.count - 3)").textStyle(.listSecondary).foregroundStyle(Theme.textTertiary).fixedSize()
                }
                if thread.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textOrange)
                        .frame(width: Theme.Metrics.iconMini, height: Theme.Metrics.iconMini)
                        .padding(.leading, 2)
                        .opacity(isHovering ? 0 : 1)
                        .accessibilityLabel("Starred")
                }
            }
            .padding(.leading, 12)
        }
    }

    private var shape: UnevenRoundedRectangle {
        let r = Theme.Metrics.rowRadius
        return UnevenRoundedRectangle(topLeadingRadius: mergeTop ? 0 : r, bottomLeadingRadius: mergeBottom ? 0 : r,
                                      bottomTrailingRadius: mergeBottom ? 0 : r, topTrailingRadius: mergeTop ? 0 : r, style: .continuous)
    }

    private func fill(selected: Bool, filled: Bool) -> Color {
        if selected { return isHovering ? Theme.rowSelectedHover : Theme.rowSelected }
        return filled ? Theme.rowHover : .clear
    }

    private func tap() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            app.toggleSelection(thread.id)
        } else if flags.contains(.shift), let anchor = app.focusedThreadId ?? app.openThreadId,
                  let a = app.visibleThreadIds.firstIndex(of: anchor), let b = app.visibleThreadIds.firstIndex(of: thread.id) {
            app.selectedThreadIds.formUnion(app.visibleThreadIds[min(a, b)...max(a, b)])
        } else {
            app.open(thread.id)
        }
    }
}

/// List chip (§5.4): hugs its text up to 122 wide, so a row's chips pack against the date column.
private struct ListChip: View {
    let label: MailLabel

    var body: some View {
        let color = LabelColor(named: label.color)
        CappedWidth(max: Theme.Metrics.chipMaxWidth) {
            Text(label.name)
                .textStyle(.list)
                .lineLimit(1)
                .foregroundStyle(color.text)
                .padding(.horizontal, 6)
                .frame(height: Theme.Metrics.chipHeightList)
                .background(color.fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.chipRadius, style: .continuous))
        }
    }
}

/// Ideal width, never more than `max`.
private struct CappedWidth: Layout {
    var max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(child.sizeThatFits(.unspecified).width, max)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Clock menu: archive now, back in the inbox (unread) at the chosen time.
struct RemindMenu: View {
    let ids: [String]
    var glyph: CGFloat = Theme.Metrics.iconSmall
    @Environment(AppState.self) private var app

    var body: some View {
        MenuButton(systemName: "clock", glyph: glyph, help: "Remind me") {
            ForEach(MailDate.reminderOptions(), id: \.title) { option in
                Button(option.title) { app.removing(ids) { app.actions.remind($0, at: option.date) } }
            }
        }
        .disabled(ids.isEmpty)
    }
}

/// Star, archive, trash, read/unread and remind over the date column while a row is hovered (§5.2).
private struct HoverActions: View {
    let thread: MailThread
    @Environment(AppState.self) private var app

    var body: some View {
        let ids = [thread.id]
        HStack(spacing: 2) {
            IconButton(systemName: thread.isStarred ? "star.fill" : "star", glyph: Theme.Metrics.iconMedium,
                       tint: thread.isStarred ? Theme.textOrange : Theme.iconSecondary, help: thread.isStarred ? "Unstar  S" : "Star  S") {
                app.actions.setStarred(ids, !thread.isStarred)
            }
            IconButton(systemName: "archivebox", glyph: Theme.Metrics.iconMedium, help: "Archive  E") {
                app.removing(ids, app.actions.archive)
            }
            .disabled(!thread.labelIds.contains("INBOX"))
            IconButton(systemName: "trash", glyph: Theme.Metrics.iconMedium, help: "Trash  #") {
                app.removing(ids, app.actions.trash)
            }
            IconButton(systemName: thread.isUnread ? "envelope.open" : "app.badge", glyph: Theme.Metrics.iconMedium,
                       help: thread.isUnread ? "Mark as read  ⇧I" : "Mark as unread  ⇧U") {
                app.actions.setRead(ids, thread.isUnread)
            }
            RemindMenu(ids: ids, glyph: Theme.Metrics.iconMedium)
        }
        .padding(.horizontal, 1)
        .frame(height: Theme.Metrics.hoverPillHeight)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous))
        .elevation(.l1, radius: Theme.Metrics.rowRadius)
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

// MARK: - Label picker (`l`)

/// Full-pane click catcher plus the picker menu; clicking outside closes it.
struct LabelPickerLayer: View {
    var alignment: Alignment
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear.contentShape(Rectangle()).onTapGesture { app.isLabelPickerOpen = false }
            LabelPicker().padding(.horizontal, 16)
        }
    }
}

/// Toggle user labels on the target threads (§5.10 menu styling). Type to filter, ↑/↓, ↵ toggles.
struct LabelPicker: View {
    @Environment(AppState.self) private var app
    @State private var labels = Live<[MailLabel]>([])
    @State private var applied = Live<[String: Int]>([:])
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let targets = app.targetThreadIds
        let matches = labels.value.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .placeholder("Label as…", showing: query.isEmpty)
                .focused($focused)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .onSubmit { if matches.indices.contains(index) { toggle(matches[index], targets) } }
                .onKeyPress(.downArrow) { index = min(index + 1, max(matches.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onChange(of: query) { index = 0 }
            Hairline().padding(.bottom, 4)
            if matches.isEmpty {
                Text(labels.value.isEmpty ? "No labels yet" : "No matching labels")
                    .textStyle(.body).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12).frame(height: 28)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { i, label in
                        let count = applied.value[label.id] ?? 0
                        Button { toggle(label, targets) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(LabelColor(named: label.color).dot).frame(width: 10, height: 10).frame(width: 16)
                                Text(label.name).textStyle(.body).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer(minLength: 8)
                                Image(systemName: count == targets.count ? "checkmark" : "minus")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.iconPrimary)
                                    .opacity(count == 0 ? 0 : 1)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: Theme.Metrics.menuItemHeight)
                            .background(i == index ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onLiveHover { if $0 { index = i } }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
        .frame(width: Theme.Metrics.menuWidth)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .elevation(.l3, radius: Theme.Metrics.radiusMenu)
        .onAppear {
            focused = true
            labels.observe(app.store) { try Store.labels($0) }
            let ids = targets
            applied.observe(app.store) { db in
                var counts: [String: Int] = [:]
                for t in try MailThread.filter(keys: ids).fetchAll(db) { for l in t.userLabelIds { counts[l, default: 0] += 1 } }
                return counts
            }
        }
    }

    private func toggle(_ label: MailLabel, _ targets: [String]) {
        guard !targets.isEmpty else { return }
        if applied.value[label.id] == targets.count {
            app.actions.setLabels(targets, remove: [label.id])
        } else {
            app.actions.setLabels(targets, add: [label.id])
        }
    }
}

extension LabelColor {
    /// Saturated dot for sidebar items and menus (Notion's colored-text palette).
    var dot: Color {
        switch self {
        case .lightGray: Color(0xACABA9, dark: 0x7F7F7F)
        case .gray: Color(0x91918E, dark: 0x9B9B9B)
        case .brown: Color(0x9F6B53, dark: 0xBA856F)
        case .orange: Color(0xD9730D, dark: 0xC77D48)
        case .yellow: Color(0xCB912F, dark: 0xCA984D)
        case .green: Color(0x448361, dark: 0x529E72)
        case .blue: Color(0x337EA9, dark: 0x379AD3)
        case .purple: Color(0x9065B0, dark: 0x9D68D3)
        case .pink: Color(0xC14C8A, dark: 0xD15796)
        case .red: Color(0xD44C47, dark: 0xDF5452)
        }
    }
}
