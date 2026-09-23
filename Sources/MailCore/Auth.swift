import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security

struct OAuthClient: Decodable {
    let client_id: String
    let client_secret: String?

    var credentials: [String: String] { ["client_id": client_id, "client_secret": client_secret].compactMapValues { $0 } }

    /// Desktop clients carry a secret and redirect to loopback; iOS/macOS clients (no secret) only accept
    /// their reversed client ID as a custom-scheme redirect.
    var usesLoopback: Bool { client_secret != nil }
    var reversedClientScheme: String { client_id.split(separator: ".").reversed().joined(separator: ".") }

    // The client's credentials JSON, downloaded from Cloud Console.
    static func load() throws -> OAuthClient {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/mail/client_secret.json")
        struct File: Decodable { let installed: OAuthClient }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).installed
    }
}

public enum AuthError: Error { case noCode, badResponse(String) }

public actor Auth {
    public static let shared = Auth()
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]

    private var accessToken: String?
    private var expiry = Date.distantPast

    public var isSignedIn: Bool { Secrets.get("refresh_token") != nil }

    /// A valid access token; `refresh` skips the cached one (after a 401).
    public func token(refresh: Bool = false) async throws -> String {
        if !refresh, let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Secrets.get("refresh_token") else { return try await signIn() }
        let client = try OAuthClient.load()
        return try await exchange(client.credentials.merging([
            "refresh_token": refresh, "grant_type": "refresh_token",
        ]) { $1 })
    }

    public func signIn() async throws -> String {
        let client = try OAuthClient.load()
        let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        let redirect: String
        var loopbackCode: Task<String, Error>?
        if client.usesLoopback {
            let (port, code) = try await Loopback.start()
            redirect = "http://127.0.0.1:\(port)"
            loopbackCode = code
        } else {
            redirect = "\(client.reversedClientScheme):/oauth2redirect"
        }
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: client.client_id),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        let code: String
        if let loopbackCode {
            await MainActor.run { _ = NSWorkspace.shared.open(auth.url!) }
            code = try await loopbackCode.value
        } else {
            code = try await WebAuth.code(from: auth.url!, scheme: client.reversedClientScheme)
        }

        return try await exchange(client.credentials.merging([
            "code": code, "code_verifier": verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        ]) { $1 })
    }

    public func signOut() {
        Secrets.delete("refresh_token")
        accessToken = nil
    }

    private func exchange(_ form: [String: String]) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            if form["grant_type"] == "refresh_token" { Secrets.delete("refresh_token") }
            throw AuthError.badResponse(String(decoding: data, as: UTF8.self))
        }
        struct Token: Decodable { let access_token: String; let expires_in: Double; let refresh_token: String? }
        let t = try JSONDecoder().decode(Token.self, from: data)
        if let r = t.refresh_token { try Secrets.set("refresh_token", r) }
        accessToken = t.access_token
        expiry = .now.addingTimeInterval(t.expires_in)
        return t.access_token
    }
}

/// Runs Google's consent page in an ASWebAuthenticationSession and returns the ?code= from the custom-scheme callback.
@MainActor
final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: WebAuth?
    private var session: ASWebAuthenticationSession?

    static func code(from url: URL, scheme: String) async throws -> String {
        let auth = WebAuth()
        current = auth
        defer { current = nil }
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? AuthError.noCode) }
            }
            session.presentationContextProvider = auth
            session.prefersEphemeralWebBrowserSession = false
            auth.session = session
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.noCode }
        return code
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

// One-shot HTTP listener on 127.0.0.1 that captures Google's ?code= redirect.
enum Loopback {
    /// Serves 127.0.0.1 until a request carries Google's `code` or `error`. Browser preconnects,
    /// favicon fetches and other stray requests get a 404 and are ignored.
    static func start() async throws -> (UInt16, Task<String, Error>) {
        let listener = try NWListener(using: .tcp, on: .any)
        let (ports, portCont) = AsyncStream<UInt16>.makeStream()
        let (codes, codeCont) = AsyncThrowingStream<String, Error>.makeStream()
        // Both handlers are attached before start(): a listener started without one fails immediately.
        listener.newConnectionHandler = { conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                let line = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first ?? ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: path)?.queryItems ?? []
                let value = items.first { $0.name == "code" }?.value
                let failure = items.first { $0.name == "error" }?.value
                guard value != nil || failure != nil else {
                    reply(conn, status: "404 Not Found", body: "")
                    return
                }
                reply(conn, status: "200 OK", body: value != nil
                      ? "Signed in to NMail. You can close this tab."
                      : "Sign-in was cancelled (\(failure!)). You can close this tab and try again from NMail.") {
                    listener.cancel()
                }
                if let value { codeCont.yield(value); codeCont.finish() } else { codeCont.finish(throwing: AuthError.badResponse("Google returned: \(failure!)")) }
            }
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                portCont.yield(listener.port!.rawValue)
                portCont.finish()
            case .failed(let error):
                portCont.finish()
                codeCont.finish(throwing: error)
            default: break
            }
        }
        listener.start(queue: .main)
        guard let port = await ports.first(where: { _ in true }) else { throw AuthError.badResponse("Couldn't open a local port for Google's sign-in redirect.") }
        let code = Task<String, Error> {
            for try await value in codes { return value }
            throw AuthError.noCode
        }
        return (port, code)
    }

    private static func reply(_ conn: NWConnection, status: String, body: String, then: (@Sendable () -> Void)? = nil) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
            conn.cancel()
            then?()
        })
    }
}

/// Login tokens in a file only this user can read (0600, directory 0700), like gcloud and gh keep theirs.
/// ponytail: not the Keychain, because NMail is ad-hoc signed and every rebuild loses its Keychain grant;
/// move back to the Keychain if the app ever ships with a stable signing identity.
public enum Secrets {
    private static let lock = NSLock()
    nonisolated(unsafe) static var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Mail/secrets.json")

    public static func get(_ key: String) -> String? {
        lock.withLock { read()[key] }
    }

    public static func set(_ key: String, _ value: String) throws {
        try lock.withLock {
            var all = read()
            all[key] = value
            try write(all)
        }
    }

    public static func delete(_ key: String) {
        lock.withLock {
            var all = read()
            guard all.removeValue(forKey: key) != nil else { return }
            try? write(all)
        }
    }

    private static func read() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) ?? [:]
    }

    private static func write(_ all: [String: String]) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir.appending(path: ".secrets.\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: try JSONEncoder().encode(all), attributes: [.posixPermissions: 0o600]) else {
            throw AuthError.badResponse("Couldn't save the login to \(url.path).")
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

