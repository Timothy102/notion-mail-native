import Foundation
#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

/// The few AppKit / UIKit calls MailCore makes, so the rest of it builds for both.
public enum Platform {
    @MainActor public static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor public static var didBecomeActive: Notification.Name {
        #if os(macOS)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    public static func image(contentsOf url: URL) -> PlatformImage? {
        #if os(macOS)
        NSImage(contentsOf: url)
        #else
        UIImage(contentsOfFile: url.path)
        #endif
    }

    /// Any image format ImageIO reads, re-encoded as PNG.
    public static func png(_ data: Data) -> Data? {
        #if os(macOS)
        NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        #else
        UIImage(data: data)?.pngData()
        #endif
    }
}
