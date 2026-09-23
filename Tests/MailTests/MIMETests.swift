import Foundation
@testable import MailCore
import XCTest

final class MIMETests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")))
    }

    func testAlternativeWithQuotedPrintableAndEncodedWords() throws {
        let root = MIME.parse(try fixture("alternative-qp.eml"))
        XCTAssertEqual(root.header("Subject"), "Café meeting ☕ tomorrow")
        XCTAssertEqual(EmailAddress.parseList(root.header("From")!).first, EmailAddress(name: "André Pirard", email: "andre@example.be"))
        XCTAssertEqual(EmailAddress.parseList(root.header("To")!),
                       [EmailAddress(name: "Doe, Jane", email: "jane@example.com"), EmailAddress(name: nil, email: "bob@example.com")])
        let body = MIME.extract(root)
        XCTAssertEqual(body.text, "Café at 10? Long line that is soft-wrapped here.")
        XCTAssertEqual(body.html, "<p>Café at <b>10</b>?</p>")
        XCTAssertTrue(body.attachments.isEmpty)
    }

    func testNestedMixedRelatedWithInlineImageAttachmentAndInvite() throws {
        let root = MIME.parse(try fixture("mixed-related.eml"))
        XCTAssertEqual(root.header("From"), "Zoë <zoe@example.com>")
        let body = MIME.extract(root)
        XCTAssertEqual(body.html, "<p>Look <img src=\"cid:logo@x\"></p>")
        XCTAssertEqual(body.attachments.map(\.filename), ["attachment", "račun €.pdf", "invite.ics"])
        let image = body.attachments[0]
        XCTAssertTrue(image.isInline)
        XCTAssertEqual(image.contentId, "logo@x")
        XCTAssertEqual(image.partId, "0.1")
        XCTAssertEqual(image.data?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(body.attachments[1].data, Data("%PDF-1.4".utf8))
        XCTAssertFalse(body.attachments[1].isInline)
        XCTAssertEqual(body.attachments[2].mimeType, "text/calendar")
    }

    func testGmailPayload() throws {
        let gmail = try JSONDecoder().decode(GmailMessage.self, from: try fixture("gmail-payload.json"))
        let (message, attachments) = try XCTUnwrap(Message.make(gmail: gmail))
        XCTAssertEqual(message.subject, "Welcome 👋")
        XCTAssertEqual(message.snippet, "Hi & welcome")
        XCTAssertEqual(message.bodyText, "Hi & welcome!")
        XCTAssertEqual(message.bodyHTML, "<b>Hi</b> welcome!")
        XCTAssertEqual(message.sender.displayName, "Ana Kovač")
        XCTAssertTrue(message.isUnread)
        XCTAssertEqual(message.date, Date(timeIntervalSince1970: 1_758_614_400))
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].gmailAttachmentId, "ANGjdJ9")
        XCTAssertEqual(attachments[0].size, 48213)
        XCTAssertNil(attachments[0].data)
    }

    func testBuildRoundTrip() throws {
        let png = Fixtures.gradientPNG(hue: 0.5, width: 8, height: 8)
        let out = OutgoingMessage(
            from: EmailAddress(name: "Tim Cvetko", email: "tim@example.com"),
            to: [EmailAddress(name: "Zoë Müller", email: "zoe@example.com"), EmailAddress(name: "Doe, Jane", email: "jane@example.com")],
            cc: [EmailAddress(name: nil, email: "cc@example.com")],
            subject: "Übersicht: a long subject with ümlauts that must be split across several encoded words 🎉",
            text: "Hej Zoë,\nsee attached.", html: "<p>Hej Zoë,</p>", quoted: "> earlier",
            inReplyTo: "<a@x>", references: ["<r@x>", "<a@x>"],
            attachments: [OutgoingAttachment(filename: "photo €.png", mimeType: "image/png", data: png)]
        )
        let raw = MIME.build(out)
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(raw.allSatisfy { $0 < 128 }, "RFC 2822 output must be 7-bit")
        XCTAssertFalse(text.split(separator: "\r\n", omittingEmptySubsequences: false).contains { $0.count > 998 })
        XCTAssertFalse(text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "bare LF")

        let root = MIME.parse(raw)
        XCTAssertEqual(root.header("Subject"), out.subject)
        XCTAssertEqual(EmailAddress.parseList(root.header("To")!), out.to)
        XCTAssertEqual(root.header("In-Reply-To"), "<a@x>")
        XCTAssertEqual(root.header("References"), "<r@x> <a@x>")
        let body = MIME.extract(root)
        XCTAssertEqual(body.text, "Hej Zoë,\r\nsee attached.\r\n\r\n> earlier".replacingOccurrences(of: "\r\n", with: "\n"))
        XCTAssertTrue(body.html?.hasPrefix("<p>Hej Zoë,</p>") == true)
        XCTAssertEqual(body.attachments.first?.filename, "photo €.png")
        XCTAssertEqual(body.attachments.first?.data, png)
    }

    func testReplyAndForwardHeaders() {
        let me = EmailAddress(name: "Tim", email: "tim@example.com")
        let original = Message(
            id: "m", threadId: "t", labelIds: ["INBOX"], from: "Priya <priya@x.com>", to: "Tim <tim@example.com>, Marco <marco@x.com>",
            cc: "Zoë <zoe@x.com>", bcc: "", replyTo: "", subject: "Re: Roadmap", snippet: "", date: .now, internalDate: 0,
            bodyText: "line one\nline two", bodyHTML: nil, messageIdHeader: "<m@x>", references: "<root@x>", inReplyTo: "<root@x>")
        let reply = OutgoingMessage.reply(to: original, all: true, from: me)
        XCTAssertEqual(reply.subject, "Re: Roadmap")
        XCTAssertEqual(reply.to.map(\.email), ["priya@x.com"])
        XCTAssertEqual(reply.cc.map(\.email), ["marco@x.com", "zoe@x.com"])
        XCTAssertEqual(reply.inReplyTo, "<m@x>")
        XCTAssertEqual(reply.references, ["<root@x>", "<m@x>"])
        XCTAssertEqual(reply.threadId, "t")
        XCTAssertTrue(reply.quoted!.hasSuffix("> line one\n> line two"))
        XCTAssertTrue(OutgoingMessage.reply(to: original, all: false, from: me).cc.isEmpty)
        XCTAssertEqual(OutgoingMessage.forward(original, from: me).subject, "Fwd: Re: Roadmap")
    }

    func testHTMLToText() {
        XCTAssertEqual(MIME.plainText(fromHTML: "<style>p{}</style><p>A&amp;B</p><p>C&#8217;s<br>D</p>"), "A&B\nC’s\nD")
    }
}
