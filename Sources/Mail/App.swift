import AppKit
import MailCore
import SwiftUI

@main
struct MailApp: App {
    @State private var accounts = AccountManager.launch()
    @NSApplicationDelegateAdaptor private var delegate: SnapshotLauncher

    init() {
        NSApplication.shared.setActivationPolicy(Launch.snapshotPath == nil ? .regular : .prohibited)
    }

    var body: some Scene {
        Window("Mail", id: "main") {
            RootView()
                .environment(accounts)
                .frame(minWidth: Theme.Metrics.windowMin.width, minHeight: Theme.Metrics.windowMin.height)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(Launch.snapshotPath == nil ? .automatic : .suppressed)
        .defaultSize(Launch.windowSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Launch-time configuration from the environment.
///
/// - `MAIL_DEMO=1`: in-memory database seeded with fixtures, no network.
/// - `MAIL_SCREEN`: see scripts/snap.sh for the list; `MAIL_QUERY` (search), `MAIL_PALETTE=search`, `MAIL_NOTION=off` tune them.
/// - `MAIL_THEME`: light | dark
/// - `MAIL_SNAPSHOT=/path.png`: render `MAIL_SCREEN`, capture the window, exit. Implies demo.
/// - `MAIL_WINDOW=1440x900`: window size (default 1280x800).
enum Launch {
    static let env = ProcessInfo.processInfo.environment
    static var snapshotPath: String? { env["MAIL_SNAPSHOT"] }
    static var isDemo: Bool { env["MAIL_DEMO"] == "1" || snapshotPath != nil }
    static var screen: String { env["MAIL_SCREEN"] ?? "inbox" }
    static var theme: ThemePreference? { env["MAIL_THEME"].flatMap(ThemePreference.init(rawValue:)) }

    static var windowSize: CGSize {
        let parts = (env["MAIL_WINDOW"] ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : Theme.Metrics.windowDefault
    }
}

extension AccountManager {
    /// Demo mode signs in one fixture account; `signin` shows none and `account-switcher` all three.
    static func launch() -> AccountManager {
        let manager = Launch.isDemo
            ? AccountManager(demo: Fixtures.accounts, signedIn: ["signin": 0, "account-switcher": Fixtures.accounts.count][Launch.screen] ?? 1)
            : AccountManager(storage: .default)
        manager.configure = { app in if let theme = Launch.theme { app.theme = theme } }
        do {
            try manager.start()
        } catch {
            fatalError("Couldn't open the mail database: \(error)")
        }
        return manager
    }
}
