# nmail-mcp

An MCP server that lets Claude read and change your mail through NMail. It uses NMail's accounts, logins and
local mail, and it builds outgoing mail with the same MailCore code as the composer: `ComposeDraft.make`,
`Signature.html(for:)`, and `outgoing()` with Notion Mail's stylesheet, one `<p dir="auto">` per line and your
signature markup. Mail sent from Claude looks the same as mail sent from the app.

- **Transport:** stdio, newline-delimited JSON-RPC 2.0, MCP protocol `2025-06-18`. Older clients can also
  negotiate `2025-03-26` and `2024-11-05`. stdout carries only protocol messages. Logs go to stderr.
- **Accounts:** the ones in NMail's `accounts.json`. Every tool takes an optional `account`, which defaults to
  the account open in NMail. The server never signs in. If an account has no login, the error tells you to add
  it in NMail.
- **Freshness:** reads use NMail's local database. Before a read, the server runs a quick Gmail `history.list`
  sync. It skips the sync if one ran in the last 20 s, gives up after 10 s, and never does a full backfill.
  This keeps results current even when the app is closed.
- **Sharing the database with the app:** every store opens in WAL mode with a 5 s busy timeout, so the app and
  the server can both have the database open. The app shows the server's changes after its next sync, within
  about 30 s.

## Tools

| Tool | What it does |
|---|---|
| `list_accounts` | Accounts, which one is active, and whether each has a login |
| `list_labels` | System and user labels, with ids and unread thread counts |
| `search` | Gmail query syntax (`from:`, `to:`, `subject:`, `is:unread`, `has:attachment`, `label:`, `in:inbox`, `before:`/`after:`, `older_than:`, `"phrases"`, `-negation`). Also takes `mailbox`, `granularity: thread\|message`, `limit` (up to 200) and `cursor`. It falls back to Gmail's own search when nothing matches locally, when the query reaches past the synced window, or for operators the local index doesn't support (`OR`, `size:`, `filename:`…). |
| `get_thread` | All messages in a thread as clean plain text, with headers and attachment metadata. Quoted history is stripped unless you pass `include_quoted: true`. |
| `get_messages` | Up to 100 messages by id |
| `modify` | Applies one action to up to 1000 explicit thread or message ids |
| `modify_by_query` | Applies one action to everything a Gmail query matches. **It is a dry run by default:** it returns the count and 10 samples. Pass `dry_run: false` to act. At most 5000 messages per call. |
| `create_draft` / `update_draft` / `list_drafts` / `delete_draft` | Gmail drafts, built the same way the composer builds them |
| `send` | New message, reply, reply-all (`reply_to_message_id`, `reply_all`) or forward (`forward_message_id`). **It previews by default.** Nothing is sent without `confirm: true`. Also takes optional `send_as` and `sign` (default true). |
| `send_bulk` | Up to 50 personalised messages, sent about 1 per second. It previews unless you pass `confirm: true`, and returns a result per message. |
| `get_signature` | The signature HTML and text for an account or alias |
| `download_attachment` | Saves an attachment to a path |
| `sync` | Runs an incremental sync now (history, labels and drafts) |

Actions are `archive`, `unarchive`, `mark_read`, `mark_unread`, `star`, `unstar`, `trash`, `untrash`, `spam`,
`add_labels` and `remove_labels`. The label actions take a `labels` list of names or ids, and each label must
already exist. With `target: "thread"` (the default), an action applies to whole conversations, as in Gmail's
conversation view. With `target: "message"`, it applies only to the listed or matching messages. Changes go to
Gmail through `messages.batchModify` in chunks of 1000 ids, and then to the local store.

Message bodies can be plain text or light markdown: `**bold**`, `*italic*`, `[text](url)` and `- ` bullets.
Don't write a sign-off. Your NMail signature is added automatically, and replies get the Gmail-style quote and
threading headers, the same as in the app.

## Things to ask Claude

- "Archive every newsletter older than a week." Claude runs `modify_by_query` with
  `label:newsletters older_than:7d in:inbox` and `archive`, shows you the dry run, then acts.
- "Draft replies to all unread mail from Priya, saying I'll get back to her Thursday." Claude runs `search` with
  `from:priya is:unread`, then `create_draft` with `reply_to_message_id` for each message.
- "Summarise today's inbox." Claude runs `search` with `in:inbox newer_than:1d`, then `get_thread` on each
  result.
- "Mark all GitHub notifications read and label them GitHub." Claude runs `modify_by_query` twice.
- "Send the attached-invoice reminder to these 12 clients, each with their own amount." Claude runs `send_bulk`
  and shows you the previews first.
- "Find the PDF Revolut sent last month and save it to ~/Downloads." Claude runs `search` with
  `from:revolut has:attachment`, then `download_attachment`.
- "Go through Promotions and star anything a real person wrote." Claude runs `search` with `category:promotions`
  (this goes to Gmail's own search), reads the results, then runs `modify` with `star` on the ones that qualify.

## Install

`scripts/install.sh` builds the release app. It also copies the release `nmail-mcp` binary into the app bundle:

```
/Applications/NMail.app/Contents/MacOS/nmail-mcp
```

## Register

For Claude Code:

```sh
claude mcp add --scope user nmail -- /Applications/NMail.app/Contents/MacOS/nmail-mcp
```

For Claude Desktop, add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nmail": {
      "command": "/Applications/NMail.app/Contents/MacOS/nmail-mcp"
    }
  }
}
```

## Environment

| Variable | Effect |
|---|---|
| `NMAIL_DATA_DIR` | Replaces `~/Library/Application Support/Mail`. `accounts.json`, `accounts/<email>/mail.sqlite` and `secrets.json` are read from here. Use it for tests. |
| `NMAIL_OFFLINE=1` | Keeps the server off the network. Reads and previews work. Anything that would reach Gmail fails with an error. |

## Testing

`swift test --filter MCPTests` covers JSON-RPC framing, the dry-run defaults, send and reply previews (signature,
Notion HTML and threading headers, with no network), and draft updates. It also runs an end-to-end test that
pipes JSON-RPC into the built binary against fixture mail in a temp directory with `NMAIL_OFFLINE=1`.
