import AppKit
import Foundation
import os

public struct GoogleUserinfo: Decodable, Sendable {
    public var name: String?
    public var picture: String?

    /// Google photo URLs end in a size option (`…/a/ACg8oc=s96-c`); this asks for `size` px, square-cropped.
    public static func sizedPicture(_ picture: String, size: Int = 256) -> URL? {
        guard var parts = URLComponents(string: picture), parts.scheme == "https" else { return nil }
        let path = parts.path
        let last = path.lastIndex(of: "/") ?? path.startIndex
        let base = path[last...].firstIndex(of: "=").map { path[..<$0] } ?? path[...]
        parts.path = base + "=s\(size)-c"
        return parts.url
    }
}

extension Sync {
    static let googleNameKey = "googleProfileName"
    static let googlePictureKey = "googleProfilePicture"
    private static let log = Logger(subsystem: "NMail", category: "profile")

    /// Google's account name (preferred over Gmail's send-as name) and photo. Never fails the sync:
    /// a login from before the userinfo.profile scope gets a 401/403 and keeps the letter avatar.
    func refreshGoogleProfile(email: String) async {
        do {
            let info = try await gmail.userinfo()
            if let name = info.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != (try store.get(Self.googleNameKey)) {
                try store.set(Self.googleNameKey, name)
                let account = Account(email: email, name: name)
                try store.save(account: account)
                await onAccount(account)
            }
            guard let avatarURL, let picture = info.picture,
                  picture != (try store.get(Self.googlePictureKey)) || !FileManager.default.fileExists(atPath: avatarURL.path),
                  let sized = GoogleUserinfo.sizedPicture(picture) else { return }
            let (data, resp) = try await URLSession.shared.data(from: sized)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            else { throw GmailError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: "profile photo") }
            try FileManager.default.createDirectory(at: avatarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: avatarURL, options: .atomic)
            try store.set(Self.googlePictureKey, picture)
            await onAvatar(png)
        } catch {
            Self.log.notice("Google profile skipped: \(String(describing: error), privacy: .public)")
        }
    }
}
