import MailCore
import SwiftUI

/// Floating composer for new mail and drafts (SPEC §4.5), and `InlineReply` for replies and
/// forwards inside the thread (§5.6). Owner: compose/signatures feature.
struct Composer: View {
    let request: ComposeRequest
    @Environment(AppState.self) private var app
    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(systemName: "minus", help: "Minimize") {}
                IconButton(systemName: "xmark", help: "Close") { app.compose = nil }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            field("From") { Text(app.account?.name ?? "").textStyle(.body) }
            field("To") { TextField("Add recipient", text: $to).textFieldStyle(.plain).textStyle(.body) }
            field("Subject") { TextField("Subject", text: $subject).textFieldStyle(.plain).textStyle(.body) }
            Hairline()
            TextEditor(text: $text)
                .font(TextStyle.mailBody.font)
                .scrollContentBackground(.hidden)
                .padding(16)
            HStack(spacing: 12) {
                Button("Send") { app.compose = nil }
                    .buttonStyle(.primary)
                    .frame(width: Theme.Metrics.sendButtonWidth, alignment: .leading)
                Spacer()
                IconButton(systemName: "paperclip", help: "Attach") {}
                IconButton(systemName: "trash", help: "Discard") { app.compose = nil }
            }
            .padding(16)
            .frame(height: Theme.Metrics.composerFooterHeight)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).textStyle(.body).foregroundStyle(Theme.textTertiary).frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.Metrics.composerFieldHeight)
    }
}

/// Inline reply card embedded by ThreadView under the last message.
struct InlineReply: View {
    let request: ComposeRequest
    @Environment(AppState.self) private var app
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: $text)
                .font(TextStyle.mailBody.font)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(16)
            HStack {
                Button("Send") { app.compose = nil }.buttonStyle(.primary)
                Spacer()
                IconButton(systemName: "trash", help: "Discard") { app.compose = nil }
            }
            .padding(16)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .elevation(.l2, radius: Theme.Metrics.radiusMenu)
    }
}
