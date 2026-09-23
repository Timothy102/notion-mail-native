import Foundation

extension AppState {
    /// Triage, navigation and layer commands every feature relies on. Feature-specific commands
    /// (label picker UI, Notion, search operators…) are registered by their own files.
    func registerCoreCommands() {
        let hasTarget: @MainActor @Sendable () -> Bool = { [unowned self] in !targetThreadIds.isEmpty }
        let hasThread: @MainActor @Sendable () -> Bool = { [unowned self] in (openThreadId ?? focusedThreadId) != nil }
        let listHasRows: @MainActor @Sendable () -> Bool = { [unowned self] in !visibleThreadIds.isEmpty }
        let targetUnread: @MainActor @Sendable () -> Bool = { [unowned self] in
            let ids = targetThreadIds
            return (try? store.db.read { try MailThread.filter(keys: ids).fetchAll($0).contains(where: \.isUnread) }) ?? false
        }
        let targetStarred: @MainActor @Sendable () -> Bool = { [unowned self] in
            let ids = targetThreadIds
            return (try? store.db.read { try MailThread.filter(keys: ids).fetchAll($0).allSatisfy(\.isStarred) }) ?? false
        }

        commands.register([
            // Thread
            Command(id: "thread.markRead", title: "Mark as read", group: .thread, icon: "envelope.open", shortcuts: ["I"],
                    keywords: ["read"], isAvailable: hasTarget) { [unowned self] in actions.setRead(targetThreadIds, true) },
            Command(id: "thread.markUnread", title: "Mark as unread", group: .thread, icon: "envelope.badge", shortcuts: ["U"],
                    keywords: ["unread"], isAvailable: hasTarget) { [unowned self] in
                        actions.setRead(targetThreadIds, false)
                        openThreadId = nil
                    },
            Command(id: "thread.toggleRead", title: "Toggle read", group: .thread, shortcuts: ["u"], showsInPalette: false,
                    isAvailable: hasTarget) { [unowned self] in actions.setRead(targetThreadIds, targetUnread()) },
            Command(id: "thread.archive", title: "Archive", group: .thread, icon: "archivebox", shortcuts: ["e"],
                    keywords: ["done"], isAvailable: hasTarget) { [unowned self] in removing(targetThreadIds, actions.archive) },
            Command(id: "thread.trash", title: "Trash", group: .thread, icon: "trash", shortcuts: ["#"],
                    keywords: ["delete"], isAvailable: hasTarget) { [unowned self] in removing(targetThreadIds, actions.trash) },
            Command(id: "thread.reply", title: "Reply", group: .thread, icon: "arrowshape.turn.up.left", shortcuts: ["r"],
                    isAvailable: hasThread) { [unowned self] in startReply(.reply) },
            Command(id: "thread.replyAll", title: "Reply all", group: .thread, icon: "arrowshape.turn.up.left.2", shortcuts: ["a"],
                    isAvailable: hasThread) { [unowned self] in startReply(.replyAll) },
            Command(id: "thread.forward", title: "Forward", group: .thread, icon: "arrowshape.turn.up.right", shortcuts: ["f"],
                    isAvailable: hasThread) { [unowned self] in startReply(.forward) },
            Command(id: "thread.star", title: "Star", group: .thread, icon: "star", shortcuts: ["s"],
                    keywords: ["unstar", "flag"], isAvailable: hasTarget) { [unowned self] in actions.setStarred(targetThreadIds, !targetStarred()) },
            Command(id: "thread.label", title: "Add label", group: .thread, icon: "tag", shortcuts: ["l"],
                    keywords: ["tag", "move"], isAvailable: hasTarget) { [unowned self] in isLabelPickerOpen = true },
            Command(id: "thread.spam", title: "Report spam", group: .thread, icon: "exclamationmark.octagon", shortcuts: ["!"],
                    isAvailable: hasTarget) { [unowned self] in removing(targetThreadIds, actions.markSpam) },
            Command(id: "thread.moveToInbox", title: "Move to Inbox", group: .thread, icon: "tray.and.arrow.down",
                    isAvailable: { [unowned self] in hasTarget() && mailbox != .inbox }) { [unowned self] in removing(targetThreadIds, actions.moveToInbox) },

            // Inbox
            Command(id: "thread.nextMessage", title: "Next message", group: .thread, shortcuts: ["n"], showsInPalette: false,
                    isAvailable: { [unowned self] in openThreadId != nil }) { [unowned self] in moveMessageSelection(1) },
            Command(id: "thread.previousMessage", title: "Previous message", group: .thread, shortcuts: ["p"], showsInPalette: false,
                    isAvailable: { [unowned self] in openThreadId != nil }) { [unowned self] in moveMessageSelection(-1) },
            Command(id: "inbox.compose", title: "Compose", group: .inbox, icon: "square.and.pencil", shortcuts: ["c"],
                    keywords: ["new", "write"]) { [unowned self] in compose = ComposeRequest(.new(to: [])) },
            Command(id: "inbox.next", title: "Next thread", group: .inbox, shortcuts: ["j", "down"], showsInPalette: false,
                    isAvailable: listHasRows) { [unowned self] in moveFocus(1) },
            Command(id: "inbox.previous", title: "Previous thread", group: .inbox, shortcuts: ["k", "up"], showsInPalette: false,
                    isAvailable: listHasRows) { [unowned self] in moveFocus(-1) },
            Command(id: "inbox.open", title: "Open thread", group: .inbox, shortcuts: ["enter", "o"], showsInPalette: false,
                    isAvailable: { [unowned self] in focusedThreadId != nil && openThreadId != focusedThreadId }) { [unowned self] in
                        if let id = focusedThreadId { open(id) }
                    },
            Command(id: "inbox.select", title: "Select", group: .inbox, shortcuts: ["x"], showsInPalette: false,
                    isAvailable: { [unowned self] in focusedThreadId != nil }) { [unowned self] in
                        if let id = focusedThreadId { toggleSelection(id) }
                    },
            Command(id: "inbox.selectAll", title: "Select all", group: .inbox, icon: "checkmark.square", shortcuts: ["cmd+a"],
                    isAvailable: listHasRows) { [unowned self] in selectedThreadIds = Set(visibleThreadIds) },
            Command(id: "inbox.undo", title: "Undo", group: .inbox, icon: "arrow.uturn.backward", shortcuts: ["z", "cmd+z"],
                    isAvailable: { [unowned self] in actions.canUndo }) { [unowned self] in undo() },

            // Navigation
            goTo("inbox", .inbox, "Inbox", "notion.inbox", "g i"),
            goTo("sent", .sent, "Sent", "paperplane", "g t"),
            goTo("drafts", .drafts, "Drafts", "pencil.and.outline", "g d"),
            goTo("starred", .starred, "Starred", "star", "g s"),
            goTo("all", .all, "All Mail", "tray.2", "g a"),
            goTo("spam", .spam, "Spam", "exclamationmark.square", "g !"),
            goTo("trash", .trash, "Trash", "trash", "g #"),

            // Misc
            Command(id: "misc.palette", title: "Command palette", group: .misc, shortcuts: ["cmd+k"], showsInPalette: false) { [unowned self] in
                palette = palette == nil ? .commands : nil
            },
            Command(id: "misc.search", title: "Search", group: .misc, icon: "magnifyingglass", shortcuts: ["/", "cmd+p"],
                    showsInPalette: false) { [unowned self] in palette = .search },
            Command(id: "misc.shortcuts", title: "Shortcuts", group: .misc, icon: "keyboard", shortcuts: ["?"],
                    keywords: ["keys", "help"]) { [unowned self] in settings = .shortcuts },
            Command(id: "misc.toggleSidebar", title: "Toggle sidebar", group: .misc, icon: "sidebar.left", shortcuts: ["cmd+\\"],
                    showsInPalette: false) { [unowned self] in
                isSidebarVisible.toggle()
            },
            Command(id: "misc.themeLight", title: "Set theme · Light", group: .misc, icon: "sun.max", keywords: ["appearance"]) { [unowned self] in theme = .light },
            Command(id: "misc.themeDark", title: "Set theme · Dark", group: .misc, icon: "moon", shortcuts: ["cmd+L"],
                    keywords: ["appearance"]) { [unowned self] in theme = theme == .dark ? .light : .dark },
            Command(id: "misc.themeSystem", title: "Set theme · System", group: .misc, icon: "circle.lefthalf.filled", keywords: ["appearance"]) { [unowned self] in theme = .system },
            Command(id: "misc.settings", title: "Settings", group: .misc, icon: "gearshape", shortcuts: ["cmd+,"],
                    keywords: ["preferences"]) { [unowned self] in settings = .account },
        ])
    }

    private func goTo(_ id: String, _ mailbox: Mailbox, _ title: String, _ icon: String, _ shortcut: Shortcut) -> Command {
        Command(id: "go.\(id)", title: "Go to \(title)", group: .navigation, icon: icon, shortcuts: [shortcut]) { [unowned self] in go(to: mailbox) }
    }

    private enum ReplyKind { case reply, replyAll, forward }

    private func startReply(_ kind: ReplyKind) {
        guard let threadId = openThreadId ?? focusedThreadId, let message = replyTarget(threadId: threadId) else { return }
        if openThreadId == nil { open(threadId) }
        switch kind {
        case .reply: compose = ComposeRequest(.reply(messageId: message.id, all: false))
        case .replyAll: compose = ComposeRequest(.reply(messageId: message.id, all: true))
        case .forward: compose = ComposeRequest(.forward(messageId: message.id))
        }
    }
}
