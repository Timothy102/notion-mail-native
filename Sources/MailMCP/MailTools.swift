import Foundation
import GRDB
import MailCore

// MARK: - Result shapes (encoded snake_case, dates in local ISO 8601)

struct ThreadRow: Encodable {
    var id: String
    var subject: String
    /// Participants, "me" for the account.
    var from: String
    var date: Date
    var snippet: String
    var labels: [String]
    var unread: Bool
    var starred: Bool?
    var messages: Int
    var hasAttachments: Bool?
}

struct MessageRow: Encodable {
    var id: String
    var threadId: String
    var subject: String
    var from: String
    var to: String
    var date: Date
    var snippet: String
    var labels: [String]
    var unread: Bool
}

struct AttachmentRow: Encodable {
    var id: String
    var filename: String
    var mimeType: String
    var size: Int
    var inline: Bool?
}

struct MessageDetail: Encodable {
    var id: String
    var threadId: String
    var from: String
    var to: String
    var cc: String?
    var date: Date
    var subject: String
    var labels: [String]
    var unread: Bool
    var draft: Bool?
    var body: String
    var attachments: [AttachmentRow]?
    var messageIdHeader: String
    var inReplyTo: String?
}

extension MCPServer {
    static let resultEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(Date.ISO8601FormatStyle(timeZone: .current)))
        }
        return e
    }()

    /// Bodies longer than this are cut, so one newsletter can't flood the context.
    static let maxBodyCharacters = 20_000
    static let maxMatches = 5000

    func call(_ name: String, _ args: JSON) async throws -> String {
        let result: any Encodable = switch name {
        case "list_accounts": listAccounts()
        case "list_labels": try await listLabels(args)
        case "search": try await search(args)
        case "get_thread": try await getThread(args)
        case "get_messages": try await getMessages(args)
        case "modify": try await modify(args)
        case "modify_by_query": try await modifyByQuery(args)
        case "create_draft": try await createDraft(args)
        case "update_draft": try await updateDraft(args)
        case "list_drafts": try await listDrafts(args)
        case "delete_draft": try await deleteDraft(args)
        case "send": try await send(args)
        case "send_bulk": try await sendBulk(args)
        case "get_signature": try await getSignature(args)
        case "download_attachment": try await downloadAttachment(args)
        case "sync": try await syncNow(args)
        default: throw ToolError("Unknown tool: \(name)")
        }
        return String(decoding: try Self.resultEncoder.encode(result), as: UTF8.self)
    }

    // MARK: Accounts and labels

    struct AccountRow: Encodable { var email: String; var name: String?; var active: Bool; var signedIn: Bool }

    func listAccounts() -> [String: [AccountRow]] {
        let r = storage.loadRegistry()
        return ["accounts": r.emails.map {
            AccountRow(email: $0, name: r.names[$0], active: $0 == r.active, signedIn: Secrets.get(Auth.tokenKey($0)) != nil)
        }]
    }

    struct LabelRow: Encodable { var id: String; var name: String; var type: String; var unreadThreads: Int? }

    func listLabels(_ args: JSON) async throws -> [String: [LabelRow]] {
        let ctx = try context(args)
        return ["labels": try await ctx.store.db.read { db in
            let counts = try Store.unreadCounts(db)
            return try MailLabel.order(Column("isSystem").desc, Column("name")).fetchAll(db).map {
                LabelRow(id: $0.id, name: $0.name, type: $0.isSystem ? "system" : "user", unreadThreads: counts[$0.id])
            }
        }]
    }

    // MARK: Search

    struct SearchResult: Encodable {
        var query: String
        var source: String
        var threads: [ThreadRow]?
        var messages: [MessageRow]?
        var nextCursor: String?
        var syncWarning: String?
    }

    func search(_ args: JSON) async throws -> SearchResult {
        let ctx = try context(args)
        let limit = min(max(args["limit"]?.int ?? 25, 1), 200)
        let byMessage = args["granularity"]?.string == "message"
        let q = Self.effectiveQuery(args) ?? "in:inbox"
        let parsed = SearchQuery(q)
        let cursor = args["cursor"]?.string
        var warning = await freshen(ctx)

        if parsed.needsGmail || cursor?.hasPrefix("g:") == true {
            guard let gmail = ctx.gmail else { throw ToolError("\"\(q)\" needs Gmail's own search, and the server is offline.") }
            let page = try await gmail.search(q, pageToken: cursor.map { String($0.dropFirst(2)) }, maxResults: limit)
            let refs = page.messages ?? []
            try await ingestMissing(ctx, refs.map(\.id))
            let ids = refs.map(\.id)
            var result = try await ctx.store.db.read { db in
                let names = try Self.labelNames(db)
                let messages = try Message.fetchAll(db, keys: ids)
                if byMessage { return SearchResult(query: q, source: "gmail", messages: Self.ordered(messages, ids).map { Self.row($0, names) }) }
                var seen = Set<String>()
                let threadIds = Self.ordered(messages, ids).map(\.threadId).filter { seen.insert($0).inserted }
                let threads = try MailThread.fetchAll(db, keys: threadIds)
                return SearchResult(query: q, source: "gmail", threads: Self.ordered(threads, threadIds).map { Self.row($0, names) })
            }
            result.nextCursor = page.nextPageToken.map { "g:" + $0 }
            result.syncWarning = warning
            return result
        }

        let offset = cursor.flatMap(Int.init) ?? 0
        var result = try await localPage(ctx, parsed, byMessage: byMessage, offset: offset, limit: limit)
        let shown = (result.threads?.count ?? 0) + (result.messages?.count ?? 0)
        if cursor == nil, let gmail = ctx.gmail, shown == 0 || (shown < limit && reachesPastWindow(parsed, ctx, gmail)) {
            do {
                let found = try await Sync(gmail: gmail, store: ctx.store).search(q, limit: limit)
                if !found.isEmpty {
                    result = try await localPage(ctx, parsed, byMessage: byMessage, offset: 0, limit: limit)
                    result.source = "local+gmail"
                }
            } catch {
                warning = [warning, "Gmail search failed: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: " ")
            }
        }
        result.syncWarning = warning
        return result
    }

    private func localPage(_ ctx: Context, _ parsed: SearchQuery, byMessage: Bool, offset: Int, limit: Int) async throws -> SearchResult {
        try await ctx.store.db.read { db in
            let names = try Self.labelNames(db)
            let window = offset + limit + 1
            var result = SearchResult(query: parsed.raw, source: "local")
            let more: Bool
            if byMessage {
                let found = try Store.searchMessages(db, parsed, limit: window)
                result.messages = found.dropFirst(offset).prefix(limit).map { Self.row($0, names) }
                more = found.count == window
            } else {
                let found = try Store.search(db, parsed, limit: window)
                result.threads = found.dropFirst(offset).prefix(limit).map { Self.row($0.thread, names) }
                more = found.count == window
            }
            result.nextCursor = more ? String(offset + limit) : nil
            return result
        }
    }

    /// Whether Gmail may hold matches NMail never synced: the query isn't inbox-only (the whole inbox is synced)
    /// and reaches before the backfilled window.
    private func reachesPastWindow(_ q: SearchQuery, _ ctx: Context, _ gmail: GmailClient) -> Bool {
        let months = Sync(gmail: gmail, store: ctx.store).backfilledMonths
        let start = Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        let inboxOnly = q.labels.contains { $0.lowercased() == "inbox" }
        return !inboxOnly && (q.after.map { $0 < start } ?? true)
    }

    /// `query` plus the `mailbox` as an operator; nil when both are empty.
    static func effectiveQuery(_ args: JSON) -> String? {
        var q = args["query"]?.string ?? ""
        if let box = args["mailbox"]?.string?.trimmingCharacters(in: .whitespaces), !box.isEmpty {
            switch box.lowercased() {
            case "all", "all mail", "anywhere": break
            case "starred": q += " is:starred"
            case let system where ["inbox", "sent", "drafts", "draft", "spam", "trash"].contains(system): q += " in:\(system)"
            default: q += " label:\"\(box)\""
            }
        }
        q = q.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? nil : q
    }

    // MARK: Reading

    struct ThreadResult: Encodable {
        var id: String
        var subject: String
        var labels: [String]
        var messages: [MessageDetail]
        var syncWarning: String?
    }

    func getThread(_ args: JSON) async throws -> ThreadResult {
        let ctx = try context(args)
        guard let id = args["thread_id"]?.string else { throw ToolError("thread_id is required.") }
        let includeQuoted = args["include_quoted"]?.bool ?? false
        let warning = await freshen(ctx)
        if try await ctx.store.db.read({ try MailThread.fetchOne($0, key: id) }) == nil, let gmail = ctx.gmail {
            try Sync(gmail: gmail, store: ctx.store).ingest(try await gmail.thread(id).messages ?? [])
        }
        return try await ctx.store.db.read { db in
            guard let detail = try Store.threadDetail(db, id: id) else { throw ToolError("No thread \(id).") }
            let names = try Self.labelNames(db)
            return ThreadResult(id: id, subject: detail.thread.subject, labels: Self.shown(detail.thread.labelIds, names),
                                messages: detail.messages.map { Self.detail($0, detail.attachments[$0.id] ?? [], names, includeQuoted: includeQuoted) },
                                syncWarning: warning)
        }
    }

    struct MessagesResult: Encodable {
        var messages: [MessageDetail]
        var notFound: [String]?
        var syncWarning: String?
    }

    func getMessages(_ args: JSON) async throws -> MessagesResult {
        let ctx = try context(args)
        let ids = args["ids"]?.strings ?? []
        guard !ids.isEmpty, ids.count <= 100 else { throw ToolError("Pass 1 to 100 message ids.") }
        let includeQuoted = args["include_quoted"]?.bool ?? false
        let warning = await freshen(ctx)
        try await ingestMissing(ctx, ids)
        return try await ctx.store.db.read { db in
            let names = try Self.labelNames(db)
            let messages = Self.ordered(try Message.fetchAll(db, keys: ids), ids)
            let attachments = Dictionary(grouping: try Attachment.filter(ids.contains(Column("messageId"))).order(Column("partId")).fetchAll(db), by: \.messageId)
            let missing = Set(ids).subtracting(messages.map(\.id))
            return MessagesResult(messages: messages.map { Self.detail($0, attachments[$0.id] ?? [], names, includeQuoted: includeQuoted) },
                                  notFound: missing.isEmpty ? nil : ids.filter(missing.contains), syncWarning: warning)
        }
    }

    /// Fetches the ids NMail doesn't have from Gmail into the store (no-op offline).
    func ingestMissing(_ ctx: Context, _ ids: [String]) async throws {
        guard let gmail = ctx.gmail, !ids.isEmpty else { return }
        let known = try await ctx.store.db.read { try String.fetchSet($0, Message.select(Column("id")).filter(keys: ids)) }
        let missing = ids.filter { !known.contains($0) }
        if !missing.isEmpty { try Sync(gmail: gmail, store: ctx.store).ingest(try await gmail.messages(missing)) }
    }

    // MARK: Modify

    struct ModifyResult: Encodable {
        var action: String
        var dryRun: Bool?
        var query: String?
        var threads: Int
        var messages: Int
        var capped: Bool?
        var notFound: [String]?
        var sampleThreads: [ThreadRow]?
        var sampleMessages: [MessageRow]?
        var note: String?
    }

    func modify(_ args: JSON) async throws -> ModifyResult {
        let ctx = try context(args)
        let ids = args["ids"]?.strings ?? []
        guard !ids.isEmpty, ids.count <= 1000 else { throw ToolError("Pass 1 to 1000 ids.") }
        let action = args["action"]?.string ?? ""
        let (add, remove) = try await labelChange(action, args["labels"]?.strings ?? [], ctx)
        let gmail = try ctx.requireGmail()
        let byMessage = args["target"]?.string == "message"

        var messageIds: [String] = []
        var threadIds = Set<String>()
        var notFound: [String] = []
        if byMessage {
            messageIds = ids
            threadIds = try await ctx.store.db.read { try String.fetchSet($0, Message.select(Column("threadId")).filter(keys: ids)) }
        } else {
            let local = try await Self.messageIds(ctx, threads: ids)
            for id in ids {
                if let known = local[id] {
                    messageIds += known
                } else {
                    do { messageIds += (try await gmail.thread(id, format: .minimal).messages ?? []).map(\.id) }
                    catch let e as GmailError where e.status == 404 { notFound.append(id); continue }
                }
                threadIds.insert(id)
            }
        }
        try await apply(ctx, gmail, messageIds, add: add, remove: remove)
        return ModifyResult(action: action, threads: threadIds.count, messages: messageIds.count, notFound: notFound.isEmpty ? nil : notFound)
    }

    func modifyByQuery(_ args: JSON) async throws -> ModifyResult {
        let ctx = try context(args)
        guard let q = Self.effectiveQuery(args) else { throw ToolError("Pass a query or a mailbox.") }
        let action = args["action"]?.string ?? ""
        let (add, remove) = try await labelChange(action, args["labels"]?.strings ?? [], ctx)
        let dryRun = args["dry_run"]?.bool ?? true
        let byMessage = args["target"]?.string == "message"
        let parsed = SearchQuery(q)

        // Matching messages, newest first, as (id, threadId).
        var matches: [(id: String, threadId: String)] = []
        var capped = false
        if let gmail = ctx.gmail {
            var pageToken: String?
            repeat {
                let page = try await gmail.listMessages(q: q, pageToken: pageToken, maxResults: 500, includeSpamTrash: parsed.includesSpamAndTrash)
                matches += (page.messages ?? []).map { ($0.id, $0.threadId ?? $0.id) }
                pageToken = page.nextPageToken
            } while pageToken != nil && matches.count <= Self.maxMatches
            capped = pageToken != nil || matches.count > Self.maxMatches
        } else {
            matches = try await ctx.store.db.read { db in
                if byMessage { return try Store.searchMessages(db, parsed, limit: Self.maxMatches + 1).map { ($0.id, $0.threadId) } }
                let threads = try Store.search(db, parsed, limit: Self.maxMatches + 1).map(\.thread.id)
                return try Message.filter(threads.contains(Column("threadId"))).order(Column("internalDate").desc).fetchAll(db).map { ($0.id, $0.threadId) }
            }
            capped = matches.count > Self.maxMatches
        }
        matches = Array(matches.prefix(Self.maxMatches))

        var seen = Set<String>()
        let threadIds = matches.map(\.threadId).filter { seen.insert($0).inserted }
        var messageIds = matches.map(\.id)
        if !byMessage {
            let local = try await Self.messageIds(ctx, threads: threadIds)
            var all = Set(messageIds)
            for ids in local.values { for id in ids where all.insert(id).inserted { messageIds.append(id) } }
        }
        var result = ModifyResult(action: action, dryRun: dryRun, query: q, threads: threadIds.count, messages: messageIds.count,
                                  capped: capped)

        if dryRun {
            let sampleIds = byMessage ? Array(matches.prefix(10).map(\.id))
                : matches.reduce(into: [(String, String)]()) { acc, m in if acc.count < 10, !acc.contains(where: { $0.1 == m.threadId }) { acc.append(m) } }.map(\.0)
            try await ingestMissing(ctx, sampleIds)
            let sampleThreadIds = Array(threadIds.prefix(10))
            (result.sampleThreads, result.sampleMessages) = try await ctx.store.db.read { db in
                let names = try Self.labelNames(db)
                if byMessage { return (nil, Self.ordered(try Message.fetchAll(db, keys: sampleIds), sampleIds).map { Self.row($0, names) }) }
                return (Self.ordered(try MailThread.fetchAll(db, keys: sampleThreadIds), sampleThreadIds).map { Self.row($0, names) }, nil)
            }
            result.note = "Dry run: nothing changed. Call again with dry_run:false to \(action) these."
                + (capped ? " More than \(Self.maxMatches) messages match; one call acts on the newest \(Self.maxMatches)." : "")
            return result
        }
        let gmail = try ctx.requireGmail()
        try await apply(ctx, gmail, messageIds, add: add, remove: remove)
        if capped { result.note = "More mail matches; call again to continue." }
        return result
    }

    /// Gmail's batchModify in chunks of 1000, each mirrored into the store once Gmail accepted it.
    /// Trash and Spam (by action or by `add_labels`) need Tim's on-screen OK first.
    private func apply(_ ctx: Context, _ gmail: GmailClient, _ messageIds: [String], add: Set<String>, remove: Set<String>) async throws {
        if !messageIds.isEmpty, let bin = add.contains("SPAM") ? "Spam" : add.contains("TRASH") ? "Trash" : nil {
            let samples = try await ctx.store.db.read { db in
                try Message.fetchAll(db, keys: Array(messageIds.prefix(8))).map { "• \($0.from.prefix(40)) — \($0.subject.prefix(60))" }
            }
            try await confirmOnScreen("Move \(messageIds.count) message(s) in \(ctx.email) to \(bin)?\n\n" + samples.joined(separator: "\n"))
        }
        for start in stride(from: 0, to: messageIds.count, by: 1000) {
            let chunk = Array(messageIds[start..<min(start + 1000, messageIds.count)])
            try await gmail.batchModify(messageIds: chunk, add: add.sorted(), remove: remove.sorted())
            try ctx.store.modify(messageIds: chunk, add: add, remove: remove)
        }
    }

    /// The label ids an action adds and removes.
    func labelChange(_ action: String, _ labels: [String], _ ctx: Context) async throws -> (add: Set<String>, remove: Set<String>) {
        switch action {
        case "archive": return ([], ["INBOX"])
        case "unarchive": return (["INBOX"], [])
        case "mark_read": return ([], ["UNREAD"])
        case "mark_unread": return (["UNREAD"], [])
        case "star": return (["STARRED"], [])
        case "unstar": return ([], ["STARRED"])
        case "trash": return (["TRASH"], ["INBOX"])
        case "untrash": return (["INBOX"], ["TRASH"])
        case "spam": return (["SPAM"], ["INBOX"])
        case "add_labels", "remove_labels":
            guard !labels.isEmpty else { throw ToolError("\(action) needs `labels`.") }
            let known = try await ctx.store.db.read { try MailLabel.fetchAll($0) }
            var ids = Set<String>(), unknown: [String] = []
            for name in labels {
                if let l = known.first(where: { $0.id == name || $0.name.caseInsensitiveCompare(name) == .orderedSame }) { ids.insert(l.id) }
                else if MailLabel.systemIds.contains(name.uppercased()) { ids.insert(name.uppercased()) }
                else { unknown.append(name) }
            }
            guard unknown.isEmpty else {
                throw ToolError("Unknown label(s): \(unknown.joined(separator: ", ")). Existing labels: \(known.filter { !$0.isSystem }.map(\.name).joined(separator: ", ")).")
            }
            return action == "add_labels" ? (ids, []) : ([], ids)
        default:
            throw ToolError("Unknown action \"\(action)\". One of: \(Tools.actions.joined(separator: ", ")).")
        }
    }

    /// Local message ids per thread id, for the threads NMail has.
    static func messageIds(_ ctx: Context, threads: [String]) async throws -> [String: [String]] {
        try await ctx.store.db.read { db in
            try Row.fetchAll(db, Message.select(Column("id"), Column("threadId")).filter(threads.contains(Column("threadId"))).asRequest(of: Row.self))
                .reduce(into: [:]) { acc, row in acc[row["threadId"] as String, default: []].append(row["id"]) }
        }
    }

    // MARK: Rows

    static func labelNames(_ db: Database) throws -> [String: String] {
        Dictionary(try MailLabel.filter(Column("isSystem") == false).fetchAll(db).map { ($0.id, $0.name) }) { a, _ in a }
    }

    /// Label names for display; unread and starred have their own fields.
    static func shown(_ ids: [String], _ names: [String: String]) -> [String] {
        ids.filter { $0 != "UNREAD" && $0 != "STARRED" }.map { names[$0] ?? $0 }
    }

    static func row(_ t: MailThread, _ names: [String: String]) -> ThreadRow {
        ThreadRow(id: t.id, subject: t.subject, from: t.participants, date: t.lastDate, snippet: t.snippet, labels: shown(t.labelIds, names),
                  unread: t.isUnread, starred: t.isStarred ? true : nil, messages: t.messageCount, hasAttachments: t.hasAttachments ? true : nil)
    }

    static func row(_ m: Message, _ names: [String: String]) -> MessageRow {
        MessageRow(id: m.id, threadId: m.threadId, subject: m.subject, from: m.from, to: m.to, date: m.date, snippet: m.snippet,
                   labels: shown(m.labelIds, names), unread: m.isUnread)
    }

    static func detail(_ m: Message, _ attachments: [Attachment], _ names: [String: String], includeQuoted: Bool) -> MessageDetail {
        let files = attachments.map { AttachmentRow(id: $0.id, filename: $0.filename, mimeType: $0.mimeType, size: $0.size, inline: $0.isInline ? true : nil) }
        return MessageDetail(id: m.id, threadId: m.threadId, from: m.from, to: m.to, cc: m.cc.isEmpty ? nil : m.cc, date: m.date,
                             subject: m.subject, labels: shown(m.labelIds, names), unread: m.isUnread, draft: m.isDraft ? true : nil,
                             body: body(m, includeQuoted: includeQuoted), attachments: files.isEmpty ? nil : files,
                             messageIdHeader: m.messageIdHeader, inReplyTo: m.inReplyTo.isEmpty ? nil : m.inReplyTo)
    }

    /// Plain text, quoted history cut (text quotes first, then Gmail/Outlook HTML quote containers).
    static func body(_ m: Message, includeQuoted: Bool) -> String {
        var text = m.bodyText
        if !includeQuoted {
            let split = Quote.split(text: text)
            if split.quoted != nil { text = split.new }
            else if let html = m.bodyHTML, case let (new, quoted?) = Quote.split(html: html), !quoted.isEmpty { text = MIME.plainText(fromHTML: new) }
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxBodyCharacters else { return text }
        return String(text.prefix(maxBodyCharacters)) + "\n…[cut \(text.count - maxBodyCharacters) characters]"
    }

    /// `items` in the order of `ids`.
    static func ordered<T: Identifiable>(_ items: [T], _ ids: [String]) -> [T] where T.ID == String {
        let byId = Dictionary(items.map { ($0.id, $0) }) { a, _ in a }
        return ids.compactMap { byId[$0] }
    }
}
