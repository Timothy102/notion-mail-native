import AppKit
import MailCore
import SwiftUI
import UniformTypeIdentifiers

/// State behind one open composer: the draft, autosave, send and discard.
@MainActor @Observable
final class ComposeModel {
    enum SaveStatus: Equatable { case idle, saving, saved, failed }
    enum Field: Hashable { case to, cc, bcc, subject }

    var draft = ComposeDraft(mode: .new, from: EmailAddress(name: nil, email: ""))
    private(set) var status = SaveStatus.idle
    private(set) var identities: [SendAs] = []
    private(set) var contacts: [Contact] = []
    var showsCc = false
    var showsBcc = false
    var showsCcBcc: Bool { showsCc || showsBcc }
    var showsQuoted = false
    var isMinimized = false
    private(set) var requestId: UUID?

    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private var lastSaved: ComposeDraft?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var finished = false
    static let autosaveDelay = Duration.seconds(1.5)
    static let attachmentLimit = 25 * 1024 * 1024

    func load(_ request: ComposeRequest, app: AppState) {
        guard request.id != requestId else { return }
        flush()
        self.app = app
        requestId = request.id
        finished = false
        isMinimized = false
        showsQuoted = false
        let fallback = EmailAddress(name: app.account?.name, email: app.account?.email ?? "")
        let signOnReplies = app.outbox.signOnReplies
        let restored = app.outbox.restore.removeValue(forKey: request.id)
        let (made, identities) = (try? app.store.db.read { db in
            (try restored ?? ComposeDraft.make(request.kind, db: db, fallbackFrom: fallback, signOnReplies: signOnReplies), try Store.sendAs(db))
        }) ?? (ComposeDraft(mode: .new, from: fallback), [])
        draft = made
        self.identities = identities
        let selfEmails = Set(identities.map { $0.email.lowercased() } + [fallback.email.lowercased()])
        contacts = (try? app.store.db.read { try Store.contacts($0, selfEmails: selfEmails) }) ?? []
        lastSaved = made.draftId == nil ? nil : made
        status = made.draftId == nil ? .idle : .saved
        showsCc = !made.cc.isEmpty
        showsBcc = !made.bcc.isEmpty
    }

    var identity: SendAs? { identities.first { $0.email.lowercased() == draft.from.email.lowercased() } }

    func choose(_ identity: SendAs) {
        draft.switchIdentity(to: identity, signature: (try? app?.store.db.read { try Signature.text(for: identity, db: $0) }) ?? "")
    }

    func switchMode(_ mode: ComposeDraft.Mode) {
        guard let app else { return }
        try? app.store.db.read { try draft.switchMode(mode, db: $0) }
    }

    /// Called on every edit: saves 1.5 s after the last change.
    func edited() {
        guard !finished, draft != lastSaved, !(draft.isPristine && draft.draftId == nil) else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard let app, !finished else { return }
        let snapshot = draft
        status = .saving
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do {
                let saved = try await app.outbox.saveDraft(snapshot)
                guard let self else { return }
                draft.draftId = saved.draftId
                draft.draftMessageId = saved.draftMessageId
                draft.threadId = saved.threadId
                for a in saved.attachments where a.data != nil {
                    if let i = draft.attachments.firstIndex(where: { $0.id == a.id && $0.data == nil }) { draft.attachments[i].data = a.data }
                }
                lastSaved = saved
                status = .saved
            } catch {
                self?.status = .failed
            }
        }
    }

    /// Saves pending edits now (closing, switching requests).
    func flush() {
        guard !finished, requestId != nil else { return }
        debounce?.cancel()
        if draft != lastSaved, !(draft.isPristine && draft.draftId == nil) { save() }
        finished = true
    }

    func send(archiveThread: Bool = false) {
        guard let app else { return }
        guard !draft.recipients.isEmpty else {
            app.show(Toast("Add at least one recipient"))
            return
        }
        finished = true
        debounce?.cancel()
        let reopen = reopenKind
        Task { [weak self] in
            await self?.saveTask?.value
            guard let self else { return }
            app.outbox.send(draft, reopen: reopen, archiveThread: archiveThread)
        }
        app.compose = nil
    }

    func discard() {
        guard let app else { return }
        finished = true
        debounce?.cancel()
        Task { [weak self] in
            await self?.saveTask?.value
            guard let self else { return }
            await app.outbox.discard(draft)
        }
        app.compose = nil
        if draft.draftId != nil || !draft.isPristine { app.show(Toast("Draft discarded")) }
    }

    func close() {
        flush()
        app?.compose = nil
    }

    private var reopenKind: ComposeRequest.Kind {
        switch (draft.mode, draft.sourceMessageId) {
        case (.reply, let id?): .reply(messageId: id, all: false)
        case (.replyAll, let id?): .reply(messageId: id, all: true)
        case (.forward, let id?): .forward(messageId: id)
        default: .new(to: [])
        }
    }

    // MARK: Attachments

    func attach(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let total = draft.attachments.reduce(0) { $0 + $1.size } + data.count
            guard total <= Self.attachmentLimit else {
                app?.show(Toast("Attachments are limited to 25 MB"))
                return
            }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            draft.attachments.append(ComposeAttachment(filename: url.lastPathComponent, mimeType: type, data: data))
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.attach(urls) }
        }
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor [weak self] in self?.attach([url]) }
            }
        }
        return !files.isEmpty
    }

    var statusText: String {
        switch status {
        case .idle: ""
        case .saving: "Saving…"
        case .saved: "Draft saved"
        case .failed: "Couldn't save draft"
        }
    }
}

// MARK: - Floating composer (§4.5)

/// Floating composer for new mail and drafts. RootView sizes and places it.
struct Composer: View {
    let request: ComposeRequest
    @Environment(AppState.self) private var app
    @State private var model = ComposeModel()
    @State private var isDropTarget = false
    @FocusState private var focus: ComposeModel.Field?

    var body: some View {
        Group {
            if model.isMinimized {
                minimized
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                panel
            }
        }
        .onChange(of: request.id, initial: true) {
            model.load(request, app: app)
            if model.draft.to.isEmpty { focus = .to }
        }
        .onChange(of: model.draft) { model.edited() }
        .composeCommands(model)
    }

    private var panel: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    FromPicker(model: model)
                    Spacer(minLength: 12)
                    HStack(spacing: 4) {
                        IconButton(systemName: "minus", help: "Minimize") { withAnimation(Theme.Motion.standard) { model.isMinimized = true } }
                        IconButton(systemName: "xmark", help: "Close") { model.close() }
                    }
                    .padding(.trailing, -4)
                }
                .frame(height: Theme.Metrics.composerFieldHeight)
                HStack(alignment: .top, spacing: 12) {
                    RecipientField(addresses: $model.draft.to, contacts: model.contacts, placeholder: "Add recipient", focus: $focus, field: .to)
                    if !(model.showsCc && model.showsBcc) {
                        CcBccButton(title: model.showsCc ? "Bcc" : "Cc/Bcc") {
                            focus = model.showsCc ? .bcc : .cc
                            model.showsCc = true
                            model.showsBcc = true
                        }
                    }
                }
                .zIndex(3)
                if model.showsCc {
                    RecipientField(addresses: $model.draft.cc, contacts: model.contacts, prefix: "Cc", focus: $focus, field: .cc).zIndex(2)
                }
                if model.showsBcc {
                    RecipientField(addresses: $model.draft.bcc, contacts: model.contacts, prefix: "Bcc", focus: $focus, field: .bcc).zIndex(1)
                }
                TextField("", text: $model.draft.subject)
                    .textFieldStyle(.plain)
                    .textStyle(.body)
                    .focused($focus, equals: .subject)
                    .placeholder("Subject", showing: model.draft.subject.isEmpty)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.composerFieldHeight, alignment: .leading)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .zIndex(1)
            Hairline()
            ScrollView {
                ComposeBody(model: model, placeholder: "Write, or press '/' for commands…", focusOnAppear: false)
                    .padding(16)
            }
            .scrollIndicators(.automatic)
            AttachmentStrip(model: model).padding(.horizontal, 16)
            ComposeFooter(model: model)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .overlay { DropHighlight(isActive: isDropTarget, radius: Theme.Metrics.radiusLarge) }
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { model.drop($0) }
    }

    private var minimized: some View {
        HStack(spacing: 4) {
            Text(model.draft.subject.isEmpty ? "New message" : model.draft.subject)
                .textStyle(.bodyMedium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Expand") { withAnimation(Theme.Motion.standard) { model.isMinimized = false } }
            IconButton(systemName: "xmark", help: "Close") { model.close() }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(width: 300, height: 48)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
        .elevation(.l4, radius: Theme.Metrics.radiusLarge)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(Theme.Motion.standard) { model.isMinimized = false } }
    }
}

// MARK: - Inline reply card (§5.6)

/// Reply, reply-all or forward card at the bottom of the thread.
struct InlineReply: View {
    let request: ComposeRequest
    @Environment(AppState.self) private var app
    @State private var model = ComposeModel()
    @State private var isDropTarget = false
    @FocusState private var focus: ComposeModel.Field?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ReplyModeMenu(model: model)
                RecipientField(addresses: $model.draft.to, contacts: model.contacts, placeholder: "Add recipient", focus: $focus, field: .to)
                HStack(spacing: 4) {
                    if !(model.showsCc && model.showsBcc) {
                        CcBccButton(title: model.showsCc ? "Bcc" : "Cc/Bcc") {
                            focus = model.showsCc ? .bcc : .cc
                            model.showsCc = true
                            model.showsBcc = true
                        }
                    }
                    MoreMenu(model: model)
                }
                .frame(height: Theme.Metrics.composerFieldHeight)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .zIndex(3)
            Group {
                if model.showsCc {
                    RecipientField(addresses: $model.draft.cc, contacts: model.contacts, prefix: "Cc", prefixAlignment: .center, focus: $focus, field: .cc).zIndex(2)
                }
                if model.showsBcc {
                    RecipientField(addresses: $model.draft.bcc, contacts: model.contacts, prefix: "Bcc", prefixAlignment: .center, focus: $focus, field: .bcc).zIndex(1)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .zIndex(2)
            if model.showsCcBcc { Spacer().frame(height: 4) }
            Hairline()
            ComposeBody(model: model, placeholder: model.draft.mode == .forward ? "Add a note…" : "Write a reply…",
                        focusOnAppear: model.draft.mode != .forward)
                .frame(minHeight: 96, alignment: .top)
                .padding(16)
            AttachmentStrip(model: model).padding(.horizontal, 16)
            ComposeFooter(model: model)
        }
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .overlay { DropHighlight(isActive: isDropTarget, radius: Theme.Metrics.radiusMenu) }
        .elevation(.l2, radius: Theme.Metrics.radiusMenu)
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { model.drop($0) }
        .onChange(of: request.id, initial: true) {
            model.load(request, app: app)
            if model.draft.mode == .forward { focus = .to }
        }
        .onChange(of: model.draft) { model.edited() }
        .composeCommands(model)
    }
}

private extension View {
    /// ⌘↵ sends from this composer while it is on screen; leaving saves the draft.
    func composeCommands(_ model: ComposeModel) -> some View {
        modifier(ComposeCommands(model: model))
    }
}

private struct ComposeCommands: ViewModifier {
    let model: ComposeModel
    @Environment(AppState.self) private var app

    func body(content: Content) -> some View {
        content
            .onAppear { app.outbox.sendAction = (ObjectIdentifier(model), { [weak model] in model?.send() }) }
            .onDisappear {
                model.flush()
                if app.outbox.sendAction?.owner == ObjectIdentifier(model) { app.outbox.sendAction = nil }
            }
    }
}

// MARK: - Pieces

private struct FromPicker: View {
    let model: ComposeModel

    var body: some View {
        let label = HStack(spacing: 6) {
            Text(model.draft.from.name ?? model.draft.from.email).textStyle(.body).foregroundStyle(Theme.textPrimary)
            if model.draft.from.name != nil {
                Text(model.draft.from.email).textStyle(.body).foregroundStyle(Theme.textTertiary)
            }
            if model.identities.count > 1 {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.iconSecondary)
            }
        }
        .lineLimit(1)
        if model.identities.count > 1 {
            Menu {
                ForEach(model.identities) { identity in
                    Button { model.choose(identity) } label: {
                        if identity.email == model.draft.from.email { SwiftUI.Label(identity.address.formatted, systemImage: "checkmark") }
                        else { Text(identity.address.formatted) }
                    }
                }
            } label: { label }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Send from")
        } else {
            label
        }
    }
}

private struct CcBccButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).textStyle(.body).foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
                .frame(height: 24)
                .hoverFill(radius: Theme.Metrics.radiusSmall)
        }
        .buttonStyle(.plain)
        .frame(height: Theme.Metrics.composerFieldHeight)
    }
}

private struct ReplyModeMenu: View {
    let model: ComposeModel

    var body: some View {
        Menu {
            Button { model.switchMode(.reply) } label: { SwiftUI.Label("Reply", systemImage: "arrowshape.turn.up.left") }
            Button { model.switchMode(.replyAll) } label: { SwiftUI.Label("Reply all", systemImage: "arrowshape.turn.up.left.2") }
            Button { model.switchMode(.forward) } label: { SwiftUI.Label("Forward", systemImage: "arrowshape.turn.up.right") }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.iconSecondary)
                .frame(width: Theme.Metrics.iconButton, height: Theme.Metrics.iconButton)
                .hoverFill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.top, 2)
        .help("Reply type")
    }

    private var icon: String {
        switch model.draft.mode {
        case .replyAll: "arrowshape.turn.up.left.2"
        case .forward: "arrowshape.turn.up.right"
        default: "arrowshape.turn.up.left"
        }
    }
}

private struct MoreMenu: View {
    let model: ComposeModel

    var body: some View {
        Menu {
            if model.draft.quoted != nil {
                Button(model.showsQuoted ? "Hide quoted text" : "Show quoted text") { model.showsQuoted.toggle() }
            }
            Button("Attach files…") { model.pickFiles() }
            Divider()
            Button("Discard draft", role: .destructive) { model.discard() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundStyle(Theme.iconSecondary)
                .frame(width: Theme.Metrics.iconButton, height: Theme.Metrics.iconButton)
                .hoverFill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

/// Body editor, then the collapsed quote ("…") of a reply or forward.
private struct ComposeBody: View {
    @Bindable var model: ComposeModel
    let placeholder: String
    let focusOnAppear: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MailTextView(text: $model.draft.body, placeholder: placeholder, signature: model.draft.signature, focusOnAppear: focusOnAppear)
            if let quoted = model.draft.quoted {
                Button { model.showsQuoted.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 24, height: 16)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(model.showsQuoted ? "Hide quoted text" : "Show quoted text")
                if model.showsQuoted {
                    Text(quoted)
                        .textStyle(.mailBody)
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ComposeFooter: View {
    let model: ComposeModel

    private var sendAndArchive: (() -> Void)? {
        guard model.draft.mode != .new, model.draft.threadId != nil else { return nil }
        return { model.send(archiveThread: true) }
    }

    var body: some View {
        HStack(spacing: 12) {
            SendButton(send: { model.send() }, sendAndArchive: sendAndArchive)
            Text(model.statusText)
                .textStyle(.body)
                .foregroundStyle(model.status == .failed ? Theme.textRed : Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                IconButton(systemName: "paperclip", help: "Attach files") { model.pickFiles() }
                SnippetMenu(model: model)
                EventMenu(model: model)
                IconButton(systemName: "trash", help: "Discard draft") { model.discard() }
            }
            .padding(.trailing, -6)
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.Metrics.composerFooterHeight)
    }
}

/// Saved text blocks: insert one, or save what was typed as a new one. Stored locally.
private struct SnippetMenu: View {
    let model: ComposeModel
    @Environment(AppState.self) private var app
    private static let key = "snippets"

    var body: some View {
        let snippets = stored
        MenuButton(systemName: "curlybraces", help: "Snippets") {
            ForEach(snippets, id: \.self) { snippet in
                Button(Self.title(snippet)) { model.draft.insert(snippet) }
            }
            if snippets.isEmpty { Text("No snippets yet") }
            Divider()
            Button("Save message as snippet") { save(snippets + [model.draft.typedText]) }
                .disabled(model.draft.typedText.isEmpty || snippets.contains(model.draft.typedText))
            if !snippets.isEmpty {
                Menu("Delete snippet") {
                    ForEach(snippets, id: \.self) { snippet in
                        Button(Self.title(snippet)) { save(snippets.filter { $0 != snippet }) }
                    }
                }
            }
        }
    }

    private var stored: [String] {
        (try? app.store.get(Self.key)).flatMap { $0 }.flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
    }

    private func save(_ snippets: [String]) {
        try? app.store.set(Self.key, (try? JSONEncoder().encode(snippets)).map { String(decoding: $0, as: UTF8.self) })
    }

    private static func title(_ snippet: String) -> String {
        let line = snippet.split(separator: "\n").first.map(String.init) ?? snippet
        return line.count > 40 ? line.prefix(40) + "…" : line
    }
}

/// Upcoming calendar events; picking one writes its title, time and place into the body.
private struct EventMenu: View {
    let model: ComposeModel
    @Environment(AppState.self) private var app
    @State private var feed: CalendarFeed?

    var body: some View {
        MenuButton(systemName: "calendar", help: "Insert event") {
            let events = feed?.days().flatMap(\.events) ?? []
            ForEach(events) { event in
                Button("\(event.title) · \(EventTime.range(event))") { model.draft.insert(Self.text(event)) }
            }
            if events.isEmpty { Text(feed?.status == .loading ? "Loading events…" : "No upcoming events") }
        }
        .task {
            let feed = CalendarFeed(client: app.isDemo ? nil : GoogleCalendarClient())
            self.feed = feed
            await feed.refresh()
        }
    }

    private static func text(_ event: CalendarEvent) -> String {
        [event.title, EventTime.range(event), event.location].compactMap { $0 }.joined(separator: "\n")
    }
}

/// Blue split button: Send, and a chevron with Send & archive (§4.5).
private struct SendButton: View {
    let send: () -> Void
    let sendAndArchive: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: send) {
                Text("Send")
                    .textStyle(.bodySemibold)
                    .foregroundStyle(Theme.textContrast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Send  ⌘↵")
            Rectangle().fill(Theme.textContrast.opacity(0.25)).frame(width: 1)
            Menu {
                Button("Send") { send() }
                if let sendAndArchive { Button("Send & archive", action: sendAndArchive) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textContrast)
                    .frame(width: 23, height: Theme.Metrics.buttonSmall)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(width: Theme.Metrics.sendButtonWidth, height: Theme.Metrics.buttonSmall)
        .background(hovering ? Theme.accentHover : Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius, style: .continuous))
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
    }
}

private struct AttachmentStrip: View {
    let model: ComposeModel

    var body: some View {
        if !model.draft.attachments.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(model.draft.attachments) { a in
                    AttachmentChip(attachment: a) { model.draft.attachments.removeAll { $0.id == a.id } }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct AttachmentChip: View {
    let attachment: ComposeAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo" : "doc")
                .font(.system(size: 12))
                .foregroundStyle(Theme.iconSecondary)
            Text(attachment.filename)
                .textStyle(.body)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                .textStyle(.small)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.iconSecondary)
                    .frame(width: 18, height: 18)
                    .hoverFill(radius: Theme.Metrics.radiusSmall)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: Theme.Metrics.buttonSmall)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private struct DropHighlight: View {
    let isActive: Bool
    let radius: CGFloat

    var body: some View {
        if isActive {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.rowSelected)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .overlay { Text("Drop files to attach").textStyle(.bodyMedium).foregroundStyle(Theme.textBlue) }
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Recipients

/// Recipient chips plus an input with contact suggestions. Enter, Tab, comma or leaving the
/// field turns typed text into a chip; Delete on an empty input removes the last one.
struct RecipientField: View {
    @Binding var addresses: [EmailAddress]
    let contacts: [Contact]
    var placeholder = ""
    var prefix: String?
    var prefixAlignment = Alignment.leading
    var focus: FocusState<ComposeModel.Field?>.Binding
    let field: ComposeModel.Field
    @State private var input = ""
    @State private var highlighted = 0

    private var suggestions: [Contact] {
        let taken = Set(addresses.map { $0.email.lowercased() })
        return Array(contacts.lazy.filter { !taken.contains($0.id) && $0.matches(input.trimmingCharacters(in: .whitespaces)) }.prefix(6))
    }

    private var showsSuggestions: Bool { focus.wrappedValue == field && !suggestions.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let prefix {
                Text(prefix).textStyle(.body).foregroundStyle(Theme.textTertiary)
                    .frame(width: 32, height: Theme.Metrics.composerFieldHeight, alignment: prefixAlignment)
            }
            FlowLayout(spacing: 4, lineSpacing: 0, minLastWidth: 120) {
                ForEach(Array(addresses.enumerated()), id: \.offset) { i, address in
                    RecipientChip(address: address) { addresses.remove(at: i) }
                        .frame(height: Theme.Metrics.composerFieldHeight)
                }
                TextField("", text: $input)
                    .textFieldStyle(.plain)
                    .textStyle(.body)
                    .placeholder(placeholder, showing: addresses.isEmpty && input.isEmpty)
                    .focused(focus, equals: field)
                    .frame(height: Theme.Metrics.composerFieldHeight)
                    .onSubmit(commitOrPick)
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.tab) {
                        guard !input.isEmpty else { return .ignored }
                        commitOrPick()
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard input.isEmpty, !addresses.isEmpty else { return .ignored }
                        addresses.removeLast()
                        return .handled
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = field }
        }
        .overlay(alignment: .bottomLeading) {
            if showsSuggestions {
                SuggestionMenu(contacts: suggestions, highlighted: min(highlighted, suggestions.count - 1)) { add($0.address) }
                    .alignmentGuide(.bottom) { $0[.top] - 2 }
                    .offset(x: prefix == nil ? -8 : 32)
            }
        }
        .onChange(of: input) {
            highlighted = 0
            if input.contains(where: { $0 == "," || $0 == ";" || $0 == "\n" }) { commitTyped() }
        }
        .onChange(of: focus.wrappedValue) { old, _ in
            if old == field { commitTyped() }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard showsSuggestions else { return .ignored }
        highlighted = (highlighted + delta + suggestions.count) % suggestions.count
        return .handled
    }

    private func commitOrPick() {
        if showsSuggestions, input.trimmingCharacters(in: .whitespaces).count > 0, !Self.isEmail(input) {
            add(suggestions[min(highlighted, suggestions.count - 1)].address)
        } else {
            commitTyped()
        }
    }

    private func add(_ address: EmailAddress) {
        if !addresses.contains(where: { $0.email.lowercased() == address.email.lowercased() }) { addresses.append(address) }
        input = ""
    }

    /// Turns every complete address in the input into a chip and leaves anything unparsable.
    private func commitTyped() {
        let parts = input.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }
        var rest: [String] = []
        for part in parts where !part.isEmpty {
            if let address = EmailAddress.parseList(part).first, Self.isEmail(address.email) { add(address) } else { rest.append(part) }
        }
        input = rest.joined(separator: ", ")
    }

    static func isEmail(_ s: String) -> Bool {
        s.wholeMatch(of: /[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+/) != nil
    }
}

private struct RecipientChip: View {
    let address: EmailAddress
    let remove: () -> Void

    var body: some View {
        let color = LabelColor.lightGray
        HStack(spacing: 4) {
            Text(address.displayName).textStyle(.body).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(color.text.opacity(0.5))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(color.text)
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .frame(height: Theme.Metrics.chipHeightReader)
        .background(color.fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.chipRadius, style: .continuous))
        .frame(maxWidth: 260)
        .fixedSize()
        .help(address.formatted)
    }
}

private struct SuggestionMenu: View {
    let contacts: [Contact]
    let highlighted: Int
    let pick: (Contact) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(contacts.enumerated()), id: \.element.id) { i, contact in
                Button { pick(contact) } label: {
                    HStack(spacing: 8) {
                        Avatar(name: contact.address.displayName, size: 20)
                        Text(contact.address.name ?? contact.address.email).textStyle(.body).lineLimit(1).layoutPriority(1)
                        if contact.address.name != nil {
                            Text(contact.address.email).textStyle(.small).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(i == highlighted ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 320)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusMenu, style: .continuous))
        .elevation(.l3, radius: Theme.Metrics.radiusMenu)
    }
}

// MARK: - Body text view

/// Plain-text editor on NSTextView: 14/24 mail body, grey "-- " delimiter lines, a
/// placeholder while nothing but the signature is there, and a height that follows the text.
struct MailTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder = ""
    var signature = ""
    var focusOnAppear = false
    var minHeight: CGFloat = TextStyle.mailBody.lineHeight

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> BodyTextView {
        let view = BodyTextView()
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.selectedTextAttributes = [.backgroundColor: NSColor(Theme.textSelection)]
        view.typingAttributes = BodyTextView.baseAttributes
        view.placeholder = placeholder
        view.signature = signature
        view.delegate = context.coordinator
        view.string = text
        view.restyle()
        if focusOnAppear {
            DispatchQueue.main.async { [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: 0, length: 0))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
                guard let view else { return }
                view.scrollToVisible(NSRect(x: 0, y: -60, width: view.bounds.width, height: view.bounds.height + 240))
            }
        }
        return view
    }

    func updateNSView(_ view: BodyTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholder = placeholder
        view.signature = signature
        if view.string != text {
            view.string = text
            view.restyle()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BodyTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, let layout = view.layoutManager, let container = view.textContainer else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(ceil(layout.usedRect(for: container).height), minHeight))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MailTextView

        init(_ parent: MailTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? BodyTextView else { return }
            view.restyle()
            parent.text = view.string
        }
    }
}

final class BodyTextView: NSTextView {
    var placeholder = "" {
        didSet { if placeholder != oldValue { needsDisplay = true } }
    }
    var signature = "" {
        didSet { if signature != oldValue { needsDisplay = true } }
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let style = TextStyle.mailBody
        let font = style.nsFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = style.lineHeight
        paragraph.maximumLineHeight = style.lineHeight
        return [.font: font, .foregroundColor: NSColor(Theme.textPrimary), .paragraphStyle: paragraph,
                .baselineOffset: (style.lineHeight - (font.ascender - font.descender)) / 2]
    }

    /// Everything in the body style, with signature delimiter lines in textTertiary.
    func restyle() {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: full)
        let ns = string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, _, _ in
            if line?.trimmingCharacters(in: .whitespaces) == "--" {
                storage.addAttribute(.foregroundColor, value: NSColor(Theme.textTertiary), range: range)
            }
        }
        storage.endEditing()
        typingAttributes = Self.baseAttributes
        needsDisplay = true
    }

    private var showsPlaceholder: Bool {
        guard !placeholder.isEmpty else { return false }
        let typed = signature.isEmpty ? string : string.replacingOccurrences(of: ComposeDraft.signatureBlock(signature), with: "")
        return typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsPlaceholder else { return }
        var attributes = Self.baseAttributes
        attributes[.foregroundColor] = NSColor(Theme.placeholder)
        (placeholder as NSString).draw(at: .zero, withAttributes: attributes)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes.filter { $0 != .fileURL && $0.rawValue != "NSFilenamesPboardType" }
    }
}
