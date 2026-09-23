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
        XCTAssertEqual(d.body, "\n\nMy kindest,\nTim\n\nLinkedIn, Cal.com")
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
        var gmailPrimary = primary
        gmailPrimary.signature = "Old <a href=\"https://old.example\">link</a>"
        XCTAssertEqual(try app.store.db.read { try Signature.html(for: gmailPrimary, db: $0) }, Signature.defaultHTML, "primary: local default beats Gmail")
        XCTAssertTrue(try app.store.db.read { try Signature.html(for: helio, db: $0) }.contains("Founder, Helio"), "aliases keep Gmail's")
        var blank = helio
        blank.signature = ""
        XCTAssertEqual(try app.store.db.read { try Signature.html(for: blank, db: $0) }, Signature.defaultHTML)
        try app.store.saveLocalSignature("Cheers,<br>Tim\n", for: helio)
        XCTAssertEqual(try app.store.db.read { try Signature.html(for: helio, db: $0) }, "Cheers,<br>Tim")
        XCTAssertTrue(try app.store.db.read(Store.sendAs)[1].signature.contains("Founder, Helio"), "local save must not touch the Gmail copy")
        let d = try app.store.db.read { try ComposeDraft.make(.new(to: []), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        XCTAssertEqual(d.body, "\n\nMy kindest,\nTim\n\nLinkedIn, Cal.com")
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
        let helioSignature = try app.store.db.read { try Signature.html(for: identities[1], db: $0) }
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

    func testSignatureRendersTextAndLinks() {
        let r = Signature.render(Signature.defaultHTML)
        XCTAssertEqual(r.text, "My kindest,\nTim\n\nLinkedIn, Cal.com")
        XCTAssertEqual(r.links.map { (r.text as NSString).substring(with: $0.range) }, ["LinkedIn", "Cal.com"])
        XCTAssertEqual(r.links.map(\.url.absoluteString), ["https://www.linkedin.com/in/timc9", "https://cal.com/timcvetko"])
        XCTAssertEqual(r.textWithURLs, "My kindest,\nTim\n\nLinkedIn (https://www.linkedin.com/in/timc9), Cal.com (https://cal.com/timcvetko)")
    }

    func testNewMessageIsAlternativeWithSignatureLinks() throws {
        let app = try demoApp()
        var d = try app.store.db.read { try ComposeDraft.make(.new(to: [EmailAddress(name: nil, email: "ana@example.com")]), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        d.body = "Hi <Ana> & co\nSecond line" + d.body
        let out = d.outgoing()
        XCTAssertEqual(out.text, "Hi <Ana> & co\nSecond line\n\nMy kindest,\nTim\n\nLinkedIn (https://www.linkedin.com/in/timc9), Cal.com (https://cal.com/timcvetko)")
        let html = try XCTUnwrap(out.html)
        XCTAssertTrue(html.hasPrefix("<style>"), "Notion Mail's stylesheet leads the HTML part")
        XCTAssertTrue(html.contains(#"<p dir="auto">Hi &lt;Ana&gt; &amp; co</p><p dir="auto">Second line</p><p dir="auto">\#u{200B}</p><div class="signature">"#), html)
        XCTAssertTrue(html.contains(#"href="https://www.linkedin.com/in/timc9" style="color: rgb(120, 119, 116);"><em>LinkedIn</em></a>"#))
        XCTAssertTrue(html.contains(#"href="https://cal.com/timcvetko" style="color: rgb(120, 119, 116);"><em>Cal.com</em></a>"#))

        let raw = String(decoding: MIME.build(out), as: UTF8.self)
        XCTAssertTrue(raw.contains("multipart/alternative"))
        XCTAssertTrue(raw.contains("Content-Type: text/plain"))
        XCTAssertTrue(raw.contains("LinkedIn (https://www.linkedin.com/in/timc9)"))
        let sentHTML = try XCTUnwrap(MIME.extract(MIME.parse(MIME.build(out))).html)
        XCTAssertTrue(sentHTML.contains(#"href="https://cal.com/timcvetko""#))
    }

    func testReplyHTMLHasSignatureAboveGmailQuote() throws {
        let app = try demoApp()
        let m = try lastInboxMessage(app, minMessages: 2)
        var d = try app.store.db.read { try ComposeDraft.make(.reply(messageId: m.id, all: false), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        d.body = "Thanks!" + d.body
        let raw = String(decoding: MIME.build(d.outgoing()), as: UTF8.self)
        let parsed = MIME.parse(MIME.build(d.outgoing()))
        XCTAssertTrue(raw.contains("multipart/alternative"))
        let body = MIME.extract(parsed)
        let html = try XCTUnwrap(body.html)
        let link = try XCTUnwrap(html.range(of: #"href="https://www.linkedin.com/in/timc9""#))
        let quote = try XCTUnwrap(html.range(of: "gmail_quote"))
        XCTAssertLessThan(link.lowerBound, quote.lowerBound)
        XCTAssertTrue(body.text.contains("LinkedIn (https://www.linkedin.com/in/timc9)"))
    }

    func testSavedDraftReopensWithPlainSignatureBlock() async throws {
        let app = try demoApp()
        var d = try await app.store.db.read { try ComposeDraft.make(.new(to: []), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        d.subject = "Links"
        d.body = "Body" + d.body
        d = try await app.outbox.saveDraft(d)
        let id = try XCTUnwrap(d.draftId)
        let reopened = try await app.store.db.read { try ComposeDraft.make(.draft(id: id), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        XCTAssertEqual(reopened.body, d.body)
        XCTAssertEqual(reopened.typedText, "Body")
    }

    /// Compose while a thread is open: the draft is its own thread, never the open one.
    func testNewComposeWithThreadOpenGetsItsOwnDraftThread() async throws {
        let app = try demoApp()
        let open = try XCTUnwrap(try threads(app, .inbox).first { !$0.hasDraft })
        app.open(open.id)
        let reply = try XCTUnwrap(app.replyTarget(threadId: open.id))
        var replyDraft = try await app.store.db.read { try ComposeDraft.make(.reply(messageId: reply.id, all: false), db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        replyDraft.body = "reply text" + replyDraft.body

        XCTAssertTrue(app.commands.run("inbox.compose"))
        guard case .new = try XCTUnwrap(app.compose).kind else { return XCTFail("compose must be a new message") }
        let kind = try XCTUnwrap(app.compose).kind
        var d = try await app.store.db.read { try ComposeDraft.make(kind, db: $0, fallbackFrom: Fixtures.me, signOnReplies: true) }
        XCTAssertNil(d.threadId)
        XCTAssertNil(d.inReplyTo)
        XCTAssertTrue(d.references.isEmpty)

        // A reply save finishing after the composer switched requests must not hand over its ids.
        let savedReply = try await app.outbox.saveDraft(replyDraft)
        d.adopt(savedReply)
        XCTAssertNil(d.threadId)
        XCTAssertNil(d.draftId)

        d.to = [EmailAddress(name: nil, email: "ana@example.com")]
        d.subject = "Fresh"
        d.body = "New thing" + d.body
        let saved = try await app.outbox.saveDraft(d)
        d.adopt(saved)
        XCTAssertNotEqual(d.threadId, open.id)
        XCTAssertNotEqual(d.draftId, savedReply.draftId)
        let raw = String(decoding: MIME.build(d.outgoing()), as: UTF8.self)
        XCTAssertFalse(raw.contains("In-Reply-To"))
        XCTAssertFalse(raw.contains("References"))
        XCTAssertTrue(try threads(app, .drafts).contains { $0.id == d.threadId && $0.subject == "Fresh" })
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
