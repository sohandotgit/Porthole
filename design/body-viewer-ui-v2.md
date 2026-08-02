# body-viewer-ui-v2.md — Body Viewer, reconciled design (v2, SOURCE OF TRUTH)

**Status:** FROZEN. Supersedes `design/body-viewer-ui.md` (v1) in full.
**Reconciles:** imported design `Body Viewer.dc.html` (claude.ai design project
`897decda-089e-43d8-987f-101d9a9fd00f`) against v1 + `BODY-VIEWER-ROADMAP.md`.
**Companions:** `design/body-viewer-tokens.md` (every color/font/metric constant),
`Tests/body-viewer.spec.md` (frozen spec), `design/body-viewer-removal-map.md` (B6 kill list).

Precedence rule used throughout: **the imported design wins**; the roadmap's settled decisions bind
where the design is silent; v1 survives only where both are silent. Every value below that the
design did **not** pin is marked **[derived]** with its rationale — B2–B6 must treat derived values
as binding too, but B7 may challenge only those.

What v1 keeps unchanged and still applies: §2 principles, §5 performance contract (as amended in
§10 here), §6 out-of-scope list, §3.6 image mode, §3.7 inline preview cards.

---

## 1. Reconciliation of the six contradictions

All six resolve on the imported design's side. Values live in `design/body-viewer-tokens.md`.

| # | Was (v1) | Now (v2, from the design) |
|---|---|---|
| 1 | hairline strips over a plain background | **inset-grouped cards.** Page fill `#F2F2F7`/`#000`; every chrome block is a card (`#fff`/`#1C1C1E`, radius **12**); the canvas is its own inset card with an internal gutter pane filled `#FBFBFD`/`#141416` and a `0.5px` trailing divider. Content column: padding `14` top / `16` horizontal, inter-card gap **14** (**12** in Hex mode, §5.3). |
| 2 | search via `.searchable` | **inline search row inside the content column.** Pill `flex:1`, height **36**, radius **10**, fill `rgba(118,118,128,.12)`/`.24`, inner padding `0 9`, gap `6`: magnifier `14×14` stroke `1.8` → **monospaced 15pt** query text → `1.6×17` accent caret. Then the `3/12` counter (monospaced 13pt medium, `min-width 38`, right-aligned) and two **30×32** chevron buttons, gap `2`. `.searchable` is **not** used on this screen. |
| 3 | gate at 512 KB | **gate at 64 KB**, from `AtlantisViewerSettings.autoRenderLimitBytes` (`@AppStorage`, internal, default `65_536`). Footnote renders the live value: `Auto-render limit: 64 KB · change in Settings`. Hex dump keeps its own independent **1 MB** cap. |
| 4 | BINARY badge orange | **BINARY badge purple** — `#D4B7FF` on `rgba(191,90,242,.22)` (dark, pinned); light **[derived]** `#7A1FA2` on `rgba(175,82,222,.12)`. |
| 5 | light `key` blue `#0B5FA4` | **the design's palette replaces v1 §4 wholesale.** Light: key `#9B2393`, string `#C41A16`, number `#1C00CF`, literal `#AA0D91`, punctuation `#6E6E73`, plain `#1C1C1E`. Dark: key `#FF7AB2`, string `#FF8170`, number `#D9C97C`, literal `#FF7AB2`, punctuation `#98989F`, plain `#F2F2F7`. |
| 6 | match `#FFE9A3` / current `#FFB340` | **other match** `rgba(255,214,10,.42)`/`rgba(255,214,10,.28)`; **current match** `#FFCC00`/`#FFD60A` **plus a 1.5pt inset ring** `#B25000`/`#FFF3B0`, **forced foreground `#1C1C1E` in both appearances**, a current-row tint `rgba(255,214,10,.14)`/`.10`, and the current line's gutter number in accent. Corner radius on match fills: **3**. Ring technique pinned in §8. |

### 1.1 Seventh contradiction — found this pass, resolved against Decision 7

Roadmap **Decision 7** and v1 §3.2 say *"BINARY → Hex only (picker hidden)"*. The imported hex mock
shows the opposite and is unambiguous: a **three-segment picker** with `Pretty` **dimmed/disabled**,
`Raw` **enabled**, `Hex` **selected**, on a `BINARY` body.

**Resolved on the design's side** (standing precedence rule): for `.binary`, the picker is
**visible** with `Pretty | Raw | Hex`; `Pretty` is disabled (there is no structure to pretty-print),
`Raw` is enabled and renders a **lossy** UTF-8 decode (`String(decoding:as: UTF8.self)`, invalid
sequences become U+FFFD), `Hex` is the default selection. Nothing is ever hidden — disabled controls
stay visible and dimmed, so there is no layout jump (v1 §3.2, kept).

> **Flag for B7:** this deviates from a settled roadmap decision. It is deliberate and traceable to
> the mock; do not file it as a defect.

---

## 2. Navigation chrome

- Title: **`Response Body`** or **`Request Body`** (the string passed by the caller; WS messages pass
  `Message`), 17pt semibold, `label`.
- Back button: chevron `12×20` stroke `2.2` + label **`Detail`**, 17pt regular, accent. This is why
  B6 changes the detail screen's `navigationTitle("Request")` → `"Detail"` (Decision 9) — it is the
  only edit B6 makes outside the body rows.
- Trailing `⋯`: `ellipsis.circle`, `24×24`, stroke `1.5`, accent. In the **empty state** it dims to
  `#C7C7CC` and its menu is disabled (nothing to copy or share).
- Nav bar fill `#F9F9F9`/`#1C1C1E` with a `0.5px` bottom hairline `#C6C6C8`/`#38383A` — i.e. the
  platform default; do not restyle, just do not force a translucent material over the page fill.

---

## 3. Meta card (present in Pretty / Raw / Text / Hex / Image / gate; **absent** in empty)

Card: fill `#fff`/`#1C1C1E`, radius `12`, padding **`12` vertical / `14` horizontal**, vertical
stack, gap **`7`**.

**Row 1** — horizontal, gap **`9`**, centered:

- **Format badge**: monospaced **11pt semibold**, tracking `+0.6`, radius `6`, padding `5` vertical /
  `8` horizontal. Text is the uppercase kind: `JSON` `XML` `HTML` `FORM` `TEXT` `IMAGE` `BINARY`.
  Per-kind tints in the tokens doc (JSON and BINARY pinned by the design; the rest **[derived]**
  from the same construction — Apple system hue, darkened for light, at `.12` light / `.22` dark
  fill alpha).
- **Content-type**: monospaced **13pt regular**, `#6C6C70`/`#98989F`, single line, truncating tail,
  selectable. Renders the raw header value verbatim
  (`application/json; charset=utf-8`); `—` when the header is absent.

**Row 2** — **stats line**, system **13pt regular**, `#8E8E93` in both appearances. Exact strings in
§4.

---

## 4. Stats line — exact strings per mode

Built by `AtlantisBodyStats.statsLine(...)` (headless, in `AtlantisBodyContent.swift`). Byte sizes
come from the existing `AtlantisFormat.bytes` (which already produces `14.2 KB` / `83.4 KB` /
`6.1 KB` exactly — verified against the mock). Counts are grouped by
`AtlantisBodyStats.grouped(_:)`: a **locale-independent** comma every three digits (never
`NumberFormatter` — tests must be stable in any locale). Separator is **` · `** (space, U+00B7,
space).

| Mode / state | Format | Example (from the mock) |
|---|---|---|
| Pretty | `<bytes> · <lines> lines · pretty-printed` | `14.2 KB · 218 lines · pretty-printed` |
| Gate (not yet rendered) | `<bytes> · <lines> lines · not yet rendered` | `83.4 KB · 4,192 lines · not yet rendered` |
| Hex | `<bytes> · <byteCount> bytes · <rows> hex rows` | `6.1 KB · 6,248 bytes · 391 hex rows` |
| Raw **[derived]** | `<bytes> · <lines> lines · raw` | `14.2 KB · 196 lines · raw` |
| Text **[derived]** | `<bytes> · <lines> lines` | `1.4 KB · 22 lines` |
| Image **[derived]**, per v1 §3.6 | `<FORMAT> · <w>×<h> · <bytes>` | `PNG · 512×720 · 14.2 KB` |
| Empty | — (no meta card at all) | — |

Semantics, pinned:

- `<lines>` in **Pretty** is the line count of the **pretty-printed** text.
- `<lines>` in **Gate** and **Raw** is the line count of the **decoded raw** text — a newline scan,
  not a projection. A minified body therefore legitimately reads `1 line` at the gate.
- Line count = number of line starts (`lineStarts.count`), so a trailing newline adds no phantom
  line and the empty string is `1 line`. Same table the gutter uses.
- `<rows>` = `ceil(min(byteCount, 1_048_576) / 16)`; `6248 → 391`.
- `<byteCount>` in Hex is the **full** byte count even when the dump is capped; the cap is disclosed
  by the footer line instead (§6.4).
- `×` is U+00D7.

---

## 5. Control strip and search row

Horizontal, gap **`10`**: segmented picker (`flex:1`) then the chip cluster (gap `4`).

### 5.1 Segmented mode picker

Track: fill `rgba(118,118,128,.12)`/`.24`, radius **`9`**, padding **`2`**. Segments split the track
evenly, padding `7` vertical.

- Selected: 13pt **semibold**; light `#000` on `#fff` with shadow `0 1px 3px rgba(0,0,0,.12)`,
  radius `7`; dark `#fff` on `#636366`, no shadow.
- Unselected: 13pt regular, `#3C3C43`/`#EBEBF5`.
- Disabled: 13pt regular, `#636366` (dark, pinned by the hex mock); light **[derived]** `#AEAEB2`.

### 5.2 Mode-option matrix (per classification)

`AtlantisBodyMode`: `.pretty` `Pretty` · `.raw` `Raw` · `.hex` `Hex` · `.text` `Text` ·
`.image` `Image`.

| Kind | Options (in order) | Default | Disabled | Picker |
|---|---|---|---|---|
| `.json` | `.pretty`, `.raw`, `.hex` | `.pretty` | — | shown |
| `.xml` | `.pretty`, `.raw`, `.hex` | `.pretty` | — | shown |
| `.html` | `.pretty`, `.raw`, `.hex` | `.pretty` | — | shown |
| `.form` | `.pretty`, `.raw`, `.hex` | `.pretty` | — | shown |
| `.text` | `.text`, `.hex` | `.text` | — | shown |
| `.image` | `.image`, `.hex` | `.image` | — | shown |
| `.binary` | `.pretty`, `.raw`, `.hex` | **`.hex`** | **`.pretty`** | shown (§1.1) |
| `.empty` | — | — | — | hidden (empty state owns the screen) |

Undecodable bytes classify as `.binary`, so they auto-select `.hex` **and** raise the UTF-8 banner
(§6.3). A body that is valid UTF-8 but has a binary content-type stays textual — today's behavior at
`AtlantisTrafficDetailView.swift:47-49` is preserved.

### 5.3 Icon chips

**34×34**, radius **`8`**, gap `4`.

- Active: fill `rgba(0,122,255,.12)`/`rgba(10,132,255,.22)`, glyph accent `#007AFF`/`#0A84FF`.
- Inactive: fill `rgba(118,118,128,.10)`/`.24`, glyph `#3C3C43`/`#EBEBF5`.

Cluster contents depend on mode:

| Mode | Chips |
|---|---|
| Pretty / Raw / Text | **wrap** (`18×18`, stroke `1.6`) · **line numbers** (monospaced 12pt semibold glyph `1` + U+200A + `2`) · **copy** (`17×17`, stroke `1.5`) |
| Hex | **ASCII pane** (monospaced 11pt semibold glyph `A` + U+200A + `S`) · **copy** |
| Image | **copy** only |

The ASCII-pane chip binds `isActive: asciiVisible` like any other toggle chip — it reads accent-filled
when the ASCII column is showing. The mock's hex frame happens to render it in the neutral/inactive
fill; that is the mock's rest-state framing, not evidence the chip shouldn't toggle (B5-16).

Copy copies the text of the **current** mode (the hex dump text in Hex mode; the raw bytes' lossy
decode in Raw on binary). Confirmation is a **1.2 s** label swap to `Copied`, not an alert.
`.help(…)` + `accessibilityLabel` on every chip; hit target padded to 44×44 without changing the
34×34 visual.

### 5.4 Search row

Geometry in §1 row 2. Behavior:

- Query debounced **150 ms** before matching. Matching is
  `AtlantisBodySearch.nsMatchRanges(in:query:)` — case-insensitive, trimmed, non-overlapping,
  ascending, `NSRange`.
- Counter: `"<current>/<total>"` with **tabular figures** (`3/12`); `current` is 1-based.
  `No matches` (13pt, secondary) when the trimmed query is non-empty and there are zero hits.
  The whole counter is **hidden** when the trimmed query is empty; the chevrons stay visible and
  dimmed (no layout jump).
- Chevrons `chevron.up` / `chevron.down`, **wrap around** at both ends, disabled at zero matches,
  `⌘G` / `⇧⌘G` on macOS.
- **The search row is not shown in Hex or Image mode** (the hex mock has none; searching a hex dump
  is a separate feature). The inter-card gap drops from `14` to `12` in Hex mode, matching the mock.

---

## 6. Canvas card and the four states

### 6.1 Canvas (Pretty / Raw / Text)

Card: `flex:1`, fill `#fff`/`#1C1C1E`, radius `12`, clipped, `min-height: 0` (it must be allowed to
shrink — this is what keeps the text view, not a parent `List`, owning the scroll).

Two panes:

- **Gutter**: fill `#FBFBFD`/`#141416`, trailing divider `0.5px` `#E5E5EA`/`#2C2C2E`, vertical
  padding **`12`** (must equal the text pane's top inset or the numbers desynchronize from their
  fragments). Numbers: monospaced **12pt** regular on a **22pt** line box, right-aligned, padding
  `12` leading / `10` trailing, width **`44`** (`digits × digitWidth + 22`, floor 44, recomputed only
  when the digit count changes). Color `#B0B0B6`/`#5A5A5F`; the **current match's line** is accent
  `#007AFF`/`#0A84FF` **semibold**. **Wrapped continuation fragments carry no number.**
- **Text**: monospaced **13pt** regular on a **22pt** line box → `lineHeightMultiple` = 22/13 =
  **1.6923**. `lineFragmentPadding = 0`. Container inset **`12` on all four sides** (design). An
  extra `contentInset.bottom = 16` provides overscroll room only — it must not enter the container
  inset, or the gutter mapping shifts.
- Base point sizes scale via `UIFontMetrics(forTextStyle: .body)` with `maximumPointSize: 22`
  (v1 §3.4, kept); the gutter uses the *same* metrics instance so both panes grow together.
- Wrap on: `.byCharWrapping` for JSON/XML/HTML/FORM/hex-ish, `.byWordWrapping` for TEXT. Wrap off:
  horizontal scrolling, container width `.greatestFiniteMagnitude`.
- Scroll-to-match lands the match **one third from the top** of the viewport, never flush
  (`scrollRangeToVisible` at `AtlantisSelectableText.swift:70` is the regression being fixed).

### 6.2 State — large-body gate

Fires when `data.count > AtlantisViewerSettings.autoRenderLimitBytes` and the user has not tapped
through. Meta card stays (with the `not yet rendered` stats line); control strip and search row are
**absent**. Content column padding becomes `14 16` (bottom padding added). Applies to `.pretty`,
`.raw`, `.text`, and `.image` — a multi-megabyte image body must not decode with no cap of any kind
(B5-12); `.hex` is exempt because it has its own independent 1 MB cap (§1 contradiction 3).

Gate card: `flex:1`, fill `#fff`/`#1C1C1E`, radius `12`, centered both axes, gap `14`, padding
`32` vertical / `28` horizontal, text centered.

1. Icon tile **56×56**, radius **16**, fill `rgba(255,149,0,.14)`; glyph
   `exclamationmark.triangle` `30×30` stroke `1.9`, `#C86000`.
2. Title **`Large body`** — 20pt semibold, line-height 1.25, `#000`/`#fff`.
3. Body — 15pt regular, line-height 1.45, `#6C6C70`/`#98989F`, `max-width 250`, balanced wrapping:
   > `<bytes> of <KIND>. Pretty-printing and highlighting this much text may take a moment and can hitch scrolling.`

   Mock instance: `83.4 KB of JSON. Pretty-printing and highlighting this much text may take a
   moment and can hitch scrolling.` `<KIND>` is the badge string (`JSON`, `XML`, …).
4. Divider `0.5px` `#E5E5EA`/`#38383A`, full width, `2` vertical margin.
5. Button stack, gap `9`, full width:
   - Primary **`Show body`** — height **48**, radius **12**, fill accent, 17pt semibold `#fff`.
   - Secondary **`Copy instead`** — height 48, radius 12, fill `rgba(0,122,255,.12)`/
     `rgba(10,132,255,.22)`, 17pt medium accent, leading `17×17` copy glyph, gap `7`.
   - Footnote, 12pt regular, line-height 1.4, `#AEAEB2`/`#8E8E93`, `2` top padding:
     > `Auto-render limit: <AtlantisFormat.bytes(autoRenderLimitBytes)> · change in Settings`

     At the default this renders exactly `Auto-render limit: 64 KB · change in Settings`. The
     phrase "change in Settings" is a **static footnote only** — no settings screen ships in this
     roadmap (Decision 4).

Dark-appearance gate colors are **[derived]** (the mock is light-only); construction is in the
tokens doc.

### 6.3 State — hex dump (+ UTF-8 failure banner)

Meta card (BINARY badge) → **banner, only when the bytes failed to decode** → control strip →
canvas. Gap `12`.

Banner: fill `rgba(255,159,10,.14)`, radius **10**, padding `10` vertical / `12` horizontal,
horizontal stack gap `9`, top-aligned. Glyph `exclamationmark.circle` `16×16` stroke `2`, `#FFB340`,
non-shrinking, `1` top margin. Text 13pt regular, line-height 1.4, `#FFD9A0` (dark, pinned);
light **[derived]** text `#8A4B00`, glyph `#C86000`, fill `rgba(255,149,0,.12)`. Copy:

> `Not valid UTF-8 — <n> undecodable byte<s> at offset 0x<OFFSET>. Showing hex dump instead.`

- `<n>` = `invalidByteCount`, grouped (§4). Singular `byte` when `n == 1`, else `bytes`.
- `<OFFSET>` = `firstInvalidOffset` as **uppercase hex, zero-padded to at least 4 digits**
  (`4 → 0004`, `65536 → 10000`). Mock instance:
  `Not valid UTF-8 — 4 undecodable bytes at offset 0x0004. Showing hex dump instead.`
- Both numbers come from `AtlantisBodyClassifier.utf8Diagnosis(_:)` →
  `(invalidByteCount: Int, firstInvalidOffset: Int)?` (`nil` when the bytes decode cleanly). The
  em dash is U+2014.

**Hex canvas** — three columns inside the card (`flex:1`, radius 12, vertical padding `12`), all on
the same **22pt** line box:

| Column | Font | Color | Geometry |
|---|---|---|---|
| offset | monospaced **11pt** | `#5A5A5F` (both) | padding `12` leading / `10` trailing |
| bytes | monospaced **11.5pt**, kern **+0.3** | `#EBEBF5` dark / `#1C1C1E` light **[derived]** | leading divider `0.5px`, `10` leading padding |
| ASCII | monospaced **11.5pt** | `#7DD3A0` dark / `#2E7D53` light **[derived]** | leading divider `0.5px`, `10` margin + `10` padding |

The three columns are **rendered from a single attributed string** in one `AtlantisCodeTextView`
(one `textStorage`, one layout) with the column tinting applied as token ranges and the dividers
drawn by the gutter/overlay layer at fixed x-offsets — not three scrolling views. Row text format is
§6.4. The ASCII pane toggle removes the ASCII column from the built string (rebuild, cached per
`(data, .hex, asciiVisible)`), it does not merely hide a view.

### 6.4 Hex row format (canonical, pinned)

Per row, exactly:

```
<OFFSET 8 uppercase hex>  <BYTES 48 chars>  <ASCII up to 16 chars>\n
```

- Offset: 8 uppercase hex digits, zero-padded (`00000000`, `000000A0`).
- Two spaces, then the byte field: 16 slots of two **uppercase** hex digits; a missing byte (short
  final row) is two spaces. Separator after each slot except the last: **one** space, except after
  slot index 7 where it is **two** spaces (the double gap). Field width is always **48**.
- Two spaces, then the ASCII pane: bytes `0x20...0x7E` verbatim (so `0x20` is a literal space),
  everything else the substitution character **`.`** (U+002E). Short rows are not padded — the row
  simply ends.
- Every row, including the last, ends with `\n`. Uppercase and the pipe-free layout are the design's
  (v1's `|AB|` delimiters and lowercase `%02x` are **dropped**).
- Cap: `AtlantisHexDump.byteLimit = 1_048_576`. Over the cap, only the first `byteLimit` bytes are
  dumped, `truncatedFrom` is the **full** byte count, and one footer line is appended after the last
  row (no extra blank line):
  > `Showing first 1 MB of <AtlantisFormat.bytes(truncatedFrom)>`

  e.g. `Showing first 1 MB of 2.5 MB`. Footer color = the offset color.

Worked example — `Data([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52])`:

```
00000000  89 50 4E 47 0D 0A 1A 0A  00 00 00 0D 49 48 44 52  .PNG........IHDR
```

### 6.5 State — empty

No meta card, no control strip, no search row, no canvas. The content area centers a stack, gap
`12`, horizontal padding `40`, text centered; the nav `⋯` is dimmed to `#C7C7CC` and disabled.

1. Glyph `doc` `52×52` stroke `1.4`, `#C7C7CC` (both appearances).
2. **`No body`** — 20pt semibold, line-height 1.25, `#3C3C43`/`#EBEBF5`.
3. **`0 bytes`** — **monospaced** 15pt regular, `#8E8E93`. Literal string, always.
4. Hint — 13pt regular, line-height 1.45, `#AEAEB2`/`#8E8E93`, `max-width 230`, balanced wrapping.
   Text depends on method + side (§6.6).

### 6.6 Empty-state hint text (per method / side)

`AtlantisBodyEmptyHint.text(method:side:statusCode:)`, headless. `method` is uppercased by the
builder; `side` is `.request` / `.response`; `statusCode` is `nil` for requests. Pinned strings:

| Side | Condition | Hint |
|---|---|---|
| request | method in `GET` `HEAD` `DELETE` `OPTIONS` `TRACE` | `<METHOD> requests usually have no body. Nothing was sent on the wire.` |
| request | any other method (incl. unknown/empty) | `The request had no body. Nothing was sent on the wire.` |
| response | `statusCode == 204` | `204 No Content responses never carry a body.` |
| response | `statusCode == 304` | `304 Not Modified responses never carry a body.` |
| response | any other / `nil` status | `The response had no body. Nothing was received on the wire.` |

The `GET` row reproduces the mock exactly: `GET requests usually have no body. Nothing was sent on
the wire.` An empty `method` string takes the "any other method" row (never renders a leading
space).

### 6.7 State — image mode (v1 §3.6, kept)

Checkerboard backdrop inside the canvas card (transparent PNGs must read correctly), `.fit`,
pinch-to-zoom 1×–6×, double-tap to reset. Stats line per §4. Chip cluster is copy-only. No search
row.

---

## 7. Inline preview cards on the detail screen (v1 §3.7, restyled)

The two `NavigationLink` rows at `AtlantisTrafficDetailView.swift:631-654` become preview cards in
the grouped-card idiom: header line `Request Body` + trailing `<bytes>` + format badge + `›`, then a
clipped canvas rendering **at most the first 14 lines / 2 KB**, highlighted, **non-scrolling,
non-selectable**, gutter on, with a bottom fade when clipped. Card radius 12, same fills, same
gutter/canvas metrics as §6.1 (the fade is a 24pt linear gradient to the card fill).

Image bodies show a 64pt thumbnail instead; binary shows one hex row; empty shows `No body`.
Tapping **anywhere** on the card pushes `AtlantisBodyViewerView`. Classification and highlighting
run on the **2 KB slice only** — the card must never classify or tokenize the whole payload, so
`List` cell cost stays bounded.

---

## 8. PINNED — current-match inset ring technique

**Decision: a layer-drawn overlay inside `AtlantisCodeTextView`, keyed off the current match's line
fragment rects. The background-image-attachment alternative is rejected.**

Why the alternative is rejected, concretely:

- TextKit has no "background image" attribute. `.backgroundColor` takes a color only, and
  `NSTextAttachment` inserts a **glyph** into the run — it would displace text, change every
  subsequent character offset, invalidate `lineStarts`, and break the gutter's fragment mapping.
  There is no way to get a stroked rounded rect behind existing glyphs through attributes.
- Even a hypothetical resizable-image background would be re-rasterized per appearance change and
  per Dynamic Type step.

The pinned implementation:

1. The text view hosts one non-interactive `AtlantisMatchOverlayView` sibling, pinned to the text
   view's content coordinate space (a subview of the scrolling content, so it scrolls for free and
   needs no per-frame offset math), `isUserInteractionEnabled = false`, hosting **one** `CAShapeLayer`.
2. On current-match change or layout invalidation, compute the fragment rects for the current match
   range only — `layoutManager.enumerateEnclosingRects(forGlyphRange:withinSelectedGlyphRange:in:)`
   — offset by `textContainerInset`. A match spans at most a handful of fragments, so this is O(1)
   in document size. **No other match** gets a ring.
3. The shape layer draws, in order: (a) the current-row tint — full-fragment-width rects at
   `currentRowTint`; (b) the match fill — rounded rects, radius **3**, at `currentMatchBackground`;
   (c) the ring — the same rounded path **inset by 0.75pt**, stroked at **1.5pt** with
   `currentMatchRing`, so the stroke sits fully inside the fill box and matches CSS
   `inset 0 0 0 1.5px`.
4. Non-current matches remain pure `.backgroundColor` attribute mutation over their ranges — no
   overlay, no rebuild.
5. The current match's **forced foreground** `#1C1C1E` (both appearances) is the single documented
   exception to "search mutates background attributes only": it is still a range-scoped attribute
   mutation on exactly the current match range, cleared when the current match moves. It is never a
   `textStorage` rebuild, and it never changes weight, size, or kern — so nothing reflows and the
   gutter mapping holds.
6. Invalidate the overlay on: current-match change, `layoutManager` layout-finished for the affected
   range, wrap-mode swap, bounds change, appearance change, Dynamic Type change. Redraw is one
   `CAShapeLayer` path assignment.

---

## 9. Search-highlight state machine (B4 contract)

Exactly one owner of highlight state:

1. Build phase (off-main, once per `(data, mode)` and per `asciiVisible` in hex): pretty-print →
   tokenize → `lineStarts` → `NSAttributedString`. Set `textStorage` **once**.
2. Query change (debounced 150 ms): compute `nsMatchRanges`; in one
   `beginEditing()`/`endEditing()`, remove `.backgroundColor` over **exactly the previously-set
   ranges**, then add it over the new ones; reset `currentMatchIndex` to 0.
3. Current-match change: clear the forced foreground on the old current range and set
   `.backgroundColor` back to `matchBackground`; set `currentMatchBackground` +
   forced foreground on the new one; hand the new range to the overlay; scroll ⅓-from-top; repaint
   the gutter (accent line number moves).

A match's foreground is never otherwise touched: the palette pairs in the tokens doc are legible
against both match fills in both appearances (v1 §4 rule, retained).

---

## 10. Performance contract (v1 §5, inherited verbatim + amendments)

All eight v1 rules stand and are merge-gate items:

1. Classification, pretty-print, tokenization, and attributed-string build happen **off the main
   thread**, once per `(data, mode)`, cached.
2. `textStorage` is set **once** per built string; search mutates attributes over ranges only.
   **Superseded by 12a** — progressive rendering means `textStorage` grows via version-delta
   `append`, never a full re-set after the stream's first chunk lands.
3. The text view owns its scroll (`isScrollEnabled = true` / `NSScrollView`); a parent `List` never
   does.
4. The gutter draws only numbers whose fragments intersect the visible rect, located by **binary
   search** over the cached `lineStarts`. No full-document enumeration on scroll.
5. `lineStarts` is computed once per string, off-main, from a UTF-16 scan.
6. **TextKit 1 pinned** — `UITextView(usingTextLayoutManager: false)` on iOS 16+, because the gutter
   and the ring overlay both use `NSLayoutManager` fragment geometry. Do not touch `.layoutManager`
   on a TextKit 2 view and hope for the compatibility fallback.
7. Tokenizers scan a `[UInt16]` buffer and emit `NSRange` — no `String.Index`↔`AttributedString`
   conversion in any loop.
8. Bodies over the gate stay gated; the hex dump builder caps at 1 MB.

Amendments introduced by v2:

- 8a. The gate threshold is `AtlantisViewerSettings.autoRenderLimitBytes` (default `65_536`), not a
  constant. The two landed perf fixes (`115fb63`, `5120ea2`) must not regress at any setting.
- 9a. The hex build cache key includes `asciiVisible`.
- 10a. The ring overlay is O(current match), never O(matches) and never O(document).
- 11a. The current-match forced foreground is the only foreground mutation search may perform (§8.5).
- 12a. Progressive body rendering (`docs/plan-progressive-body-render.md`): `AtlantisBodyStream`
  chunks a build off-main (line-aligned, 2 000 lines / 64 KB UTF-16 per chunk, first chunk capped at
  400 lines) and `AtlantisCodeTextView` appends only chunks it has not yet applied to `textStorage` —
  never a full replace after the first chunk. Search scoping reads `stream.loadedText` while
  incomplete, the full text once complete. Copy always copies the full payload, never the
  loaded-so-far prefix.

Budgets (measured in B9, on the 83 KB payload from `docs/plan-large-body-scroll-perf.md`): first
paint ≤ **150 ms** after the gate, keystroke-to-highlight ≤ **16 ms**, sustained **60 fps** scroll
with the gutter on, wrap on and off.

---

## 11. Layer split and file plan

| File | Change | Session |
|---|---|---|
| `Sources/AtlantisSyntaxTheme.swift` | **new** — every token in the tokens doc as a light/dark dynamic color pair; fonts; paragraph styles | B2 |
| `Sources/AtlantisSyntaxHighlighter.swift` | **new** — token kinds, JSON + XML/HTML tokenizers over `[UInt16]` → `NSRange`, `lineStarts`, attributed-string builder. **No SwiftUI import** | B2 |
| `Sources/AtlantisHexDump.swift` | **new** — §6.4 canonical dump. **No SwiftUI import** | B3 |
| `Sources/AtlantisBodyContent.swift` | **new** — `AtlantisBodyClassifier` (kind + counts + pretty-printers + `utf8Diagnosis`), `AtlantisBodyStats` (stats line, `grouped`), `AtlantisBodyMode` + matrix, gate predicate, `AtlantisBodyEmptyHint`. **No SwiftUI import** | B3 |
| `Sources/AtlantisFormat.swift` | **new (moved)** — `enum AtlantisFormat` relocated out of `AtlantisTrafficListView.swift:35-72` so it is not behind `#if canImport(SwiftUI)`; the headless stats builder depends on it. `AtlantisPalette` stays put | B3 |
| `Sources/AtlantisBodySearch.swift` | **edit** — add `nsMatchRanges(in:query:)`; the two existing public functions are untouched (the headers section still uses them) | B3 |
| `Sources/AtlantisCodeTextView.swift` | **new** — TextKit 1 view, gutter, §8 ring overlay, §9 state machine, ⅓-from-top scroll | B4 |
| `Sources/AtlantisSelectableText.swift` | **deleted** | B4 |
| `Sources/AtlantisBodyViewerView.swift` | **new** — §2-§6 chrome and all states; `AtlantisViewerSettings.autoRenderLimitBytes` | B5 |
| `Sources/AtlantisBodyPreviewCard.swift` | **new** — §7 | B6 |
| `Sources/AtlantisTrafficDetailView.swift` | **edit** — preview cards, `AtlantisMessageDetailView` retargeted, `navigationTitle("Detail")`, plus the removal map | B6 |

All new viewer code is `internal`, `#if canImport(SwiftUI)` + `@available(iOS 15.0, macOS 12.0, *)`
where it touches SwiftUI. **Public API does not grow**: only `AtlantisTrafficListView`,
`AtlantisTrafficDetailView`, and the existing `AtlantisBodySearch` stay public.
`Package.swift` stays at `.iOS(.v13)`. No model or DTO changes anywhere in this roadmap.

---

## 12. Out of scope (v1 §6, unchanged)

Collapsible JSON nodes / structure outline; JSONPath or jq filtering; body diffing; editable or
re-send; user-selectable themes beyond the built-in light/dark pair. Also out of scope: the sibling
design files `Request Overview.dc.html` and `Traffic List.dc.html`.
