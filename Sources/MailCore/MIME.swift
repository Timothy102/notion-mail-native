import Foundation

public struct MIMEHeader: Sendable, Hashable {
    public var name: String
    public var value: String
}

/// A node of a message's MIME tree, from either Gmail's `payload` JSON or a raw RFC 2822 message.
public struct MIMEPart: Sendable {
    /// Gmail numbering: "" for the root, "0", "1", "1.0"…
    public var partId: String
    /// Raw (unfolded) values; `header(_:)` decodes encoded-words.
    public var headers: [MIMEHeader]
    /// Content with the transfer encoding removed, still in its charset.
    public var body: Data
    public var gmailAttachmentId: String?
    public var size: Int
    public var parts: [MIMEPart]

    public func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { MIME.decodeEncodedWords($0.value) }
    }

    private var contentType: (type: String, params: [String: String]) {
        MIME.parseParameterized(header("Content-Type") ?? "text/plain")
    }

    public var mimeType: String { contentType.type }
    public var charset: String? { contentType.params["charset"] }
    public var isMultipart: Bool { mimeType.hasPrefix("multipart/") }

    public var disposition: String? {
        header("Content-Disposition").map { MIME.parseParameterized($0).type }
    }

    public var filename: String? {
        let name = header("Content-Disposition").flatMap { MIME.parseParameterized($0).params["filename"] } ?? contentType.params["name"]
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var contentId: String? {
        header("Content-ID").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t")) }
    }

    public init(partId: String, headers: [MIMEHeader], body: Data, gmailAttachmentId: String? = nil, size: Int? = nil, parts: [MIMEPart] = []) {
        self.partId = partId
        self.headers = headers
        self.body = body
        self.gmailAttachmentId = gmailAttachmentId
        self.size = size ?? body.count
        self.parts = parts
    }

    public init(gmail p: GmailPayload) {
        let data = p.body?.data.flatMap { Data(base64URL: $0) } ?? Data()
        self.init(
            partId: p.partId ?? "",
            headers: (p.headers ?? []).map { MIMEHeader(name: $0.name, value: $0.value) },
            body: data,
            gmailAttachmentId: p.body?.attachmentId,
            size: p.body?.size ?? data.count,
            parts: (p.parts ?? []).map(MIMEPart.init(gmail:))
        )
        if !(p.mimeType ?? "").isEmpty, header("Content-Type") == nil {
            headers.append(MIMEHeader(name: "Content-Type", value: p.mimeType!))
        }
    }
}

public struct ParsedAttachment: Sendable, Hashable {
    public var partId: String
    public var filename: String
    public var mimeType: String
    public var size: Int
    public var contentId: String?
    public var isInline: Bool
    public var gmailAttachmentId: String?
    public var data: Data?
}

public struct ParsedBody: Sendable {
    public var text: String
    public var html: String?
    public var attachments: [ParsedAttachment]
}

public struct EmailAddress: Sendable, Hashable, Codable {
    public var name: String?
    public var email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }

    /// Name if present, otherwise the local part.
    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(email.split(separator: "@").first ?? Substring(email))
    }

    /// Header form, e.g. `"Doe, Jane" <jane@x.com>` or an encoded-word name.
    public var formatted: String {
        guard let name, !name.isEmpty else { return email }
        let specials = CharacterSet(charactersIn: "()<>@,;:\\\".[]")
        let shown: String
        if !name.allSatisfy(\.isASCII) { shown = MIME.encodeWords(name) }
        else if name.unicodeScalars.contains(where: specials.contains) {
            shown = "\"" + name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        } else { shown = name }
        return "\(shown) <\(email)>"
    }

    /// Parses an address-list header value. Commas inside quotes or angle brackets don't split.
    public static func parseList(_ value: String) -> [EmailAddress] {
        var items: [String] = []
        var current = ""
        var inQuotes = false, inAngle = false, escaped = false
        for c in value {
            if escaped { current.append(c); escaped = false; continue }
            switch c {
            case "\\" where inQuotes: escaped = true; current.append(c)
            case "\"": inQuotes.toggle(); current.append(c)
            case "<" where !inQuotes: inAngle = true; current.append(c)
            case ">" where !inQuotes: inAngle = false; current.append(c)
            case ",", ";":
                if inQuotes || inAngle { current.append(c) } else { items.append(current); current = "" }
            default: current.append(c)
            }
        }
        items.append(current)
        return items.compactMap { item in
            let s = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            if let open = s.lastIndex(of: "<"), let close = s.lastIndex(of: ">"), open < close {
                let email = String(s[s.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
                var name = String(s[..<open]).trimmingCharacters(in: .whitespaces)
                if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                    name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                }
                name = MIME.decodeEncodedWords(name)
                return EmailAddress(name: name.isEmpty ? nil : name, email: email)
            }
            return s.contains("@") ? EmailAddress(name: nil, email: s) : nil
        }
    }
}

public struct OutgoingAttachment: Sendable, Hashable {
    public var filename: String
    public var mimeType: String
    public var data: Data
    /// Set for inline images referenced as `cid:` from the HTML.
    public var contentId: String?

    public init(filename: String, mimeType: String, data: Data, contentId: String? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.contentId = contentId
    }
}

public struct OutgoingMessage: Sendable, Hashable {
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress] = []
    public var bcc: [EmailAddress] = []
    public var subject: String
    public var text: String
    public var html: String?
    /// Quoted original for replies and forwards, appended below `text` (and `html`).
    public var quoted: String?
    public var inReplyTo: String?
    public var references: [String] = []
    /// Gmail thread to send into; not a header.
    public var threadId: String?
    public var attachments: [OutgoingAttachment] = []
    public var date = Date()
    public var messageId = "<\(UUID().uuidString.lowercased())@mail.local>"

    public init(from: EmailAddress, to: [EmailAddress], cc: [EmailAddress] = [], bcc: [EmailAddress] = [], subject: String,
                text: String, html: String? = nil, quoted: String? = nil, inReplyTo: String? = nil, references: [String] = [],
                threadId: String? = nil, attachments: [OutgoingAttachment] = [], date: Date = Date()) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.text = text
        self.html = html
        self.quoted = quoted
        self.inReplyTo = inReplyTo
        self.references = references
        self.threadId = threadId
        self.attachments = attachments
        self.date = date
    }

    public static func reply(to m: Message, all: Bool, from: EmailAddress) -> OutgoingMessage {
        let me = from.email.lowercased()
        let sender = m.sender
        let fromSelf = sender.email.lowercased() == me
        var to = fromSelf ? EmailAddress.parseList(m.to) : (m.replyTo.isEmpty ? [sender] : EmailAddress.parseList(m.replyTo))
        var cc: [EmailAddress] = []
        if all {
            let others = (fromSelf ? [] : EmailAddress.parseList(m.to)) + EmailAddress.parseList(m.cc)
            var seen = Set(to.map { $0.email.lowercased() } + [me])
            for a in others where seen.insert(a.email.lowercased()).inserted { cc.append(a) }
        }
        if to.isEmpty { to = [sender] }
        let refs = m.references.split(whereSeparator: \.isWhitespace).map(String.init) + [m.messageIdHeader].filter { !$0.isEmpty }
        return OutgoingMessage(
            from: from, to: to, cc: cc, subject: MIME.prefixed("Re:", m.subject), text: "",
            quoted: "On \(MIME.quoteDate(m.date)), \(sender.formatted) wrote:\n" + m.bodyText.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"),
            inReplyTo: m.messageIdHeader.isEmpty ? nil : m.messageIdHeader, references: refs, threadId: m.threadId
        )
    }

    public static func forward(_ m: Message, from: EmailAddress) -> OutgoingMessage {
        var header = "---------- Forwarded message ---------\nFrom: \(m.from)\nDate: \(MIME.quoteDate(m.date))\nSubject: \(m.subject)\nTo: \(m.to)\n"
        if !m.cc.isEmpty { header += "Cc: \(m.cc)\n" }
        return OutgoingMessage(from: from, to: [], subject: MIME.prefixed("Fwd:", m.subject), text: "", quoted: header + "\n" + m.bodyText, threadId: m.threadId)
    }
}

public enum MIME {
    // MARK: Parse

    /// Parses a raw RFC 2822 message (or part) into a tree.
    public static func parse(_ data: Data, partId: String = "") -> MIMEPart {
        let bytes = [UInt8](data)
        var split = bytes.count, bodyStart = bytes.count
        var i = 0
        while i < bytes.count {
            if bytes[i] == 10 {
                if i + 1 < bytes.count, bytes[i + 1] == 10 { split = i; bodyStart = i + 2; break }
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { split = i; bodyStart = i + 3; break }
            }
            i += 1
        }
        if bytes.first == 10 { split = 0; bodyStart = 1 }
        else if bytes.starts(with: [13, 10]) { split = 0; bodyStart = 2 }
        let headers = parseHeaders(latin1(bytes[..<split]))
        let raw = Array(bytes[min(bodyStart, bytes.count)...])
        var part = MIMEPart(partId: partId, headers: headers, body: Data())
        if part.isMultipart, let boundary = parseParameterized(part.header("Content-Type") ?? "").params["boundary"] {
            part.parts = splitMultipart(raw, boundary: boundary).enumerated().map { index, chunk in
                parse(Data(chunk), partId: partId.isEmpty ? "\(index)" : "\(partId).\(index)")
            }
        } else {
            part.body = decodeTransfer(raw, encoding: part.header("Content-Transfer-Encoding"))
        }
        part.size = part.body.count
        return part
    }

    private static func latin1(_ bytes: ArraySlice<UInt8>) -> String {
        String(bytes.map { Character(Unicode.Scalar($0)) })
    }

    static func parseHeaders(_ text: String) -> [MIMEHeader] {
        var headers: [MIMEHeader] = []
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = line.hasSuffix("\r") ? line.dropLast() : line
            if line.first == " " || line.first == "\t", !headers.isEmpty {
                headers[headers.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                headers.append(MIMEHeader(name: String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                                          value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            }
        }
        // Raw headers are bytes; reinterpret as UTF-8 when valid (common for modern non-encoded headers).
        return headers.map { h in
            let bytes = h.value.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
            let utf8 = h.value.unicodeScalars.allSatisfy({ $0.value < 256 }) ? String(bytes: bytes, encoding: .utf8) : nil
            return MIMEHeader(name: h.name, value: utf8 ?? h.value)
        }
    }

    private static func splitMultipart(_ bytes: [UInt8], boundary: String) -> [[UInt8]] {
        let delimiter = Array(("--" + boundary).utf8)
        var parts: [[UInt8]] = []
        var current: [UInt8]? = nil
        var lineStart = 0
        func isDelimiter(_ line: ArraySlice<UInt8>) -> (Bool, closing: Bool) {
            var line = line
            while let last = line.last, last == 13 || last == 10 || last == 32 || last == 9 { line = line.dropLast() }
            guard line.starts(with: delimiter) else { return (false, false) }
            let rest = line.dropFirst(delimiter.count)
            if rest.isEmpty { return (true, false) }
            if Array(rest) == [45, 45] { return (true, true) }
            return (false, false)
        }
        while lineStart < bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10 { lineEnd += 1 }
            let next = min(lineEnd + 1, bytes.count)
            let line = bytes[lineStart..<next]
            let (delim, closing) = isDelimiter(line)
            if delim {
                if var c = current {
                    if c.last == 10 { c.removeLast() }
                    if c.last == 13 { c.removeLast() }
                    parts.append(c)
                }
                current = closing ? nil : []
                if closing { break }
            } else if current != nil {
                current!.append(contentsOf: line)
            }
            lineStart = next
        }
        if let c = current, !c.isEmpty { parts.append(c) }
        return parts
    }

    static func decodeTransfer(_ bytes: [UInt8], encoding: String?) -> Data {
        switch encoding?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let clean = bytes.filter { !($0 == 10 || $0 == 13 || $0 == 32 || $0 == 9) }
            return Data(base64Encoded: Data(clean), options: .ignoreUnknownCharacters) ?? Data(bytes)
        case "quoted-printable":
            return Data(decodeQuotedPrintable(bytes, underscoreIsSpace: false))
        default:
            return Data(bytes)
        }
    }

    static func decodeQuotedPrintable(_ bytes: [UInt8], underscoreIsSpace: Bool) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 61 { // "="
                if i + 1 < bytes.count, bytes[i + 1] == 10 { i += 2; continue }
                if i + 2 < bytes.count, bytes[i + 1] == 13, bytes[i + 2] == 10 { i += 3; continue }
                if i + 2 < bytes.count, let hi = hexValue(bytes[i + 1]), let lo = hexValue(bytes[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                    continue
                }
                // Trailing "=" with whitespace before a line break is also a soft break.
                var j = i + 1
                while j < bytes.count, bytes[j] == 32 || bytes[j] == 9 { j += 1 }
                if j < bytes.count, bytes[j] == 13 || bytes[j] == 10 {
                    i = bytes[j] == 13 && j + 1 < bytes.count && bytes[j + 1] == 10 ? j + 2 : j + 1
                    continue
                }
            }
            out.append(underscoreIsSpace && b == 95 ? 32 : b)
            i += 1
        }
        return out
    }

    private static func hexValue(_ b: UInt8) -> UInt8? {
        switch b {
        case 48...57: b - 48
        case 65...70: b - 55
        case 97...102: b - 87
        default: nil
        }
    }

    /// `type/subtype; a=b; filename*=UTF-8''%E2%82%AC.pdf` → ("type/subtype", params), keys lowercased, RFC 2231 applied.
    static func parseParameterized(_ value: String) -> (type: String, params: [String: String]) {
        var pieces: [String] = []
        var current = ""
        var inQuotes = false
        for c in value {
            if c == "\"" { inQuotes.toggle() }
            if c == ";", !inQuotes { pieces.append(current); current = "" } else { current.append(c) }
        }
        pieces.append(current)
        let type = pieces.removeFirst().trimmingCharacters(in: .whitespaces).lowercased()
        var params: [String: String] = [:]
        var continued: [String: [(Int, String, Bool)]] = [:]
        for piece in pieces {
            guard let eq = piece.firstIndex(of: "=") else { continue }
            var key = piece[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var val = piece[piece.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 { val = String(val.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"") }
            let encoded = key.hasSuffix("*")
            if encoded { key.removeLast() }
            if let star = key.firstIndex(of: "*"), let n = Int(key[key.index(after: star)...]) {
                continued[String(key[..<star]), default: []].append((n, val, encoded))
            } else {
                params[key] = encoded ? decodeRFC2231(val, first: true) : val
            }
        }
        for (key, chunks) in continued {
            let sorted = chunks.sorted { $0.0 < $1.0 }
            let charsetHolder = sorted.first
            var bytes: [UInt8] = []
            var charset = "utf-8"
            for (index, chunk) in sorted.enumerated() {
                var v = chunk.1
                if chunk.2 {
                    if index == 0, charsetHolder?.2 == true {
                        let comps = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                        if comps.count == 3 { charset = String(comps[0]); v = String(comps[2]) }
                    }
                    bytes += percentDecode(v)
                } else {
                    bytes += Array(v.utf8)
                }
            }
            params[key] = decodeText(Data(bytes), charset: charset)
        }
        return (type, params)
    }

    private static func decodeRFC2231(_ value: String, first: Bool) -> String {
        let comps = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard comps.count == 3 else { return decodeText(Data(percentDecode(value)), charset: "utf-8") }
        return decodeText(Data(percentDecode(String(comps[2]))), charset: String(comps[0]))
    }

    private static func percentDecode(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 37, i + 2 < bytes.count, let hi = hexValue(bytes[i + 1]), let lo = hexValue(bytes[i + 2]) {
                out.append(hi << 4 | lo)
                i += 3
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return out
    }

    public static func decodeText(_ data: Data, charset: String?) -> String {
        if let charset {
            let name = charset.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased()
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: encoding) { return s }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// RFC 2047 `=?charset?B|Q?…?=` decoding. Whitespace between adjacent encoded-words is dropped.
    public static func decodeEncodedWords(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let pattern = /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/
        var out = ""
        var cursor = value.startIndex
        var lastWasWord = false
        for match in value.matches(of: pattern) {
            let gap = value[cursor..<match.range.lowerBound]
            if !(lastWasWord && gap.allSatisfy(\.isWhitespace)) { out += gap }
            let charset = String(match.1.split(separator: "*").first ?? match.1)
            let payload = String(match.3)
            let data: Data
            if match.2.lowercased() == "b" {
                data = Data(base64Encoded: payload.padding(toLength: (payload.count + 3) / 4 * 4, withPad: "=", startingAt: 0)) ?? Data()
            } else {
                data = Data(decodeQuotedPrintable(Array(payload.utf8), underscoreIsSpace: true))
            }
            out += decodeText(data, charset: charset)
            cursor = match.range.upperBound
            lastWasWord = true
        }
        out += value[cursor...]
        return out
    }

    /// Walks the tree: first plain part, preferred HTML, and every attachment or inline image.
    public static func extract(_ part: MIMEPart) -> ParsedBody {
        if part.isMultipart {
            let children = part.parts.map(extract)
            let attachments = children.flatMap(\.attachments)
            if part.mimeType == "multipart/alternative" {
                return ParsedBody(text: children.first { !$0.text.isEmpty }?.text ?? "",
                                  html: children.last { $0.html != nil }?.html, attachments: attachments)
            }
            let htmls = children.compactMap(\.html)
            return ParsedBody(text: children.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n"),
                              html: htmls.isEmpty ? nil : htmls.joined(separator: "\n"), attachments: attachments)
        }
        let type = part.mimeType
        let isBody = (type == "text/plain" || type == "text/html") && part.disposition != "attachment" && part.filename == nil
        if isBody {
            let s = decodeText(part.body, charset: part.charset)
            return type == "text/html" ? ParsedBody(text: "", html: s, attachments: []) : ParsedBody(text: s, html: nil, attachments: [])
        }
        let isInline = part.contentId != nil && part.disposition != "attachment" && type.hasPrefix("image/")
        let fallbackName = type == "text/calendar" ? "invite.ics" : "attachment"
        let attachment = ParsedAttachment(
            partId: part.partId, filename: part.filename ?? fallbackName, mimeType: type, size: part.size,
            contentId: part.contentId, isInline: isInline, gmailAttachmentId: part.gmailAttachmentId,
            data: part.gmailAttachmentId == nil ? part.body : nil
        )
        return ParsedBody(text: "", html: nil, attachments: [attachment])
    }

    // MARK: Text helpers

    public static func plainText(fromHTML html: String) -> String {
        guard !html.isEmpty else { return "" }
        var s = html
        for tag in ["style", "script", "head", "title"] {
            s = s.replacing(try! Regex("(?is)<\(tag)\\b.*?</\(tag)>"), with: " ")
        }
        s = s.replacing(/(?i)<br\s*\/?>|<\/(p|div|tr|h[1-6]|li|table)>/, with: "\n")
        s = s.replacing(/<[^>]+>/, with: "")
        s = decodeHTMLEntities(s)
        s = s.replacing(/[ \t\u{00A0}]+/, with: " ")
        s = s.replacing(/\s*\n\s*(\n\s*)+/, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeHTMLEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "#39": "'", "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "copy": "©", "reg": "®", "trade": "™", "zwnj": "", "middot": "·"]
        return s.replacing(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/) { m in
            let key = String(m.1)
            if let v = named[key] { return v }
            if key.hasPrefix("#x"), let n = UInt32(key.dropFirst(2), radix: 16), let u = Unicode.Scalar(n) { return String(u) }
            if key.hasPrefix("#"), let n = UInt32(key.dropFirst()), let u = Unicode.Scalar(n) { return String(u) }
            return String(m.0)
        }
    }

    /// First ~200 characters of the new text, quoted lines skipped.
    public static func snippet(_ text: String) -> String {
        let lines = text.split(separator: "\n").filter { !$0.hasPrefix(">") }
        let flat = lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(flat.prefix(200))
    }

    public static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func prefixed(_ prefix: String, _ subject: String) -> String {
        subject.lowercased().hasPrefix(prefix.lowercased()) ? subject : "\(prefix) \(subject)"
    }

    static func quoteDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }

    // MARK: Build

    /// RFC 2822 bytes with CRLF line endings, ready for `GmailClient.send(raw:)`.
    public static func build(_ m: OutgoingMessage) -> Data {
        var headers: [(String, String)] = [("From", m.from.formatted)]
        if !m.to.isEmpty { headers.append(("To", m.to.map(\.formatted).joined(separator: ", "))) }
        if !m.cc.isEmpty { headers.append(("Cc", m.cc.map(\.formatted).joined(separator: ", "))) }
        if !m.bcc.isEmpty { headers.append(("Bcc", m.bcc.map(\.formatted).joined(separator: ", "))) }
        headers.append(("Subject", encodeWords(m.subject)))
        headers.append(("Date", rfc2822Date(m.date)))
        headers.append(("Message-ID", m.messageId))
        if let r = m.inReplyTo { headers.append(("In-Reply-To", r)) }
        if !m.references.isEmpty { headers.append(("References", m.references.joined(separator: " "))) }
        headers.append(("MIME-Version", "1.0"))

        let text = m.quoted.map { m.text + "\n\n" + $0 } ?? m.text
        var body: Entity = leaf("text/plain; charset=utf-8", Data(text.utf8), textual: true)
        if let html = m.html {
            let fullHTML = m.quoted.map { html + "<br><br><blockquote>" + htmlEscape($0).replacingOccurrences(of: "\n", with: "<br>") + "</blockquote>" } ?? html
            body = multipart("alternative", [body, leaf("text/html; charset=utf-8", Data(fullHTML.utf8), textual: true)])
        }
        if !m.attachments.isEmpty {
            body = multipart("mixed", [body] + m.attachments.map { a in
                var e = leaf("\(a.mimeType); name=\(quotedParam(a.filename))", a.data, textual: false)
                let disposition = a.contentId == nil ? "attachment" : "inline"
                e.headers.append(("Content-Disposition", "\(disposition); filename=\(quotedParam(a.filename))"))
                if let cid = a.contentId { e.headers.append(("Content-ID", "<\(cid)>")) }
                return e
            })
        }
        var out = ""
        for (k, v) in headers + body.headers { out += "\(k): \(v)\r\n" }
        out += "\r\n" + body.content
        return Data(out.utf8)
    }

    private struct Entity {
        var headers: [(String, String)]
        var content: String
    }

    private static func leaf(_ contentType: String, _ data: Data, textual: Bool) -> Entity {
        let ascii = data.allSatisfy { $0 < 128 }
        let text = textual && ascii ? String(decoding: data, as: UTF8.self) : nil
        if let text, !text.split(separator: "\n", omittingEmptySubsequences: false).contains(where: { $0.utf8.count > 900 }) {
            let crlf = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
            return Entity(headers: [("Content-Type", contentType), ("Content-Transfer-Encoding", "7bit")], content: crlf)
        }
        return Entity(headers: [("Content-Type", contentType), ("Content-Transfer-Encoding", "base64")],
                      content: data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]))
    }

    private static func multipart(_ subtype: String, _ parts: [Entity]) -> Entity {
        let boundary = "=_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var content = ""
        for p in parts {
            content += "--\(boundary)\r\n"
            for (k, v) in p.headers { content += "\(k): \(v)\r\n" }
            content += "\r\n" + p.content + "\r\n"
        }
        content += "--\(boundary)--\r\n"
        return Entity(headers: [("Content-Type", "multipart/\(subtype); boundary=\"\(boundary)\"")], content: content)
    }

    private static func quotedParam(_ value: String) -> String {
        value.allSatisfy(\.isASCII) ? "\"\(value.replacingOccurrences(of: "\"", with: "'"))\"" : "\"\(encodeWords(value))\""
    }

    /// RFC 2047 B-encoding for non-ASCII header text, folded so each word stays within 75 characters.
    public static func encodeWords(_ value: String) -> String {
        guard !value.allSatisfy(\.isASCII) else { return value }
        var words: [String] = []
        var chunk = ""
        for c in value {
            if (chunk + String(c)).utf8.count > 45, !chunk.isEmpty {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(c)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    static func rfc2822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }
}

extension Data {
    public init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s, options: .ignoreUnknownCharacters)
    }

    public var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
