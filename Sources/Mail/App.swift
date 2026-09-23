import AppKit
import MailCore
import SwiftUI

@main
struct MailApp: App {
    @State private var app = AppState.launch()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Mail", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: Theme.Metrics.windowMin.width, minHeight: Theme.Metrics.windowMin.height)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(Launch.windowSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Launch-time configuration from the environment.
///
/// - `MAIL_DEMO=1`: in-memory database seeded with fixtures, no network.
/// - `MAIL_SCREEN`: inbox | thread | compose | palette | search | sidebar | empty | settings | syncing | offline | syncfailed
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

extension AppState {
    static func launch() -> AppState {
        do {
            let app: AppState
            if Launch.isDemo {
                let store = try Store()
                try Fixtures.seed(store)
                app = AppState(store: store, gmail: nil)
            } else {
                app = AppState(store: try Store(path: Store.defaultPath), gmail: GmailClient())
            }
            if let theme = Launch.theme { app.theme = theme }
            return app
        } catch {
            fatalError("Couldn't open the mail database: \(error)")
        }
    }
}
