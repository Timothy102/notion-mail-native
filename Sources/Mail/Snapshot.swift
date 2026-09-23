import AppKit
import MailCore
import SwiftUI

/// MAIL_SNAPSHOT harness: puts the app in the state for MAIL_SCREEN, waits for it to render,
/// captures this window to the PNG path and exits.
@MainActor
enum Snapshot {
    private static var started = false

    static func run(_ app: AppState, window: NSWindow) {
        guard !started, let path = Launch.snapshotPath else { return }
        started = true
        place(window)
        prepare(app, screen: Launch.screen)
        if Launch.screen == "calendar" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scrollSidebarToEnd(window) }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            place(window)
            try? await Task.sleep(for: .seconds(1.1))
            let ok = capture(window, to: path)
            if !ok { FileHandle.standardError.write(Data("snapshot failed: \(path)\n".utf8)) }
            exit(ok ? 0 : 1)
        }
    }

    static func prepare(_ app: AppState, screen: String) {
        switch screen {
        case "thread":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if let thread = inbox.first(where: { $0.messageCount >= 5 }) ?? inbox.first { app.open(thread.id) }
        case "thread-selected":
            prepare(app, screen: "thread")
            app.moveMessageSelection(-1)
            app.moveMessageSelection(-1)
        case "thread-long":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if let thread = inbox.max(by: { $0.subject.count < $1.subject.count }) { app.open(thread.id) }
        case "palette-thread":
            prepare(app, screen: "thread")
            app.palette = .commands
        case "search-loading":
            SearchView.snapshotSearching = true
            app.search(Launch.env["MAIL_QUERY"] ?? "from:ana has:drive")
        case "rows":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if inbox.count > 6 {
                app.selectedThreadIds = [inbox[2].id, inbox[3].id]
                ThreadRow.snapshotHoverId = inbox[5].id
            }
        case "toast":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if inbox.count > 2 {
                app.visibleThreadIds = inbox.map(\.id)
                app.focusedThreadId = inbox[1].id
                app.commands.run("thread.archive")
            }
        case "attachments":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if let thread = inbox.first(where: { $0.subject.hasPrefix("Contract draft") }) { app.open(thread.id) }
        case "html", "labels":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if let thread = inbox.first(where: { $0.subject.hasPrefix("The Sunday Stack") }) { app.open(thread.id) }
            if screen == "labels" { app.isLabelPickerOpen = true }
        case "quotes", "quotes-expanded", "quotes-text", "quotes-text-expanded", "reply-quotes":
            let subject = screen.hasPrefix("quotes-text") ? "Talk proposal" : "Brand refresh"
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            if let thread = inbox.first(where: { $0.subject.contains(subject) }) { app.open(thread.id) }
            QuotedHistory.snapshotExpanded = screen.hasSuffix("expanded")
            if screen == "reply-quotes" {
                ComposeModel.snapshotShowsQuoted = true
                app.commands.run("thread.replyAll")
            }
        case "compose": app.compose = ComposeRequest(.new(to: []))
        case "compose-draft":
            if let draft = (try? app.store.db.read(Store.drafts))?.first { app.compose = ComposeRequest(.draft(id: draft.id)) }
        case "reply":
            prepare(app, screen: "thread")
            app.commands.run("thread.replyAll")
        case "palette": app.palette = Launch.env["MAIL_PALETTE"] == "search" ? .search : .commands
        case "search": app.search(Launch.env["MAIL_QUERY"] ?? "helio")
        case "empty": app.go(to: .spam)
        case "settings": app.settings = .signature
        case "syncing":
            try? app.store.deleteMessages(ids: (try? app.store.db.read { try Message.fetchAll($0).map(\.id) }) ?? [])
            for draft in (try? app.store.db.read(Store.drafts)) ?? [] { try? app.store.deleteDraft(id: draft.id) }
            app.isAwaitingFirstSync = true
            app.syncStatus = .backfilling(fetched: 1_240, total: 4_810)
        case "offline": app.syncStatus = .offline
        case "syncfailed": app.syncStatus = .failed("Gmail 503: Backend Error")
        case "integrations": app.settings = .integrations
        case "notion-save", "notion-link", "invite":
            let inbox = (try? app.store.db.read { try Store.threads($0, in: .inbox) }) ?? []
            let invite = inbox.first { $0.subject.hasPrefix("Invitation:") }
            guard let thread = screen == "invite" ? invite : inbox.first else { break }
            app.open(thread.id)
            if screen == "notion-save" { app.notionPicker = .save(threadId: thread.id) }
            if screen == "notion-link" { app.notionPicker = .link(threadId: thread.id) }
        default: break
        }
    }

    /// On the sharpest screen the window fits, never key (inactive chrome is expected). Runs again after launch
    /// because SwiftUI may restore a saved frame on another display.
    private static func place(_ window: NSWindow) {
        window.setContentSize(Launch.windowSize)
        let fitting = NSScreen.screens.filter { $0.visibleFrame.width >= window.frame.width && $0.visibleFrame.height >= window.frame.height }
        if let screen = fitting.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) ?? NSScreen.main {
            let area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: max(area.minY, area.midY - window.frame.height / 2)))
        }
        // Below the desktop: invisible to whoever is using the Mac, yet screencapture -l still reads its backing store.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.orderFrontRegardless()
    }

    /// The sidebar is the leftmost scroll view; its Calendar section sits below the fold.
    private static func scrollSidebarToEnd(_ window: NSWindow) {
        func scrollViews(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? v.subviews.flatMap(scrollViews) }
        guard let root = window.contentView,
              let sidebar = scrollViews(root).min(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let doc = sidebar.documentView else { return }
        doc.scroll(NSPoint(x: 0, y: doc.isFlipped ? doc.bounds.maxY : 0))
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        for _ in 0..<3 {
            try? FileManager.default.removeItem(atPath: path)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", path]
            if (try? p.run()) != nil { p.waitUntilExit() }
            if FileManager.default.fileExists(atPath: path), p.terminationStatus == 0 { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        // Fallback when screen capture isn't permitted: render the content view (no window chrome).
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

/// Snapshot runs never show SwiftUI's window: this one is below the desktop from before its first frame,
/// so nothing flashes on the user's screen while screencapture -l still reads it.
@MainActor
final class SnapshotLauncher: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Launch.snapshotPath != nil else { return }
        let app = AppState.launch()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Launch.windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        window.contentView = NSHostingView(rootView: RootView().environment(app))
        window.orderFrontRegardless()
        self.window = window
    }
}
