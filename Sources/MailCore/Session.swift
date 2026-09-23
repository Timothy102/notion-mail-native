import Foundation
import GRDB

extension Store {
    /// Deletes every synced and local row: what sign-out leaves behind is an empty database.
    public func eraseAll() throws {
        try db.write { db in
            for table in ["thread_labels", "attachments", "drafts", "notion_links", "messages", "threads", "labels", "signatures", "accounts", "kv"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}

extension AppState {
    /// Stops syncing, forgets the Google tokens, clears the local store and returns to sign-in.
    public func signOut() async {
        syncLoop?.cancel()
        syncTick?.finish()
        syncLoop = nil
        syncTick = nil
        if !isDemo { await Auth.shared.signOut() }
        try? store.eraseAll()
        isAccountMenuOpen = false
        settings = nil
        compose = nil
        palette = nil
        account = nil
        syncStatus = .idle
        go(to: .inbox)
        isSignedIn = false
    }
}
