import Foundation
import Observation

/// One key press. `key` is the character as typed with Shift applied ("j", "U", "#", "?")
/// or a named key: "enter", "esc", "up", "down", "left", "right", "space", "tab", "delete".
public struct KeyStroke: Hashable, Sendable {
    public var key: String
    public var command = false
    public var option = false
    public var control = false

    public init(_ key: String, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.option = option
        self.control = control
    }

    /// "⌘⇧L", "⇧U", "E", "#", "↵".
    public var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        let named = ["enter": "↵", "esc": "Esc", "up": "↑", "down": "↓", "left": "←", "right": "→", "space": "Space", "tab": "⇥", "delete": "⌫"]
        let isShiftedLetter = key.count == 1 && key.uppercased() == key && key.lowercased() != key
        if command { s += "⌘" }
        if isShiftedLetter { s += "⇧" }
        return s + (named[key] ?? key.uppercased())
    }
}

/// One or more strokes pressed in sequence ("g i" = G then I).
///
/// Written as a string: strokes separated by spaces, modifiers joined with "+":
/// `"e"`, `"U"` (shift-u), `"#"`, `"g i"`, `"cmd+k"`, `"cmd+L"` (⌘⇧L), `"enter"`, `"cmd+\\"`.
public struct Shortcut: Hashable, Sendable, ExpressibleByStringLiteral {
    public var strokes: [KeyStroke]

    public init(_ strokes: [KeyStroke]) {
        self.strokes = strokes
    }

    public init(_ spec: String) {
        strokes = spec.split(separator: " ").map { token in
            var parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            var key = parts.removeLast()
            if key.isEmpty { key = "+" }
            return KeyStroke(key, command: parts.contains("cmd"), option: parts.contains("opt"), control: parts.contains("ctrl"))
        }
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// "G then I", "⌘K", "⇧U".
    public var display: String {
        strokes.map(\.display).joined(separator: " then ")
    }
}

public struct Command: Identifiable, Sendable {
    /// Palette group headers, in display order.
    public enum Group: String, Sendable, CaseIterable {
        case thread = "Thread"
        case inbox = "Inbox"
        case navigation = "Navigation"
        case integrations = "Integrations"
        case misc = "Misc"
    }

    public var id: String
    public var title: String
    public var group: Group
    /// SF Symbol name for the palette row.
    public var icon: String?
    /// All bindings; the first is the one shown as a hint.
    public var shortcuts: [Shortcut]
    /// Extra words the palette's fuzzy match considers.
    public var keywords: [String]
    /// false hides it from the palette (j/k and friends) while keeping its keys.
    public var showsInPalette: Bool
    public var isAvailable: @MainActor @Sendable () -> Bool
    public var perform: @MainActor @Sendable () -> Void

    public init(id: String, title: String, group: Group, icon: String? = nil, shortcuts: [Shortcut] = [], keywords: [String] = [],
                showsInPalette: Bool = true, isAvailable: @escaping @MainActor @Sendable () -> Bool = { true },
                perform: @escaping @MainActor @Sendable () -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.icon = icon
        self.shortcuts = shortcuts
        self.keywords = keywords
        self.showsInPalette = showsInPalette
        self.isAvailable = isAvailable
        self.perform = perform
    }
}

public enum KeyMatch {
    case none
    /// The strokes so far start a longer shortcut ("g"); wait for the next key.
    case prefix
    case command(Command)
}

/// Every action in the app. Features register their commands here; the palette lists them
/// and the key router dispatches shortcuts to them, so nobody edits a central switch.
@MainActor @Observable
public final class CommandRegistry {
    public private(set) var commands: [Command] = []

    public init() {}

    /// Adds commands, replacing any with the same id.
    public func register(_ new: [Command]) {
        let ids = Set(new.map(\.id))
        commands.removeAll { ids.contains($0.id) }
        commands += new
    }

    public func unregister(_ ids: [String]) {
        commands.removeAll { ids.contains($0.id) }
    }

    public subscript(id: String) -> Command? {
        commands.first { $0.id == id }
    }

    /// Available palette commands, grouped in `Group` order, registration order within a group.
    public var paletteCommands: [Command] {
        let available = commands.filter { $0.showsInPalette && $0.isAvailable() }
        return Command.Group.allCases.flatMap { g in available.filter { $0.group == g } }
    }

    @discardableResult
    public func run(_ id: String) -> Bool {
        guard let c = self[id], c.isAvailable() else { return false }
        c.perform()
        return true
    }

    public func match(_ strokes: [KeyStroke]) -> KeyMatch {
        var isPrefix = false
        for c in commands where c.isAvailable() {
            for s in c.shortcuts {
                if s.strokes == strokes { return .command(c) }
                if s.strokes.count > strokes.count, Array(s.strokes.prefix(strokes.count)) == strokes { isPrefix = true }
            }
        }
        return isPrefix ? .prefix : .none
    }
}
