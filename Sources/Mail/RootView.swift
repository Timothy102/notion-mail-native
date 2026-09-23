import AppKit
import MailCore
import SwiftUI

/// Window shell (SPEC §4.1). Owns layout and layering only; every region is a feature view.
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var keys = KeyRouter()

    var body: some View {
        Group {
            if app.isSignedIn == true {
                Shell()
                    .onAppear {
                        keys.install(app)
                        app.startSync()
                    }
            } else if app.isSignedIn == false {
                SignInView { app.isSignedIn = true }
            } else {
                Theme.page
            }
        }
        .background(WindowAccessor { window in
            configure(window)
            if Launch.snapshotPath != nil { Snapshot.run(app, window: window) }
        })
        .onChange(of: app.theme, initial: true) { NSApp.appearance = app.theme.appearance }
        .task { if app.isSignedIn == nil { app.isSignedIn = await Auth.shared.isSignedIn } }
    }

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(Theme.page)
        TrafficLights.install(window)
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
            .overlay(alignment: .topLeading) {
                if app.isAccountMenuOpen {
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { app.isAccountMenuOpen = false }
                        AccountMenu()
                            .padding(.leading, Theme.Metrics.sidebarItemInset + 4)
                            .padding(.top, Theme.Metrics.titleBarHeight + 40)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
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
            .animation(Theme.Motion.fast, value: app.isAccountMenuOpen)
        }
        .ignoresSafeArea()
        .task {
            while !Task.isCancelled {
                app.actions.wakeDueReminders()
                try? await Task.sleep(for: .seconds(60))
            }
        }
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

struct SignInView: View {
    let onSignedIn: () -> Void
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(spacing: 0) {
                appIcon
                    .frame(width: 112, height: 112)
                    .padding(.bottom, 20)
                Text("Welcome to NMail").textStyle(.threadTitle)
                    .padding(.bottom, 8)
                Text("Your Gmail in a calm, keyboard-first inbox.")
                    .textStyle(.body).foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 32)
                GoogleButton(busy: busy, action: signIn)
                if busy {
                    Text("Finish signing in on the Google page, then come back here.")
                        .textStyle(.small).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 12)
                }
                if let error {
                    VStack(spacing: 6) {
                        Text("Couldn't sign in").textStyle(.smallSemibold).foregroundStyle(Theme.textRed)
                        Text(error).textStyle(.small).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).textSelection(.enabled).lineLimit(4)
                    }
                    .frame(maxWidth: 360)
                    .padding(.top, 16)
                }
            }
            Spacer(minLength: 40)
            Label("Your mail syncs straight from Google and is stored only on this Mac.", systemImage: "lock")
                .labelStyle(.titleAndIcon)
                .textStyle(.small).foregroundStyle(Theme.textTertiary)
                .padding(.bottom, 28)
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }

    private var appIcon: some View {
        let url = Bundle.appResources.url(forResource: "app-icon", withExtension: "png", subdirectory: "Art")
        return Image(nsImage: url.flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage)
            .resizable().interpolation(.high)
    }

    private func signIn() {
        busy = true
        error = nil
        Task {
            do {
                _ = try await Auth.shared.signIn()
                NSApp.activate()
                onSignedIn()
            }
            catch { self.error = Self.describe(error) }
            busy = false
        }
    }

    private static func describe(_ error: Error) -> String {
        if case AuthError.badResponse(let body) = error { return body }
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession" { return "The Google sign-in window was closed." }
        return error.localizedDescription
    }
}

/// "Sign in with Google" per Google's branding guidelines: neutral fill, 1pt outline, the four-colour G.
private struct GoogleButton: View {
    var busy: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().controlSize(.small).frame(width: 18, height: 18) } else { GoogleG().frame(width: 18, height: 18) }
                Text(busy ? "Continue in your browser…" : "Sign in with Google")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color(0x1F1F1F, dark: 0xE3E3E3))
            .frame(width: 260, height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(0x747775, dark: 0x8E918F), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        hovering && !busy ? Color(0xF6F7F8, dark: 0x1E1F20) : Color(0xFFFFFF, dark: 0x131314)
    }
}

private struct GoogleG: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let w = d * 0.2
            ZStack {
                arc(0.125, 0.375, Color(0x34A853, dark: 0x34A853), w)
                arc(0.375, 0.53, Color(0xFBBC05, dark: 0xFBBC05), w)
                arc(0.53, 0.875, Color(0xEA4335, dark: 0xEA4335), w)
                arc(0.0, 0.125, Color(0x4285F4, dark: 0x4285F4), w)
                Rectangle().fill(Color(0x4285F4, dark: 0x4285F4))
                    .frame(width: d * 0.46, height: w)
                    .offset(x: d * 0.21)
            }
            .frame(width: d, height: d)
        }
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color, _ width: CGFloat) -> some View {
        Circle().trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .padding(width / 2)
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

/// Keeps the window buttons at SPEC §3 positions. AppKit lays them out again on resize and key
/// changes, so each button's frame change puts it back.
@MainActor
private enum TrafficLights {
    private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private static var installed: Set<ObjectIdentifier> = []

    static func install(_ window: NSWindow) {
        place(window)
        guard installed.insert(ObjectIdentifier(window)).inserted else { return }
        for button in types.compactMap(window.standardWindowButton) {
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { place(window) } }
            }
        }
    }

    private static func place(_ window: NSWindow) {
        for (type, centreX) in zip(types, Theme.Metrics.trafficLightCentresX) {
            guard let button = window.standardWindowButton(type), let bar = button.superview else { continue }
            let centreY = bar.isFlipped ? Theme.Metrics.trafficLightCentreY : bar.bounds.height - Theme.Metrics.trafficLightCentreY
            let origin = NSPoint(x: centreX - button.frame.width / 2, y: centreY - button.frame.height / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
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
