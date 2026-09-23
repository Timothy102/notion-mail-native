import Foundation

public struct Toast: Identifiable, Sendable {
    public let id = UUID()
    public var text: String
    public var actionTitle: String?
    public var action: (@MainActor @Sendable () -> Void)?

    public init(_ text: String, actionTitle: String? = nil, action: (@MainActor @Sendable () -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    /// 5 s with an action, 4 s without (SPEC §5.8).
    public var duration: Duration { action == nil ? .seconds(4) : .seconds(5) }
}

/// Every mail mutation goes through here: applied to the Store at once (the UI updates via
/// observation), then sent to Gmail in order. A failed call rolls the Store back and toasts.
/// With no Gmail client (demo mode) only the local half runs.
@MainActor
public final class MailActions {
    public let store: Store
    public let gmail: GmailClient?
    /// Set by AppState.
    public var onToast: (Toast) -> Void = { _ in }

    private struct UndoEntry {
        var threadIds: [String]
        var add: Set<String>
        var remove: Set<String>
        var snapshot: LabelSnapshot
    }

    private var undoStack: [UndoEntry] = []
    private var queue: Task<Void, Never>?

    public init(store: Store, gmail: GmailClient?) {
        self.store = store
        self.gmail = gmail
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    public func archive(_ threadIds: [String]) {
        apply(threadIds, remove: ["INBOX"], toast: threadIds.count == 1 ? "Archived" : "Archived \(threadIds.count) threads")
    }

    public func moveToInbox(_ threadIds: [String]) {
        apply(threadIds, add: ["INBOX"], remove: ["TRASH", "SPAM"], toast: "Moved to Inbox")
    }

    public func trash(_ threadIds: [String]) {
        apply(threadIds, add: ["TRASH"], remove: ["INBOX"], toast: threadIds.count == 1 ? "Moved to Trash" : "Moved \(threadIds.count) threads to Trash")
    }

    public func markSpam(_ threadIds: [String]) {
        apply(threadIds, add: ["SPAM"], remove: ["INBOX"], toast: "Marked as spam")
    }

    public func setRead(_ threadIds: [String], _ read: Bool, undoable: Bool = true) {
        read ? apply(threadIds, remove: ["UNREAD"], undoable: undoable) : apply(threadIds, add: ["UNREAD"], undoable: undoable)
    }

    public func setStarred(_ threadIds: [String], _ starred: Bool) {
        starred ? apply(threadIds, add: ["STARRED"]) : apply(threadIds, remove: ["STARRED"])
    }

    public func setLabels(_ threadIds: [String], add: Set<String> = [], remove: Set<String> = []) {
        apply(threadIds, add: add, remove: remove)
    }

    /// Reverts the most recent undoable mutation. Returns false when there is nothing to undo.
    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        do { try store.restore(entry.snapshot) } catch { report("Couldn't undo", error); return false }
        enqueue(entry.threadIds, add: entry.remove, remove: entry.add, rollback: nil)
        return true
    }

    private func apply(_ threadIds: [String], add: Set<String> = [], remove: Set<String> = [], toast: String? = nil, undoable: Bool = true) {
        guard !threadIds.isEmpty else { return }
        let snapshot: LabelSnapshot
        do { snapshot = try store.modify(threadIds: threadIds, add: add, remove: remove) }
        catch { report("Couldn't update mail", error); return }
        if undoable {
            undoStack.append(UndoEntry(threadIds: threadIds, add: add, remove: remove, snapshot: snapshot))
            if undoStack.count > 50 { undoStack.removeFirst() }
        }
        if let toast {
            onToast(Toast(toast, actionTitle: "Undo") { [weak self] in self?.undo() })
        }
        enqueue(threadIds, add: add, remove: remove, rollback: snapshot)
    }

    /// Serial queue so Gmail sees mutations in the order the user made them.
    private func enqueue(_ threadIds: [String], add: Set<String>, remove: Set<String>, rollback: LabelSnapshot?) {
        guard let gmail else { return }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            do {
                for id in threadIds {
                    if add.contains("TRASH") { try await gmail.trashThread(id) }
                    if remove.contains("TRASH") { try await gmail.untrashThread(id) }
                    let a = add.subtracting(["TRASH"]), r = remove.subtracting(["TRASH"])
                    if !a.isEmpty || !r.isEmpty { try await gmail.modifyThread(id, add: a.sorted(), remove: r.sorted()) }
                }
            } catch {
                guard let self else { return }
                if let rollback { try? self.store.restore(rollback) }
                self.report("Couldn't sync with Gmail", error)
            }
        }
    }

    private func report(_ title: String, _ error: any Error) {
        onToast(Toast("\(title): \(error.localizedDescription)"))
    }
}
