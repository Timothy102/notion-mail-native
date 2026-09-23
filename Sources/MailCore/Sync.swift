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
    public static let defaultBackfillMonths = 3

    public let gmail: GmailClient
    public let store: Store
    /// Messages fetched so far and the total, while backfilling.
    public var progress: @Sendable (_ fetched: Int, _ total: Int) async -> Void = { _, _ in }

    public init(gmail: GmailClient, store: Store) {
        self.gmail = gmail
        self.store = store
    }

    public var backfillMonths: Int {
        (try? store.get(Self.backfillMonthsKey)).flatMap { $0.flatMap(Int.init) } ?? Self.defaultBackfillMonths
    }

    /// Account, labels, send-as identities, mail (history, or a backfill when there is no usable history id) and drafts.
    public func run() async throws {
        let profile = try await gmail.profile()
        let sendAs = try await gmail.sendAs()
        let primary = sendAs.first { $0.isPrimary == true }
        try store.save(account: Account(email: profile.emailAddress, name: primary?.displayName ?? profile.emailAddress))
        try store.save(sendAs: sendAs.map {
            SendAs(email: $0.sendAsEmail, displayName: $0.displayName ?? "", signature: $0.signature ?? "",
                   isDefault: $0.isDefault ?? false, isPrimary: $0.isPrimary ?? false, replyTo: $0.replyToAddress)
        })
        try syncLabels(try await gmail.labels())

        if let historyId = try store.get("historyId") {
            do { try await applyHistory(since: historyId) }
            catch let e as GmailError where e.status == 404 { try await backfill(historyId: profile.historyId) }
        } else {
            try await backfill(historyId: profile.historyId)
        }
        try await syncDrafts()
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

    /// Lists every message id in the window first (so progress has a total), drops local messages in the
    /// window that Gmail no longer has, then fetches what is missing newest first, 100 at a time.
    /// `historyId` is taken before listing, so changes made meanwhile arrive through the next history sync.
    private func backfill(historyId: String) async throws {
        let since = Calendar.current.date(byAdding: .month, value: -backfillMonths, to: .now) ?? .now
        var ids: [String] = []
        var pageToken: String?
        repeat {
            let page = try await gmail.listMessages(q: "after:\(Int(since.timeIntervalSince1970))", pageToken: pageToken,
                                                    maxResults: 500, includeSpamTrash: true)
            ids += (page.messages ?? []).map(\.id)
            pageToken = page.nextPageToken
        } while pageToken != nil

        let listed = Set(ids)
        let known = try await store.db.read { db in
            try Message.select(Column("id"), Column("internalDate")).asRequest(of: Row.self).fetchAll(db)
                .map { (id: $0["id"] as String, date: $0["internalDate"] as Int64) }
        }
        let cutoff = Int64(since.timeIntervalSince1970 * 1000)
        try store.deleteMessages(ids: known.filter { $0.date >= cutoff && !listed.contains($0.id) }.map(\.id))

        let knownIds = Set(known.map(\.id))
        let missing = ids.filter { !knownIds.contains($0) }
        var fetched = ids.count - missing.count
        await progress(fetched, ids.count)
        for start in stride(from: 0, to: missing.count, by: 100) {
            let chunk = Array(missing[start..<min(start + 100, missing.count)])
            try ingest(try await gmail.messages(chunk, concurrency: 8))
            fetched += chunk.count
            await progress(fetched, ids.count)
        }
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

    /// Syncs as soon as the current run (if any) finishes.
    public func syncNow() {
        syncTick?.yield()
    }
}
