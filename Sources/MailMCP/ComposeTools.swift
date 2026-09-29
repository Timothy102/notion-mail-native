import Foundation
import GRDB
import MailCore

/// What a message will look like, before it is sent.
struct Preview: Encodable {
    var mode: String
    var from: String
    var to: [String]
    var cc: [String]?
    var bcc: [String]?
    var subject: String
    /// The text/plain part: what was written, then the signature with its links spelled out.
    var text: String
    /// The HTML part above the quote: Notion Mail's stylesheet, a `<p dir="auto">` per line, the signature markup.
    var html: String?
    /// Start of the quoted history appended below (replies and forwards).
    var quoted: String?
    var threads: Bool
    var threadId: String?
    var inReplyTo: String?
    var references: [String]?
    var signed: Bool
    var attachments: [String]?

    init(_ d: ComposeDraft, html: Bool = true) {
        let out = d.outgoing()
        mode = switch d.mode { case .new: "new"; case .reply: "reply"; case .replyAll: "reply_all"; case .forward: "forward" }
        from = out.from.formatted
        to = out.to.map(\.formatted)
        cc = out.cc.isEmpty ? nil : out.cc.map(\.formatted)
        bcc = out.bcc.isEmpty ? nil : out.bcc.map(\.formatted)
        subject = out.subject
        text = out.text
        self.html = html ? out.html : nil
        quoted = out.quoted.map { $0.count > 400 ? String($0.prefix(400)) + "…" : $0 }
        threads = d.threadId != nil
        threadId = d.threadId
        inReplyTo = d.inReplyTo
        references = d.references.isEmpty ? nil : d.references
        signed = d.signatureSplit != nil
        attachments = d.attachments.isEmpty ? nil : d.attachments.map(\.filename)
    }
}

extension MCPServer {
    // MARK: Building mail, the composer's way

    /// A draft built like NMail's composer builds one: `ComposeDraft.make` (identity, signature, reply threading and
    /// Gmail quote), the alias switch, then the text inserted above the signature.
    func draft(_ ctx: Context, _ a: JSON) async throws -> ComposeDraft {
        let replyId = a["reply_to_message_id"]?.string, forwardId = a["forward_message_id"]?.string
        if replyId != nil, forwardId != nil { throw ToolError("Pass reply_to_message_id or forward_message_id, not both.") }
        if let source = replyId ?? forwardId {
            try await ingestMissing(ctx, [source])
            guard try await ctx.store.db.read({ try Message.exists($0, key: source) }) else { throw ToolError("No message \(source).") }
        }
        let kind: ComposeRequest.Kind = if let replyId { .reply(messageId: replyId, all: a["reply_all"]?.bool ?? false) }
            else if let forwardId { .forward(messageId: forwardId) } else { .new(to: []) }
        let sign = a["sign"]?.bool ?? true
        let sendAs = a["send_as"]?.string
        let email = ctx.email
        var d = try await ctx.store.db.read { db in
            let account = try Store.account(db)
            var d = try ComposeDraft.make(kind, db: db, fallbackFrom: EmailAddress(name: account?.name, email: account?.email ?? email), signOnReplies: sign)
            if let sendAs { try Self.switchIdentity(&d, to: sendAs, db: db, account: email) }
            return d
        }
        try Self.fill(&d, a)
        Self.write(&d, a["body"]?.string ?? "", sign: sign)
        return d
    }

    private static func switchIdentity(_ d: inout ComposeDraft, to email: String, db: Database, account: String) throws {
        let identities = try Store.sendAs(db)
        guard let identity = identities.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) else {
            throw ToolError("\(email) isn't a send-as identity of \(account). Identities: \(identities.map(\.email).joined(separator: ", ")).")
        }
        d.switchIdentity(to: identity, signature: try Signature.html(for: identity, db: db))
    }

    /// Recipients and subject given in `a` replace the draft's.
    private static func fill(_ d: inout ComposeDraft, _ a: JSON) throws {
        func addresses(_ key: String) throws -> [EmailAddress]? {
            guard let values = a[key]?.strings else { return nil }
            let parsed = values.flatMap(EmailAddress.parseList)
            if let bad = parsed.first(where: { !$0.email.contains("@") }) { throw ToolError("\"\(bad.email)\" in \(key) isn't an email address.") }
            return parsed
        }
        if let to = try addresses("to") { d.to = to }
        if let cc = try addresses("cc") { d.cc = cc }
        if let bcc = try addresses("bcc") { d.bcc = bcc }
        if let subject = a["subject"]?.string { d.subject = subject }
    }

    /// Sets what was written, above the signature block when signing (as the composer's `insert` does).
    private static func write(_ d: inout ComposeDraft, _ text: String, sign: Bool) {
        d.markdown = true
        guard sign, !d.signature.isEmpty else {
            d.signature = ""
            d.body = text
            return
        }
        d.body = ComposeDraft.signatureBlock(d.signatureText)
        if !text.isEmpty { d.insert(text) }
    }

    /// Everyone the message goes to, for the approval dialog. Recipients come first so truncation never hides one.
    static func summary(_ p: Preview) -> String {
        var lines = ["From: \(p.from)", "To: \(p.to.joined(separator: ", "))"]
        if let cc = p.cc { lines.append("Cc: \(cc.joined(separator: ", "))") }
        if let bcc = p.bcc { lines.append("Bcc: \(bcc.joined(separator: ", "))") }
        lines.append("Subject: \(p.subject)")
        if let files = p.attachments { lines.append("Attachments: \(files.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }

    private static func validateForSending(_ d: ComposeDraft) throws {
        guard !d.recipients.isEmpty else { throw ToolError("Add at least one recipient (to, cc or bcc).") }
        if d.mode == .new, d.subject.trimmingCharacters(in: .whitespaces).isEmpty { throw ToolError("A new message needs a subject.") }
        if d.mode != .forward, d.typedText.isEmpty { throw ToolError("The body is empty.") }
    }

    // MARK: Send

    struct SendResult: Encodable {
        var sent: Bool
        var id: String?
        var threadId: String?
        var preview: Preview?
        var note: String?
    }

    func send(_ args: JSON) async throws -> SendResult {
        let ctx = try context(args)
        let d = try await draft(ctx, args)
        try Self.validateForSending(d)
        guard args["confirm"]?.bool == true else {
            return SendResult(sent: false, preview: Preview(d), note: "Preview only, nothing sent. Call again with confirm:true to send.")
        }
        let gmail = try ctx.requireGmail()
        let preview = Preview(d, html: false)
        try await confirmOnScreen("Send this email?\n\n\(Self.summary(preview))\n\n\(preview.text.prefix(700))")
        let sent = try await Outbox.sendNow(d, store: ctx.store, gmail: gmail)
        return SendResult(sent: true, id: sent.id, threadId: sent.threadId)
    }

    struct BulkItem: Encodable {
        var index: Int
        var ok: Bool
        var id: String?
        var threadId: String?
        var to: [String]?
        var subject: String?
        var preview: Preview?
        var error: String?
    }

    struct BulkResult: Encodable {
        var sent: Int
        var failed: Int
        var confirm: Bool
        var results: [BulkItem]
    }

    func sendBulk(_ args: JSON) async throws -> BulkResult {
        let ctx = try context(args)
        let items = args["messages"]?.array ?? []
        guard !items.isEmpty, items.count <= 50 else { throw ToolError("Pass 1 to 50 messages.") }
        let confirm = args["confirm"]?.bool == true
        var results: [BulkItem] = []
        var drafts: [(index: Int, draft: ComposeDraft)] = []
        for (i, item) in items.enumerated() {
            do {
                let d = try await draft(ctx, item)
                try Self.validateForSending(d)
                drafts.append((i, d))
            } catch {
                results.append(BulkItem(index: i, ok: false, error: error.localizedDescription))
            }
        }
        var sent = 0
        if confirm, !drafts.isEmpty {
            let gmail = try ctx.requireGmail()
            let lines = drafts.map { "• \($0.draft.recipients.map(\.email).joined(separator: ", ").prefix(80)) — \($0.draft.subject.prefix(50))" }
            try await confirmOnScreen("Send \(drafts.count) separate emails from \(ctx.email)?\n\n" + lines.joined(separator: "\n"))
            for (i, d) in drafts {
                do {
                    if sent > 0 { try await Task.sleep(for: sendPacing) }
                    let message = try await Outbox.sendNow(d, store: ctx.store, gmail: gmail)
                    sent += 1
                    results.append(BulkItem(index: i, ok: true, id: message.id, threadId: message.threadId, to: d.to.map(\.email), subject: d.subject))
                } catch {
                    results.append(BulkItem(index: i, ok: false, error: error.localizedDescription))
                }
            }
        } else {
            results += drafts.map { BulkItem(index: $0.index, ok: true, preview: Preview($0.draft, html: false)) }
        }
        results.sort { $0.index < $1.index }
        return BulkResult(sent: sent, failed: results.filter { !$0.ok }.count, confirm: confirm, results: results)
    }

    // MARK: Drafts

    struct DraftResult: Encodable {
        var draftId: String?
        var messageId: String?
        var threadId: String?
        var preview: Preview
    }

    func createDraft(_ args: JSON) async throws -> DraftResult {
        let ctx = try context(args)
        let d = try await draft(ctx, args)
        let saved = try await Outbox.saveDraft(d, store: ctx.store, gmail: try ctx.requireGmail())
        return DraftResult(draftId: saved.draftId, messageId: saved.draftMessageId, threadId: saved.threadId, preview: Preview(saved))
    }

    func updateDraft(_ args: JSON) async throws -> DraftResult {
        let ctx = try context(args)
        guard let id = args["draft_id"]?.string else { throw ToolError("draft_id is required.") }
        let gmail = try ctx.requireGmail()
        if try await ctx.store.db.read({ try Draft.exists($0, key: id) }) == false {
            _ = await freshen(ctx, force: true)
            try await Sync(gmail: gmail, store: ctx.store).syncLabelsAndDrafts()
        }
        let email = ctx.email
        var (d, signed) = try await ctx.store.db.read { db in
            guard let draft = try Draft.fetchOne(db, key: id), try Message.exists(db, key: draft.messageId) else {
                throw ToolError("No draft \(id); list_drafts shows the current ones.")
            }
            var d = try ComposeDraft.make(.draft(id: id), db: db, fallbackFrom: EmailAddress(name: nil, email: email), signOnReplies: true)
            let signed = d.signatureSplit != nil
            if let sendAs = args["send_as"]?.string { try Self.switchIdentity(&d, to: sendAs, db: db, account: email) }
            // `.draft` brings the quoted history back as body text: move it out again, below the new text.
            let (written, quote) = Self.splitQuote(d.typedText)
            d.body = written
            if let inReplyTo = d.inReplyTo, let source = try Message.filter(Column("messageIdHeader") == inReplyTo).fetchOne(db) {
                let reply = OutgoingMessage.reply(to: source, all: false, from: d.from)
                d.quoted = reply.quoted
                d.quotedHTML = reply.quotedHTML
            } else {
                d.quoted = quote
            }
            return (d, signed)
        }
        try Self.fill(&d, args)
        Self.write(&d, args["body"]?.string ?? d.body, sign: args["sign"]?.bool ?? signed)
        let saved = try await Outbox.saveDraft(d, store: ctx.store, gmail: gmail)
        return DraftResult(draftId: saved.draftId, messageId: saved.draftMessageId, threadId: saved.threadId, preview: Preview(saved))
    }

    /// What was written, and the quoted history (a reply's "On … wrote:" block or a forwarded message) below it.
    static func splitQuote(_ text: String) -> (String, String?) {
        if let forward = text.range(of: "---------- Forwarded message ---------") {
            return (String(text[..<forward.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), String(text[forward.lowerBound...]))
        }
        let split = Quote.split(text: text)
        return (split.new, split.quoted)
    }

    struct DraftRow: Encodable {
        var draftId: String
        var messageId: String
        var threadId: String?
        var to: String?
        var subject: String?
        var snippet: String?
        var date: Date?
    }

    func listDrafts(_ args: JSON) async throws -> [String: [DraftRow]] {
        let ctx = try context(args)
        let limit = min(max(args["limit"]?.int ?? 50, 1), 200)
        if let gmail = ctx.gmail {
            _ = await freshen(ctx)
            try await Sync(gmail: gmail, store: ctx.store).syncLabelsAndDrafts()
            try await ingestMissing(ctx, try await ctx.store.db.read { try Store.drafts($0).prefix(limit).map(\.messageId) })
        }
        return ["drafts": try await ctx.store.db.read { db in
            try Store.drafts(db).prefix(limit).map { draft in
                let m = try Message.fetchOne(db, key: draft.messageId)
                return DraftRow(draftId: draft.id, messageId: draft.messageId, threadId: draft.threadId, to: m?.to,
                                subject: m?.subject, snippet: m?.snippet, date: m?.date ?? draft.updatedAt)
            }
        }]
    }

    func deleteDraft(_ args: JSON) async throws -> [String: String] {
        let ctx = try context(args)
        guard let id = args["draft_id"]?.string else { throw ToolError("draft_id is required.") }
        let gmail = try ctx.requireGmail()
        let summary = try await ctx.store.db.read { db in
            try Draft.fetchOne(db, key: id).flatMap { try Message.fetchOne(db, key: $0.messageId) }.map { "To: \($0.to)\nSubject: \($0.subject)" }
        }
        try await confirmOnScreen("Delete this draft in \(ctx.email)? It can't be undone.\n\n\(summary ?? "Draft \(id)")")
        try await gmail.deleteDraft(id)
        try ctx.store.deleteDraft(id: id)
        return ["deleted": id]
    }

    // MARK: Signature, attachments, sync

    struct SignatureResult: Encodable {
        var email: String
        var displayName: String
        var html: String
        var text: String
        var textWithUrls: String
        var identities: [String]
    }

    func getSignature(_ args: JSON) async throws -> SignatureResult {
        let ctx = try context(args)
        let asked = args["send_as"]?.string
        let email = ctx.email
        return try await ctx.store.db.read { db in
            let identities = try Store.sendAs(db)
            let identity = try asked.map { asked in
                guard let match = identities.first(where: { $0.email.caseInsensitiveCompare(asked) == .orderedSame }) else {
                    throw ToolError("\(asked) isn't a send-as identity of \(email). Identities: \(identities.map(\.email).joined(separator: ", ")).")
                }
                return match
            } ?? identities.first(where: \.isDefault) ?? identities.first(where: \.isPrimary) ?? identities.first
            let html = try Signature.html(for: identity, db: db)
            let rendered = Signature.render(html)
            return SignatureResult(email: identity?.email ?? email, displayName: identity?.displayName ?? "", html: html,
                                   text: rendered.text, textWithUrls: rendered.textWithURLs, identities: identities.map(\.email))
        }
    }

    struct DownloadResult: Encodable { var path: String; var filename: String; var mimeType: String; var bytes: Int }

    func downloadAttachment(_ args: JSON) async throws -> DownloadResult {
        let ctx = try context(args)
        guard let messageId = args["message_id"]?.string, let key = args["attachment_id"]?.string else {
            throw ToolError("message_id and attachment_id are required.")
        }
        let path = args["path"]?.string
        try await ingestMissing(ctx, [messageId])
        let attachments = try await ctx.store.db.read { try Attachment.filter(Column("messageId") == messageId).fetchAll($0) }
        guard let a = attachments.first(where: { $0.id == key || $0.partId == key || $0.filename == key }) else {
            throw ToolError("No attachment \(key) on \(messageId). Attachments: \(attachments.map { "\($0.id) (\($0.filename))" }.joined(separator: ", ")).")
        }
        let url = try Self.downloadTarget(path, filename: a.filename, root: .downloadsDirectory)
        if FileManager.default.fileExists(atPath: url.path), args["overwrite"]?.bool != true {
            throw ToolError("\(url.path) exists; pass overwrite:true to replace it.")
        }
        let data: Data
        if let local = a.data { data = local }
        else if let remote = a.gmailAttachmentId { data = try await ctx.requireGmail().attachment(messageId: messageId, id: remote) }
        else { throw ToolError("\(a.filename) has no content to save.") }
        try data.write(to: url, options: .atomic)
        Self.quarantine(url)
        return DownloadResult(path: url.path, filename: a.filename, mimeType: a.mimeType, bytes: data.count)
    }

    /// Where an attachment may be saved: inside `root` (~/Downloads) only, after resolving `..` and symlinks, into a
    /// directory that already exists. Otherwise a malicious email could talk Claude into writing ~/.zshrc or a LaunchAgent.
    static func downloadTarget(_ path: String?, filename: String, root: URL) throws -> URL {
        let root = root.resolvingSymlinksInPath()
        let expanded = ((path ?? "") as NSString).expandingTildeInPath
        var url = (expanded.hasPrefix("/") ? URL(filePath: expanded) : root.appending(path: expanded)).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let name = filename.replacing(/[\/:\x00]/, with: "_")
            url.append(path: [".", ".."].contains(name) || name.isEmpty ? "attachment" : name)
        }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        guard parent.path == root.path || parent.path.hasPrefix(root.path + "/") else {
            throw ToolError("Attachments can only be saved inside \(root.path).")
        }
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ToolError("\(parent.path) doesn't exist; save into an existing folder under \(root.path).")
        }
        return parent.appending(path: url.lastPathComponent)
    }

    /// Marks a saved attachment as downloaded from the internet, so Gatekeeper checks it before it can run.
    static func quarantine(_ url: URL) {
        let value = String(format: "0081;%08x;AxiosM;", Int(Date.now.timeIntervalSince1970))
        _ = url.withUnsafeFileSystemRepresentation { path in
            path.map { setxattr($0, "com.apple.quarantine", value, value.utf8.count, 0, 0) }
        }
    }

    struct SyncResult: Encodable { var history: String; var milliseconds: Int }

    func syncNow(_ args: JSON) async throws -> SyncResult {
        let ctx = try context(args)
        let sync = Sync(gmail: try ctx.requireGmail(), store: ctx.store)
        let start = Date.now
        let resumed = try await sync.incremental()
        try await sync.syncLabelsAndDrafts()
        return SyncResult(history: resumed ? "applied" : "none yet: open AxiosM once for its first full sync",
                          milliseconds: Int(Date.now.timeIntervalSince(start) * 1000))
    }
}
