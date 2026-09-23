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
/// observation), then queued for Gmail and sent in order. The queue is persisted, so changes made
/// offline or before a quit reach Gmail later. Offline, the head of the queue is retried with backoff;
/// a call Gmail rejects is rolled back locally and toasted. With no Gmail client (demo mode) only the
/// local half runs.
@MainActor
public final class MailActions {
    public let store: Store
    public let gmail: GmailClient?
    /// Set by AppState.
    public var onToast: (Toast) -> Void = { _ in }
    public var onOfflineChange: (Bool) -> Void = { _ in }

    struct Mutation: Codable {
        var threadIds: [String]
        var add: Set<String>
        var remove: Set<String>
        /// Labels before the change, to roll back to if Gmail rejects it. Not persisted.
        var rollback: LabelSnapshot?

        private enum CodingKeys: String, CodingKey { case threadIds, add, remove }
    }

    private struct UndoEntry {
        var threadIds: [String]
        var add: Set<String>
        var remove: Set<String>
        var snapshot: LabelSnapshot
    }

    static let pendingKey = "pendingMutations"
    private var undoStack: [UndoEntry] = []
    private(set) var pending: [Mutation]
    private var drain: Task<Void, Never>?
    private(set) var isOffline = false {
        didSet { if isOffline != oldValue { onOfflineChange(isOffline) } }
    }

    public init(store: Store, gmail: GmailClient?) {
        self.store = store
        self.gmail = gmail
        pending = (try? store.get(Self.pendingKey)).flatMap { $0 }
            .flatMap { try? JSONDecoder().decode([Mutation].self, from: Data($0.utf8)) } ?? []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var pendingCount: Int { pending.count }

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
        let current: LabelSnapshot
        do {
            current = try labels(of: Array(entry.snapshot.labelIds.keys))
            try store.restore(entry.snapshot)
        } catch { report("Couldn't undo", error); return false }
        enqueue(Mutation(threadIds: entry.threadIds, add: entry.remove, remove: entry.add, rollback: current))
        return true
    }

    /// Starts sending queued changes, or retries now if waiting out the network.
    public func resume() {
        guard let gmail, !pending.isEmpty else { return }
        if drain != nil, !isOffline { return }
        drain?.cancel()
        drain = Task { [weak self] in
            var delay = 2.0
            while let self, !Task.isCancelled, let next = self.pending.first {
                do {
                    try await Self.send(next, gmail)
                    guard !Task.isCancelled else { return }
                    self.isOffline = false
                    delay = 2
                    self.finishHead()
                } catch where Task.isCancelled {
                    return
                } catch where MailCore.isOffline(error) {
                    self.isOffline = true
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 2, 60)
                } catch {
                    self.finishHead()
                    self.rollBack(next)
                    self.report("Gmail didn't accept the change, so it was undone", error)
                }
            }
            if !Task.isCancelled { self?.drain = nil }
        }
    }

    /// Re-applies queued changes on top of what a sync just wrote, so mail Gmail hasn't heard about yet
    /// keeps its local state.
    public func reapplyPending() {
        for m in pending { _ = try? store.modify(threadIds: m.threadIds, add: m.add, remove: m.remove) }
    }

    /// Waits until the queue is empty or stalled offline.
    func settle() async {
        while drain != nil, !isOffline { try? await Task.sleep(for: .milliseconds(5)) }
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
        enqueue(Mutation(threadIds: threadIds, add: add, remove: remove, rollback: snapshot))
    }

    private func enqueue(_ mutation: Mutation) {
        guard gmail != nil else { return }
        pending.append(mutation)
        persist()
        resume()
    }

    private func finishHead() {
        pending.removeFirst()
        persist()
    }

    /// Restores the labels from before `mutation`, then re-applies the changes queued after it.
    private func rollBack(_ mutation: Mutation) {
        guard let snapshot = mutation.rollback else { return }
        try? store.restore(snapshot)
        reapplyPending()
    }

    private func persist() {
        let json = pending.isEmpty ? nil : (try? JSONEncoder().encode(pending)).map { String(decoding: $0, as: UTF8.self) }
        try? store.set(Self.pendingKey, json)
    }

    private func labels(of messageIds: [String]) throws -> LabelSnapshot {
        try store.db.read { db in
            LabelSnapshot(labelIds: Dictionary(uniqueKeysWithValues: try Message.fetchAll(db, keys: messageIds).map { ($0.id, $0.labelIds) }))
        }
    }

    private nonisolated static func send(_ m: Mutation, _ gmail: GmailClient) async throws {
        for id in m.threadIds {
            if m.add.contains("TRASH") { try await gmail.trashThread(id) }
            if m.remove.contains("TRASH") { try await gmail.untrashThread(id) }
            let add = m.add.subtracting(["TRASH"]), remove = m.remove.subtracting(["TRASH"])
            if !add.isEmpty || !remove.isEmpty { try await gmail.modifyThread(id, add: add.sorted(), remove: remove.sorted()) }
        }
    }

    private func report(_ title: String, _ error: any Error) {
        onToast(Toast(title))
        FileHandle.standardError.write(Data("\(title): \(error)\n".utf8))
    }
}
