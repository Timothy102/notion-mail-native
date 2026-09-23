import Foundation
@testable import MailCore
import XCTest

final class MailHTMLTests: XCTestCase {
    private let palette = MailHTML.Palette(text: "#111", link: "#222", quote: "#333")

    private func part(_ cid: String?, data: Data? = Data([1]), remoteId: String? = nil) -> Attachment {
        Attachment(id: "m/\(cid ?? "x")", messageId: "m", partId: "1", gmailAttachmentId: remoteId, filename: "a.png",
                   mimeType: "image/png", size: 1, contentId: cid, isInline: true, data: data)
    }

    func testRewritesCIDReferencesOnly() {
        let html = #"<img src="cid:logo@x"><td background='CID:bg@x'><div style="background:url(cid:bg@x)">cid: in text</div>"#
        XCTAssertEqual(MailHTML.rewriteCIDs(html),
                       #"<img src="nmail-cid:logo@x"><td background='nmail-cid:bg@x'><div style="background:url(nmail-cid:bg@x)">cid: in text</div>"#)
    }

    func testResolvesCIDURLToPart() throws {
        let parts = [part("other@x"), part("Image001.PNG@01D9"), part("ii_lx9", data: nil, remoteId: "ANG")]
        XCTAssertEqual(MailHTML.attachment(for: try XCTUnwrap(URL(string: "nmail-cid:image001.png@01D9")), in: parts)?.contentId, "Image001.PNG@01D9")
        XCTAssertEqual(MailHTML.attachment(for: try XCTUnwrap(URL(string: "nmail-cid:%3Cii_lx9%3E")), in: parts)?.gmailAttachmentId, "ANG")
        XCTAssertNil(MailHTML.attachment(for: try XCTUnwrap(URL(string: "nmail-cid:missing@x")), in: parts))
    }

    func testCSPBlocksActiveContentAndGatesRemoteImages() {
        for allow in [true, false] {
            let csp = MailHTML.csp(allowRemote: allow)
            for rule in ["default-src 'none'", "script-src 'none'", "object-src 'none'", "frame-src 'none'", "form-action 'none'"] {
                XCTAssertTrue(csp.contains(rule), rule)
            }
            XCTAssertTrue(csp.contains("img-src data: cid: nmail-cid:"))
            XCTAssertEqual(csp.contains("https: http:"), allow)
        }
    }

    func testDocumentFitsWidthAndServesInlineParts() {
        let doc = MailHTML.document(#"<table width="650"><tr><td><img src="cid:qr@x"></td></tr></table>"#,
                                    allowRemote: true, dark: false, palette: palette)
        XCTAssertTrue(doc.contains(MailHTML.csp(allowRemote: true)))
        XCTAssertTrue(doc.contains("img{max-width:100%!important;height:auto}"))
        XCTAssertTrue(doc.contains("table{max-width:100%!important}"))
        XCTAssertTrue(doc.contains("overflow-wrap:anywhere"))
        XCTAssertTrue(doc.contains(#"src="nmail-cid:qr@x""#))
        XCTAssertFalse(doc.contains("display:none"))
        XCTAssertFalse(doc.lowercased().contains("<script"))
    }

    func testBlockedRemoteImagesAreHidden() {
        let doc = MailHTML.document(#"<img src="https://t.example/p.gif">"#, allowRemote: false, dark: false, palette: palette)
        XCTAssertFalse(doc.contains("https: http:"))
        XCTAssertTrue(doc.contains(#"img[src^="http" i]"#))
    }

    func testDarkModeKeepsRichMailOnALightCard() {
        let rich = MailHTML.document(##"<table bgcolor="#eef2f6"><tr><td>Hi</td></tr></table>"##, allowRemote: true, dark: true, palette: palette)
        XCTAssertTrue(rich.contains("body{background:#fff"))
        XCTAssertTrue(rich.contains(#"content="light""#))
        let plain = MailHTML.document("<div>Hi</div>", allowRemote: true, dark: true, palette: palette)
        XCTAssertTrue(plain.contains(#"content="dark""#))
        XCTAssertFalse(plain.contains("body{background:#fff"))
    }

    func testDemoFixtureImagesAreServedOffline() {
        let url = "https://img.dalmatia-air.example/mail/logo.png"
        XCTAssertTrue(Fixtures.offlineImages(#"<img src="\#(url)">"#).hasPrefix(#"<img src="data:image/png;base64,"#))
        XCTAssertEqual(Fixtures.offlineImages(#"<img src="https://elsewhere.example/a.png">"#), #"<img src="https://elsewhere.example/a.png">"#)
    }
}
