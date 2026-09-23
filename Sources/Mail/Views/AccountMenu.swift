import MailCore
import SwiftUI

/// Dropdown under the sidebar's account row (§5.10): the signed-in accounts (⌘1…⌘9 switch), add account,
/// settings, appearance, shortcuts and sign out of the open account.
struct AccountMenu: View {
    @Environment(AppState.self) private var app
    @Environment(AccountManager.self) private var accounts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(accounts.emails.enumerated()), id: \.element) { i, email in
                AccountRow(name: email == accounts.activeEmail ? app.account?.name ?? accounts.name(of: email) : accounts.name(of: email),
                           email: email,
                           image: email == accounts.activeEmail ? app.avatarImage : accounts.avatar(of: email),
                           hint: i < 9 ? "⌘\(i + 1)" : nil,
                           isActive: email == accounts.activeEmail) {
                    app.isAccountMenuOpen = false
                    accounts.switchTo(email)
                }
            }
            MenuItem(title: "Add account…", icon: "plus") {
                app.isAccountMenuOpen = false
                Task {
                    do { try await accounts.addAccount() } catch { app.show(Toast("Couldn't add the account: \(SignInView.describe(error))")) }
                }
            }
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
            MenuItem(title: "Sign out of \(accounts.activeEmail ?? "account")", icon: "rectangle.portrait.and.arrow.right", tint: Theme.textRed) {
                app.isAccountMenuOpen = false
                Task { await accounts.signOut() }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 300)
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

/// An account in the switcher: photo or letter, name over email, ⌘-number, check on the open one.
private struct AccountRow: View {
    let name: String
    let email: String
    let image: NSImage?
    let hint: String?
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Avatar(name: name, size: 28, fill: Theme.accent, image: image)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).textStyle(.bodySemibold).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(email).textStyle(.small).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.iconPrimary)
                } else if let hint {
                    Text(hint).textStyle(.small).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
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
