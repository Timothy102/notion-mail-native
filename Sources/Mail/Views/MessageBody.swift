import AppKit
import MailCore
import SwiftUI
import WebKit

/// Untrusted HTML mail body (SPEC §4.4): JavaScript off, strict CSP, remote content blocked
/// unless `allowRemote`, every navigation leaves the web view. Sized to its content height.
struct MessageBody: View {
    let html: String
    var attachments: [Attachment] = []
    var allowRemote = false
    var onMailto: (EmailAddress) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 0

    var body: some View {
        let document = MailHTML.document(html, attachments: attachments, allowRemote: allowRemote, dark: scheme == .dark)
        WebBody(document: document, height: $height, onMailto: onMailto)
            .frame(height: max(height, 1))
            .opacity(height > 0 ? 1 : 0)
    }
}

/// Quoted history under a message body, collapsed behind Gmail's "•••" pill.
struct QuotedHistory: View {
    let html: String
    var attachments: [Attachment] = []
    var allowRemote = false
    var onMailto: (EmailAddress) -> Void = { _ in }
    @State private var isExpanded = QuotedHistory.snapshotExpanded
    static var snapshotExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuoteToggle(isExpanded: $isExpanded)
            if isExpanded { MessageBody(html: html, attachments: attachments, allowRemote: allowRemote, onMailto: onMailto) }
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

enum MailHTML {
    /// Whether the HTML pulls anything from the network (images, backgrounds, stylesheets).
    static func hasRemoteContent(_ html: String) -> Bool {
        html.range(of: #"(src|background)\s*=\s*["']?\s*(https?:)?//|url\(\s*["']?\s*(https?:)?//"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Mail that paints its own backgrounds; in dark mode it is inverted rather than recoloured.
    static func isRich(_ html: String) -> Bool {
        html.range(of: #"bgcolor|background(-color)?\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func document(_ html: String, attachments: [Attachment], allowRemote: Bool, dark: Bool) -> String {
        let remote = allowRemote ? " https: http:" : ""
        let blocked = allowRemote ? "" : "\nimg[src^=\"http\"],img[src^=\"//\"]{display:none!important}"
        let csp = "default-src 'none'; img-src data: cid:\(remote); style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'"
        let rich = isRich(html)
        let text = css(Theme.textPrimary, dark: dark)
        let link = css(Theme.textSecondary, dark: dark)
        let quote = css(Theme.border, dark: dark)
        var style = """
        html,body{margin:0;padding:0;overflow:hidden;background:transparent}
        body{font:14px/1.71 -apple-system,system-ui,sans-serif;color:\(text);word-wrap:break-word;overflow-wrap:anywhere;-webkit-font-smoothing:antialiased}
        p{margin:0}
        img{max-width:100%;height:auto}
        table{max-width:100%}
        blockquote{margin:4px 0 4px 4px!important;border-left:1px solid \(quote)!important;padding:0 0 0 12px!important}
        a{color:\(link);text-decoration-thickness:.05em;text-underline-offset:3px}
        ::selection{background:rgba(35,131,226,.28)}\(blocked)
        """
        if dark && rich {
            style += """

            html{background:#fff;filter:invert(.855) hue-rotate(180deg)}
            body{color:#1D1B16}
            a{color:#5F5E5B}
            img,video,picture,[style*="background-image"]{filter:invert(1) hue-rotate(180deg)}
            """
        } else if dark {
            style += "\nbody *{color:inherit!important;background:transparent!important}\na,a *{color:\(link)!important}"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="color-scheme" content="\(dark && !rich ? "dark" : "light")">
        <style>\(style)</style></head><body>\(inlineCIDs(html, attachments))</body></html>
        """
    }

    /// `cid:` references become data URIs; WebKit can't resolve cid: on its own.
    static func inlineCIDs(_ html: String, _ attachments: [Attachment]) -> String {
        var out = html
        for a in attachments {
            guard let cid = a.contentId, let data = a.data, out.contains("cid:\(cid)") else { continue }
            out = out.replacingOccurrences(of: "cid:\(cid)", with: "data:\(a.mimeType);base64,\(data.base64EncodedString())")
        }
        return out
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
    @Binding var height: CGFloat
    let onMailto: (EmailAddress) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PassiveWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = PassiveWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.onResize = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: PassiveWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        view.loadHTMLString(document, baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebBody
        weak var view: PassiveWebView?
        var loaded: String?

        init(_ parent: WebBody) {
            self.parent = parent
        }

        func measure() {
            view?.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)") { [weak self] value, _ in
                guard let self, let h = value as? Double else { return }
                MainActor.assumeIsolated {
                    if abs(self.parent.height - h) > 0.5 { self.parent.height = h }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure()
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
    var onResize: () -> Void = {}
    private var lastWidth: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastWidth) > 0.5 {
            lastWidth = newSize.width
            onResize()
        }
    }
}
