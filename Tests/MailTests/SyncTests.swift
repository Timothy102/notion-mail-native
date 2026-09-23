import Foundation
import GRDB
@testable import MailCore
import XCTest

/// Serves canned Gmail responses by request ("GET history", "GET history page=p2", "POST threads/t1/modify"…).
final class StubGmail: URLProtocol, @unchecked Sendable {
    enum Reply { case json(Int, String), offline }
    nonisolated(unsafe) static var routes: [String: Reply] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    static let lock = NSLock()

    static func reset(_ routes: [String: Reply]) {
        lock.withLock { self.routes = routes; requests = [] }
    }

    static var log: [String] { lock.withLock { requests } }

    static var client: GmailClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGmail.self]
        return GmailClient(token: { _ in "token" }, session: URLSession(configuration: config))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path.replacingOccurrences(of: "/gmail/v1/users/me/", with: "")
        let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pageToken" }?.value
        let key = "\(request.httpMethod ?? "GET") \(path)" + (page.map { " page=\($0)" } ?? "")
        let reply = Self.lock.withLock {
            Self.requests.append(key)
            return Self.routes[key] ?? .json(404, #"{"error":{"message":"not stubbed"}}"#)
        }
        switch reply {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .json(let status, let body):
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

final class SyncTests: XCTestCase {
    private static func message(_ id: String, thread: String, labels: [String], subject: String = "Hello") -> String {
        let body = Data("Body of \(id)".utf8).base64EncodedString()
        return """
        {"id":"\(id)","threadId":"\(thread)","labelIds":[\(labels.map { "\"\($0)\"" }.joined(separator: ","))],"snippet":"Body of \(id)","internalDate":"\(Int(Date.now.timeIntervalSince1970 * 1000))",
         "payload":{"mimeType":"text/plain","headers":[{"name":"From","value":"Ana <ana@example.com>"},{"name":"Subject","value":"\(subject)"}],"body":{"data":"\(body)"}}}
        """
    }

    private static func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/history"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let basics: [String: StubGmail.Reply] = [
        "GET profile": .json(200, #"{"emailAddress":"tim@example.com","messagesTotal":3,"historyId":"500"}"#),
        "GET settings/sendAs": .json(200, #"{"sendAs":[{"sendAsEmail":"tim@example.com","displayName":"Tim","isPrimary":true,"isDefault":true}]}"#),
        "GET labels": .json(200, #"{"labels":[{"id":"INBOX","name":"INBOX","type":"system"},{"id":"Label_7","name":"Receipts","type":"user"}]}"#),
        "GET drafts": .json(200, "{}"),
    ]

    private func seededStore() throws -> Store {
        let store = try Store()
        let sync = Sync(gmail: StubGmail.client, store: store)
        let seed = try [Self.message("m1", thread: "t1", labels: ["INBOX", "UNREAD"]), Self.message("m2", thread: "t2", labels: ["INBOX"])]
            .map { try JSONDecoder().decode(GmailMessage.self, from: Data($0.utf8)) }
        try sync.ingest(seed)
        try store.save(labels: [MailLabel(id: "Label_gone", name: "Old", isSystem: false, color: nil)])
        try store.set("historyId", "100")
        return store
    }

    func testHistoryFoldsRecordsInOrder() throws {
        var changes = HistoryChanges()
        changes.add(try JSONDecoder().decode(GmailHistory.self, from: Data(Self.fixture("page1").utf8)).history ?? [])
        changes.add(try JSONDecoder().decode(GmailHistory.self, from: Data(Self.fixture("page2").utf8)).history ?? [])
        XCTAssertEqual(changes.added, ["m3"])
        XCTAssertEqual(changes.deleted, ["m2", "m4"])
        XCTAssertEqual(changes.labels["m1"]?.add, ["STARRED"])
        XCTAssertEqual(changes.labels["m1"]?.remove, ["UNREAD", "Label_7", "INBOX"])
        XCTAssertNil(changes.labels["m4"])
    }

    func testIncrementalSyncAppliesHistoryPages() async throws {
        let store = try seededStore()
        var routes = Self.basics
        routes["GET history"] = .json(200, try Self.fixture("page1"))
        routes["GET history page=p2"] = .json(200, try Self.fixture("page2"))
        routes["GET messages/m3"] = .json(200, Self.message("m3", thread: "t1", labels: ["INBOX", "UNREAD"], subject: "Re: Hello"))
        routes["GET messages/m9"] = .json(200, Self.message("m9", thread: "t9", labels: ["STARRED"], subject: "Old but starred"))
        StubGmail.reset(routes)
        try await Sync(gmail: StubGmail.client, store: store).run()

        XCTAssertEqual(try store.get("historyId"), "109")
        try await store.db.read { db in
            XCTAssertEqual(try Message.fetchOne(db, key: "m1")?.labelIds, ["STARRED"])
            XCTAssertNotNil(try Message.fetchOne(db, key: "m3"))
            XCTAssertNil(try Message.fetchOne(db, key: "m2"))
            XCTAssertNil(try MailThread.fetchOne(db, key: "t2"), "thread of the only deleted message is gone")
            XCTAssertEqual(try MailThread.fetchOne(db, key: "t1")?.messageCount, 2)
            XCTAssertEqual(try MailThread.fetchOne(db, key: "t1")?.isUnread, true, "m3 arrived unread")
            XCTAssertEqual(try Store.threads(db, in: .starred).map(\.id).sorted(), ["t1", "t9"])
            XCTAssertNil(try MailLabel.fetchOne(db, key: "Label_gone"), "labels deleted on Gmail are dropped")
            XCTAssertNotNil(try MailLabel.fetchOne(db, key: "Label_7"))
        }
        let fetched = StubGmail.log.filter { $0.hasPrefix("GET messages/") }.sorted()
        XCTAssertEqual(fetched, ["GET messages/m3", "GET messages/m9"], "m4 was added and deleted in the window, m1 is known")
    }

    func testExpiredHistoryIdTriggersFullResync() async throws {
        let store = try seededStore()
        var routes = Self.basics
        routes["GET history"] = .json(404, #"{"error":{"message":"Requested entity was not found."}}"#)
        routes["GET messages"] = .json(200, #"{"messages":[{"id":"m1","threadId":"t1"},{"id":"m5","threadId":"t5"}]}"#)
        routes["GET messages/m5"] = .json(200, Self.message("m5", thread: "t5", labels: ["INBOX"]))
        StubGmail.reset(routes)
        var sync = Sync(gmail: StubGmail.client, store: store)
        let progress = Progress()
        sync.progress = { fetched, total in progress.record(fetched, total) }
        let requestsAtAccount = Progress()
        sync.onAccount = { _ in requestsAtAccount.record(StubGmail.log.filter { $0.hasPrefix("GET messages") }.count, 0) }
        try await sync.run()

        XCTAssertEqual(requestsAtAccount.values.first?.0, 0, "the profile is published before any mail is listed or fetched")
        XCTAssertEqual(try store.get("historyId"), "500", "resync restarts from the profile's history id")
        try await store.db.read { db in
            XCTAssertEqual(try Message.fetchAll(db).map(\.id).sorted(), ["m1", "m5"], "m2 is gone from Gmail, m1 isn't refetched")
        }
        XCTAssertEqual(progress.values.last?.0, 2)
        XCTAssertEqual(progress.values.last?.1, 2)
        XCTAssertFalse(StubGmail.log.contains("GET messages/m1"))
    }

    @MainActor
    func testRejectedMutationRollsBackAndToasts() async throws {
        let store = try seededStore()
        StubGmail.reset(["POST threads/t1/modify": .json(400, #"{"error":{"message":"Invalid label"}}"#)])
        let actions = MailActions(store: store, gmail: StubGmail.client)
        var toasts: [String] = []
        actions.onToast = { toasts.append($0.text) }
        actions.archive(["t1"])
        XCTAssertFalse(try inInbox(store, "t1"), "applied locally at once")
        await actions.settle()
        XCTAssertTrue(try inInbox(store, "t1"), "rolled back")
        XCTAssertEqual(toasts.last, "Gmail didn't accept the change, so it was undone")
        XCTAssertNil(try store.get(MailActions.pendingKey))
    }

    @MainActor
    func testOfflineMutationStaysQueuedAndIsSentLater() async throws {
        let store = try seededStore()
        StubGmail.reset(["POST threads/t1/modify": .offline])
        let actions = MailActions(store: store, gmail: StubGmail.client)
        var offline: [Bool] = []
        actions.onOfflineChange = { offline.append($0) }
        actions.archive(["t1"])
        actions.setStarred(["t2"], true)
        await actions.settle()
        XCTAssertEqual(offline, [true])
        XCTAssertFalse(try inInbox(store, "t1"), "offline keeps the local change")
        XCTAssertEqual(actions.pendingCount, 2)

        XCTAssertEqual(MailActions(store: store, gmail: nil).pendingCount, 2, "queue survives a relaunch")

        StubGmail.reset(["POST threads/t1/modify": .json(200, #"{"id":"t1"}"#), "POST threads/t2/modify": .json(200, #"{"id":"t2"}"#)])
        actions.resume()
        for _ in 0..<400 where actions.pendingCount > 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(offline, [true, false])
        XCTAssertEqual(actions.pendingCount, 0)
        XCTAssertEqual(StubGmail.log, ["POST threads/t1/modify", "POST threads/t2/modify"], "sent in order")
        XCTAssertNil(try store.get(MailActions.pendingKey))
    }

    @MainActor
    func testReapplyKeepsQueuedChangesOverSyncedState() throws {
        let store = try seededStore()
        StubGmail.reset(["POST threads/t1/modify": .offline])
        let actions = MailActions(store: store, gmail: StubGmail.client)
        actions.archive(["t1"])
        try store.setLabels(messageId: "m1", ["INBOX", "UNREAD"])
        actions.reapplyPending()
        XCTAssertFalse(try inInbox(store, "t1"))
    }

    private func inInbox(_ store: Store, _ threadId: String) throws -> Bool {
        try store.db.read { try MailThread.fetchOne($0, key: threadId)?.labelIds.contains("INBOX") ?? false }
    }
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(Int, Int)] = []
    func record(_ a: Int, _ b: Int) { lock.withLock { recorded.append((a, b)) } }
    var values: [(Int, Int)] { lock.withLock { recorded } }
}
