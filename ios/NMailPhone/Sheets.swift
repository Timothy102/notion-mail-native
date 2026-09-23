import MailCore
import SwiftUI

/// Inbox, Starred, All Mail, Sent, Drafts, Spam, Trash and the Gmail labels, with unread counts (SPEC §4.2).
struct MailboxesSheet: View {
    @Binding var sheet: MainSheet?
    @Environment(AppState.self) private var app
    @State private var counts = Live<[String: Int]>([:])
    @State private var labels = Live<[MailLabel]>([])

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Mailbox.system, id: \.self) { box in
                        row(box) {
                            Image(systemName: box == .inbox ? "tray.fill" : box.symbol)
                                .foregroundStyle(box == .inbox ? Theme.inboxRed : Theme.iconSecondary)
                        }
                    }
                }
                if !labels.value.isEmpty {
                    Section("Labels") {
                        ForEach(labels.value) { label in
                            row(.label(label.id), title: label.name) {
                                Circle().fill(LabelColor(named: label.color).dot).frame(width: 11, height: 11)
                            }
                        }
                    }
                }
                Section {
                    Button { sheet = .settings } label: {
                        Label { Text("Settings").foregroundStyle(Theme.textPrimary) } icon: {
                            Image(systemName: "gearshape").foregroundStyle(Theme.iconSecondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.wash)
            .navigationTitle("Mailboxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            counts.observe(app.store) { try Store.unreadCounts($0) }
            labels.observe(app.store) { try Store.labels($0) }
        }
    }

    private func row<Icon: View>(_ box: Mailbox, title: String? = nil, @ViewBuilder icon: () -> Icon) -> some View {
        let count = box == .sent ? 0 : box.labelId.flatMap { counts.value[$0] } ?? 0
        let current = app.mailbox == box
        return Button {
            app.go(to: box)
            sheet = nil
        } label: {
            HStack(spacing: 12) {
                icon().frame(width: 24)
                Text(title ?? box.title).foregroundStyle(Theme.textPrimary).fontWeight(current ? .semibold : .regular)
                Spacer()
                if count > 0 { Text("\(count)").foregroundStyle(Theme.textTertiary).monospacedDigit() }
                if current { Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent) }
            }
        }
        .listRowBackground(Theme.card)
    }
}

/// The account switcher from the toolbar avatar: every signed-in account, Add account, Settings and Sign out.
struct AccountsSheet: View {
    @Binding var sheet: MainSheet?
    @Environment(AccountManager.self) private var accounts
    @Environment(AppState.self) private var app
    @State private var error: String?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AccountRows { sheet = nil }
                    AddAccountButton(error: $error)
                } footer: {
                    if let error { Text(error).foregroundStyle(Theme.textRed) }
                }
                Section {
                    Button { sheet = .settings } label: {
                        Label { Text("Settings").foregroundStyle(Theme.textPrimary) } icon: {
                            Image(systemName: "gearshape").foregroundStyle(Theme.iconSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                    SignOutButton(confirming: $confirmSignOut) { sheet = nil }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.wash)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct AccountRows: View {
    var switched: () -> Void = {}
    @Environment(AccountManager.self) private var accounts

    var body: some View {
        ForEach(accounts.emails, id: \.self) { email in
            Button {
                accounts.switchTo(email)
                switched()
            } label: {
                HStack(spacing: 12) {
                    Avatar(name: accounts.name(of: email), size: 36, fill: Theme.accent, image: accounts.avatar(of: email))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(accounts.name(of: email)).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(email).font(.footnote).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    if email == accounts.activeEmail {
                        Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .listRowBackground(Theme.card)
            .accessibilityAddTraits(email == accounts.activeEmail ? .isSelected : [])
        }
    }
}

struct AddAccountButton: View {
    @Binding var error: String?
    @Environment(AccountManager.self) private var accounts
    @State private var busy = false

    var body: some View {
        Button {
            busy = true
            error = nil
            Task {
                do { try await accounts.addAccount() } catch { self.error = SignInView.describe(error) }
                busy = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.body.weight(.medium)).foregroundStyle(Theme.iconSecondary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                Text("Add account").foregroundStyle(Theme.textPrimary)
                Spacer()
                if busy { ProgressView() }
            }
        }
        .disabled(busy)
        .listRowBackground(Theme.card)
    }
}

struct SignOutButton: View {
    @Binding var confirming: Bool
    var done: () -> Void = {}
    @Environment(AccountManager.self) private var accounts

    var body: some View {
        Button(role: .destructive) { confirming = true } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.textRed)
        }
        .listRowBackground(Theme.card)
        .confirmationDialog("Sign out of \(accounts.activeEmail ?? "this account")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                done()
                Task { await accounts.signOut() }
            }
        } message: {
            Text("Its mail is removed from this iPhone. It stays in Gmail.")
        }
    }
}

/// Settings: accounts, signature, appearance and reading.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var confirmSignOut = false
    @State private var signOnReplies = true
    @AppStorage(MessageBody.loadRemoteKey) private var loadRemote = true

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    AccountRows()
                    AddAccountButton(error: $error)
                } header: { Text("Accounts") } footer: {
                    if let error { Text(error).foregroundStyle(Theme.textRed) }
                }
                Section {
                    NavigationLink { SignatureSettings() } label: {
                        Label { Text("Signature") } icon: { Image(systemName: "signature").foregroundStyle(Theme.iconSecondary) }
                    }
                    .listRowBackground(Theme.card)
                    Toggle(isOn: $signOnReplies) {
                        Label { Text("Sign replies and forwards") } icon: { Image(systemName: "arrowshape.turn.up.left").foregroundStyle(Theme.iconSecondary) }
                    }
                    .listRowBackground(Theme.card)
                } header: { Text("Composing") }
                Section("Appearance") {
                    Picker("Theme", selection: $app.theme) {
                        Text("System").tag(ThemePreference.system)
                        Text("Light").tag(ThemePreference.light)
                        Text("Dark").tag(ThemePreference.dark)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Theme.card)
                }
                Section {
                    Toggle(isOn: $loadRemote) {
                        Label { Text("Load remote images") } icon: { Image(systemName: "photo").foregroundStyle(Theme.iconSecondary) }
                    }
                    .listRowBackground(Theme.card)
                } header: { Text("Reading") } footer: {
                    Text("Remote images can tell senders when you open their mail.")
                }
                Section {
                    SignOutButton(confirming: $confirmSignOut) { dismiss() }
                } footer: {
                    Text(version).frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.wash)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { signOnReplies = app.outbox.signOnReplies }
        .onChange(of: signOnReplies) { app.outbox.signOnReplies = signOnReplies }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "NMail \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}

/// Settings → Signature (§4.9): per-address HTML editor and a live preview rendered like outgoing mail.
/// "Save" keeps it on this iPhone; only "Save to Gmail" changes the Gmail signature.
struct SignatureSettings: View {
    @Environment(AppState.self) private var app
    @State private var identities = Live<[SendAs]>([])
    @State private var selectedEmail = ""
    @State private var text = ""
    @State private var original = ""
    @State private var status: String?

    private var selected: SendAs? { identities.value.first { $0.email == selectedEmail } ?? identities.value.first }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            if identities.value.count > 1 {
                Picker("Address", selection: $selectedEmail) {
                    ForEach(identities.value) { Text($0.email).tag($0.email) }
                }
                .listRowBackground(Theme.card)
            }
            Section("Preview") {
                MessageBody(html: trimmed)
                    .padding(.vertical, 6)
                    .listRowBackground(Theme.card)
            }
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 160)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .listRowBackground(Theme.card)
            } header: { Text("HTML") } footer: {
                Text(status ?? "NMail signs new messages with this signature. Your Gmail signature only changes when you choose Save to Gmail.")
            }
            Section {
                Button("Save on This iPhone", action: save).disabled(trimmed == original)
                Button("Save to Gmail", action: push).disabled(selected == nil)
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.wash)
        .navigationTitle("Signature")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            identities.observe(app.store) { try Store.sendAs($0) }
            selectedEmail = identities.value.first?.email ?? ""
            load()
        }
        .onChange(of: selectedEmail) { load() }
    }

    private func load() {
        original = (try? app.store.db.read { try Signature.html(for: selected, db: $0) }) ?? ""
        text = original
        status = nil
    }

    private func save() {
        guard let identity = selected else { return }
        do {
            try app.store.saveLocalSignature(trimmed, for: identity)
            original = trimmed
            status = "Saved on this iPhone."
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func push() {
        guard let identity = selected else { return }
        let html = trimmed
        status = "Saving to Gmail…"
        Task {
            do {
                try await app.outbox.updateSignature(identity, html: html)
                original = html
                status = app.isDemo ? "Saved (demo mode, not sent to Gmail)." : "Saved to Gmail."
            } catch {
                status = "Couldn't save to Gmail: \(error.localizedDescription)"
            }
        }
    }
}
