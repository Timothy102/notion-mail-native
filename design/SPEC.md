# Notion Mail rebuild: design spec

This is the only spec to build from. It merges `tokens.md` (values from the app's own JS bundle) with `layout.md` and a fresh pass over every image in `ref/` (all 99 were viewed). Where they disagreed, the screenshot won. Each such case is listed in §0.

Units are points (1 pt = 2 px in the `-2x` captures). "Pane" means the list pane, whose leading edge is the sidebar's trailing edge. Colors are sRGB. Every PNG in `ref/` is tagged Display P3 or "Color LCD", so convert to sRGB before sampling. That conversion is why `layout.md` quoted `#4281DB` for a dot whose real value is `#2383E2`.

`Theme.swift` implements every token here. Views must use `Theme.*` and never write a raw number or hex value.

---

## 0. Where the sources disagreed

| Topic | tokens.md (bundle) | layout.md | Screenshot measurement (wins) |
|---|---|---|---|
| Thread row height | 40 | 38 | **38**: 76 px pitch in `hc-…-2x`, and 38 in `yt-mf`, `hcvid` and `yt-kw` |
| List row text | 14 (REGULAR) | 13 | **13** at the Default font size. The cap height is 18 px @2x, versus 19–20 px for the 14 pt sidebar and title. The "Large" setting (used in `yt-mf` and `yt-kw`) is 14 and is not built. |
| Sidebar width | 240 | 219 | **240** default (`yt-mf`, 239); min 220 (`hc` at a 960 pt window), max 480 |
| Sidebar item label | 14 medium, textSecondary | 14 regular, primary | **14 regular, textSecondary `#5F5E5B`**, textPrimary when selected (sampled) |
| Read-row text | textPrimary @ 0.85 | primary | **Light: textPrimary at full opacity** (lossless `hc` and `zp` sample `#1D1B17`). **Dark: textPrimary @ 0.85** (`ant-*`: read ≈ `#B7B7B7`, unread clearly brighter). The difference is exposed as the `textRead` token. |
| Unread dot | `#2383E2` | `#4281DB` | **`#2383E2`**: the layout value was a P3 artifact |
| Row separators | transparent | 0.5 pt `#F1F0F0` | **1 px (0.5 pt) `borderDeemphasized`** from the sender's x to the date's trailing edge. There is none after the last row of a group. |
| Date-group header | 80 (48 when first) | 38 + 20 | **56**: label centred 28 from the top, 1 px hairline 48 from the top (8 above the next row). A header that opens the list is 56 too. |
| Palette row radius | 4 | 6 | **6** |
| Palette row label | medium | — | **regular** 14 |
| Hover-action width | 21.5 per action | 24 pitch | **30 pitch**, pill 32 tall (`hcvid`: 54 px / 1.8; `yt-mf`: 46.5 px / 1.5625) |
| Chip in list | 20 tall, 14 medium | 17.5 tall | **18 tall, 13 regular**, padding 0 6, gap 4, radius 3, max width 122 |
| Tooltip background | unverified | `#1F1F1F` | **`surfaceDark`** (`#1D1B16` light, `#252525` dark), radius 4 |
| Scrim | `#000 @ .56` | ~40% | **`#000 @ .56`**: light samples `#646464` over white, dark samples `#0B0B0B` over `#191919` |
| Thread pane background, dark | page | — | **`surfaceElevated` `#252525`** for the side peek, centre peek and full page (`ant-thread-*`); the list stays `#191919` |
| Keycap font | — | "mono-ish" | **iA Writer Mono S Regular 12** (bundled), as in `yt-mf-shortcuts-*` |

---

## 1. Color tokens

Light / dark. `@a` is alpha. Only these names may appear in views.

### Surfaces
| Token | Light | Dark | Use |
|---|---|---|---|
| `page` | `#FFFFFF` | `#191919` | list pane, window |
| `wash` | `#F7F7F5` | `#202020` | sidebar, settings nav, field fill |
| `elevated` | `#FFFFFF` | `#252525` | thread pane, menus, palette, composer, hover pill, modals |
| `darkSurface` | `#1D1B16` | `#252525` | tooltip, toast |
| `scrim` | `#000 @.56` | `#000 @.56` | behind the palette and modals |

### Text
| Token | Light | Dark |
|---|---|---|
| `textPrimary` | `#1D1B16` | `#D3D3D3` |
| `textRead` | `#1D1B16` | `#D3D3D3 @.85` |
| `textSecondary` | `#5F5E5B` | `#9B9B9B` |
| `textTertiary` | `#91918E` | `#7F7F7F` |
| `textQuaternary` (placeholder, disabled) | `#ACABA9` | `#FFF @.13` |
| `textContrast` (on blue or dark) | `#FFFFFF` | `#FFFFFF` |
| `textContrastSecondary` | `#D3D3D3` | `#D3D3D3` |
| `textBlue` (links, active filter) | `#2383E2` | `#2383E2` |
| `textRed` ("Draft", destructive) | `#D44C47` | `#DE5550` |
| `textOrange` (snoozed or scheduled date) | `#D9730D` | `#C77D48` |

### Icons
| Token | Light | Dark |
|---|---|---|
| `iconPrimary` | `#32302C` | `#FFF @.81` |
| `iconSecondary` (default glyph) | `#91918E` | `#FFF @.445` |
| `iconTertiary` (checkbox stroke, disabled) | `#C7C6C4` | `#FFF @.283` |

### Fills and tints
| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#2383E2` | `#2383E2` | unread dot, primary button, focus, checked box |
| `accentHover` | `#2076CB` | `#2076CB` | |
| `accentPressed` | `#1C69B5` | `#1C69B5` | |
| `hover` (tintHover) | `#000 @.04` | `#FFF @.055` | button, menu item and palette row hover |
| `pressed` (tintPress) | `#000 @.08` | `#FFF @.13` | |
| `rowHover` (tintPrimary) | `#000 @.05` | `#FFF @.055` | list row hover, sidebar selected pill, open-thread row |
| `rowSelected` | `#2383E2 @.14` | same | multi-selected rows |
| `rowSelectedHover` | `#2383E2 @.21` | same | |
| `markBackground` | `#E7F3F8` | `#1B1F22` | search `<mark>` |
| `skeleton` | `#F1F1EF` | `#373737` | loading bars |

### Borders
| Token | Light | Dark | Use |
|---|---|---|---|
| `divider` (borderDeemphasized) | `#E3E2E0 @.5` | `#FFF @.055` | row separators, group line, pane edges, header rules |
| `border` (borderRegular) | `#E3E2E0` | `#FFF @.13` | inputs, outline buttons, menus, cards |
| `focusRing` | inner 1 pt `#2383E2`, outer 2 pt `#2383E2 @.35` | same | |

Over `wash` in light, `divider` renders as `#EDECEB`, and over `page` as `#F1F1EF`. Both match the samples.

### Label chips (10 Notion colors)
| Name | Fill light | Text light | Fill dark | Text dark |
|---|---|---|---|---|
| lightGray | `#F1F1EF` | `#1D1B16` | `#373737` | `#D3D3D3` |
| gray | `#E3E2E0` | `#32302C` | `#5A5A5A` | `#FFF @.87` |
| brown | `#EEE0DA` | `#442A1E` | `#4A3228` | `#FFF @.87` |
| orange | `#FADEC9` | `#49290E` | `#5C3B23` | `#FFF @.87` |
| yellow | `#FDECC8` | `#402C1B` | `#564328` | `#FFF @.87` |
| green | `#DBEDDB` | `#1C3829` | `#243D30` | `#FFF @.87` |
| blue | `#D3E5EF` | `#183347` | `#143A4E` | `#FFF @.87` |
| purple | `#E8DEEE` | `#412454` | `#3C2D49` | `#FFF @.87` |
| pink | `#F5E0E9` | `#4C2337` | `#4E2C3C` | `#FFF @.87` |
| red | `#FFE2DD` | `#5D1715` | `#522E2A` | `#FFF @.87` |

The `hc` capture samples exactly `#F1F1EF`, `#E8DEEE` and `#D3E5EF`. A Gmail label color maps to the nearest name by hue. A label with no color, or a system label, is `lightGray`.

### Shadows (`Theme.Elevation`)
Every level is a 1 pt ring plus blur layers. The ring is `#E3E2E0 @.5` in light and `#313131` in dark, drawn as a stroke overlay. A CSS blur of N becomes a SwiftUI radius of N/2.
| Level | Light layers (y, blur, alpha black) | Dark | Use |
|---|---|---|---|
| `l1` | (2, 4, .04) | (2, 4, .08) | hover-action pill, chips on hover |
| `l2` | (4, 12, .08) | (4, 12, .16) | inline reply card, toast |
| `l3` | (2, 4, .06) + (12, 32, .12) | (12, 36, .40) | menus, popovers, tooltips |
| `l4` | (4, 12, .14) + (32, 48, .28) | (20, 48, .56) | palette, composer, modals |

---

## 2. Typography

SF Pro (system) everywhere, with antialiasing on. Avatar initials use SF Pro Rounded. Keycaps use iA Writer Mono S. Inter and Lyon are never used, so they are not bundled. Line heights are fixed: each text block gets `.frame(height:)` or `lineSpacing` to reach the listed value. Text is single-line with a tail ellipsis unless it is marked "wraps".

| Token | Size / line height | Weight | Color | Where |
|---|---|---|---|---|
| `threadTitle` | 22 / 26 | semibold | textPrimary | reader subject (wraps) |
| `sectionTitle` | 17 / 22 | semibold | textPrimary | settings page and shortcuts section titles |
| `emptyTitle` | 17 / 22 | medium | textPrimary | empty state |
| `paletteInput` | 18 / 24 | regular | textPrimary; placeholder textQuaternary | cmd-K input |
| `body` | 14 / 20 | regular | textPrimary | sidebar items (textSecondary), buttons, menus, palette rows, composer fields, message header |
| `bodyMedium` | 14 / 20 | medium | textPrimary | list-pane title, sender name in the message header, chips on the reader, toast |
| `list` | 13 / 16 (row is 38) | regular | textRead | read sender and subject |
| `listUnread` | 13 / 16 | semibold | textPrimary | unread sender and subject |
| `listSecondary` | 13 / 16 | regular | textTertiary | snippet, thread count "2", date (tabular numbers) |
| `groupHeader` | 13 / 16 | medium | textPrimary | "Yesterday", "Last 7 days", "March" |
| `small` | 12 / 16 | regular | textTertiary | shortcut hints, palette footer, secondary lines |
| `smallMedium` | 12 / 16 | medium | textTertiary | sidebar section labels ("Views", "Mail", "Labels") and sidebar counts (textSecondary) |
| `smallSemibold` | 12 / 16 | semibold | textSecondary | palette group labels ("Inbox", "Navigation") |
| `keycap` | iA Writer Mono S 12 / 16 | regular | textSecondary | shortcut keycaps |
| `mailBody` | 14, line height 1.71 (24) | regular | textPrimary | email body CSS and composer body |

---

## 3. Metrics (`Theme.Metrics`)

| Name | Value |
|---|---|
| Window minimum | 900 × 600; default 1280 × 800 |
| Sidebar | 240 default, 220 min, 480 max; 1 pt `divider` on the trailing edge |
| Traffic lights | inside the sidebar, centres at x 21 / 41 / 61, y 24; hidden titlebar, full-size content |
| Pane toolbar height | 48, title centred at y 24 |
| Row height | 38 |
| Row inset (row box to pane edge) | 14 each side, radius 8 |
| Group header height | 56 (hairline at y 48) |
| Sidebar item | 30 tall on a 32 pitch, inset 8, radius 6, icon slot 20, gap 8 |
| Icon sizes | 14 / 16 / 20 / 24 |
| Button heights | 28 small, 32 medium; radius 6 |
| Chip | 18 list, 20 reader; radius 3 |
| Reader column | max 800 plus 42 padding each side |
| Palette | 720 × 520, radius 12, input 48, rows 36, footer 32 |
| Composer | 600 wide, radius 12, inset 16 from the bottom-right, fields 32 |
| Menu | radius 8, padding 6 vertical, items 28, item radius 6, inset 4 |
| Toast | 40 tall, radius 6, bottom 20, leading = pane + 16 |

---

## 4. Screens

### 4.1 Window shell
- Two fixed columns: the sidebar (`wash`) and the content pane (`page`). The thread opens as a **side peek** over the right of the content pane (§4.4).
- There is no visible title bar or toolbar chrome. The traffic lights sit on the sidebar's `wash`. The content area runs under the title bar and the content supplies its own 48 pt header.
- `⌘\` toggles the sidebar. The toggle slides over 0.2 s with ease `(0.16, 1, 0.3, 1)`.

### 4.2 Sidebar (`hc-inbox-view-labels-light-2x`, `ant-inbox-sidebar-dark`)
From the top (y is window coordinates):
1. **Title-bar strip**: 40 tall, holding the traffic lights. Nothing else.
2. **Account row**, centred at y 62:
   - 20 pt avatar at x 18: a circle with its initial in SF Rounded semibold 12, on an `accent` circle with white text (the account color).
   - Name at x 44 in `body` medium textPrimary, then a 12 pt chevron-down in iconSecondary.
   - A **compose** icon button (square-and-pencil, 20 glyph in a 28 × 28 hit area, radius 6) whose right edge sits 12 from the sidebar edge.
   - With an email line, the name moves up 8 and the email sits below it in `small` textTertiary.
3. **Search row**: a sidebar item at y 100 with a magnifier icon and the label "Search" in textSecondary. It opens the palette in search mode.
4. A 26 pt gap, then the section label **"Views"** at x 18, `smallMedium` textTertiary, 30 tall. A "+" icon appears at the right on hover.
5. Items: Inbox (red tray icon), Starred, then labels the user has pinned as views. Then "Mail": All Mail, Sent, Drafts, Spam, Trash. Then "Labels": each label with a 10 pt colored dot icon. Then **"Calendar"**: today's events as 2-line items (§5.10).
6. Footer, pinned: a 1 pt `divider` top rule, 45 tall, with a Settings gear (16) and a "?" help button (16) at the right.

**Sidebar item** (see §5.1): the counts are the unread counts in `smallMedium` textSecondary, right-aligned 12 from the pill's trailing edge. Inbox, Sent and so on use outline monochrome icons in iconSecondary. Only Inbox uses the red tray, `#E16259`.

### 4.3 Inbox, the thread list (`hc-inbox-view-labels-light-2x`, `yt-mf-inbox-grouped-date-chips`, `ant-view-grouped-by-date-dark`)
**Header, 48 tall:**
- Left at pane + 74: a 16 pt view icon, then the title in `bodyMedium` 8 pt after it, centred at y 24.
- When hovering the header, or while anything is selected, a 14 pt select-all checkbox appears at pane + 24.
- Right: 28 × 28 icon buttons (16 glyph, iconSecondary) at a 30 pitch, ending 18 from the window edge: Filter (three lines, `accent` while a filter is active), Display (sliders), Refresh.
- No "Auto label" button. That feature is AI.
- In **bulk mode**, when one or more rows are selected, the title is replaced by: checkbox, chevron, a 1 pt × 16 `divider`, then icon buttons for read, archive, remind, trash, spam and label. The right side shows "N selected" in `body` textTertiary.

**Groups (date grouping):**
- Groups are Today (no header when it comes first), Yesterday, Last 7 days, Last 30 days, then month names ("March"), with "Dec 2024" style labels for earlier years.
- A group header (§5.3) is 56 tall.
- Between two groups nothing else changes. The header height alone supplies the whitespace.

**Rows:** see §5.2, 38 tall. The list scrolls under the header. The header has no background change and no divider while scrolling.

**Column geometry**, in pane coordinates. W is the window width and P is the pane width:
| Element | x |
|---|---|
| Row box | 14 … P−14 |
| Checkbox (hover, selected or bulk) | 14 × 14 at x 24, vertically centred |
| Unread dot | 6 × 6, centre x 55 |
| Sender | x 69, width `S = round(0.16 × W)` (min 150, max 260), then a 14 gap |
| Subject + snippet | x 69 + S + 14 … chips |
| Label chips | right-aligned, ending at P − 54 − 120, gap 4, max 3 then "+N" |
| Date column | 120 wide, text right-aligned at P − 54 |
| Hover-action pill | replaces the date; right edge at P − 17, 3 pt inset from the row's top and bottom |

Separators run from the sender's x to the date's right edge.

### 4.4 Thread (side peek) (`tjf-three-pane-…-2x`, `yt-mf-thread-sidepeek-header`, `ant-thread-sidepeek-dark`, `zp-thread-multimessage`)
**Panel:**
- Anchored to the right of the content pane, full height, background `elevated`.
- 1 pt `divider` on its leading edge plus a leftward shadow (x −4, blur 12, black @.04 light / @.3 dark).
- Width `max(520, 0.58 × contentWidth)`. The list behind it keeps its layout and is clipped under the panel. It does not reflow.
- The open thread's row keeps `rowHover` fill.
- Opens by sliding in 16 pt with an opacity fade over 0.2 s `(0.16, 1, 0.3, 1)`. Closes with Esc.

**Toolbar, 44 tall, no divider:**
- Left: collapse "»" (16), then prev "∧" and next "∨" (16) at a 32 pitch. Disabled buttons use iconTertiary.
- Right, at a 32 pitch: remind (clock), mark unread (square with dot), label (tag), archive (box), trash, "⋯". All are 16 glyphs in 28 hit areas.

**Subject block:**
- Padding 12 42 16 42.
- `threadTitle` (wraps).
- 8 below it, a chip row: "N attachments" (paperclip 14 plus `body` textTertiary) when there are attachments, then label chips at 20 tall, then "Add label" in `body` textQuaternary. Gap 8.
- A 1 pt `divider` spans the panel 16 below the chips.

**Collapsed message** (all but the last and the selected ones):
- One line, 44 tall, padding 0 42: sender `body` textPrimary, then snippet `body` textTertiary after 10, then date `body` textTertiary right-aligned.
- `divider` below. `hover` fill on hover.

**Expanded message:**
- Header at padding 16 42 0:
  - Line 1: sender name in `bodyMedium`, then the email in `body` textTertiary 6 after it. At the right: reply and forward icon buttons (16), then the date in `body` textTertiary.
  - Line 2: "To me, Alex" in `body` textTertiary.
  - 4 between the lines.
- Body padding 24 42 (the body wrapper adds 4 horizontal).
- The selected message (n/p) shows a 4 pt `accent` bar at the panel's left edge, full message height.

**"Show N more messages"**, when more than 4 are collapsed: a centred pill `elevated`, `border` 1 pt, radius 12, 24 tall, `smallMedium` textSecondary, drawn over a 1 pt `divider` line.

**Bottom:**
- With no reply open: three outline buttons (32 tall) "Reply", "Reply all", "Forward", each with a 16 icon, gap 8, left-aligned at x 42, 24 below the last message.
- `r`, `a` or `f` swaps them for the inline reply card (§5.6).

**HTML body:**
- `WKWebView`, JavaScript off, CSP `default-src 'none'; img-src data: cid:; style-src 'unsafe-inline'`. Remote images are blocked until the per-sender allow button is used.
- Base CSS: 14 px system-ui, line-height 1.71, color textPrimary, `p{margin:0}`, `blockquote{border-left:3px solid border; padding:3px 2px 3px 14px}`, `a{color:textSecondary; text-decoration-thickness:.05em; text-underline-offset:3px}`.
- The web view is sized to its content height. There is no inner scroll; the panel scrolls.
- **Dark mode**: plain-text and simple-HTML mail renders on transparent with dark tokens. Rich mail with its own light backgrounds gets `filter: invert(1) hue-rotate(180deg)` on the root, with images inverted back. It is never shown as a white slab.

### 4.5 Composer (`yt-kw-compose-panel-empty`, `yt-mf-drafts-view-compose`, `tjf-inline-reply-send-2x`)
**New message: a floating panel.**
- 600 wide, bottom-right inset 16, top at 142 (height = window − 158, clamped to 420…720).
- `elevated`, radius 12, `l4` shadow.
- Top-right: minimise "–" and close "×", 16 glyphs in 28 buttons, 12 from the edges.
- Minimised: 300 × 48 with the subject (or "New message") in `bodyMedium`.

**Fields.** Each row is 32, padding x 16, no borders between rows:
1. **From**: name in `body` textPrimary, then the email in textTertiary. With several sendAs aliases, a 12 chevron opens a menu.
2. **To**: recipient chips ("Name ×": 20 tall, radius 3, `lightGray` fill, `body`), then an input with the placeholder "Add recipient" in textQuaternary. "Cc/Bcc" in `body` textTertiary sits right-aligned and adds Cc and Bcc rows.
3. **Subject**: placeholder "Subject".
4. A 1 pt `divider` full width.

**Body:**
- Padding 16. `mailBody`. Placeholder "Write, or press '/' for commands…" in textQuaternary.
- The signature is inserted after one empty line, preceded by "--" in textTertiary. It is editable.
- A reply's quoted text collapses to a "…" button (textTertiary, 24 × 16, `hover`).

**Footer:**
- 60 tall, padding 16.
- Left: the **Send split button**, 28 tall and 80 wide. "Send" is `body` semibold white on `accent`. Radius 6. A 24-wide chevron segment is separated by a 1 pt `#FFF @.25` line. The chevron opens "Send later…" and "Send & archive".
- 12 after the button, the status in `body` textTertiary: "Draft saved", "Saving…" or "Sending…".
- Right: attach (paperclip), snippets `{}`, insert event (calendar) and discard (trash). 16 glyphs at a 32 pitch, iconSecondary.

### 4.6 Command palette (`yt-mf-palette-*`, `ant-palette-dark`, `cache-cmd_f0`, `cache-cmdk`)
**Frame:**
- `scrim` over the whole window.
- Panel 720 wide (min(720, window − 80)), horizontally centred, top at 12.5% of the window height.
- Height up to 520, shrinking to its content.
- `elevated`, radius 12, `l4`.

**Input row:**
- 48 tall. Magnifier 16 at x 16 in iconSecondary. Text at x 44 in `paletteInput`.
- Placeholder: "Search commands or mail…". In the thread context it is "Type a command or search…".
- A 1 pt `divider` below.

**Results:**
- Padding 4 8. Scrolls. The scrollbar only shows while scrolling.
- Group label: `smallSemibold` textSecondary, 28 tall, padding x 8, 12 top spacing. The first group has 4.
- Row (§5.5), 36 tall.

**Footer:**
- 32 tall, 1 pt `divider` above.
- "⇅ Select   ↵ Open" in `small` textTertiary, at x 16, gap 16.

**Groups, in order when the query is empty:**
- Thread (only when a thread is open or selected): Mark as read `U`, Archive `E`, Trash `#`, Reply `R`, Reply all `A`, Forward `F`, Star `S`, Add label `L`, Save to Notion, Link to Notion page.
- Inbox: Compose `C`, Select all `⌘A`.
- Navigation: Go to Inbox `G then I`, Sent `G then T`, Drafts `G then D`, Starred `G then S`, All Mail `G then A`, Spam `G then !`, Trash `G then #`, then each label.
- Misc: Shortcuts `?`, Set theme · Light, Set theme · Dark `⌘⇧L`, Set theme · System.

**Typing:**
- Filters the commands by fuzzy match.
- Adds a "Threads" group of search results (§5.5b) and a "Contacts" group.
- Enter on the query itself runs a full search (§4.7).

### 4.7 Search results
- These appear in the list pane with the normal header. The title is a magnifier icon plus the query in `bodyMedium`, and "N results" in `body` textTertiary 8 after it.
- The list uses the normal row (§5.2) with no date groups, sorted by date.
- Matched terms in the subject and snippet are wrapped in `<mark>`: `markBackground`, text `accent`, weight semibold, radius 2.
- The source line sits under the header at 28 tall, padding x 74: "Searched this Mac" or "Searching Gmail…" with the 3-dot loader, in `small` textTertiary.
- With no results: the empty state with "No results" / "Try different words or a Gmail operator like from: or has:attachment".

### 4.8 Empty, loading and error states
**Empty mailbox** (`hc-inbox-empty-groups-popover-2x`, `shutdown-*`):
- A column centred horizontally in the pane, 80 below the header.
- The mailbox-and-dog line art is 200 × 130. `cache-mailbox.png` and `cache-dog.png` are layered and templated to textPrimary, so the ink follows the theme. The dog's fill is `page`.
- 16 below the art, the title "No mail here!" in `emptyTitle`.
- 4 below the title, the body "Rest easy, no mail carriers in sight." in `body` textSecondary, centred and wrapping at max 320.

**Loading list** (`cache-inbox-preview`):
- 8 skeleton rows at the 38 row pitch.
- Each row has a pill bar (radius 7, 14 tall, `skeleton`) at the sender x, 90–130 wide, and a second bar at the subject x, 180–320 wide.
- The widths come from a fixed pseudo-random sequence, so they never jump between frames.
- Opacity pulses between .5 and 1 over 1.2 s ease-in-out.
- No spinner. The header shows the real title immediately.

**Loading inline** (search or sending): three 4 × 4 dots in textQuaternary, gap 2. They bounce 2 pt with 0.5 s alternate and delays of 0, .2 and .4.

**Error:**
- The list pane shows the empty-state layout without art: title "Couldn't load mail" and body = the error message, plus an outline button "Retry".
- Transient failures show a toast.

**Toast** (§5.8): bottom-leading.

### 4.9 Settings (signature) (`yt-kw-settings-signature`, `ant-settings-*`)
**Frame:**
- A modal over the scrim, inset 40 from the window, radius 12, `l4`.
- Left nav 250 wide on `wash`: group labels "Account" (`smallMedium` textTertiary), then sidebar-style items (Inbox, Signature, Integrations, Shortcuts).

**Content:**
- Padding 32 48, max width 720.
- Title in `sectionTitle`, then a 1 pt `divider` 12 below it.
- Rows are 56 tall. On the left: name in `body` medium, with the description below it in `small` textSecondary. On the right: the control (toggle in `accent`, pop-up "Light ⌄" in `body` textSecondary, or an outline button).

**Signature page:**
- "Include on replies and forwards" toggle.
- A per-alias picker.
- A plain editor box: `border` 1 pt, radius 6, min height 120, padding 12, `mailBody`.
- A "Save to Gmail" primary button, right-aligned.

---

## 5. Components

### 5.1 Sidebar item
- Frame 30 tall, horizontal inset 8 (width = sidebar − 16), radius 6. Padding: leading 8 + 12 × depth, trailing 9.
- Icon slot 20 × 20 (16 glyph, iconSecondary), then a gap of 8, then the label in `body`.
- The label is textSecondary. It is **textPrimary when selected**. It does not bold.
- Count: `smallMedium` textSecondary, trailing, padding x 3. Hidden when 0.

| State | Background |
|---|---|
| rest | clear |
| hover | `hover` (100 ms ease-out) |
| pressed | `pressed` |
| selected | `rowHover` (renders `#EAEAE8` light / `#2C2C2C` dark) |

### 5.2 Thread row
- Height 38. The whole row is one hit target.
- Radius 8, but a corner that touches an adjacent hovered or selected row is 0, so runs merge into one shape.

**States.** Every state is an overlay, so nothing moves:
| State | Background | Content |
|---|---|---|
| rest, read | clear | sender and subject `list` textRead, dot hidden (opacity 0, still in layout) |
| rest, unread | clear | sender and subject `listUnread`, dot `accent` |
| hover | `rowHover` | checkbox shown (iconTertiary 1.5 pt stroke, radius 3), date hidden, hover-action pill shown |
| keyboard focus (j/k cursor) | `rowHover` | the same as hover but without the pill. If the mouse hovers another row, only the focused row keeps the fill. |
| open in the peek | `rowHover` | |
| selected (x or ⇧-click) | `rowSelected` | checkbox checked: `accent` fill with a white check |
| selected + hover | `rowSelectedHover` | |

**Content, left to right:**
- Checkbox.
- Dot.
- Sender: names joined by ", " with "me" for self. It truncates. The thread count follows as " 3" in `listSecondary`, and a draft adds "Draft" in textRed after 6.
- Subject, then the snippet after 6 in `listSecondary`. They share one line; the subject keeps priority and the snippet truncates first.
- Chips (§5.4, 18 tall).
- An attachment paperclip 14 in iconSecondary when there is an attachment.
- Date in `listSecondary`, tabular: "11:32 PM" today, "Mar 6" this year, "Dec 25, 2024" for older.
- Separator: 1 px `divider` at the bottom from the sender's x to the date's right edge. It is hidden when the row or its neighbour below has a background.

**Hover-action pill:**
- `elevated`, radius 8, `l1`, height 32, 3 pt inset.
- 28 × 28 icon buttons (20 glyph, iconSecondary, radius 6, `hover`) at a 30 pitch with 1 pt end padding.
- Actions: Star, Archive, Trash, Read/unread, Remind.
- Clicking one never opens the row.
- Icon tooltip, after a 500 ms delay: §5.9.

**Mark read on open:** the dot fades out over 150 ms and the weight changes on the same frame. This is optimistic.

### 5.3 Date-group header
- 56 tall. Label `groupHeader` at x 71 (pane coordinates), centred 28 from the top.
- 1 px `divider` from x 55 to P − 38 at y 48.
- A hover shows "Collapse" in `groupHeader` textTertiary after the label, 6 after it. An empty group shows "(Empty)" in textTertiary.

### 5.4 Label chip
- List: height 18, padding 0 6, radius 3, `list` (13 regular). Reader: height 20, `body`, radius 3.
- Fill and text come from the chip color (§1). Max width 122 in the list, with the text truncating inside it.
- Remove "×" (reader, on hover): 12 glyph at 50% of the text color.

### 5.5 Palette row
- Height 36, padding 0 8, radius 6, gap 10.
- Icon 16 in iconSecondary in a 20 slot. Label `body` regular textPrimary.
- Right-aligned shortcut hint (`small` textTertiary, min width 78), in the format "G then T", "⌘⇧L".
- Hover or keyboard selection gives `hover` fill (sampled `#F2F2F2` light / `#313131` dark). The mouse moves the selection. Arrow keys move it and scroll it into view.
- **Thread result (5.5b)**: 48 tall, radius 8, a 24 avatar, the subject in `body` medium, with "from · snippet" below it in `small` textTertiary, and the date in `small` medium textSecondary at the right.

### 5.6 Inline reply card
- Inset 16 from the panel sides, `elevated`, 1 pt `border`, radius 8, `l2`.
- Header 40:
  - A reply-type icon button (reply, reply all or forward, with a menu).
  - Recipient chips at 12 after it.
  - "Cc/Bcc" in `body` textTertiary and "⋯" at the right.
- `divider`, then the body (§4.5 body), then the footer (§4.5 footer).

### 5.7 Buttons
All buttons have a 1 pt border, clear when the style has none. Transitions are 100 ms ease-out.
| Style | Rest | Hover | Pressed | Label |
|---|---|---|---|---|
| primary | `accent` | `accentHover` | `accentPressed` | `body` semibold textContrast |
| outline | clear, `border` | `hover` | `pressed` | `body` medium textPrimary, icon iconPrimary |
| ghost (icon button) | clear | `hover` | `pressed` | iconSecondary glyph |
| destructive text | clear | `hover` | `pressed` | textRed |

- Heights: 28 (small: padding x 8, gap 4), 32 (medium: padding x 12). Radius 6.
- Icon-only: square 28, radius 6.
- Disabled: opacity .4, no hover.
- Keyboard focus: `focusRing`.

### 5.8 Toast
- `darkSurface`, radius 6, height 40, padding x 12, `l2`.
- Text in `bodyMedium` textContrast. An optional action ("Undo") in `bodyMedium` textContrastSecondary with its keycap hint `Z`.
- Width fits the content, min 240, max 420.
- Enters by rising 8 pt with a fade over 0.2 s. Lasts 5 s (4 s without an action). Hover pauses the timer.
- One toast at a time; a new toast replaces the current one.

### 5.9 Tooltip
- `darkSurface`, radius 4, padding 4 8.
- Title `small` medium textContrast. An optional shortcut 8 after it, in textContrastSecondary @ .6.
- Placed 6 below its anchor. Appears after 500 ms (2 s on sidebar items). No animation.

### 5.10 Menus and popovers
- `elevated`, 1 pt `border`, radius 8, `l3`, padding 6 0, width 240 (260 for filter menus).
- Item: 28 tall, inset 4, radius 6, padding 0 8, gap 8. Icon 16 in iconSecondary, label `body`. Right side: value or chevron in textTertiary.
- Hover `hover`.
- Section label: `small` medium textTertiary, 26 tall.
- Separator: `divider` with 6 vertical margin.
- A destructive item goes last, after a separator.

**Calendar sidebar item:** time "9:30" in `small` textTertiary at 36 wide, then the title in `body` textSecondary, with the location on the second line in `small` textTertiary. 44 tall. A 3 × 16 color bar in the event color at the leading edge.

### 5.11 Keycap
- Height 20, min width 20, padding x 5, radius 4.
- Fill `wash`, 1 pt `border`, text `keycap`.
- Joined by "then" or "or" in `small` textTertiary with gap 4.

### 5.12 Search / text field
- Height 32, radius 6, fill `wash`, 1 pt `border`, padding x 10.
- Text `body`, placeholder textQuaternary. With a magnifier: 16 glyph at x 10, text at x 32.
- Focus: `focusRing`, and the fill turns `elevated`.

### 5.13 Avatar
- A circle. The fill is `elevated` with a 1 pt `divider` ring (initial in iconSecondary), or a solid label color for the account.
- The initial is SF Rounded semibold at 0.6 × size (16 → 10, 20 → 12, 24 → 14, 32 → 16).

---

## 6. Interaction and motion

| What | Behaviour |
|---|---|
| Standard ease | `timingCurve(0.16, 1, 0.3, 1, duration: 0.2)` (`Theme.Motion.standard`) |
| Hover backgrounds | 100 ms ease-out in, instant out (`Theme.Motion.hover`) |
| Row removal (archive, trash) | the row collapses its height to 0 over 0.2 s standard ease and the rows below slide up. Focus moves to the next row, or the previous row if it was last. |
| Undo (`z`) | the row reinserts with the reverse animation, and the toast dismisses |
| Peek open or close | 0.2 s standard: a 16 pt slide plus fade. The list never reflows. |
| Palette | scrim fades 150 ms. The panel scales from 0.98 and fades over 150 ms. On close, 100 ms fade. |
| Composer | rises 12 pt with a fade over 0.2 s. Minimising animates the frame. |
| Keyboard focus | j/k moves the focused row. The list scrolls only when the row leaves the visible area, and then by the minimum amount. The focused row is always visible. |
| Focus ring | only on keyboard focus of controls (buttons, fields), never on list rows |
| `⌘K` or `/` | opens the palette. Esc closes the topmost layer: palette, then composer, then peek, then selection. |
| Triage keys | `j`/`k`, `enter`/`o` open, `e` archive, `#` trash, `s` star, `⇧U` unread, `⇧I` read, `u` toggle, `l` label, `x` select, `z` undo, `r`/`a`/`f` reply / reply all / forward, `c` compose, `g i`, `g t`, `g d`, `g s`, `g a` go-to (1 s chord window), `?` shortcuts |
| Scrollbars | overlay only; the system default is fine |
| Text selection color | `#2383E2 @ .28` |

Nothing may change size between states. Bold versus regular text must not shift layout: the sender and subject columns have fixed widths or truncate. Empty, loading and loaded states all keep the same header.

---

## 7. "Must match" checklist (graded per snapshot)

Graders compare the snapshot against the named reference at the same theme. Every item is pass/fail.

### sidebar (`hc-inbox-view-labels-light-2x`, `ant-inbox-sidebar-dark`)
- [ ] Background is `#F7F7F5` / `#202020`, with a 1 pt divider at the trailing edge (`#EDECEB` / ≈`#2B2B2B`).
- [ ] Traffic lights sit on the sidebar color. There is no separate title-bar band.
- [ ] Items sit on a 32 pitch. The selected pill is 30 tall, 8 inset, radius 6, `#EAEAE8` / `#2C2C2C`.
- [ ] Unselected labels are grey `#5F5E5B`, the selected label is near-black, and none of them bold.
- [ ] "Views" and "Mail" labels are 12 pt grey `#91918E`, with ≈26 pt above each section.
- [ ] Counts are right-aligned and grey, and no count is clipped.
- [ ] The footer has a top divider and 16 pt icons, and nothing overlaps the last item.

### inbox (`hc-inbox-view-labels-light-2x`, `yt-mf-inbox-grouped-date-chips`, `ant-view-grouped-by-date-dark`)
- [ ] Header is 48 tall, with the title 14 medium next to a 16 icon and three 16 icons at the right. There is no "Auto label".
- [ ] Rows are exactly 38 apart. Sender and subject are 13 pt. Unread is semibold; read is regular.
- [ ] The unread dot is 6 pt `#2383E2`, centred 55 from the pane edge, and read rows keep the gap.
- [ ] Sender column ≈16% of the window width. Subjects in all rows start at the same x.
- [ ] Dates are right-aligned on one edge, grey, and tabular ("11:32 PM", "Mar 6").
- [ ] Chips are 18 tall, radius 3, pastel fill with dark same-hue text, and end ≈120 left of the date edge.
- [ ] Hairline separators appear between rows, with none after a group's last row.
- [ ] Group headers are 13 medium with a full-width hairline 8 above the first row, and 56 total.
- [ ] Dark: the list is `#191919`, read rows are visibly dimmer than unread, and chips are dark fills.
- [ ] No text is clipped vertically. Descenders (g, y, p) are fully visible.

### row states (`yt-mf-row-hover-actions-tooltip`, `hcvid-row-hover-actions-grouped`, `ant-selected-rows-bulk-toolbar-dark`)
- [ ] Hover: a rounded (8) grey fill 14 inset from the pane sides, and a checkbox appears at the left.
- [ ] Hover: the date is replaced by a white pill (radius 8, hairline ring, soft shadow) of 20 pt icons at a 30 pitch.
- [ ] Selected rows are blue-tinted (`#2383E2` @ .14) with checked blue checkboxes, and adjacent selected rows merge into one shape.
- [ ] Bulk header shows the checkbox, action icons and "N selected" at the right.
- [ ] Row contents do not shift by even 1 pt between rest, hover and selected.

### thread (`tjf-three-pane-…-2x`, `yt-mf-thread-sidepeek-header`, `ant-thread-sidepeek-dark`, `zp-thread-multimessage`)
- [ ] The peek sits over the right ≈55–60% of the content, with a divider line. The list is clipped, not squeezed.
- [ ] The open row in the list keeps a grey fill.
- [ ] Toolbar: » ∧ ∨ at the left, and 16 pt action icons at a 32 pitch at the right. There is no divider under it.
- [ ] Subject is 22 semibold at x 42, then the chip row, then a full-width divider.
- [ ] Collapsed messages are single 44 pt lines: sender, grey snippet, date.
- [ ] Expanded header: name medium plus grey email, "To me" grey below it, and the date at the right.
- [ ] Body text is 14 pt at ≈24 pt line height, never clipped, and the panel scrolls as one piece.
- [ ] Dark: the peek panel is `#252525`, lighter than the `#191919` list. The email body is not a white rectangle.
- [ ] Reply / Reply all / Forward outline buttons, or the reply card, sit at the bottom.

### compose (`yt-kw-compose-panel-empty`, `yt-mf-drafts-view-compose`)
- [ ] A floating panel 600 wide, bottom-right inset 16, radius 12, with a large soft shadow.
- [ ] From, To and Subject rows at a 32 pitch with no row borders, then one divider.
- [ ] Placeholders are grey. "Cc/Bcc" is right-aligned grey.
- [ ] The Send split button is blue, 28 tall and ≈80 wide with a chevron segment, at the bottom-left, with "Draft saved" grey beside it.
- [ ] Four grey 16 pt icons at the bottom-right on a 32 pitch.
- [ ] The signature shows in the body, below "--".

### palette (`yt-mf-palette-top`, `ant-palette-dark`, `cache-cmd_f0`)
- [ ] The scrim darkens the whole window, including the sidebar.
- [ ] Panel ≈720 wide, centred, top ≈12.5% down, radius 12.
- [ ] Input 48 tall with an 18 pt placeholder "Search commands or mail…" and a divider below it.
- [ ] Group labels 12 semibold grey. Rows 36 tall with an icon, a 14 label and a right-aligned grey hint.
- [ ] The first row is preselected with a light grey fill, radius 6, inset 8.
- [ ] Footer: "⇅ Select ↵ Open" 12 grey above a divider.
- [ ] Dark: panel `#252525`, selected row `#313131`.

### search (`ant-palette-dark` style, list layout)
- [ ] Results use the exact inbox row layout, with no date groups.
- [ ] Header shows the magnifier, the query and a grey count.
- [ ] Matched terms are highlighted with a pale blue background and blue semibold text.

### empty (`hc-inbox-empty-groups-popover-2x`, `shutdown-*`)
- [ ] The mailbox-and-dog line art is centred and follows the theme ink (dark ink in light, light ink in dark).
- [ ] Title 17 medium and a grey 14 subtitle, centred and not clipped.
- [ ] The header remains in place.

### loading (`cache-inbox-preview`)
- [ ] Rounded grey skeleton bars at the 38 row pitch, in the sender and subject columns. No spinner.

### settings (`yt-kw-settings-signature`, `ant-settings-thread-style-dark`)
- [ ] Modal with a `wash` left nav at 250, and the title 17 semibold above a divider.
- [ ] Rows 56 tall: medium name plus grey description at the left, control at the right. Toggles are blue.
