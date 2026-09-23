import Foundation
import Observation
import UniformTypeIdentifiers

/// State behind one open composer: the draft, autosave, send and discard.
@MainActor @Observable
public final class ComposeModel {
    public init() {}

    public enum SaveStatus: Equatable { case idle, saving, saved, failed }
    public enum Field: Hashable { case to, cc, bcc, subject }

    public var draft = ComposeDraft(mode: .new, from: EmailAddress(name: nil, email: ""))
    public private(set) var status = SaveStatus.idle
    public private(set) var identities: [SendAs] = []
    public private(set) var contacts: [Contact] = []
    public var showsCc = false
    public var showsBcc = false
    public var showsCcBcc: Bool { showsCc || showsBcc }
    public var showsQuoted = false
    public static var snapshotShowsQuoted = false
    public var isMinimized = false
    public private(set) var requestId: UUID?

    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private var lastSaved: ComposeDraft?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var finished = false
    public static let autosaveDelay = Duration.seconds(1.5)
    public static let attachmentLimit = 25 * 1024 * 1024

    public func load(_ request: ComposeRequest, app: AppState) {
        guard request.id != requestId else { return }
        flush()
        self.app = app
        requestId = request.id
        finished = false
        isMinimized = false
        showsQuoted = Self.snapshotShowsQuoted
        let fallback = EmailAddress(name: app.account?.name, email: app.account?.email ?? "")
        let signOnReplies = app.outbox.signOnReplies
        let restored = app.outbox.restore.removeValue(forKey: request.id)
        let (made, identities) = (try? app.store.db.read { db in
            (try restored ?? ComposeDraft.make(request.kind, db: db, fallbackFrom: fallback, signOnReplies: signOnReplies), try Store.sendAs(db))
        }) ?? (ComposeDraft(mode: .new, from: fallback), [])
        draft = made
        self.identities = identities
        let selfEmails = Set(identities.map { $0.email.lowercased() } + [fallback.email.lowercased()])
        contacts = (try? app.store.db.read { try Store.contacts($0, selfEmails: selfEmails) }) ?? []
        lastSaved = made.draftId == nil ? nil : made
        status = made.draftId == nil ? .idle : .saved
        showsCc = !made.cc.isEmpty
        showsBcc = !made.bcc.isEmpty
    }

    public var identity: SendAs? { identities.first { $0.email.lowercased() == draft.from.email.lowercased() } }

    public func choose(_ identity: SendAs) {
        draft.switchIdentity(to: identity, signature: (try? app?.store.db.read { try Signature.html(for: identity, db: $0) }) ?? "")
    }

    public func switchMode(_ mode: ComposeDraft.Mode) {
        guard let app else { return }
        try? app.store.db.read { try draft.switchMode(mode, db: $0) }
    }

    /// Called on every edit: saves 1.5 s after the last change.
    public func edited() {
        guard !finished, draft != lastSaved, !(draft.isPristine && draft.draftId == nil) else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let app, !finished else { return }
        let snapshot = draft
        status = .saving
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do {
                let saved = try await app.outbox.saveDraft(snapshot)
                guard let self else { return }
                guard saved.sessionId == draft.sessionId else { return }
                draft.adopt(saved)
                lastSaved = saved
                status = .saved
            } catch {
                self?.status = .failed
            }
        }
    }

    /// Saves pending edits now (closing, switching requests).
    public func flush() {
        guard !finished, requestId != nil else { return }
        debounce?.cancel()
        if draft != lastSaved, !(draft.isPristine && draft.draftId == nil) { save() }
        finished = true
    }

    public func send(archiveThread: Bool = false) {
        guard let app else { return }
        guard !draft.recipients.isEmpty else {
            app.show(Toast("Add at least one recipient"))
            return
        }
        finished = true
        debounce?.cancel()
        let reopen = reopenKind
        Task { [weak self] in
            await self?.saveTask?.value
            guard let self else { return }
            app.outbox.send(draft, reopen: reopen, archiveThread: archiveThread)
        }
        app.compose = nil
    }

    public func discard() {
        guard let app else { return }
        finished = true
        debounce?.cancel()
        Task { [weak self] in
            await self?.saveTask?.value
            guard let self else { return }
            await app.outbox.discard(draft)
        }
        app.compose = nil
        if draft.draftId != nil || !draft.isPristine { app.show(Toast("Draft discarded")) }
    }

    public func close() {
        flush()
        app?.compose = nil
    }

    private var reopenKind: ComposeRequest.Kind {
        switch (draft.mode, draft.sourceMessageId) {
        case (.reply, let id?): .reply(messageId: id, all: false)
        case (.replyAll, let id?): .reply(messageId: id, all: true)
        case (.forward, let id?): .forward(messageId: id)
        default: .new(to: [])
        }
    }

    // MARK: Attachments

    public func attach(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let total = draft.attachments.reduce(0) { $0 + $1.size } + data.count
            guard total <= Self.attachmentLimit else {
                app?.show(Toast("Attachments are limited to 25 MB"))
                return
            }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            draft.attachments.append(ComposeAttachment(filename: url.lastPathComponent, mimeType: type, data: data))
        }
    }

    public var statusText: String {
        switch status {
        case .idle: ""
        case .saving: "Saving…"
        case .saved: "Draft saved"
        case .failed: "Couldn't save draft"
        }
    }
}
