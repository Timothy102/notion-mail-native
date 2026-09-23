import Foundation

// MARK: - Wire types (Gmail REST v1)

public struct GmailPayload: Codable, Sendable {
    public struct Header: Codable, Sendable { public var name: String; public var value: String }
    public struct Body: Codable, Sendable { public var attachmentId: String?; public var size: Int?; public var data: String? }
    public var partId: String?
    public var mimeType: String?
    public var filename: String?
    public var headers: [Header]?
    public var body: Body?
    public var parts: [GmailPayload]?
}

public struct GmailMessage: Codable, Sendable {
    public var id: String
    public var threadId: String
    public var labelIds: [String]?
    public var snippet: String?
    public var historyId: String?
    /// Epoch milliseconds as a string.
    public var internalDate: String?
    public var payload: GmailPayload?
    /// base64url RFC 2822, only with `format=raw`.
    public var raw: String?
    public var sizeEstimate: Int?
}

public struct GmailRef: Codable, Sendable, Hashable { public var id: String; public var threadId: String? }

public struct GmailThread: Codable, Sendable {
    public var id: String
    public var historyId: String?
    public var snippet: String?
    public var messages: [GmailMessage]?
}

public struct GmailMessageList: Codable, Sendable {
    public var messages: [GmailRef]?
    public var nextPageToken: String?
    public var resultSizeEstimate: Int?
}

public struct GmailThreadList: Codable, Sendable {
    public var threads: [GmailRef]?
    public var nextPageToken: String?
}

public struct GmailHistory: Codable, Sendable {
    public struct Added: Codable, Sendable { public var message: GmailMessage }
    public struct LabelChange: Codable, Sendable { public var message: GmailMessage; public var labelIds: [String]? }
    public struct Record: Codable, Sendable {
        public var id: String
        public var messagesAdded: [Added]?
        public var messagesDeleted: [Added]?
        public var labelsAdded: [LabelChange]?
        public var labelsRemoved: [LabelChange]?
    }
    public var history: [Record]?
    public var nextPageToken: String?
    public var historyId: String
}

public struct GmailLabel: Codable, Sendable {
    public struct Color: Codable, Sendable { public var textColor: String?; public var backgroundColor: String? }
    public var id: String
    public var name: String
    public var type: String?
    public var color: Color?
    public var messagesUnread: Int?
    public var threadsUnread: Int?
}

public struct GmailDraft: Codable, Sendable {
    public var id: String
    public var message: GmailMessage?
}

public struct GmailSendAs: Codable, Sendable {
    public var sendAsEmail: String
    public var displayName: String?
    public var signature: String?
    public var isDefault: Bool?
    public var isPrimary: Bool?
    public var replyToAddress: String?
}

public struct GmailProfile: Codable, Sendable {
    public var emailAddress: String
    public var messagesTotal: Int
    public var historyId: String
}

public enum GmailError: LocalizedError, CustomStringConvertible {
    case http(status: Int, body: String)

    public var status: Int {
        switch self { case .http(let s, _): s }
    }

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .http(let status, let body):
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: Data(body.utf8)))?.error.message
            return "Gmail \(status): \(message ?? body.prefix(200).description)"
        }
    }

    private struct ErrorBody: Decodable { struct E: Decodable { var message: String }; var error: E }
}

public enum MessageFormat: String, Sendable { case full, metadata, minimal, raw }

// MARK: - Client

public struct GmailClient: Sendable {
    public static let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!

    /// Returns an access token; `true` forces a refresh (after a 401).
    public let token: @Sendable (_ refresh: Bool) async throws -> String
    private let session: URLSession

    public init(token: @escaping @Sendable (_ refresh: Bool) async throws -> String,
                session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // Profile

    public func profile() async throws -> GmailProfile { try await request("GET", "profile") }

    /// The Google account's name and photo. Needs the userinfo.profile scope: older logins get a 401/403.
    public func userinfo() async throws -> GoogleUserinfo {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(try await token(false))", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GmailError.http(status: status, body: String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(GoogleUserinfo.self, from: data)
    }

    // Messages

    public func listMessages(q: String? = nil, labelIds: [String] = [], pageToken: String? = nil, maxResults: Int = 100, includeSpamTrash: Bool = false) async throws -> GmailMessageList {
        var query = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        if let q { query.append(.init(name: "q", value: q)) }
        query += labelIds.map { .init(name: "labelIds", value: $0) }
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        if includeSpamTrash { query.append(.init(name: "includeSpamTrash", value: "true")) }
        return try await request("GET", "messages", query: query)
    }

    public func message(_ id: String, format: MessageFormat = .full) async throws -> GmailMessage {
        try await request("GET", "messages/\(id)", query: [.init(name: "format", value: format.rawValue)])
    }

    /// Fetches many messages with at most `concurrency` requests in flight. Order follows `ids`; missing (404) ones are dropped.
    public func messages(_ ids: [String], format: MessageFormat = .full, concurrency: Int = 8) async throws -> [GmailMessage] {
        // Plain iterator, no nested func mutating captured state: that shape returned 1 of 100 results in -O builds.
        try await withThrowingTaskGroup(of: (Int, GmailMessage?).self) { group in
            var results = [GmailMessage?](repeating: nil, count: ids.count)
            var pending = ids.enumerated().makeIterator()
            for _ in 0..<min(concurrency, ids.count) {
                guard let (i, id) = pending.next() else { break }
                group.addTask { (i, try await self.messageOrNil(id, format: format)) }
            }
            while let (i, m) = try await group.next() {
                results[i] = m
                if let (j, id) = pending.next() {
                    group.addTask { (j, try await self.messageOrNil(id, format: format)) }
                }
            }
            return results.compactMap { $0 }
        }
    }

    /// A message deleted between listing and fetching is skipped rather than failing the batch.
    private func messageOrNil(_ id: String, format: MessageFormat) async throws -> GmailMessage? {
        do { return try await message(id, format: format) }
        catch let e as GmailError where e.status == 404 { return nil }
    }

    /// Gmail `q` search (the remote fallback for local search).
    public func search(_ q: String, pageToken: String? = nil, maxResults: Int = 50) async throws -> GmailMessageList {
        try await listMessages(q: q, pageToken: pageToken, maxResults: maxResults, includeSpamTrash: true)
    }

    public func batchModify(messageIds: [String], add: [String] = [], remove: [String] = []) async throws {
        let _: Empty = try await request("POST", "messages/batchModify", body: ModifyBody(ids: messageIds, addLabelIds: add, removeLabelIds: remove))
    }

    /// Sends a raw RFC 2822 message (see `MIME.build`) into `threadId` when replying.
    public func send(raw: Data, threadId: String? = nil) async throws -> GmailMessage {
        try await request("POST", "messages/send", body: RawMessage(raw: raw.base64URL, threadId: threadId))
    }

    public func attachment(messageId: String, id: String) async throws -> Data {
        struct Body: Decodable { var data: String }
        let b: Body = try await request("GET", "messages/\(messageId)/attachments/\(id)")
        return Data(base64URL: b.data) ?? Data()
    }

    // Threads

    public func listThreads(q: String? = nil, labelIds: [String] = [], pageToken: String? = nil, maxResults: Int = 100) async throws -> GmailThreadList {
        var query = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        if let q { query.append(.init(name: "q", value: q)) }
        query += labelIds.map { .init(name: "labelIds", value: $0) }
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        return try await request("GET", "threads", query: query)
    }

    public func thread(_ id: String, format: MessageFormat = .full) async throws -> GmailThread {
        try await request("GET", "threads/\(id)", query: [.init(name: "format", value: format.rawValue)])
    }

    public func modifyThread(_ id: String, add: [String] = [], remove: [String] = []) async throws {
        let _: GmailThread = try await request("POST", "threads/\(id)/modify", body: ModifyBody(ids: nil, addLabelIds: add, removeLabelIds: remove))
    }

    public func trashThread(_ id: String) async throws {
        let _: GmailThread = try await request("POST", "threads/\(id)/trash")
    }

    public func untrashThread(_ id: String) async throws {
        let _: GmailThread = try await request("POST", "threads/\(id)/untrash")
    }

    // History

    /// Throws `GmailError` 404 when `startHistoryId` is too old; resync from scratch then.
    public func history(since startHistoryId: String, pageToken: String? = nil) async throws -> GmailHistory {
        var query = [URLQueryItem(name: "startHistoryId", value: startHistoryId), .init(name: "maxResults", value: "500")]
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        return try await request("GET", "history", query: query)
    }

    // Labels

    public func labels() async throws -> [GmailLabel] {
        struct List: Decodable { var labels: [GmailLabel]? }
        let list: List = try await request("GET", "labels")
        return list.labels ?? []
    }

    // Drafts

    public func drafts(pageToken: String? = nil, maxResults: Int = 100) async throws -> (drafts: [GmailDraft], nextPageToken: String?) {
        struct List: Decodable { var drafts: [GmailDraft]?; var nextPageToken: String? }
        var query = [URLQueryItem(name: "maxResults", value: "\(maxResults)")]
        if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
        let list: List = try await request("GET", "drafts", query: query)
        return (list.drafts ?? [], list.nextPageToken)
    }

    public func draft(_ id: String) async throws -> GmailDraft {
        try await request("GET", "drafts/\(id)", query: [.init(name: "format", value: "full")])
    }

    public func createDraft(raw: Data, threadId: String? = nil) async throws -> GmailDraft {
        try await request("POST", "drafts", body: DraftBody(id: nil, message: RawMessage(raw: raw.base64URL, threadId: threadId)))
    }

    public func updateDraft(_ id: String, raw: Data, threadId: String? = nil) async throws -> GmailDraft {
        try await request("PUT", "drafts/\(id)", body: DraftBody(id: id, message: RawMessage(raw: raw.base64URL, threadId: threadId)))
    }

    public func deleteDraft(_ id: String) async throws {
        let _: Empty = try await request("DELETE", "drafts/\(id)")
    }

    public func sendDraft(_ id: String) async throws -> GmailMessage {
        struct Body: Encodable { var id: String }
        return try await request("POST", "drafts/send", body: Body(id: id))
    }

    // Settings: send-as identities and signatures

    public func sendAs() async throws -> [GmailSendAs] {
        struct List: Decodable { var sendAs: [GmailSendAs]? }
        let list: List = try await request("GET", "settings/sendAs")
        return list.sendAs ?? []
    }

    public func updateSignature(sendAsEmail: String, signature: String) async throws -> GmailSendAs {
        struct Body: Encodable { var signature: String }
        return try await request("PATCH", "settings/sendAs/\(sendAsEmail)", body: Body(signature: signature))
    }

    // MARK: Transport

    private struct Empty: Decodable {}
    private struct NoBody: Encodable {}
    private struct RawMessage: Encodable { var raw: String; var threadId: String? }
    private struct DraftBody: Encodable { var id: String?; var message: RawMessage }
    private struct ModifyBody: Encodable { var ids: [String]?; var addLabelIds: [String]; var removeLabelIds: [String] }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        var url = Self.base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method == "POST" {
            req.httpBody = Data("{}".utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        var refreshed = false
        var attempt = 0
        while true {
            req.setValue("Bearer \(try await token(refreshed))", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await session.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if (200..<300).contains(status) {
                if T.self == Empty.self || data.isEmpty { return try JSONDecoder().decode(T.self, from: Data("{}".utf8)) }
                return try JSONDecoder().decode(T.self, from: data)
            }
            if status == 401, !refreshed {
                refreshed = true
                continue
            }
            SyncLog.write("http \(status) \(method) \(path.prefix(40)) attempt \(attempt)")
            let rateLimited = status == 429 || (status == 403 && String(decoding: data, as: UTF8.self).contains("ateLimitExceeded"))
            if (rateLimited || status >= 500), attempt < 5 {
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                // Gmail's limit is per second, so short backoffs recover fastest.
                let delay = retryAfter ?? min(8, 0.5 * pow(2, Double(attempt))) + Double.random(in: 0..<0.25)
                try await Task.sleep(for: .seconds(delay))
                attempt += 1
                continue
            }
            throw GmailError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }
}
