import AppKit
import MailCore

/// Turns key presses into registered commands, with a 1 s window for chords like "g i".
/// While a text field has focus only ⌘-shortcuts (and Esc) are routed, minus text editing ones.
@MainActor
final class KeyRouter {
    private weak var app: AppState?
    private var monitor: Any?
    private var pending: [KeyStroke] = []
    private var pendingAt = Date.distantPast
    private static let textEditingKeys: Set<String> = ["a", "c", "v", "x", "z", "Z"]

    func install(_ app: AppState) {
        self.app = app
        pending = []
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event ran (or started) a command and must not reach the responder chain.
    private func handle(_ event: NSEvent) -> Bool {
        guard let app, let stroke = Self.stroke(event) else { return false }
        if stroke.key == "esc", !stroke.command {
            pending = []
            return app.dismissTopmost()
        }
        let typing = NSApp.keyWindow?.firstResponder is NSText
        if typing, !stroke.command || Self.textEditingKeys.contains(stroke.key) { return false }

        if Date.now.timeIntervalSince(pendingAt) > 1 { pending = [] }
        pending.append(stroke)
        switch app.commands.match(pending) {
        case .command(let command):
            pending = []
            command.perform()
            return true
        case .prefix:
            pendingAt = .now
            return true
        case .none:
            let wasChord = pending.count > 1
            pending = []
            if wasChord, case .command(let command) = app.commands.match([stroke]) {
                command.perform()
                return true
            }
            return false
        }
    }

    static func stroke(_ event: NSEvent) -> KeyStroke? {
        let flags = event.modifierFlags
        let named: [UInt16: String] = [36: "enter", 76: "enter", 53: "esc", 125: "down", 126: "up", 123: "left", 124: "right",
                                       48: "tab", 51: "delete", 49: "space"]
        var key = named[event.keyCode] ?? event.charactersIgnoringModifiers
        if flags.contains(.shift), key?.count == 1 { key = key?.uppercased() }
        guard let key, !key.isEmpty else { return nil }
        return KeyStroke(key, command: flags.contains(.command), option: flags.contains(.option), control: flags.contains(.control))
    }
}
