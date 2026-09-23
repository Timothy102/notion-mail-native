import AppKit
import Foundation
import GRDB
import Observation
import os

/// Signed-in accounts in the order the menu lists them, and the one last open.
public struct AccountRegistry: Codable, Sendable, Equatable {
    public var emails: [String] = []
    public var active: String?
    /// Last known Google name per account, for menu rows of accounts not opened this launch.
    public var names: [String: String] = [:]

    public init(emails: [String] = [], active: String? = nil, names: [String: String] = [:]) {
        self.emails = emails
        self.active = active
        self.names = names
    }
}

/// On-disk layout under `base` (normally `~/Library/Application Support/Mail`):
/// `accounts.json`, and `accounts/<email>/` holding that account's `mail.sqlite` and `avatar.png`.
/// Refresh tokens live in Secrets under `refresh_token.<email>`.
public struct AccountStorage: Sendable {
    public static let `default` = AccountStorage(
        base: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Mail"))

    public let base: URL

    public init(base: URL) {
        self.base = base
    }

    public func directory(_ email: String) -> URL { base.appending(path: "accounts").appending(path: email, directoryHint: .isDirectory) }
    public func database(_ email: String) -> String { directory(email).appending(path: "mail.sqlite").path }
    public func avatar(_ email: String) -> URL { directory(email).appending(path: "avatar.png") }
    var registryURL: URL { base.appending(path: "accounts.json") }

    public func loadRegistry() -> AccountRegistry {
        (try? JSONDecoder().decode(AccountRegistry.self, from: Data(contentsOf: registryURL))) ?? AccountRegistry()
    }

    public func save(_ registry: AccountRegistry) throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try JSONEncoder().encode(registry).write(to: registryURL, options: .atomic)
    }

    /// Forgets the login and deletes the account's mail and photo. The registry is the caller's.
    public func remove(_ email: String) {
        Secrets.delete(Auth.tokenKey(email))
        try? FileManager.default.removeItem(at: directory(email))
    }

    /// Single-account installs kept `mail.sqlite` (+ -wal/-shm) and `avatar.png` directly under `base`, and the
    /// login under `refresh_token`. Moves them to the account's directory and key, so that account stays signed
    /// in with its mail. The email comes from the database's `accounts` row; without one there is nothing to
    /// attach the login to and everything is left as it was.
    public func migrateLegacy() throws {
        let legacyDB = base.appending(path: "mail.sqlite")
        guard let token = Secrets.get("refresh_token"), FileManager.default.fileExists(atPath: legacyDB.path) else { return }
        let account: Account? = try {
            let db = try DatabaseQueue(path: legacyDB.path)
            defer { try? db.close() }
            return try db.read { db in try db.tableExists("accounts") ? Store.account(db) : nil }
        }()
        guard let account else { return }

        try Secrets.set(Auth.tokenKey(account.email), token)
        var registry = loadRegistry()
        if !registry.emails.contains(account.email) { registry.emails.insert(account.email, at: 0) }
        registry.active = registry.active ?? account.email
        registry.names[account.email] = registry.names[account.email] ?? account.name
        try save(registry)

        let dir = directory(account.email)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The database moves last: after a crash midway it is still here and the next launch finishes the move.
        for name in ["mail.sqlite-wal", "mail.sqlite-shm", "mail.sqlite-journal", "avatar.png", "mail.sqlite"] {
            let from = base.appending(path: name), to = dir.appending(path: name)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
            try FileManager.default.moveItem(at: from, to: to)
        }
        Secrets.delete("refresh_token")
    }
}

/// Every signed-in account and the AppState of the open one. Switching stops the old account's sync
/// and starts the new one's; AppStates are kept, so switching back is instant.
/// ponytail: only the active account syncs; inactive ones catch up (history deltas) when opened.
/// Add a background Sync per cached AppState if unread counts for other accounts are ever wanted.
@MainActor @Observable
public final class AccountManager {
    /// nil in demo mode: fixture accounts, nothing on disk.
    public let storage: AccountStorage?
    public private(set) var registry: AccountRegistry
    /// The open account's state; nil shows sign-in.
    public private(set) var app: AppState?
    /// Runs on each AppState when it is created.
    @ObservationIgnored public var configure: (AppState) -> Void = { _ in }
    @ObservationIgnored private var apps: [String: AppState] = [:]
    @ObservationIgnored private var demoAccounts: [Account] = []
    private static let log = Logger(subsystem: "NMail", category: "accounts")
    static let maxShortcuts = 9

    public var isDemo: Bool { storage == nil }
    public var emails: [String] { registry.emails }
    public var activeEmail: String? { registry.active }

    public init(storage: AccountStorage) {
        self.storage = storage
        do { try storage.migrateLegacy() } catch { Self.log.error("legacy migration failed: \(String(describing: error), privacy: .public)") }
        registry = storage.loadRegistry()
    }

    /// Demo mode: `available` fixture accounts, the first `signedIn` of them signed in.
    public init(demo available: [Account], signedIn: Int) {
        storage = nil
        demoAccounts = available
        let accounts = available.prefix(signedIn)
        registry = AccountRegistry(emails: accounts.map(\.email), active: accounts.first?.email,
                                   names: Dictionary(accounts.map { ($0.email, $0.name) }) { a, _ in a })
    }

    /// Opens the last active account.
    public func start() throws {
        if let email = registry.active.flatMap({ registry.emails.contains($0) ? $0 : nil }) ?? registry.emails.first {
            try activate(email)
        }
    }

    public func switchTo(_ email: String) {
        guard email != registry.active else { return }
        do { try activate(email) } catch { app?.show(Toast("Couldn't open \(email): \(error.localizedDescription)")) }
    }

    public func name(of email: String) -> String {
        apps[email]?.account?.name ?? registry.names[email] ?? email
    }

    public func avatar(of email: String) -> NSImage? {
        if let app = apps[email] { return app.avatarImage }
        return storage.flatMap { NSImage(contentsOf: $0.avatar(email)) }
    }

    /// Google sign-in for another account (the chooser is shown), then switches to it.
    public func addAccount() async throws {
        guard storage != nil else {
            if let next = demoAccounts.first(where: { !registry.emails.contains($0.email) }) {
                registry.emails.append(next.email)
                registry.names[next.email] = next.name
                try activate(next.email)
            }
            return
        }
        let auth = Auth(email: nil)
        let email = try await auth.signIn()
        if !registry.emails.contains(email) { registry.emails.append(email) }
        if apps[email] == nil { apps[email] = try makeApp(email, auth: auth) }
        try activate(email)
    }

    /// Signs out of the open account only: stops its sync, deletes its login and mail, and opens the next account.
    public func signOut() async {
        guard let email = registry.active, let current = app else { return }
        // An in-flight sync must unwind before the delete, or it writes rows back afterwards.
        await current.stopSync()?.value
        apps[email] = nil
        app = nil
        registry.emails.removeAll { $0 == email }
        registry.names[email] = nil
        registry.active = nil
        storage?.remove(email)
        saveRegistry()
        if let next = registry.emails.first {
            do { try activate(next) } catch { Self.log.error("couldn't open \(next, privacy: .public): \(String(describing: error), privacy: .public)") }
        }
    }

    private func activate(_ email: String) throws {
        let next = try apps[email] ?? makeApp(email)
        apps[email] = next
        if let previous = app, previous !== next {
            previous.stopSync()
            previous.palette = nil
            previous.isAccountMenuOpen = false
            next.theme = previous.theme
            if let from = registry.active, let name = previous.account?.name { registry.names[from] = name }
        }
        registry.active = email
        saveRegistry()
        registerSwitchCommands(in: next)
        app = next
        next.startSync()
    }

    private func makeApp(_ email: String, auth: Auth? = nil) throws -> AppState {
        let app: AppState
        if let storage {
            let auth = auth ?? Auth(email: email)
            app = AppState(store: try Store(path: storage.database(email)),
                           gmail: GmailClient(token: { try await auth.token(refresh: $0) }),
                           avatarURL: storage.avatar(email))
        } else {
            let store = try Store()
            try Fixtures.seed(store)
            if let account = demoAccounts.first(where: { $0.email == email }), account.email != Fixtures.me.email {
                try store.db.write { _ = try Account.deleteAll($0) }
                try store.save(account: account)
            }
            app = AppState(store: store, gmail: nil)
        }
        configure(app)
        return app
    }

    /// ⌘1…⌘9, also listed in the palette as "Switch to <email>".
    private func registerSwitchCommands(in app: AppState) {
        app.commands.unregister((1...Self.maxShortcuts).map { "account.switch.\($0)" })
        app.commands.register(registry.emails.prefix(Self.maxShortcuts).enumerated().map { i, email in
            Command(id: "account.switch.\(i + 1)", title: "Switch to \(email)", group: .misc, icon: "person.crop.circle",
                    shortcuts: [Shortcut("cmd+\(i + 1)")], keywords: ["account", "switch"],
                    isAvailable: { [weak self] in self?.registry.active != email }) { [weak self] in self?.switchTo(email) }
        })
    }

    private func saveRegistry() {
        guard let storage else { return }
        do { try storage.save(registry) } catch { Self.log.error("couldn't save accounts: \(String(describing: error), privacy: .public)") }
    }
}
