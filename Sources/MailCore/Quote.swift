import Foundation

/// Quoted history in mail bodies: finding it so it can collapse behind "•••", and writing it Gmail-style
/// into replies and forwards.
public enum Quote {
    // MARK: Detect

    /// Splits `html` into the new part and the trailing quoted history. `quoted` is nil when there is none,
    /// or when the whole message is quoted (nothing new to show above it).
    public static func split(html: String) -> (new: String, quoted: String?) {
        guard let start = quoteStart(html) else { return (html, nil) }
        let cut = attributionStart(html, before: start)
        let new = String(html[..<cut]).replacing(/(?i)(?:\s|&nbsp;|<br\s*\/?>|<(?:div|p)\b[^>]*>(?:\s|<br\s*\/?>)*<\/(?:div|p)>|<(?:div|p|span)\b[^>]*>)+$/, with: "")
        guard hasVisibleContent(new) else { return (html, nil) }
        return (new, String(html[cut...]))
    }

    /// Splits plain text at a trailing run of `>` lines, including the "On … wrote:" line above it.
    public static func split(text: String) -> (new: String, quoted: String?) {
        let lines = text.components(separatedBy: "\n")
        func quoteLine(_ i: Int) -> Bool { lines[i].drop(while: { $0 == " " }).hasPrefix(">") }
        func blank(_ i: Int) -> Bool { lines[i].allSatisfy(\.isWhitespace) }
        func restQuoted(from i: Int) -> Bool { i < lines.count && quoteLine(i) && (i..<lines.count).allSatisfy { blank($0) || quoteLine($0) } }
        func attribution(_ s: String) -> Bool { s.range(of: #"^\s*On\s.{4,300}\bwrote:\s*$"#, options: .regularExpression) != nil }
        for i in lines.indices {
            var start: Int?
            for span in 1...2 where start == nil && i + span <= lines.count && attribution(lines[i..<(i + span)].joined(separator: " ")) {
                if let next = (i + span..<lines.count).first(where: { !blank($0) }), restQuoted(from: next) { start = i }
            }
            if start == nil, restQuoted(from: i) { start = i }
            guard let start else { continue }
            let new = lines[..<start].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !new.isEmpty else { return (text, nil) }
            return (new, lines[start...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (text, nil)
    }

    /// Where quoted history begins: the earliest Gmail or Outlook reply container, or a blockquote with
    /// nothing visible after it (a blockquote followed by a reply is inline quoting and stays visible).
    static func quoteStart(_ html: String) -> String.Index? {
        let containers = [
            #"<div\b[^>]*\bclass\s*=\s*["']?[^"'>]*\bgmail_quote"#,
            #"<blockquote\b[^>]*\bclass\s*=\s*["']?[^"'>]*\bgmail_quote"#,
            #"<[a-z]+\b[^>]*\bid\s*=\s*["']?(divRplyFwdMsg|appendonsend)\b"#,
        ]
        var found = containers.compactMap { html.range(of: "(?i)" + $0, options: .regularExpression)?.lowerBound }
        if let header = html.range(of: #"(?is)\bFrom:(?:(?!\bFrom:).){1,600}?\bSent:.{1,600}?\b(To|Subject):"#, options: .regularExpression) {
            let block = html[..<header.lowerBound].ranges(of: /(?i)<(div|p|hr)\b/).last?.lowerBound
            found.append(block ?? header.lowerBound)
        }
        var search = html.startIndex..<html.endIndex
        while let open = html.range(of: #"(?i)<blockquote\b"#, options: .regularExpression, range: search) {
            if let end = blockquoteEnd(html, from: open.lowerBound), !hasVisibleContent(html[end...]) {
                found.append(open.lowerBound)
                break
            }
            search = open.upperBound..<html.endIndex
        }
        return found.min()
    }

    /// Just past the `</blockquote>` matching the one opening at `start`.
    private static func blockquoteEnd(_ html: String, from start: String.Index) -> String.Index? {
        var depth = 0, i = start
        while let tag = html.range(of: #"(?i)</?blockquote\b[^>]*>"#, options: .regularExpression, range: i..<html.endIndex) {
            depth += html[tag].hasPrefix("</") ? -1 : 1
            if depth == 0 { return tag.upperBound }
            i = tag.upperBound
        }
        return nil
    }

    /// Moves `start` back over an "On … wrote:" line that sits just above the quote (Apple Mail, Outlook web).
    private static func attributionStart(_ html: String, before start: String.Index) -> String.Index {
        let windowStart = html.index(start, offsetBy: -1500, limitedBy: html.startIndex) ?? html.startIndex
        let pattern = #"(?is)(?:<(?:div|p|span)\b[^>]*>\s*)*\bOn\s(?:(?!<(?:div|p|blockquote)\b)(?!\bOn\s).){4,400}?wrote:(?:\s|&nbsp;|<br\s*/?>|</?(?:div|p|span|b|i|a)\b[^>]*>)*$"#
        return html.range(of: pattern, options: .regularExpression, range: windowStart..<start)?.lowerBound ?? start
    }

    private static func hasVisibleContent(_ html: Substring) -> Bool {
        if html.range(of: #"(?i)<(img|video|table)\b"#, options: .regularExpression) != nil { return true }
        let text = html.replacing(/<[^>]*>|&nbsp;|&#160;/, with: "")
        return text.contains { !$0.isWhitespace }
    }

    private static func hasVisibleContent(_ html: String) -> Bool { hasVisibleContent(html[...]) }

    // MARK: Write

    /// Plain text as HTML; each level of `>` becomes a nested blockquote.
    public static func html(fromText text: String) -> String {
        var out = "", depth = 0
        for line in text.trimmingCharacters(in: .newlines).components(separatedBy: "\n") {
            var rest = Substring(line), level = 0
            while case let trimmed = rest.drop(while: { $0 == " " }), trimmed.first == ">" {
                level += 1
                rest = trimmed.dropFirst()
            }
            if level > 0, rest.first == " " { rest = rest.dropFirst() }
            out += String(repeating: "<blockquote>", count: max(0, level - depth))
            out += String(repeating: "</blockquote>", count: max(0, depth - level))
            depth = level
            out += MIME.htmlEscape(String(rest)) + "<br>"
        }
        return out + String(repeating: "</blockquote>", count: depth)
    }

    /// "On Thu, Jan 22, 2026 at 1:22 AM, Lizzy <hello@lizzy.studio> wrote:"
    public static func attribution(date: Date, sender: EmailAddress) -> String {
        let who = sender.name.map { $0.isEmpty ? "" : $0 + " " } ?? ""
        return "On \(MIME.quoteDate(date)), \(who)<\(sender.email)> wrote:"
    }

    /// The text/plain quote: attribution, then every line one `>` deeper.
    public static func replyText(attribution: String, body: String) -> String {
        let lines = body.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").map { line in
            line.hasPrefix(">") ? ">" + line : line.isEmpty ? ">" : "> " + line
        }
        return attribution + "\n" + lines.joined(separator: "\n")
    }

    /// Gmail's own quote markup, so Gmail (and this app) collapse and indent it.
    public static func replyHTML(attribution: String, bodyHTML: String) -> String {
        #"<div class="gmail_quote"><div dir="ltr" class="gmail_attr">"# + MIME.htmlEscape(attribution)
            + #"<br></div><blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex">"#
            + bodyHTML + "</blockquote></div>"
    }

    /// Gmail's forward block: the original's headers, then its body unindented.
    public static func forwardHTML(_ m: Message) -> String {
        let sender = m.sender
        var header = "---------- Forwarded message ---------<br>From: <strong class=\"gmail_sendername\" dir=\"auto\">"
            + MIME.htmlEscape(sender.displayName) + "</strong> <span dir=\"auto\">&lt;" + MIME.htmlEscape(sender.email) + "&gt;</span><br>"
            + "Date: " + MIME.htmlEscape(MIME.quoteDate(m.date)) + "<br>Subject: " + MIME.htmlEscape(m.subject)
            + "<br>To: " + MIME.htmlEscape(m.to) + "<br>"
        if !m.cc.isEmpty { header += "Cc: " + MIME.htmlEscape(m.cc) + "<br>" }
        return #"<div class="gmail_quote"><div dir="ltr" class="gmail_attr">"# + header + "</div><br><br>" + bodyHTML(m) + "</div>"
    }

    /// What `m` looks like inside a quote: its HTML body (nested quotes intact), else its text.
    public static func bodyHTML(_ m: Message) -> String {
        guard let html = m.bodyHTML, !html.isEmpty else { return self.html(fromText: m.bodyText) }
        guard let open = html.range(of: #"(?i)<body\b[^>]*>"#, options: .regularExpression) else { return html }
        let close = html.range(of: "</body>", options: [.caseInsensitive, .backwards])?.lowerBound ?? html.endIndex
        return open.upperBound < close ? String(html[open.upperBound..<close]) : html
    }
}
