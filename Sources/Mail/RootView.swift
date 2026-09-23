import AppKit
import MailCore
import SwiftUI

/// Window shell (SPEC §4.1). Owns layout and layering only; every region is a feature view.
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var signedIn: Bool?
    @State private var keys = KeyRouter()

    var body: some View {
        Group {
            if app.isDemo || signedIn == true {
                Shell()
                    .onAppear {
                        keys.install(app)
                        app.startSync()
                    }
            } else if signedIn == false {
                SignInView { signedIn = true }
            } else {
                Theme.page
            }
        }
        .background(WindowAccessor { window in
            configure(window)
            if Launch.snapshotPath != nil { Snapshot.run(app, window: window) }
        })
        .onChange(of: app.theme, initial: true) { NSApp.appearance = app.theme.appearance }
        .task { if !app.isDemo { signedIn = await Auth.shared.isSignedIn } }
    }

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(Theme.page)
    }
}

private struct Shell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if app.isSidebarVisible {
                    Sidebar()
                        .frame(width: Theme.Metrics.sidebarWidth)
                        .background(Theme.wash)
                        .overlay(alignment: .trailing) { Hairline(vertical: true) }
                        .transition(.move(edge: .leading))
                }
                ContentPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(Theme.Motion.standard, value: app.isSidebarVisible)
            .overlay(alignment: .bottomTrailing) {
                if let request = app.compose, request.isFloating {
                    Composer(request: request)
                        .frame(width: Theme.Metrics.composerWidth,
                               height: min(max(geo.size.height - Theme.Metrics.composerTop - Theme.Metrics.composerInset, 420), 720))
                        .padding(Theme.Metrics.composerInset)
                        .transition(.offset(y: 12).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomLeading) {
                ToastHost()
                    .padding(.leading, (app.isSidebarVisible ? Theme.Metrics.sidebarWidth : 0) + 16)
                    .padding(.bottom, Theme.Metrics.toastBottom)
            }
            .overlay {
                if let page = app.settings {
                    SettingsView(page: page).transition(.opacity)
                }
            }
            .overlay {
                if let mode = app.palette {
                    CommandPalette(mode: mode).transition(.opacity)
                }
            }
            .overlay {
                if let request = app.notionPicker {
                    NotionPicker(request: request).transition(.opacity)
                }
            }
            .animation(Theme.Motion.standard, value: app.compose?.id)
            .animation(Theme.Motion.fast, value: app.notionPicker)
            .animation(Theme.Motion.fast, value: app.palette)
            .animation(Theme.Motion.fast, value: app.settings)
        }
        .ignoresSafeArea()
        .background(Theme.page)
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
    }
}

/// List (or search results) with the thread peek sliding over its right side (§4.4).
private struct ContentPane: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let query = app.searchQuery { SearchView(query: query) } else { InboxList() }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                if let id = app.openThreadId {
                    ThreadView(threadId: id)
                        .id(id)
                        .frame(width: min(geo.size.width, max(Theme.Metrics.peekMinWidth, geo.size.width * Theme.Metrics.peekFraction)),
                               height: geo.size.height)
                        .background(Theme.elevated)
                        .overlay(alignment: .leading) { Hairline(vertical: true) }
                        .shadow(color: .black.opacity(0.04), radius: 6, x: -4)
                        .transition(.offset(x: 16).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.standard, value: app.openThreadId == nil)
        }
        .clipped()
    }
}

private struct SignInView: View {
    let onSignedIn: () -> Void
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Mail").textStyle(.threadTitle)
            Text("Sign in with your Google account to sync Gmail.")
                .textStyle(.body).foregroundStyle(Theme.textSecondary)
            Button {
                busy = true
                Task {
                    do { _ = try await Auth.shared.signIn(); onSignedIn() }
                    catch { self.error = "\(error)" }
                    busy = false
                }
            } label: {
                Text(busy ? "Waiting for browser…" : "Sign in with Google")
            }
            .buttonStyle(MailButtonStyle(kind: .primary, height: Theme.Metrics.buttonMedium))
            .disabled(busy)
            if let error {
                Text(error).textStyle(.small).foregroundStyle(Theme.textRed).textSelection(.enabled).frame(maxWidth: 420)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }
}

extension ComposeRequest {
    /// New messages and drafts float bottom-right; replies and forwards render inline in the thread.
    var isFloating: Bool {
        switch kind {
        case .new, .draft: true
        case .reply, .forward: false
        }
    }
}

extension ThemePreference {
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Hands the hosting NSWindow to `configure` once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    let configure: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
