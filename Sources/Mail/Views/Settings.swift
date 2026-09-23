import MailCore
import SwiftUI

/// Settings modal (SPEC §4.9). Owner: account feature; the Integrations page belongs to the
/// Notion + Calendar feature.
struct SettingsView: View {
    let page: SettingsPage
    @Environment(AppState.self) private var app
    @AppStorage(MessageBody.loadRemoteKey) private var loadRemoteImages = true

    var body: some View {
        ZStack {
            Theme.scrim.onTapGesture { app.settings = nil }
            HStack(spacing: 0) {
                nav
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(page.rawValue).textStyle(.sectionTitle)
                        Hairline().padding(.top, 12)
                        content
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 720, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radiusLarge, style: .continuous))
            .elevation(.l4, radius: Theme.Metrics.radiusLarge)
            .padding(40)
        }
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("Account", top: 12)
            ForEach([SettingsPage.account, .signature, .appearance, .shortcuts], id: \.self, content: navItem)
            group("Connections", top: 16)
            navItem(.integrations)
            Spacer()
        }
        .frame(width: 250)
        .background(Theme.wash)
    }

    private func group(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .textStyle(.smallMedium)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, 18)
            .frame(height: 30, alignment: .bottom)
            .padding(.top, top)
            .padding(.bottom, 2)
    }

    private func navItem(_ p: SettingsPage) -> some View {
        SidebarItem(title: p.rawValue, isSelected: p == page, icon: { SlotIcon(systemName: icon(p)) }) { app.settings = p }
    }

    private func icon(_ p: SettingsPage) -> String {
        switch p {
        case .account: "person.crop.circle"
        case .signature: "pencil.line"
        case .appearance: "circle.lefthalf.filled"
        case .shortcuts: "keyboard"
        case .integrations: "square.grid.2x2"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .account: AccountSettings().padding(.top, 8)
        case .signature: SignatureSettings().padding(.top, 8)
        case .appearance:
            @Bindable var app = app
            SettingsRow(title: "Theme mode", detail: "Choose how Mail looks on this Mac") {
                SettingsPopUp(selection: $app.theme, options: ThemePreference.menuOrder, title: \.title)
            }
            .padding(.top, 8)
            HStack(spacing: 16) {
                ForEach(ThemePreference.menuOrder, id: \.self) { theme in
                    ThemeCard(theme: theme, isSelected: app.theme == theme) { app.theme = theme }
                }
            }
            .padding(.top, 12)
            Hairline().padding(.top, 24).padding(.bottom, 8)
            SettingsRow(title: "Load remote images automatically", detail: "Off: images from the web stay hidden until you allow them per message or sender") {
                Toggle("", isOn: $loadRemoteImages).toggleStyle(SettingsSwitch()).labelsHidden()
            }
        case .integrations: IntegrationsSettings()
        case .shortcuts: ShortcutsSettings().padding(.top, 8)
        }
    }
}

/// Settings → Account: who is signed in, and sign out.
private struct AccountSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Avatar(name: app.account?.name ?? "?", size: 44, fill: Theme.accent, image: app.avatarImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.account?.name ?? "Not synced yet").textStyle(.bodySemibold).foregroundStyle(Theme.textPrimary)
                    Text(app.account?.email ?? "").textStyle(.small).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(minHeight: 72)
            .padding(.bottom, 4)
            SettingsRow(title: "Name", detail: app.isDemo ? "Demo account" : "Your Google account name") {
                Text(app.account?.name ?? "—").textStyle(.body).foregroundStyle(Theme.textSecondary)
            }
            SettingsRow(title: "Email", detail: "The Google account Mail syncs") {
                Text(app.account?.email ?? "—").textStyle(.body).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
            }
            Hairline().padding(.vertical, 8)
            SettingsRow(title: "Sign out", detail: "Signs out of Google and removes this account's mail from this Mac") {
                Button("Sign out") { Task { await app.signOut() } }
                    .buttonStyle(MailButtonStyle(kind: .destructive))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
        }
    }
}

/// Settings → Keyboard shortcuts: every bound command from the registry, by palette group.
private struct ShortcutsSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let bound = app.commands.commands.filter { !$0.shortcuts.isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Command.Group.allCases, id: \.self) { group in
                let commands = bound.filter { $0.group == group }
                if !commands.isEmpty {
                    Text(group.rawValue)
                        .textStyle(.smallSemibold)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(height: 32, alignment: .bottom)
                        .padding(.top, group == Command.Group.allCases.first ? 0 : 12)
                        .padding(.bottom, 4)
                    ForEach(commands) { command in
                        HStack(spacing: 12) {
                            Text(command.title).textStyle(.body)
                            Spacer()
                            ForEach(Array(command.shortcuts.prefix(2).enumerated()), id: \.offset) { i, shortcut in
                                if i > 0 { Text("or").textStyle(.small).foregroundStyle(Theme.textTertiary) }
                                ShortcutKeys(shortcut: shortcut)
                            }
                        }
                        .frame(height: 36)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }
        }
    }
}

/// A small window drawn in the theme's own colors; System is split light | dark.
private struct ThemeCard: View {
    let theme: ThemePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 148, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
                    }
                Text(theme.title).textStyle(.small).foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniWindow(dark: false).frame(width: 74, alignment: .leading).clipped()
                MiniWindow(dark: true).frame(width: 148).frame(width: 74, alignment: .trailing).clipped()
            }
        }
    }
}

private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let page = dark ? Color(0x191919, dark: 0x191919) : Color(0xFFFFFF, dark: 0xFFFFFF)
        let wash = dark ? Color(0x202020, dark: 0x202020) : Color(0xF7F7F5, dark: 0xF7F7F5)
        let line = dark ? Color.white.opacity(0.16) : Color.black.opacity(0.09)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                ForEach(0..<4, id: \.self) { i in Capsule().fill(line).frame(width: i == 0 ? 26 : 20, height: 4) }
            }
            .padding(8)
            .frame(width: 44, height: 92, alignment: .topLeading)
            .background(wash)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 5) {
                        Capsule().fill(line).frame(width: 22, height: 4)
                        Capsule().fill(line).frame(width: [52, 40, 58, 34, 46][i], height: 4)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(page)
        }
    }
}

/// Blue when on regardless of window focus, as in the reference (§4.9).
struct SettingsSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Theme.accent : Theme.iconTertiary)
            .frame(width: 30, height: 18)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 14, height: 14).padding(2).shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
            .animation(Theme.Motion.fast, value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
    }
}

/// "Light ⌄": a borderless pop-up in textSecondary (§4.9).
struct SettingsPopUp<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    init(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.title = title
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    if option == selection { Label(title(option), systemImage: "checkmark") } else { Text(title(option)) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(selection)).textStyle(.body).foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.iconSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .hoverFill()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// 56 tall settings row: name and description on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.bodyMedium)
                Text(detail).textStyle(.small).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            control
        }
        .frame(minHeight: 56)
    }
}
