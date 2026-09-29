import Foundation

/// Tool names, descriptions and input schemas, as `tools/list` returns them.
struct Tool {
    var name: String
    var title: String
    var description: String
    var properties: [String: JSON]
    var required: [String] = []
    var readOnly = false
    var destructive = false

    var listing: JSON {
        var props = properties
        props["account"] = ["type": "string", "description": "Account email. Defaults to the account open in AxiosM; see list_accounts."]
        return [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": ["type": "object", "properties": .object(props), "required": .array(required.map(JSON.string)),
                            "additionalProperties": false],
            "annotations": ["readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive), "openWorldHint": .bool(!readOnly)],
        ]
    }
}

enum Tools {
    static let actions = ["archive", "unarchive", "mark_read", "mark_unread", "star", "unstar", "trash", "untrash", "spam",
                          "add_labels", "remove_labels"]

    static let query: JSON = ["type": "string", "description": """
        Gmail search syntax: free words, "quoted phrases", from:, to:, cc:, subject:, is:unread / is:read / is:starred, \
        has:attachment, label:<name>, in:inbox / in:sent / in:spam / in:trash / in:anywhere, before:/after: (2026/03/01), \
        older_than:/newer_than: (7d, 2m, 1y), -negation. OR, size:, filename:, category: and the like go to Gmail's own search.
        """]
    static let mailbox: JSON = ["type": "string", "description": "Limit to a mailbox: inbox, starred, sent, drafts, spam, trash, or a label name. Omit for all mail (spam and trash excluded)."]
    static let action: JSON = ["type": "string", "enum": .array(actions.map(JSON.string)), "description": """
        archive (leave inbox), unarchive (back to inbox), mark_read, mark_unread, star, unstar, trash, untrash (out of trash, \
        back to inbox), spam, add_labels / remove_labels (with `labels`).
        """]
    static let labels: JSON = ["type": "array", "items": ["type": "string"], "description": "Label names or ids, for add_labels / remove_labels. The labels must exist (see list_labels)."]
    static let target: JSON = ["type": "string", "enum": ["thread", "message"], "default": "thread",
                               "description": "thread (default): whole conversations, like Gmail's conversation view. message: only the listed/matching messages."]
    static let includeQuoted: JSON = ["type": "boolean", "default": false, "description": "Keep quoted reply history in bodies (stripped by default)."]
    static let addresses: JSON = ["type": "array", "items": ["type": "string"], "description": "Addresses: \"Name <a@b.com>\" or \"a@b.com\"."]

    static let compose: [String: JSON] = [
        "to": addresses, "cc": addresses, "bcc": addresses,
        "subject": ["type": "string", "description": "Required for new messages; replies and forwards default to Re:/Fwd: of the original."],
        "body": ["type": "string", "description": """
            What Tim writes, as plain text or light markdown (**bold**, *italic*, [text](url), "- " bullets). \
            Don't add a sign-off: his NMail signature is appended (see `sign`). Quoted history is added automatically for replies and forwards.
            """],
        "reply_to_message_id": ["type": "string", "description": "Reply to this message id: threads it (In-Reply-To, References, thread id) and quotes it Gmail-style. To/cc default to the reply's recipients."],
        "reply_all": ["type": "boolean", "default": false, "description": "With reply_to_message_id: reply to everyone."],
        "forward_message_id": ["type": "string", "description": "Forward this message id (with its attachments). Needs `to`."],
        "send_as": ["type": "string", "description": "Send-as alias email; defaults to Tim's default identity (replies: the address the original was sent to)."],
        "sign": ["type": "boolean", "default": true, "description": "Append the AxiosM signature for the sending identity."],
    ]

    static let all: [Tool] = [
        Tool(name: "list_accounts", title: "List accounts",
             description: "AxiosM's accounts, which one is open in the app (the default for every tool), and whether each has a Gmail login.",
             properties: [:], readOnly: true),
        Tool(name: "list_labels", title: "List labels",
             description: "System and user labels with their ids and unread thread counts.",
             properties: [:], readOnly: true),
        Tool(name: "search", title: "Search mail",
             description: """
                Search mail, newest first. Returns threads (default) or messages with ids, subject, from, date, snippet, \
                labels and unread. Reads NMail's local copy after a quick Gmail sync, and falls back to Gmail's search when \
                nothing matches locally or the query reaches past the locally synced window. Page with `cursor`.
                """,
             properties: [
                 "query": query, "mailbox": mailbox,
                 "granularity": ["type": "string", "enum": ["thread", "message"], "default": "thread"],
                 "limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 25],
                 "cursor": ["type": "string", "description": "next_cursor from the previous page."],
             ], readOnly: true),
        Tool(name: "get_thread", title: "Read thread",
             description: "Every message of a thread, oldest first: headers, clean plain-text body (quoted history stripped unless include_quoted), attachments.",
             properties: ["thread_id": ["type": "string"], "include_quoted": includeQuoted],
             required: ["thread_id"], readOnly: true),
        Tool(name: "get_messages", title: "Read messages",
             description: "Several messages by id, same shape as get_thread's messages.",
             properties: ["ids": ["type": "array", "items": ["type": "string"], "maxItems": 100], "include_quoted": includeQuoted],
             required: ["ids"], readOnly: true),
        Tool(name: "modify", title: "Modify mail",
             description: "Apply one action to explicit thread or message ids (up to 1000), on Gmail and in AxiosM. Trash and spam need Tim's OK in an on-screen dialog. Returns counts.",
             properties: ["ids": ["type": "array", "items": ["type": "string"], "maxItems": 1000], "target": target,
                          "action": action, "labels": labels],
             required: ["ids", "action"], destructive: true),
        Tool(name: "modify_by_query", title: "Modify mail by query",
             description: """
                Apply one action to everything matching a Gmail query (matched on Gmail, all time). DRY RUN BY DEFAULT: \
                returns the match count and 10 samples and changes nothing. Pass dry_run:false to act; at most 5000 \
                matching messages per call (call again for the rest). Trash and spam need Tim's OK in an on-screen dialog.
                """,
             properties: ["query": query, "mailbox": mailbox, "target": target, "action": action, "labels": labels,
                          "dry_run": ["type": "boolean", "default": true, "description": "true (default): only count and sample."]],
             required: ["action"], destructive: true),
        Tool(name: "create_draft", title: "Create draft",
             description: "Save a Gmail draft built exactly like AxiosM's composer (signature, Notion-style HTML, reply threading and quote).",
             properties: compose),
        Tool(name: "update_draft", title: "Update draft",
             description: "Change a draft's recipients, subject or body. Omitted fields keep their current value; `body` replaces what was written (signature and quote are kept).",
             properties: compose.filter { !["reply_to_message_id", "reply_all", "forward_message_id"].contains($0.key) }
                 .merging(["draft_id": ["type": "string"]]) { a, _ in a },
             required: ["draft_id"]),
        Tool(name: "list_drafts", title: "List drafts",
             description: "Drafts, newest first, with recipients, subject and snippet.",
             properties: ["limit": ["type": "integer", "minimum": 1, "maximum": 200, "default": 50]], readOnly: true),
        Tool(name: "delete_draft", title: "Delete draft",
             description: "Delete a draft on Gmail and in AxiosM, after Tim allows it in an on-screen dialog.",
             properties: ["draft_id": ["type": "string"]], required: ["draft_id"], destructive: true),
        Tool(name: "send", title: "Send mail",
             description: """
                Send a new message, reply, reply-all or forward, built exactly like NMail's composer (signature, Notion-style \
                HTML, Gmail threading and quote). PREVIEW BY DEFAULT: without confirm:true it returns from, to, cc, subject, \
                the text with the signature and whether it threads, and sends nothing. Show Tim the preview first. \
                With confirm:true Tim still has to click Allow in an on-screen AxiosM dialog.
                """,
             properties: compose.merging(["confirm": ["type": "boolean", "default": false, "description": "true sends. false (default) only previews."]]) { a, _ in a },
             destructive: true),
        Tool(name: "send_bulk", title: "Send many",
             description: """
                Send up to 50 individual messages (each with the same fields as `send`), about one per second. Previews all \
                of them unless confirm:true, which asks Tim once in an on-screen dialog for the whole batch. Returns a result \
                per message; one failure doesn't stop the rest.
                """,
             properties: [
                 "messages": ["type": "array", "maxItems": 50, "items": ["type": "object", "properties": .object(compose)]],
                 "confirm": ["type": "boolean", "default": false],
             ],
             required: ["messages"], destructive: true),
        Tool(name: "get_signature", title: "Get signature",
             description: "The signature AxiosM signs with for an identity, as HTML and text.",
             properties: ["send_as": ["type": "string", "description": "Identity email; defaults to the default identity."]], readOnly: true),
        Tool(name: "download_attachment", title: "Download attachment",
             description: "Save an attachment (ids from get_thread / get_messages) under ~/Downloads, quarantined like a browser download.",
             properties: [
                 "message_id": ["type": "string"],
                 "attachment_id": ["type": "string", "description": "The attachment's id, or its filename."],
                 "path": ["type": "string", "description": "File or existing folder inside ~/Downloads (absolute, or relative to ~/Downloads). Defaults to ~/Downloads under the attachment's name."],
                 "overwrite": ["type": "boolean", "default": false],
             ],
             required: ["message_id", "attachment_id"]),
        Tool(name: "sync", title: "Sync now",
             description: "Pull the latest changes from Gmail (history, labels, drafts) into AxiosM's local copy now.",
             properties: [:]),
    ]
}
