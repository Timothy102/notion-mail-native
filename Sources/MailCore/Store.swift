import Foundation
import GRDB

/// Previous label sets of the messages a mutation touched, so it can be reverted exactly.
public struct LabelSnapshot: Sendable, Hashable {
    public var labelIds: [String: [String]]
}

public final class Store: Sendable {
    public let db: DatabaseQueue

    /// nil path = in-memory (demo, tests). A file is opened in WAL mode with a 5 s busy timeout, because the
    /// app and the nmail-mcp server open the same database from two processes.
    public init(path: String? = nil) throws {
        if let path {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var config = Configuration()
            config.journalMode = .wal
            config.busyMode = .timeout(5)
            db = try DatabaseQueue(path: path, configuration: config)
        } else {
            db = try DatabaseQueue()
        }
        try Self.migrator.migrate(db)
    }

    public static var defaultPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Mail/mail.sqlite").path
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "accounts") { t in
                t.primaryKey("email", .text)
                t.column("name", .text).notNull()
            }
            try db.create(table: "labels") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("isSystem", .boolean).notNull()
                t.column("color", .text)
            }
            try db.create(table: "threads") { t in
                t.primaryKey("id", .text)
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("participants", .text).notNull()
                t.column("messageCount", .integer).notNull()
                t.column("lastDate", .datetime).notNull().indexed()
                t.column("isUnread", .boolean).notNull()
                t.column("isStarred", .boolean).notNull()
                t.column("hasAttachments", .boolean).notNull()
                t.column("hasDraft", .boolean).notNull()
                t.column("labelIds", .jsonText).notNull()
            }
            try db.create(table: "thread_labels") { t in
                t.column("threadId", .text).notNull().references("threads", onDelete: .cascade)
                t.column("labelId", .text).notNull().indexed()
                t.primaryKey(["threadId", "labelId"])
            }
            try db.create(table: "messages") { t in
                t.primaryKey("id", .text)
                t.column("threadId", .text).notNull().indexed()
                t.column("labelIds", .jsonText).notNull()
                t.column("from", .text).notNull()
                t.column("to", .text).notNull()
                t.column("cc", .text).notNull()
                t.column("bcc", .text).notNull()
                t.column("replyTo", .text).notNull()
                t.column("subject", .text).notNull()
                t.column("snippet", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("internalDate", .integer).notNull()
                t.column("bodyText", .text).notNull()
                t.column("bodyHTML", .text)
                t.column("messageIdHeader", .text).notNull()
                t.column("references", .text).notNull()
                t.column("inReplyTo", .text).notNull()
            }
            try db.create(virtualTable: "messages_fts", using: FTS5()) { t in
                t.synchronize(withTable: "messages")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("subject")
                t.column("from")
                t.column("to")
                t.column("snippet")
                t.column("bodyText")
            }
            try db.create(table: "attachments") { t in
                t.primaryKey("id", .text)
                t.column("messageId", .text).notNull().indexed().references("messages", onDelete: .cascade)
                t.column("partId", .text).notNull()
                t.column("gmailAttachmentId", .text)
                t.column("filename", .text).notNull()
                t.column("mimeType", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("contentId", .text)
                t.column("isInline", .boolean).notNull()
                t.column("data", .blob)
            }
            try db.create(table: "drafts") { t in
                t.primaryKey("id", .text)
                t.column("messageId", .text).notNull()
                t.column("threadId", .text)
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "signatures") { t in
                t.primaryKey("email", .text)
                t.column("displayName", .text).notNull()
                t.column("signature", .text).notNull()
                t.column("isDefault", .boolean).notNull()
                t.column("isPrimary", .boolean).notNull()
                t.column("replyTo", .text)
            }
            try db.create(table: "kv") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.create(table: "notion_links") { t in
                t.column("threadId", .text).notNull().indexed()
                t.column("pageId", .text).notNull()
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.primaryKey(["threadId", "pageId"])
            }
        }
        return m
    }

    // MARK: - Writes

    public func save(account: Account) throws {
        try db.write { try account.upsert($0) }
    }

    public func save(labels: [MailLabel]) throws {
        try db.write { db in for l in labels { try l.upsert(db) } }
    }

    public func save(sendAs: [SendAs]) throws {
        try db.write { db in for s in sendAs { try s.upsert(db) } }
    }

    public func save(draft: Draft) throws {
        try db.write { try draft.upsert($0) }
    }

    public func save(notionLink: NotionLink) throws {
        try db.write { try notionLink.upsert($0) }
    }

    public func deleteDraft(id: String) throws {
        try db.write { db in
            guard let draft = try Draft.fetchOne(db, key: id) else { return }
            try Draft.deleteOne(db, key: id)
            if let m = try Message.fetchOne(db, key: draft.messageId) {
                try Message.deleteOne(db, key: m.id)
                try Self.refreshThread(db, id: m.threadId)
            }
        }
    }

    public func set(_ key: String, _ value: String?) throws {
        try db.write { db in
            if let value { try db.execute(sql: "INSERT OR REPLACE INTO kv(key, value) VALUES (?, ?)", arguments: [key, value]) }
            else { try db.execute(sql: "DELETE FROM kv WHERE key = ?", arguments: [key]) }
        }
    }

    public func get(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM kv WHERE key = ?", arguments: [key]) }
    }

    /// Inserts or replaces messages (and their attachments), then rebuilds the affected threads.
    public func upsert(messages: [Message], attachments: [Attachment] = []) throws {
        try db.write { db in
            for m in messages {
                try m.upsert(db)
                try db.execute(sql: "DELETE FROM attachments WHERE messageId = ?", arguments: [m.id])
            }
            for a in attachments { try a.upsert(db) }
            for id in Set(messages.map(\.threadId)) { try Self.refreshThread(db, id: id) }
        }
    }

    public func deleteMessages(ids: [String]) throws {
        try db.write { db in
            let threadIds = try String.fetchSet(db, Message.select(Column("threadId")).filter(keys: ids))
            try Message.deleteAll(db, keys: ids)
            for id in threadIds { try Self.refreshThread(db, id: id) }
        }
    }

    public func setLabels(messageId: String, _ labelIds: [String]) throws {
        try db.write { db in
            guard var m = try Message.fetchOne(db, key: messageId) else { return }
            m.labelIds = labelIds
            try m.update(db)
            try Self.refreshThread(db, id: m.threadId)
        }
    }

    /// Applies label changes to every message of the given threads. Returns what to pass to `restore` to undo.
    @discardableResult
    public func modify(threadIds: [String], add: Set<String> = [], remove: Set<String> = []) throws -> LabelSnapshot {
        try modify(Message.filter(threadIds.contains(Column("threadId"))), add: add, remove: remove, threads: threadIds)
    }

    /// Like `modify(threadIds:)`, for single messages.
    @discardableResult
    public func modify(messageIds: [String], add: Set<String> = [], remove: Set<String> = []) throws -> LabelSnapshot {
        try modify(Message.filter(keys: messageIds), add: add, remove: remove, threads: [])
    }

    private func modify(_ messages: QueryInterfaceRequest<Message>, add: Set<String>, remove: Set<String>, threads: [String]) throws -> LabelSnapshot {
        try db.write { db in
            var before: [String: [String]] = [:]
            var touched = Set(threads)
            for var m in try messages.fetchAll(db) {
                before[m.id] = m.labelIds
                var labels = Set(m.labelIds)
                labels.subtract(remove)
                labels.formUnion(add)
                m.labelIds = labels.sorted()
                try m.update(db)
                touched.insert(m.threadId)
            }
            for id in touched { try Self.refreshThread(db, id: id) }
            return LabelSnapshot(labelIds: before)
        }
    }

    public func restore(_ snapshot: LabelSnapshot) throws {
        try db.write { db in
            var threads = Set<String>()
            for (id, labels) in snapshot.labelIds {
                guard var m = try Message.fetchOne(db, key: id) else { continue }
                m.labelIds = labels
                try m.update(db)
                threads.insert(m.threadId)
            }
            for id in threads { try Self.refreshThread(db, id: id) }
        }
    }

    static func refreshThread(_ db: Database, id: String) throws {
        let messages = try Message.filter(Column("threadId") == id).order(Column("internalDate")).fetchAll(db)
        guard !messages.isEmpty else {
            try MailThread.deleteOne(db, key: id)
            return
        }
        let sent = messages.filter { !$0.isDraft }
        let shown = sent.isEmpty ? messages : sent
        let last = shown[shown.count - 1]
        let labels = Set(messages.flatMap(\.labelIds))
        let selfEmail = try String.fetchOne(db, sql: "SELECT email FROM accounts LIMIT 1")?.lowercased()
        let attachmentCount = try Attachment
            .filter(messages.map(\.id).contains(Column("messageId")) && Column("isInline") == false).fetchCount(db)
        let thread = MailThread(
            id: id,
            subject: shown[0].subject,
            snippet: last.snippet,
            participants: participants(shown, selfEmail: selfEmail),
            messageCount: sent.count,
            lastDate: last.date,
            isUnread: labels.contains("UNREAD"),
            isStarred: labels.contains("STARRED"),
            hasAttachments: attachmentCount > 0,
            hasDraft: labels.contains("DRAFT"),
            labelIds: labels.sorted()
        )
        try thread.upsert(db)
        try db.execute(sql: "DELETE FROM thread_labels WHERE threadId = ?", arguments: [id])
        for l in labels {
            try db.execute(sql: "INSERT INTO thread_labels(threadId, labelId) VALUES (?, ?)", arguments: [id, l])
        }
    }

    static func participants(_ messages: [Message], selfEmail: String?) -> String {
        var seen: [String] = []
        var names: [String] = []
        for m in messages {
            let a = m.sender
            let key = a.email.lowercased()
            guard !seen.contains(key) else { continue }
            seen.append(key)
            names.append(key == selfEmail ? "me" : a.displayName)
        }
        guard names.count > 1 else { return names.first ?? "" }
        return names.map { $0 == "me" ? $0 : String($0.split(separator: " ").first ?? Substring($0)) }.joined(separator: ", ")
    }

    // MARK: - Reads (pass to `Live` or call inside `db.read`)

    public static func account(_ db: Database) throws -> Account? {
        try Account.fetchOne(db)
    }

    /// Newest first.
    public static func threads(_ db: Database, in mailbox: Mailbox, limit: Int = 500) throws -> [MailThread] {
        if let label = mailbox.labelId {
            return try MailThread.fetchAll(db, sql: """
                SELECT threads.* FROM threads JOIN thread_labels tl ON tl.threadId = threads.id AND tl.labelId = ?
                ORDER BY lastDate DESC LIMIT ?
                """, arguments: [label, limit])
        }
        return try MailThread.fetchAll(db, sql: """
            SELECT * FROM threads WHERE id NOT IN (SELECT threadId FROM thread_labels WHERE labelId IN ('SPAM', 'TRASH'))
            ORDER BY lastDate DESC LIMIT ?
            """, arguments: [limit])
    }

    public static func threadDetail(_ db: Database, id: String) throws -> ThreadDetail? {
        guard let thread = try MailThread.fetchOne(db, key: id) else { return nil }
        let messages = try Message.filter(Column("threadId") == id).order(Column("internalDate")).fetchAll(db)
        let attachments = try Attachment.filter(messages.map(\.id).contains(Column("messageId"))).order(Column("partId")).fetchAll(db)
        return ThreadDetail(
            thread: thread,
            messages: messages,
            attachments: Dictionary(grouping: attachments, by: \.messageId),
            labels: try MailLabel.filter(keys: thread.userLabelIds).order(Column("name")).fetchAll(db),
            notionLinks: try NotionLink.filter(Column("threadId") == id).order(Column("createdAt")).fetchAll(db)
        )
    }

    /// Unread thread count per label id ("INBOX", "STARRED", user labels…). Drafts count all drafts under "DRAFT".
    public static func unreadCounts(_ db: Database) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT tl.labelId, COUNT(*) AS n FROM thread_labels tl JOIN threads t ON t.id = tl.threadId
            WHERE t.isUnread GROUP BY tl.labelId
            """) {
            counts[row["labelId"]] = row["n"]
        }
        counts["DRAFT"] = try Draft.fetchCount(db)
        return counts
    }

    /// User labels, alphabetical.
    public static func labels(_ db: Database) throws -> [MailLabel] {
        try MailLabel.filter(Column("isSystem") == false).order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
    }

    public static func sendAs(_ db: Database) throws -> [SendAs] {
        try SendAs.order(Column("isDefault").desc, Column("isPrimary").desc, Column("email")).fetchAll(db)
    }

    public static func drafts(_ db: Database) throws -> [Draft] {
        try Draft.order(Column("updatedAt").desc).fetchAll(db)
    }

    public static func message(_ db: Database, id: String) throws -> Message? {
        try Message.fetchOne(db, key: id)
    }

    /// Prefix match on every word over subject, from, to, snippet and body. Newest first.
    public static func searchThreads(_ db: Database, text: String, limit: Int = 200) throws -> [MailThread] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }
        return try MailThread.fetchAll(db, sql: """
            SELECT * FROM threads WHERE id IN (
                SELECT m.threadId FROM messages m JOIN messages_fts f ON f.rowid = m.rowid WHERE messages_fts MATCH ?
            ) ORDER BY lastDate DESC LIMIT ?
            """, arguments: [pattern, limit])
    }
}
