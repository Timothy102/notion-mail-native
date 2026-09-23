import AppKit
import Foundation
import GRDB
import Network

public enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing
    /// First run (or a resync after the history id expired): messages fetched so far of `total`.
    case backfilling(fetched: Int, total: Int)
    case offline
    case failed(String)

    public var isBackfilling: Bool {
        if case .backfilling = self { true } else { false }
    }
}

/// Pulls Gmail into the Store: a backfill of the last `backfillMonths` on first run, then `history.list` deltas.
public struct Sync: Sendable {
    public static let backfillMonthsKey = "backfillMonths"
    public static let defaultBackfillMonths = 12
    /// Measured on Tim's account: 25 in flight fetches 200 full messages in ~2.8s; 40 trips Gmail's per-user rate limit.
    static let fetchConcurrency = 25
    /// The first chunk is small so the newest inbox rows paint within about a second.
    static let firstChunk = 50

    public let gmail: GmailClient
    public let store: Store
    /// Messages fetched so far and the total, while backfilling.
    public var progress: @Sendable (_ fetched: Int, _ total: Int) async -> Void = { _, _ in }
    /// Called as soon as the profile is known, before any mail is fetched.
    public var onAccount: @Sendable (Account) async -> Void = { _ in }
    /// Where the Google profile photo is cached; nil skips it.
    public var avatarURL: URL?
    /// Called with the PNG when a new Google profile photo has been cached.
    public var onAvatar: @Sendable (Data) async -> Void = { _ in }

    public init(gmail: GmailClient, store: Store) {
        self.gmail = gmail
        self.store = store
    }

    public var backfillMonths: Int {
        (try? store.get(Self.backfillMonthsKey)).flatMap { $0.flatMap(Int.init) } ?? Self.defaultBackfillMonths
    }

    /// Account, labels, send-as identities, mail (history, or a backfill when there is no usable history id) and drafts.
    public func run() async throws {
        SyncLog.write("sync run start")
        let profile = try await gmail.profile()
        let sendAs = try await gmail.sendAs()
        let primary = sendAs.first { $0.isPrimary == true } ?? sendAs.first { $0.sendAsEmail.lowercased() == profile.emailAddress.lowercased() }
        let displayName = primary?.displayName.flatMap { $0.isEmpty ? nil : $0 }
        try await publishAccount(email: profile.emailAddress, displayName: displayName)
        await refreshGoogleProfile(email: profile.emailAddress)
        try store.save(sendAs: sendAs.map {
            SendAs(email: $0.sendAsEmail, displayName: $0.displayName ?? "", signature: $0.signature ?? "",
                   isDefault: $0.isDefault ?? false, isPrimary: $0.isPrimary ?? false, replyTo: $0.replyToAddress)
        })
        try syncLabels(try await gmail.labels())

        if let historyId = try store.get("historyId") {
            do {
                try await applyHistory(since: historyId)
                if backfilledMonths < backfillMonths { try await backfill(historyId: profile.historyId) }
            }
            catch let e as GmailError where e.status == 404 { try await backfill(historyId: profile.historyId) }
        } else {
            try await backfill(historyId: profile.historyId)
        }
        try await syncDrafts()
        if displayName == nil { try await publishAccount(email: profile.emailAddress, displayName: nil) }
    }

    /// Months the last completed backfill covered; widening `backfillMonths` backfills the difference.
    private var backfilledMonths: Int {
        (try? store.get(Self.backfilledMonthsKey)).flatMap { $0.flatMap(Int.init) } ?? Self.legacyBackfillMonths
    }
    /// Installs that finished a backfill before this key existed used a 3-month window.
    static let legacyBackfillMonths = 3
    static let backfilledMonthsKey = "backfilledMonths"

    /// Gmail's send-as display name is often empty; the name on mail the user sent is the next best source.
    private func publishAccount(email: String, displayName: String?) async throws {
        let sent = try await store.db.read { db in
            try String.fetchAll(db, sql: "SELECT \"from\" FROM messages WHERE labelIds LIKE '%SENT%' ORDER BY internalDate DESC LIMIT 50")
        }
        let name = try store.get(Self.googleNameKey) ?? displayName ?? sent.lazy.compactMap(Self.displayName(from:)).first ?? email
        let account = Account(email: email, name: name)
        try store.save(account: account)
        await onAccount(account)
    }

    /// `Tim Cvetko <tim@x.com>` or `"Tim Cvetko" <tim@x.com>` → `Tim Cvetko`; a bare address has no name.
    static func displayName(from header: String) -> String? {
        guard let bracket = header.firstIndex(of: "<") else { return nil }
        let name = header[..<bracket].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return name.isEmpty || name.contains("@") ? nil : name
    }

    private func syncLabels(_ remote: [GmailLabel]) throws {
        let labels = remote.map {
            MailLabel(id: $0.id, name: $0.name, isSystem: $0.type == "system", color: $0.color?.backgroundColor.map(MailLabel.colorName(gmailHex:)))
        }
        try store.save(labels: labels)
        try store.db.write { db in
            _ = try MailLabel.filter(!labels.map(\.id).contains(Column("id"))).deleteAll(db)
        }
    }

    /// Streams the inbox first (any age), then everything in the window, newest first: each listed page is
    /// fetched and stored right away so the list fills while the backfill continues.
    /// Afterwards, local messages in the window that Gmail no longer lists are dropped.
    /// `historyId` is taken before listing, so changes made meanwhile arrive through the next history sync.
    private func backfill(historyId: String) async throws {
        let since = Calendar.current.date(byAdding: .month, value: -backfillMonths, to: .now) ?? .now
        let window = "after:\(Int(since.timeIntervalSince1970))"
        let known = try await store.db.read { db in
            try Message.select(Column("id"), Column("internalDate")).asRequest(of: Row.self).fetchAll(db)
                .map { (id: $0["id"] as String, date: $0["internalDate"] as Int64) }
        }
        var have = Set(known.map(\.id))
        var listedInWindow = Set<String>()
        var done = Set<String>()
        var total = 0

        for (query, isWindow) in [("in:inbox", false), (window, true)] {
            var pageToken: String?
            repeat {
                let page = try await SyncLog.time("list \(isWindow ? "window" : "inbox")") {
                    try await gmail.listMessages(q: query, pageToken: pageToken, maxResults: 500, includeSpamTrash: isWindow)
                }
                let ids = (page.messages ?? []).map(\.id)
                SyncLog.write("  page: \(ids.count) ids, estimate \(page.resultSizeEstimate ?? -1), known \(ids.filter(have.contains).count)")
                if isWindow { listedInWindow.formUnion(ids) }
                total = max(total, isWindow ? page.resultSizeEstimate ?? 0 : 0, done.count + ids.count)
                done.formUnion(ids.filter(have.contains))
                let missing = ids.filter { !have.contains($0) }
                var start = 0
                while start < missing.count {
                    let size = done.isEmpty ? Self.firstChunk : 100
                    let chunk = Array(missing[start..<min(start + size, missing.count)])
                    start += chunk.count
                    let fetchedChunk = try await SyncLog.time("  fetch \(chunk.count)") {
                        try await gmail.messages(chunk, concurrency: Self.fetchConcurrency)
                    }
                    try await SyncLog.time("  ingest \(fetchedChunk.count) returned") { try ingest(fetchedChunk) }
                    have.formUnion(chunk)
                    done.formUnion(chunk)
                    await progress(done.count, max(total, done.count))
                }
                if missing.isEmpty { await progress(done.count, max(total, done.count)) }
                pageToken = page.nextPageToken
            } while pageToken != nil
        }
        await progress(done.count, done.count)
        try store.set(Self.backfilledMonthsKey, String(backfillMonths))

        let cutoff = Int64(since.timeIntervalSince1970 * 1000)
        try store.deleteMessages(ids: known.filter { $0.date >= cutoff && !listedInWindow.contains($0.id) }.map(\.id))
        try store.set("historyId", historyId)
    }

    private func applyHistory(since start: String) async throws {
        var changes = HistoryChanges()
        var latest = start
        var pageToken: String?
        repeat {
            let page = try await gmail.history(since: start, pageToken: pageToken)
            changes.add(page.history ?? [])
            latest = page.historyId
            pageToken = page.nextPageToken
        } while pageToken != nil
        let unknown = try apply(changes)
        try ingest(try await gmail.messages(unknown.sorted()))
        try store.set("historyId", latest)
    }

    /// Applies deletions and label changes to known messages in one transaction. Returns the ids to fetch:
    /// added messages, and label changes on messages outside the local window (say an old mail just starred).
    func apply(_ changes: HistoryChanges) throws -> Set<String> {
        try store.db.write { db in
            var threads = try String.fetchSet(db, Message.select(Column("threadId")).filter(keys: changes.deleted))
            try Message.deleteAll(db, keys: changes.deleted)
            var fetch = changes.added
            for (id, delta) in changes.labels {
                guard var m = try Message.fetchOne(db, key: id) else { fetch.insert(id); continue }
                m.labelIds = Set(m.labelIds).subtracting(delta.remove).union(delta.add).sorted()
                try m.update(db)
                threads.insert(m.threadId)
            }
            fetch.subtract(try String.fetchSet(db, Message.select(Column("id")).filter(keys: fetch)))
            for id in threads { try Store.refreshThread(db, id: id) }
            return fetch
        }
    }

    private func syncDrafts() async throws {
        var pageToken: String?
        var ids: [String] = []
        repeat {
            let page = try await gmail.drafts(pageToken: pageToken)
            for d in page.drafts {
                guard let m = d.message else { continue }
                ids.append(d.id)
                try store.save(draft: Draft(id: d.id, messageId: m.id, threadId: m.threadId, updatedAt: .now))
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        let stale = try await store.db.read { try Draft.fetchAll($0).map(\.id) }.filter { !ids.contains($0) }
        for id in stale { try store.deleteDraft(id: id) }
    }

    public func ingest(_ messages: [GmailMessage]) throws {
        let parsed = messages.compactMap(Message.make(gmail:))
        try store.upsert(messages: parsed.map(\.0), attachments: parsed.flatMap(\.1))
    }
}

/// History records folded into their net effect, in order: a label added then removed cancels out,
/// and a message added then deleted is never fetched.
struct HistoryChanges {
    var added = Set<String>()
    var deleted = Set<String>()
    var labels: [String: (add: Set<String>, remove: Set<String>)] = [:]

    mutating func add(_ records: [GmailHistory.Record]) {
        for r in records {
            for a in r.messagesAdded ?? [] { added.insert(a.message.id); deleted.remove(a.message.id) }
            for d in r.messagesDeleted ?? [] { deleted.insert(d.message.id); added.remove(d.message.id); labels[d.message.id] = nil }
            for c in r.labelsAdded ?? [] where !deleted.contains(c.message.id) {
                let ids = Set(c.labelIds ?? [])
                labels[c.message.id, default: ([], [])].add.formUnion(ids)
                labels[c.message.id]!.remove.subtract(ids)
            }
            for c in r.labelsRemoved ?? [] where !deleted.contains(c.message.id) {
                let ids = Set(c.labelIds ?? [])
                labels[c.message.id, default: ([], [])].remove.formUnion(ids)
                labels[c.message.id]!.add.subtract(ids)
            }
        }
    }
}

extension URLError {
    /// Errors that mean "no network right now": worth retrying later rather than giving up.
    var isOffline: Bool {
        [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
         .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed].contains(code)
    }
}

func isOffline(_ error: any Error) -> Bool {
    (error as? URLError)?.isOffline ?? false
}

extension AppState {
    /// Syncs now, then every 30 s, whenever the app becomes active and when the network comes back.
    /// Also resumes Gmail calls queued while offline. No-op in demo mode.
    public func startSync() {
        guard let gmail, syncLoop == nil else { return }
        isAwaitingFirstSync = (try? store.get("historyId")) == nil
        var sync = Sync(gmail: gmail, store: store)
        sync.avatarURL = avatarURL
        sync.onAccount = { account in
            await MainActor.run { [weak self] in self?.account = account }
        }
        sync.onAvatar = { png in
            await MainActor.run { [weak self] in self?.avatarImage = NSImage(data: png) }
        }
        sync.progress = { fetched, total in
            await MainActor.run { [weak self] in self?.syncStatus = .backfilling(fetched: fetched, total: total) }
        }
        actions.onOfflineChange = { [weak self] offline in
            guard let self else { return }
            if offline { syncStatus = .offline } else if syncStatus == .offline { syncStatus = .idle }
        }

        let (ticks, tick) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        tick.yield()
        let timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                tick.yield()
            }
        }
        let activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
            tick.yield()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { if $0.status == .satisfied { tick.yield() } }
        monitor.start(queue: .main)

        syncLoop = Task { [weak self] in
            for await _ in ticks {
                guard let self else { break }
                actions.resume()
                if !syncStatus.isBackfilling { syncStatus = .syncing }
                do {
                    try await sync.run()
                    actions.reapplyPending()
                    account = try? await store.db.read(Store.account)
                    syncStatus = .idle
                    isAwaitingFirstSync = false
                } catch where isOffline(error) {
                    syncStatus = .offline
                } catch {
                    syncStatus = .failed(error.localizedDescription)
                }
            }
            timer.cancel()
            monitor.cancel()
            NotificationCenter.default.removeObserver(activation)
        }
        syncTick = tick
    }

    /// Cancels the sync loop; the returned task ends once an in-flight run has unwound.
    @discardableResult
    public func stopSync() -> Task<Void, Never>? {
        let loop = syncLoop
        loop?.cancel()
        syncTick?.finish()
        syncLoop = nil
        syncTick = nil
        return loop
    }

    /// Syncs as soon as the current run (if any) finishes.
    public func syncNow() {
        syncTick?.yield()
    }
}
