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
    ]

    private var accessToken: String?
    private var expiry = Date.distantPast

    public var isSignedIn: Bool { Keychain.get("refresh_token") != nil }

    /// A valid access token; `refresh` skips the cached one (after a 401).
    public func token(refresh: Bool = false) async throws -> String {
        if !refresh, let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get("refresh_token") else { return try await signIn() }
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
        Keychain.delete("refresh_token")
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
            if form["grant_type"] == "refresh_token" { Keychain.delete("refresh_token") }
            throw AuthError.badResponse(String(decoding: data, as: UTF8.self))
        }
        struct Token: Decodable { let access_token: String; let expires_in: Double; let refresh_token: String? }
        let t = try JSONDecoder().decode(Token.self, from: data)
        if let r = t.refresh_token { try Keychain.set("refresh_token", r) }
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
        let (portStream, portCont) = AsyncStream<UInt16>.makeStream()
        let code = Task<String, Error> {
            try await withCheckedThrowingContinuation { cont in
                var done = false
                listener.newConnectionHandler = { conn in
                    conn.start(queue: .main)
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                        let line = String(decoding: data ?? Data(), as: UTF8.self).split(separator: "\r\n").first ?? ""
                        let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                        let items = URLComponents(string: path)?.queryItems ?? []
                        let value = items.first { $0.name == "code" }?.value
                        let failure = items.first { $0.name == "error" }?.value
                        guard !done, value != nil || failure != nil else {
                            reply(conn, status: "404 Not Found", body: "")
                            return
                        }
                        done = true
                        reply(conn, status: "200 OK", body: value != nil
                              ? "Signed in to NMail. You can close this tab."
                              : "Sign-in was cancelled (\(failure!)). You can close this tab and try again from NMail.") {
                            listener.cancel()
                        }
                        if let value { cont.resume(returning: value) } else { cont.resume(throwing: AuthError.badResponse("Google returned: \(failure!)")) }
                    }
                }
            }
        }
        listener.stateUpdateHandler = { if case .ready = $0 { portCont.yield(listener.port!.rawValue); portCont.finish() } }
        listener.start(queue: .main)
        for await port in portStream { return (port, code) }
        throw AuthError.noCode
    }

    private static func reply(_ conn: NWConnection, status: String, body: String, then: (@Sendable () -> Void)? = nil) {
        let resp = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
            conn.cancel()
            then?()
        })
    }
}

public enum Keychain {
    private static let service = "mail.tim"

    public static func get(_ key: String) -> String? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    public static func set(_ key: String, _ value: String) throws {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8)]
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.badResponse("Couldn't save the login to the Keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "\(status)")).")
        }
    }

    public static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

