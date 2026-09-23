import MailCore
import SwiftUI
import WebKit

/// Untrusted HTML mail body (SPEC §4.4) in MailCore's MailHTML document: page JavaScript off, strict CSP,
/// fit-to-width, `cid:` parts served by CIDSchemeHandler, links open outside. Sized to its content height.
struct MessageBody: View {
    static let loadRemoteKey = "images.loadRemote"
    let html: String
    var attachments: [Attachment] = []
    var allowRemote = true
    var gmail: GmailClient?
    var onMailto: (EmailAddress) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 0

    var body: some View {
        WebBody(document: Self.document(html, allowRemote: allowRemote, dark: scheme == .dark), attachments: attachments,
                gmail: gmail, height: $height, onMailto: onMailto)
            .frame(height: max(height, 1))
            .opacity(height > 0 ? 1 : 0)
    }

    /// MailHTML's document with a phone viewport and a 16 px body, so mail reads at iOS body size.
    static func document(_ html: String, allowRemote: Bool, dark: Bool) -> String {
        let palette = MailHTML.Palette(text: UIColor(Theme.textPrimary).css(dark: dark), link: UIColor(Theme.textSecondary).css(dark: dark),
                                       quote: UIColor(Theme.border).css(dark: dark))
        return MailHTML.document(html, allowRemote: allowRemote, dark: dark, palette: palette)
            .replacingOccurrences(of: "<head>", with: #"<head><meta name="viewport" content="width=device-width,initial-scale=1">"#)
            .replacingOccurrences(of: "</style></head>", with: "\nbody{font-size:16px;line-height:1.5;overflow-wrap:break-word;word-break:normal}</style></head>")
    }
}

/// Quoted history under a message, collapsed behind Gmail's "•••" pill.
struct QuotedHistory<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                Text("•••")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 34, height: 16)
                    .background(Theme.hover, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide quoted text" : "Show quoted text")
            if isExpanded { content }
        }
    }
}

private struct WebBody: UIViewRepresentable {
    let document: String
    let attachments: [Attachment]
    let gmail: GmailClient?
    @Binding var height: CGFloat
    let onMailto: (EmailAddress) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.dataDetectorTypes = [.link, .phoneNumber, .address, .calendarEvent]
        config.setURLSchemeHandler(context.coordinator.parts, forURLScheme: MailHTML.cidScheme)
        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(source: MailHTML.fitScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        scripts.add(context.coordinator, contentWorld: .defaultClient, name: "height")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.parts.attachments = attachments
        context.coordinator.parts.gmail = gmail
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        view.loadHTMLString(document, baseURL: nil)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
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
            case "mailto":
                let address = url.absoluteString.dropFirst("mailto:".count).split(separator: "?").first.map(String.init) ?? ""
                if let to = EmailAddress.parseList(address.removingPercentEncoding ?? address).first { parent.onMailto(to) }
            case "http", "https", "tel", "maps", "x-apple-calevent": Platform.open(url)
            default: break
            }
        }
    }
}
