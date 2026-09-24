import Foundation
import GRDB

/// What a list row shows beyond `MailThread`: whose avatar, which attachment chips, and a one-time code to copy.
public struct ThreadRowExtras: Sendable, Hashable {
    /// Sender of the newest non-draft message.
    public var sender: EmailAddress
    /// Chip-worthy attachments, newest message first; `data` is never loaded here.
    public var files: [Attachment]
    public var code: String?
}

extension Store {
    /// Extras for the given threads, in one pass over their messages' headers and attachment metadata.
    /// Codes are only looked for in messages from the last day.
    public static func rowExtras(_ db: Database, threadIds: [String], now: Date = .now) throws -> [String: ThreadRowExtras] {
        guard !threadIds.isEmpty else { return [:] }
        let marks = databaseQuestionMarks(count: threadIds.count)
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, threadId, "from", subject, snippet, date, labelIds FROM messages
            WHERE threadId IN (\(marks)) ORDER BY internalDate DESC
            """, arguments: StatementArguments(threadIds))
        var newest: [String: Row] = [:]
        var messageThread: [String: String] = [:]
        for row in rows {
            let threadId: String = row["threadId"]
            messageThread[row["id"]] = threadId
            let labels: String = row["labelIds"]
            if newest[threadId] == nil, !labels.contains("\"DRAFT\"") { newest[threadId] = row }
        }
        var files: [String: [Attachment]] = [:]
        if !messageThread.isEmpty {
            let ids = Array(messageThread.keys)
            let attachments = try Attachment.fetchAll(db, sql: """
                SELECT id, messageId, partId, gmailAttachmentId, filename, mimeType, size, contentId, isInline, NULL AS data
                FROM attachments WHERE isInline = 0 AND messageId IN (\(databaseQuestionMarks(count: ids.count))) ORDER BY partId
                """, arguments: StatementArguments(ids))
            let order = Dictionary(rows.enumerated().map { ($1["id"] as String, $0) }) { a, _ in a }
            for a in attachments.filter(\.isChip).sorted(by: { order[$0.messageId, default: 0] < order[$1.messageId, default: 0] }) {
                files[messageThread[a.messageId]!, default: []].append(a)
            }
        }
        var out: [String: ThreadRowExtras] = [:]
        for (threadId, row) in newest {
            let from: String = row["from"]
            let date: Date = row["date"]
            let recent = now.timeIntervalSince(date) < 24 * 3600
            out[threadId] = ThreadRowExtras(
                sender: EmailAddress.parseList(from).first ?? EmailAddress(name: nil, email: from),
                files: files[threadId] ?? [],
                code: recent ? VerificationCode.find(subject: row["subject"], text: row["snippet"]) : nil
            )
        }
        return out
    }
}

extension Attachment {
    public enum Kind: Sendable {
        case pdf, image, document, spreadsheet, presentation, archive, other

        /// SF Symbol for chips.
        public var symbol: String {
            switch self {
            case .pdf: "doc.richtext.fill"
            case .image: "photo.fill"
            case .document: "doc.text.fill"
            case .spreadsheet: "tablecells.fill"
            case .presentation: "rectangle.on.rectangle.angled.fill"
            case .archive: "doc.zipper"
            case .other: "doc.fill"
            }
        }

        /// A `LabelColor` name for the symbol, Gmail's convention in Notion's palette.
        public var colorName: String {
            switch self {
            case .pdf: "red"
            case .image: "orange"
            case .document: "blue"
            case .spreadsheet: "green"
            case .presentation: "yellow"
            case .archive, .other: "gray"
            }
        }
    }

    public var kind: Kind {
        let type = mimeType.lowercased()
        let ext = (filename as NSString).pathExtension.lowercased()
        if type == "application/pdf" || ext == "pdf" { return .pdf }
        if type.hasPrefix("image/") { return .image }
        if type.contains("spreadsheet") || type.contains("excel") || ["xls", "xlsx", "csv", "numbers"].contains(ext) { return .spreadsheet }
        if type.contains("presentation") || type.contains("powerpoint") || ["ppt", "pptx", "key"].contains(ext) { return .presentation }
        if type.contains("zip") || type.contains("compressed") || ["zip", "rar", "7z", "gz", "tar"].contains(ext) { return .archive }
        if type.contains("word") || type.contains("document") || type.hasPrefix("text/") || ["doc", "docx", "rtf", "txt", "pages", "md"].contains(ext) { return .document }
        return .other
    }

    /// Files a row shows as chips: not inline parts, calendar invites, or the logos signatures attach
    /// (images with a Content-ID, or Outlook's small `image001.png`).
    public var isChip: Bool {
        guard !isInline, !mimeType.lowercased().hasPrefix("text/calendar") else { return false }
        guard kind == .image else { return true }
        if contentId != nil { return false }
        return !(filename.lowercased().wholeMatch(of: /image\d{3}\.(png|jpe?g|gif)/) != nil && size < 50_000)
    }

    /// Writes this attachment's bytes (from the store, else from Gmail) to a temporary file for Quick Look
    /// or the default app, and returns its URL.
    public static func file(id: String, store: Store, gmail: GmailClient?) async throws -> URL {
        guard let a = try await store.db.read({ try Attachment.fetchOne($0, key: id) }) else { throw CocoaError(.fileReadNoSuchFile) }
        let data: Data
        if let d = a.data { data = d }
        else if let gmail, let remoteId = a.gmailAttachmentId { data = try await gmail.attachment(messageId: a.messageId, id: remoteId) }
        else { throw CocoaError(.fileReadNoSuchFile) }
        let dir = FileManager.default.temporaryDirectory.appending(path: "MailAttachments/\(a.messageId)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: (a.filename.isEmpty ? "attachment" : a.filename).replacingOccurrences(of: "/", with: "-"))
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// One-time codes ("Copy code: 143819"). Conservative: the subject must look like a code mail, and the digits
/// must sit right next to a code word, so door codes, years, prices, order and phone numbers stay out.
public enum VerificationCode {
    private static let subjectHint = regex(#"\b(codes?|verif\w*|otp|passcode|one[- ]time|2fa|two[- ]factor|pin|koda|kodo|geslo|log[- ]?in|sign[- ]?in|authenticat\w*|security|confirm\w*|prijav\w*|potrdi\w*)\b"#)
    private static let codeWord = #"(?:codes?|verification|verify|otp|passcode|one[- ]time|pin|koda|kodo|geslo)"#
    private static let digits = #"(?<![\w€$£¥#+\-./:,])(\d{3}[- ]\d{3}|\d{4,8})(?![\w%€$£\-/:]|[.,]\d|\s?(?:eur|usd|gbp|chf|kn|€|\$|%))"#
    /// "code is 143819", "code: 143819", "koda za prijavo: 5821", or "143819 is your code".
    private static let patterns = [
        regex(#"\b"# + codeWord + #"\b[^\d\n]{0,24}?"# + digits),
        regex(digits + #"\s+(?:is|je)\s+(?:your|vaša|vasa)\b[^\d\n]{0,24}?\b"# + codeWord + #"\b"#),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    public static func find(subject: String, text: String) -> String? {
        guard subjectHint.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil else { return nil }
        for source in [subject, text] {
            for pattern in patterns {
                for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    guard let r = Range(match.range(at: 1), in: source) else { continue }
                    let code = source[r].filter(\.isNumber)
                    if code.count == 4, let n = Int(code), (1900...2099).contains(n) { continue }
                    return code
                }
            }
        }
        return nil
    }
}

extension String {
    /// A list preview: `(https://…)` and `<https://…>` link expansions from plain-text parts removed.
    public var listPreview: String {
        guard contains("://") else { return self }
        return replacing(/\s*[(<]https?:\/\/[^\s)>]*[)>]?/, with: "")
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
