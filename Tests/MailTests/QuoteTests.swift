import Foundation
@testable import MailCore
import XCTest

final class QuoteTests: XCTestCase {
    func testGmailQuoteSplitsAtContainer() {
        let html = #"<div dir="ltr">Sounds good.</div><br><div class="gmail_quote"><div class="gmail_attr">On Mon, Lizzy wrote:<br></div><blockquote class="gmail_quote">Earlier<blockquote class="gmail_quote">Oldest</blockquote></blockquote></div>"#
        let (new, quoted) = Quote.split(html: html)
        XCTAssertEqual(new, #"<div dir="ltr">Sounds good.</div>"#)
        XCTAssertTrue(quoted!.hasPrefix(#"<div class="gmail_quote">"#))
        XCTAssertTrue(quoted!.contains("Oldest</blockquote></blockquote>"))
    }

    func testAppleCiteTakesAttributionAlong() {
        let html = #"<div>Yes!</div><div><br><div>On 22 Jan 2026, at 01:22, Lizzy &lt;hello@x.com&gt; wrote:</div><br><blockquote type="cite"><div>Coffee?</div></blockquote></div>"#
        let (new, quoted) = Quote.split(html: html)
        XCTAssertEqual(new, "<div>Yes!</div>")
        XCTAssertTrue(quoted!.contains("On 22 Jan 2026") && quoted!.contains(#"<blockquote type="cite">"#))
    }

    func testOutlookMarkers() {
        let web = #"<p>Thanks</p><div id="appendonsend"></div><hr><div id="divRplyFwdMsg"><b>From:</b> A</div>"#
        XCTAssertTrue(Quote.split(html: web).quoted!.hasPrefix(#"<div id="appendonsend">"#))
        let desktop = #"<p>Thanks</p><div style="border-top:solid #E1E1E1 1pt"><p><b>From:</b> A<br><b>Sent:</b> Monday<br><b>To:</b> B</p></div>"#
        XCTAssertEqual(Quote.split(html: desktop).new, "<p>Thanks</p>")
    }

    func testInlineBlockquoteWithReplyBelowStaysVisible() {
        let html = "<blockquote>Can you make it?</blockquote><p>Yes, see you there.</p>"
        XCTAssertNil(Quote.split(html: html).quoted)
        XCTAssertNotNil(Quote.split(html: "<p>Yes.</p><blockquote>Can you make it?</blockquote>").quoted)
        XCTAssertNil(Quote.split(html: "<blockquote>Only a quote</blockquote>").quoted, "nothing new to show above it")
    }

    func testPlainTextNestedSplitAndHTML() {
        let text = "Great, thanks.\n\nOn Tue, Jan 20, 2026 at 9:00 AM, Lizzy <hello@x.com>\nwrote:\n> Are we on?\n>\n> On Mon, Tim wrote:\n>> Friday works.\n"
        let (new, quoted) = Quote.split(text: text)
        XCTAssertEqual(new, "Great, thanks.")
        XCTAssertTrue(quoted!.hasPrefix("On Tue"))
        XCTAssertEqual(Quote.html(fromText: quoted!),
                       "On Tue, Jan 20, 2026 at 9:00 AM, Lizzy &lt;hello@x.com&gt;<br>wrote:<br><blockquote>Are we on?<br><br>On Mon, Tim wrote:<br><blockquote>Friday works.<br></blockquote></blockquote>")
        XCTAssertNil(Quote.split(text: "> a\nmy reply below").quoted)
        XCTAssertEqual(MIME.snippet(text), "Great, thanks.")
    }

    func testReplyBuildNestsGmailQuote() throws {
        let earlier = #"<div dir="ltr">Friday?</div><br><div class="gmail_quote"><div class="gmail_attr">On Mon, Tim wrote:<br></div><blockquote class="gmail_quote">Lunch soon?</blockquote></div>"#
        let original = Message(
            id: "m", threadId: "t", labelIds: ["INBOX"], from: "Lizzy <hello@x.com>", to: "Tim <tim@example.com>",
            cc: "", bcc: "", replyTo: "", subject: "Lunch", snippet: "", date: Date(timeIntervalSince1970: 1_769_044_920), internalDate: 0,
            bodyText: "Friday?\n\nOn Mon, Tim wrote:\n> Lunch soon?", bodyHTML: "<html><body>\(earlier)</body></html>",
            messageIdHeader: "<m@x>", references: "", inReplyTo: "")
        var reply = OutgoingMessage.reply(to: original, all: false, from: EmailAddress(name: "Tim", email: "tim@example.com"))
        reply.text = "Works for me."
        let body = MIME.extract(MIME.parse(MIME.build(reply)))
        let attribution = "On \(MIME.quoteDate(original.date)), Lizzy &lt;hello@x.com&gt; wrote:"
        let html = try XCTUnwrap(body.html)
        XCTAssertTrue(html.hasPrefix(#"<div dir="ltr">Works for me.<br></div><br><div class="gmail_quote"><div dir="ltr" class="gmail_attr">"# + attribution + "<br></div>"), html)
        XCTAssertTrue(html.contains(#"<blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex">"# + earlier + "</blockquote></div>"))
        XCTAssertEqual(body.text.replacingOccurrences(of: "\r\n", with: "\n"), "Works for me.\n\nOn \(MIME.quoteDate(original.date)), Lizzy <hello@x.com> wrote:\n> Friday?\n>\n> On Mon, Tim wrote:\n>> Lunch soon?")
        XCTAssertEqual(Quote.split(html: html).new, #"<div dir="ltr">Works for me.<br></div>"#)

        let forward = OutgoingMessage.forward(original, from: EmailAddress(name: "Tim", email: "tim@example.com"))
        XCTAssertTrue(forward.quotedHTML!.contains("---------- Forwarded message ---------<br>From: <strong class=\"gmail_sendername\" dir=\"auto\">Lizzy</strong>"))
    }
}
