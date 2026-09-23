# Notion Mail layout reference

Source images are indexed in `ref/INDEX.md`, and all of them live under `ref/online/`.

## How values were obtained
- **[M] Measured:** pixel-measured on `hc-inbox-view-labels-light-2x.png`, a clean 2x macOS capture. px ÷ 2 = pt.
- **[m] Measured on a video frame:** from `yt-mf-*` (≈1.5625 px/pt) or `yt-kw-*` (the window is scaled into the video, so the scale is unknown). These values are only good as ratios or approximations.
- **[I] Inferred:** read by eye from several screenshots, or taken from Notion's general design language.

Several users had the "Font size: Large" setting on. Where sizes conflict, the `hc-` 2x capture wins.

## Global tokens (light / dark)
| Token | Light | Dark | Source |
|---|---|---|---|
| Sidebar background | `#F7F7F5` | `#202020` | [M] / [m] ant |
| Content background | `#FFFFFF` | `#191919` | [M] / [m] ant |
| Sidebar/content divider | `#EDECEB`, 1px @2x (0.5pt) | `#2B2B2B` | [M] / [m] |
| Row separator | `#F1F0F0`, 0.5pt | `#232323` | [M] / [m] |
| Group header rule | `#F1F0F0`, 1pt | `#232323` | [M] |
| Selected sidebar item | `#EAEAE8` | `#2C2C2C` | [M] / [m] |
| Selected (checked) list row | light blue tint (≈`#E9F1FB`) [I] | `#232E40` | [m] ant |
| Hover list row | `#F5F5F4`-ish, rounded 6pt [I] | ≈`#232323` [I] | yt-mf 63:02 |
| Primary text | `#1D1B17` (rgb 29,27,23) | ≈`#E3E3E3` [I] | [M] |
| Secondary text (dates, counts, section labels) | `#91918E` | ≈`#7F7F7F` | [M] / [m] |
| Unread dot / accent blue | `#4281DB` | same | [M] |
| Primary button (Send, Save) | `#2A86D9` [m] (≈Notion blue `#2383E2`) | same | yt-kw |
| Label chip, gray | bg `#F1F1EF` | ≈`#2F2F2F` [I] | [M] |
| Label chip, purple | bg `#E6DEED` | [I] | [M] |
| Label chip, blue | bg `#D6E4EE` | [I] | [M] |
| Label chip, yellow/orange | bg ≈`#FBEBD0` [m], text ≈`#8C6A2E` | [I] | yt-kw |
| Label chip, green | bg ≈`#D3E9D7` [m] | [I] | yt-mf thread |
| Label chip, red/pink | bg ≈`#F6DEDF` [I] | [I] | yt-mf "Networking" |
| Palette panel | `#FFFFFF` | `#252525` | [m] |
| Palette selected row | `#F2F2F2` | `#313131` | [m] |
| Modal scrim | black at ≈45% | black at ≈55% | [m] |
| Row hover action bar | white, hairline border, 6pt radius | `#252525` | [m] |

- **Label chips:** Notion "select" colours, 18pt tall, radius about 3pt, and 12 to 13pt regular text in the darker shade of the same hue [M/I].
- **Fonts:** the system font (SF Pro). Nothing else was observed [I, confirmed by the CSS stack].

## Window and panes
- **Window:** traffic lights sit in the sidebar at about y=24pt with standard inset. There is no visible title bar, so the content runs full-height [M].
- **Sidebar:** 220pt wide (divider at x=219.5pt) [M]. It is collapsible with cmd-\ and the ">>"/"<<" button.
- **List pane:** fills the rest of the window.
- **Thread in side peek (default):** a right pane about 50% of the content width. The list stays visible underneath, with the subject column clipped by the pane [m] (tjf 3-pane: 1076/1978 px ≈ 54% list, 46% thread).
- **Other thread styles:** center peek (modal over the list) and full page. These are chosen in Settings → Inbox → Thread style.

## Sidebar [M unless noted]
From top to bottom:
1. **Account row** (y≈62pt):
   - 20pt avatar (round, or initial on a coloured circle).
   - Name in 14pt medium.
   - In yt-mf, the email appears on a second line in 11 to 12pt secondary text.
   - A chevron-down, then the compose icon (square-pencil, 18pt) right-aligned at about x=195pt.
2. **Search row:** magnifier icon plus "Search" at 14pt.
3. **Section label "Views":** 12pt medium, secondary colour, with a "+" at the right edge. There is 30pt of space above it.
4. **Items:**
   - 32pt row pitch. Selected pill is 30pt tall, inset 8pt left and right (x 8→212), radius about 6pt.
   - Icon glyph is 15 to 16pt, centred at x≈26pt.
   - Label is 14pt at x=44pt, truncated with "…".
   - Count sits right-aligned at x≈200pt in 13pt secondary text.
   - The default "Inbox" view uses a red tray icon. Custom views use coloured emoji or Notion icons.
5. **"+ New view"** and **"^ Less" / "More"** rows.
6. **Section label "Mail":** All Mail, Sent, Drafts (with count), Spam, Trash. These use monochrome line icons in secondary colour.
7. **Lower group:** Settings, Templates or Refer friend, Support & feedback.
8. **Footer bar:**
   - 0.5pt top border.
   - About 44pt tall.
   - Notion app icon and Calendar app icon (showing today's date number) on the left.
   - A "?" circle on the right.

Unread counts appear only on views. The number is not bold.

## List header [M]
- **Height:** 48pt.
  - Title centre at 24pt, 14pt regular text.
  - A view icon of about 13pt at x≈290 (window coords, 70pt into the list pane) is followed by the title.
- **Header checkbox:** appears on hover or when rows are selected. It sits at about x=+12pt in the list pane. [m]
- **Right side:**
  - The "Auto label" button is 29pt tall, about 100pt wide, 8pt radius, with a hairline border. It is AI, so **omit it**.
  - Then three 18pt icon buttons on a 30pt pitch: filter (blue when a filter is active), properties/settings sliders, refresh.
  - Right padding is about 52pt.
- **Selection mode (ant dark):** the header is replaced by a bulk toolbar:
  - A checkbox with a chevron, then a separator.
  - Mark read, archive, remind, trash, spam, label with chevron.
  - "Auto label similar" (omit).
  - "N selected" on the right in secondary text.

## List rows [M]
- **Pitch:** 38pt. A 0.5pt separator runs from the sender x to the date's right edge, so it does **not** span full width.
- **Columns** (x in pt from the list-pane left edge):

| Element | Position and size | Notes |
|---|---|---|
| Unread dot | 6pt, centre x≈55, vertically centred | Only on unread rows |
| Sender | x=69, column about 160pt, truncated | Unread: semibold 14pt primary. Read: regular 14pt. Participant lists look like "me, Yann, me" followed by the message count in secondary 13pt ("4"). A red "Draft" text follows when the thread has a draft. |
| Subject | x=234 (column 2 starts about 165pt after the sender) | 14pt, weight matches the sender. The snippet follows on the same line in secondary colour, then an ellipsis. Emoji are inline. |
| Label chips | right-aligned before the date, gap about 6pt | Long names truncate to "Notion Support …" |
| Attachment | paperclip icon of about 14pt, secondary, just left of the date column | |
| Date | right-aligned, ends 52pt before the window edge, 13 to 14pt secondary, tabular | |

- **Optional status circle:** 14pt, placed before the sender. It is a dashed circle for "No status" and a solid pink circle for unread-status [m] (tjf, hcvid). This is a Notion "status" property. **Skip it for v1.**
- **Group header:** row text at about 13 to 14pt primary ("Yesterday", "Last 7 days", "March", "Unread", "Read", "Starred", "Everything else").
  - 1pt rule under it, spanning slightly wider than the rows (from x=52).
  - About 22pt top gap above it.
  - Header block is about 44pt.
  - Collapsible groups show a "Collapse" affordance in secondary text on hover (hcvid). An empty group shows "(Empty)" in secondary text.
- **Hover** (yt-mf 63:02, ant):
  - The row gets a rounded (6pt) light-gray background extending about 8pt beyond the columns.
  - A checkbox appears to the left of the dot (x≈+14pt).
  - The date is covered by a floating action bar: white with a hairline border and 6pt radius, holding 5 icon buttons of about 28pt.
  - Default order: **Star, Archive, Trash, Mark read/unread, Remind**. The actions are configurable in Settings → Customize hover actions.
  - Each icon has a black tooltip (e.g. "Star") with white 12pt text and 4pt radius, placed below.
- **Keyboard focus row:** the same background as hover [I].
- **Selected** (x or checkbox): checkbox filled `#2383E2` and the row tinted blue.

## Date formatting [M/m]
| When | Format | Example |
|---|---|---|
| Today | time only | "11:32 PM" |
| Earlier this year | month and day | "Apr 6", "Mar 22" |
| Previous years | month, day, year | "Dec 25, 2024" |

The thread message header uses the same rules ("Apr 18").

## Thread view (side peek) [m: yt-mf 21:11, tjf 3-pane, zp]
- **Pane:** white, with a 0.5pt left divider plus a faint shadow.
- **Toolbar** (height about 48pt, same baseline as the list header):
  - Left: ">>" (close peek), then up and down chevrons for previous and next.
  - Right: "Auto label similar" (omit), remind (clock), mark read/unread, label (tag), archive, trash, "…".
  - Icons are 18pt on a 32pt pitch.
- **Header block** (content inset about 44pt on the left, max width about 720pt, centred in full page):
  - **Subject:** about 22pt bold, can wrap, emoji allowed.
  - **Chip row:** label chips plus "Add label" (plus "2 attachments" with a paperclip in tjf) in secondary text.
  - A 0.5pt full-width divider under the block, about 16pt below.
- **Message:**
  - **Header, variant A** (yt-mf): "FROM" / "TO" small uppercase labels in 11pt secondary on the left. The name is medium and the address is secondary. The sender row gets a hover highlight and a context menu (Copy email, Copy name, Split sender or domain into a view).
  - **Header, variant B** (tjf and newer builds): name in 14pt medium, "To me" beneath in secondary text.
  - **Right side:** reply and forward icons (yt-mf), then the date in secondary text.
  - **Body:** HTML rendered at about 14 to 15pt, line-height about 1.5, with the same left inset.
  - **Attachments:** "⤓ Download all" link, then 64pt rounded thumbnail tiles.
- **Multi-message threads** (zp):
  - Earlier messages collapse into single-line rows: sender (medium) + snippet (secondary, truncated) + date on the right.
  - Rows are about 36pt with 0.5pt separators.
  - The last message is expanded.
  - o expands and collapses one message; shift-o does it for all.
- **Inline reply card** (tjf, yt-mf):
  - Rounded 8pt, hairline border, soft shadow, pinned under the last message.
  - Header row: reply-type icon (dropdown for reply, reply-all or forward), recipient chip "Name ×", then "Cc/Bcc" and "…" on the right.
  - Body placeholder: "Write, or press '/' for commands" (drop the AI part of the original "press 'space' for AI").
  - Footer: the Send split button.
- **Fallback buttons** under the last message (zp): outlined 32pt buttons "↩ Reply", "↩↩ Reply All", "↪ Forward" with 8pt radius.

## Composer (new message) [m: yt-kw 5:38 / 6:58, ce, cache-quickstart]
- **Position:** a floating panel docked to the right side of the content area. It spans from about the list's 5th row down to 8pt above the bottom, is about 42% of the content width, and does not cover the sidebar.
  - Background `#FBFBF9` (light), 1pt border `#ECECE9`, radius about 8pt, large soft shadow.
  - Minimize "–" and close "×" sit top right.
- **Rows** (each about 32pt, 16pt horizontal padding, no labels, placeholders in secondary text):
  1. **From:** "Name email@…" with the email in secondary text. Clicking selects the sendAs alias (cache-quickstart shows a "▾").
  2. **To:** "Add recipient" placeholder, with "Cc/Bcc" in secondary text on the right. Recipients render as chips; a group shows as "Mail Team 12 people".
  3. **Subject:** "Subject" placeholder.
  4. A 0.5pt divider.
- **Body:** Notion-style block editor. "/" opens a block menu (Text, Heading 1/2/3, Bulleted, Numbered, To-do, Quote, Callout, Code) with 40pt rows, a 32pt icon tile, a title and a secondary description.
  - Signature is inserted at the bottom of the body.
- **Footer** (about 40pt):
  - Blue "Send" split button with chevron, 28pt tall, 6pt radius. The menu offers Send, Send & Archive, Send & Snooze.
  - "Draft saved" in secondary text next to it.
  - Right-aligned icons: attach (paperclip), snippets "{}", schedule/calendar, discard (trash).
- **Schedule send menu:** "Tomorrow morning / Tomorrow afternoon / Thursday morning" rows with dates in secondary text, then "Custom date".

## Command palette (cmd-K / cmd-P) [m: yt-mf 61:41, ant dark]
- **Size:** centred horizontally, about 60% of the window width (roughly 715pt on a 1230pt window).
  - Top at about 12% of the window height; about 516pt tall max, scrolling.
  - Radius about 10pt, big shadow, dim scrim.
- **Input row:** 47pt, magnifier at 20pt, placeholder "Search commands or Notion Mail..." at about 18pt, with a 0.5pt divider below.
- **Groups:** section labels in 12pt medium secondary ("Inbox", "View", "Label", "Thread", "Navigation", "Misc", "Snippets"), with a group gap of about 16pt.
- **Rows:**
  - 36pt pitch, inset 8pt, selected row background `#F2F2F2` with 6pt radius.
  - 18pt line icon, then the label at 14 to 15pt.
  - Shortcut hint right-aligned in secondary text, written as plain words ("C", "G then T", "⌘ A or Shift 8 A", "Control+F", "⌘+Shift+L").
- **Footer:** about 32pt, top hairline, "⇅ Select   ↵ Open" in 12pt secondary.
- **Contents seen:**
  - Compose (C), Select all, Create new snippet.
  - Add a View, Filter Inbox (ctrl F), Edit Inbox properties (ctrl E).
  - Go to Sent / Reminders / Drafts / Spam / Scheduled / All Mail / Trash / <each view>.
  - Open settings, Go to Snippets.
  - Shortcuts (?), Switch to center peek / full page, Set theme · Light / Dark (⌘⇧L), Send feedback.
  - Compose "<snippet>".
- **Thread context** (cache-cmdk): Mark as read, Trash, Archive, Reply, Reply all, Forward, Mark as spam, View attachments, Open links, Add label.
- **Shortcuts modal** ("?"):
  - Large modal (about 85% of the window) with a "Keyboard shortcuts" title in 22pt bold and a "Search shortcuts…" field top right (focused, blue ring).
  - Two-column grid grouped under 17pt bold section heads.
  - Keys are drawn as keycaps: 1pt border, 4pt radius, monospace 12pt, joined by "or" / "then".

## Search [I]
No dedicated search-results screenshot survives.
- Search opens from the sidebar "Search" row or "/".
- It shares the palette's field style.
- Results reuse the list-row layout under a header of "Search: <query>", with filter chips taken from the filter menu: Unread, Read, Attachment, Calendar event, Label, To, CC, BCC, From, Subject, Date, and Promotions, Social, Forums and Updates.
- By default it excludes Spam and Trash.
- `label:` syntax is supported.

## Menus and popovers [m: tjf, hcvid]
- **Popovers:** white, radius about 8pt, shadow, and a width of about 300 to 320pt.
  - Header row: "← Title" in 14pt semibold.
  - Rows are 32pt: icon plus label, with the value in secondary text plus a chevron on the right.
  - A search field (bg `#F7F7F5`, 1pt border, 6pt radius, "Search…").
  - Destructive items at the bottom after a divider (trash icon plus "Remove grouping").
- **Remind menu:** "Remind if no reply" toggle, then Later today / Tomorrow / Next Monday rows with times in secondary text.
- **Toast:** dark `#2F2F2F` pill, white 13pt text, bottom-left of the content area ("Snippet saved").

## Empty state [M/I]
Source: `hc-inbox-empty-groups-popover-light-2x.png`, where a popover partly hides the text.
- Centred in the list area, about 180pt from the top.
- Line-art illustration of a mailbox with a sleeping dog, about 200×130pt. The art is in `ref/online/cache-mailbox.png` and `ref/online/cache-dog.png` (transparent black line art; invert it for dark).
- Title in 16pt medium primary, beginning "No n…". It is likely "No new mail" [I].
- Subtitle in 14pt secondary, beginning "Rest easy, no n…" [I].

## Settings (modal) [m: yt-kw 10:07 / 11:25, yt-mf dark]
- **Modal:** about 85% of the window, radius about 10pt.
- **Left nav:** 220pt, sidebar background, items 32pt.
  - "Account" section: Inbox, Notion AI, Gmail filters, Snippets, Signature, Account.
  - "Workspace" section: Members ↗, Plans ↗.
- **Content:**
  - Title in 16pt semibold, then a 0.5pt rule.
  - Rows: title in 14pt medium, description in 13pt secondary, value dropdown ("Light ⌄") right-aligned. Rows are about 56pt apart.
- **Inbox page:** Theme mode (System/Light/Dark), Thread style (Side peek/Center peek/Full page), Auto-advance (Go to next thread/previous/Close thread), Font size (Default/Large).
- **Signature page:**
  - "Include on replies and forwards" toggle (blue).
  - "Default signature" toggle ("Show 'Sent with Notion Mail'"; drop it).
  - "Edit signature in Gmail" with an "Open" button. Our app edits locally and pushes via `sendAs.patch`.
- **Snippets page:**
  - Table of Icon / Shortcut / Preview, with a blue "Create new" button.
  - The editor modal has "Shortcut" and "Snippet content" fields, variables {first_name} …, and Cancel / Save buttons.

## Keyboard shortcuts
The list is complete. It comes from the Help Center (Wayback 2025-06-28) and the in-app "?" modal (yt-mf 62:34–62:41).

### Inbox and navigation
| Action | Keys |
|---|---|
| Next / previous thread | j / k |
| Open thread | enter |
| Close thread / back | esc |
| Select thread | x |
| Multi-select | shift + ↑/↓ |
| Select all | ⌘A, or shift 8 A |
| Deselect all | shift 8 N |
| Compose | c |
| Command palette | ⌘K or ⌘P |
| Open search | / |
| Jump to top / bottom | ⌘↑ / ⌘↓ |
| Scroll down / up | space / shift+space |
| Go to Inbox | g then i |
| Go to Sent | g then t |
| Go to Drafts | g then d |
| Go to Archive / All Mail | g then a |
| Go to Spam | g then ! |
| Go to Trash | g then # |
| Go to Scheduled | g then s |
| Go to Reminders | g then h, or g then b |
| Switch account | ctrl + 1–9 |
| Toggle sidebar | ⌘\ |
| Filter inbox | ctrl F |
| Edit inbox properties | ctrl E |
| Edit labels | l |
| Shortcuts help | ? |
| Toggle dark theme | ⌘⇧L |

### Thread and message actions
| Action | Keys |
|---|---|
| Archive (mark done) | e |
| Move to Inbox | shift e |
| Trash | # (shift 3) or delete |
| Spam | ! |
| Reply | r |
| Reply all | a (or enter in a thread) |
| Forward | f |
| Mark read / unread (toggle) | u |
| Mark read | shift i |
| Mark unread | shift u |
| Star | s [I] (the modal shows a "Star thread" row; the key is cut off in the frame) |
| Label / unlabel | l |
| Set reminder (snooze) | h or b |
| Undo | z |
| Unsubscribe | ⌘U |
| Copy link to thread | ctrl / |
| Open attachments | ⌘O |
| Next / previous message in thread | n / p |
| First / last message | shift p / shift n |
| Expand or collapse message | o (or enter) |
| Expand or collapse all messages | shift o |
| Reply all and change To / CC / BCC / Subject / From | ⌘⇧O / ⌘⇧C / ⌘⇧B / ⌘⇧P / ⌘⇧F |
| Compose intro | ⌘⇧I |

### Compose
| Action | Keys |
|---|---|
| Send | ⌘ enter |
| Send and archive | ⌘⇧ enter |
| Exit draft | esc |
| Discard draft | ⌘⇧D |
| Add cc / bcc | ⌘⇧C / ⌘⇧B |
| Edit from | ⌘⇧F |
| Edit recipient / subject | ⌘⇧O / ⌘⇧P |
| Focus message body | ⌘⇧Y |
| Add attachment | ⌘⇧A |
| Align center / right | ⌘⇧E / ⌘⇧R |
| Text / H1 / H2 / H3 | ⌘⌥0 / 1 / 2 / 3 |
| Checkbox / bullets / numbered / quote | ⌘⌥4 / 5 / 6 / 7 |
| Indent less / more | ⌘[ / ⌘] |
| Emoji | :name |
| Block menu | / |

### Mapping to our v1 plan
The plan's keys j/k/enter/e/shift-u/#/l/z/g i/g d match Notion Mail exactly. Two differ:
- **Go to sent:** Notion Mail uses **g t**, not g s. g s means Scheduled. Bind both g t and g s to Sent unless we add a Scheduled view.
- **Star:** `s` is inferred. Star appears as a hover action and as "Star thread" in the modal.
