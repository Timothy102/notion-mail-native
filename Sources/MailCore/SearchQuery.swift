import Foundation
import GRDB

/// A Gmail-style query parsed for the local index:
/// `from:ana subject:"q4 plan" has:attachment is:unread label:work -newsletter after:2026/03/01`.
///
/// Operators the local index can't answer (OR, size:, filename:, braces…) land in `unsupported`,
/// which sends the raw text to Gmail's own search instead.
public struct SearchQuery: Sendable, Equatable {
    public enum Field: String, Sendable { case from, to, subject }

    /// Words or a quoted phrase, optionally limited to one field.
    public struct Match: Sendable, Equatable {
        public var field: Field?
        public var text: String
        public var isPhrase: Bool

        public init(_ text: String, field: Field? = nil, isPhrase: Bool = false) {
            self.text = text
            self.field = field
            self.isPhrase = isPhrase
        }
    }

    public var raw: String
    public var include: [Match] = []
    public var exclude: [Match] = []
    /// Label names or ids ("work", "Label_1", "INBOX"), matched case-insensitively.
    public var labels: [String] = []
    public var excludedLabels: [String] = []
    public var isUnread: Bool?
    public var isStarred: Bool?
    public var hasAttachment: Bool?
    public var after: Date?
    public var before: Date?
    /// `in:anywhere`, `in:spam` or `in:trash` lift the default exclusion of spam and trash.
    public var includesSpamAndTrash = false
    public var unsupported: [String] = []

    public var needsGmail: Bool { !unsupported.isEmpty }

    public var isEmpty: Bool {
        include.isEmpty && exclude.isEmpty && labels.isEmpty && excludedLabels.isEmpty && isUnread == nil
            && isStarred == nil && hasAttachment == nil && after == nil && before == nil && unsupported.isEmpty
    }

    /// Words to highlight in subjects and snippets: free text and `subject:` terms.
    public var highlightTerms: [String] {
        include.filter { $0.field != .from && $0.field != .to }
            .flatMap { $0.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
    }

    public init(_ raw: String, now: Date = .now, calendar: Calendar = .current) {
        self.raw = raw
        for token in Self.tokenize(raw) { apply(token, now: now, calendar: calendar) }
    }

    private struct Token { var negated: Bool; var op: String?; var value: String; var quoted: Bool }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        func readValue() -> (String, Bool) {
            if i < s.endIndex, s[i] == "\"" {
                let start = s.index(after: i)
                let end = s[start...].firstIndex(of: "\"") ?? s.endIndex
                i = end < s.endIndex ? s.index(after: end) : end
                return (String(s[start..<end]), true)
            }
            let start = i
            while i < s.endIndex, !s[i].isWhitespace { i = s.index(after: i) }
            return (String(s[start..<i]), false)
        }
        while i < s.endIndex {
            if s[i].isWhitespace { i = s.index(after: i); continue }
            var negated = false
            if s[i] == "-", s.index(after: i) < s.endIndex, !s[s.index(after: i)].isWhitespace {
                negated = true
                i = s.index(after: i)
            }
            var op: String?
            if s[i] != "\"", let colon = s[i...].prefix(while: { !$0.isWhitespace && $0 != "\"" }).firstIndex(of: ":"),
               colon > i, s[i..<colon].allSatisfy({ $0.isLetter || $0 == "_" }) {
                op = s[i..<colon].lowercased()
                i = s.index(after: colon)
            }
            let (value, quoted) = readValue()
            if value.isEmpty, op == nil, !quoted { continue }
            tokens.append(Token(negated: negated, op: op, value: value, quoted: quoted))
        }
        return tokens
    }

    private mutating func apply(_ t: Token, now: Date, calendar: Calendar) {
        let value = t.value.lowercased()
        let original = (t.negated ? "-" : "") + (t.op.map { $0 + ":" } ?? "") + (t.quoted ? "\"\(t.value)\"" : t.value)
        switch t.op {
        case nil:
            if !t.quoted, ["OR", "AND", "AROUND"].contains(t.value) || t.value.contains(where: { "{}()".contains($0) }) {
                unsupported.append(original)
            } else {
                match(t, nil)
            }
        case "from": match(t, .from)
        case "to", "cc", "bcc": match(t, .to)
        case "subject": match(t, .subject)
        case "label", "in":
            switch value {
            case "anywhere", "all":
                includesSpamAndTrash = true
            case "spam", "trash":
                includesSpamAndTrash = true
                fallthrough
            default:
                if t.negated { excludedLabels.append(t.value) } else { labels.append(t.value) }
            }
        case "is":
            switch value {
            case "unread": isUnread = !t.negated
            case "read": isUnread = t.negated
            case "starred": isStarred = !t.negated
            case "unstarred": isStarred = t.negated
            case "important", "sent", "draft", "inbox":
                if t.negated { excludedLabels.append(value) } else { labels.append(value) }
            default: unsupported.append(original)
            }
        case "has":
            if value == "attachment" { hasAttachment = !t.negated } else { unsupported.append(original) }
        case "before", "after", "older", "newer", "older_than", "newer_than":
            guard !t.negated, let date = Self.date(value, op: t.op!, now: now, calendar: calendar) else {
                unsupported.append(original)
                return
            }
            if t.op == "after" || t.op == "newer" || t.op == "newer_than" { after = date } else { before = date }
        case let op? where Self.gmailOnlyOperators.contains(op):
            unsupported.append(original)
        default:
            match(Token(negated: t.negated, op: nil, value: "\(t.op ?? ""):\(t.value)", quoted: t.quoted), nil)
        }
    }

    private static let gmailOnlyOperators: Set = ["filename", "size", "larger", "smaller", "list", "category", "deliveredto",
                                                   "rfc822msgid", "around", "has", "is"]

    private mutating func match(_ t: Token, _ field: Field?) {
        let m = Match(t.value, field: field, isPhrase: t.quoted)
        if t.negated { exclude.append(m) } else { include.append(m) }
    }

    /// "2026/03/01", "2026-3-1", "03/01/2026", epoch seconds, or for *_than: "7d", "2m", "1y".
    private static func date(_ s: String, op: String, now: Date, calendar: Calendar) -> Date? {
        if op.hasSuffix("_than") {
            guard let unit = s.last, let n = Int(s.dropLast()) else { return nil }
            let component: Calendar.Component
            switch unit {
            case "d": component = .day
            case "m": component = .month
            case "y": component = .year
            default: return nil
            }
            return calendar.date(byAdding: component, value: -n, to: now)
        }
        if s.allSatisfy(\.isNumber), let seconds = TimeInterval(s), s.count > 8 { return Date(timeIntervalSince1970: seconds) }
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (y, m, d) = parts[0] > 31 ? (parts[0], parts[1], parts[2]) : (parts[2], parts[0], parts[1])
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}

// MARK: - Local search

/// One thread matching a search, with the body excerpt around the hit when the match was in the body.
public struct SearchHit: Sendable, Hashable, Identifiable {
    public var thread: MailThread
    public var excerpt: String?
    public var id: String { thread.id }

    public init(thread: MailThread, excerpt: String? = nil) {
        self.thread = thread
        self.excerpt = excerpt
    }
}

public enum SearchOrder: Sendable { case date, relevance }

extension Store {
    /// Runs the parsed query over the FTS5 index. `.relevance` ranks by BM25 (subject 10, from 5, to 3, snippet and body 1).
    public static func search(_ db: Database, _ query: SearchQuery, order: SearchOrder = .date, limit: Int = 200) throws -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var arguments: StatementArguments = []
        var messageFilters: [String] = []
        if let after = query.after {
            messageFilters.append("m.date >= ?")
            arguments += [after]
        }
        if let before = query.before {
            messageFilters.append("m.date < ?")
            arguments += [before]
        }

        let positive = ftsExpression(query.include)
        let hits: String
        if let positive {
            hits = """
                WITH scored AS MATERIALIZED (
                    SELECT m.threadId, bm25(messages_fts, 10.0, 5.0, 3.0, 1.0, 1.0) AS score,
                           snippet(messages_fts, 4, char(1), char(2), '…', 14) AS excerpt
                    FROM messages_fts JOIN messages m ON m.rowid = messages_fts.rowid
                    WHERE messages_fts MATCH ?\(messageFilters.map { " AND " + $0 }.joined())
                )
                SELECT threadId, MIN(score) AS score, excerpt FROM scored GROUP BY threadId
                """
            arguments = [positive] + arguments
        } else {
            let filter = messageFilters.isEmpty ? "" : " WHERE " + messageFilters.joined(separator: " AND ")
            hits = "SELECT DISTINCT m.threadId AS threadId, 0.0 AS score, NULL AS excerpt FROM messages m\(filter)"
        }

        var threadFilters: [String] = []
        if let negative = ftsExpression(query.exclude, joinedBy: " OR ") {
            threadFilters.append("t.id NOT IN (SELECT m.threadId FROM messages_fts JOIN messages m ON m.rowid = messages_fts.rowid WHERE messages_fts MATCH ?)")
            arguments += [negative]
        }
        let allLabels = try MailLabel.fetchAll(db)
        for name in query.labels {
            threadFilters.append("t.id IN (SELECT threadId FROM thread_labels WHERE labelId IN \(sqlList(labelIds(name, allLabels))))")
        }
        for name in query.excludedLabels {
            threadFilters.append("t.id NOT IN (SELECT threadId FROM thread_labels WHERE labelId IN \(sqlList(labelIds(name, allLabels))))")
        }
        if !query.includesSpamAndTrash {
            threadFilters.append("t.id NOT IN (SELECT threadId FROM thread_labels WHERE labelId IN ('SPAM', 'TRASH'))")
        }
        if let v = query.isUnread { threadFilters.append("t.isUnread = \(v ? 1 : 0)") }
        if let v = query.isStarred { threadFilters.append("t.isStarred = \(v ? 1 : 0)") }
        if let v = query.hasAttachment { threadFilters.append("t.hasAttachments = \(v ? 1 : 0)") }

        let orderBy = order == .relevance ? "hits.score, t.lastDate DESC" : "t.lastDate DESC"
        let sql = """
            SELECT t.*, hits.excerpt AS excerpt FROM threads t JOIN (\(hits)) hits ON hits.threadId = t.id
            \(threadFilters.isEmpty ? "" : "WHERE " + threadFilters.joined(separator: " AND "))
            ORDER BY \(orderBy) LIMIT ?
            """
        arguments += [limit]
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            let excerpt: String? = row["excerpt"]
            return SearchHit(thread: try MailThread(row: row), excerpt: excerpt.flatMap(Self.bodyExcerpt))
        }
    }

    /// Like `search`, one row per matching message rather than per thread (labels, unread and attachments
    /// are the message's own). Newest first.
    public static func searchMessages(_ db: Database, _ query: SearchQuery, limit: Int = 200) throws -> [Message] {
        guard !query.isEmpty else { return [] }
        var filters: [String] = []
        var arguments: StatementArguments = []
        if let positive = ftsExpression(query.include) {
            filters.append("m.rowid IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)")
            arguments += [positive]
        }
        if let negative = ftsExpression(query.exclude, joinedBy: " OR ") {
            filters.append("m.rowid NOT IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)")
            arguments += [negative]
        }
        if let after = query.after {
            filters.append("m.date >= ?")
            arguments += [after]
        }
        if let before = query.before {
            filters.append("m.date < ?")
            arguments += [before]
        }
        let allLabels = try MailLabel.fetchAll(db)
        func has(_ ids: [String], _ yes: Bool = true) -> String {
            (yes ? "" : "NOT ") + "EXISTS (SELECT 1 FROM json_each(m.labelIds) WHERE value IN \(sqlList(ids)))"
        }
        filters += query.labels.map { has(labelIds($0, allLabels)) }
        filters += query.excludedLabels.map { has(labelIds($0, allLabels), false) }
        if !query.includesSpamAndTrash { filters.append(has(["SPAM", "TRASH"], false)) }
        if let v = query.isUnread { filters.append(has(["UNREAD"], v)) }
        if let v = query.isStarred { filters.append(has(["STARRED"], v)) }
        if let v = query.hasAttachment {
            filters.append((v ? "" : "NOT ") + "EXISTS (SELECT 1 FROM attachments a WHERE a.messageId = m.id AND NOT a.isInline)")
        }
        arguments += [limit]
        return try Message.fetchAll(db, sql: """
            SELECT m.* FROM messages m \(filters.isEmpty ? "" : "WHERE " + filters.joined(separator: " AND "))
            ORDER BY m.internalDate DESC LIMIT ?
            """, arguments: arguments)
    }

    /// Threads by id, newest first: what Gmail's search returned once ingested.
    public static func threads(_ db: Database, ids: [String]) throws -> [MailThread] {
        try MailThread.filter(keys: ids).order(Column("lastDate").desc).fetchAll(db)
    }

    /// People whose name or address starts with `prefix`, most-mailed first. Excludes the account itself.
    public static func contacts(_ db: Database, matching prefix: String, limit: Int = 3) throws -> [EmailAddress] {
        let folded = prefix.trimmingCharacters(in: .whitespaces).searchFolded
        guard let pattern = ftsExpression([SearchQuery.Match(prefix)]), !folded.isEmpty else { return [] }
        let me = try String.fetchOne(db, sql: "SELECT email FROM accounts LIMIT 1")?.lowercased()
        let rows = try Row.fetchAll(db, sql: """
            SELECT m."from", m."to", m.cc FROM messages_fts JOIN messages m ON m.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ? ORDER BY m.internalDate DESC LIMIT 400
            """, arguments: ["{from to} : (\(pattern))"])
        var counts: [String: (address: EmailAddress, count: Int)] = [:]
        for row in rows {
            for column in ["from", "to", "cc"] {
                for a in EmailAddress.parseList(row[column] ?? "") {
                    let key = a.email.lowercased()
                    guard key != me else { continue }
                    let words = [a.email] + (a.name ?? "").split(separator: " ").map(String.init)
                    guard words.contains(where: { $0.searchFolded.hasPrefix(folded) }) || (a.name ?? "").searchFolded.hasPrefix(folded) else { continue }
                    var entry = counts[key] ?? (a, 0)
                    if entry.address.name == nil, a.name != nil { entry.address = a }
                    entry.count += 1
                    counts[key] = entry
                }
            }
        }
        return counts.values.sorted { ($0.count, $1.address.email) > ($1.count, $0.address.email) }.prefix(limit).map(\.address)
    }

    /// FTS5 MATCH expression: each match as a prefix phrase (exact for quoted phrases), AND-ed by default.
    static func ftsExpression(_ matches: [SearchQuery.Match], joinedBy separator: String = " AND ") -> String? {
        let parts = matches.compactMap { m -> String? in
            guard m.text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            let phrase = "\"" + m.text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" + (m.isPhrase ? "" : "*")
            return m.field.map { "{\($0.rawValue)} : \(phrase)" } ?? phrase
        }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    private static func labelIds(_ name: String, _ labels: [MailLabel]) -> [String] {
        let key = name.searchFolded == "drafts" ? "draft" : name.searchFolded
        let dashed = { (s: String) in s.searchFolded.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-") }
        let ids = labels.filter { $0.id.lowercased() == key || $0.name.searchFolded == key || dashed($0.name) == dashed(key) }.map(\.id)
        return ids.isEmpty ? [key.uppercased()] : ids
    }

    private static func sqlList(_ values: [String]) -> String {
        "(" + values.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" }.joined(separator: ", ") + ")"
    }

    /// FTS snippet with its \u{1}…\u{2} markers removed, or nil when the hit wasn't in the body.
    private static func bodyExcerpt(_ snippet: String) -> String? {
        guard snippet.contains("\u{1}") else { return nil }
        return snippet.replacingOccurrences(of: "\u{1}", with: "").replacingOccurrences(of: "\u{2}", with: "")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

// MARK: - Gmail fallback

extension Sync {
    /// Gmail's own search, for queries the local index can't answer or that found nothing locally.
    /// Ingests matching messages that haven't been synced and returns their thread ids.
    public func search(_ q: String, limit: Int = 50) async throws -> [String] {
        let refs = try await gmail.search(q, maxResults: limit).messages ?? []
        let ids = refs.map(\.id)
        let known = try await store.db.read { try String.fetchSet($0, Message.select(Column("id")).filter(keys: ids)) }
        try ingest(try await gmail.messages(ids.filter { !known.contains($0) }))
        let threadIds = try await store.db.read { db in
            try refs.compactMap { try $0.threadId ?? String.fetchOne(db, Message.select(Column("threadId")).filter(key: $0.id)) }
        }
        var seen = Set<String>()
        return threadIds.filter { seen.insert($0).inserted }
    }
}

// MARK: - Highlighting and fuzzy matching

extension String {
    /// Case- and diacritic-insensitive form used for matching.
    public var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

public enum SearchText {
    /// Ranges of whole words in `text` that start with one of `terms` (the same prefix rule as the index).
    public static func marks(in text: String, terms: [String]) -> [Range<String.Index>] {
        let folded = terms.map(\.searchFolded).filter { !$0.isEmpty }
        guard !folded.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
            guard let word = word?.searchFolded else { return }
            if folded.contains(where: word.hasPrefix) { ranges.append(range) }
        }
        return ranges
    }

    /// Fuzzy score of `query` in `candidate`, higher is better; nil when it doesn't match. Matches a
    /// substring anywhere, or a subsequence whose characters each start a word or continue the previous
    /// match, so "gs" finds "Go to Sent" and "arch" finds "Archive" but "gs" skips "Go to Investors".
    public static func fuzzyScore(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.searchFolded.filter { !$0.isWhitespace })
        let c = Array(candidate.searchFolded)
        guard !q.isEmpty else { return 0 }
        func isWordStart(_ i: Int) -> Bool { i == 0 || !(c[i - 1].isLetter || c[i - 1].isNumber) }
        if let r = candidate.searchFolded.range(of: String(q)) {
            let at = candidate.searchFolded.distance(from: candidate.searchFolded.startIndex, to: r.lowerBound)
            return q.count * 6 + (isWordStart(at) ? 8 : 0) + (at == 0 ? 6 : 0) - c.count / 8
        }
        var score = 0
        var previous = -2
        for ch in q {
            guard let next = (max(previous + 1, 0)..<c.count).first(where: { c[$0] == ch && ($0 == previous + 1 || isWordStart($0)) }) else { return nil }
            score += 1 + (isWordStart(next) ? 8 : 0) + (next == previous + 1 ? 5 : 0) + (next == 0 ? 6 : 0)
            previous = next
        }
        return score - c.count / 8
    }
}
