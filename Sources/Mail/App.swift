import SwiftUI

@main
struct MailApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup("Mail") { RootView().frame(minWidth: 900, minHeight: 600) }
    }
}

struct RootView: View {
    @State private var email: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: Theme.gutter) {
            if let email {
                Text(email).font(Theme.listSender)
            } else {
                Button("Sign in with Google") { Task { await load() } }
            }
            if let error { Text(error).font(Theme.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task { if await Auth.shared.isSignedIn { await load() } }
    }

    private func load() async {
        do { email = try await Gmail.profile().emailAddress; error = nil }
        catch { self.error = "\(error)" }
    }
}
