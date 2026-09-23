import MailCore
import SwiftUI
import UIKit

/// The Notion palette from design/SPEC.md §1 (same values as the Mac app's Theme), for UIKit trait-based light and dark.
/// Type is the system font with Dynamic Type; metrics follow iOS conventions rather than the Mac's.
enum Theme {
    static let page = Color(0xFFFFFF, dark: 0x191919)
    static let wash = Color(0xF7F7F5, dark: 0x202020)
    static let elevated = Color(0xFFFFFF, dark: 0x252525)
    static let card = Color(0xFFFFFF, dark: 0x252525)

    static let textPrimary = Color(0x1D1B16, dark: 0xD3D3D3)
    static let textSecondary = Color(0x5F5E5B, dark: 0x9B9B9B)
    static let textTertiary = Color(0x91918E, dark: 0x7F7F7F)
    static let placeholder = Color(0xACABA9, dark: 0xFFFFFF, 0.283)
    static let textRed = Color(0xD44C47, dark: 0xDE5550)

    static let iconPrimary = Color(0x32302C, dark: 0xFFFFFF, 0.81)
    static let iconSecondary = Color(0x91918E, dark: 0xFFFFFF, 0.445)
    static let inboxRed = Color(0xE16259, dark: 0xE16259)

    static let accent = Color(0x2383E2, dark: 0x2383E2)
    static let hover = Color(0x000000, 0.04, dark: 0xFFFFFF, 0.055)
    static let pressed = Color(0x000000, 0.08, dark: 0xFFFFFF, 0.13)
    static let skeleton = Color(0xF1F1EF, dark: 0x373737)
    static let skeletonHighlight = Color(0xFAFAF9, dark: 0x434343)
    static let markBackground = Color(0xE7F3F8, dark: 0x1B2E41)

    static let divider = Color(0xE3E2E0, 0.5, dark: 0xFFFFFF, 0.055)
    static let border = Color(0xE3E2E0, dark: 0xFFFFFF, 0.13)

    // Swipe action fills: Notion's label hues, deep enough for white glyphs.
    static let swipeArchive = Color(0x448361, dark: 0x3F7A5A)
    static let swipeTrash = Color(0xD44C47, dark: 0xC4453F)
    static let swipeRemind = Color(0xD9730D, dark: 0xC06A1B)
    static let swipeRead = Color(0x2383E2, dark: 0x2383E2)
    static let swipeStar = Color(0xCB912F, dark: 0xB88A3E)
}

enum LabelColor: String {
    case lightGray, gray, brown, orange, yellow, green, blue, purple, pink, red

    init(named name: String?) {
        self = name.flatMap(LabelColor.init(rawValue:)) ?? .lightGray
    }

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

    var dot: Color {
        switch self {
        case .lightGray: Color(0xACABA9, dark: 0x7F7F7F)
        case .gray: Color(0x91918E, dark: 0x9B9B9B)
        case .brown: Color(0x9F6B53, dark: 0xBA856F)
        case .orange: Color(0xD9730D, dark: 0xC77D48)
        case .yellow: Color(0xCB912F, dark: 0xCA984D)
        case .green: Color(0x448361, dark: 0x529E72)
        case .blue: Color(0x337EA9, dark: 0x379AD3)
        case .purple: Color(0x9065B0, dark: 0x9D68D3)
        case .pink: Color(0xC14C8A, dark: 0xD15796)
        case .red: Color(0xD44C47, dark: 0xDF5452)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// `rgba(…)` for this color in light or dark, for the mail body's CSS.
    func css(dark: Bool) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "rgba(%d,%d,%d,%.3f)", Int(r * 255), Int(g * 255), Int(b * 255), a)
    }
}

extension Color {
    /// sRGB color that resolves per trait collection.
    init(_ light: UInt32, _ lightAlpha: CGFloat = 1, dark: UInt32, _ darkAlpha: CGFloat = 1) {
        let lightColor = UIColor(hex: light, alpha: lightAlpha), darkColor = UIColor(hex: dark, alpha: darkAlpha)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

extension ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Mailbox {
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .drafts: "doc"
        case .all: "tray.2"
        case .spam: "exclamationmark.octagon"
        case .trash: "trash"
        case .label: "tag"
        }
    }

    static let system: [Mailbox] = [.inbox, .starred, .all, .sent, .drafts, .spam, .trash]
}
