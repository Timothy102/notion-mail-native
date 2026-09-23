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
                .textStyle(kind == .primary ? .bodySemibold : .body)
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
                .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h && isEnabled } }
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
                .font(.glyph(glyph))
                .foregroundStyle(isEnabled ? tint : Theme.iconTertiary)
                .frame(width: Theme.Metrics.iconButton, height: Theme.Metrics.iconButton)
                .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h && isEnabled } }
        .help(help ?? "")
    }
}

extension Font {
    /// SF Symbol sized so its ink fills a `glyph`-point icon box, at Notion's stroke weight.
    static func glyph(_ glyph: CGFloat) -> Font { .system(size: (glyph * 0.94).rounded(), weight: .medium) }
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

/// Circle with an initial (§5.13), or `image` cropped to the circle. `fill` nil = neutral contact avatar.
struct Avatar: View {
    let name: String
    var size: CGFloat = 20
    var fill: Color?
    var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 0.5) }
        } else {
            initialCircle
        }
    }

    private var initialCircle: some View {
        let initial = name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        return Circle()
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
    /// The mailbox-and-dog drawing; errors show text only.
    var art = true
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if art {
                ZStack {
                    Self.layer("mailbox", Theme.textPrimary)
                    Self.layer("dog-fill", Theme.page)
                    Self.layer("dog", Theme.textPrimary)
                }
                .frame(width: 200, height: 130)
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

extension EmptyState {
    /// One bundled 400 × 260 mask, tinted so the ink follows the theme.
    private static func layer(_ name: String, _ color: Color) -> some View {
        let image = Bundle.appResources.url(forResource: name, withExtension: "png", subdirectory: "Art").flatMap(NSImage.init(contentsOf:))
        return Image(nsImage: image ?? NSImage()).resizable().renderingMode(.template).foregroundStyle(color)
    }
}

/// Skeleton rows at the row pitch with bars in the sender, subject and date columns. Widths come from a
/// fixed sequence so nothing jumps; one soft highlight sweeps across all of them (static under Reduce Motion).
struct SkeletonRows: View {
    var layout: RowLayout
    var count = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let widths: [(CGFloat, CGFloat, CGFloat)] = [(118, 284, 44), (96, 212, 38), (130, 300, 44), (104, 246, 52),
                                                                (122, 188, 38), (90, 320, 44), (112, 262, 52), (126, 230, 38)]
    private static let sweep: Double = 1.4

    var body: some View {
        bars
            .overlay {
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.sweep) / Self.sweep
                        highlight(phase: phase)
                    }
                    .mask(bars)
                }
            }
            .accessibilityHidden(true)
    }

    private var bars: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let (sender, subject, date) = Self.widths[i % Self.widths.count]
                let dateX = layout.paneWidth - Theme.Metrics.dateTrailing - date
                ZStack(alignment: .leading) {
                    bar(sender).offset(x: layout.senderX)
                    bar(max(0, min(subject, dateX - 32 - layout.subjectX))).offset(x: layout.subjectX)
                    bar(date).offset(x: dateX)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.rowHeight, maxHeight: Theme.Metrics.rowHeight, alignment: .leading)
                .opacity(1 - 0.6 * Double(i) / Double(max(count, 12)))
            }
        }
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.skeleton).frame(width: width, height: 14)
    }

    /// A band 40% of the width, eased so it lingers softly at the edges.
    private func highlight(phase: Double) -> some View {
        GeometryReader { geo in
            let band = geo.size.width * 0.4
            let t = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
            LinearGradient(colors: [Theme.skeletonHighlight.opacity(0), Theme.skeletonHighlight, Theme.skeletonHighlight.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .offset(x: -band + (geo.size.width + band) * t)
        }
    }
}

/// Thin accent bar: determinate when `fraction` is known, a gliding segment otherwise.
struct LinearProgressBar: View {
    var fraction: Double?
    var height: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.progressTrack
                if let fraction {
                    Theme.accent
                        .frame(width: geo.size.width * max(0.02, min(1, fraction)))
                        .animation(.easeOut(duration: 0.6), value: fraction)
                } else if reduceMotion {
                    Theme.accent.opacity(0.4)
                } else {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let segment = geo.size.width * 0.3
                        Theme.accent
                            .frame(width: segment)
                            .offset(x: -segment + (geo.size.width + segment) * (1 - pow(1 - phase, 2)))
                    }
                }
            }
            .clipped()
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Syncing mail")
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "")
    }
}

/// 12 pt ring: fills to `fraction`, or spins a partial arc when it's unknown.
struct ProgressRing: View {
    var fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Theme.progressTrack, lineWidth: 1.75)
            if let fraction {
                Circle().trim(from: 0, to: max(0.04, min(1, fraction)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
            } else {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            }
        }
        .frame(width: 12, height: 12)
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
                    .onLiveHover { hovering = $0 }
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
    /// Placeholder drawn by us, in `Theme.placeholder`, because a TextField prompt ignores foregroundStyle.
    func placeholder(_ text: String, showing: Bool) -> some View {
        overlay(alignment: .leading) {
            if showing { Text(text).foregroundStyle(Theme.placeholder).lineLimit(1).allowsHitTesting(false) }
        }
    }

    /// `onHover` that snapshots ignore, so a capture never depends on where the pointer is.
    func onLiveHover(perform action: @escaping (Bool) -> Void) -> some View {
        onHover { if Launch.snapshotPath == nil { action($0) } }
    }

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
            .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
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
        .onLiveHover { h in withAnimation(h ? Theme.Motion.hover : nil) { hovering = h } }
    }

    private var background: Color {
        isSelected ? Theme.rowHover : hovering ? Theme.hover : .clear
    }
}

/// A 16 pt outline SF Symbol in the icon slot, or Notion's inbox tray for `InboxTray.symbol`.
struct SlotIcon: View {
    let systemName: String
    var tint: Color = Theme.iconSecondary

    var body: some View {
        if systemName == InboxTray.symbol {
            InboxTray().fill(tint, style: FillStyle(eoFill: true)).frame(width: 15, height: 15)
        } else {
            Image(systemName: systemName).font(.system(size: 14, weight: .regular)).foregroundStyle(tint)
        }
    }
}

/// Notion Mail's inbox glyph: a tray outline with a solid lip, traced from the 2x reference.
struct InboxTray: Shape {
    static let symbol = "notion.inbox"

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 15, sy = rect.height / 15
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.addLines([p(1.4, 0), p(13.6, 0), p(15, 9.6), p(15, 15), p(0, 15), p(0, 9.6)])
        path.closeSubpath()
        path.move(to: p(2.9, 1.6))
        path.addLine(to: p(12.1, 1.6))
        path.addLine(to: p(13.3, 9.9))
        path.addLine(to: p(9.5, 9.9))
        path.addQuadCurve(to: p(5.5, 9.9), control: p(7.5, 12.6))
        path.addLine(to: p(1.7, 9.9))
        path.closeSubpath()
        return path
    }
}

/// Left-to-right wrapping layout, items centred vertically within their line. With `minLastWidth`,
/// the last subview (an input) stretches to fill its line and wraps when less than that is left.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat?
    var minLastWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let used = frames.map(\.maxX).max() ?? 0
        let width = minLastWidth != nil ? (proposal.width ?? used) : min(proposal.width ?? used, used)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, subview) in zip(arrange(width: bounds.width, subviews: subviews), subviews) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var line: [Int] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        func closeLine() {
            for i in line { frames[i].origin.y = y + (lineHeight - frames[i].height) / 2 }
            y += lineHeight + (lineSpacing ?? spacing)
            line = []; x = 0; lineHeight = 0
        }
        for (i, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            let isStretching = minLastWidth != nil && i == subviews.count - 1
            if isStretching { size.width = minLastWidth ?? 0 }
            if !line.isEmpty, x + size.width > width { closeLine() }
            if isStretching, width.isFinite { size.width = max(width - x, size.width) }
            size.width = min(size.width, width)
            frames.append(CGRect(origin: CGPoint(x: x, y: 0), size: size))
            line.append(i)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        if !line.isEmpty { closeLine() }
        return frames
    }
}
