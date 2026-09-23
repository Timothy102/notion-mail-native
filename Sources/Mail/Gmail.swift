import Foundation

enum Gmail {
    static let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!

    struct Profile: Decodable { let emailAddress: String; let messagesTotal: Int; let historyId: String }

    static func profile() async throws -> Profile { try await get("profile") }

    static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await Auth.shared.token())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.badResponse(String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
