import SwiftUI

// Provisional Notion palette; confirm against mail.notion.so computed styles.
enum Theme {
    static let body = Font.system(size: 14)
    static let listSender = Font.system(size: 14, weight: .semibold)
    static let listSubject = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let mono = Font.custom("iA Writer Mono S", size: 13)

    static let text = Color(light: .init(red: 55/255, green: 53/255, blue: 47/255), dark: .white.opacity(0.81))
    static let secondary = Color(light: .init(red: 55/255, green: 53/255, blue: 47/255, opacity: 0.65), dark: .white.opacity(0.46))
    static let background = Color(light: .white, dark: .init(red: 25/255, green: 25/255, blue: 25/255))
    static let sidebar = Color(light: .init(red: 247/255, green: 247/255, blue: 245/255), dark: .init(red: 32/255, green: 32/255, blue: 32/255))
    static let selection = Color(light: .init(red: 35/255, green: 131/255, blue: 226/255, opacity: 0.14), dark: .init(red: 35/255, green: 131/255, blue: 226/255, opacity: 0.28))

    static let rowHeight: CGFloat = 36
    static let gutter: CGFloat = 12
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}
