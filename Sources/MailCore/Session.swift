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
        let loop = syncLoop
        loop?.cancel()
        syncTick?.finish()
        syncLoop = nil
        syncTick = nil
        // An in-flight sync must finish unwinding before the wipe, or it writes rows back afterwards.
        await loop?.value
        if !isDemo {
            await Auth.shared.signOut()
            try? FileManager.default.removeItem(at: ProfilePhoto.url)
        }
        try? store.eraseAll()
        isAccountMenuOpen = false
        settings = nil
        compose = nil
        palette = nil
        account = nil
        avatarImage = nil
        syncStatus = .idle
        go(to: .inbox)
        isSignedIn = false
    }
}
