import MailCore
import SwiftUI

/// Sidebar footer status: first-sync progress, "Up to date" briefly after it, offline, or a paused sync.
/// Empty when all is well.
struct SyncIndicator: View {
    @Environment(AppState.self) private var app
    @Environment(AccountManager.self) private var accounts
    @State private var justFinished = false

    var body: some View {
        status
            .animation(.easeOut(duration: 0.3), value: app.syncStatus)
            .animation(.easeOut(duration: 0.3), value: justFinished)
            .onChange(of: app.syncStatus.isBackfilling) { was, now in
                if was, !now, app.syncStatus == .idle || app.syncStatus == .syncing { justFinished = true }
            }
            .task(id: justFinished) {
                guard justFinished else { return }
                try? await Task.sleep(for: .seconds(2.5))
                justFinished = false
            }
    }

    @ViewBuilder
    private var status: some View {
        switch app.syncStatus {
        case .backfilling(let fetched, let total):
            let count = "\(fetched.formatted()) of \(total.formatted())"
            ViewThatFits(in: .horizontal) {
                label(total > 0 ? "Syncing · \(count)" : "Syncing") { ProgressRing(fraction: app.syncStatus.backfillFraction) }
                label(total > 0 ? count : "Syncing") { ProgressRing(fraction: app.syncStatus.backfillFraction) }
            }
            .help(total > 0 ? "\(fetched.formatted()) of \(total.formatted()) messages downloaded" : "Looking for your mail")
        case .offline:
            label("Offline") { symbol("wifi.slash") }
                .help(pendingHelp)
        case .signedOut:
            Button(action: reauthenticate) {
                label("Sign in again") { symbol("person.crop.circle.badge.exclamationmark") }
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .hoverFill()
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            .help("Google ended this login. Sign in again to keep syncing.")
        case .failed(let message):
            Button { app.syncNow() } label: {
                label("Sync paused") { symbol("exclamationmark.triangle") }
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .hoverFill()
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            .help("\(message)\nClick to retry.")
        case .idle, .syncing:
            if justFinished {
                label("Up to date") { symbol("checkmark") }
            }
        }
    }

    private func reauthenticate() {
        Task {
            do { try await accounts.reauthenticate() } catch { app.show(Toast("Couldn't sign in: \(SignInView.describe(error))")) }
        }
    }

    private var pendingHelp: String {
        let count = app.actions.pendingCount
        return count == 0 ? "New mail will appear when you're back online."
            : "\(count) \(count == 1 ? "change" : "changes") will sync when you're back online."
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.iconSecondary)
    }

    private func label(_ text: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 6) {
            icon().frame(width: 16)
            Text(text).textStyle(.small).foregroundStyle(Theme.textTertiary).lineLimit(1).monospacedDigit()
        }
        .fixedSize()
        .transition(.opacity)
    }
}
