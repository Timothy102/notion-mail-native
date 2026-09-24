import Foundation
import GRDB
import MailCore

public struct ToolError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// NMail as an MCP server: JSON-RPC 2.0 over newline-delimited stdio, tools only.
/// Mail lives in the app's per-account stores (read locally, freshened with history deltas); writes go to
/// Gmail first, then the store. Requests are handled one at a time.
/// ponytail: sequential handling, so a long send_bulk delays other calls; run tool calls concurrently if that bites.
public actor MCPServer {
    public static let protocolVersion = "2025-06-18"
    static let olderVersions: Set = ["2025-03-26", "2024-11-05"]

    /// The Gmail client for an account; nil when offline. Throws when the account has no login.
    public typealias GmailFactory = @Sendable (_ email: String) throws -> GmailClient?

    public let storage: AccountStorage
    let makeGmail: GmailFactory
    /// Pause between messages of a send_bulk, for Gmail's sending limits.
    public var sendPacing: Duration = .seconds(1)
    /// Longest a pre-read history sync may take before reads go ahead on local data.
    public var syncTimeout: Duration = .seconds(10)
    /// A history sync this recent (by the app or this server) is fresh enough to skip another.
    static let freshFor: TimeInterval = 20

    struct Context {
        var email: String
        var store: Store
        var gmail: GmailClient?

        func requireGmail() throws -> GmailClient {
            guard let gmail else { throw ToolError("Offline (NMAIL_OFFLINE=1): nothing was sent to Gmail and nothing changed.") }
            return gmail
        }
    }

    private var contexts: [String: Context] = [:]

    public init(storage: AccountStorage, gmail: @escaping GmailFactory) {
        self.storage = storage
        makeGmail = gmail
    }

    public func setPacing(_ pacing: Duration) { sendPacing = pacing }

    /// The real server: `NMAIL_DATA_DIR` replaces `~/Library/Application Support/Mail` (secrets.json included),
    /// `NMAIL_OFFLINE=1` keeps it off the network. Logins are the app's; this never runs a sign-in.
    public static func live(environment: [String: String]) -> MCPServer {
        var storage = AccountStorage.default
        if let dir = environment["NMAIL_DATA_DIR"], !dir.isEmpty {
            storage = AccountStorage(base: URL(filePath: dir, directoryHint: .isDirectory))
            Secrets.url = storage.base.appending(path: "secrets.json")
        }
        let offline = environment["NMAIL_OFFLINE"] == "1"
        return MCPServer(storage: storage) { email in
            if offline { return nil }
            let key = Auth.tokenKey(email)
            let missing = ToolError("\(email) has no Gmail login. Open AxiosM and add the account (account menu → Add account), then try again.")
            guard Secrets.get(key) != nil else { throw missing }
            let auth = Auth(email: email)
            return GmailClient { refresh in
                // Auth.token falls back to an interactive sign-in without a refresh token; a server must never do that.
                guard Secrets.get(key) != nil else { throw missing }
                return try await auth.token(refresh: refresh)
            }
        }
    }

    // MARK: JSON-RPC

    /// Handles one line from the client. Returns the response line, or nil for notifications.
    public func handle(_ line: String) async -> String? {
        guard let message = try? JSONDecoder().decode(JSON.self, from: Data(line.utf8)) else {
            return Self.error(id: .null, code: -32700, "Parse error")
        }
        if message["method"] == nil, message["result"] != nil || message["error"] != nil { return nil }
        guard case .object = message, let method = message["method"]?.string else {
            return Self.error(id: message["id"] ?? .null, code: -32600, "Invalid request")
        }
        guard let id = message["id"] else { return nil }
        let params = message["params"] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.string ?? Self.protocolVersion
            return Self.result(id: id, [
                "protocolVersion": .string(Self.olderVersions.contains(asked) ? asked : Self.protocolVersion),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "axiosm", "title": "AxiosM", "version": "0.1.0"],
                "instructions": .string(Self.instructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(Tools.all.map(\.listing))])
        case "tools/call":
            guard let name = params["name"]?.string, let tool = Tools.all.first(where: { $0.name == name }) else {
                return Self.error(id: id, code: -32602, "Unknown tool: \(params["name"]?.string ?? "(none)")")
            }
            let arguments = params["arguments"] ?? [:]
            do {
                let text = try await call(tool.name, arguments)
                return Self.result(id: id, ["content": [["type": "text", "text": .string(text)]], "isError": false])
            } catch {
                log("\(name) failed: \(error)")
                return Self.result(id: id, ["content": [["type": "text", "text": .string(error.localizedDescription)]], "isError": true])
            }
        default:
            return Self.error(id: id, code: -32601, "Method not found: \(method)")
        }
    }

    static let instructions = """
        NMail: Tim's Gmail through his NMail app, all accounts. Every tool takes an optional `account` (email); \
        it defaults to the account open in NMail. Find mail with `search` (Gmail query syntax), read it with \
        `get_thread` / `get_messages`. Writes are guarded: `modify_by_query` is a dry run unless dry_run:false, \
        and `send` / `send_bulk` only preview unless confirm:true. Show Tim the preview and get his OK before \
        sending or before a large modify. Outgoing mail uses his NMail signature and formatting.
        """

    private static func result(id: JSON, _ result: JSON) -> String {
        JSON.object(["jsonrpc": "2.0", "id": id, "result": result]).line
    }

    private static func error(id: JSON, code: Int, _ message: String) -> String {
        JSON.object(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]).line
    }

    func log(_ line: String) {
        FileHandle.standardError.write(Data("nmail-mcp: \(line)\n".utf8))
    }

    // MARK: Accounts

    /// The account named by `account`, else the one open in NMail.
    func context(_ args: JSON) throws -> Context {
        let registry = storage.loadRegistry()
        guard let asked = args["account"]?.string ?? registry.active ?? registry.emails.first else {
            throw ToolError("AxiosM has no accounts yet. Sign in to AxiosM first.")
        }
        guard let email = registry.emails.first(where: { $0.caseInsensitiveCompare(asked) == .orderedSame }) else {
            throw ToolError("\(asked) isn't an AxiosM account. Accounts: \(registry.emails.joined(separator: ", ")). Add it in AxiosM first.")
        }
        if let cached = contexts[email] { return cached }
        let context = Context(email: email, store: try Store(path: storage.database(email)), gmail: try makeGmail(email))
        contexts[email] = context
        return context
    }

    // MARK: Sync

    /// A quick history sync before a read, so results are fresh even when the app isn't running.
    /// Skipped when one finished in the last 20 s or offline; bounded by `syncTimeout`. Returns an error to report, if any.
    func freshen(_ ctx: Context, force: Bool = false) async -> String? {
        guard let gmail = ctx.gmail else { return nil }
        if !force, let last = (try? ctx.store.get(Sync.historySyncedAtKey)).flatMap({ $0.flatMap(TimeInterval.init) }),
           Date.now.timeIntervalSince1970 - last < Self.freshFor {
            return nil
        }
        let sync = Sync(gmail: gmail, store: ctx.store)
        do {
            let resumed = try await withTimeout(syncTimeout) { try await sync.incremental() }
            return resumed ? nil : "No sync history yet; open AxiosM once so it can do the first full sync."
        } catch {
            log("sync failed: \(error)")
            return "Couldn't sync with Gmail (\(error.localizedDescription)); showing local mail."
        }
    }
}

func withTimeout<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw ToolError("timed out after \(limit)")
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
