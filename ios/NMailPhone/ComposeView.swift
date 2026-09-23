import MailCore
import SwiftUI

/// The compose sheet for new mail, replies, forwards and drafts. MailCore's ComposeModel owns the draft, autosaves it
/// to Gmail and sends through the Outbox (Notion-style HTML with the signature, 5 s undo toast).
struct ComposeView: View {
    let request: ComposeRequest
    @Environment(AppState.self) private var app
    @State private var model = ComposeModel()
    @State private var confirmingCancel = false
    @FocusState private var focus: Field?
    /// Starts at the top of the body, above the signature.
    @State private var bodySelection: TextSelection?

    enum Field: Hashable { case to, cc, bcc, subject, body }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    RecipientField(title: "To", addresses: $model.draft.to, contacts: model.contacts, focus: $focus, field: .to) {
                        if !model.showsCc || !model.showsBcc {
                            Button("Cc/Bcc") { model.showsCc = true; model.showsBcc = true }
                                .font(.subheadline).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if model.showsCc {
                        RecipientField(title: "Cc", addresses: $model.draft.cc, contacts: model.contacts, focus: $focus, field: .cc) { EmptyView() }
                    }
                    if model.showsBcc {
                        RecipientField(title: "Bcc", addresses: $model.draft.bcc, contacts: model.contacts, focus: $focus, field: .bcc) { EmptyView() }
                    }
                    if model.identities.count > 1 { fromRow }
                    row {
                        TextField("Subject", text: $model.draft.subject)
                            .font(.body)
                            .focused($focus, equals: .subject)
                            .submitLabel(.next)
                            .onSubmit { focus = .body }
                    }
                    TextField("Message", text: $model.draft.body, selection: $bodySelection, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(8...)
                        .focused($focus, equals: .body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    if let quoted = model.draft.quotedHTML ?? model.draft.quoted.map(Quote.html(fromText:)) {
                        QuotedHistory { MessageBody(html: quoted) }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !model.draft.attachments.isEmpty { attachments }
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.page)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.page, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.draft.isPristine, model.draft.draftId == nil { model.close() } else { confirmingCancel = true }
                    }
                    .confirmationDialog("", isPresented: $confirmingCancel) {
                        Button("Delete Draft", role: .destructive) { model.discard() }
                        Button("Save Draft") { model.close() }
                    }
                }
                ToolbarItem(placement: .principal) { modeMenu }
                ToolbarItem(placement: .confirmationAction) {
                    Button { model.send() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, model.draft.recipients.isEmpty ? Theme.iconSecondary : Theme.accent)
                    }
                    .accessibilityLabel("Send")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !model.statusText.isEmpty {
                    Text(model.statusText).font(.caption).foregroundStyle(Theme.textTertiary).padding(.bottom, 4)
                }
            }
        }
        .interactiveDismissDisabled(!model.draft.isPristine)
        .onAppear {
            model.load(request, app: app)
            bodySelection = TextSelection(insertionPoint: model.draft.body.startIndex)
            focus = model.draft.to.isEmpty ? .to : .body
        }
        .onDisappear { model.flush() }
        .onChange(of: model.draft) { model.edited() }
    }

    private var title: String {
        switch model.draft.mode {
        case .new: model.draft.draftId == nil ? "New Message" : "Draft"
        case .reply: "Reply"
        case .replyAll: "Reply All"
        case .forward: "Forward"
        }
    }

    @ViewBuilder
    private var modeMenu: some View {
        if model.draft.mode == .new {
            Text(title).font(.headline)
        } else {
            Menu {
                Picker("Mode", selection: Binding(get: { model.draft.mode }, set: { model.switchMode($0) })) {
                    Label("Reply", systemImage: "arrowshape.turn.up.left").tag(ComposeDraft.Mode.reply)
                    Label("Reply All", systemImage: "arrowshape.turn.up.left.2").tag(ComposeDraft.Mode.replyAll)
                    Label("Forward", systemImage: "arrowshape.turn.up.right").tag(ComposeDraft.Mode.forward)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.iconSecondary)
                }
            }
        }
    }

    private var fromRow: some View {
        row {
            Text("From").font(.body).foregroundStyle(Theme.textTertiary)
            Menu {
                ForEach(model.identities) { identity in
                    Button(identity.email) { model.choose(identity) }
                }
            } label: {
                Text(model.draft.from.email).font(.body).foregroundStyle(Theme.textPrimary).lineLimit(1)
            }
            Spacer()
        }
    }

    private var attachments: some View {
        VStack(spacing: 6) {
            ForEach(model.draft.attachments) { a in
                HStack(spacing: 8) {
                    Image(systemName: "paperclip").foregroundStyle(Theme.iconSecondary)
                    Text(a.filename).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file)).font(.caption).foregroundStyle(Theme.textTertiary)
                    Button { model.draft.attachments.removeAll { $0.id == a.id } } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Theme.iconSecondary)
                        .accessibilityLabel("Remove \(a.filename)")
                }
                .padding(10)
                .background(Theme.wash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { Hairline().padding(.leading, 16) }
    }
}

/// "To:" with each address as a token, a text field for the next one and contact suggestions below.
/// Return, comma or space after a full address commits it; backspace in the empty field removes the last token.
private struct RecipientField<Accessory: View>: View {
    let title: String
    @Binding var addresses: [EmailAddress]
    let contacts: [Contact]
    var focus: FocusState<ComposeView.Field?>.Binding
    let field: ComposeView.Field
    @ViewBuilder let accessory: Accessory
    @State private var input = "\u{200B}"

    private var typed: String { input.replacingOccurrences(of: "\u{200B}", with: "").trimmingCharacters(in: .whitespaces) }

    private var suggestions: [Contact] {
        let taken = Set(addresses.map { $0.email.lowercased() })
        return Array(contacts.lazy.filter { !taken.contains($0.id) && $0.matches(typed) }.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.body).foregroundStyle(Theme.textTertiary)
                FlowLayout(spacing: 6, lineSpacing: 6, minLastWidth: 44) {
                    ForEach(Array(addresses.enumerated()), id: \.offset) { i, address in
                        Token(address: address) { addresses.remove(at: i) }
                    }
                    TextField("", text: $input)
                        .font(.body)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused(focus, equals: field)
                        .onSubmit(commit)
                        .onChange(of: input) { old, new in edited(old: old, new: new) }
                }
                accessory
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { Hairline().padding(.leading, 16) }
            if focus.wrappedValue == field, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { contact in
                        Button { add(contact.address) } label: {
                            HStack(spacing: 10) {
                                Avatar(name: contact.address.displayName, size: 30)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(contact.address.displayName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                    Text(contact.address.email).font(.footnote).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.wash)
            }
        }
    }

    /// A zero-width space keeps the field non-empty so deleting it can be seen as "backspace on empty".
    private func edited(old: String, new: String) {
        if new.isEmpty {
            if !addresses.isEmpty, old == "\u{200B}" { addresses.removeLast() }
            input = "\u{200B}"
        } else if let last = new.last, last == "," || last == " " || last == ";", typed.contains("@") {
            commit()
        }
    }

    private func commit() {
        let text = typed.trimmingCharacters(in: CharacterSet(charactersIn: ",; "))
        if let first = suggestions.first, !text.contains("@") {
            add(first.address)
        } else if let parsed = EmailAddress.parseList(text).first, parsed.email.contains("@") {
            add(parsed)
        }
    }

    private func add(_ address: EmailAddress) {
        addresses.append(address)
        input = "\u{200B}"
    }
}

private struct Token: View {
    let address: EmailAddress
    let remove: () -> Void

    var body: some View {
        Menu {
            Text(address.email)
            Button("Remove", systemImage: "xmark", role: .destructive, action: remove)
        } label: {
            Text(address.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel("\(address.displayName), \(address.email)")
    }
}
