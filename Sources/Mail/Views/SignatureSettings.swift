import MailCore
import SwiftUI

/// Settings → Signature (§4.9): the reply toggle, a per-alias picker and a plain editor. "Save"
/// keeps the signature on this Mac; only "Save to Gmail" changes the sendAs signature in Gmail.
struct SignatureSettings: View {
    @Environment(AppState.self) private var app
    @State private var identities = Live<[SendAs]>([])
    @State private var selectedEmail = ""
    @State private var text = ""
    @State private var original = ""
    @State private var signOnReplies = true
    @State private var state = SaveState.idle

    private enum SaveState: Equatable {
        case idle, saved, pushing, pushed, failed(String)
        var isFailure: Bool { if case .failed = self { true } else { false } }
    }

    private var selected: SendAs? { identities.value.first { $0.email == selectedEmail } ?? identities.value.first }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var gmailText: String { MIME.plainText(fromHTML: selected?.signature ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: "Include on replies and forwards", detail: "Add your signature when you reply to or forward a message.") {
                Toggle("", isOn: $signOnReplies).toggleStyle(SettingsSwitch()).labelsHidden()
            }
            if identities.value.count > 1 {
                SettingsRow(title: "Signature for", detail: "Each address you send from has its own signature.") {
                    SettingsPopUp(selection: $selectedEmail, options: identities.value.map(\.email)) { $0 }
                }
            }
            MailTextView(text: $text, placeholder: "Add a signature…")
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(Theme.page.opacity(0.001))
                .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                .padding(.top, 16)
            HStack(spacing: 8) {
                Text(stateText)
                    .textStyle(.small)
                    .foregroundStyle(state.isFailure ? Theme.textRed : Theme.textTertiary)
                    .lineLimit(2)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.outline)
                    .disabled(trimmed == original)
                Button("Save to Gmail", action: pushToGmail)
                    .buttonStyle(.primary)
                    .disabled(trimmed == gmailText || state == .pushing || selected == nil)
            }
            .padding(.top, 12)
            Text("Mail signs new messages and replies with this text. Your Gmail signature only changes when you choose Save to Gmail.")
                .textStyle(.small)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
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
        case .idle: trimmed == original ? "" : "Unsaved changes"
        case .saved: trimmed == original ? "Saved on this Mac" : "Unsaved changes"
        case .pushing: "Saving to Gmail…"
        case .pushed: app.isDemo ? "Saved (demo mode, not sent to Gmail)" : "Saved to Gmail"
        case .failed(let message): "Couldn't save to Gmail: \(message)"
        }
    }

    private func load() {
        original = (try? app.store.db.read { try Signature.text(for: selected, db: $0) }) ?? ""
        text = original
        state = .idle
    }

    private func save() {
        guard let identity = selected else { return }
        do {
            try app.store.saveLocalSignature(trimmed, for: identity)
            original = trimmed
            state = .saved
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func pushToGmail() {
        guard let identity = selected else { return }
        let saving = trimmed
        state = .pushing
        Task {
            do {
                try await app.outbox.updateSignature(identity, text: saving)
                original = saving
                state = .pushed
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
