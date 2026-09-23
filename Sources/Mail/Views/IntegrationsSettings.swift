import MailCore
import SwiftUI

/// Settings → Integrations: the Notion token (stored in the Keychain) and Google Calendar status.
struct IntegrationsSettings: View {
    @Environment(AppState.self) private var app
    @State private var token = ""
    @State private var workspace: String?
    @State private var state = NotionState.disconnected
    @FocusState private var fieldFocused: Bool

    enum NotionState: Equatable { case disconnected, verifyingSaved, connecting, connected, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: "Notion", detail: "Save threads to a database and link them to pages from ⌘K.") {
                switch state {
                case .verifyingSaved: DotsLoader()
                case .connected:
                    HStack(spacing: 8) {
                        status(workspace.map { "Connected to \($0)" } ?? "Connected")
                        if !app.isDemo { Button("Disconnect", action: disconnect).buttonStyle(.destructive) }
                    }
                default: EmptyView()
                }
            }
            if state != .connected && state != .verifyingSaved {
                tokenField.padding(.bottom, 12)
            }
            Hairline()
            SettingsRow(title: "Google Calendar", detail: "Today's and upcoming events in the sidebar, read-only.") {
                status(app.isDemo ? "Demo calendar" : app.account?.email ?? "Connected")
            }
        }
        .task {
            let client = NotionClient(demo: app.isDemo)
            guard client.isConnected else { return }
            state = .verifyingSaved
            await verify(client)
        }
    }

    private func status(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Text(text).textStyle(.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecureField("Internal integration secret (ntn_…)", text: $token)
                    .textFieldStyle(.plain)
                    .textStyle(.body)
                    .focused($fieldFocused)
                    .onSubmit(connect)
                    .padding(.horizontal, 10)
                    .frame(height: Theme.Metrics.buttonMedium)
                    .background(fieldFocused ? Theme.elevated : Theme.wash, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .strokeBorder(fieldFocused ? Theme.accent : Theme.border, lineWidth: 1))
                Button(action: connect) {
                    Text("Connect").opacity(state == .connecting ? 0 : 1)
                        .overlay { if state == .connecting { DotsLoader() } }
                }
                .buttonStyle(MailButtonStyle(kind: .primary, height: Theme.Metrics.buttonMedium))
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || state == .connecting)
            }
            Group {
                if case .failed(let message) = state {
                    Text(message).foregroundStyle(Theme.textRed)
                } else {
                    Text("Create an internal integration at notion.so/profile/integrations, then share databases and pages with it from their ••• menu → Connections.")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .textStyle(.small)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard !app.isDemo else {
            state = .failed("Demo mode doesn't connect to Notion.")
            return
        }
        state = .connecting
        Task { await verify(NotionClient(demo: false, token: value), saving: value) }
    }

    private func verify(_ client: NotionClient, saving value: String? = nil) async {
        do {
            workspace = try await client.workspaceName()
            if let value { Keychain.set(NotionClient.tokenKey, value) }
            token = ""
            state = .connected
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func disconnect() {
        Keychain.delete(NotionClient.tokenKey)
        workspace = nil
        state = .disconnected
    }
}
