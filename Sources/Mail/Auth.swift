import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct OAuthClient: Decodable {
    let client_id: String
    let client_secret: String

    // Google's "Desktop app" credentials JSON, downloaded from Cloud Console.
    static func load() throws -> OAuthClient {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/mail/client_secret.json")
        struct File: Decodable { let installed: OAuthClient }
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).installed
    }
}

enum AuthError: Error { case noCode, badResponse(String) }

actor Auth {
    static let shared = Auth()
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.compose",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]

    private var accessToken: String?
    private var expiry = Date.distantPast

    var isSignedIn: Bool { Keychain.get("refresh_token") != nil }

    func token() async throws -> String {
        if let accessToken, expiry > .now.addingTimeInterval(60) { return accessToken }
        guard let refresh = Keychain.get("refresh_token") else { return try await signIn() }
        let client = try OAuthClient.load()
        return try await exchange([
            "client_id": client.client_id, "client_secret": client.client_secret,
            "refresh_token": refresh, "grant_type": "refresh_token",
        ])
    }

    func signIn() async throws -> String {
        let client = try OAuthClient.load()
        let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        let (port, code) = try await Loopback.start()
        let redirect = "http://127.0.0.1:\(port)"
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
        await MainActor.run { _ = NSWorkspace.shared.open(auth.url!) }

        return try await exchange([
            "client_id": client.client_id, "client_secret": client.client_secret,
            "code": try await code.value, "code_verifier": verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        ])
    }

    func signOut() {
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
        if let r = t.refresh_token { Keychain.set("refresh_token", r) }
        accessToken = t.access_token
        expiry = .now.addingTimeInterval(t.expires_in)
        return t.access_token
    }
}

// One-shot HTTP listener on 127.0.0.1 that captures Google's ?code= redirect.
enum Loopback {
    static func start() async throws -> (UInt16, Task<String, Error>) {
        let listener = try NWListener(using: .tcp, on: .any)
        let (portStream, portCont) = AsyncStream<UInt16>.makeStream()
        let code = Task<String, Error> {
            try await withCheckedThrowingContinuation { cont in
                listener.newConnectionHandler = { conn in
                    conn.start(queue: .main)
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                        let line = String(decoding: data ?? Data(), as: UTF8.self)
                            .split(separator: "\r\n").first ?? ""
                        let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                        let value = URLComponents(string: path)?.queryItems?.first { $0.name == "code" }?.value
                        let body = value == nil ? "Sign-in failed." : "Signed in. You can close this tab."
                        let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n\(body)"
                        conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
                            conn.cancel()
                            listener.cancel()
                        })
                        if let value { cont.resume(returning: value) } else { cont.resume(throwing: AuthError.noCode) }
                    }
                }
            }
        }
        listener.stateUpdateHandler = { if case .ready = $0 { portCont.yield(listener.port!.rawValue); portCont.finish() } }
        listener.start(queue: .main)
        for await port in portStream { return (port, code) }
        throw AuthError.noCode
    }
}

enum Keychain {
    private static let service = "mail.tim"

    static func get(_ key: String) -> String? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    static func set(_ key: String, _ value: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
