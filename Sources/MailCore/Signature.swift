import GRDB

/// Which signature a send-as identity signs with. Edits in Settings stay local; Gmail's copy only
/// changes through `Outbox.updateSignature`, when the user asks for it.
public enum Signature {
    /// Tim's sign-off. Flip the two lines here to change the order everywhere.
    public static let defaultText = "My kindest,\nTim Cvetko"

    static func localKey(_ email: String) -> String { "signature.local.\(email.lowercased())" }

    /// The local edit if there is one, else Gmail's sendAs signature, else `defaultText`.
    public static func text(for identity: SendAs?, db: Database) throws -> String {
        if let identity, let local = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [localKey(identity.email)]) {
            return local
        }
        let gmail = MIME.plainText(fromHTML: identity?.signature ?? "")
        return gmail.isEmpty ? defaultText : gmail
    }
}

extension Store {
    public func saveLocalSignature(_ text: String, for identity: SendAs) throws {
        try set(Signature.localKey(identity.email), text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
