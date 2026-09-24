import CoreGraphics
import CryptoKit
import Foundation
import GRDB
import ImageIO
import Synchronization

/// A picture per sender address, shared by both apps: the account's own Google photo, else the brand favicon of a
/// company domain, else Gravatar, else nil (the row draws a colored initial). Remote lookups go to Google and
/// Gravatar only, never to the sender. Results live in memory, and on disk under the account's `avatars/`
/// directory with an index: hits for 14 days, misses for 3.
///
/// ponytail: no BIMI. Its logos are SVG Tiny PS and neither UIKit nor AppKit rasterizes arbitrary SVG; favicons
/// cover the same brands. Add it with an SVG renderer if favicons fall short.
public final class SenderAvatars: Sendable {
    public enum Entry: Sendable {
        /// `fullBleed`: an opaque square that fills the circle; otherwise a transparent mark drawn on a white disc.
        case image(CGImage, fullBleed: Bool)
        case none
    }

    private struct IndexEntry: Codable {
        var file: String?
        var fetched: Date
    }

    private let directory: URL?
    private let ownPhoto: URL?
    private let store: Store
    private let isDemo: Bool
    private let session: URLSession
    private let memory = Mutex<[String: Entry]>([:])
    private let index: Mutex<[String: IndexEntry]>
    private let inflight = Mutex<[String: Task<Entry, Never>]>([:])
    private let ownEmails = Mutex<Set<String>?>(nil)
    static let hitTTL: TimeInterval = 14 * 86_400
    static let missTTL: TimeInterval = 3 * 86_400

    /// `directory` nil keeps everything in memory. `isDemo` never touches the network and serves `Fixtures.brandLogos`.
    public init(directory: URL?, ownPhoto: URL?, store: Store, isDemo: Bool) {
        self.directory = directory
        self.ownPhoto = ownPhoto
        self.store = store
        self.isDemo = isDemo
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
        let saved = directory.flatMap { try? Data(contentsOf: $0.appending(path: "index.json")) }
            .flatMap { try? JSONDecoder().decode([String: IndexEntry].self, from: $0) }
        index = Mutex(saved ?? [:])
    }

    /// What is already known, without waiting; nil means not looked up yet.
    public func cached(_ email: String) -> Entry? {
        memory.withLock { $0[email.lowercased()] }
    }

    public func resolve(_ email: String) async -> Entry {
        let email = email.lowercased()
        if let hit = cached(email) { return hit }
        let task = inflight.withLock { tasks in
            if let running = tasks[email] { return running }
            let task = Task { await self.lookup(email) }
            tasks[email] = task
            return task
        }
        let entry = await task.value
        memory.withLock { $0[email] = entry }
        inflight.withLock { $0[email] = nil }
        return entry
    }

    // MARK: Lookup

    private func lookup(_ email: String) async -> Entry {
        if isOwn(email), let photo = ownPhoto, let image = Self.decode(try? Data(contentsOf: photo)) { return .image(image, fullBleed: true) }
        let domain = Self.baseDomain(String(email.split(separator: "@").last ?? ""))
        if !Self.isFreemail(domain) {
            if case .image(let image, let full) = await cachedFetch("d:" + domain, { await self.favicon(domain) }) { return .image(image, fullBleed: full) }
        }
        if isDemo { return .none }
        return await cachedFetch("a:" + email) { await self.gravatar(email) }
    }

    private func favicon(_ domain: String) async -> Data? {
        if isDemo { return Fixtures.brandLogos[domain].flatMap { Data(base64Encoded: $0) } }
        var url = URLComponents(string: "https://www.google.com/s2/favicons")!
        url.queryItems = [URLQueryItem(name: "domain", value: domain), URLQueryItem(name: "sz", value: "128")]
        // Unknown domains get a 404 with a 16 px globe; small real icons look blurry at 40 pt, so both are misses.
        guard let data = await get(url.url!), let image = Self.decode(data), image.width >= 64 else { return nil }
        return data
    }

    private func gravatar(_ email: String) async -> Data? {
        let hash = SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        return await get(URL(string: "https://gravatar.com/avatar/\(hash)?s=128&d=404")!)
    }

    private func get(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Disk-cached by `key`; a miss is remembered too, so a sender without a picture isn't looked up on every scroll.
    private func cachedFetch(_ key: String, _ fetch: () async -> Data?) async -> Entry {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        if let known = index.withLock({ $0[key] }) {
            let ttl = known.file == nil ? Self.missTTL : Self.hitTTL
            if Date.now.timeIntervalSince(known.fetched) < ttl {
                guard let file = known.file, let dir = directory else { return .none }
                if let image = Self.decode(try? Data(contentsOf: dir.appending(path: file))) { return Self.entry(image) }
            }
        }
        let data = await fetch()
        let image = Self.decode(data)
        var file: String?
        if let dir = directory, let data, image != nil {
            file = name + ".png"
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? (Platform.png(data) ?? data).write(to: dir.appending(path: file!), options: .atomic)
        }
        if !isDemo { saveIndex(key, IndexEntry(file: file, fetched: .now)) }
        return image.map(Self.entry) ?? .none
    }

    private func saveIndex(_ key: String, _ entry: IndexEntry) {
        let snapshot = index.withLock { index in
            index[key] = entry
            return index
        }
        guard let dir = directory, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "index.json"), options: .atomic)
    }

    private func isOwn(_ email: String) -> Bool {
        let own = ownEmails.withLock { cached in
            if let cached { return cached }
            let emails = (try? store.db.read { db in
                try String.fetchAll(db, sql: "SELECT email FROM accounts UNION SELECT email FROM signatures")
            }) ?? []
            let set = Set(emails.map { $0.lowercased() })
            if !set.isEmpty { cached = set }
            return set
        }
        return own.contains(email)
    }

    // MARK: Helpers

    static func decode(_ data: Data?) -> CGImage? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Opaque corners mean the icon is its own tile (Figma, Stripe); transparent ones need a backdrop (Notion).
    static func entry(_ image: CGImage) -> Entry {
        let size = 4
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let opaque = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        } && pixels[3] > 200 && pixels[(size * size - 1) * 4 + 3] > 200
        return .image(image, fullBleed: opaque)
    }

    /// "mail.notion.so" → "notion.so", "news.bbc.co.uk" → "bbc.co.uk": favicons live on the registrable domain.
    static func baseDomain(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count > 2 else { return host.lowercased() }
        let keep = labels[labels.count - 1].count == 2 && labels[labels.count - 2].count <= 3 ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    static let freemail: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
        "aol.com", "proton.me", "protonmail.com", "pm.me", "gmx.com", "gmx.net", "gmx.de", "web.de", "mail.com", "yandex.com",
        "yandex.ru", "zoho.com", "fastmail.com", "hey.com", "tutanota.com", "siol.net", "t-2.net", "amis.net", "qq.com", "163.com",
    ]

    static func isFreemail(_ domain: String) -> Bool {
        freemail.contains(domain) || domain.hasPrefix("yahoo.") || domain.hasPrefix("hotmail.") || domain.hasPrefix("outlook.")
            || domain.hasPrefix("live.") || domain.hasPrefix("ymail.")
    }

    /// Stable across launches (unlike `hashValue`), so a sender keeps their color: FNV-1a of the lowercased address.
    public static func colorIndex(_ email: String, count: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in email.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    /// First letter or digit of the name (or address), uppercased.
    public static func initial(_ name: String) -> String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }
}
