import MailCore
import SwiftUI

/// Sidebar footer status: first-sync progress, offline, or a paused sync. Empty when all is well.
struct SyncIndicator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.syncStatus {
        case .backfilling(let fetched, let total):
            label(total > 0 ? "Syncing mail · \(fetched * 100 / total)%" : "Syncing mail") { DotsLoader().offset(y: 1) }
                .help(total > 0 ? "\(fetched.formatted()) of \(total.formatted()) messages" : "Looking for your mail")
        case .offline:
            label("Offline") { symbol("wifi.slash") }
                .help(pendingHelp)
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
            EmptyView()
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
