import Foundation
import GRDB
@testable import MailCore
import XCTest

@MainActor
final class ComposeTests: XCTestCase {
    private func demoApp() throws -> AppState {
        let store = try Store()
        try Fixtures.seed(store)
        return AppState(store: store, gmail: nil)
    }

    private func lastInboxMessage(_ app: AppState, minMessages: Int) throws -> Message {
        try app.store.db.read { db in
            let thread = try XCTUnwrap(try Store.threads(db, in: .inbox).first { $0.messageCount >= minMessages })
            return try XCTUnwrap(try Store.threadDetail(db, id: thread.id)?.messages.last { !$0.isDraft })
        }
    }

    func testReplyAllThreadsCorrectlyAndSigns() throws {
        let app = try demoApp()
        let m = try lastInboxMessage(app, minMessages: 5)
        let d = try app.store.db.read { try ComposeDraft.make(.reply(messageId: m.id, all: true), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        XCTAssertEqual(d.inReplyTo, m.messageIdHeader)
        XCTAssertEqual(d.references.last, m.messageIdHeader)
        XCTAssertEqual(d.threadId, m.threadId)
        XCTAssertEqual(d.to.map(\.email), [m.sender.email])
        XCTAssertFalse(d.cc.contains { $0.email == Fixtures.me.email })
        XCTAssertEqual(d.body, "\n\nMy kindest,\nTim Cvetko")
        XCTAssertTrue(d.subject.hasPrefix("Re:"))
        XCTAssertTrue(d.isPristine)

        let raw = String(decoding: MIME.build(d.outgoing()), as: UTF8.self)
        XCTAssertTrue(raw.contains("In-Reply-To: \(m.messageIdHeader)"))
    }

    func testInsertGoesAboveSignature() {
        var draft = ComposeDraft(mode: .new, from: EmailAddress(name: nil, email: "me@x.com"))
        draft.sign("My kindest,\nTim")
        XCTAssertEqual(draft.typedText, "")
        draft.insert("Standup · 9:30")
        XCTAssertEqual(draft.body, "Standup · 9:30\n\nMy kindest,\nTim")
        draft.insert("Thanks")
        XCTAssertEqual(draft.body, "Standup · 9:30\n\nThanks\n\nMy kindest,\nTim")
        XCTAssertEqual(draft.typedText, "Standup · 9:30\n\nThanks")
    }

    func testSignatureSourcesLocalThenGmailThenDefault() throws {
        let app = try demoApp()
        let (primary, helio) = try app.store.db.read { db in (try Store.sendAs(db)[0], try Store.sendAs(db)[1]) }
        XCTAssertEqual(try app.store.db.read { try Signature.text(for: primary, db: $0) }, Signature.defaultText)
        var blank = helio
        blank.signature = ""
        XCTAssertEqual(try app.store.db.read { try Signature.text(for: blank, db: $0) }, Signature.defaultText)
        try app.store.saveLocalSignature("Cheers,\nTim\n", for: helio)
        XCTAssertEqual(try app.store.db.read { try Signature.text(for: helio, db: $0) }, "Cheers,\nTim")
        XCTAssertTrue(try app.store.db.read(Store.sendAs)[1].signature.contains("Founder, Helio"), "local save must not touch the Gmail copy")
        let d = try app.store.db.read { try ComposeDraft.make(.new(to: []), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        XCTAssertEqual(d.body, "\n\n" + Signature.defaultText)
    }

    func testSwitchingModeAndIdentityKeepsTypedText() throws {
        let app = try demoApp()
        let m = try lastInboxMessage(app, minMessages: 5)
        var d = try app.store.db.read { try ComposeDraft.make(.reply(messageId: m.id, all: false), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        d.body = "Sounds good." + d.body
        try app.store.db.read { try d.switchMode(.forward, db: $0) }
        XCTAssertTrue(d.to.isEmpty)
        XCTAssertNil(d.inReplyTo)
        XCTAssertTrue(d.subject.hasPrefix("Fwd:"))
        XCTAssertEqual(d.typedText, "Sounds good.")

        let identities = try app.store.db.read(Store.sendAs)
        let helioSignature = try app.store.db.read { try Signature.text(for: identities[1], db: $0) }
        d.switchIdentity(to: identities[1], signature: helioSignature)
        XCTAssertEqual(d.from.email, "tim@helio.dev")
        XCTAssertTrue(d.body.contains("Founder, Helio"))
        XCTAssertFalse(d.body.contains("My kindest"))
        XCTAssertEqual(d.typedText, "Sounds good.")
    }

    func testContactsRankPeopleYouWriteTo() throws {
        let app = try demoApp()
        let contacts = try app.store.db.read { try Store.contacts($0, selfEmails: [Fixtures.me.email]) }
        XCTAssertFalse(contacts.contains { $0.address.email == Fixtures.me.email })
        XCTAssertFalse(contacts.contains { $0.address.email.contains("noreply") })
        let priya = try XCTUnwrap(contacts.first { $0.matches("pri") })
        XCTAssertEqual(priya.address.name, "Priya Raman")
        XCTAssertTrue(contacts.contains { $0.matches("zoe") }, "diacritics fold")
        XCTAssertFalse(priya.matches("xyz"))
    }

    func testDemoDraftSaveSendAndUndo() async throws {
        let app = try demoApp()
        let outbox = app.outbox
        var d = ComposeDraft(mode: .new, from: Fixtures.me, to: [EmailAddress(name: "Ana", email: "ana@example.com")], subject: "Hello")
        d.body = "First line"
        d.attachments = [ComposeAttachment(filename: "notes.txt", mimeType: "text/plain", data: Data("hi".utf8))]
        d = try await outbox.saveDraft(d)
        let draftId = try XCTUnwrap(d.draftId)
        XCTAssertEqual(try threads(app, .drafts).count, 3)

        d.body = "Second version"
        d = try await outbox.saveDraft(d)
        XCTAssertEqual(d.draftId, draftId)
        let messageId = try XCTUnwrap(d.draftMessageId)
        XCTAssertEqual(try threads(app, .drafts).count, 3)
        XCTAssertTrue(try threads(app, .drafts).contains { $0.snippet == "Second version" && $0.id == d.threadId }, messageId)

        outbox.send(d, reopen: .new(to: []))
        XCTAssertNotNil(outbox.pending)
        XCTAssertTrue(app.commands.run("inbox.undo"))
        XCTAssertNil(outbox.pending)
        let reopened = try XCTUnwrap(app.compose)
        XCTAssertEqual(outbox.restore[reopened.id]?.body, "Second version")

        outbox.sendDelay = .zero
        outbox.send(d, reopen: .new(to: []))
        for _ in 0..<50 where outbox.pending != nil { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(try threads(app, .drafts).count, 2)
        let sent = try XCTUnwrap(try threads(app, .sent).first { $0.subject == "Hello" })
        XCTAssertTrue(sent.hasAttachments)
    }

    private func threads(_ app: AppState, _ box: Mailbox) throws -> [MailThread] {
        try app.store.db.read { try Store.threads($0, in: box) }
    }

    func testSignatureHTMLRoundTrip() {
        XCTAssertEqual(Outbox.signatureHTML(fromText: "Tim <CEO>\nHelio\n"), "Tim &lt;CEO&gt;<br>Helio")
        XCTAssertEqual(MIME.plainText(fromHTML: Outbox.signatureHTML(fromText: "Tim\nHelio")), "Tim\nHelio")
    }
}

@MainActor
final class SessionTests: XCTestCase {
    func testSignOutClearsStoreAndReturnsToSignIn() async throws {
        let store = try Store()
        try Fixtures.seed(store)
        let app = AppState(store: store, gmail: nil)
        app.isAccountMenuOpen = true
        await app.signOut()
        XCTAssertEqual(app.isSignedIn, false)
        XCTAssertNil(app.account)
        XCTAssertFalse(app.isAccountMenuOpen)
        let (messages, account) = try await store.db.read { (try Message.fetchCount($0), try Store.account($0)) }
        XCTAssertEqual(messages, 0)
        XCTAssertNil(account)
    }
}
