import MailCore
import SwiftUI

enum MainSheet: String, Identifiable {
    case mailboxes, accounts, settings
    var id: String { rawValue }
}

/// The signed-in app: the inbox navigation stack, the compose sheet, the mailbox / account / settings sheets and toasts.
struct MainView: View {
    @Environment(AppState.self) private var app
    @State private var path: [String] = []
    @State private var sheet: MainSheet?
    @State private var presetApplied = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $path) {
            InboxView(sheet: $sheet, open: open)
                .navigationDestination(for: String.self) { ThreadView(threadId: $0) }
        }
        .overlay(alignment: .bottom) {
            ToastHost().padding(.bottom, path.isEmpty ? 84 : 56)
        }
        .sheet(item: $app.compose) { ComposeView(request: $0).preferredColorScheme(app.theme.colorScheme) }
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .mailboxes: MailboxesSheet(sheet: $sheet)
                case .accounts: AccountsSheet(sheet: $sheet)
                case .settings: SettingsView()
                }
            }
            .environment(app)
            .preferredColorScheme(app.theme.colorScheme)
        }
        .onChange(of: path) { if path.isEmpty { app.closeThread() } }
        .task {
            while !Task.isCancelled {
                app.actions.wakeDueReminders()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onAppear(perform: applyPreset)
    }

    /// Opens a thread; a thread that is only a draft opens in the composer instead.
    private func open(_ thread: MailThread) {
        if thread.messageCount == 0, thread.hasDraft,
           let draft = try? app.store.db.read({ try Store.drafts($0).first { $0.threadId == thread.id } }) {
            app.compose = ComposeRequest(.draft(id: draft.id))
            return
        }
        app.open(thread.id)
        path.append(thread.id)
    }

    /// `MAIL_SCREEN` presets for demo screenshots.
    private func applyPreset() {
        guard Launch.isDemo, !presetApplied else { return }
        presetApplied = true
        let threads = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
        switch Launch.screen {
        case "thread":
            if let t = threads.first(where: { $0.messageCount >= 3 && !$0.hasDraft }) ?? threads.first { open(t) }
        case "compose":
            let target = threads.first { $0.messageCount >= 2 && $0.participants.contains(",") }.flatMap { app.replyTarget(threadId: $0.id) }
            app.compose = ComposeRequest(target.map { .reply(messageId: $0.id, all: true) } ?? .new(to: []))
        case "html":
            let all = (try? app.store.db.read { try Store.threads($0, in: .all) }) ?? []
            if let t = all.first(where: { app.replyTarget(threadId: $0.id)?.bodyHTML.map(MailHTML.isRich) == true }) { open(t) }
        case "mailboxes": sheet = .mailboxes
        case "accounts": sheet = .accounts
        case "settings": sheet = .settings
        case "empty": app.go(to: .spam)
        case "signedout": app.syncStatus = .signedOut
        default: break
        }
    }
}

extension AppState {
    /// Pull to refresh: syncs now and returns when the run is over (demo mode just pauses).
    func refresh() async {
        guard !isDemo else {
            try? await Task.sleep(for: .milliseconds(700))
            return
        }
        syncNow()
        try? await Task.sleep(for: .milliseconds(300))
        let deadline = Date.now.addingTimeInterval(30)
        while syncStatus == .syncing, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
