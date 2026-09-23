@testable import MailCore
import XCTest

@MainActor
final class CommandTests: XCTestCase {
    func testShortcutParsingAndDisplay() {
        XCTAssertEqual(Shortcut("g i").display, "G then I")
        XCTAssertEqual(Shortcut("cmd+k").display, "⌘K")
        XCTAssertEqual(Shortcut("cmd+L").display, "⌘⇧L")
        XCTAssertEqual(Shortcut("U").display, "⇧U")
        XCTAssertEqual(Shortcut("#").strokes, [KeyStroke("#")])
        XCTAssertEqual(Shortcut("cmd+\\").strokes, [KeyStroke("\\", command: true)])
    }

    func testChordMatching() {
        let registry = CommandRegistry()
        var ran: [String] = []
        registry.register([
            Command(id: "a", title: "Go", group: .navigation, shortcuts: ["g i"]) { ran.append("a") },
            Command(id: "b", title: "Archive", group: .thread, shortcuts: ["e"]) { ran.append("b") },
            Command(id: "c", title: "Hidden", group: .misc, shortcuts: ["x"], isAvailable: { false }) { ran.append("c") },
        ])
        guard case .prefix = registry.match([KeyStroke("g")]) else { return XCTFail() }
        guard case .command(let c) = registry.match([KeyStroke("g"), KeyStroke("i")]) else { return XCTFail() }
        c.perform()
        guard case .none = registry.match([KeyStroke("x")]) else { return XCTFail("unavailable commands don't match") }
        XCTAssertEqual(registry.paletteCommands.map(\.id), ["b", "a"], "grouped Thread before Navigation")
        registry.register([Command(id: "b", title: "Replaced", group: .thread) {}])
        XCTAssertEqual(registry["b"]?.title, "Replaced")
        XCTAssertEqual(ran, ["a"])
    }
}
