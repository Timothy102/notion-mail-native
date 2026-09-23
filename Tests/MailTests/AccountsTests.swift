import GRDB
import XCTest
@testable import MailCore

final class AccountStorageTests: XCTestCase {
    private var base: URL!
    private var savedSecrets: URL!

    override func setUp() {
        base = FileManager.default.temporaryDirectory.appending(path: "accounts-\(UUID().uuidString)/Mail")
        savedSecrets = Secrets.url
        Secrets.url = base.appending(path: "secrets.json")
    }

    override func tearDown() {
        Secrets.url = savedSecrets
        try? FileManager.default.removeItem(at: base.deletingLastPathComponent())
    }

    func testLegacyInstallMovesToItsAccountDirectory() throws {
        let legacy = base.appending(path: "mail.sqlite")
        let messages: Int = try {
            let store = try Store(path: legacy.path)
            try Fixtures.seed(store)
            try store.set("historyId", "12345")
            return try store.db.read { try Message.fetchCount($0) }
        }()
        try Data("png".utf8).write(to: base.appending(path: "avatar.png"))
        try Secrets.set("refresh_token", "1//legacy")
        try Secrets.set("notion", "secret_x")

        let storage = AccountStorage(base: base)
        try storage.migrateLegacy()
        let email = Fixtures.me.email

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appending(path: "avatar.png").path))
        XCTAssertEqual(try Data(contentsOf: storage.avatar(email)), Data("png".utf8))
        XCTAssertNil(Secrets.get("refresh_token"))
        XCTAssertEqual(Secrets.get(Auth.tokenKey(email)), "1//legacy")
        XCTAssertEqual(Secrets.get("notion"), "secret_x")
        XCTAssertEqual(storage.loadRegistry(), AccountRegistry(emails: [email], active: email, names: [email: "Tim Cvetko"]))

        let moved = try Store(path: storage.database(email))
        XCTAssertEqual(try moved.db.read { try Message.fetchCount($0) }, messages, "mail kept, nothing to re-download")
        XCTAssertEqual(try moved.get("historyId"), "12345", "sync resumes from history, no backfill")

        try storage.migrateLegacy()
        XCTAssertEqual(storage.loadRegistry().emails, [email], "second run is a no-op")
    }

    func testLegacyDatabaseWithoutAccountIsLeftAlone() throws {
        let legacy = base.appending(path: "mail.sqlite")
        _ = try Store(path: legacy.path)
        try Secrets.set("refresh_token", "1//legacy")
        try AccountStorage(base: base).migrateLegacy()
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(Secrets.get("refresh_token"), "1//legacy")
        XCTAssertEqual(AccountStorage(base: base).loadRegistry().emails, [])
    }

    func testRemoveDeletesOnlyThatAccount() throws {
        let storage = AccountStorage(base: base)
        for email in ["a@x.com", "b@x.com"] {
            _ = try Store(path: storage.database(email))
            try Secrets.set(Auth.tokenKey(email), "token-\(email)")
        }
        storage.remove("a@x.com")
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.directory("a@x.com").path))
        XCTAssertNil(Secrets.get(Auth.tokenKey("a@x.com")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.database("b@x.com")))
        XCTAssertEqual(Secrets.get(Auth.tokenKey("b@x.com")), "token-b@x.com")
    }
}

@MainActor
final class AccountManagerTests: XCTestCase {
    func testSwitchingReusesStateAndRegistersShortcuts() throws {
        let accounts = AccountManager(demo: Fixtures.accounts, signedIn: 2)
        try accounts.start()
        let first = try XCTUnwrap(accounts.app)
        first.palette = .commands
        XCTAssertEqual(first.commands["account.switch.2"]?.shortcuts, ["cmd+2"])
        XCTAssertEqual(first.commands["account.switch.2"]?.title, "Switch to tim@helio.dev")
        XCTAssertNil(first.commands["account.switch.3"])

        XCTAssertTrue(first.commands.run("account.switch.2"))
        let second = try XCTUnwrap(accounts.app)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.account?.email, "tim@helio.dev")
        XCTAssertNil(first.palette, "layers don't stay open behind the switch")

        accounts.switchTo(Fixtures.me.email)
        XCTAssertTrue(accounts.app === first, "switching back reuses the AppState")
    }

    func testSignOutOpensNextAccountThenSignIn() async throws {
        let accounts = AccountManager(demo: Fixtures.accounts, signedIn: 2)
        try accounts.start()
        await accounts.signOut()
        XCTAssertEqual(accounts.emails, ["tim@helio.dev"])
        XCTAssertEqual(accounts.app?.account?.email, "tim@helio.dev")
        XCTAssertNil(accounts.app?.commands["account.switch.2"])
        await accounts.signOut()
        XCTAssertNil(accounts.app)
        XCTAssertEqual(accounts.emails, [])
    }
}
