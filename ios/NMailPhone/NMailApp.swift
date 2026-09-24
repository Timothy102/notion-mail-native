import MailCore
import SwiftUI

@main
struct NMailApp: App {
    @State private var accounts = AccountManager.launch()

    var body: some Scene {
        WindowGroup {
            RootView().environment(accounts)
        }
    }
}

/// Launch-time configuration from the environment (pass with `SIMCTL_CHILD_` when launching through simctl).
///
/// - `MAIL_DEMO=1`: in-memory database seeded with MailCore's fixtures, no network.
/// - `MAIL_SCREEN`: inbox | thread | html | compose | search | mailboxes | accounts | settings | signin | swipe | empty
/// - `MAIL_THEME`: light | dark; `MAIL_QUERY`: the search preset's query.
enum Launch {
    static let env = ProcessInfo.processInfo.environment
    static var isDemo: Bool { env["MAIL_DEMO"] == "1" }
    static var screen: String { isDemo ? env["MAIL_SCREEN"] ?? "inbox" : "inbox" }
    static var theme: ThemePreference? { env["MAIL_THEME"].flatMap(ThemePreference.init(rawValue:)) }
    static var query: String { env["MAIL_QUERY"] ?? "invoice" }
}

extension AccountManager {
    /// Demo mode signs in one fixture account; `signin` shows none and `accounts` all three.
    /// ponytail: foreground sync only (launch, returning to the foreground, pull to refresh, every 30 s while open).
    /// BGAppRefreshTask background sync is future work; it needs the BGTaskScheduler identifier in Info.plist.
    static func launch() -> AccountManager {
        let manager = Launch.isDemo
            ? AccountManager(demo: Fixtures.accounts, signedIn: ["signin": 0, "accounts": Fixtures.accounts.count][Launch.screen] ?? 1)
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

struct RootView: View {
    @Environment(AccountManager.self) private var accounts

    var body: some View {
        Group {
            if let app = accounts.app {
                MainView().environment(app).id(ObjectIdentifier(app))
            } else {
                SignInView()
            }
        }
        .preferredColorScheme(accounts.app?.theme.colorScheme ?? Launch.theme?.colorScheme)
        .tint(Theme.accent)
    }
}

struct SignInView: View {
    @Environment(AccountManager.self) private var accounts
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Logo").resizable().interpolation(.high).frame(width: 112, height: 112).padding(.bottom, 20)
                .accessibilityHidden(true)
            Text("Welcome to AxiosM").font(.title2.weight(.semibold)).foregroundStyle(Theme.textPrimary).padding(.bottom, 8)
            Text("Your Gmail in a calm, focused inbox.").font(.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.bottom, 36)
            GoogleButton(busy: busy, action: signIn).padding(.horizontal, 32)
            if let error {
                VStack(spacing: 6) {
                    Text("Couldn't sign in").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textRed)
                    Text(error).font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).lineLimit(5)
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
            }
            Spacer()
            Label("Your mail syncs straight from Google and is stored only on this iPhone.", systemImage: "lock")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }

    private func signIn() {
        busy = true
        error = nil
        Task {
            do { try await accounts.addAccount() } catch { self.error = Self.describe(error) }
            busy = false
        }
    }

    static func describe(_ error: Error) -> String {
        if case AuthError.badResponse(let body) = error { return body }
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" { return "The Google sign-in sheet was closed." }
        return error.localizedDescription
    }
}
