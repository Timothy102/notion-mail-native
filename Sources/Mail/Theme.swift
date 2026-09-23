import SwiftUI
import CoreText

/// Tokens from design/SPEC.md. Views read colors, type, metrics and motion only from here.
enum Theme {
    // MARK: Surfaces
    static let page = Color(0xFFFFFF, dark: 0x191919)
    static let wash = Color(0xF7F7F5, dark: 0x202020)
    static let elevated = Color(0xFFFFFF, dark: 0x252525)
    static let darkSurface = Color(0x1D1B16, dark: 0x252525)
    static let scrim = Color(0x000000, 0.56, dark: 0x000000, 0.56)

    // MARK: Text
    static let textPrimary = Color(0x1D1B16, dark: 0xD3D3D3)
    static let textRead = Color(0x1D1B16, dark: 0xD3D3D3, 0.85)
    static let textSecondary = Color(0x5F5E5B, dark: 0x9B9B9B)
    static let textTertiary = Color(0x91918E, dark: 0x7F7F7F)
    static let textQuaternary = Color(0xACABA9, dark: 0xFFFFFF, 0.13)
    static let textContrast = Color(0xFFFFFF, dark: 0xFFFFFF)
    static let textContrastSecondary = Color(0xD3D3D3, dark: 0xD3D3D3)
    static let textBlue = Color(0x2383E2, dark: 0x2383E2)
    static let textRed = Color(0xD44C47, dark: 0xDE5550)
    static let textOrange = Color(0xD9730D, dark: 0xC77D48)

    // MARK: Icons
    static let iconPrimary = Color(0x32302C, dark: 0xFFFFFF, 0.81)
    static let iconSecondary = Color(0x91918E, dark: 0xFFFFFF, 0.445)
    static let iconTertiary = Color(0xC7C6C4, dark: 0xFFFFFF, 0.283)
    static let inboxRed = Color(0xE16259, dark: 0xE16259)

    // MARK: Fills and tints
    static let accent = Color(0x2383E2, dark: 0x2383E2)
    static let accentHover = Color(0x2076CB, dark: 0x2076CB)
    static let accentPressed = Color(0x1C69B5, dark: 0x1C69B5)
    static let hover = Color(0x000000, 0.04, dark: 0xFFFFFF, 0.055)
    static let pressed = Color(0x000000, 0.08, dark: 0xFFFFFF, 0.13)
    static let rowHover = Color(0x000000, 0.05, dark: 0xFFFFFF, 0.055)
    static let rowSelected = Color(0x2383E2, 0.14, dark: 0x2383E2, 0.14)
    static let rowSelectedHover = Color(0x2383E2, 0.21, dark: 0x2383E2, 0.21)
    static let markBackground = Color(0xE7F3F8, dark: 0x1B1F22)
    static let skeleton = Color(0xF1F1EF, dark: 0x373737)
    static let textSelection = Color(0x2383E2, 0.28, dark: 0x2383E2, 0.28)

    // MARK: Borders
    static let divider = Color(0xE3E2E0, 0.5, dark: 0xFFFFFF, 0.055)
    static let border = Color(0xE3E2E0, dark: 0xFFFFFF, 0.13)
    static let elevationRing = Color(0xE3E2E0, 0.5, dark: 0x313131)
    static let focusRingOuter = Color(0x2383E2, 0.35, dark: 0x2383E2, 0.35)

    enum Metrics {
        static let windowMin = CGSize(width: 900, height: 600)
        static let windowDefault = CGSize(width: 1280, height: 800)

        static let sidebarWidth: CGFloat = 240
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarMaxWidth: CGFloat = 480
        static let titleBarHeight: CGFloat = 40
        static let sidebarItemHeight: CGFloat = 30
        static let sidebarItemPitch: CGFloat = 32
        static let sidebarItemInset: CGFloat = 8
        static let sidebarFooterHeight: CGFloat = 45

        static let paneHeaderHeight: CGFloat = 48
        static let rowHeight: CGFloat = 38
        static let rowInset: CGFloat = 14
        static let rowRadius: CGFloat = 8
        static let groupHeaderHeight: CGFloat = 56
        static let groupHairlineY: CGFloat = 48
        static let checkboxX: CGFloat = 24
        static let checkboxSize: CGFloat = 14
        static let unreadDotCenterX: CGFloat = 55
        static let unreadDotSize: CGFloat = 6
        static let senderX: CGFloat = 69
        static let senderGap: CGFloat = 14
        static let dateTrailing: CGFloat = 54
        static let dateColumnWidth: CGFloat = 120
        static let hoverPillHeight: CGFloat = 32
        static let hoverActionPitch: CGFloat = 30

        /// Sender column width: 16% of the window width, clamped.
        static func senderWidth(windowWidth: CGFloat) -> CGFloat {
            min(max((windowWidth * 0.16).rounded(), 150), 260)
        }

        static let peekMinWidth: CGFloat = 520
        static let peekFraction: CGFloat = 0.58
        static let peekToolbarHeight: CGFloat = 44
        static let readerMaxWidth: CGFloat = 800
        static let readerPadding: CGFloat = 42
        static let collapsedMessageHeight: CGFloat = 44
        static let selectedMessageBar: CGFloat = 4

        static let composerWidth: CGFloat = 600
        static let composerInset: CGFloat = 16
        static let composerTop: CGFloat = 142
        static let composerFieldHeight: CGFloat = 32
        static let composerFooterHeight: CGFloat = 60
        static let sendButtonWidth: CGFloat = 80

        static let paletteWidth: CGFloat = 720
        static let paletteMaxHeight: CGFloat = 520
        static let paletteTopFraction: CGFloat = 0.125
        static let paletteInputHeight: CGFloat = 48
        static let paletteRowHeight: CGFloat = 36
        static let paletteFooterHeight: CGFloat = 32

        static let menuWidth: CGFloat = 240
        static let menuItemHeight: CGFloat = 28
        static let toastHeight: CGFloat = 40
        static let toastBottom: CGFloat = 20

        static let chipHeightList: CGFloat = 18
        static let chipHeightReader: CGFloat = 20
        static let chipMaxWidth: CGFloat = 122
        static let chipRadius: CGFloat = 3

        static let buttonSmall: CGFloat = 28
        static let buttonMedium: CGFloat = 32
        static let buttonRadius: CGFloat = 6
        static let iconButton: CGFloat = 28

        static let radiusSmall: CGFloat = 4
        static let radius: CGFloat = 6
        static let radiusMenu: CGFloat = 8
        static let radiusLarge: CGFloat = 12

        static let iconMini: CGFloat = 14
        static let iconSmall: CGFloat = 16
        static let iconMedium: CGFloat = 20
        static let iconLarge: CGFloat = 24
    }

    enum Motion {
        static let standard = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.2)
        static let hover = Animation.easeOut(duration: 0.1)
        static let fast = Animation.easeOut(duration: 0.15)
    }
}

// MARK: - Typography

struct TextStyle: Sendable {
    enum Face: Sendable { case system, rounded, mono }

    let size: CGFloat
    let weight: NSFont.Weight
    let lineHeight: CGFloat
    var face: Face = .system
    var tabular = false

    static let threadTitle = TextStyle(size: 22, weight: .semibold, lineHeight: 26)
    static let sectionTitle = TextStyle(size: 17, weight: .semibold, lineHeight: 22)
    static let emptyTitle = TextStyle(size: 17, weight: .medium, lineHeight: 22)
    static let paletteInput = TextStyle(size: 18, weight: .regular, lineHeight: 24)
    static let body = TextStyle(size: 14, weight: .regular, lineHeight: 20)
    static let bodyMedium = TextStyle(size: 14, weight: .medium, lineHeight: 20)
    static let bodySemibold = TextStyle(size: 14, weight: .semibold, lineHeight: 20)
    static let list = TextStyle(size: 13, weight: .regular, lineHeight: 16)
    static let listUnread = TextStyle(size: 13, weight: .semibold, lineHeight: 16)
    static let listSecondary = TextStyle(size: 13, weight: .regular, lineHeight: 16, tabular: true)
    static let groupHeader = TextStyle(size: 13, weight: .medium, lineHeight: 16)
    static let small = TextStyle(size: 12, weight: .regular, lineHeight: 16)
    static let smallMedium = TextStyle(size: 12, weight: .medium, lineHeight: 16)
    static let smallSemibold = TextStyle(size: 12, weight: .semibold, lineHeight: 16)
    static let keycap = TextStyle(size: 12, weight: .regular, lineHeight: 16, face: .mono)
    static let mailBody = TextStyle(size: 14, weight: .regular, lineHeight: 24)

    static func avatarInitial(size avatar: CGFloat) -> TextStyle {
        TextStyle(size: (avatar * 0.6).rounded(), weight: .semibold, lineHeight: avatar, face: .rounded)
    }

    var nsFont: NSFont {
        switch face {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .mono:
            _ = BundledFonts.registered
            return NSFont(name: "iAWriterMonoS-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    var font: Font {
        let font = Font(nsFont as CTFont)
        return tabular ? font.monospacedDigit() : font
    }

    /// Extra space between lines so multi-line text lands on `lineHeight`.
    var lineSpacing: CGFloat {
        let f = nsFont
        return max(0, lineHeight - (f.ascender - f.descender + f.leading))
    }
}

extension View {
    /// Applies font and line height. Single lines get a fixed-height frame so rows never jump.
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
            .lineSpacing(style.lineSpacing)
            .frame(minHeight: style.lineHeight)
    }
}

private enum BundledFonts {
    static let registered: Bool = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else { return false }
        return urls.allSatisfy { CTFontManagerRegisterFontsForURL($0 as CFURL, .process, nil) }
    }()
}

// MARK: - Label chips

enum LabelColor: String, CaseIterable, Sendable {
    case lightGray, gray, brown, orange, yellow, green, blue, purple, pink, red

    var fill: Color {
        switch self {
        case .lightGray: Color(0xF1F1EF, dark: 0x373737)
        case .gray: Color(0xE3E2E0, dark: 0x5A5A5A)
        case .brown: Color(0xEEE0DA, dark: 0x4A3228)
        case .orange: Color(0xFADEC9, dark: 0x5C3B23)
        case .yellow: Color(0xFDECC8, dark: 0x564328)
        case .green: Color(0xDBEDDB, dark: 0x243D30)
        case .blue: Color(0xD3E5EF, dark: 0x143A4E)
        case .purple: Color(0xE8DEEE, dark: 0x3C2D49)
        case .pink: Color(0xF5E0E9, dark: 0x4E2C3C)
        case .red: Color(0xFFE2DD, dark: 0x522E2A)
        }
    }

    var text: Color {
        switch self {
        case .lightGray: Theme.textPrimary
        case .gray: Color(0x32302C, dark: 0xFFFFFF, 0.87)
        case .brown: Color(0x442A1E, dark: 0xFFFFFF, 0.87)
        case .orange: Color(0x49290E, dark: 0xFFFFFF, 0.87)
        case .yellow: Color(0x402C1B, dark: 0xFFFFFF, 0.87)
        case .green: Color(0x1C3829, dark: 0xFFFFFF, 0.87)
        case .blue: Color(0x183347, dark: 0xFFFFFF, 0.87)
        case .purple: Color(0x412454, dark: 0xFFFFFF, 0.87)
        case .pink: Color(0x4C2337, dark: 0xFFFFFF, 0.87)
        case .red: Color(0x5D1715, dark: 0xFFFFFF, 0.87)
        }
    }
}

// MARK: - Elevation

enum Elevation: Sendable {
    case l1, l2, l3, l4

    private struct Layer { let y: CGFloat; let blur: CGFloat; let alpha: Double }

    private func layers(_ scheme: ColorScheme) -> [Layer] {
        switch (self, scheme) {
        case (.l1, .dark): [Layer(y: 2, blur: 4, alpha: 0.08)]
        case (.l1, _): [Layer(y: 2, blur: 4, alpha: 0.04)]
        case (.l2, .dark): [Layer(y: 4, blur: 12, alpha: 0.16)]
        case (.l2, _): [Layer(y: 4, blur: 12, alpha: 0.08)]
        case (.l3, .dark): [Layer(y: 12, blur: 36, alpha: 0.40)]
        case (.l3, _): [Layer(y: 2, blur: 4, alpha: 0.06), Layer(y: 12, blur: 32, alpha: 0.12)]
        case (.l4, .dark): [Layer(y: 20, blur: 48, alpha: 0.56)]
        case (.l4, _): [Layer(y: 4, blur: 12, alpha: 0.14), Layer(y: 32, blur: 48, alpha: 0.28)]
        }
    }

    fileprivate struct Modifier: ViewModifier {
        let level: Elevation
        let radius: CGFloat
        @Environment(\.colorScheme) private var scheme

        func body(content: Content) -> some View {
            let layers = level.layers(scheme)
            let near = layers[0]
            let far = layers.count > 1 ? layers[1] : Layer(y: 0, blur: 0, alpha: 0)
            content
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.elevationRing, lineWidth: 1))
                .shadow(color: .black.opacity(near.alpha), radius: near.blur / 2, y: near.y)
                .shadow(color: .black.opacity(far.alpha), radius: far.blur / 2, y: far.y)
        }
    }
}

extension View {
    /// Ring plus drop shadows for floating surfaces. Apply after the background and clip shape.
    func elevation(_ level: Elevation, radius: CGFloat) -> some View {
        modifier(Elevation.Modifier(level: level, radius: radius))
    }
}

// MARK: - Color construction

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// sRGB color that resolves per appearance.
    init(_ light: UInt32, _ lightAlpha: CGFloat = 1, dark: UInt32, _ darkAlpha: CGFloat = 1) {
        let lightColor = NSColor(hex: light, alpha: lightAlpha)
        let darkColor = NSColor(hex: dark, alpha: darkAlpha)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}
