import SwiftUI

@main
struct MailApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup("Mail") { RootView().frame(minWidth: Theme.Metrics.windowMin.width, minHeight: Theme.Metrics.windowMin.height) }
    }
}

struct RootView: View {
    @State private var email: String?
    @State private var error: String?

    var body: some View {
        VStack {
            if let email {
                Text(email).textStyle(.bodyMedium)
            } else {
                Button("Sign in with Google") { Task { await load() } }
            }
            if let error { Text(error).textStyle(.small).foregroundStyle(Theme.textRed).textSelection(.enabled) }
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
        .task { if await Auth.shared.isSignedIn { await load() } }
    }

    private func load() async {
        do { email = try await Gmail.profile().emailAddress; error = nil }
        catch { self.error = "\(error)" }
    }
}
