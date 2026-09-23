import Foundation

/// Pulls Gmail into the Store: a backfill on first run, then `history.list` deltas.
public struct Sync: Sendable {
    public let gmail: GmailClient
    public let store: Store

    public init(gmail: GmailClient, store: Store) {
        self.gmail = gmail
        self.store = store
    }

    /// Account, labels, send-as identities and drafts, then mail: backfill or history.
    public func run(backfillQuery: String = "newer_than:90d") async throws {
        let profile = try await gmail.profile()
        let sendAs = try await gmail.sendAs()
        let primary = sendAs.first { $0.isPrimary == true }
        try store.save(account: Account(email: profile.emailAddress, name: primary?.displayName ?? profile.emailAddress))
        try store.save(sendAs: sendAs.map {
            SendAs(email: $0.sendAsEmail, displayName: $0.displayName ?? "", signature: $0.signature ?? "",
                   isDefault: $0.isDefault ?? false, isPrimary: $0.isPrimary ?? false, replyTo: $0.replyToAddress)
        })
        try store.save(labels: try await gmail.labels().map {
            MailLabel(id: $0.id, name: $0.name, isSystem: $0.type == "system", color: $0.color?.backgroundColor.map(MailLabel.colorName(gmailHex:)))
        })

        if let historyId = try store.get("historyId") {
            do { try await applyHistory(since: historyId) }
            catch let e as GmailError where e.status == 404 { try await backfill(query: backfillQuery, historyId: profile.historyId) }
        } else {
            try await backfill(query: backfillQuery, historyId: profile.historyId)
        }
        try await syncDrafts()
    }

    private func backfill(query: String, historyId: String) async throws {
        var pageToken: String?
        repeat {
            let page = try await gmail.listMessages(q: query, pageToken: pageToken, maxResults: 200, includeSpamTrash: true)
            try ingest(try await gmail.messages((page.messages ?? []).map(\.id)))
            pageToken = page.nextPageToken
        } while pageToken != nil
        try store.set("historyId", historyId)
    }

    private func applyHistory(since start: String) async throws {
        var pageToken: String?
        var latest = start
        repeat {
            let page = try await gmail.history(since: start, pageToken: pageToken)
            var changed = Set<String>()
            var deleted = Set<String>()
            for r in page.history ?? [] {
                r.messagesAdded?.forEach { changed.insert($0.message.id) }
                r.labelsAdded?.forEach { changed.insert($0.message.id) }
                r.labelsRemoved?.forEach { changed.insert($0.message.id) }
                r.messagesDeleted?.forEach { deleted.insert($0.message.id) }
            }
            changed.subtract(deleted)
            try store.deleteMessages(ids: Array(deleted))
            try ingest(try await gmail.messages(Array(changed)))
            latest = page.historyId
            pageToken = page.nextPageToken
        } while pageToken != nil
        try store.set("historyId", latest)
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
