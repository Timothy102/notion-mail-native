import MailCore
import SwiftUI

/// Dropdown under the sidebar's account row (§5.10): who is signed in, settings, appearance,
/// shortcuts and sign out.
struct AccountMenu: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Avatar(name: app.account?.name ?? "?", size: 32, fill: Theme.accent, image: app.avatarImage)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.account?.name ?? "Not synced yet").textStyle(.bodySemibold).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(app.account?.email ?? "").textStyle(.small).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            separator
            MenuItem(title: "Settings…", icon: "gearshape", hint: shortcut("misc.settings")) { open(.account) }
            MenuItem(title: "Keyboard shortcuts", icon: "keyboard", hint: shortcut("misc.shortcuts")) { open(.shortcuts) }
            separator
            Text("Appearance")
                .textStyle(.smallMedium)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 26)
            ForEach(ThemePreference.menuOrder, id: \.self) { theme in
                MenuItem(title: theme.title, icon: theme.icon, isChecked: app.theme == theme) { app.theme = theme }
            }
            separator
            MenuItem(title: "Sign out", icon: "rectangle.portrait.and.arrow.right", tint: Theme.textRed) {
                Task { await app.signOut() }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 260)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .elevation(.l3, radius: 8)
    }

    private var separator: some View {
        Hairline().padding(.vertical, 6)
    }

    private func shortcut(_ id: String) -> String? {
        app.commands.commands.first { $0.id == id }?.shortcuts.first?.display
    }

    private func open(_ page: SettingsPage) {
        app.isAccountMenuOpen = false
        app.settings = page
    }
}

/// One menu row (§5.10): 28 tall, inset 4, icon 16, value or check on the right.
struct MenuItem: View {
    let title: String
    let icon: String
    var hint: String?
    var isChecked = false
    var tint: Color?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint ?? Theme.iconSecondary)
                    .frame(width: 16, height: 16)
                Text(title).textStyle(.body).foregroundStyle(tint ?? Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                if let hint { Text(hint).textStyle(.small).foregroundStyle(Theme.textTertiary) }
                if isChecked {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.iconPrimary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
    }
}

extension ThemePreference {
    static let menuOrder: [ThemePreference] = [.light, .dark, .system]

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
