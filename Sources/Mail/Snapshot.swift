import AppKit
import MailCore

/// MAIL_SNAPSHOT harness: puts the app in the state for MAIL_SCREEN, waits for it to render,
/// captures this window to the PNG path and exits.
@MainActor
enum Snapshot {
    private static var started = false

    static func run(_ app: AppState, window: NSWindow) {
        guard !started, let path = Launch.snapshotPath else { return }
        started = true
        window.setContentSize(Launch.windowSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        prepare(app, screen: Launch.screen)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
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
        case "compose": app.compose = ComposeRequest(.new(to: []))
        case "palette": app.palette = .commands
        case "search": app.search("offsite")
        case "empty": app.go(to: .spam)
        case "settings": app.settings = .signature
        case "syncing":
            try? app.store.deleteMessages(ids: (try? app.store.db.read { try Message.fetchAll($0).map(\.id) }) ?? [])
            for draft in (try? app.store.db.read(Store.drafts)) ?? [] { try? app.store.deleteDraft(id: draft.id) }
            app.isAwaitingFirstSync = true
            app.syncStatus = .backfilling(fetched: 1_240, total: 4_810)
        case "offline": app.syncStatus = .offline
        case "syncfailed": app.syncStatus = .failed("Gmail 503: Backend Error")
        default: break
        }
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        try? FileManager.default.removeItem(atPath: path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-l", "\(window.windowNumber)", "-o", "-x", path]
        if (try? p.run()) != nil { p.waitUntilExit() }
        if FileManager.default.fileExists(atPath: path), p.terminationStatus == 0 { return true }
        // Fallback when screen capture isn't permitted: render the content view (no window chrome).
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
