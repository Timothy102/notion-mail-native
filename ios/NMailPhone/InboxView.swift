import MailCore
import SwiftUI

/// The mailbox list (SPEC §4.3 adapted to iPhone): day groups, swipe actions, pull to refresh, infinite scroll over
/// the local store, and search results in place of the list while searching.
struct InboxView: View {
    @Environment(AppState.self) private var app
    @Binding var sheet: MainSheet?
    let open: (MailThread) -> Void
    @State private var threads = Live<[MailThread]>([])
    @State private var extras = Live<[String: ThreadRowExtras]>([:])
    @State private var labels = Live<[MailLabel]>([])
    @State private var counts = Live<[String: Int]>([:])
    @State private var limit = Self.page
    @State private var query = Launch.screen == "search" ? Launch.query : ""
    @State private var isSearching = Launch.screen == "search"
    static let page = 60

    var body: some View {
        content
            .background(Theme.page)
            .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search mail")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { mailboxButton }
                ToolbarItem(placement: .topBarTrailing) { accountButton }
            }
            .toolbarBackground(Theme.page, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) {
                if !isSearching { ComposeButton { app.compose = ComposeRequest(.new(to: [])) } }
            }
            .onChange(of: app.mailbox, initial: true) {
                limit = Self.page
                observeThreads()
            }
            .onChange(of: limit) { observeThreads() }
            .onAppear {
                labels.observe(app.store) { try Store.labels($0) }
                counts.observe(app.store) { try Store.unreadCounts($0) }
            }
    }

    @ViewBuilder
    private var content: some View {
        let byId = Dictionary(labels.value.map { ($0.id, $0) }) { a, _ in a }
        if isSearching, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResults(query: query, labels: byId, open: open)
        } else if let error = threads.error {
            EmptyState(title: "Couldn't load mail", message: error.localizedDescription, art: false) { observeThreads() }
        } else if !threads.isLoaded || (threads.value.isEmpty && isLoading) {
            ScrollView { SkeletonRows(count: 9) }.scrollDisabled(true)
        } else if threads.value.isEmpty {
            ScrollView {
                EmptyState(title: "No mail here!", message: "Rest easy, no mail carriers in sight.")
            }
            .refreshable { await app.refresh() }
        } else {
            list(byId)
        }
    }

    private func list(_ byId: [String: MailLabel]) -> some View {
        List {
            syncNotice
            ForEach(groups, id: \.id) { group in
                Section {
                    ForEach(group.threads) { thread in
                        ThreadRow(thread: thread, extras: extras.value[thread.id], labels: byId,
                                  revealed: Launch.screen == "swipe" && thread.id == threads.value.first?.id) { open(thread) }
                        .threadRowStyle()
                        .threadActions(thread, app: app)
                        .onAppear { if thread.id == threads.value.last?.id, threads.value.count >= limit { limit += Self.page } }
                    }
                } header: {
                    if let title = group.title { GroupHeader(title: title) }
                }
            }
            if threads.value.count >= limit {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Theme.page)
            }
            Color.clear.frame(height: 72).listRowSeparator(.hidden).listRowBackground(Theme.page)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await app.refresh() }
    }

    @ViewBuilder
    private var syncNotice: some View {
        let text: String? = switch app.syncStatus {
        case .offline: "You're offline. Changes will sync when you're back online."
        case .failed(let message): "Couldn't sync: \(message)"
        default: nil
        }
        if let text {
            Label(text, systemImage: app.syncStatus == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.page)
        }
    }

    private var mailboxButton: some View {
        Button { sheet = .mailboxes } label: {
            HStack(spacing: 8) {
                icon
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let unread = app.mailbox.labelId.flatMap({ counts.value[$0] }), unread > 0, app.mailbox != .sent {
                    Text("\(unread)").font(.title3).foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.iconSecondary)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), choose mailbox")
    }

    @ViewBuilder
    private var icon: some View {
        if case .label(let id) = app.mailbox {
            Circle().fill(LabelColor(named: labels.value.first { $0.id == id }?.color).dot).frame(width: 12, height: 12)
        } else {
            Image(systemName: app.mailbox == .inbox ? "tray.fill" : app.mailbox.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(app.mailbox == .inbox ? Theme.inboxRed : Theme.iconSecondary)
        }
    }

    private var accountButton: some View {
        Button { sheet = .accounts } label: {
            Avatar(name: app.account?.name ?? "?", size: 32, fill: Theme.accent, image: app.avatarImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Accounts")
    }

    private var title: String {
        if case .label(let id) = app.mailbox { return labels.value.first { $0.id == id }?.name ?? "Label" }
        return app.mailbox.title
    }

    private var isLoading: Bool { app.syncStatus.isBackfilling || app.isAwaitingFirstSync }

    private func observeThreads() {
        let box = app.mailbox, limit = limit
        threads.observe(app.store) { try Store.threads($0, in: box, limit: limit) }
        extras.observe(app.store) { try Store.rowExtras($0, threadIds: Store.threads($0, in: box, limit: limit).map(\.id)) }
    }

    private struct DayGroup {
        var title: String?
        var threads: [MailThread]
        var id: String { title ?? "today" }
    }

    /// Consecutive threads sharing a `MailDate.group` title, like the Mac list; today has no header.
    private var groups: [DayGroup] {
        var out: [DayGroup] = []
        let now = Date.now
        for t in threads.value {
            let title = MailDate.group(t.lastDate, now: now)
            if out.last?.title == title, !out.isEmpty { out[out.count - 1].threads.append(t) } else { out.append(DayGroup(title: title, threads: [t])) }
        }
        return out
    }
}

struct GroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.page)
            .listRowInsets(EdgeInsets())
    }
}

/// Floating compose button, bottom-right above the home indicator.
struct ComposeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.page)
                .frame(width: 58, height: 58)
                .background(Theme.textPrimary, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 12)
        .accessibilityLabel("Compose")
    }
}

/// Avatar, sender and time, subject, snippet with a label chip and the star, then attachment / code chips:
/// Gmail's density and affordances in Notion's palette. Rows are 76 pt with three lines.
struct ThreadRow: View {
    let thread: MailThread
    var extras: ThreadRowExtras?
    let labels: [String: MailLabel]
    var terms: [String] = []
    var excerpt: String?
    /// Demo screenshot of a half-swiped row.
    var revealed = false
    let open: () -> Void
    @Environment(AppState.self) private var app

    static let avatarSize: CGFloat = 40
    static let textInset: CGFloat = avatarSize + 12

    var body: some View {
        if revealed {
            content.offset(x: -222).overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    SwipeTile(title: "Archive", icon: "archivebox", color: Theme.swipeArchive)
                    SwipeTile(title: "Trash", icon: "trash", color: Theme.swipeTrash)
                    SwipeTile(title: "Remind", icon: "clock", color: Theme.swipeRemind)
                }
                .padding(.trailing, -16)
            }
        } else {
            content
        }
    }

    private var content: some View {
        let unread = thread.isUnread
        let chips = thread.userLabelIds.compactMap { labels[$0] }
        let files = extras?.files ?? []
        let code = extras?.code
        return HStack(alignment: .top, spacing: 12) {
            SenderAvatar(address: sender, size: Self.avatarSize)
                .overlay(alignment: .leading) {
                    if unread {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: -12).accessibilityLabel("Unread")
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(thread.participants.isEmpty ? "(no sender)" : thread.participants)
                        .font(.body.weight(unread ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if thread.messageCount > 1 {
                        Text("\(thread.messageCount)").font(.footnote).foregroundStyle(Theme.textTertiary)
                    }
                    if thread.hasDraft {
                        Text("Draft").font(.footnote).foregroundStyle(Theme.textRed)
                    }
                    Spacer(minLength: 8)
                    Text(MailDate.list(thread.lastDate))
                        .font(.footnote.weight(unread ? .semibold : .regular))
                        .foregroundStyle(unread ? Theme.textPrimary : Theme.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                marked(thread.subject.isEmpty ? "(no subject)" : thread.subject)
                    .font(.subheadline.weight(unread ? .semibold : .regular))
                    .foregroundStyle(unread ? Theme.textPrimary : Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 8) {
                    marked(excerpt ?? thread.snippet.listPreview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(excerpt == nil ? 1 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let first = chips.first {
                        HStack(spacing: 3) {
                            LabelChip(label: first).frame(maxWidth: 96, alignment: .trailing)
                            if chips.count > 1 {
                                Text("+\(chips.count - 1)").font(.footnote).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    star
                }
                if !files.isEmpty || code != nil {
                    HStack(spacing: 6) {
                        if let code { CodeChip(code: code) }
                        if !files.isEmpty { AttachmentChips(files: files) }
                    }
                    .padding(.top, 7)
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .overlay(alignment: .bottom) { Hairline(color: Theme.border).padding(.leading, Self.textInset) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", open)
    }

    private var star: some View {
        Button { app.actions.setStarred([thread.id], !thread.isStarred) } label: {
            Image(systemName: thread.isStarred ? "star.fill" : "star")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(thread.isStarred ? Theme.swipeStar : Theme.iconSecondary.opacity(0.7))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(thread.isStarred ? "Unstar" : "Star")
    }

    /// The newest sender, or a stand-in keyed by the name until the extras load.
    private var sender: EmailAddress {
        extras?.sender ?? EmailAddress(name: firstSender, email: firstSender.lowercased())
    }

    private var firstSender: String {
        String(thread.participants.split(separator: ",").first ?? "?").trimmingCharacters(in: .whitespaces)
    }

    /// Search terms in accent semibold, as in the Mac results list (§4.7).
    private func marked(_ text: String) -> Text {
        let ranges = SearchText.marks(in: text, terms: terms)
        guard !ranges.isEmpty else { return Text(verbatim: text) }
        var out = AttributedString()
        var cursor = text.startIndex
        for r in ranges {
            out += AttributedString(String(text[cursor..<r.lowerBound]))
            var hit = AttributedString(String(text[r]))
            hit.foregroundColor = Theme.accent
            hit.inlinePresentationIntent = .stronglyEmphasized
            out += hit
            cursor = r.upperBound
        }
        out += AttributedString(String(text[cursor...]))
        return Text(out)
    }
}

private struct SwipeTile: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.body.weight(.medium))
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .frame(width: 74)
        .frame(maxHeight: .infinity)
        .background(color)
    }
}

extension View {
    /// The row draws its own hairline (one device pixel, from the text column), so List's separators are off.
    func threadRowStyle() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Theme.page)
            .listRowSeparator(.hidden)
    }

    /// Swipes (read / star from the leading edge; archive, trash, remind from the trailing edge) and a long-press menu.
    func threadActions(_ thread: MailThread, app: AppState) -> some View {
        modifier(ThreadActions(thread: thread, app: app))
    }
}

private struct ThreadActions: ViewModifier {
    let thread: MailThread
    let app: AppState
    @State private var reminding = false

    private var ids: [String] { [thread.id] }
    private var inInbox: Bool { thread.labelIds.contains("INBOX") }
    private var inTrashOrSpam: Bool { thread.labelIds.contains("TRASH") || thread.labelIds.contains("SPAM") }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { app.actions.setRead(ids, thread.isUnread) } label: {
                    Label(thread.isUnread ? "Read" : "Unread", systemImage: thread.isUnread ? "envelope.open" : "envelope.badge")
                }
                .tint(Theme.swipeRead)
                Button { app.actions.setStarred(ids, !thread.isStarred) } label: {
                    Label(thread.isStarred ? "Unstar" : "Star", systemImage: thread.isStarred ? "star.slash" : "star")
                }
                .tint(Theme.swipeStar)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if inTrashOrSpam {
                    Button { app.actions.moveToInbox(ids) } label: { Label("Inbox", systemImage: "tray.and.arrow.down") }.tint(Theme.swipeArchive)
                } else if inInbox {
                    Button { app.actions.archive(ids) } label: { Label("Archive", systemImage: "archivebox") }.tint(Theme.swipeArchive)
                }
                if !thread.labelIds.contains("TRASH") {
                    Button { app.actions.trash(ids) } label: { Label("Trash", systemImage: "trash") }.tint(Theme.swipeTrash)
                }
                Button { reminding = true } label: { Label("Remind", systemImage: "clock") }.tint(Theme.swipeRemind)
            }
            .contextMenu {
                if let target = app.replyTarget(threadId: thread.id) {
                    Button { app.compose = ComposeRequest(.reply(messageId: target.id, all: false)) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    Button { app.compose = ComposeRequest(.reply(messageId: target.id, all: true)) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                    Button { app.compose = ComposeRequest(.forward(messageId: target.id)) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                    Divider()
                }
                Button { app.actions.setRead(ids, thread.isUnread) } label: {
                    Label(thread.isUnread ? "Mark as Read" : "Mark as Unread", systemImage: thread.isUnread ? "envelope.open" : "envelope.badge")
                }
                Button { app.actions.setStarred(ids, !thread.isStarred) } label: {
                    Label(thread.isStarred ? "Unstar" : "Star", systemImage: thread.isStarred ? "star.slash" : "star")
                }
                if inInbox { Button { app.actions.archive(ids) } label: { Label("Archive", systemImage: "archivebox") } }
                ReminderMenu(ids: ids, app: app)
                Button(role: .destructive) { app.actions.trash(ids) } label: { Label("Trash", systemImage: "trash") }
            }
            .confirmationDialog("Remind me", isPresented: $reminding, titleVisibility: .visible) {
                ForEach(MailDate.reminderOptions(), id: \.title) { option in
                    Button(option.title) { app.actions.remind(ids, at: option.date) }
                }
            } message: {
                Text("The thread leaves the inbox and comes back, unread, at the time you pick.")
            }
    }
}

struct ReminderMenu: View {
    let ids: [String]
    let app: AppState

    var body: some View {
        Menu {
            ForEach(MailDate.reminderOptions(), id: \.title) { option in
                Button(option.title) { app.actions.remind(ids, at: option.date) }
            }
        } label: {
            Label("Remind Me", systemImage: "clock")
        }
    }
}

/// Search results (SPEC §4.7): the local FTS index as you type, Gmail's own search when the query uses operators
/// only Gmail knows or nothing matched here.
struct SearchResults: View {
    let query: String
    let labels: [String: MailLabel]
    let open: (MailThread) -> Void
    @Environment(AppState.self) private var app
    @State private var local = Live<[SearchHit]>([])
    @State private var remote = Live<[MailThread]>([])
    @State private var extras = Live<[String: ThreadRowExtras]>([:])
    @State private var gmail = GmailState.idle

    private enum GmailState: Equatable { case idle, searching, done, failed }

    private var parsed: SearchQuery { SearchQuery(query) }

    private var hits: [SearchHit] {
        gmail == .done && (parsed.needsGmail || local.value.isEmpty) ? remote.value.map { SearchHit(thread: $0) } : local.value
    }

    var body: some View {
        let hits = hits
        Group {
            if let error = local.error {
                EmptyState(title: "Couldn't search", message: error.localizedDescription, art: false) { observeLocal() }
            } else if hits.isEmpty, gmail != .searching {
                VStack(spacing: 0) {
                    source.padding(.top, 12)
                    EmptyState(title: "No results", message: "Try different words, or a Gmail operator like from: or has:attachment.", art: false)
                }
            } else {
                List {
                    source.listRowSeparator(.hidden).listRowBackground(Theme.page)
                    ForEach(hits) { hit in
                        ThreadRow(thread: hit.thread, extras: extras.value[hit.thread.id], labels: labels,
                                  terms: parsed.highlightTerms, excerpt: hit.excerpt) { open(hit.thread) }
                        .threadRowStyle()
                        .threadActions(hit.thread, app: app)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .onChange(of: query, initial: true) { observeLocal() }
        .onChange(of: hits.map(\.thread.id), initial: true) { _, ids in
            extras.observe(app.store) { try Store.rowExtras($0, threadIds: ids) }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await searchGmail()
        }
    }

    private var source: some View {
        HStack(spacing: 6) {
            switch gmail {
            case .searching:
                Text("Searching Gmail")
                DotsLoader()
            case .done: Text("\(hits.count == 1 ? "1 result" : "\(hits.count) results") · Searched Gmail")
            case .failed: Text("Couldn't reach Gmail · Showing results from this iPhone")
            case .idle:
                Text(parsed.needsGmail && app.isDemo
                     ? "Searched this iPhone · \(parsed.unsupported.joined(separator: " ")) needs Gmail"
                     : "\(hits.count == 1 ? "1 result" : "\(hits.count) results") on this iPhone")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func observeLocal() {
        let q = parsed
        local.observe(app.store) { try Store.search($0, q) }
    }

    private func searchGmail() async {
        gmail = .idle
        guard let client = app.gmail, parsed.needsGmail || local.value.isEmpty else { return }
        gmail = .searching
        do {
            let ids = try await Sync(gmail: client, store: app.store).search(query)
            guard !Task.isCancelled else { return }
            remote.observe(app.store) { try Store.threads($0, ids: ids) }
            gmail = .done
        } catch {
            if !Task.isCancelled { gmail = .failed }
        }
    }
}
