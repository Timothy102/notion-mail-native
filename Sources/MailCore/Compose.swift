import Foundation
import GRDB
import Observation

/// A file in the composer. Forwarded Gmail attachments start without bytes and are fetched on
/// the first save or send.
public struct ComposeAttachment: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var filename: String
    public var mimeType: String
    public var size: Int
    public var data: Data?
    public var gmailMessageId: String?
    public var gmailAttachmentId: String?

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.size = data.count
        self.data = data
    }

    init(_ a: Attachment) {
        filename = a.filename
        mimeType = a.mimeType
        size = a.size
        data = a.data
        gmailMessageId = a.messageId
        gmailAttachmentId = a.gmailAttachmentId
    }
}

/// Everything the composer edits, plus the Gmail ids that tie it to a saved draft and a thread.
public struct ComposeDraft: Sendable, Hashable {
    public enum Mode: Sendable, Hashable { case new, reply, replyAll, forward }

    public var mode: Mode
    public var from: EmailAddress
    public var to: [EmailAddress] = []
    public var cc: [EmailAddress] = []
    public var bcc: [EmailAddress] = []
    public var subject = ""
    /// Plain text, including the signature block when one was inserted.
    public var body = ""
    /// Quoted original for replies and forwards; sent below `body`.
    public var quoted: String?
    public var inReplyTo: String?
    public var references: [String] = []
    public var threadId: String?
    /// The message a reply or forward answers, so the mode can be switched in place.
    public var sourceMessageId: String?
    public var attachments: [ComposeAttachment] = []
    public var draftId: String?
    public var draftMessageId: String?

    public static let signatureDelimiter = "-- "

    public init(mode: Mode, from: EmailAddress, to: [EmailAddress] = [], cc: [EmailAddress] = [], subject: String = "") {
        self.mode = mode
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
    }

    public static func signatureBlock(_ identity: SendAs?) -> String {
        let text = MIME.plainText(fromHTML: identity?.signature ?? "")
        return text.isEmpty ? "" : "\n\n\(signatureDelimiter)\n\(text)"
    }

    /// Body with the signature block and surrounding whitespace removed: what the user typed.
    public var typedText: String {
        let cut = body.range(of: "\n\(Self.signatureDelimiter)\n").map { String(body[..<$0.lowerBound]) } ?? body
        return cut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Appends `text` as a new paragraph after what was typed, keeping the signature block below.
    public mutating func insert(_ text: String) {
        let signature = body.range(of: "\n\(Self.signatureDelimiter)\n").map { String(body[$0.lowerBound...]) } ?? ""
        let typed = typedText
        body = (typed.isEmpty ? text : typed + "\n\n" + text) + (signature.isEmpty ? "" : "\n" + signature)
    }

    /// Nothing worth keeping as a draft.
    public var isPristine: Bool {
        guard typedText.isEmpty, !attachments.contains(where: { $0.gmailMessageId == nil }) else { return false }
        return mode != .new || (subject.isEmpty && recipients.isEmpty && attachments.isEmpty)
    }

    public var recipients: [EmailAddress] { to + cc + bcc }

    /// Swaps the signature block of `old` for that of `new` when the body still contains it.
    public mutating func switchIdentity(to identity: SendAs, from old: SendAs?) {
        let previous = Self.signatureBlock(old), next = Self.signatureBlock(identity)
        if !previous.isEmpty, let range = body.range(of: previous, options: .backwards) {
            body.replaceSubrange(range, with: next)
        }
        from = identity.address
    }

    public func outgoing() -> OutgoingMessage {
        OutgoingMessage(
            from: from, to: to, cc: cc, bcc: bcc, subject: subject, text: body, quoted: quoted,
            inReplyTo: inReplyTo, references: references, threadId: threadId,
            attachments: attachments.compactMap { a in a.data.map { OutgoingAttachment(filename: a.filename, mimeType: a.mimeType, data: $0) } }
        )
    }

    // MARK: Building from a request

    /// The initial draft for a compose request. Signatures come from the chosen send-as identity.
    public static func make(_ kind: ComposeRequest.Kind, db: Database, fallbackFrom: EmailAddress, signOnReplies: Bool) throws -> ComposeDraft {
        let identities = try Store.sendAs(db)
        let defaultIdentity = identities.first
        let defaultFrom = defaultIdentity?.address ?? fallbackFrom
        switch kind {
        case .new(let to):
            var d = ComposeDraft(mode: .new, from: defaultFrom, to: to)
            d.body = signatureBlock(defaultIdentity)
            return d
        case .reply(let messageId, let all):
            guard let m = try Store.message(db, id: messageId) else { return ComposeDraft(mode: .new, from: defaultFrom) }
            return try reply(to: m, mode: all ? .replyAll : .reply, db: db, identities: identities, fallbackFrom: defaultFrom, signOnReplies: signOnReplies)
        case .forward(let messageId):
            guard let m = try Store.message(db, id: messageId) else { return ComposeDraft(mode: .new, from: defaultFrom) }
            return try reply(to: m, mode: .forward, db: db, identities: identities, fallbackFrom: defaultFrom, signOnReplies: signOnReplies)
        case .draft(let id):
            guard let draft = try Draft.fetchOne(db, key: id), let m = try Store.message(db, id: draft.messageId) else {
                return ComposeDraft(mode: .new, from: defaultFrom)
            }
            var d = ComposeDraft(mode: m.inReplyTo.isEmpty ? .new : .reply, from: m.sender)
            d.to = EmailAddress.parseList(m.to)
            d.cc = EmailAddress.parseList(m.cc)
            d.bcc = EmailAddress.parseList(m.bcc)
            d.subject = m.subject
            d.body = m.bodyText
            d.inReplyTo = m.inReplyTo.isEmpty ? nil : m.inReplyTo
            d.references = m.references.split(whereSeparator: \.isWhitespace).map(String.init)
            d.threadId = draft.threadId
            d.attachments = try Attachment.filter(Column("messageId") == m.id).fetchAll(db).filter { !$0.isInline }.map(ComposeAttachment.init)
            d.draftId = draft.id
            d.draftMessageId = m.id
            return d
        }
    }

    /// Reply, reply-all or forward to `m`, sent from the identity the original was addressed to.
    public static func reply(to m: Message, mode: Mode, db: Database, identities: [SendAs], fallbackFrom: EmailAddress, signOnReplies: Bool) throws -> ComposeDraft {
        let addressed = Set((EmailAddress.parseList(m.to) + EmailAddress.parseList(m.cc) + [m.sender]).map { $0.email.lowercased() })
        let identity = identities.first { addressed.contains($0.email.lowercased()) } ?? identities.first
        let from = identity?.address ?? fallbackFrom
        let out = mode == .forward ? OutgoingMessage.forward(m, from: from) : OutgoingMessage.reply(to: m, all: mode == .replyAll, from: from)
        var d = ComposeDraft(mode: mode, from: from, to: out.to, cc: out.cc, subject: out.subject)
        d.quoted = out.quoted
        d.inReplyTo = mode == .forward ? nil : out.inReplyTo
        d.references = mode == .forward ? [] : out.references
        d.threadId = mode == .forward ? nil : m.threadId
        d.sourceMessageId = m.id
        d.body = signOnReplies ? signatureBlock(identity) : ""
        if mode == .forward {
            d.attachments = try Attachment.filter(Column("messageId") == m.id).fetchAll(db).filter { !$0.isInline }.map(ComposeAttachment.init)
        }
        return d
    }

    /// Changes reply ↔ reply-all ↔ forward, keeping what was typed and chosen.
    public mutating func switchMode(_ mode: Mode, db: Database) throws {
        guard mode != self.mode, mode != .new, let id = sourceMessageId, let m = try Store.message(db, id: id) else { return }
        let fresh = try Self.reply(to: m, mode: mode, db: db, identities: [], fallbackFrom: from, signOnReplies: false)
        let userFiles = attachments.filter { $0.gmailMessageId != id }
        self.mode = mode
        to = fresh.to
        cc = fresh.cc
        subject = fresh.subject
        quoted = fresh.quoted
        inReplyTo = fresh.inReplyTo
        references = fresh.references
        threadId = fresh.threadId
        attachments = mode == .forward ? fresh.attachments + userFiles : userFiles
    }
}

// MARK: - Contacts

public struct Contact: Sendable, Hashable, Identifiable {
    public var address: EmailAddress
    public var score: Int
    public var id: String { address.email.lowercased() }

    /// Prefix match on the email or any word of the name, case- and diacritic-insensitive.
    public func matches(_ query: String) -> Bool {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return false }
        let email = address.email.lowercased()
        if email.hasPrefix(q) { return true }
        let name = (address.name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return name.hasPrefix(q) || name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" }).contains { $0.hasPrefix(q) }
    }
}

extension Store {
    /// Everyone in recent mail, ranked by how often they appear; people you wrote to count triple.
    public static func contacts(_ db: Database, selfEmails: Set<String>, limit: Int = 3000) throws -> [Contact] {
        let rows = try Row.fetchAll(db, sql: #"SELECT "from", "to", cc FROM messages ORDER BY internalDate DESC LIMIT ?"#, arguments: [limit])
        var byEmail: [String: Contact] = [:]
        for row in rows {
            let from = EmailAddress.parseList(row["from"] ?? "")
            let sentByMe = from.contains { selfEmails.contains($0.email.lowercased()) }
            let others = from + EmailAddress.parseList(row["to"] ?? "") + EmailAddress.parseList(row["cc"] ?? "")
            for a in others {
                let key = a.email.lowercased()
                guard !selfEmails.contains(key), !key.contains("noreply"), !key.contains("no-reply"), !key.hasPrefix("notifications@") else { continue }
                var c = byEmail[key] ?? Contact(address: a, score: 0)
                c.score += sentByMe ? 3 : 1
                if c.address.name == nil, a.name != nil { c.address = a }
                byEmail[key] = c
            }
        }
        return byEmail.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.address.email < $1.address.email }
    }
}

// MARK: - Outbox

/// Saves drafts, sends with an undo window and pushes signatures. Local store first, then Gmail;
/// in demo mode only the local half runs.
@MainActor @Observable
public final class Outbox {
    public struct PendingSend {
        let id: UUID
        public let draft: ComposeDraft
        let reopen: ComposeRequest.Kind
        let archiveThread: Bool
        let task: Task<Void, Never>
    }

    @ObservationIgnored private weak var app: AppState?
    public var sendDelay: Duration = .seconds(5)
    public private(set) var pending: PendingSend?
    @ObservationIgnored private var toastId: UUID?
    /// Content to reopen the composer with after an undone or failed send, keyed by request id.
    public var restore: [UUID: ComposeDraft] = [:]
    /// Set by the open composer; ⌘↵ calls it.
    public var sendAction: (owner: ObjectIdentifier, run: @MainActor () -> Void)?

    private static var attached: [ObjectIdentifier: Outbox] = [:]

    static func attached(to app: AppState) -> Outbox {
        if let outbox = attached[ObjectIdentifier(app)] { return outbox }
        let outbox = Outbox(app: app)
        attached[ObjectIdentifier(app)] = outbox
        outbox.registerCommands()
        return outbox
    }

    private init(app: AppState) {
        self.app = app
    }

    private var store: Store? { app?.store }
    private var gmail: GmailClient? { app?.gmail }

    public static let signOnRepliesKey = "signature.onReplies"

    public var signOnReplies: Bool {
        get { (try? store?.get(Self.signOnRepliesKey)) != "0" }
        set { try? store?.set(Self.signOnRepliesKey, newValue ? "1" : "0") }
    }

    private func registerCommands() {
        guard let app else { return }
        app.commands.register([
            Command(id: "compose.send", title: "Send", group: .thread, icon: "paperplane", shortcuts: ["cmd+enter"], showsInPalette: false,
                    isAvailable: { [unowned self] in sendAction != nil }) { [unowned self] in sendAction?.run() },
            // Replaces the core undo so `z` / ⌘Z take back a pending send first.
            Command(id: "inbox.undo", title: "Undo", group: .inbox, icon: "arrow.uturn.backward", shortcuts: ["z", "cmd+z"],
                    isAvailable: { [unowned self, unowned app] in pending != nil || app.actions.canUndo }) { [unowned self, unowned app] in
                        if pending != nil { undoSend() } else { app.undo() }
                    },
        ])
    }

    // MARK: Drafts

    /// Fills in bytes for forwarded attachments that still live on Gmail.
    func resolved(_ draft: ComposeDraft) async throws -> ComposeDraft {
        var d = draft
        for i in d.attachments.indices where d.attachments[i].data == nil {
            guard let gmail, let m = d.attachments[i].gmailMessageId, let a = d.attachments[i].gmailAttachmentId else { continue }
            d.attachments[i].data = try await gmail.attachment(messageId: m, id: a)
        }
        return d
    }

    /// Creates or updates the draft. Returns it with the draft, message and thread ids filled in.
    public func saveDraft(_ draft: ComposeDraft) async throws -> ComposeDraft {
        guard let store else { return draft }
        var d = try await resolved(draft)
        let out = d.outgoing()
        let draftId: String, messageId: String, threadId: String
        if let gmail {
            let raw = MIME.build(out)
            let saved = if let id = d.draftId { try await gmail.updateDraft(id, raw: raw, threadId: d.threadId) }
                        else { try await gmail.createDraft(raw: raw, threadId: d.threadId) }
            draftId = saved.id
            messageId = saved.message?.id ?? Self.localId()
            threadId = saved.message?.threadId ?? d.threadId ?? messageId
        } else {
            draftId = d.draftId ?? Self.localId()
            messageId = d.draftMessageId ?? Self.localId()
            threadId = d.threadId ?? Self.localId()
        }
        if let old = d.draftMessageId, old != messageId { try store.deleteMessages(ids: [old]) }
        try Self.insert(out, id: messageId, threadId: threadId, labels: ["DRAFT"], into: store)
        try store.save(draft: Draft(id: draftId, messageId: messageId, threadId: threadId, updatedAt: .now))
        d.draftId = draftId
        d.draftMessageId = messageId
        d.threadId = threadId
        return d
    }

    public func discard(_ draft: ComposeDraft) async {
        guard let id = draft.draftId, let store else { return }
        try? store.deleteDraft(id: id)
        if let gmail { try? await gmail.deleteDraft(id) }
    }

    // MARK: Sending

    /// Sends after `sendDelay`, showing an Undo toast meanwhile. `reopen` is the request the
    /// composer comes back as when the send is undone or fails.
    public func send(_ draft: ComposeDraft, reopen: ComposeRequest.Kind, archiveThread: Bool = false) {
        if let previous = pending {
            previous.task.cancel()
            pending = nil
            Task { await deliver(previous) }
        }
        let toast = Toast("Sending…", actionTitle: "Undo") { [weak self] in self?.undoSend() }
        let id = UUID()
        let delay = sendDelay
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let p = pending, p.id == id else { return }
            pending = nil
            await deliver(p)
        }
        pending = PendingSend(id: id, draft: draft, reopen: reopen, archiveThread: archiveThread, task: task)
        app?.show(toast)
        toastId = toast.id
    }

    public func undoSend() {
        guard let p = pending, let app else { return }
        p.task.cancel()
        pending = nil
        if let toastId { app.dismissToast(toastId) }
        reopen(p.draft, as: p.reopen)
    }

    private func reopen(_ draft: ComposeDraft, as kind: ComposeRequest.Kind) {
        let request = ComposeRequest(kind)
        restore[request.id] = draft
        app?.compose = request
    }

    private func deliver(_ p: PendingSend) async {
        guard let store else { return }
        do {
            let d = try await resolved(p.draft)
            let out = d.outgoing()
            var id = Self.localId(), threadId = d.threadId ?? id, labels = ["SENT"]
            if let gmail {
                let raw = MIME.build(out)
                let sent: GmailMessage
                if let draftId = d.draftId {
                    _ = try await gmail.updateDraft(draftId, raw: raw, threadId: d.threadId)
                    sent = try await gmail.sendDraft(draftId)
                } else {
                    sent = try await gmail.send(raw: raw, threadId: d.threadId)
                }
                id = sent.id
                threadId = sent.threadId
                labels = sent.labelIds ?? labels
            }
            if let draftId = d.draftId { try store.deleteDraft(id: draftId) }
            try Self.insert(out, id: id, threadId: threadId, labels: labels, into: store)
            app?.show(Toast("Message sent"))
            if p.archiveThread, let t = d.threadId { app?.actions.archive([t]) }
        } catch {
            app?.show(Toast("Couldn't send: \(error.localizedDescription)", actionTitle: "Open") { [weak self] in
                self?.reopen(p.draft, as: p.reopen)
            })
        }
    }

    // MARK: Signatures

    /// Saves the signature locally and pushes it to Gmail (`sendAs.patch`).
    public func updateSignature(_ identity: SendAs, html: String) async throws {
        guard let store else { return }
        var updated = identity
        updated.signature = html
        if let gmail { _ = try await gmail.updateSignature(sendAsEmail: identity.email, signature: html) }
        try store.save(sendAs: [updated])
    }

    /// Plain-text signature to the HTML Gmail stores.
    public static func signatureHTML(fromText text: String) -> String {
        MIME.htmlEscape(text.trimmingCharacters(in: .whitespacesAndNewlines)).replacingOccurrences(of: "\n", with: "<br>")
    }

    // MARK: Helpers

    static func localId() -> String { "local-" + UUID().uuidString.lowercased() }

    /// Stores what was sent or saved through the same parse path as synced mail.
    static func insert(_ out: OutgoingMessage, id: String, threadId: String, labels: [String], into store: Store) throws {
        let root = MIME.parse(MIME.build(out))
        let (message, parts) = Message.make(id: id, threadId: threadId, labelIds: labels,
                                            internalDate: Int64(out.date.timeIntervalSince1970 * 1000), snippet: nil, root: root)
        try store.upsert(messages: [message], attachments: parts)
    }
}

extension AppState {
    public var outbox: Outbox { Outbox.attached(to: self) }
}
