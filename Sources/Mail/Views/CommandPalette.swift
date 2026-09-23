import AppKit
import MailCore
import SwiftUI

/// ⌘K palette (SPEC §4.6). Lists every registered palette command plus a jump to each label,
/// and once there is a query, the best-ranked threads and matching contacts. Features add
/// actions by registering commands, never by editing this file.
struct CommandPalette: View {
    let mode: PaletteMode
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var sections: [Section] = []
    @State private var selection = 0
    @State private var keyboardMovedAt = Date.distantPast
    @State private var keyMonitor: KeyMonitor?
    @FocusState private var focused: Bool

    fileprivate struct Section: Identifiable {
        var title: String
        var items: [Item]
        var id: String { title }
    }

    fileprivate struct Item: Identifiable {
        enum Kind {
            case command(Command)
            case thread(SearchHit, terms: [String])
            case contact(EmailAddress)
            case search(String)
            case insert(String)
        }

        var id: String
        var kind: Kind
        var title: String
        var icon: String?
        var hint: String?
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.scrim.onTapGesture { app.palette = nil }
                panel
                    .frame(width: min(Theme.Metrics.paletteWidth, geo.size.width - 80))
                    .padding(.top, (geo.size.height * Theme.Metrics.paletteTopFraction).rounded())
            }
        }
        .onAppear {
            if mode == .search, let q = app.searchQuery { query = q }
            if Launch.snapshotPath != nil, let q = Launch.env["MAIL_QUERY"] { query = q }
            sections = buildSections()
            DispatchQueue.main.async { focused = true }
            keyMonitor = KeyMonitor { move($0) }
        }
        .onDisappear { keyMonitor = nil }
        .onChange(of: query) {
            sections = buildSections()
            selection = 0
        }
    }

    private var items: [Item] { sections.flatMap(\.items) }

    private var placeholder: String {
        if mode == .search { return "Search mail…" }
        return app.openThreadId != nil || !app.selectedThreadIds.isEmpty ? "Type a command or search…" : "Search commands or mail…"
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.Metrics.iconSmall)
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .textStyle(.paletteInput)
                    .placeholder(placeholder, showing: query.isEmpty)
                    .focused($focused)
                    .onSubmit { run(selection) }
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.Metrics.paletteInputHeight)
            Theme.divider.frame(height: 1)
            if !items.isEmpty {
                results
                Theme.divider.frame(height: 1)
            }
            HStack(spacing: 16) {
                footerHint("arrow.up.arrow.down", "Select")
                footerHint("return", "Open")
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.Metrics.paletteFooterHeight)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
    }

    private var results: some View {
        let offsets = sectionOffsets
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { s, section in
                        Text(section.title)
                            .textStyle(.smallSemibold)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8)
                            .frame(height: 28, alignment: .center)
                            .padding(.top, s == 0 ? 4 : 12)
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { i, item in
                            let index = offsets[s] + i
                            row(item, selected: index == selection)
                                .id(item.id)
                                .onContinuousHover { phase in
                                    if case .active = phase, Launch.snapshotPath == nil, Date.now.timeIntervalSince(keyboardMovedAt) > 0.3 { selection = index }
                                }
                                .onTapGesture { run(index) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: Theme.Metrics.paletteMaxHeight - Theme.Metrics.paletteInputHeight - Theme.Metrics.paletteFooterHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selection) {
                guard Date.now.timeIntervalSince(keyboardMovedAt) < 0.1, items.indices.contains(selection) else { return }
                proxy.scrollTo(items[selection].id)
            }
        }
    }

    private var sectionOffsets: [Int] {
        var offsets: [Int] = []
        var n = 0
        for s in sections {
            offsets.append(n)
            n += s.items.count
        }
        return offsets
    }

    @ViewBuilder
    private func row(_ item: Item, selected: Bool) -> some View {
        switch item.kind {
        case .thread(let hit, let terms):
            ThreadResultRow(hit: hit, terms: terms, selected: selected)
        case .contact(let address):
            HStack(spacing: 10) {
                Avatar(name: address.displayName, size: Theme.Metrics.iconMedium)
                HStack(spacing: 8) {
                    Text(address.displayName).textStyle(.body).lineLimit(1).layoutPriority(1)
                    if address.name != nil {
                        Text(address.email).textStyle(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .paletteRow(selected: selected)
        default:
            HStack(spacing: 10) {
                icon(item.icon).frame(width: Theme.Metrics.iconMedium, height: Theme.Metrics.iconMedium)
                Text(item.title).textStyle(.body).lineLimit(1)
                Spacer(minLength: 8)
                if let hint = item.hint {
                    Text(hint).textStyle(.small).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        .frame(minWidth: 78, alignment: .trailing)
                }
            }
            .paletteRow(selected: selected)
        }
    }

    /// Same glyphs as the sidebar: the inbox tray, label dots, outline symbols.
    @ViewBuilder
    private func icon(_ name: String?) -> some View {
        if let name, name.hasPrefix(Self.labelIcon) {
            Circle().fill(LabelColor(named: String(name.dropFirst(Self.labelIcon.count))).dot).frame(width: 10, height: 10)
        } else if let name {
            SlotIcon(systemName: name, tint: Theme.textSecondary)
        }
    }

    private static let labelIcon = "label.dot:"

    private func footerHint(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(title).textStyle(.small)
        }
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Results

    private func buildSections() -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if mode == .search, q.isEmpty { return [Section(title: "Search with", items: Self.operatorTips)] }
        var out = mode == .commands ? commandSections(q) : []
        guard !q.isEmpty else { return out }
        let parsed = SearchQuery(q)
        let search = Item(id: "search", kind: .search(q), title: "Search mail for “\(q)”", icon: "magnifyingglass",
                          hint: parsed.needsGmail && !app.isDemo ? "Gmail" : nil)
        out.append(Section(title: "Search", items: [search]))
        let (threads, contacts) = (try? app.store.db.read { db in
            (try Store.search(db, parsed, order: .relevance, limit: 5),
             q.contains(":") ? [] : try Store.contacts(db, matching: q))
        }) ?? ([], [])
        if !threads.isEmpty {
            let terms = parsed.highlightTerms
            out.append(Section(title: "Threads", items: threads.map {
                Item(id: "thread:\($0.id)", kind: .thread($0, terms: terms), title: $0.thread.subject)
            }))
        }
        if !contacts.isEmpty {
            out.append(Section(title: "Contacts", items: contacts.map {
                Item(id: "contact:\($0.email)", kind: .contact($0), title: $0.displayName)
            }))
        }
        return out
    }

    /// Registered commands plus "Go to <label>", fuzzy-filtered on the title and, with a query, best match first.
    private func commandSections(_ q: String) -> [Section] {
        let labels = (try? app.store.db.read(Store.labels)) ?? []
        let labelCommands = labels.map { label in
            Command(id: "go.label.\(label.id)", title: "Go to \(label.name)", group: .navigation, icon: Self.labelIcon + (label.color ?? "")) { [app] in
                app.go(to: .label(label.id))
            }
        }
        let commands = app.commands.paletteCommands + labelCommands
        let scored: [(Command, Int)] = commands.compactMap { c in
            SearchText.fuzzyScore(q, c.title).map { (c, $0) }
        }
        var groups = Command.Group.allCases.compactMap { group -> (Command.Group, [(Command, Int)])? in
            let rows = scored.filter { $0.0.group == group }
            return rows.isEmpty ? nil : (group, q.isEmpty ? rows : rows.sorted { $0.1 > $1.1 })
        }
        if !q.isEmpty { groups.sort { ($0.1.first?.1 ?? 0) > ($1.1.first?.1 ?? 0) } }
        return groups.map { group, rows in
            Section(title: group.rawValue, items: rows.map { c, _ in
                Item(id: c.id, kind: .command(c), title: c.title, icon: c.icon,
                     hint: c.shortcuts.isEmpty ? nil : c.shortcuts.prefix(2).map(\.display).joined(separator: " or "))
            })
        }
    }

    private static let operatorTips: [Item] = [
        ("from:", "From someone", "person"),
        ("to:", "Sent to someone", "paperplane"),
        ("subject:", "Subject contains", "text.alignleft"),
        ("has:attachment", "Has an attachment", "paperclip"),
        ("is:unread", "Unread", "envelope.badge"),
        ("is:starred", "Starred", "star"),
        ("label:", "With a label", "tag"),
        ("after:", "After a date", "calendar"),
        ("before:", "Before a date", "calendar"),
    ].map { op, title, icon in Item(id: "insert:\(op)", kind: .insert(op), title: title, icon: icon, hint: op) }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        keyboardMovedAt = .now
        selection = (selection + delta + items.count) % items.count
    }

    private func run(_ index: Int) {
        guard items.indices.contains(index) else {
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty { close { app.search(q) } }
            return
        }
        switch items[index].kind {
        case .command(let command): close { command.perform() }
        case .thread(let hit, _): close { app.open(hit.id) }
        case .contact(let address): close { app.search("from:\(address.email)") }
        case .search(let q): close { app.search(q) }
        case .insert(let op):
            query = op.hasSuffix(":") ? op : op + " "
        }
    }

    private func close(then action: () -> Void) {
        app.palette = nil
        action()
    }
}

private extension View {
    func paletteRow(selected: Bool) -> some View {
        padding(.horizontal, 8)
            .frame(height: Theme.Metrics.paletteRowHeight)
            .background(selected ? Theme.rowHover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Thread result (§5.5b): 48 tall, 24 avatar, subject over "from · snippet", date at the right.
private struct ThreadResultRow: View {
    let hit: SearchHit
    let terms: [String]
    let selected: Bool

    var body: some View {
        let thread = hit.thread
        HStack(spacing: 10) {
            Avatar(name: thread.participants, size: Theme.Metrics.iconLarge)
            VStack(alignment: .leading, spacing: 0) {
                MarkedText(text: thread.subject.isEmpty ? "(no subject)" : thread.subject, terms: terms)
                    .textStyle(.bodyMedium)
                    .lineLimit(1)
                MarkedText(text: "\(thread.participants) · \(hit.excerpt ?? thread.snippet)", terms: terms)
                    .textStyle(.small)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(MailDate.list(thread.lastDate))
                .textStyle(.smallMedium)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        .background(selected ? Theme.rowHover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.rowRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Arrow keys and ⌃N / ⌃P move the palette selection while its field has focus.
@MainActor
private final class KeyMonitor {
    private var monitor: Any?

    init(_ move: @escaping @MainActor (Int) -> Void) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let ctrl = event.modifierFlags.contains(.control)
            let key = event.charactersIgnoringModifiers
            let delta: Int? = switch event.keyCode {
            case 125: 1
            case 126: -1
            default: ctrl && key == "n" ? 1 : ctrl && key == "p" ? -1 : nil
            }
            guard let delta else { return event }
            MainActor.assumeIsolated { move(delta) }
            return nil
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
