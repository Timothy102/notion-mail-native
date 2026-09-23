import MailCore
import SwiftUI

/// Side-peek thread reader (SPEC §4.4). Owner: thread feature. RootView sizes and positions it.
struct ThreadView: View {
    let threadId: String
    @Environment(AppState.self) private var app
    @State private var detail = Live<ThreadDetail?>(nil)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let detail = detail.value {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        subject(detail)
                        ForEach(detail.messages.filter { !$0.isDraft }) { message in
                            MessageView(message: message)
                            Hairline()
                        }
                        if let request = app.compose, !request.isFloating, detail.messages.contains(where: { request.targets($0.id) }) {
                            InlineReply(request: request).padding(16)
                        } else {
                            replyButtons.padding(.top, 24).padding(.horizontal, Theme.Metrics.readerPadding)
                        }
                    }
                    .padding(.bottom, 32)
                    .frame(maxWidth: Theme.Metrics.readerMaxWidth + 2 * Theme.Metrics.readerPadding, alignment: .leading)
                }
            } else {
                Spacer()
            }
        }
        .onAppear { let id = threadId; detail.observe(app.store) { try Store.threadDetail($0, id: id) } }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            IconButton(systemName: "chevron.right.2", help: "Close") { app.closeThread() }
            IconButton(systemName: "chevron.up", help: "Previous") { app.moveFocus(-1) }
            IconButton(systemName: "chevron.down", help: "Next") { app.moveFocus(1) }
            Spacer()
            IconButton(systemName: "envelope.badge", help: "Mark unread") { app.commands.run("thread.markUnread") }
            IconButton(systemName: "tag", help: "Label") { app.commands.run("thread.label") }
            IconButton(systemName: "archivebox", help: "Archive") { app.commands.run("thread.archive") }
            IconButton(systemName: "trash", help: "Trash") { app.commands.run("thread.trash") }
            IconButton(systemName: "ellipsis", help: "More") {}
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.peekToolbarHeight)
    }

    private func subject(_ detail: ThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.thread.subject.isEmpty ? "(no subject)" : detail.thread.subject)
                .textStyle(.threadTitle)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.labels.isEmpty {
                HStack(spacing: 8) { ForEach(detail.labels) { LabelChip(label: $0, reader: true) } }
            }
        }
        .padding(EdgeInsets(top: 12, leading: Theme.Metrics.readerPadding, bottom: 16, trailing: Theme.Metrics.readerPadding))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var replyButtons: some View {
        HStack(spacing: 8) {
            Button { app.commands.run("thread.reply") } label: { SwiftUI.Label("Reply", systemImage: "arrowshape.turn.up.left") }
            Button { app.commands.run("thread.replyAll") } label: { SwiftUI.Label("Reply all", systemImage: "arrowshape.turn.up.left.2") }
            Button { app.commands.run("thread.forward") } label: { SwiftUI.Label("Forward", systemImage: "arrowshape.turn.up.right") }
        }
        .buttonStyle(.outline(height: Theme.Metrics.buttonMedium))
    }
}

private struct MessageView: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(message.sender.displayName).textStyle(.bodyMedium).lineLimit(1)
                Text(message.sender.email).textStyle(.body).foregroundStyle(Theme.textTertiary).lineLimit(1)
                Spacer(minLength: 8)
                Text(MailDate.list(message.date)).textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
            }
            Text("To " + EmailAddress.parseList(message.to).map(\.displayName).joined(separator: ", "))
                .textStyle(.body).foregroundStyle(Theme.textTertiary).lineLimit(1)
            Text(message.bodyText)
                .textStyle(.mailBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        }
        .padding(.horizontal, Theme.Metrics.readerPadding)
        .padding(.vertical, 16)
    }
}

extension ComposeRequest {
    /// Whether this reply or forward is for `messageId`.
    func targets(_ messageId: String) -> Bool {
        switch kind {
        case .reply(let id, _), .forward(let id): id == messageId
        case .new, .draft: false
        }
    }
}
