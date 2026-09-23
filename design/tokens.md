# Notion Mail design tokens

These values were extracted from the real Notion Mail web bundle that the Electron app cached locally. Nothing here is estimated unless it is marked **(unverified)**.

## Sources

| tag | file | where it came from |
|---|---|---|
| **[M]** | `nmail-main.c484b3090d159047bf7e.js`, 9.05 MB decompressed | This is the last full build before the shutdown. It is Chromium HTTP cache entry `~/Library/Application Support/Notion Mail/Partitions/notionmail/Cache/Cache_Data/6fb85f246fa76e6d_0`, brotli-compressed. `@N` is the character offset in the decompressed file. |
| **[S]** | `nmail-main.5543c33883b67b5f3941.js` | This is the shutdown build, taken from the Service Worker CacheStorage in `.../Service Worker/CacheStorage/55d5…/b151…/807e834b7f9154e9_0`. It holds the same design system: the palette and semantic map were diffed against [M] and are identical. |
| **[CSS]** | `app.global.css` | This is the css-loader module inlined in both bundles, at [M]@424677. |

- The app has **no standalone CSS files**. All UI styling is styled-components template literals.
- The design system is the internal `./notion-ui/*` package:
  - `notion-ui/colors/notion-colors.ts`
  - `notion-ui/components/Typography/*`
  - `notion-ui/constants.ts`
  - `notion-ui/types.ts`
- Mail-specific constants live in:
  - `src/constants/mailbox.constants.ts`
  - `src/constants/sidebar.constants.ts`
  - `src/constants/thread.constants.ts`
- Component identifiers such as `Y_e` or `nne` are minified names in [M].
- A display name is quoted wherever React kept one (`displayName="SidebarItem"`).
- The extraction scratch copies (decompressed bundles and resolved `tokens.json`) are in the session scratchpad. They are not committed.

## 1. Fonts

**The whole UI uses the system font.** Every text style in `notion-typography.tsx` uses `baseFontFamily.sans`:

```
sans:  ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, "Apple Color Emoji", Arial, sans-serif, "Segoe UI Emoji", "Segoe UI Symbol"
serif: Lyon-Text, Georgia, ui-serif, serif
mono:  iawriter-mono, Nitti, Menlo, Courier, monospace
githubMono (code in compose/email): "SFMono-Regular", Menlo, Consolas, "PT Mono", "Liberation Mono", Courier, monospace
emoji: 'Apple Color Emoji', 'Segoe UI Emoji', NotoColorEmoji, ...
```

Source: [M] module `./notion-ui/components/Typography/notion-typography.tsx` (@1780213).

- On macOS the sans stack resolves to **SF Pro**. In SwiftUI, use `.system(size:weight:)` with the default design.
- The global rule `* { font-family: <sans>; line-height: 1.4; -webkit-font-smoothing: antialiased }` comes from [CSS].
- **Avatar initials** use `ui-rounded, -apple-system, …`, which is **SF Pro Rounded**, so use `.system(.., design: .rounded)`. Source: [M] notion-ui avatar `f=(0,d.Ay)(m.o5)` @49496.
- `@font-face` rules in [CSS] declare these families:
  - `inter-var`: Inter-Var.woff2, with weight aliases 350→wght 290, 430, 544, 586 and 669.
  - `Lyon-Text` at 400/600, regular and italic.
  - `iawriter-mono` at 400/600, regular and italic.
  - `permanent-marker` and `Roboto` 500.
- **None of these families is used by any mail UI text.**
  - `inter-var` has no reference outside `@font-face`.
  - Lyon and iA Writer only appear through `getHeaderFontFamily({pageFont})`, which is used for Notion-page blocks.
- Treat the bundled fonts as optional extras, for example a mono font for code, and not as the UI face.

**Font weights** (`notion-typography.tsx` `fontWeight`):

| name | CSS | SwiftUI |
|---|---|---|
| light | 200 | `.ultraLight` |
| regular | 400 | `.regular` |
| medium | 500 | `.medium` |
| semibold | 600 | `.semibold` |
| bold | 700 | `.bold` |

One exception: the settings page title uses `font-weight: 590` at 20/25px ([M] `Tit` @8426812).

**Font files copied to `Fonts/`** (converted with fontTools, woff2 → sfnt):
- Every file registers with `CTFontManagerRegisterFontsForURL` (verified).
- Every file is TrueType-flavoured (`0x00010000`), so all of them are `.ttf`.

| file | PostScript name | source asset | licence |
|---|---|---|---|
| `Inter-Var.ttf` | `Inter` (variable: wght 100–900, slnt −10–0) | `c2fe3cb2b7c746f7966a.woff2` | OFL, committable |
| `iAWriterMonoS-Regular.ttf` | `iAWriterMonoS-Regular` | `94bc22198e6b6a5fbe0f.woff2` | OFL |
| `iAWriterMonoS-Italic.ttf` | `iAWriterMonoS-Italic` | `33749a44a4a0ea163ea2.woff2` | OFL |
| `iAWriterMonoS-Bold.ttf` | `iAWriterMonoS-Bold` | `59f9cfdd29de5ae7c38a.woff2` | OFL |
| `iAWriterMonoS-BoldItalic.ttf` | `iAWriterMonoS-BoldItalic` | `5e4cedd5bd9fd10e9005.woff2` | OFL |
| `LyonText-Regular.ttf` | `LyonTextWeb-Regular` | `7cc342aa0ccab978b116.woff2` | **commercial**, gitignored (`Fonts/Lyon*`), personal use only |
| `LyonText-RegularItalic.ttf` | `LyonTextWeb-RegularItalic` | `8584ff4c9d641f17da4c.woff2` | same |
| `LyonText-Bold.ttf` | `LyonTextWeb-Bold` | `f421f34186ea2bfdda13.woff2` | same |
| `LyonText-BoldItalic.ttf` | `LyonTextWeb-BoldItalic` | `e0c0e3d4fee50bdea3f9.woff2` | same |

The asset-to-name mapping comes from the `"./public/fonts/<Name>.woff2": e.exports=n.p+"<hash>.woff2"` modules in [M] and [S].

## 2. Type scale

This is the `Typography.constants.ts` `lC` table ([M]@40061). Every `<Text size=…>` in the app goes through it, and line height is always fixed in px.

| token | size / line-height (px) |
|---|---|
| `TITLE_LARGE` | 26 / 32 |
| `TITLE` | 22 / 26 |
| `TITLE_MEDIUM` | 20 / 25 |
| `HEADING` | 17 / 22 |
| `REGULAR` | 14 / 20 |
| `MEDIUM` | 13 / 16 |
| `SMALL` | 12 / 16 |
| `MINI` | 10 / 13 |

The default Text color is `textPrimary` and the default weight is `regular`. Unless `wrap` is set, text is a single line with an ellipsis (`white-space:nowrap; overflow:hidden; text-overflow:ellipsis`). Source: [M] `notion-ui/components/Typography/Typography.tsx`.

### UI roles

| role | size | weight | color | source |
|---|---|---|---|---|
| Sidebar item label | REGULAR 14/20 | medium | `textSecondary`; `textPrimary` when active; `textTertiary` for tertiary items such as "Add view" and "More" | `SidebarItem` `nne` [M]@6524474 |
| Sidebar item unread count | SMALL 12/16 | medium | `textSecondary`, hidden while the row is hovered | same |
| Sidebar section header ("Views", "Mail", "Labels") | SMALL 12/16 | **semibold** | `textTertiary`, with a 12px chevron in `textTertiary` shown on hover | `Bue`/`Uue` [M]@6671205 |
| List sender (From) | REGULAR 14/20 | unread `semibold`, read `regular` (`medium` in the bold-read variant) | `textPrimary`; read rows use **opacity 0.85** | `NWe`/`IWe`/`MWe` [M]@7459031–7460025 (`MailboxContactCell`) |
| List subject | REGULAR 14/20 | unread `semibold`, read `regular` | `textPrimary`; read rows use opacity 0.85 | `bqe` `MailboxTextCell` [M]@7471801 |
| List snippet (inline after the subject) | REGULAR 14/20 | regular | `textTertiary`, opacity 0.9, `padding-left: 2px` | `pqe` [M]@7471602 |
| List timestamp | REGULAR 14/20 | regular | `textTertiary`; `textOrangeSecondary` for snoozed, reminder and scheduled rows; `font-feature-settings: 'tnum','lnum'` | `iJe` [M]@7510729 |
| List thread count (e.g. "3") | REGULAR 14/20 | regular | `textTertiary` | `sJe` [M]@7516531 |
| List "Draft" marker | REGULAR 14/20 | regular | `textUIRedPrimary` | same |
| Date group header ("Yesterday", "Last 7 days", "August") | REGULAR 14/20 | medium | `textPrimary` | `tJe`/`nJe`/`oJe` [M]@7508864 |
| Thread subject (reader) | TITLE 22/26 | semibold | `textPrimary`; min-height 37.2, padding 3px 2px 3px 0 | `Pot` [M]@8383191 |
| Message header sender name | REGULAR 14/20 | medium | `textPrimary`; the inline address is `textTertiary` regular | `het` [M]@8323629, `vet` @8323703 |
| Message header date | REGULAR 14/20 | regular | `textTertiary` | `s9e` [M] |
| "Show N more messages" expander | SMALL 12/16 | medium | `textSecondary` | `Uot` "Expander" [M]@8385711 |
| Email body (iframe) | 14px, **line-height 1.71** | 400 | `textPrimary`, sans stack | `XE` `<body style=…>` [M]@5913956 |
| Button label | REGULAR 14/20; the SMALL and MINI sizes use SMALL 12/16 | primary variant `semibold`, all other variants `medium`, deemphasized `regular` | depends on the variant (§6) | notion-ui button `Ge` [M]@68544 |
| Tooltip | SMALL 12/16 | medium | title `textContrast`; subtitle and shortcut `textContrastSecondary` at opacity 0.6 | `src/components/Shared/TooltipLabel/TooltipLabel.tsx` |
| Cmd-K / search input | **18px** | regular | placeholder at opacity 0.6 | `Zke` [M]@6895971 |
| Palette row label | REGULAR 14/20 | medium | `textPrimary` | `GlobalActionRow` `_Ae` [M]@6859537 |
| Palette row shortcut hint | SMALL 12/16 | regular | `textTertiary` | same |
| Palette section header ("Threads", "Contacts", "Labels") | SMALL 12/16 | semibold in actions, medium in search | `textSecondary`, padding 0 8px | `QAe`, `zte` [M] |
| Search-result row | subject REGULAR medium; from + snippet REGULAR regular `textTertiary`; date SMALL medium `textSecondary` | | | `SearchItem` `Tke` [M]@6890241 |
| Empty-state title "No mail here!" | HEADING 17/22 | medium | `textPrimary`, centered | `vJe` [M]@7526364 |
| Empty-state body "Rest easy, no mail carriers in sight." | REGULAR 14/20 | regular | `textSecondary`, centered | same |
| Settings section title | HEADING 17/22 | semibold | `textPrimary` | e.g. `signatureSettings.signature` [M]@6665377 |
| Label chip text | REGULAR 14/20 at default size, SMALL at compact size | medium | per color (§4) | notion-ui tag `te`/`$` [M]@51626 |

## 3. Colors

The palettes are `notion-ui/colors/notion-colors.ts`: `$t`, light and `Qt`, dark in [S]; `a.XA.light` / `a.XA.dark` in [M]. The semantic map is `ia` in [S] (@110709) and `w4V` in [M]. The theme picked at runtime is `f(mode)`, which is `{mode, ...semantic[mode], ...shadows[mode], ...glass[mode]}` (`src/components/AppThemeProvider/AppThemeProvider.tsx`). `body { background: surfacePage }`.

Notation: `#RRGGBB @ a` means that color at alpha `a`. The accent is **Notion blue `#2383E2`** (`uiBlue[600]`). The text selection color is `rgba(35,131,226,0.28)` ([CSS] `*::selection`).

### Where each surface goes

| UI element | token | light | dark | source |
|---|---|---|---|---|
| Main content background (list and reader) | `surfacePage` | `#FFFFFF` | `#191919` | `AppThemeProvider` body |
| **Sidebar background** | `surfaceWash` | `#F7F7F5` | `#202020` | sidebar `Nge` [M]@6707365 |
| Sidebar right edge | inset box-shadow `-1px 0 0 0 borderDeemphasized`, or `-2px … borderRegular` while the resize handle is hovered | | | same |
| Popover, menu, modal and compose background | `surfaceElevated` | `#FFFFFF` | `#252525` | menu `Nn` [M]@153827, dialog `he` |
| Row hover | `tintPrimary` | `#000 @ 0.05` | `#FFF @ 0.055` | row `Y_e` [M]@7504901 |
| Row **selected** (multi-select) | `tintUIBlueHover` | `#2383E2 @ 0.14` | same | same |
| Row selected + hover | `tintUIBluePressed` | `#2383E2 @ 0.21` | same | same |
| Sidebar item hover / pressed | `tintHover` / `tintPress` | `#000 @ .04` / `@ .08` | `#FFF @ .055` / `@ .13` | `_te` [M]@6522101 |
| Sidebar item **active** | `tintPrimary` | `#000 @ 0.05` | `#FFF @ 0.055` | same |
| **Unread dot** | `fillUIBlue` | `#2383E2` | `#2383E2` | `rJe` [M]@7511075 |
| Selected-message bar in reader (4px, left) | `fillUIBlue` | | | `vtt` [M] |
| Dividers and hairlines | `borderDeemphasized` | `#E3E2E0 @ 0.5` | `#FFF @ 0.055` | date header, reader `zot`, search `Yke` |
| Control borders (inputs, outline buttons, menus) | `borderRegular` | `#E3E2E0` | `#FFF @ 0.13` | |
| Focus ring | `shadowFocusPrimary` | `inset 0 0 0 1px #2383E2, 0 0 0 2px rgba(35,131,226,.35)` | same | shadows `Ho` |
| Search highlight `<mark>` | background `tintBlue`, text `textUIBluePrimary`, weight 600, radius 2 | `#E7F3F8` / `#2383E2` | `#1B1F22` / `#2383E2` | `Y_e`, `qke` |
| Modal scrim | `scrim` | `#000 @ 0.56` | same | notion-ui `fe` |
| Tooltip background | **(unverified)**: it uses contrast text, so it is a dark chip in both modes; `surfaceDark` `#1D1B16` light / `#252525` dark is the only dark surface token | | | |


## 4. Full semantic color table

This is resolved from the palettes by evaluating the bundle's own `$t`/`Qt`/`ia` objects with Node. It is identical in [M] and [S].

### Text

| token | light | dark |
|---|---|---|
| `textPrimary` | `#1D1B16` | `#D3D3D3` |
| `textSecondary` | `#5F5E5B` | `#9B9B9B` |
| `textTertiary` | `#91918E` | `#7F7F7F` |
| `textQuaternary` | `#ACABA9` | `#FFFFFF @ 0.13` |
| `textContrast` | `#FFFFFF` | `#FFFFFF` |
| `textContrastSecondary` | `#D3D3D3` | `#D3D3D3` |
| `textContrastTertiary` | `#5F5E5B` | `#7F7F7F` |
| `textUIBluePrimary` | `#2383E2` | `#2383E2` |
| `textUIBlueSecondary` | `#2383E2 @ 0.57` | `#2383E2 @ 0.57` |
| `textUIBlueTertiary` | `#2383E2 @ 0.35` | `#2383E2 @ 0.35` |
| `textUIRedPrimary` | `#D44C47` | `#DE5550` |
| `textUIRedSecondary` | `#E3988E` | `#B4413C` |
| `textUIRedTertiary` | `#EFBAB3` | `#8F3A35` |
| `textUIYellowPrimary` | `#CB912F` | `#CA9849` |
| `textRed` | `#5D1715` | `#FFFFFF @ 0.87` |
| `textRedSecondary` | `#D44C47` | `#DF5452` |
| `textRedTertiary` | `#E16F64` | `#8F3A35` |
| `textBrown` | `#442A1E` | `#FFFFFF @ 0.87` |
| `textBrownSecondary` | `#9F6B53` | `#BA856F` |
| `textBrownTertiary` | `#BB846C` | `#845641` |
| `textOrange` | `#49290E` | `#FFFFFF @ 0.87` |
| `textOrangeSecondary` | `#D9730D` | `#C77D48` |
| `textOrangeTertiary` | `#D7813A` | `#A75B1A` |
| `textYellow` | `#402C1B` | `#FFFFFF @ 0.87` |
| `textYellowSecondary` | `#CB912F` | `#CA9849` |
| `textYellowTertiary` | `#CB9433` | `#9B6E23` |
| `textGreen` | `#1C3829` | `#FFFFFF @ 0.87` |
| `textGreenSecondary` | `#448361` | `#529E72` |
| `textGreenTertiary` | `#6C9B7D` | `#2D7650` |
| `textBlue` | `#183347` | `#FFFFFF @ 0.87` |
| `textBlueSecondary` | `#337EA9` | `#5E87C9` |
| `textBlueTertiary` | `#5B97BD` | `#295A95` |
| `textPurple` | `#412454` | `#FFFFFF @ 0.87` |
| `textPurpleSecondary` | `#9065B0` | `#9D68D3` |
| `textPurpleTertiary` | `#A782C3` | `#704A96` |
| `textPink` | `#4C2337` | `#FFFFFF @ 0.87` |
| `textPinkSecondary` | `#C14C8A` | `#D15796` |
| `textPinkTertiary` | `#CD749F` | `#903A65` |

### Icon

| token | light | dark |
|---|---|---|
| `iconPrimary` | `#32302C` | `#FFFFFF @ 0.81` |
| `iconSecondary` | `#91918E` | `#FFFFFF @ 0.445` |
| `iconTertiary` | `#C7C6C4` | `#FFFFFF @ 0.283` |
| `iconQuaternary` | `#E3E2E0` | `#FFFFFF @ 0.13` |
| `iconContrast` | `#FFFFFF` | `#F6F6F6` |
| `iconUIBluePrimary` | `#2383E2` | `#2383E2` |
| `iconUIBlueSecondary` | `#2383E2 @ 0.57` | `#2383E2 @ 0.57` |
| `iconUIBlueTertiary` | `#2383E2 @ 0.35` | `#2383E2 @ 0.35` |
| `iconUIRedPrimary` | `#D44C47` | `#DE5550` |
| `iconUIRedSecondary` | `#E3988E` | `#B4413C` |
| `iconUIRedTertiary` | `#EFBAB3` | `#8F3A35` |
| `iconRed` | `#E16F64` | `#DE5550` |
| `iconBrown` | `#BB846C` | `#B27E67` |
| `iconOrange` | `#D7813A` | `#E48538` |
| `iconYellow` | `#CB9433` | `#D99E35` |
| `iconGreen` | `#6C9B7D` | `#3C9D6A` |
| `iconBlue` | `#5B97BD` | `#4694F2` |
| `iconPurple` | `#A782C3` | `#9D67D2` |
| `iconPink` | `#CD749F` | `#C94B8C` |

### Surface

| token | light | dark |
|---|---|---|
| `surfacePage` | `#FFFFFF` | `#191919` |
| `surfaceWash` | `#F7F7F5` | `#202020` |
| `surfaceElevated` | `#FFFFFF` | `#252525` |
| `surfaceDark` | `#1D1B16` | `#252525` |
| `surfaceGlass` | `#FFFFFF @ 0.8` | `#191919 @ 0.8` |

### Fill (solid)

| token | light | dark |
|---|---|---|
| `fillUIBlue` | `#2383E2` | `#2383E2` |
| `fillUIBlueHover` | `#2076CB` | `#2076CB` |
| `fillUIBluePressed` | `#1C69B5` | `#1C69B5` |
| `fillUIRed` | `#D44C47` | `#CD4945` |
| `fillUIRedHover` | `#BF4440` | `#B8423E` |
| `fillUIRedPressed` | `#AA3D39` | `#A43A37` |
| `fillLightGray` | `#F1F1EF` | `#373737` |
| `fillGray` | `#E3E2E0` | `#5A5A5A` |
| `fillRed` | `#FFE2DD` | `#522E2A` |
| `fillBrown` | `#EEE0DA` | `#4A3228` |
| `fillOrange` | `#FADEC9` | `#5C3B23` |
| `fillYellow` | `#FDECC8` | `#564328` |
| `fillGreen` | `#DBEDDB` | `#243D30` |
| `fillBlue` | `#D3E5EF` | `#143A4E` |
| `fillPurple` | `#E8DEEE` | `#3C2D49` |
| `fillPink` | `#F5E0E9` | `#4E2C3C` |
| `fillBlack` | `#000000` | `#000000` |
| `fillBlackHover` | `#0E0E0E` | `#0E0E0E` |
| `fillBlackPressed` | `#212121` | `#212121` |

### Tint (translucent / pale)

| token | light | dark |
|---|---|---|
| `tintUIBlue` | `#2383E2 @ 0.07` | `#2383E2 @ 0.07` |
| `tintUIBlueHover` | `#2383E2 @ 0.14` | `#2383E2 @ 0.14` |
| `tintUIBluePressed` | `#2383E2 @ 0.21` | `#2383E2 @ 0.21` |
| `tintUIBlueDisabled` | `#2383E2 @ 0.35` | `#2383E2 @ 0.35` |
| `tintUIRed` | `#FDEBEC` | `#362422` |
| `tintUIRedHover` | `#FFE2DD` | `#3E2825` |
| `tintUIRedPressed` | `#FFE2DD` | `#3E2825` |
| `tintUIRedDisabled` | `#FDF5F3 @ 0.7` | `#FDDADA` |
| `tintLightGray` | `#F1F1EF` | `#373737` |
| `tintGray` | `#E3E2E0 @ 0.5` | `#2F2F2F` |
| `tintRed` | `#FDF5F3 @ 0.7` | `#241E1D` |
| `tintOrange` | `#FBECDD` | `#251F1B` |
| `tintYellow` | `#FBF3DB` | `#231F1A` |
| `tintGreen` | `#EDF3EC` | `#1D2220` |
| `tintBlue` | `#E7F3F8` | `#1B1F22` |
| `tintPink` | `#F9EEF3 @ 0.8` | `#231C1F` |
| `tintPurple` | `#F4F0F7 @ 0.8` | `#1F1D21` |
| `tintBrown` | `#F4EEEE` | `#231E1C` |
| `tintPrimary` | `#000000 @ 0.05` | `#FFFFFF @ 0.055` |
| `tintHover` | `#000000 @ 0.04` | `#FFFFFF @ 0.055` |
| `tintPress` | `#000000 @ 0.08` | `#FFFFFF @ 0.13` |

### Border

| token | light | dark |
|---|---|---|
| `borderRegular` | `#E3E2E0` | `#FFFFFF @ 0.13` |
| `borderDeemphasized` | `#E3E2E0 @ 0.5` | `#FFFFFF @ 0.055` |
| `borderContrast` | `#FFFFFF` | `#FFFFFF` |
| `borderContrastDeemphasized` | `#FFFFFF @ 0.13` | `#FFFFFF @ 0.13` |
| `borderUIBlue` | `#2383E2` | `#2383E2` |
| `borderUIBlueDeemphasized` | `#2383E2 @ 0.35` | `#2383E2 @ 0.35` |
| `borderUIRed` | `#D44C47` | `#DE5550` |
| `borderUIRedDeemphasized` | `#E3988E` | `#522E2A` |

### Other

| token | light | dark |
|---|---|---|
| `popoverWaxPaperBackground` | `#FFFFFF @ 0.9` | `#202020 @ 0.9` |
| `scrim` | `#000000 @ 0.56` | `#000000 @ 0.56` |
| `scrollbarTrack` | `#EDECE9` | `#CACCCE @ 0.04` |
| `scrollbarThumb` | `#D3D1CB` | `#474C50` |
| `scrollbarThumbHover` | `#AEACA6` | `#CACCCE @ 0.3` |
| `badgeBackgroundRed` | `#EB5757` | `#B4413C` |

### Tag/select-option colors (`<color>Primary` = dot/icon, `<color>Secondary` = chip fill)

| token | light | dark |
|---|---|---|
| `bluePrimary` | `#5B97BD` | `#2E7CD1` |
| `blueSecondary` | `#D3E5EF` | `#1B2D38` |
| `brownPrimary` | `#BB846C` | `#AA755F` |
| `brownSecondary` | `#EEE0DA` | `#362822` |
| `grayPrimary` | `#91918E` | `#FFFFFF @ 0.445` |
| `graySecondary` | `#E3E2E0` | `#FFFFFF @ 0.095` |
| `greenPrimary` | `#6C9B7D` | `#2D9964` |
| `greenSecondary` | `#DBEDDB` | `#23312A` |
| `lightGrayPrimary` | `#91918E` | `#FFFFFF @ 0.445` |
| `lightGraySecondary` | `#E3E2E0 @ 0.5` | `#FFFFFF @ 0.055` |
| `orangePrimary` | `#D7813A` | `#D87620` |
| `orangeSecondary` | `#FADEC9` | `#422F22` |
| `pinkPrimary` | `#CD749F` | `#C44387` |
| `pinkSecondary` | `#F5E0E9` | `#3B2730` |
| `purplePrimary` | `#A782C3` | `#8D5BC1` |
| `purpleSecondary` | `#E8DEEE` | `#302739` |
| `redPrimary` | `#E16F64` | `#CD4945` |
| `redSecondary` | `#FFE2DD` | `#3E2825` |
| `yellowPrimary` | `#CB9433` | `#CA8E1B` |
| `yellowSecondary` | `#FDECC8` | `#403324` |

## 5. Layout metrics

### App shell ([M] `src/constants/sidebar.constants.ts`, `mailbox.constants.ts`, `thread.constants.ts`)

| value | px | constant |
|---|---|---|
| Sidebar default width | **240** | `sidebar.constants` `_d` |
| Sidebar min / max width (resizable) | 220 / 480 | `xt` / `jH` |
| Sidebar resize handle | 12 wide, `cursor: col-resize` | `Hge` @6709577 |
| Collapsed-rail width | 66 | `Gc` |
| Floating (collapsed-hover) sidebar | 220 wide, radius `0 8 8 0`, `shadowL4`, `surfaceElevated`, slide 270ms ease | `Bge` @6707906 |
| Desktop title-bar strip (traffic lights) | 40 tall, `surfaceWash` | `Lge` @6706953 |
| Sidebar scroll area | padding-top 6 | `Vge` @6708709 |
| Thread row height | **40** | `mailbox.constants` `Hd` |
| Date-group header row height | **80**; **48** when it is the first row; 64 in high-contrast mode | `G2` / `XE` |
| Other list constants | 32 (`Bq`), 36 (`M`), 37 (`Dn`), 800 (`o2`) | |
| Reader content max width | **800** (`thread.constants` `Hb`) | `pb = fg.Hb` |
| Reader horizontal padding | 42 each side, so the column is 884 max | `jot` @8383739 (`padding 0 42px; max-width: pb+84`) |
| Reader subject block padding | `12px 42px 16px 42px` | `Hot` @8385545 |
| Reader header stack gap | 8 | `Got` @8385259 |
| Compose window (floating) | width **600**, minimized 300×48, bottom-right inset 16, radius **12**, shadow `largeLightBoxShadow` | `hBe` @7232754 |
| Cmd-K / search modal | width **720**, aspect ratio 1.3846 (≈720×520), radius **12**, `surfaceElevated` | `$ke` @6896425, `y.lGe({size:720,…})` @6908381 |
| Motion | `ease: [0.16, 1, 0.3, 1]`, `duration: 0.2s`; hover transitions `background 100ms ease-out`; 20ms ease-in on small icon buttons | `constants/index.ts` `c`, `_te`, `que` |

### Sidebar item (`SidebarItem`, `_te` @6522101)

- **Height 30**, **radius 6**, horizontal margin 8 each side (`width: calc(100% - 16px)`), vertical margin 1.
- Padding: `4px 9px 4px (8 + 8×depth)px`. Gap between icon and label: **8**.
- The icon slot is **20×20** (`ene`) with an inner 20×20 radius-4 hit area (`Jte`). The icon glyph is size MEDIUM (20) in `iconSecondary` by default.
- Label: REGULAR medium. The count is right-aligned (`Xte`: `margin-left:auto; padding: 0 3px; radius 3`).
- Section header (`Bue` @6671205): height 30, radius 6, margin `0 8px`, padding `0 6px 0 8px`, hover `tintPrimary`. The section wrapper adds `padding-bottom: 12px` when expanded.
- The compose icon-button in the sidebar header (`que` @6675391) is 28×28, radius 4, hover `tintHover`, active `tintPress`.

### Thread-list row (`Y_e` @7504902, `sJe` @7511531)

- Height 40 (from the virtual list `itemSize`). Row box: `margin-left: 14px; width: calc(100% - 28px)`, `padding: 0 40px 0 7px`, `gap: 6px` (4px when the first column is an icon).
- **Radius 8**, but corners touching a hovered or selected neighbour go to 0, so contiguous rows merge into one pill:
  - `border-radius: ${prevActive?0:8} ${prevActive?0:8} ${nextActive?0:8} ${nextActive?0:8}`
- `border-bottom: 1px solid transparent`. High-contrast mode uses `borderDeemphasized` and square corners.
- Background states:
  - hover: `tintPrimary`
  - selected: `tintUIBlueHover`
  - selected + hover: `tintUIBluePressed`
  - otherwise transparent
- Column order: [hover checkbox] → unread dot → sender column → subject+snippet → labels → right-aligned date.
- Unread dot (`rJe`): **6×6** circle, `fillUIBlue`, margin `0 4px 0 2px` (right margin 1px next to a status icon). It **stays in layout on read rows with opacity 0**, so nothing jumps.
- Sender column (`Z_e`): width = min-width = **16vw** for From/To. `padding-right: 8`, gap 4.
- Subject/snippet group (`X_e`): flex 1, gap 4. When the date column is last, `max-width: calc(100% - 120px)`.
- Subject gets 3 parts of the flex space and snippet gets 1 (`uqe`/`dqe`). Snippet has `padding-left: 2px`.
- Date cell (`iJe`):
  - `padding-left: 36px`, flex-shrink 0, right-aligned, tabular numbers.
  - `min-width = 21.5 × max(3, hoverActionCount) + 4 − 30` px, which is 38.5 for 3 actions. This reserves room for the hover actions that replace it.
- Date format (`cke` @6876679):
  - today: `h:mm AM/PM` (`hour:"numeric", minute:"2-digit", hour12`)
  - this year: `MMM d` (for example "Sep 22")
  - older: `MMM d, yyyy`
- Label chips in the row (`mke`/`bke` @6883864): max-width 122, min-height 20, radius 4.
- Draft marker group (`$_e`): gap 2, min-width 32.

### Date-group header (`tJe` @7508865)

- Labels (`[M]` grouping fn): no header for today; "Yesterday" with sublabel `Tue, Sep 22`; "Last 7 days"; "Last 30 days", or the month name when that falls in a previous month; month name; month name plus year for earlier years.
- Aligned to the bottom: `padding-bottom: 8px; padding-left: 6px`, `margin: 0 52px`.
- The bottom hairline is drawn as `box-shadow: inset 0 -7px 0 surfacePage, inset 0 -8px 0 borderDeemphasized`, a 1px line 7px above the bottom.
- Inner row: gap 6, padding-bottom 10.

### Reader: message blocks (`htt` @8343805, `ftt`, `ytt`, `wtt`, `xtt`)

- Each message block: `padding: 8px 42px` (14px next to collapsed neighbours), gap 16, `border-bottom: 1px solid borderDeemphasized`. The first expanded message also gets a top border.
- A collapsed message is 30 tall (`xtt`) and shows `tintHover` on hover. An expanded message is transparent.
- The body wrapper is `padding: 24px 4px` (`wtt`). The header row gap is 8 (`ktt`). The expanded header stacks with `padding-top: 5px`.
- The selected message gets a 4px-wide `fillUIBlue` bar at the left edge (`vtt`).
- Hidden-messages expander (`Lot`/`Bot`):
  - Centered pill "Show N more messages", `padding 12px 42px`.
  - Drawn over a 1px `borderDeemphasized` line.
  - Pill background `surfaceElevated`, `padding: 0 12px`.
- Schedule-send banner: 44 tall, `tintUIBlue`, gap 24. Truncation banner: `tintOrange`.

### Command palette / search modal (`qke`, `Kke`, `Zke` @6894696–6896000)

- Input bar: **48 tall**, `padding: 0 12px`, 18px text, `surfaceElevated`, `border-bottom: 1px solid borderDeemphasized`, radius 0.
- Results container: `padding: 4px 8px`.
- Action row (`WAe` @6858157):
  - **36 tall**, padding 8, gap 6, **radius 4**.
  - Hover `tintHover`, active `tintHover`.
  - The shortcut column is right-aligned with min-width 78.
- Search-result thread row (`wke` @6887935): 64 tall (48 contact, 32 header), padding 8, gap 8, **radius 12**, 24px avatar.
- Sections are 16px apart. The footer hint row (`_ke`) is 28 tall, `padding 8px 12px`, gap 16.
- `<mark>` highlight: `tintBlue` background, `textUIBluePrimary` text, weight 600, radius 2.

### Menus and popovers (notion-ui)

- Menu container (`Nn` @153827): `padding: 6px 0`, **radius 6**, width 240, `shadowL3`, `1px solid borderRegular`, `surfaceElevated`.
- Menu item (notion-ui, @152422): **28 tall**, radius 4, `margin: 0 4px`, `padding: 0 4px 0 8px`, gap 8. Focus/active background `tintHover`. Disabled items use opacity 0.5.
- Dialog (`he` @56296): radius 6 by default (12 for search and compose), `surfaceElevated`, horizontal margin 150. The scrim uses `scrim`.

## 6. Components (notion-ui)

### Buttons (`Ge` @68544, style `Fe`, size maps `Ee`/`Ne`/`Be`/`Ve`/`Re`)

| size | height | h-padding | gap | radius | icon | label |
|---|---|---|---|---|---|---|
| MINI | 16 | 4 | 2 | 4 | 14 | SMALL |
| SMALL | 28 | 8 | 4 | 6 | 16 | REGULAR (outline: SMALL) |
| MEDIUM (default) | 32 | 12 | 4 | 6 | 20 | REGULAR |
| LARGE | 36 | 12 | 4 | 8 | 20 | REGULAR |

- The **text** variant (`Re`) is SMALL 24/8/r6, MEDIUM 32/12/r6 (icon 16) and LARGE 32.
- The **pill** variant (`Be`) uses radii 18/30/34/38.
- Every button has `border: 1px solid transparent`, even when it has no border. The focus-visible state adds `shadowFocusPrimary`.

Variant colors (`Pe` primary, `Te` outline, `je` tint, `Le` text):

| variant/color | resting | hover | pressed | text / icon |
|---|---|---|---|---|
| primary blue | `fillUIBlue` | `fillUIBlueHover` | `fillUIBluePressed` | `textContrast` / `iconContrast`, **semibold** |
| primary red | `fillUIRed` | `fillUIRedHover` | `fillUIRedPressed` | `textContrast` |
| primary black | `fillBlack` | `fillBlackHover` | `fillBlackPressed` | `textContrast` |
| outline black | border `borderRegular`, no fill | `tintHover` | `tintPress` | `textPrimary` / `iconPrimary`; focused: border `borderUIBlue`, fill `surfaceElevated` |
| outline gray | border `borderRegular` | `tintHover` | `tintPress` | `textSecondary` / `iconSecondary` |
| tint blue | `tintUIBlue` | `tintUIBlueHover` | `tintUIBluePressed` | `textUIBluePrimary` |
| tint black | `tintHover` | `tintHover` | `tintHover` | `textPrimary` |
| text black | none | `tintHover` | `tintPress` | `textPrimary` / `iconPrimary` |
| text gray | none | `tintHover` | `tintPress` | `textSecondary` / `iconSecondary` |
| text blue | none | `tintUIBlue` | `tintUIBluePressed` | `textUIBluePrimary` |
| disabled (outline/text) | | | | `textQuaternary` or `textTertiary` / `iconTertiary` |

### Icons (`notion-ui/components/IconUtils/Icons.utils.tsx`, sizes from `notion-ui/types.ts`)

- Sizes: MINI **14**, SMALL **16**, MEDIUM **20** (default), LARGE **24**.
- `viewBox="0 0 20 20"`, filled paths, default color `iconSecondary`.
- In practice: sidebar icons 20; row hover actions MEDIUM 20; chevrons 12–14; palette row icons 20; the unread-thread search dot is 8.

### Avatar (notion-ui `y`/`b` @48725)

- A circle; `square` gives radius 4. Background `surfaceElevated`. There is a `1px` outline in `borderDeemphasized` with `outline-offset: -1px`.
- Initial: one uppercase letter in SF Rounded, semibold, color `iconSecondary` (`iconTertiary` when inactive).
- Initial size by avatar size: 16→MINI 10, 20→SMALL 12, 24→REGULAR 14, 32→16px, otherwise 0.6×size.
- Used at: list/search 24, message header 32, contact pickers 20.

### Tag / label chip (`te`, style `$` @51626; colors from `notion-ui/constants.ts` `Wc`)

- Height: 20 default, 18 compact, 30 large. Padding `0 6px`, gap 4, **radius 3** (6 when large).
- Text: medium weight, REGULAR size (SMALL compact, TITLE large).
- Color names (`ES`): `light-gray, gray, brown, orange, yellow, green, blue, purple, pink, red`.
- Solid chip = `fill<Color>` background + `text<Color>` text + `icon<Color>` icon.
- Tint chip (`isTint`) = `tint<Color>` background + `text<Color>Secondary` text.
- `light-gray`: `fillLightGray` + `textPrimary`, or tint `tintLightGray` + `textSecondary`.
- When hoverable, a chip uses the tint colors as its hover background and text.

### Tooltip

- Content: title SMALL medium `textContrast`; subtitle and keyboard hint SMALL medium `textContrastSecondary` at opacity 0.6.
- Title and inline shortcut sit in one row, gap 8. Default open delay: 2000ms on sidebar items.
- The tooltip container background is **(unverified)**; see §3.

### Scrollbars (notion-ui `zo` @170109, `Go` @170583)

- 10px (11 in overlay variant).
- Track `scrollbarTrack`, thumb `scrollbarThumb`, hover `scrollbarThumbHover`.
- The overlay variant has a radius 10 thumb with a 2px `surfaceWash` border. Its thumb is `#7F7F7F` in light and `#919191` in dark.

## 7. Shadows (`notion-ui` `Ho` @171122)

| token | light | dark |
|---|---|---|
| `shadowL1` | `0 0 0 1px rgba(227,226,224,.5), 0 2px 4px 0 rgba(0,0,0,.04)` | `0 0 0 1px #313131, 0 2px 4px 0 rgba(0,0,0,.08)` |
| `shadowL2` | `0 0 0 1px rgba(227,226,224,.5), 0 4px 12px -2px rgba(0,0,0,.08)` | `0 0 0 1px #313131, 0 4px 12px -2px rgba(0,0,0,.16)` |
| `shadowL3` (menus) | `0 0 0 1px rgba(227,226,224,.5), 0 2px 4px -1px rgba(0,0,0,.06), 0 12px 32px -6px rgba(0,0,0,.12)` | `0 0 0 1px #313131, 0 12px 36px -6px rgba(0,0,0,.40)` |
| `shadowL4` (floating sidebar, modals) | `0 0 0 1px rgba(227,226,224,.5), 0 4px 12px -1px rgba(0,0,0,.14), 0 32px 48px -8px rgba(0,0,0,.28)` | `0 0 0 1px #313131, 0 20px 48px -8px rgba(0,0,0,.56)` |
| `shadowFocusPrimary` | `inset 0 0 0 1px #2383E2, 0 0 0 2px rgba(35,131,226,.35)` | same |
| `shadowFocusError` | `inset 0 0 0 1px #D44C47, 0 0 0 2px rgba(225,111,100,.35)` | same |
| `largeLightBoxShadow` (compose) | `rgba(15,15,15,.04) 0 0 0 1px, rgba(15,15,15,.03) 0 3px 6px, rgba(15,15,15,.06) 0 9px 24px` | `rgba(15,15,15,.05) 0 0 0 1px, rgba(15,15,15,.1) 0 3px 6px, rgba(15,15,15,.2) 0 9px 24px` |
| glass blur | `glassThick: blur(32px)`, `glassThin: blur(16px)` | same |

**SwiftUI note:** each shadow starts with a `0 0 0 1px` spread ring. That ring is really a 1pt stroke overlay:
- light: `#E3E2E0 @ 0.5`
- dark: `#313131`

Draw it as `.overlay(RoundedRectangle(...).strokeBorder(...))` and add the blur layers as `.shadow(color:radius:y:)`. A CSS blur of N px is about SwiftUI radius N/2.

## 8. Email body rendering (`XE` @5909393, `hE`, `Qg`)

- The HTML goes into a sandboxed iframe without `allow-scripts`, except on native mobile. Sanitized with DOMPurify.
- Body style: `line-height: 1.71; font-weight: 400; font-size: 14px; color: textPrimary; font-family: <sans stack>`. The iframe background is `surfaceElevated`.
- Base stylesheet (`rt`, exported as `fiP`, `<style>` at @8662887):
  - `p { margin: 0 }`
  - Lists: `padding-inline-start: 24px`
  - `blockquote`: `border-left: 3px solid` (light `rgba(55,53,47,.16)`, dark `rgba(255,255,255,.13)`), `padding: 3px 2px 3px 14px`, margin-top 4
  - Code uses `githubMono`
  - `a { color: rgba(120,119,116,1); text-decoration-thickness: .05em; text-underline-offset: 3px }`
- Quoted-reply blockquote uses `border-left: 3px solid borderRegular`.
- CSP, verbatim from [M]:
  ```
  default-src 'none'; img-src blob: data: <notion image proxy>; style-src 'unsafe-inline'; script-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'; frame-ancestors '<origin>'
  ```
  Remote images only loaded through Notion's proxy. For us that becomes: blocked by default, with a per-sender opt-in.
- **Dark mode** (`qE` @5904769, `QE` @5906163, `YE` @5906457) recolors emails instead of leaving them white:
  - Dark text colors are inverted with a 180° hue rotation.
  - Light backgrounds become `invert().rotate(180).lighten(.145)`.
  - Low-contrast pairs are then nudged (`QE`, which targets a contrast ratio of at least 7).

## 9. Keyboard map found in the bundle (`messageCellActions.*`, `globalActions.*`)

- `E` archive; `Shift E` unarchive
- `Delete` or `Shift 3` trash
- `H` reminder/snooze; `L` add label
- `R` reply; `A` reply all; `F` forward
- `C` compose
- `⌘K` command palette; `⌘\` toggle sidebar

These do not conflict with the Superhuman keys in the plan.

## 10. Empty and loading states (`vJe` @7526364, `uJe` @7524281, `dJe` @7524487, `gJe` @7525310, `fJe` @7525763, `mJe` @7524725)

- Empty mailbox: a column centered with `padding-top: 80px`, gap 8. The title/body block has gap 4.
  - Title "No mail here!" in HEADING medium.
  - Body "Rest easy, no mail carriers in sight." in REGULAR `textSecondary`.
  - Above them sits an illustration (`images/dog.png` and `images/mailbox.png`, both cached in SW storage).
- Loading dots (`gJe`/`fJe`):
  - Three 4×4 circles, `textQuaternary`, gap 2.
  - Each bounces 2px over 0.5s alternate, `cubic-bezier(.11,0,.5,0)`, with delays of 0.2, 0.4 and 0.6s.
- Loading text shimmer (`mJe`): a 16px gradient `textQuaternary → textSecondary → textQuaternary` sweeping over 2s.

## Not covered or unverified

- **Tooltip container background and radius.** It lives in the notion-ui tooltip, which uses a floating-ui wrapper that was not traced. Check it against a reference screenshot.
- **Hover-action strip styling.** `CUe`/`jUe` only shows the icon set: Reminder H, Add label L, Archive E, Trash, and Mark read/unread. Each action is ≈21.5px wide, as implied by the date-column math.
- **Compose field styling.** Only the window metrics were extracted. The recipient row `vWe` is `padding: 9px 1px 6px 9px`, min-height 34, `surfaceWash` background, bottom border `borderDeemphasized`.
- **Gmail label color → `ES` name mapping.** This is `C.$6o` in [M] and was not dumped. Map Gmail's `backgroundColor` to the nearest of the 10 names.
