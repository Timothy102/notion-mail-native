import MailCore
import SwiftUI

/// A thread as message cards (SPEC §4.4 on iPhone): the newest message open, older ones collapsed to one line,
/// long collapsed runs folded behind "Show N more", quoted history behind "•••".
struct ThreadView: View {
    let threadId: String
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var detail = Live<ThreadDetail?>(nil)
    @State private var expanded: Set<String> = []
    @State private var showAll = false
    @AppStorage(MessageBody.loadRemoteKey) private var loadRemote = true

    var body: some View {
        Group {
            if let detail = detail.value {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header(detail)
                        ForEach(items(detail)) { item in
                            switch item {
                            case .message(let m, let open):
                                if open {
                                    MessageCard(message: m, attachments: detail.attachments[m.id] ?? [], allowRemote: loadRemote) { toggle(m.id) }
                                } else {
                                    CollapsedCard(message: m) { toggle(m.id) }
                                }
                            case .more(let count):
                                Button { withAnimation(.snappy) { showAll = true } } label: {
                                    Text("Show \(count) more messages")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Theme.card, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
                .background(Theme.wash)
            } else if detail.isLoaded {
                EmptyState(title: "Thread not found", message: "It may have been deleted on another device.", art: false).background(Theme.page)
            } else {
                Theme.wash
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.wash, for: .navigationBar)
        .toolbarBackground(Theme.wash, for: .bottomBar)
        .toolbar { toolbar }
        .tint(Theme.iconPrimary)
        .onAppear {
            let id = threadId
            detail.observe(app.store) { try Store.threadDetail($0, id: id) }
            if let last = detail.value?.messages.last(where: { !$0.isDraft }) { expanded = [last.id] }
        }
    }

    // MARK: Header

    private func header(_ detail: ThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.thread.subject.isEmpty ? "(no subject)" : detail.thread.subject)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.labels.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(detail.labels) { LabelChip(label: $0, large: true) }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let thread = detail.value?.thread
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let thread {
                Button { app.actions.setStarred([threadId], !thread.isStarred) } label: {
                    Image(systemName: thread.isStarred ? "star.fill" : "star")
                }
                .tint(thread.isStarred ? Theme.swipeStar : Theme.iconPrimary)
                .accessibilityLabel(thread.isStarred ? "Unstar" : "Star")
                if thread.labelIds.contains("INBOX") {
                    Button { leave { app.actions.archive($0) } } label: { Image(systemName: "archivebox") }
                        .accessibilityLabel("Archive")
                }
                Button { leave { app.actions.trash($0) } } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Trash")
                Menu {
                    Button { leave { app.actions.setRead($0, false) } } label: { Label("Mark as Unread", systemImage: "envelope.badge") }
                    ReminderMenu(ids: [threadId], app: app)
                    if !thread.labelIds.contains("INBOX") {
                        Button { app.actions.moveToInbox([threadId]) } label: { Label("Move to Inbox", systemImage: "tray.and.arrow.down") }
                    }
                    Button(role: .destructive) { leave { app.actions.markSpam($0) } } label: { Label("Report Spam", systemImage: "exclamationmark.octagon") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if let target = app.replyTarget(threadId: threadId) {
                Button { app.compose = ComposeRequest(.reply(messageId: target.id, all: false)) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                Spacer()
                Button { app.compose = ComposeRequest(.reply(messageId: target.id, all: true)) } label: {
                    Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                }
                Spacer()
                Button { app.compose = ComposeRequest(.forward(messageId: target.id)) } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
            }
        }
    }

    /// Runs a mutation that takes the thread out of this mailbox, then goes back to the list.
    private func leave(_ mutation: ([String]) -> Void) {
        mutation([threadId])
        dismiss()
    }

    // MARK: Messages

    private enum Item: Identifiable {
        case message(Message, open: Bool)
        case more(count: Int)
        var id: String {
            switch self {
            case .message(let m, _): m.id
            case .more: "more"
            }
        }
    }

    /// Collapsed runs longer than 3 fold into "Show N more messages" after their first message.
    private func items(_ detail: ThreadDetail) -> [Item] {
        let messages = detail.messages.filter { !$0.isDraft }
        let lastId = messages.last?.id
        var out: [Item] = []
        var run: [Message] = []
        func flush() {
            if run.count > 3, !showAll {
                out += [.message(run[0], open: false), .more(count: run.count - 2), .message(run[run.count - 1], open: false)]
            } else {
                out += run.map { .message($0, open: false) }
            }
            run = []
        }
        for m in messages {
            if m.id == lastId || expanded.contains(m.id) { flush(); out.append(.message(m, open: true)) } else { run.append(m) }
        }
        flush()
        return out
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
    }
}

private struct CollapsedCard: View {
    let message: Message
    let expand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Avatar(name: message.sender.displayName, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(message.sender.displayName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MailDate.list(message.date)).font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                Text(message.snippet).font(.subheadline).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .modifier(CardBackground())
        .contentShape(Rectangle())
        .onTapGesture(perform: expand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the message")
    }
}

private struct MessageCard: View {
    let message: Message
    let attachments: [Attachment]
    let allowRemote: Bool
    let collapse: () -> Void
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            let files = attachments.filter { !$0.isInline }
            if !files.isEmpty { AttachmentList(attachments: files) }
        }
        .padding(14)
        .modifier(CardBackground())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: message.sender.displayName, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.sender.displayName).font(.body.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(MessageDate.format(message.date)).font(.footnote).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Text(recipients).font(.footnote).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Menu {
                Button { app.compose = ComposeRequest(.reply(messageId: message.id, all: false)) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Button { app.compose = ComposeRequest(.reply(messageId: message.id, all: true)) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                Button { app.compose = ComposeRequest(.forward(messageId: message.id)) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.medium)).foregroundStyle(Theme.iconSecondary)
                    .frame(width: 32, height: 28).contentShape(Rectangle())
            }
            .accessibilityLabel("Message actions")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: collapse)
    }

    /// "to me, Alex" (cc included).
    private var recipients: String {
        let people = EmailAddress.parseList(message.to) + EmailAddress.parseList(message.cc)
        let me = app.account?.email ?? ""
        let names = people.map { $0.email.caseInsensitiveCompare(me) == .orderedSame ? "me" : $0.displayName }
        return names.isEmpty ? "to undisclosed recipients" : "to " + names.joined(separator: ", ")
    }

    @ViewBuilder
    private var content: some View {
        let mailto: (EmailAddress) -> Void = { app.compose = ComposeRequest(.new(to: [$0])) }
        if let html = message.bodyHTML, !html.isEmpty {
            let parts = Quote.split(html: app.isDemo ? Fixtures.offlineImages(html) : html)
            let remote = allowRemote && MailHTML.hasRemoteContent(html)
            MessageBody(html: parts.new, attachments: attachments, allowRemote: remote, gmail: app.gmail, onMailto: mailto)
            if let quoted = parts.quoted {
                QuotedHistory { MessageBody(html: quoted, attachments: attachments, allowRemote: remote, gmail: app.gmail, onMailto: mailto) }
            }
        } else {
            let parts = Quote.split(text: message.bodyText)
            Text(parts.new.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let quoted = parts.quoted {
                QuotedHistory { MessageBody(html: Quote.html(fromText: quoted)) }
            }
        }
    }
}

/// Attachment tiles; tapping one downloads it if needed and opens the share sheet / Quick Look.
private struct AttachmentList: View {
    let attachments: [Attachment]
    @Environment(AppState.self) private var app
    @State private var opening: String?
    @State private var shared: URL?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(attachments) { a in
                Button { open(a) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(a)).font(.title3).foregroundStyle(Theme.iconSecondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.filename.isEmpty ? "Untitled" : a.filename).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                .lineLimit(1).truncationMode(.middle)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file))
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        if opening == a.id { ProgressView() }
                    }
                    .padding(10)
                    .background(Theme.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $shared) { ShareSheet(url: $0) }
    }

    private func icon(_ a: Attachment) -> String {
        let type = a.mimeType.lowercased()
        if type.hasPrefix("image/") { return "photo" }
        if type == "application/pdf" { return "doc.richtext" }
        if type.hasPrefix("text/calendar") { return "calendar" }
        if type.contains("zip") { return "doc.zipper" }
        return "doc"
    }

    private func open(_ a: Attachment) {
        guard opening == nil else { return }
        opening = a.id
        let gmail = app.gmail
        Task {
            defer { opening = nil }
            do {
                let data: Data
                if let d = a.data { data = d }
                else if let gmail, let remoteId = a.gmailAttachmentId { data = try await gmail.attachment(messageId: a.messageId, id: remoteId) }
                else { throw CocoaError(.fileReadNoSuchFile) }
                let dir = FileManager.default.temporaryDirectory.appending(path: "Attachments/\(a.messageId)", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appending(path: (a.filename.isEmpty ? "attachment" : a.filename).replacingOccurrences(of: "/", with: "-"))
                try data.write(to: url, options: .atomic)
                shared = url
            } catch {
                app.show(Toast("Couldn't open \(a.filename): \(error.localizedDescription)"))
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum MessageDate {
    /// "8:12 AM" today, "Sep 22, 8:12 AM" this year, "Dec 25, 2024" before (as on the Mac).
    static func format(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let text = if cal.isDate(date, inSameDayAs: now) {
            date.formatted(date: .omitted, time: .shortened)
        } else if cal.isDate(date, equalTo: now, toGranularity: .year) {
            date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        } else {
            date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return text.replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
