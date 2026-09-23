import Foundation
import Network
@testable import MailCore
import XCTest

final class LoopbackTests: XCTestCase {
    func testIgnoresPreconnectsAndFaviconThenReturnsCode() async throws {
        let (port, code) = try await Loopback.start()
        let base = "http://127.0.0.1:\(port)"

        let preconnect = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        preconnect.start(queue: .global())
        try await Task.sleep(for: .milliseconds(100))
        preconnect.cancel()

        let (_, favicon) = try await URLSession.shared.data(from: URL(string: "\(base)/favicon.ico")!)
        XCTAssertEqual((favicon as? HTTPURLResponse)?.statusCode, 404)

        let (body, ok) = try await URLSession.shared.data(from: URL(string: "\(base)/?code=4/abc&scope=x")!)
        XCTAssertEqual((ok as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("Signed in"))
        let value = try await code.value
        XCTAssertEqual(value, "4/abc")
    }

    func testGoogleErrorSurfaces() async throws {
        let (port, code) = try await Loopback.start()
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/?error=access_denied")!)
        do {
            _ = try await code.value
            XCTFail("expected an error")
        } catch AuthError.badResponse(let message) {
            XCTAssertTrue(message.contains("access_denied"))
        }
    }
}
