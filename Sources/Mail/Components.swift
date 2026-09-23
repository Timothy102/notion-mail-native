import MailCore
import SwiftUI

// Shared building blocks from SPEC §5. Feature views compose these instead of restyling their own.

// MARK: - Buttons (§5.7)

struct MailButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, ghost, destructive }
    var kind: Kind
    var height: CGFloat = Theme.Metrics.buttonSmall

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .textStyle(kind == .primary ? .bodySemibold : kind == .outline ? .bodyMedium : .body)
                .foregroundStyle(foreground)
                .padding(.horizontal, height >= Theme.Metrics.buttonMedium ? 12 : 8)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metrics.buttonRadius, style: .continuous)
                        .strokeBorder(kind == .outline ? Theme.border : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h && isEnabled } }
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.textContrast
            case .outline: Theme.textPrimary
            case .ghost: Theme.iconSecondary
            case .destructive: Theme.textRed
            }
        }

        private var background: Color {
            let pressed = configuration.isPressed
            if kind == .primary { return pressed ? Theme.accentPressed : hovering ? Theme.accentHover : Theme.accent }
            return pressed ? Theme.pressed : hovering ? Theme.hover : .clear
        }
    }
}

extension ButtonStyle where Self == MailButtonStyle {
    static var primary: MailButtonStyle { MailButtonStyle(kind: .primary) }
    static var outline: MailButtonStyle { MailButtonStyle(kind: .outline) }
    static func outline(height: CGFloat) -> MailButtonStyle { MailButtonStyle(kind: .outline, height: height) }
    static var destructive: MailButtonStyle { MailButtonStyle(kind: .destructive) }
}

/// 28 × 28 ghost icon button with a 16 (or 20) glyph.
struct IconButton: View {
    let systemName: String
    var glyph: CGFloat = Theme.Metrics.iconSmall
    var tint: Color = Theme.iconSecondary
    var help: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyph * 0.875, weight: .regular))
                .foregroundStyle(isEnabled ? tint : Theme.iconTertiary)
                .frame(width: Theme.Metrics.iconButton, height: Theme.Metrics.iconButton)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h && isEnabled } }
        .help(help ?? "")
    }
}

// MARK: - Chips, avatars, keycaps

/// Label chip (§5.4): 18 tall in the list, 20 in the reader.
struct LabelChip: View {
    let label: MailLabel
    var reader = false

    var body: some View {
        let color = LabelColor(named: label.color)
        Text(label.name)
            .textStyle(reader ? .body : .list)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(color.text)
            .padding(.horizontal, 6)
            .frame(height: reader ? Theme.Metrics.chipHeightReader : Theme.Metrics.chipHeightList)
            .background(color.fill, in: RoundedRectangle(cornerRadius: Theme.Metrics.chipRadius, style: .continuous))
            .frame(maxWidth: reader ? nil : Theme.Metrics.chipMaxWidth, alignment: .leading)
            .fixedSize(horizontal: reader, vertical: true)
    }
}

/// Circle with an initial (§5.13). `fill` nil = neutral contact avatar.
struct Avatar: View {
    let name: String
    var size: CGFloat = 20
    var fill: Color?

    var body: some View {
        let initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        Circle()
            .fill(fill ?? Theme.elevated)
            .overlay { if fill == nil { Circle().strokeBorder(Theme.divider, lineWidth: 1) } }
            .overlay {
                Text(initial)
                    .font(TextStyle.avatarInitial(size: size).font)
                    .foregroundStyle(fill == nil ? Theme.iconSecondary : Theme.textContrast)
            }
            .frame(width: size, height: size)
    }
}

/// One key (§5.11).
struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .textStyle(.keycap)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.Metrics.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radiusSmall, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// "G then I" as keycaps.
struct ShortcutKeys: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.strokes.enumerated()), id: \.offset) { i, stroke in
                if i > 0 { Text("then").textStyle(.small).foregroundStyle(Theme.textTertiary) }
                Keycap(text: stroke.display)
            }
        }
    }
}

/// 14 pt list checkbox (§5.2).
struct Checkbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isOn ? Theme.accent : .clear)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textContrast)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Theme.iconTertiary, lineWidth: 1.5)
                }
            }
            .frame(width: Theme.Metrics.checkboxSize, height: Theme.Metrics.checkboxSize)
    }
}

/// One device pixel of `divider`, horizontal or vertical.
struct Hairline: View {
    var vertical = false
    var color: Color = Theme.divider
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle().fill(color)
            .frame(width: vertical ? 1 / scale : nil, height: vertical ? nil : 1 / scale)
    }
}

// MARK: - States (§4.8)

struct EmptyState: View {
    var title: String
    var message: String
    var symbol: String? = "tray"
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Theme.iconTertiary)
                    .frame(height: 64)
                    .padding(.bottom, 16)
            }
            Text(title).textStyle(.emptyTitle).foregroundStyle(Theme.textPrimary)
            Text(message)
                .textStyle(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let retry {
                Button("Retry", action: retry).buttonStyle(.outline(height: Theme.Metrics.buttonMedium)).padding(.top, 16)
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 8 skeleton rows at the row pitch, widths from a fixed sequence so nothing jumps.
struct SkeletonRows: View {
    var senderX: CGFloat
    var subjectX: CGFloat
    @State private var dim = false
    private static let widths: [(CGFloat, CGFloat)] = [(118, 284), (96, 212), (130, 300), (104, 246), (122, 188), (90, 320), (112, 262), (126, 230)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.widths.indices, id: \.self) { i in
                ZStack(alignment: .leading) {
                    bar(Self.widths[i].0).offset(x: senderX)
                    bar(Self.widths[i].1).offset(x: subjectX)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.rowHeight, alignment: .leading)
            }
        }
        .opacity(dim ? 0.5 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true } }
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.skeleton).frame(width: width, height: 14)
    }
}

/// Three bouncing dots for inline loading (search, sending).
struct DotsLoader: View {
    @State private var up = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.textQuaternary).frame(width: 4, height: 4)
                    .offset(y: up ? -2 : 0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.2), value: up)
            }
        }
        .onAppear { up = true }
    }
}

// MARK: - Toast (§5.8)

struct ToastHost: View {
    @Environment(AppState.self) private var app
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .onHover { hovering = $0 }
                    .task(id: "\(toast.id)\(hovering)") {
                        guard !hovering else { return }
                        try? await Task.sleep(for: toast.duration)
                        if !Task.isCancelled { app.dismissToast(toast.id) }
                    }
                    .transition(.offset(y: 8).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .animation(Theme.Motion.standard, value: app.toast?.id)
    }
}

struct ToastView: View {
    let toast: Toast
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).textStyle(.bodyMedium).foregroundStyle(Theme.textContrast).lineLimit(1)
            if let title = toast.actionTitle, let action = toast.action {
                Button {
                    action()
                    app.dismissToast(toast.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(title).textStyle(.bodyMedium).foregroundStyle(Theme.textContrastSecondary)
                        Text("Z").textStyle(.keycap).foregroundStyle(Theme.textContrastSecondary.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 240, minHeight: Theme.Metrics.toastHeight, alignment: .leading)
        .background(Theme.darkSurface, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .elevation(.l2, radius: Theme.Metrics.radius)
    }
}

// MARK: - Modifiers

extension View {
    /// Background that fades in on hover (100 ms) and out instantly (§6).
    func hoverFill(_ color: Color = Theme.hover, radius: CGFloat = Theme.Metrics.radius) -> some View {
        modifier(HoverFill(color: color, radius: radius))
    }
}

private struct HoverFill: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? color : .clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
    }
}

// MARK: - Sidebar-style item (§5.1), also used by the settings nav

struct SidebarItem<Icon: View>: View {
    let title: String
    var count: Int = 0
    var isSelected = false
    var depth = 0
    @ViewBuilder var icon: Icon
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: Theme.Metrics.iconMedium, height: Theme.Metrics.iconMedium)
                Text(title)
                    .textStyle(.body)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .textStyle(.smallMedium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 3)
                }
            }
            .padding(.leading, 8 + 12 * CGFloat(depth))
            .padding(.trailing, 9)
            .frame(height: Theme.Metrics.sidebarItemHeight)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Metrics.sidebarItemInset)
        .padding(.vertical, (Theme.Metrics.sidebarItemPitch - Theme.Metrics.sidebarItemHeight) / 2)
        .onHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
    }

    private var background: Color {
        isSelected ? Theme.rowHover : hovering ? Theme.hover : .clear
    }
}

/// A 16 pt outline SF Symbol in the icon slot.
struct SlotIcon: View {
    let systemName: String
    var tint: Color = Theme.iconSecondary

    var body: some View {
        Image(systemName: systemName).font(.system(size: 14, weight: .regular)).foregroundStyle(tint)
    }
}
