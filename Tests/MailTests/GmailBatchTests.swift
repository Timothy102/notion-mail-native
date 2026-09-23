import Foundation
@testable import MailCore
import XCTest

final class GmailBatchTests: XCTestCase {
    func testConcurrentFetchReturnsEveryMessage() async throws {
        var routes: [String: StubGmail.Reply] = [:]
        let ids = (0..<100).map { "m\($0)" }
        for id in ids { routes["GET messages/\(id)"] = .json(200, SyncTests.message(id, thread: "t\(id)", labels: ["INBOX"])) }
        StubGmail.reset(routes)
        let fetched = try await StubGmail.client.messages(ids, concurrency: 40)
        XCTAssertEqual(fetched.map(\.id), ids)
    }
}
