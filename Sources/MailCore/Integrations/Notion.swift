import AppKit
import Foundation
import GRDB

/// A Notion database (to save threads into) or page (to link threads to).
public struct NotionObject: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case database, page }

    public var id: String
    public var kind: Kind
    public var title: String
    /// Emoji icon, when the object has one.
    public var icon: String?
    public var url: String
    public var lastEdited: Date?
    /// Databases only: the title property's name, and a URL property to hold the Gmail link.
    public var titleProperty: String?
    public var urlProperty: String?

    public init(id: String, kind: Kind, title: String, icon: String? = nil, url: String, lastEdited: Date? = nil,
                titleProperty: String? = nil, urlProperty: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
        self.url = url
        self.lastEdited = lastEdited
        self.titleProperty = titleProperty
        self.urlProperty = urlProperty
    }
}

public enum NotionPickerRequest: Hashable, Sendable {
    case save(threadId: String)
    case link(threadId: String)

    public var threadId: String {
        switch self { case .save(let id), .link(let id): id }
    }

    public var kind: NotionObject.Kind {
        switch self { case .save: .database; case .link: .page }
    }
}

public enum NotionError: LocalizedError {
    case notConnected
    case http(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Add a Notion integration token in Settings → Integrations."
        case .http(let status, let message): status == 401 ? "Notion rejected the token. Check it in Settings → Integrations." : message
        }
    }
}

/// Notion REST API with an internal integration token kept in the Keychain. In demo mode it
/// answers from fixtures after a short delay and never touches the network.
public struct NotionClient: Sendable {
    public static let tokenKey = "notion_token"
    private let token: String?
    private let isDemo: Bool

    /// Demo mode is connected unless `MAIL_NOTION=off`, which shows the not-connected states.
    public init(demo: Bool, token: String? = Keychain.get(NotionClient.tokenKey)) {
        isDemo = demo && ProcessInfo.processInfo.environment["MAIL_NOTION"] != "off"
        self.token = demo ? nil : token
    }

    public var isConnected: Bool { isDemo || !(token ?? "").isEmpty }

    /// The workspace the token belongs to; also validates the token.
    public func workspaceName() async throws -> String {
        if isDemo { return "Helio" }
        struct Me: Decodable { struct Bot: Decodable { var workspace_name: String? }; var name: String?; var bot: Bot? }
        let me: Me = try await request("GET", "users/me")
        return me.bot?.workspace_name ?? me.name ?? "Notion"
    }

    /// Databases or pages shared with the integration whose title matches `query`, most recently edited first.
    public func search(_ query: String, kind: NotionObject.Kind) async throws -> [NotionObject] {
        if isDemo {
            try await Task.sleep(for: .milliseconds(250))
            let all = kind == .database ? NotionFixtures.databases : NotionFixtures.pages
            let q = query.trimmingCharacters(in: .whitespaces)
            return q.isEmpty ? all : all.filter { $0.title.localizedStandardContains(q) }
        }
        let body: [String: Any] = [
            "query": query, "page_size": 20,
            "filter": ["property": "object", "value": kind.rawValue],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"],
        ]
        let list: SearchResults = try await request("POST", "search", body: body)
        return list.results.compactMap(\.notionObject)
    }

    /// Creates a page in `database` for the thread and returns the link to store.
    public func savePage(_ thread: ThreadDetail, to database: NotionObject) async throws -> NotionLink {
        let title = Self.title(thread)
        if isDemo {
            try await Task.sleep(for: .milliseconds(400))
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return NotionLink(threadId: thread.thread.id, pageId: id, title: title, url: "https://www.notion.so/\(id)")
        }
        struct Created: Decodable { var id: String; var url: String }
        let page: Created = try await request("POST", "pages", body: Self.pageBody(thread, database: database))
        return NotionLink(threadId: thread.thread.id, pageId: page.id, title: title, url: page.url)
    }

    public static func gmailURL(threadId: String) -> String {
        "https://mail.google.com/mail/u/0/#all/\(threadId)"
    }

    static func title(_ thread: ThreadDetail) -> String {
        thread.thread.subject.isEmpty ? "(no subject)" : thread.thread.subject
    }

    /// `POST /v1/pages` body: title = subject, the database's URL property (if any) = Gmail link,
    /// and blocks for the sender, the link and an excerpt of the latest message.
    static func pageBody(_ thread: ThreadDetail, database: NotionObject) -> [String: Any] {
        let messages = thread.messages.filter { !$0.isDraft }
        let sender = messages.first?.sender.formatted ?? ""
        let excerpt = String((messages.last?.bodyText ?? thread.thread.snippet).trimmingCharacters(in: .whitespacesAndNewlines).prefix(1800))
        let link = gmailURL(threadId: thread.thread.id)
        func text(_ s: String, url: String? = nil) -> [String: Any] {
            var t: [String: Any] = ["content": s]
            if let url { t["link"] = ["url": url] }
            return ["type": "text", "text": t]
        }
        var properties: [String: Any] = [database.titleProperty ?? "Name": ["title": [text(title(thread))]]]
        if let urlProperty = database.urlProperty { properties[urlProperty] = ["url": link] }
        var children: [[String: Any]] = [
            ["object": "block", "type": "paragraph", "paragraph": ["rich_text": [text("From: "), text(sender)]]],
            ["object": "block", "type": "paragraph", "paragraph": ["rich_text": [text("Open in Gmail", url: link)]]],
        ]
        if !excerpt.isEmpty { children.append(["object": "block", "type": "quote", "quote": ["rich_text": [text(excerpt)]]]) }
        return ["parent": ["database_id": database.id], "properties": properties, "children": children]
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let token, !token.isEmpty else { throw NotionError.notConnected }
        var req = URLRequest(url: URL(string: "https://api.notion.com/v1/")!.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(NotionErrorBody.self, from: data))?.message ?? "Notion \(status)"
            throw NotionError.http(status: status, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct NotionErrorBody: Decodable { var message: String }

struct SearchResults: Decodable {
    struct RichText: Decodable { var plain_text: String }
    struct Property: Decodable { var type: String; var title: [RichText]? }
    struct Icon: Decodable { var type: String; var emoji: String? }
    struct Result: Decodable {
        var object: String
        var id: String
        var url: String?
        var icon: Icon?
        var last_edited_time: String?
        /// Databases carry their title here; pages in their title property.
        var title: [RichText]?
        var properties: [String: Property]?

        var plainTitle: String {
            let rich = title ?? properties?.values.first { $0.type == "title" }?.title ?? []
            let s = rich.map(\.plain_text).joined()
            return s.isEmpty ? "Untitled" : s
        }

        var notionObject: NotionObject? {
            guard let kind = NotionObject.Kind(rawValue: object), let url else { return nil }
            let props = properties ?? [:]
            return NotionObject(
                id: id, kind: kind, title: plainTitle, icon: icon?.emoji, url: url,
                lastEdited: last_edited_time.flatMap { ISO8601DateFormatter.fractional.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) },
                titleProperty: kind == .database ? props.first { $0.value.type == "title" }?.key : nil,
                urlProperty: kind == .database ? props.filter { $0.value.type == "url" }.map(\.key).sorted().first : nil)
        }
    }
    var results: [Result]
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions.insert(.withFractionalSeconds)
        return f
    }()
}

enum NotionFixtures {
    private static func edited(_ daysAgo: Double) -> Date { Date.now.addingTimeInterval(-daysAgo * 86_400) }

    static let databases: [NotionObject] = [
        NotionObject(id: "db-inbox", kind: .database, title: "Mail follow-ups", icon: "📥", url: "https://www.notion.so/db-inbox", lastEdited: edited(0.2), titleProperty: "Name", urlProperty: "Gmail"),
        NotionObject(id: "db-tasks", kind: .database, title: "Tasks", icon: "✅", url: "https://www.notion.so/db-tasks", lastEdited: edited(1), titleProperty: "Task"),
        NotionObject(id: "db-crm", kind: .database, title: "Partners & vendors", icon: "🤝", url: "https://www.notion.so/db-crm", lastEdited: edited(4), titleProperty: "Name", urlProperty: "Link"),
        NotionObject(id: "db-reading", kind: .database, title: "Reading list", icon: "📚", url: "https://www.notion.so/db-reading", lastEdited: edited(12), titleProperty: "Title"),
        NotionObject(id: "db-receipts", kind: .database, title: "Receipts 2026", icon: "🧾", url: "https://www.notion.so/db-receipts", lastEdited: edited(30), titleProperty: "Name"),
    ]

    static let pages: [NotionObject] = [
        NotionObject(id: "pg-q4", kind: .page, title: "Q4 Roadmap", icon: "🗺️", url: "https://www.notion.so/pg-q4", lastEdited: edited(0.1)),
        NotionObject(id: "pg-search", kind: .page, title: "Search — result states", icon: "🔍", url: "https://www.notion.so/pg-search", lastEdited: edited(0.5)),
        NotionObject(id: "pg-offline", kind: .page, title: "Offline search: technical spec", icon: nil, url: "https://www.notion.so/pg-offline", lastEdited: edited(1)),
        NotionObject(id: "pg-offsite", kind: .page, title: "Offsite 2026 — Ljubljana", icon: "🏔️", url: "https://www.notion.so/pg-offsite", lastEdited: edited(3)),
        NotionObject(id: "pg-1on1", kind: .page, title: "1:1 Zoë / Tim", icon: "💬", url: "https://www.notion.so/pg-1on1", lastEdited: edited(6)),
        NotionObject(id: "pg-hiring", kind: .page, title: "Hiring plan — platform team", icon: "🧑‍💻", url: "https://www.notion.so/pg-hiring", lastEdited: edited(9)),
        NotionObject(id: "pg-perf", kind: .page, title: "Performance review template", icon: "📝", url: "https://www.notion.so/pg-perf", lastEdited: edited(21)),
    ]
}

extension AppState {
    func registerIntegrationCommands() {
        let current: @MainActor @Sendable () -> String? = { [unowned self] in openThreadId ?? focusedThreadId }
        let latestLink: @MainActor @Sendable () -> NotionLink? = { [unowned self] in
            guard let id = current() else { return nil }
            return try? store.db.read { try NotionLink.filter(Column("threadId") == id).order(Column("createdAt").desc).fetchOne($0) }
        }
        commands.register([
            Command(id: "notion.save", title: "Save to Notion", group: .thread, icon: "square.and.arrow.down",
                    keywords: ["notion", "database", "export"], isAvailable: { current() != nil }) { [unowned self] in
                        if let id = current() { notionPicker = .save(threadId: id) }
                    },
            Command(id: "notion.link", title: "Link to Notion page", group: .thread, icon: "link",
                    keywords: ["notion", "page", "attach"], isAvailable: { current() != nil }) { [unowned self] in
                        if let id = current() { notionPicker = .link(threadId: id) }
                    },
            Command(id: "notion.open", title: "Open linked Notion page", group: .thread, icon: "arrow.up.forward.square",
                    keywords: ["notion"], isAvailable: { latestLink() != nil }) {
                        if let link = latestLink(), let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
                    },
            Command(id: "integrations.settings", title: "Connect Notion", group: .integrations, icon: "puzzlepiece.extension",
                    keywords: ["notion", "token", "calendar", "integrations"]) { [unowned self] in settings = .integrations },
        ])
    }
}
