import Foundation
import GRDB

public struct Account: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "accounts"
    public var email: String
    public var name: String

    public init(email: String, name: String) {
        self.email = email
        self.name = name
    }
}

public struct MailLabel: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "labels"
    public var id: String
    public var name: String
    public var isSystem: Bool
    /// A `LabelColor` name (see Theme); nil renders as lightGray.
    public var color: String?

    public init(id: String, name: String, isSystem: Bool = false, color: String? = nil) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.color = color
    }

    /// Nearest of the 10 Notion chip colors by hue, for a Gmail label color like "#fb4c2f".
    public static func colorName(gmailHex hex: String) -> String {
        guard let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) else { return "lightGray" }
        let r = Double(v >> 16 & 0xFF) / 255, g = Double(v >> 8 & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        if maxC == 0 || delta / maxC < 0.15 { return maxC > 0.85 ? "lightGray" : "gray" }
        var hue: Double
        if maxC == r { hue = (g - b) / delta } else if maxC == g { hue = 2 + (b - r) / delta } else { hue = 4 + (r - g) / delta }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        switch hue {
        case 15..<45: return maxC < 0.6 ? "brown" : "orange"
        case 45..<70: return "yellow"
        case 70..<170: return "green"
        case 170..<255: return "blue"
        case 255..<290: return "purple"
        case 290..<345: return "pink"
        default: return "red"
        }
    }

    public static let systemIds: Set<String> = [
        "INBOX", "SENT", "DRAFT", "SPAM", "TRASH", "STARRED", "UNREAD", "IMPORTANT",
        "CHAT", "CATEGORY_PERSONAL", "CATEGORY_SOCIAL", "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS",
    ]
}

/// One row per Gmail thread, derived from its messages by `Store` whenever they change.
public struct MailThread: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "threads"
    public var id: String
    public var subject: String
    public var snippet: String
    /// Sender names in order, "me" for the account, e.g. "Alex, me, Priya".
    public var participants: String
    public var messageCount: Int
    public var lastDate: Date
    public var isUnread: Bool
    public var isStarred: Bool
    public var hasAttachments: Bool
    public var hasDraft: Bool
    /// Union of every message's labels, system and user.
    public var labelIds: [String]

    public var userLabelIds: [String] { labelIds.filter { !MailLabel.systemIds.contains($0) } }
}

public struct Message: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "messages"
    public var id: String
    public var threadId: String
    public var labelIds: [String]
    /// Raw header values ("Name <a@b>, …"); parse with `EmailAddress.parseList`.
    public var from: String
    public var to: String
    public var cc: String
    public var bcc: String
    public var replyTo: String
    public var subject: String
    public var snippet: String
    public var date: Date
    public var internalDate: Int64
    public var bodyText: String
    public var bodyHTML: String?
    public var messageIdHeader: String
    public var references: String
    public var inReplyTo: String

    public var isUnread: Bool { labelIds.contains("UNREAD") }
    public var isDraft: Bool { labelIds.contains("DRAFT") }
    public var sender: EmailAddress { EmailAddress.parseList(from).first ?? EmailAddress(name: nil, email: from) }
}

public struct Attachment: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "attachments"
    /// "\(messageId)/\(partId)"
    public var id: String
    public var messageId: String
    public var partId: String
    /// Set when the bytes live on Gmail (`GmailClient.attachment`); nil when `data` holds them.
    public var gmailAttachmentId: String?
    public var filename: String
    public var mimeType: String
    public var size: Int
    /// Content-ID without angle brackets, for `cid:` references in HTML.
    public var contentId: String?
    public var isInline: Bool
    public var data: Data?
}

public struct Draft: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "drafts"
    public var id: String
    public var messageId: String
    public var threadId: String?
    public var updatedAt: Date

    public init(id: String, messageId: String, threadId: String?, updatedAt: Date) {
        self.id = id
        self.messageId = messageId
        self.threadId = threadId
        self.updatedAt = updatedAt
    }
}

/// Gmail `users.settings.sendAs`: an identity the account can send as, with its signature.
public struct SendAs: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "signatures"
    public var email: String
    public var displayName: String
    /// HTML, as Gmail stores it.
    public var signature: String
    public var isDefault: Bool
    public var isPrimary: Bool
    public var replyTo: String?
    public var id: String { email }

    public init(email: String, displayName: String, signature: String, isDefault: Bool, isPrimary: Bool, replyTo: String? = nil) {
        self.email = email
        self.displayName = displayName
        self.signature = signature
        self.isDefault = isDefault
        self.isPrimary = isPrimary
        self.replyTo = replyTo
    }

    public var address: EmailAddress { EmailAddress(name: displayName.isEmpty ? nil : displayName, email: email) }
}

public struct NotionLink: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "notion_links"
    public var threadId: String
    public var pageId: String
    public var title: String
    public var url: String
    public var createdAt: Date

    public init(threadId: String, pageId: String, title: String, url: String, createdAt: Date = .now) {
        self.threadId = threadId
        self.pageId = pageId
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}

public enum Mailbox: Hashable, Sendable {
    case inbox, starred, sent, drafts, all, spam, trash
    case label(String)

    /// The Gmail label a thread must carry; nil for All Mail.
    public var labelId: String? {
        switch self {
        case .inbox: "INBOX"
        case .starred: "STARRED"
        case .sent: "SENT"
        case .drafts: "DRAFT"
        case .spam: "SPAM"
        case .trash: "TRASH"
        case .all: nil
        case .label(let id): id
        }
    }

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .starred: "Starred"
        case .sent: "Sent"
        case .drafts: "Drafts"
        case .all: "All Mail"
        case .spam: "Spam"
        case .trash: "Trash"
        case .label(let id): id
        }
    }
}

public struct ThreadDetail: Sendable, Hashable {
    public var thread: MailThread
    /// Oldest first, drafts included.
    public var messages: [Message]
    public var attachments: [String: [Attachment]]
    public var labels: [MailLabel]
    public var notionLinks: [NotionLink]
}

extension Message {
    /// Maps a parsed MIME tree plus Gmail metadata into a stored message and its attachments.
    public static func make(id: String, threadId: String, labelIds: [String], internalDate: Int64, snippet: String?, root: MIMEPart) -> (Message, [Attachment]) {
        let body = MIME.extract(root)
        let text = body.text.isEmpty ? MIME.plainText(fromHTML: body.html ?? "") : body.text
        let message = Message(
            id: id, threadId: threadId, labelIds: labelIds,
            from: root.header("From") ?? "", to: root.header("To") ?? "", cc: root.header("Cc") ?? "",
            bcc: root.header("Bcc") ?? "", replyTo: root.header("Reply-To") ?? "",
            subject: root.header("Subject") ?? "",
            snippet: snippet ?? MIME.snippet(text),
            date: Date(timeIntervalSince1970: Double(internalDate) / 1000), internalDate: internalDate,
            bodyText: text, bodyHTML: body.html,
            messageIdHeader: root.header("Message-ID") ?? "",
            references: root.header("References") ?? "",
            inReplyTo: root.header("In-Reply-To") ?? ""
        )
        let attachments = body.attachments.map {
            Attachment(id: "\(id)/\($0.partId)", messageId: id, partId: $0.partId, gmailAttachmentId: $0.gmailAttachmentId,
                       filename: $0.filename, mimeType: $0.mimeType, size: $0.size, contentId: $0.contentId,
                       isInline: $0.isInline, data: $0.data)
        }
        return (message, attachments)
    }

    public static func make(gmail m: GmailMessage) -> (Message, [Attachment])? {
        let root: MIMEPart
        if let payload = m.payload { root = MIMEPart(gmail: payload) }
        else if let raw = m.raw, let data = Data(base64URL: raw) { root = MIME.parse(data) }
        else { return nil }
        return make(id: m.id, threadId: m.threadId, labelIds: m.labelIds ?? [],
                    internalDate: Int64(m.internalDate ?? "") ?? 0, snippet: m.snippet.map(MIME.decodeHTMLEntities), root: root)
    }
}
