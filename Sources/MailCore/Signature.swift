import Foundation
import GRDB

/// Which signature a send-as identity signs with, as HTML (the form Gmail stores). Edits in Settings
/// stay local; Gmail's copy only changes through `Outbox.updateSignature`, when the user asks for it.
public enum Signature {
    /// Tim's sign-off; the primary address uses it until a local edit replaces it.
    public static let defaultHTML = #"My kindest, Tim<br><br><a href="https://www.linkedin.com/in/timc9">LinkedIn</a>, <a href="https://cal.com/timcvetko">Cal.com</a>"#

    /// v2 keys hold HTML; the old `signature.local.` plain-text keys are ignored.
    static func localKey(_ email: String) -> String { "signature.html.\(email.lowercased())" }

    /// The local edit if there is one; else `defaultHTML` for the primary address, Gmail's sendAs
    /// signature for aliases, `defaultHTML` when that is empty.
    public static func html(for identity: SendAs?, db: Database) throws -> String {
        if let identity, let local = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [localKey(identity.email)]) {
            return local
        }
        guard let identity, !identity.isPrimary, !MIME.plainText(fromHTML: identity.signature).isEmpty else { return defaultHTML }
        return identity.signature
    }

    /// Signature HTML as display text plus the linked ranges (UTF-16, relative to `text`).
    public struct Rendered: Equatable, Sendable {
        public var text: String
        public var links: [Link]

        public struct Link: Equatable, Sendable {
            public var range: NSRange
            public var url: URL
        }

        /// The text with each link's URL in parentheses after it (unless the text already is the URL).
        public var textWithURLs: String {
            let ns = NSMutableString(string: text)
            for link in links.reversed() {
                let label = ns.substring(with: link.range)
                let url = link.url.absoluteString
                guard label != url, "mailto:" + label != url else { continue }
                ns.insert(" (\(url))", at: link.range.location + link.range.length)
            }
            return ns as String
        }
    }

    private static let open: Character = "\u{E000}", close: Character = "\u{E001}"

    /// Anchors are swapped for sentinel-wrapped text so `MIME.plainText` can flatten the rest.
    public static func render(_ html: String) -> Rendered {
        var urls: [URL?] = []
        let marked = html.replacing(/(?is)<a\b[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>(.*?)<\/a>/) { m in
            urls.append(URL(string: MIME.decodeHTMLEntities(String(m.1)).trimmingCharacters(in: .whitespaces)))
            return "\(open)\(m.2)\(close)"
        }
        var text = "", links: [Rendered.Link] = [], start = 0, index = 0
        for c in MIME.plainText(fromHTML: marked) {
            if c == open {
                start = text.utf16.count
            } else if c == close {
                if index < urls.count, let url = urls[index] { links.append(.init(range: NSRange(location: start, length: text.utf16.count - start), url: url)) }
                index += 1
            } else {
                text.append(c)
            }
        }
        return Rendered(text: text, links: links)
    }
}

extension Store {
    public func saveLocalSignature(_ html: String, for identity: SendAs) throws {
        try set(Signature.localKey(identity.email), html.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
