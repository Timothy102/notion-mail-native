import AppKit
import MailCore
import SwiftUI
import UniformTypeIdentifiers

/// Side-peek thread reader (SPEC §4.4). Owner: thread feature. RootView sizes and positions it.
struct ThreadView: View {
    let threadId: String
    @Environment(AppState.self) private var app
    @State private var detail = Live<ThreadDetail?>(nil)
    @State private var expanded: Set<String> = []
    @State private var showAllCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let detail = detail.value {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            subject(detail)
                            messages(detail)
                            bottom(detail)
                        }
                        .padding(.bottom, Theme.Metrics.readerBottom)
                        .frame(maxWidth: Theme.Metrics.readerMaxWidth + 2 * Theme.Metrics.readerPadding, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: app.selectedMessageId) { _, id in
                        if let id { withAnimation(Theme.Motion.standard) { proxy.scrollTo(id, anchor: .top) } }
                    }
                }
            } else if detail.isLoaded {
                EmptyState(title: "Thread not found", message: "It may have been deleted on another device.", art: false)
            } else {
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if app.isLabelPickerOpen {
                LabelPickerLayer(alignment: .topTrailing).padding(.top, Theme.Metrics.peekToolbarHeight - 4)
            }
        }
        .onAppear {
            let id = threadId
            detail.observe(app.store) { try Store.threadDetail($0, id: id) }
            if let last = detail.value?.messages.last(where: { !$0.isDraft }) { expanded = [last.id] }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let ids = app.visibleThreadIds
        let index = ids.firstIndex(of: threadId)
        return HStack(spacing: 4) {
            IconButton(systemName: "chevron.right.2", help: "Close  Esc") { app.closeThread() }
            IconButton(systemName: "chevron.up", help: "Previous  K") { app.moveFocus(-1) }
                .disabled(index.map { $0 == 0 } ?? true)
            IconButton(systemName: "chevron.down", help: "Next  J") { app.moveFocus(1) }
                .disabled(index.map { $0 == ids.count - 1 } ?? true)
            Spacer()
            RemindMenu(ids: [threadId])
            IconButton(systemName: "app.badge", help: "Mark as unread  ⇧U") { app.commands.run("thread.markUnread") }
            IconButton(systemName: "tag", help: "Label  L") { app.commands.run("thread.label") }
            IconButton(systemName: "archivebox", help: "Archive  E") { app.commands.run("thread.archive") }
                .disabled(!(detail.value?.thread.labelIds.contains("INBOX") ?? false))
            IconButton(systemName: "trash", help: "Trash  #") { app.commands.run("thread.trash") }
            MenuButton(systemName: "ellipsis", help: "More") {
                let starred = detail.value?.thread.isStarred ?? false
                Button(starred ? "Unstar" : "Star") { app.commands.run("thread.star") }
                Button("Forward") { app.commands.run("thread.forward") }
                Divider()
                if app.mailbox != .inbox { Button("Move to Inbox") { app.commands.run("thread.moveToInbox") } }
                Button("Report spam") { app.commands.run("thread.spam") }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.peekToolbarHeight)
    }

    // MARK: Subject

    private func subject(_ detail: ThreadDetail) -> some View {
        let files = detail.attachments.values.joined().filter { !$0.isInline }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(detail.thread.subject.isEmpty ? "(no subject)" : detail.thread.subject)
                .textStyle(.threadTitle)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                if files > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip").font(.system(size: 12)).foregroundStyle(Theme.iconSecondary)
                        Text(files == 1 ? "1 attachment" : "\(files) attachments").textStyle(.body).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(height: Theme.Metrics.chipHeightReader)
                }
                ForEach(detail.labels) { label in
                    RemovableChip(label: label) { app.actions.setLabels([threadId], remove: [label.id]) }
                }
                Button { app.commands.run("thread.label") } label: {
                    Text("Add label").textStyle(.body).foregroundStyle(Theme.placeholder)
                        .padding(.horizontal, 4)
                        .frame(height: Theme.Metrics.chipHeightReader)
                        .hoverFill(radius: Theme.Metrics.chipRadius)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: Theme.Metrics.subjectTop, leading: Theme.Metrics.readerPadding, bottom: Theme.Metrics.subjectBottom, trailing: Theme.Metrics.readerPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: Messages

    private enum Item: Identifiable {
        case message(Message, expanded: Bool)
        case more(count: Int)
        var id: String {
            switch self {
            case .message(let m, _): m.id
            case .more: "more"
            }
        }
    }

    /// Collapsed runs longer than 4 fold into "Show N more messages" between their first and last.
    private func items(_ detail: ThreadDetail) -> [Item] {
        let messages = detail.messages.filter { !$0.isDraft }
        let lastId = messages.last?.id
        let isOpen = { (m: Message) in m.id == lastId || m.id == app.selectedMessageId || expanded.contains(m.id) }
        var out: [Item] = []
        var run: [Message] = []
        func flush() {
            if run.count > 4, !showAllCollapsed {
                out.append(.message(run[0], expanded: false))
                out.append(.more(count: run.count - 2))
                out.append(.message(run[run.count - 1], expanded: false))
            } else {
                out += run.map { .message($0, expanded: false) }
            }
            run = []
        }
        for m in messages {
            if isOpen(m) { flush(); out.append(.message(m, expanded: true)) } else { run.append(m) }
        }
        flush()
        return out
    }

    private func messages(_ detail: ThreadDetail) -> some View {
        let items = items(detail)
        return ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            switch item {
            case .message(let message, let isExpanded):
                Group {
                    if isExpanded {
                        MessageView(message: message, attachments: detail.attachments[message.id] ?? [],
                                    selfEmail: app.account?.email) { toggle(message.id) }
                    } else {
                        CollapsedMessage(message: message) { toggle(message.id) }
                    }
                }
                .overlay(alignment: .leading) {
                    if app.selectedMessageId == message.id {
                        Theme.accent.frame(width: Theme.Metrics.selectedMessageBar)
                    }
                }
                .id(message.id)
                if i < items.count - 1, case .message = items[i + 1] { Hairline() }
            case .more(let count):
                ZStack {
                    Hairline()
                    Button { withAnimation(Theme.Motion.standard) { showAllCollapsed = true } } label: {
                        Text("Show \(count) more messages")
                            .textStyle(.smallMedium)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Theme.elevated, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: Theme.Metrics.showMoreHeight)
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(Theme.Motion.standard) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    @ViewBuilder
    private func bottom(_ detail: ThreadDetail) -> some View {
        if let request = app.compose, !request.isFloating, detail.messages.contains(where: { request.targets($0.id) }) {
            InlineReply(request: request).padding(16)
        } else {
            HStack(spacing: Theme.Metrics.replyBarSpacing) {
                Button { app.commands.run("thread.reply") } label: { ButtonLabel("Reply", "arrowshape.turn.up.left") }
                Button { app.commands.run("thread.replyAll") } label: { ButtonLabel("Reply all", "arrowshape.turn.up.left.2") }
                Button { app.commands.run("thread.forward") } label: { ButtonLabel("Forward", "arrowshape.turn.up.right") }
            }
            .buttonStyle(.outline(height: Theme.Metrics.buttonMedium))
            .padding(.top, Theme.Metrics.replyBarTop)
            .padding(.horizontal, Theme.Metrics.readerPadding)
        }
    }
}

private struct ButtonLabel: View {
    let title: String
    let icon: String
    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.iconPrimary).frame(width: 16, height: 16)
            Text(title)
        }
    }
}

/// Reader chip with a remove "×" on hover (§5.4).
private struct RemovableChip: View {
    let label: MailLabel
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = LabelColor(named: label.color)
        HStack(spacing: 4) {
            Text(label.name).textStyle(.body).foregroundStyle(color.text).lineLimit(1)
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(color.text.opacity(0.5))
                        .frame(width: 12, height: 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove label")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Theme.Metrics.chipHeightReader)
        .background(color.fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.chipRadius, style: .continuous))
        .onLiveHover { hovering = $0 }
    }
}

/// One-line older message: sender, snippet, date (§4.4).
private struct CollapsedMessage: View {
    let message: Message
    let expand: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(message.sender.displayName).textStyle(.body).foregroundStyle(Theme.textPrimary).lineLimit(1).fixedSize()
            Text(message.snippet).textStyle(.body).foregroundStyle(Theme.textTertiary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .padding(.trailing, 16)
            Text(MessageDate.format(message.date)).textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
        }
        .padding(.horizontal, Theme.Metrics.readerPadding)
        .frame(height: Theme.Metrics.collapsedMessageHeight)
        .contentShape(Rectangle())
        .hoverFill(radius: 0)
        .onTapGesture(perform: expand)
    }
}

private struct MessageView: View {
    let message: Message
    let attachments: [Attachment]
    let selfEmail: String?
    let collapse: () -> Void
    @Environment(AppState.self) private var app
    @State private var showImagesOnce = false
    @State private var allowedSender = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content(html: message.bodyHTML)
            ForEach(attachments.filter { $0.mimeType.lowercased() == "text/calendar" }) { invite in
                InviteAttachment(attachment: invite)
                    .padding(.horizontal, Theme.Metrics.readerPadding)
                    .padding(.bottom, 16)
            }
            let files = attachments.filter { !$0.isInline && !Self.rendersAsInvite($0) }
            if !files.isEmpty {
                AttachmentList(attachments: files).padding(.horizontal, Theme.Metrics.readerPadding).padding(.bottom, 24)
            }
        }
        .onAppear { allowedSender = (try? app.store.get(Self.allowKey(message.sender.email))) == "1" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(message.sender.displayName).textStyle(.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1).layoutPriority(1)
                if message.sender.name != nil {
                    Text(message.sender.email).textStyle(.body).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    IconButton(systemName: "arrowshape.turn.up.left", help: "Reply  R") { app.compose = ComposeRequest(.reply(messageId: message.id, all: false)) }
                    IconButton(systemName: "arrowshape.turn.up.right", help: "Forward  F") { app.compose = ComposeRequest(.forward(messageId: message.id)) }
                }
                .frame(height: 20)
                Text(MessageDate.format(message.date)).textStyle(.body).foregroundStyle(Theme.textTertiary).fixedSize()
            }
            Text(recipients).textStyle(.body).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .padding(.top, Theme.Metrics.messageHeaderTop)
        .padding(.horizontal, Theme.Metrics.readerPadding)
        .contentShape(Rectangle())
        .onTapGesture(perform: collapse)
    }

    /// "To me, Alex" (cc included).
    private var recipients: String {
        let people = EmailAddress.parseList(message.to) + EmailAddress.parseList(message.cc)
        let names = people.map { $0.email.caseInsensitiveCompare(selfEmail ?? "") == .orderedSame ? "me" : $0.displayName }
        return names.isEmpty ? "To undisclosed recipients" : "To " + names.joined(separator: ", ")
    }

    @ViewBuilder
    private func content(html: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let html, !html.isEmpty {
                let remote = MailHTML.hasRemoteContent(html)
                let allow = showImagesOnce || allowedSender
                if remote, !allow { imagesBanner }
                MessageBody(html: html, attachments: attachments, allowRemote: remote && allow) { to in
                    app.compose = ComposeRequest(.new(to: [to]))
                }
            } else {
                Text(message.bodyText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .textStyle(.mailBody)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Metrics.readerPadding)
        .padding(.vertical, Theme.Metrics.messageBodyInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imagesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").font(.system(size: 13)).foregroundStyle(Theme.iconSecondary)
            Text("Remote images are hidden.")
                .textStyle(.body).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Show images") { showImagesOnce = true }
                .buttonStyle(.outline)
            Button("Always from sender") {
                try? app.store.set(Self.allowKey(message.sender.email), "1")
                allowedSender = true
            }
            .buttonStyle(.outline)
            .help("Always load images from \(message.sender.email)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
    }

    /// Invites whose bytes are local and parse show as an InviteCard instead of a file card.
    static func rendersAsInvite(_ a: Attachment) -> Bool {
        a.mimeType.lowercased() == "text/calendar" && a.data.map { !ICS.events($0).isEmpty } == true
    }

    static func allowKey(_ email: String) -> String { "images.allow.\(email.lowercased())" }
}

/// An .ics attachment as an InviteCard, downloading the bytes first when they live on Gmail.
private struct InviteAttachment: View {
    let attachment: Attachment
    @Environment(AppState.self) private var app
    @State private var data: Data?

    var body: some View {
        Group {
            if let data = data ?? attachment.data { InviteCard(ics: data) }
        }
        .task(id: attachment.id) {
            guard attachment.data == nil, let gmail = app.gmail, let remoteId = attachment.gmailAttachmentId else { return }
            data = try? await gmail.attachment(messageId: attachment.messageId, id: remoteId)
        }
    }
}

/// Attachment cards: type icon, name, size. Click opens the file with its default app.
private struct AttachmentList: View {
    let attachments: [Attachment]
    @Environment(AppState.self) private var app
    @State private var opening: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(attachments) { a in
                Button { open(a) } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: icon(a)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(a.filename.isEmpty ? "Untitled" : a.filename)
                                .textStyle(.body).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file))
                                .textStyle(.small).foregroundStyle(Theme.textTertiary)
                        }
                        if opening == a.id { DotsLoader() }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 260, alignment: .leading)
                    .frame(height: 48)
                    .hoverFill(radius: Theme.Metrics.radiusMenu)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(a.filename)")
            }
        }
    }

    private func icon(_ a: Attachment) -> NSImage {
        NSWorkspace.shared.icon(for: UTType(mimeType: a.mimeType) ?? UTType(filenameExtension: (a.filename as NSString).pathExtension) ?? .data)
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
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MailAttachments/\(a.messageId)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = (a.filename.isEmpty ? "attachment" : a.filename).replacingOccurrences(of: "/", with: "-")
                let url = dir.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                NSWorkspace.shared.open(url)
            } catch {
                app.show(Toast("Couldn't open \(a.filename): \(error.localizedDescription)"))
            }
        }
    }
}

enum MessageDate {
    /// "8:12 AM" today, "Sep 22, 8:12 AM" this year, "Dec 25, 2024" before.
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

extension ComposeRequest {
    /// Whether this reply or forward is for `messageId`.
    func targets(_ messageId: String) -> Bool {
        switch kind {
        case .reply(let id, _), .forward(let id): id == messageId
        case .new, .draft: false
        }
    }
}
