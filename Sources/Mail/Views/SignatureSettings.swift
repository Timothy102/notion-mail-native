import MailCore
import SwiftUI

/// Settings → Signature (§4.9): the reply toggle, a per-alias picker and a plain editor whose
/// text is pushed to Gmail's sendAs signature.
struct SignatureSettings: View {
    @Environment(AppState.self) private var app
    @State private var identities = Live<[SendAs]>([])
    @State private var selectedEmail = ""
    @State private var text = ""
    @State private var original = ""
    @State private var signOnReplies = true
    @State private var state = SaveState.idle

    private enum SaveState: Equatable {
        case idle, saving, saved, failed(String)
        var isFailure: Bool { if case .failed = self { true } else { false } }
    }

    private var selected: SendAs? { identities.value.first { $0.email == selectedEmail } ?? identities.value.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: "Include on replies and forwards", detail: "Add your signature when you reply to or forward a message.") {
                Toggle("", isOn: $signOnReplies).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.accent)
            }
            if identities.value.count > 1 {
                SettingsRow(title: "Signature for", detail: "Each address you send from has its own signature.") {
                    Picker("", selection: $selectedEmail) {
                        ForEach(identities.value) { Text($0.email).tag($0.email) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            MailTextView(text: $text, placeholder: "Add a signature…")
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(Theme.page.opacity(0.001))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .padding(.top, 16)
            HStack(spacing: 12) {
                Text(stateText)
                    .textStyle(.small)
                    .foregroundStyle(state.isFailure ? Theme.textRed : Theme.textTertiary)
                    .lineLimit(2)
                Spacer()
                Button("Save to Gmail", action: save)
                    .buttonStyle(.primary)
                    .disabled(text == original || state == .saving)
            }
            .padding(.top, 12)
        }
        .onAppear {
            signOnReplies = app.outbox.signOnReplies
            identities.observe(app.store) { try Store.sendAs($0) }
            selectedEmail = identities.value.first?.email ?? ""
            load()
        }
        .onChange(of: selectedEmail) { load() }
        .onChange(of: signOnReplies) { app.outbox.signOnReplies = signOnReplies }
    }

    private var stateText: String {
        switch state {
        case .idle: text == original ? "" : "Unsaved changes"
        case .saving: "Saving…"
        case .saved: app.isDemo ? "Saved (demo mode, not sent to Gmail)" : "Saved to Gmail"
        case .failed(let message): "Couldn't save: \(message)"
        }
    }

    private func load() {
        original = MIME.plainText(fromHTML: selected?.signature ?? "")
        text = original
        state = .idle
    }

    private func save() {
        guard let identity = selected else { return }
        let saving = text
        state = .saving
        Task {
            do {
                try await app.outbox.updateSignature(identity, html: Outbox.signatureHTML(fromText: saving))
                original = saving
                state = .saved
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

