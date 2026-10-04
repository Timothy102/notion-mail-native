import Foundation
@testable import MailCore
import XCTest

final class SecretsTests: XCTestCase {
    func testRoundTripAndOwnerOnlyPermissions() throws {
        let saved = Secrets.url
        let dir = FileManager.default.temporaryDirectory.appending(path: "secrets-\(UUID().uuidString)")
        Secrets.url = dir.appending(path: "Mail/secrets.json")
        defer { Secrets.url = saved; try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(Secrets.get("refresh_token"))
        try Secrets.set("refresh_token", "1//abc")
        try Secrets.set("notion", "secret_x")
        XCTAssertEqual(Secrets.get("refresh_token"), "1//abc")
        let perms = try FileManager.default.attributesOfItem(atPath: Secrets.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)

        Secrets.delete("refresh_token")
        XCTAssertNil(Secrets.get("refresh_token"))
        XCTAssertEqual(Secrets.get("notion"), "secret_x", "deleting one key keeps the others")
    }
}

final class AuthRevokedTests: XCTestCase {
    func testOnlyInvalidGrantForgetsTheLogin() {
        XCTAssertTrue(Auth.isRevoked(Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)))
        XCTAssertFalse(Auth.isRevoked(Data(#"{"error":"internal_failure"}"#.utf8)))
        XCTAssertFalse(Auth.isRevoked(Data("<html>Hotel Wi-Fi login</html>".utf8)))
        XCTAssertFalse(Auth.isRevoked(Data()))
    }
}
