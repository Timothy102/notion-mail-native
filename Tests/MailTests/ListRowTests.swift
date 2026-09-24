import XCTest
@testable import MailCore

final class ListRowTests: XCTestCase {
    func testVerificationCodes() {
        let found: [(String, String, String)] = [
            ("One-time verification code", "Keep your account safe. Your code is 143819. It expires in 10 minutes.", "143819"),
            ("143819 is your Stripe verification code", "", "143819"),
            ("Your sign-in code", "Use code: 734-912 to finish signing in.", "734912"),
            ("Vaša koda za prijavo", "Koda za prijavo: 5821. Velja 5 minut.", "5821"),
            ("Your new PIN", "Your PIN is 4821.", "4821"),
            ("Verify your email", "60311275 is your verification code.", "60311275"),
            ("Login verification", "Your one-time passcode 918273 expires soon.", "918273"),
        ]
        for (subject, text, code) in found {
            XCTAssertEqual(VerificationCode.find(subject: subject, text: text), code, subject)
        }
        let none: [(String, String)] = [
            ("Dinner Friday? 🍝", "7:30 works. Door code is 2408, see you Friday"),
            ("Security alert: new sign-in on Mac", "We noticed a new sign-in to your Google Account on 12 Sep 2026."),
            ("Your verification code", "Your code expires in 2026. Call +386 1 234 5678 with questions."),
            ("Confirm your order", "Order 558213 confirmed. Total €1299.00."),
            ("Your code review is ready", "PR #4123 needs your code review; 3 files changed."),
            ("Verification code", "The code costs 2500 EUR per seat."),
            ("Your PIN reset", "Reset link expires on 2025-10-01 at 10:30."),
            ("Weekly metrics — week 38", "Weekly active users 4,812 code"),
        ]
        for (subject, text) in none {
            XCTAssertNil(VerificationCode.find(subject: subject, text: text), subject)
        }
    }

    func testListPreviewDropsLinkExpansions() {
        XCTAssertEqual("My kindest, Tim LinkedIn (https://www.linkedin.com/in/tim) Cal.com (https://cal.com/tim)".listPreview,
                       "My kindest, Tim LinkedIn Cal.com")
        XCTAssertEqual("See <https://example.com/a?b=c> for details".listPreview, "See for details")
        XCTAssertEqual("No links here".listPreview, "No links here")
        XCTAssertEqual(MIME.snippet("Thanks!\n\nTim\nLinkedIn (https://www.linkedin.com/in/tim)"), "Thanks! Tim LinkedIn")
    }

    func testChipsSkipSignatureLogos() {
        func a(_ name: String, _ type: String, size: Int = 90_000, cid: String? = nil, inline: Bool = false) -> Attachment {
            Attachment(id: "m/\(name)", messageId: "m", partId: name, gmailAttachmentId: nil, filename: name, mimeType: type,
                       size: size, contentId: cid, isInline: inline, data: nil)
        }
        XCTAssertTrue(a("IDCard.pdf", "application/pdf").isChip)
        XCTAssertTrue(a("photo.jpg", "image/jpeg").isChip)
        XCTAssertFalse(a("logo.png", "image/png", cid: "logo@x").isChip)
        XCTAssertFalse(a("image001.png", "image/png", size: 8_000).isChip)
        XCTAssertFalse(a("chart.png", "image/png", inline: true).isChip)
        XCTAssertFalse(a("invite.ics", "text/calendar").isChip)
        XCTAssertEqual(a("IDCard.pdf", "application/pdf").kind, .pdf)
        XCTAssertEqual(a("budget.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet").kind, .spreadsheet)
        XCTAssertEqual(a("draft.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document").kind, .document)
    }

    func testRowExtrasFromFixtures() throws {
        let store = try Store()
        try Fixtures.seed(store)
        let threads = try store.db.read { try Store.threads($0, in: .inbox) }
        let extras = try store.db.read { try Store.rowExtras($0, threadIds: threads.map(\.id)) }
        let byThread = { (prefix: String) in extras[threads.first { $0.subject.hasPrefix(prefix) }!.id]! }
        XCTAssertEqual(byThread("Your Stripe verification code").code, "143819")
        XCTAssertEqual(byThread("Your Stripe verification code").sender.email, "verify@stripe.com")
        XCTAssertEqual(byThread("Your travel insurance").files.map(\.filename), ["IDCard_359W2K.pdf"])
        XCTAssertNil(byThread("Dinner Friday").code)
        XCTAssertTrue(byThread("Booking confirmed").files.isEmpty, "the inline boarding QR is not a chip")
        XCTAssertTrue(extras.values.allSatisfy { $0.files.allSatisfy { $0.data == nil } })
        XCTAssertEqual(extras.values.compactMap(\.code), ["143819"])
    }

    func testAttachmentFileFromStore() async throws {
        let store = try Store()
        try Fixtures.seed(store)
        let threads = try await store.db.read { try Store.threads($0, in: .inbox) }
        let extras = try await store.db.read { try Store.rowExtras($0, threadIds: threads.map(\.id)) }
        let pdf = try XCTUnwrap(extras.values.flatMap(\.files).first { $0.filename == "IDCard_359W2K.pdf" })
        let url = try await Attachment.file(id: pdf.id, store: store, gmail: nil)
        XCTAssertEqual(url.lastPathComponent, "IDCard_359W2K.pdf")
        XCTAssertTrue(try Data(contentsOf: url).starts(with: Data("%PDF".utf8)))
    }

    func testAvatarHelpers() {
        XCTAssertEqual(SenderAvatars.baseDomain("mail.notion.so"), "notion.so")
        XCTAssertEqual(SenderAvatars.baseDomain("news.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(SenderAvatars.baseDomain("stripe.com"), "stripe.com")
        XCTAssertTrue(SenderAvatars.isFreemail("gmail.com"))
        XCTAssertTrue(SenderAvatars.isFreemail("yahoo.co.uk"))
        XCTAssertFalse(SenderAvatars.isFreemail("stripe.com"))
        XCTAssertEqual(SenderAvatars.colorIndex("Ana@Example.com", count: 9), SenderAvatars.colorIndex("ana@example.com", count: 9))
        XCTAssertEqual(SenderAvatars.initial("  Łukasz"), "Ł")
    }

    func testDemoAvatarsResolveBrandLogosWithoutNetwork() async throws {
        let store = try Store()
        try Fixtures.seed(store)
        let avatars = SenderAvatars(directory: nil, ownPhoto: nil, store: store, isDemo: true)
        guard case .image(let logo, _) = await avatars.resolve("notify@mail.notion.so") else { return XCTFail("no Notion logo") }
        XCTAssertGreaterThanOrEqual(logo.width, 64)
        guard case .none = await avatars.resolve("ana.kovac@gmail.com") else { return XCTFail("freemail should fall back") }
        XCTAssertNotNil(avatars.cached("ANA.kovac@gmail.com"))
    }
}
