import AppKit
import MailCore
import SwiftUI
import WebKit

/// Untrusted HTML mail body (SPEC §4.4): page JavaScript off, strict CSP, remote images only when `allowRemote`,
/// `cid:` parts served by `CIDSchemeHandler`, every navigation leaves the web view. Sized to its content height.
struct MessageBody: View {
    static let loadRemoteKey = "images.loadRemote"
    let html: String
    var attachments: [Attachment] = []
    var allowRemote = false
    var gmail: GmailClient?
    var onMailto: (EmailAddress) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 0

    var body: some View {
        let document = MailHTML.document(html, allowRemote: allowRemote, dark: scheme == .dark)
        WebBody(document: document, attachments: attachments, gmail: gmail, height: $height, onMailto: onMailto)
            .frame(height: max(height, 1))
            .opacity(height > 0 ? 1 : 0)
    }
}

/// Quoted history under a message body, collapsed behind Gmail's "•••" pill.
struct QuotedHistory: View {
    let html: String
    var attachments: [Attachment] = []
    var allowRemote = false
    var gmail: GmailClient?
    var onMailto: (EmailAddress) -> Void = { _ in }
    @State private var isExpanded = QuotedHistory.snapshotExpanded
    static var snapshotExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuoteToggle(isExpanded: $isExpanded)
            if isExpanded { MessageBody(html: html, attachments: attachments, allowRemote: allowRemote, gmail: gmail, onMailto: onMailto) }
        }
    }
}

struct QuoteToggle: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Text("•••")
                .font(.system(size: 8, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 26, height: 12)
                .background(Theme.hover, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Hide quoted text" : "Show quoted text")
    }
}

extension MailHTML {
    static func document(_ html: String, allowRemote: Bool, dark: Bool) -> String {
        document(html, allowRemote: allowRemote, dark: dark,
                 palette: Palette(text: css(Theme.textPrimary, dark: dark), link: css(Theme.textSecondary, dark: dark), quote: css(Theme.border, dark: dark)))
    }

    private static func css(_ color: Color, dark: Bool) -> String {
        var resolved = NSColor.black
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return String(format: "rgba(%d,%d,%d,%.3f)", Int(resolved.redComponent * 255), Int(resolved.greenComponent * 255),
                      Int(resolved.blueComponent * 255), resolved.alphaComponent)
    }
}

private struct WebBody: NSViewRepresentable {
    let document: String
    let attachments: [Attachment]
    let gmail: GmailClient?
    @Binding var height: CGFloat
    let onMailto: (EmailAddress) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PassiveWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.setURLSchemeHandler(context.coordinator.parts, forURLScheme: MailHTML.cidScheme)
        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(source: MailHTML.fitScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        scripts.add(context.coordinator, contentWorld: .defaultClient, name: "height")
        let view = PassiveWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PassiveWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.parts.attachments = attachments
        context.coordinator.parts.gmail = gmail
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        view.loadHTMLString(document, baseURL: nil)
    }

    static func dismantleNSView(_ view: PassiveWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebBody
        var loaded: String?
        let parts = CIDSchemeHandler()

        init(_ parent: WebBody) {
            self.parent = parent
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = (message.body as? NSNumber)?.doubleValue, abs(parent.height - h) > 0.5 else { return }
            parent.height = h
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.absoluteString == "about:blank", action.navigationType == .other { return decisionHandler(.allow) }
            decisionHandler(.cancel)
            guard action.navigationType == .linkActivated else { return }
            switch url.scheme?.lowercased() {
            case "http", "https": NSWorkspace.shared.open(url)
            case "mailto":
                let address = url.absoluteString.dropFirst("mailto:".count).split(separator: "?").first.map(String.init) ?? ""
                if let to = EmailAddress.parseList(address.removingPercentEncoding ?? address).first { parent.onMailto(to) }
            default: break
            }
        }
    }
}

/// A web view that never scrolls itself: wheel events go to the enclosing SwiftUI scroll view.
final class PassiveWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
