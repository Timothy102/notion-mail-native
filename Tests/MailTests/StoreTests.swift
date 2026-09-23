import Foundation
@testable import MailCore
import XCTest

final class StoreTests: XCTestCase {
    private func seeded() throws -> Store {
        let store = try Store()
        try Fixtures.seed(store)
        return store
    }

    func testFixturesLookLikeARealInbox() throws {
        let store = try seeded()
        try store.db.read { db in
            let inbox = try Store.threads(db, in: .inbox)
            XCTAssertGreaterThanOrEqual(try MailThread.fetchCount(db), 55)
            XCTAssertGreaterThan(inbox.count, 45)
            XCTAssertTrue(inbox.contains { $0.messageCount >= 5 })
            XCTAssertTrue(inbox.contains(where: \.isUnread))
            XCTAssertTrue(inbox.contains(where: \.isStarred))
            XCTAssertTrue(inbox.contains(where: \.hasAttachments))
            XCTAssertFalse(try Store.threads(db, in: .sent).isEmpty)
            XCTAssertEqual(try Store.threads(db, in: .drafts).count, 2)
            XCTAssertTrue(try Store.threads(db, in: .spam).isEmpty)
            XCTAssertEqual(try Store.unreadCounts(db)["DRAFT"], 2)
            XCTAssertEqual(try Store.sendAs(db).first?.isDefault, true)
            XCTAssertEqual(inbox, inbox.sorted { $0.lastDate > $1.lastDate })
            let invite = try Attachment.fetchAll(db).first { $0.mimeType == "text/calendar" }
            XCTAssertNotNil(invite?.data)
        }
    }

    func testSearchUsesFTSWithPrefixesAndDiacritics() throws {
        let store = try seeded()
        try store.db.read { db in
            XCTAssertEqual(try Store.searchThreads(db, text: "offsite").first?.subject, "Offsite venue options")
            XCTAssertFalse(try Store.searchThreads(db, text: "Zoe").isEmpty, "diacritics fold")
            XCTAssertFalse(try Store.searchThreads(db, text: "bohin").isEmpty, "prefix match in body")
            XCTAssertTrue(try Store.searchThreads(db, text: "xyzzyq").isEmpty)
        }
    }

    func testModifyAndRestore() throws {
        let store = try seeded()
        let thread = try XCTUnwrap(store.db.read { try Store.threads($0, in: .inbox).first(where: \.isUnread) })
        let snapshot = try store.modify(threadIds: [thread.id], add: ["STARRED"], remove: ["INBOX", "UNREAD"])
        try store.db.read { db in
            let t = try XCTUnwrap(MailThread.fetchOne(db, key: thread.id))
            XCTAssertFalse(t.isUnread)
            XCTAssertTrue(t.isStarred)
            XCTAssertFalse(try Store.threads(db, in: .inbox).contains { $0.id == thread.id })
        }
        try store.restore(snapshot)
        try store.db.read { db in
            XCTAssertEqual(try MailThread.fetchOne(db, key: thread.id), thread)
        }
    }

    @MainActor
    func testActionsUndoAndFocusAdvance() throws {
        let app = AppState(store: try seeded(), gmail: nil)
        let ids = try app.store.db.read { try Store.threads($0, in: .inbox).map(\.id) }
        app.visibleThreadIds = ids
        app.focusedThreadId = ids[1]
        app.commands.run("thread.archive")
        XCTAssertEqual(app.focusedThreadId, ids[2])
        XCTAssertEqual(app.toast?.text, "Archived")
        XCTAssertFalse(try app.store.db.read { try Store.threads($0, in: .inbox) }.contains { $0.id == ids[1] })
        app.undo()
        XCTAssertTrue(try app.store.db.read { try Store.threads($0, in: .inbox) }.contains { $0.id == ids[1] })
        XCTAssertNil(app.toast)
    }

    @MainActor
    func testRemindArchivesThenReturnsUnread() throws {
        let app = AppState(store: try seeded(), gmail: nil)
        let thread = try XCTUnwrap(app.store.db.read { try Store.threads($0, in: .inbox).first { !$0.isUnread } })
        let inInbox = { try app.store.db.read { try Store.threads($0, in: .inbox) }.first { $0.id == thread.id } }
        app.actions.remind([thread.id], at: .now.addingTimeInterval(3_600))
        XCTAssertNil(try inInbox())
        app.actions.wakeDueReminders()
        XCTAssertNil(try inInbox(), "not due yet")
        app.actions.wakeDueReminders(now: .now.addingTimeInterval(7_200))
        XCTAssertEqual(try inInbox()?.isUnread, true)
    }

    @MainActor
    func testOpenMarksRead() throws {
        let app = AppState(store: try seeded(), gmail: nil)
        let unread = try XCTUnwrap(app.store.db.read { try Store.threads($0, in: .inbox).first(where: \.isUnread) })
        app.open(unread.id)
        XCTAssertEqual(try app.store.db.read { try MailThread.fetchOne($0, key: unread.id)?.isUnread }, false)
        XCTAssertFalse(app.actions.canUndo, "opening is not an undoable action")
    }

    func testMailDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_790_000_000) // Sep 21 2026
        XCTAssertNil(MailDate.group(now.addingTimeInterval(-60), now: now, calendar: cal))
        XCTAssertEqual(MailDate.group(now.addingTimeInterval(-86_400), now: now, calendar: cal), "Yesterday")
        XCTAssertEqual(MailDate.group(now.addingTimeInterval(-3 * 86_400), now: now, calendar: cal), "Last 7 days")
        XCTAssertEqual(MailDate.group(now.addingTimeInterval(-20 * 86_400), now: now, calendar: cal), "Last 30 days")
        XCTAssertEqual(MailDate.group(now.addingTimeInterval(-120 * 86_400), now: now, calendar: cal), "May")
        XCTAssertEqual(MailDate.group(now.addingTimeInterval(-300 * 86_400), now: now, calendar: cal), "Nov 2025")
        XCTAssertEqual(MailDate.list(now.addingTimeInterval(-300 * 86_400), now: now, calendar: cal), "Nov 25, 2025")
        XCTAssertFalse(MailDate.list(now.addingTimeInterval(-60), now: now, calendar: cal).contains("\u{202F}"), "normal space before AM/PM")
    }

    func testGmailLabelColorMapping() {
        XCTAssertEqual(MailLabel.colorName(gmailHex: "#fb4c2f"), "red")
        XCTAssertEqual(MailLabel.colorName(gmailHex: "#16a766"), "green")
        XCTAssertEqual(MailLabel.colorName(gmailHex: "#4a86e8"), "blue")
        XCTAssertEqual(MailLabel.colorName(gmailHex: "#ffffff"), "lightGray")
    }
}
