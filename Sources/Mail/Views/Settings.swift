import MailCore
import SwiftUI

/// Settings modal (SPEC §4.9). Owner: compose/signatures feature (Signature page); Notion +
/// Calendar feature (Integrations page).
struct SettingsView: View {
    let page: SettingsPage
    @Environment(AppState.self) private var app
    @State private var sendAs = Live<[SendAs]>([])

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
        .onAppear { sendAs.observe(app.store) { try Store.sendAs($0) } }
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Account")
                .textStyle(.smallMedium)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 18)
                .frame(height: 30, alignment: .bottom)
                .padding(.top, 12)
            ForEach(SettingsPage.allCases, id: \.self) { p in
                SidebarItem(title: p.rawValue, isSelected: p == page, icon: { SlotIcon(systemName: icon(p)) }) { app.settings = p }
            }
            Spacer()
        }
        .frame(width: 250)
        .background(Theme.wash)
    }

    private func icon(_ p: SettingsPage) -> String {
        switch p {
        case .inbox: "tray"
        case .signature: "signature"
        case .integrations: "square.grid.2x2"
        case .shortcuts: "keyboard"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .inbox:
            @Bindable var app = app
            SettingsRow(title: "Appearance", detail: "Light, dark, or follow the system") {
                Picker("", selection: $app.theme) {
                    Text("System").tag(ThemePreference.system)
                    Text("Light").tag(ThemePreference.light)
                    Text("Dark").tag(ThemePreference.dark)
                }
                .labelsHidden()
                .fixedSize()
            }
        case .signature:
            ForEach(sendAs.value) { identity in
                VStack(alignment: .leading, spacing: 8) {
                    Text(identity.address.formatted).textStyle(.bodyMedium)
                    Text(MIME.plainText(fromHTML: identity.signature))
                        .textStyle(.mailBody)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }
                .padding(.top, 16)
            }
        case .integrations:
            IntegrationsSettings()
        case .shortcuts:
            ForEach(app.commands.commands.filter { !$0.shortcuts.isEmpty }) { command in
                HStack {
                    Text(command.title).textStyle(.body)
                    Spacer()
                    ShortcutKeys(shortcut: command.shortcuts[0])
                }
                .frame(height: 36)
            }
            .padding(.top, 8)
        }
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
