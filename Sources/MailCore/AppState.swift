import AppKit
import Foundation
import Observation

public enum ThemePreference: String, Sendable, CaseIterable { case system, light, dark }

public enum PaletteMode: Sendable, Hashable { case commands, search }

public enum SettingsPage: String, Sendable, CaseIterable {
    case account = "Account", signature = "Signature", appearance = "Appearance", shortcuts = "Keyboard shortcuts", integrations = "Integrations"
}

public struct ComposeRequest: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case new(to: [EmailAddress])
        case reply(messageId: String, all: Bool)
        case forward(messageId: String)
        case draft(id: String)
    }

    public let id = UUID()
    public var kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }
}

/// UI state shared by every view. Views read it from the environment; mutations of mail go
/// through `actions`, everything else through the methods here or the command registry.
@MainActor @Observable
public final class AppState {
    public let store: Store
    public let actions: MailActions
    public let commands = CommandRegistry()
    /// nil in demo mode: nothing touches the network.
    public let gmail: GmailClient?
    public var isDemo: Bool { gmail == nil }
    /// This account's cached Google photo.
    public let avatarURL: URL?

    public var account: Account?
    /// Google profile photo; nil shows the letter avatar.
    public var avatarImage: NSImage?
    public var syncStatus: SyncStatus = .idle
    /// Until the first backfill completes an empty list means "not synced yet", not "no mail".
    public var isAwaitingFirstSync = false
    @ObservationIgnored var syncLoop: Task<Void, Never>?
    @ObservationIgnored var syncTick: AsyncStream<Void>.Continuation?

    // Navigation
    public private(set) var mailbox: Mailbox = .inbox
    /// Non-nil shows search results in the list pane instead of `mailbox`.
    public var searchQuery: String?

    // List state. The visible list (InboxList or SearchView) keeps `visibleThreadIds` in display order.
    public var visibleThreadIds: [String] = []
    public var focusedThreadId: String?
    public var selectedThreadIds: Set<String> = []
    public var openThreadId: String?
    /// Message picked with n / p in the open thread; nil until then.
    public var selectedMessageId: String?

    // Layers
    public var palette: PaletteMode?
    public var compose: ComposeRequest?
    public var settings: SettingsPage?
    public var isLabelPickerOpen = false
    public var isAccountMenuOpen = false
    public var notionPicker: NotionPickerRequest?
    public var isSidebarVisible = true
    /// Remembered across launches outside demo mode.
    public var theme: ThemePreference = .system {
        didSet { if !isDemo { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) } }
    }
    static let themeKey = "appearance.theme"
    public private(set) var toast: Toast?

    public init(store: Store, gmail: GmailClient?, avatarURL: URL? = nil) {
        self.store = store
        self.gmail = gmail
        self.avatarURL = avatarURL
        actions = MailActions(store: store, gmail: gmail)
        account = try? store.db.read(Store.account)
        avatarImage = avatarURL.flatMap(NSImage.init(contentsOf:))
        if gmail != nil { theme = UserDefaults.standard.string(forKey: Self.themeKey).flatMap(ThemePreference.init(rawValue:)) ?? .system }
        actions.onToast = { [weak self] in self?.show($0) }
        registerCoreCommands()
        registerIntegrationCommands()
    }

    /// Selection if any, else the open thread, else the keyboard-focused row.
    public var targetThreadIds: [String] {
        if !selectedThreadIds.isEmpty { return visibleThreadIds.filter(selectedThreadIds.contains) }
        if let id = openThreadId ?? focusedThreadId { return [id] }
        return []
    }

    public func go(to mailbox: Mailbox) {
        self.mailbox = mailbox
        searchQuery = nil
        selectedThreadIds = []
        openThreadId = nil
        focusedThreadId = nil
    }

    public func search(_ query: String) {
        searchQuery = query
        selectedThreadIds = []
        openThreadId = nil
        focusedThreadId = nil
    }

    /// Opens the thread in the peek and marks it read (optimistic, not undoable).
    public func open(_ threadId: String) {
        openThreadId = threadId
        focusedThreadId = threadId
        selectedMessageId = nil
        let unread = (try? store.db.read { try MailThread.fetchOne($0, key: threadId)?.isUnread }) ?? false
        if unread == true { actions.setRead([threadId], true, undoable: false) }
    }

    public func closeThread() {
        openThreadId = nil
    }

    /// j/k: moves the focused row, or with a thread open, opens the adjacent one.
    public func moveFocus(_ delta: Int) {
        guard !visibleThreadIds.isEmpty else { return }
        let current = (openThreadId ?? focusedThreadId).flatMap(visibleThreadIds.firstIndex(of:))
        let next = current.map { min(max($0 + delta, 0), visibleThreadIds.count - 1) } ?? (delta > 0 ? 0 : visibleThreadIds.count - 1)
        let id = visibleThreadIds[next]
        if openThreadId != nil { open(id) } else { focusedThreadId = id }
    }

    /// n / p: selects the next or previous message of the open thread, starting from the newest.
    public func moveMessageSelection(_ delta: Int) {
        guard let threadId = openThreadId else { return }
        let ids = (try? store.db.read { try Store.threadDetail($0, id: threadId)?.messages.filter { !$0.isDraft }.map(\.id) }).flatMap { $0 } ?? []
        guard !ids.isEmpty else { return }
        let current = selectedMessageId.flatMap(ids.firstIndex(of:)) ?? ids.count - (delta > 0 ? 2 : 0)
        selectedMessageId = ids[min(max(current + delta, 0), ids.count - 1)]
    }

    public func toggleSelection(_ threadId: String) {
        if selectedThreadIds.contains(threadId) { selectedThreadIds.remove(threadId) } else { selectedThreadIds.insert(threadId) }
    }

    /// Runs a mutation that removes threads from the current list (archive, trash…) and moves
    /// focus, and the open thread, to the next row (or the previous one if they were last).
    public func removing(_ threadIds: [String], _ mutation: ([String]) -> Void) {
        guard !threadIds.isEmpty else { return }
        let gone = Set(threadIds)
        let wasOpen = openThreadId.map(gone.contains) ?? false
        let anchor = visibleThreadIds.lastIndex { gone.contains($0) } ?? -1
        let after = visibleThreadIds[(anchor + 1)...].first { !gone.contains($0) }
        let before = visibleThreadIds[..<max(anchor, 0)].last { !gone.contains($0) }
        let next = after ?? before
        mutation(threadIds)
        selectedThreadIds.subtract(gone)
        if let f = focusedThreadId, gone.contains(f) { focusedThreadId = next }
        if wasOpen {
            if let next { open(next) } else { openThreadId = nil }
        }
    }

    public func show(_ toast: Toast) {
        self.toast = toast
    }

    public func dismissToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
    }

    public func undo() {
        if actions.undo() { toast = nil }
    }

    /// Esc: closes the topmost layer. Returns false when nothing was open.
    @discardableResult
    public func dismissTopmost() -> Bool {
        if palette != nil { palette = nil }
        else if isAccountMenuOpen { isAccountMenuOpen = false }
        else if notionPicker != nil { notionPicker = nil }
        else if isLabelPickerOpen { isLabelPickerOpen = false }
        else if settings != nil { settings = nil }
        else if compose != nil { compose = nil }
        else if openThreadId != nil { openThreadId = nil }
        else if !selectedThreadIds.isEmpty { selectedThreadIds = [] }
        else if searchQuery != nil { searchQuery = nil }
        else { return false }
        return true
    }

    /// Newest non-draft message of a thread: what r / a / f reply to.
    public func replyTarget(threadId: String) -> Message? {
        try? store.db.read { db in
            try Store.threadDetail(db, id: threadId)?.messages.last { !$0.isDraft }
        }
    }
}
