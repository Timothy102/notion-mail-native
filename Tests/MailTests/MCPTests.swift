import Foundation
import GRDB
@testable import MailCore
@testable import MailMCP
import Synchronization
import XCTest

/// nmail-mcp against fixture mail in a temp dir; Gmail is StubGmail (or absent, offline).
final class MCPTests: XCTestCase {
    private var base: URL!
    private var savedSecrets: URL!
    private let me = Fixtures.me.email

    override func setUp() {
        base = FileManager.default.temporaryDirectory.appending(path: "mcp-\(UUID().uuidString)/Mail")
        savedSecrets = Secrets.url
        Secrets.url = base.appending(path: "secrets.json")
        StubGmail.reset([:])
    }

    override func tearDown() {
        Secrets.url = savedSecrets
        try? FileManager.default.removeItem(at: base.deletingLastPathComponent())
    }

    /// Fixture mail for `me`, synced "just now" so reads don't sync first.
    @discardableResult
    private func seed() throws -> Store {
        let storage = AccountStorage(base: base)
        let store = try Store(path: storage.database(me))
        try Fixtures.seed(store)
        try store.set("historyId", "100")
        try store.set(Sync.historySyncedAtKey, String(Int(Date.now.timeIntervalSince1970)))
        try storage.save(AccountRegistry(emails: [me], active: me))
        return store
    }

    private func server(offline: Bool = false) -> MCPServer {
        MCPServer(storage: AccountStorage(base: base)) { _ in offline ? nil : StubGmail.client }
    }

    private func rpc(_ server: MCPServer, _ method: String, _ params: JSON = [:], id: JSON = 1) async throws -> JSON {
        let line = JSON.object(["jsonrpc": "2.0", "id": id, "method": .string(method), "params": params]).line
        let handled = await server.handle(line)
        let reply = try XCTUnwrap(handled)
        XCTAssertFalse(reply.contains("\n"), "one message per line")
        return try JSONDecoder().decode(JSON.self, from: Data(reply.utf8))
    }

    /// A tool's JSON result; fails the test on a tool error.
    private func call(_ server: MCPServer, _ tool: String, _ args: JSON = [:], file: StaticString = #filePath, line: UInt = #line) async throws -> JSON {
        let reply = try await rpc(server, "tools/call", ["name": .string(tool), "arguments": args])
        let text = try XCTUnwrap(reply["result"]?["content"]?.array?.first?["text"]?.string, "\(reply)", file: file, line: line)
        XCTAssertEqual(reply["result"]?["isError"], false, text, file: file, line: line)
        return try JSONDecoder().decode(JSON.self, from: Data(text.utf8))
    }

    private func replyTarget(_ store: Store) throws -> Message {
        try store.db.read { db in
            let thread = try XCTUnwrap(try Store.threads(db, in: .inbox).first { $0.messageCount >= 5 })
            return try XCTUnwrap(try Store.threadDetail(db, id: thread.id)?.messages.last { !$0.isDraft })
        }
    }

    // MARK: JSON-RPC

    func testInitializeListAndErrors() async throws {
        try seed()
        let s = server()
        let initialized = try await rpc(s, "initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]])
        XCTAssertEqual(initialized["jsonrpc"], "2.0")
        XCTAssertEqual(initialized["id"], 1)
        XCTAssertEqual(initialized["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(initialized["result"]?["serverInfo"]?["name"], "axiosm")
        XCTAssertNotNil(initialized["result"]?["capabilities"]?["tools"])
        let older = try await rpc(s, "initialize", ["protocolVersion": "2025-03-26"])
        XCTAssertEqual(older["result"]?["protocolVersion"], "2025-03-26")

        let notification = await s.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification, "notifications get no response")
        let ping = try await rpc(s, "ping", id: "p")
        XCTAssertEqual(ping["result"], [:])
        XCTAssertEqual(ping["id"], "p", "string ids are echoed")

        let listed = try await rpc(s, "tools/list")
        let tools = try XCTUnwrap(listed["result"]?["tools"]?.array)
        let names = tools.compactMap { $0["name"]?.string }
        XCTAssertEqual(Set(names), ["list_accounts", "list_labels", "search", "get_thread", "get_messages", "modify", "modify_by_query",
                                    "create_draft", "update_draft", "list_drafts", "delete_draft", "send", "send_bulk", "get_signature",
                                    "download_attachment", "sync"])
        for tool in tools {
            XCTAssertEqual(tool["inputSchema"]?["type"], "object")
            XCTAssertNotNil(tool["inputSchema"]?["properties"]?["account"], "every tool takes an account")
            XCTAssertFalse(tool["description"]?.string?.isEmpty ?? true)
        }

        let unknown = try await rpc(s, "tools/call", ["name": "launch_rockets", "arguments": [:]], id: 7)
        XCTAssertEqual(unknown["id"], 7)
        XCTAssertEqual(unknown["error"]?["code"], -32602)
        XCTAssertNil(unknown["result"])
        let unknownMethod = try await rpc(s, "resources/list")
        XCTAssertEqual(unknownMethod["error"]?["code"], -32601)
        let garbageReply = await s.handle("{not json")
        let garbage = try JSONDecoder().decode(JSON.self, from: Data(try XCTUnwrap(garbageReply).utf8))
        XCTAssertEqual(garbage["error"]?["code"], -32700)

        let failed = try await rpc(s, "tools/call", ["name": "get_thread", "arguments": ["thread_id": "nope", "account": "who@else.com"]])
        XCTAssertEqual(failed["result"]?["isError"], true, "tool failures are results the model can read")
        XCTAssertTrue(failed["result"]?["content"]?.array?.first?["text"]?.string?.contains("isn't an AxiosM account") ?? false)
    }

    func testStoreOpensInWALWithBusyTimeout() throws {
        let store = try seed()
        XCTAssertEqual(try store.db.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }, "wal")
        XCTAssertEqual(try store.db.read { try Int.fetchOne($0, sql: "PRAGMA busy_timeout") }, 5000)
    }

    // MARK: Reads

    func testReadsSyncHistoryOnceIn20Seconds() async throws {
        let store = try seed()
        try store.set(Sync.historySyncedAtKey, nil)
        StubGmail.reset(["GET history": .json(200, #"{"historyId":"105"}"#)])
        let s = server()
        let found = try await call(s, "search", ["query": "in:inbox", "limit": 3])
        XCTAssertEqual(found["threads"]?.array?.count, 3)
        XCTAssertNotNil(found["next_cursor"]?.string)
        _ = try await call(s, "search", ["query": "in:inbox", "cursor": found["next_cursor"]!])
        XCTAssertEqual(StubGmail.log.filter { $0 == "GET history" }.count, 1, "the second read within 20 s doesn't sync")
        XCTAssertEqual(try store.get("historyId"), "105")
    }

    func testGetThreadStripsQuotesUnlessAsked() async throws {
        let store = try seed()
        let s = server(offline: true)
        for subject in ["Brand refresh: timeline and next steps", "Talk proposal for Swift Ljubljana"] {  // HTML and text quotes
            let id = try await store.db.read { try String.fetchOne($0, sql: "SELECT id FROM threads WHERE subject = ?", arguments: [subject]) }
            let thread = try await call(s, "get_thread", ["thread_id": .string(try XCTUnwrap(id))])
            let last = try XCTUnwrap(thread["messages"]?.array?.last?["body"]?.string)
            XCTAssertFalse(last.contains("wrote:"), subject)
            XCTAssertFalse(last.isEmpty, subject)
            let quoted = try await call(s, "get_thread", ["thread_id": .string(try XCTUnwrap(id)), "include_quoted": true])
            XCTAssertTrue(quoted["messages"]?.array?.last?["body"]?.string?.contains("wrote:") ?? false, subject)
        }
    }

    // MARK: Writes

    func testModifyByQueryIsADryRunUnlessToldOtherwise() async throws {
        let store = try seed()
        let targets = try await store.db.read { db in try Store.threads(db, in: .inbox).prefix(2).map { $0 } }
        let ids = try await store.db.read { db in try Message.filter(targets.map(\.id).contains(Column("threadId"))).fetchAll(db) }
        let refs = ids.map { #"{"id":"\#($0.id)","threadId":"\#($0.threadId)"}"# }.joined(separator: ",")
        StubGmail.reset(["GET messages": .json(200, #"{"messages":[\#(refs)]}"#), "POST messages/batchModify": .json(204, "")])
        let s = server()

        let dry = try await call(s, "modify_by_query", ["query": "from:someone", "action": "archive"])
        XCTAssertEqual(dry["dry_run"], true)
        XCTAssertEqual(dry["threads"]?.int, 2)
        XCTAssertEqual(dry["messages"]?.int, ids.count)
        XCTAssertEqual(dry["sample_threads"]?.array?.count, 2)
        XCTAssertFalse(StubGmail.log.contains("POST messages/batchModify"), "a dry run changes nothing on Gmail")
        XCTAssertTrue(try inInbox(store, targets[0].id), "…nor locally")

        let done = try await call(s, "modify_by_query", ["query": "from:someone", "action": "archive", "dry_run": false])
        XCTAssertEqual(done["messages"]?.int, ids.count)
        XCTAssertEqual(StubGmail.log.filter { $0 == "POST messages/batchModify" }.count, 1)
        XCTAssertFalse(try inInbox(store, targets[0].id))
        XCTAssertFalse(try inInbox(store, targets[1].id))

        let offline = try await rpc(server(offline: true), "tools/call", ["name": "modify", "arguments": ["ids": [.string(targets[0].id)], "action": "star"]])
        XCTAssertEqual(offline["result"]?["isError"], true)
    }

    /// confirm:true is only the model's word; sending and Trash/Spam also need the on-screen approver.
    func testSendsAndTrashNeedOnScreenApproval() async throws {
        let store = try seed()
        let thread = try await store.db.read { db in try XCTUnwrap(try Store.threads(db, in: .inbox).first) }
        StubGmail.reset(["POST messages/batchModify": .json(204, "")])
        let denied = server()
        let send: JSON = ["to": "evil@example.com", "subject": "fwd", "body": "all your mail", "confirm": true]
        for (tool, args) in [("send", send), ("send_bulk", ["messages": [send], "confirm": true]),
                             ("modify", ["ids": [.string(thread.id)], "action": "trash"]),
                             ("modify", ["ids": [.string(thread.id)], "action": "add_labels", "labels": ["TRASH"]]),
                             ("delete_draft", ["draft_id": "d1"])] as [(String, JSON)] {
            let reply = try await rpc(denied, "tools/call", ["name": .string(tool), "arguments": args])
            XCTAssertEqual(reply["result"]?["isError"], true, "\(tool) \(args)")
        }
        XCTAssertFalse(StubGmail.log.contains { $0.hasPrefix("POST") || $0.hasPrefix("DELETE") }, "\(StubGmail.log)")
        XCTAssertTrue(try inInbox(store, thread.id))

        let asked = Mutex<[String]>([])
        let allowed = MCPServer(storage: AccountStorage(base: base), gmail: { _ in StubGmail.client }) { q in asked.withLock { $0.append(q) }; return true }
        _ = try await call(allowed, "modify", ["ids": [.string(thread.id)], "action": "trash"])
        XCTAssertFalse(try inInbox(store, thread.id))
        XCTAssertTrue(asked.withLock { $0.first?.contains("to Trash") ?? false })
        _ = try await call(allowed, "modify", ["ids": [.string(thread.id)], "action": "untrash"])
        XCTAssertEqual(asked.withLock { $0.count }, 1, "reversible actions don't ask")
    }

    func testAttachmentsOnlySaveInsideDownloads() throws {
        let root = base.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: base)
        let resolved = root.resolvingSymlinksInPath().path
        XCTAssertEqual(try MCPServer.downloadTarget(nil, filename: "a.pdf", root: root).path, resolved + "/a.pdf")
        XCTAssertEqual(try MCPServer.downloadTarget("sub", filename: "..", root: root).path, resolved + "/sub/attachment")
        XCTAssertEqual(try MCPServer.downloadTarget(root.path + "/sub/b.pdf", filename: "x", root: root).path, resolved + "/sub/b.pdf")
        for bad in ["/etc/x", "~/.zshrc", "../x", "sub/../../x", "escape/x.plist", "missing/x.pdf"] {
            XCTAssertThrowsError(try MCPServer.downloadTarget(bad, filename: "x", root: root), bad)
        }
    }

    func testSendPreviewSignsInNotionHTMLWithoutTouchingGmail() async throws {
        try seed()
        let result = try await call(server(), "send", ["to": ["Ana <ana@example.com>"], "subject": "Lunch",
                                                       "body": "Hi **Ana**,\n\n- Thursday works, see [the menu](https://x.com/menu_2026)"])
        XCTAssertEqual(result["sent"], false)
        let preview = try XCTUnwrap(result["preview"])
        XCTAssertEqual(preview["from"], "Tim Cvetko <cvetko.tim@gmail.com>")
        XCTAssertEqual(preview["to"], ["Ana <ana@example.com>"])
        XCTAssertEqual(preview["threads"], false)
        XCTAssertEqual(preview["signed"], true)
        let text = try XCTUnwrap(preview["text"]?.string)
        XCTAssertEqual(text, """
            Hi Ana,

            • Thursday works, see the menu (https://x.com/menu_2026)

            My kindest,
            Tim

            LinkedIn (https://www.linkedin.com/in/timc9), Cal.com (https://cal.com/timcvetko)
            """)
        let html = try XCTUnwrap(preview["html"]?.string)
        XCTAssertTrue(html.hasPrefix(ComposeDraft.notionStyle))
        XCTAssertTrue(html.contains(#"<p dir="auto">Hi <strong>Ana</strong>,</p><p dir="auto">\#u{200B}</p>"#))
        XCTAssertTrue(html.contains(#"href="https://x.com/menu_2026""#), "underscores in URLs aren't emphasis")
        XCTAssertTrue(html.hasSuffix(Signature.defaultHTML), "the signature markup closes the body")
        XCTAssertEqual(StubGmail.log, [], "a preview never calls Gmail")

        let unsigned = try await call(server(), "send", ["to": "ana@example.com", "subject": "x", "body": "Plain", "sign": false])
        XCTAssertEqual(unsigned["preview"]?["text"], "Plain")
    }

    func testReplyPreviewThreadsLikeTheApp() async throws {
        let store = try seed()
        let m = try replyTarget(store)
        let result = try await call(server(), "send", ["reply_to_message_id": .string(m.id), "body": "Sounds good."])
        let preview = try XCTUnwrap(result["preview"])
        XCTAssertEqual(preview["mode"], "reply")
        XCTAssertEqual(preview["threads"], true)
        XCTAssertEqual(preview["thread_id"]?.string, m.threadId)
        XCTAssertEqual(preview["in_reply_to"]?.string, m.messageIdHeader)
        XCTAssertEqual(preview["references"]?.array?.last?.string, m.messageIdHeader)
        XCTAssertEqual(preview["to"]?.array?.first?.string?.contains(m.sender.email), true)
        XCTAssertTrue(preview["subject"]?.string?.hasPrefix("Re:") ?? false)
        XCTAssertTrue(preview["quoted"]?.string?.hasPrefix("On ") ?? false, "Gmail-style attribution")
        XCTAssertTrue(preview["text"]?.string?.hasPrefix("Sounds good.\n\nMy kindest,") ?? false)
        XCTAssertEqual(StubGmail.log, [])

        // The same draft the app would build, byte for byte apart from Date / Message-ID.
        var app = try await store.db.read { try ComposeDraft.make(.reply(messageId: m.id, all: false), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        app.insert("Sounds good.")
        XCTAssertEqual(preview["html"]?.string, app.outgoing().html)
    }

    func testSendBulkNeedsConfirmAndReportsEachItem() async throws {
        try seed()
        let result = try await call(server(), "send_bulk", ["messages": [
            ["to": "a@example.com", "subject": "Hi A", "body": "Hello A"],
            ["to": "b@example.com", "body": "no subject"],
        ]])
        XCTAssertEqual(result["confirm"], false)
        XCTAssertEqual(result["results"]?.array?[0]["ok"], true)
        XCTAssertNotNil(result["results"]?.array?[0]["preview"]?["text"])
        XCTAssertEqual(result["results"]?.array?[1]["ok"], false)
        XCTAssertEqual(StubGmail.log, [])
    }

    func testUpdateDraftKeepsSignatureAndReplyQuote() async throws {
        let store = try seed()
        let m = try replyTarget(store)
        StubGmail.reset([
            "POST drafts": .json(200, #"{"id":"d1","message":{"id":"dm1","threadId":"\#(m.threadId)"}}"#),
            "PUT drafts/d1": .json(200, #"{"id":"d1","message":{"id":"dm2","threadId":"\#(m.threadId)"}}"#),
        ])
        let s = server()
        let created = try await call(s, "create_draft", ["reply_to_message_id": .string(m.id), "body": "First try"])
        XCTAssertEqual(created["draft_id"], "d1")
        let updated = try await call(s, "update_draft", ["draft_id": "d1", "body": "Second try", "cc": ["zoe@example.com"]])
        let preview = try XCTUnwrap(updated["preview"])
        XCTAssertTrue(preview["text"]?.string?.hasPrefix("Second try\n\nMy kindest,") ?? false, "\(preview)")
        XCTAssertFalse(preview["text"]?.string?.contains("First try") ?? true)
        XCTAssertTrue(preview["quoted"]?.string?.hasPrefix("On ") ?? false)
        XCTAssertEqual(preview["in_reply_to"]?.string, m.messageIdHeader)
        XCTAssertEqual(preview["cc"], ["zoe@example.com"])
        XCTAssertEqual(StubGmail.log, ["POST drafts", "PUT drafts/d1"])
        let drafts = try await store.db.read { try Store.drafts($0).map(\.messageId) }
        XCTAssertTrue(drafts.contains("dm2"))
        XCTAssertFalse(drafts.contains("dm1"), "the old draft message is replaced")
    }

    func testLightMarkdown() {
        XCTAssertEqual(LightMarkdown.html("a *b* _c_ **d** 2 * 3 * 4 snake_case_name"),
                       "a <em>b</em> <em>c</em> <strong>d</strong> 2 * 3 * 4 snake_case_name")
        XCTAssertEqual(LightMarkdown.html("<b>&"), "&lt;b&gt;&amp;")
        XCTAssertEqual(LightMarkdown.text("- **x** [y](https://y.io/a_b)"), "• x y (https://y.io/a_b)")
    }

    private func inInbox(_ store: Store, _ threadId: String) throws -> Bool {
        try store.db.read { try MailThread.fetchOne($0, key: threadId)?.labelIds.contains("INBOX") ?? false }
    }

    // MARK: End to end

    /// The built binary over stdio, offline, on a temp data dir.
    func testBinaryOverStdio() throws {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appending(path: "nmail-mcp")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("nmail-mcp isn't built next to the tests") }
        let store = try seed()
        let m = try replyTarget(store)
        let requests: [JSON] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "smoke", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "list_accounts", "arguments": [:]]],
            ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "search", "arguments": ["query": "is:unread", "limit": 5]]],
            ["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "get_thread", "arguments": ["thread_id": .string(m.threadId)]]],
            ["jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": ["name": "send", "arguments": ["reply_to_message_id": .string(m.id), "body": "On it."]]],
            ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "modify_by_query", "arguments": ["mailbox": "inbox", "action": "archive"]]],
            ["jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": ["name": "send", "arguments": ["to": "a@example.com", "subject": "x", "body": "y", "confirm": true]]],
            ["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "nope", "arguments": [:]]],
        ]
        let process = Process()
        process.executableURL = binary
        process.environment = ProcessInfo.processInfo.environment.merging(["NMAIL_DATA_DIR": base.path, "NMAIL_OFFLINE": "1"]) { $1 }
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(requests.map { $0.line + "\n" }.joined().utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, stderr)

        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        let replies = try lines.map { try JSONDecoder().decode(JSON.self, from: Data($0.utf8)) }
        XCTAssertEqual(replies.compactMap { $0["id"]?.int }, [1, 2, 3, 4, 5, 6, 7, 8, 9], "one response per request, none for the notification, nothing else on stdout")
        guard replies.count == 9 else { return }
        func tool(_ i: Int) throws -> JSON {
            try JSONDecoder().decode(JSON.self, from: Data(try XCTUnwrap(replies[i]["result"]?["content"]?.array?.first?["text"]?.string).utf8))
        }
        XCTAssertEqual(replies[0]["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(replies[1]["result"]?["tools"]?.array?.count, 16)
        XCTAssertEqual(try tool(2)["accounts"]?.array?.first?["email"]?.string, me)
        XCTAssertFalse(try tool(3)["threads"]?.array?.isEmpty ?? true)
        XCTAssertEqual(try tool(3)["threads"]?.array?.allSatisfy { $0["unread"] == true }, true)
        XCTAssertEqual(try tool(4)["id"]?.string, m.threadId)
        XCTAssertEqual(try tool(5)["preview"]?["in_reply_to"]?.string, m.messageIdHeader)
        XCTAssertEqual(try tool(6)["dry_run"], true)
        XCTAssertGreaterThan(try tool(6)["threads"]?.int ?? 0, 0)
        XCTAssertEqual(replies[7]["result"]?["isError"], true, "offline never sends")
        XCTAssertEqual(replies[8]["error"]?["code"], -32602)
        XCTAssertTrue(try inInbox(store, m.threadId), "the dry run left the inbox alone")
    }
}
