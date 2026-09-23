import Foundation

/// The sandboxed document an HTML mail body renders in (SPEC §4.4): strict CSP, no page JavaScript,
/// fit-to-width CSS, and `cid:` parts routed to `cidScheme` so the app can serve them.
public enum MailHTML {
    /// Custom scheme `cid:` references are rewritten to; WebKit can't load cid: itself.
    public static let cidScheme = "nmail-cid"

    public struct Palette: Sendable {
        public var text, link, quote: String
        public init(text: String, link: String, quote: String) {
            self.text = text
            self.link = link
            self.quote = quote
        }
    }

    /// Whether the HTML pulls anything from the network (images, backgrounds, stylesheets).
    public static func hasRemoteContent(_ html: String) -> Bool {
        html.range(of: #"(src|background)\s*=\s*["']?\s*(https?:)?//|url\(\s*["']?\s*(https?:)?//"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Mail that paints its own backgrounds; in dark mode it keeps them on a light card, as Gmail does.
    public static func isRich(_ html: String) -> Bool {
        html.range(of: #"bgcolor|background(-color)?\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func csp(allowRemote: Bool) -> String {
        let remote = allowRemote ? " https: http:" : ""
        return "default-src 'none'; script-src 'none'; object-src 'none'; frame-src 'none'; child-src 'none'; "
            + "img-src data: cid: \(cidScheme):\(remote); style-src 'unsafe-inline'; font-src data:; "
            + "media-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'"
    }

    public static func document(_ html: String, allowRemote: Bool, dark: Bool, palette: Palette) -> String {
        let blocked = allowRemote ? "" : "\nimg[src^=\"http\" i],img[src^=\"//\"]{display:none!important}"
        let rich = isRich(html)
        var style = """
        html,body{margin:0;padding:0;overflow:hidden;background:transparent}
        body{font:14px/1.71 -apple-system,system-ui,sans-serif;color:\(palette.text);overflow-wrap:anywhere;word-break:break-word;-webkit-font-smoothing:antialiased;-webkit-text-size-adjust:none}
        p{margin:0}
        img{max-width:100%!important;height:auto}
        table{max-width:100%!important}
        td,th{max-width:100%}
        pre{white-space:pre-wrap}
        blockquote{margin:4px 0 4px 4px!important;border-left:1px solid \(palette.quote)!important;padding:0 0 0 12px!important}
        a{color:\(palette.link);text-decoration-thickness:.05em;text-underline-offset:3px}
        ::selection{background:rgba(35,131,226,.28)}\(blocked)
        """
        if dark && rich {
            style += "\nbody{background:#fff;color:#1D1B16;border-radius:8px;padding:12px}\na{color:#2383E2}"
        } else if dark {
            style += "\nbody *{color:inherit!important;background:transparent!important}\na,a *{color:\(palette.link)!important}"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(allowRemote: allowRemote))">
        <meta name="color-scheme" content="\(dark && !rich ? "dark" : "light")">
        <style>\(style)</style></head><body>\(rewriteCIDs(html))</body></html>
        """
    }

    /// `cid:x` in src/background/url() becomes `nmail-cid:x`.
    public static func rewriteCIDs(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?<=["'(=\s])\s*cid:"#, with: "\(cidScheme):", options: [.regularExpression, .caseInsensitive])
    }

    /// The part a `nmail-cid:` URL names; Content-IDs compare without angle brackets, case-insensitively.
    public static func attachment(for url: URL, in attachments: [Attachment]) -> Attachment? {
        let raw = url.absoluteString.dropFirst(cidScheme.count + 1)
        let cid = (raw.removingPercentEncoding ?? String(raw)).trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        return attachments.first { $0.contentId?.caseInsensitiveCompare(cid) == .orderedSame }
    }

    /// Runs in an isolated content world (page JS stays off): scales content that is still wider than the
    /// pane after the CSS above, hides images that failed to load, and reports the body height whenever it changes (e.g. as images load).
    public static let fitScript = """
    (() => {
      const d = document.documentElement, b = document.body;
      let last = -1;
      const fit = () => {
        d.style.zoom = '';
        let w = d.scrollWidth;
        for (const e of b.querySelectorAll('*')) w = Math.max(w, e.getBoundingClientRect().right);
        const z = Math.min(1, innerWidth / Math.max(w, 1));
        if (z < 1) d.style.zoom = z;
        const h = Math.ceil(b.getBoundingClientRect().height * (z < 1 ? z : 1));
        if (h !== last) { last = h; webkit.messageHandlers.height.postMessage(h); }
      };
      const hideBroken = () => { for (const i of document.images) if (i.complete && !i.naturalWidth) i.style.display = 'none'; };
      addEventListener('error', e => { if (e.target.tagName === 'IMG') e.target.style.display = 'none'; }, true);
      addEventListener('load', hideBroken);
      hideBroken();
      new ResizeObserver(fit).observe(b);
      addEventListener('resize', fit);
      addEventListener('load', fit);
      fit();
    })();
    """
}
