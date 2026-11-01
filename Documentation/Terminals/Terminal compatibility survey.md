# Terminal compatibility survey

The canonical record of how each terminal emulator behaves on every axis
TUI cares about — input encodings (keys, mouse, trackpad) and output
behaviour (cursor advance vs painted width, emoji handling, glyph cell
coverage, colour depth, OSC 8 hyperlinks, OSC 52 clipboard writes, the window
title, progress bars and notifications, graphics protocols) — plus the environment variables each one defines and the exact
versions the observations were made against.

**Maintenance contract:** whenever anything new is observed or learned
about any terminal's behaviour — a new quirk, a version that changes one,
a new terminal evaluated — record it here, with the version and the method
of observation. Consult this document before making or reviewing any
change that relies on terminal-specific behaviour (`TerminalHost`,
`Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance` /
`.ghosttyCursorAdvance` / `.warpCursorAdvance`, `String.tmuxCursorAdvance`, the
`FrameDiffWriter` compensation paths, `ToggleCharacterSet.automatic`, …). tmux is a
**fifth cursor-advance model** here, not a fall-through to "unknown": a change
touching cursor advance must consider tmux's grid explicitly.

Two structural rules hold everywhere in that machinery:

- **The advance MODELS state raw-cluster truth, ungated.** Only the WALKS
  (and the claims) are gated on `TerminalWidthTraits`. A model gated on the
  traits silently reverts to the claim when a widening is turned off — it
  happened, and the conformance suite could not see it because a
  self-consistent model passes conservation while being wrong about the
  terminal. Where a walk rewrites a cluster, the raw cluster's model keeps
  an explicit arm anyway (`TerminalLedgerConformanceTests` checks it against
  the committed records).
- **Every emission must net the cursor to the claim** (the conservation
  law, `CursorAdvanceConservationTests`) — and consistency is not
  correctness, which is why every model value must also trace to a record
  under `Tools/TerminalProbes/data/`.

**Terminals covered:** Apple Terminal.app, iTerm2, Ghostty, Warp, tmux
(all measured). Jump to the
[measured advance table](#measured-advance-table-divergences-and-key-rows)
for the one-screen comparison.

## Methodology

> **CORRECTED 2026-08-27, twice — the first correction was itself wrong.**
> The original text below called advance "the ground truth for layout". A first
> correction swung to the opposite pole — "advance is not ground truth, paint
> is" — rebuilt the Apple Terminal model on paint alone, and shipped the
> mirror-image defect within a day: every full-width row carrying a skin tone
> wrapped, leaving default-white cells at its right edge, because the internal
> column the models no longer tracked is what decides when a row wraps.
>
> The truth is that **both counters are load-bearing and compensation must end
> each cluster with both at the claim**: the internal column (DSR) governs
> wrapping and how far a row's writes are accepted; the paint position governs
> where glyphs land. On iTerm2, Ghostty and Warp they agree for every row the
> pixel probes have covered, so the distinction is invisible; on Apple Terminal
> they diverge on 28, by up to nine cells. See
> [Four numbers, not one](#four-numbers-not-one).
>
> **EXTENDED 2026-08-27, the same day, by the treatment cards:** there is a
> THIRD per-row fact — the cluster's **stored width** in the row's text store —
> and it, not the cursor, decides where everything *later* on the row paints,
> absolutely-addressed writes included. A cluster stored wider than it paints
> (a flag pair: 2 painted, one surplus column; a composed ZWJ sequence under
> any cursor-move repair) displaces the whole tail left, and no cursor move
> repairs that, because cursor moves do not edit the store. Backward moves are
> worse than useless here: **any backward cursor motion over a composed
> cluster makes this terminal re-render it as its bare first segment** — the
> tone or the sequence survives in the store and dies on screen. The shipped
> treatments (see the Apple Terminal section) all make stored width == painted
> width == claim: rewrite (ZWNJ separation), decompose (ZWJ), or delete the
> surplus stored column (`DCH` — flags, keycaps).

### Four numbers, not one

A cluster has four different measurements and this project has, at various
times, mistaken each for another:

| number | measured by | what it governs |
|---|---|---|
| **advance** | DSR (`ESC[6n`) | the terminal's own bookkeeping |
| **landing** | pixels | **where the next character is drawn** — row alignment |
| **ink** | pixels | how many cells the glyph covers — gaps and overlap |
| **reserve** | the wrap test | whether the row wraps early |

`advance` and `landing` are BOTH load-bearing, for different failures: a walk
that leaves the internal column past the claim wraps every full-width row that
carries the cluster (white cells at the row's right edge — measured, and
briefly shipped); one that leaves paint short of the claim shears the row.
`landing` is the one no escape sequence will tell you. On iTerm2, Ghostty and
Warp the two are equal for all 78 rows the pixel probes have covered; on Apple
Terminal they differ for 28 (69 and 25 until `72ac8283`, 2026-08-28, which
added nine newly measured rows, three of them divergent; the 69 already in the
record reproduced with zero drift).

The displacement is **row-wide, not local**: on a row already carrying 🤙🏽, an
absolute `CUP` to column 50 paints at column 48. Every later cell on the row
inherits the whole accumulated error, which is why a single skin-toned emoji
moves an enclosing border two cells left.

Compensation moves BOTH counters, and must also respect the STORE. `CUF(n)`
moves internal and paint by exactly `n`. `CUB(n)` moves internal by exactly
`−n` — and what looks like "paint snapping to the internal column" is the
terminal re-rendering the cluster as its bare first segment, which is how a
CUB pull-back silently strips a skin tone on screen (treatment cards,
2026-08-27). Even where a pull-back aligns, a cluster whose stored width
differs from its painted width displaces every LATER write on the row —
sequential or absolutely addressed — by the difference, which cursor moves
cannot repair. Hence the shipped per-class treatments: rewrite as base + ZWNJ
+ modifier (every Fitzpatrick cluster — the one separator the terminal does
not re-join, with a text-presentation base VS-16-promoted first, 2026-08-28),
software decomposition (ZWJ sequences), and `CUB(1)` `DCH(1)` `CUF(1)` store
surgery (FE0F keycaps and flag pairs; a BARE keycap is pulled back instead). Every emission was
verified in the terminal itself: follower and absolute-move alignment,
background integrity, and a full-width row ending in the cluster with no wrap.
A claim must never be narrower than the landing —
`TerminalLedgerConformanceTests` asserts that — and no emission may leave the
internal sum above the claim — `CursorAdvanceConservationTests` sums exactly
that, and catches both halves of the briefly-shipped defect under mutation.

### Measuring paint

`landing_probe.py` prints a cluster, lets the terminal put a magenta marker
wherever it thinks the cursor is, and screenshots the result;
`landing_analyze.py` reads the marker's column out of the pixels. The reading is
arithmetic, not judgement — this project has a poor record of interpreting
screenshots by eye, and every conclusion in this section that had to be
corrected was corrected by a program looking at the same picture.

The instrument checks itself in two ways, both of which caught real errors:

- **A self-check marker** at a column the probe chose, with nothing in front of
  it. If the analyser cannot read that column back exactly it aborts rather than
  report numbers off a mis-derived grid.
- **Control clusters** whose landing is known before any terminal is asked
  (ASCII is 1, East-Asian-Wide is 2). iTerm2 read uniformly +1 on these,
  including for `a`; taking that as a terminal behaviour would have "corrected"
  all 69 clusters on a host that gets every one of them right.

Five bugs in the instrument were found this way, each of which produced
confident, plausible, wrong numbers: reading the marker's left edge (a wide
glyph's ink spills into it, biasing every skin-tone reading), bounding `ink` by
`landing` (they then agree by construction), measuring `ink` further along the
same row (it inherits the displacement being measured), calibrating off a
stale window from an earlier run, and — found 2026-08-28 — **screenshotting a
page with the cursor still on it**.

That last one is worth stating plainly, because it is the reason this section
used to say `ink` could not be trusted. The probe draws each cluster a second
time on its own row to measure ink, and then simply stopped: the terminal left
a block cursor sitting immediately after the *last* cluster on the page, inside
the eight-cell ink window, and `ink_cells` reports the **rightmost** inked cell.
So exactly one row per page — whichever cluster happened to fall last — read
`ink == advance + 1`, describing the cursor rather than the glyph. It was
invisible precisely because it was rare, self-consistent, and moved: which
cluster it hit depends on where the page breaks fall, so growing the corpus
changed the answer for a host whose rendering had not changed at all.

The probe now hides the cursor (DECTCEM) and parks it on the self-check row.
Re-measuring all four hosts afterwards moved **only** `ink`, and only on
last-on-page rows — `advance`, `landing` and `reserve` are DSR- and
wrap-derived and were identical to the cell — which is what a fix for this
specific fault should look like. Seven committed values were wrong:
`combining_acute` on all four hosts (2 → 1, its true one cell), and on Apple
Terminal `partying` (3 → 2), `vs16_wavy_dash` (3 → 2), `zwj_astronaut`
(6 → 2) and `tone_thumbsup` (5 → 2).

`ink` is still recorded but **not asserted on** — it remains a coverage
threshold over an antialiased glyph, and a genuine over-ink (Apple paints
⏩ ⏪ ⏫ ⏬ into three cells) is a real reading rather than a bug. But the
specific evidence this document cited for distrusting it — "it puts 👍🏼 at five
cells on a host where it composes into about two" — was the cursor, not the
threshold. That host puts 👍🏼 at two.

Every probe result is written with a provenance stamp (`probe_stamp.py`) and
the curated ones are committed under `Tools/TerminalProbes/data/`, one file per
terminal, version and screen buffer. The stamp records the two conditions this
document has twice been bitten by leaving out — **which screen buffer**, and
**whether DEC mode 2027 was set** — because a number without them cannot be
re-read later and either trusted or discarded. See `data/README.md`.

Records are produced by running a probe, never by editing a file: that is the
only mechanism that keeps "contributing a measurement" and "making one" the
same act.

Reproducible probes live in `Tools/TerminalProbes/`; run them INSIDE
the terminal under test:

- `advance_probe.py` — measures the **cursor advance** of a battery of
  grapheme clusters with DSR (`ESC[6n`) position queries, and dumps the
  terminal-relevant environment. Writes JSON to `$PROBE_OUT`. Advance is
  the ground truth for layout: a glyph whose advance differs from the
  width TUI's tables claim shifts everything after it on the row.
  **Set `PROBE_ALT=1` and use those numbers**: TUI apps run on the
  ALTERNATE screen buffer, and advance can differ between buffers —
  iTerm2 advances VS-16 clusters by 2 on its primary screen but by 1 on
  the alternate screen. A first pass probed the primary screen only,
  concluded iTerm2 had no VS-16 quirk, and shipped a wrong model. iTerm2
  is also sensitive to write boundaries on the primary screen: a VS-16
  selector flushed ~100 ms after its base retro-colours the glyph without
  advancing the cursor.
- `visual_card.py` — prints a static `|<c>|<c>|<c>|X` alignment card with a
  column ruler; screenshot + zoom shows **painted width** (which DSR
  cannot see) and glyph appearance: merged vs split clusters, seams,
  swatches, cell coverage.
- `mouse_probe.py` — enables SGR mouse reporting (1000/1002/1006) in raw
  mode and appends every input byte sequence to `$PROBE_OUT`, for
  capturing exactly what a terminal sends per gesture.
- `identity_probe.py` — asks the terminal **who it is** over escape
  sequences (DA1, DA2, DA3, XTVERSION, XTGETTCAP) rather than trusting the
  environment, and dumps the identifying variables alongside. Each query is
  fenced with a DSR request, which every terminal answers, so a query that
  goes unanswered reports `<silent>` instead of hanging. This is the only
  identification that survives an ssh hop — see the next section.

The `TerminalClientQuirks` app (`swift run TerminalClientQuirks`) is the
interactive counterpart to these probes: it shows which terminal was
detected and by which signal, the advance model in force, and an alignment
strip that fails visibly on any cluster the host handles differently from
TUI. Its **Custom** screen decomposes the workarounds into one switch per
cluster class, so an unmeasured terminal can be characterised by experiment
and exported as a `TerminalQuirks(...)` literal — see
`Sources/TerminalClientQuirks/README.md`.

Since 2026-08-28 the switches can express **every** measured host: all four
native shapes are pinned to their real walks emission-for-emission by
`TerminalQuirksTests`, with no skipped rows. That pin is the point of the
app — what an explorer dials in is exactly what TUI would emit once the
model was written down — and it only became true when the mirror grew the
four mechanisms the real walks already had: claiming the detached skin-tone
swatch (for every base, or only a BMP one), merging a tone into a narrow
text base's single cell, a width table cut before Unicode 16.0, and keycaps
that advance a fixed 2 whichever spelling arrives — which the FE0F form's
claim meets and the bare form's one-cell claim does not, so only the bare
one is repaired.

"Advance" below = cells the cursor moves; "paints" = cells with ink.
TUI's shared layout width (`Character.terminalWidth`) claims 2 for all
the emoji-class clusters below unless noted.

---

### The framework's own chrome — advance and ink measured 2026-09-04

Until 2026-09-04 the width corpus had 116 rows for every class of cluster
someone's *data* might contain and none for a glyph TUI itself draws. Every
keyboard symbol the status bar emits (`⎋ ↵ ⏎ ⇥ ⇤ ⌫ ⌦ ␣ ↑ ↓ ← → ⇧ ⌃ ⌥ ⌘`) and
every glyph its borders, scrollbars, tracks, radio buttons, steppers and
disclosure triangles are made of (`◀ ▶ ▼ ▲ ● ◯ ◌ █ ▌ ▐ ▒ ─ │`) was claimed at
one cell on trust. Fifteen of the twenty-nine are East Asian **Ambiguous**,
whose width is a terminal SETTING rather than a property of the character, so
the claim was not obviously safe — and a border glyph measured wrong moves
every cell of every row inside it.

**Measured on all four hosts: every one of the twenty-nine advances exactly one
cell.** Ghostty 1.3.1, iTerm2 3.6.11, Apple Terminal 455.1 and Warp
v0.2026.09.02 agree with each other and with the claim, with no Ambiguous-width
divergence anywhere. (The *ink* is a separate question with a different answer —
eight of the rows paint two cells while advancing one, and not the same eight on
every host. See "The ink half" below.) Records:
`Tools/TerminalProbes/data/{ghostty-1.3.1,iTerm2,Apple-Terminal,Warp}-advance.json`.
Since 2026-10-19 `ChromeGlyphAdvanceTests` reads each host's alternate-screen
record of that day's runs instead, the screen TUI draws on
(`{ghostty-1.3.1,iterm2-3.7.6,apple-terminal-455.1,warpterminal-v0.2026.09.30.08.29.stable_01}-alternate.json`):
every chrome row, these and the ones added since, one cell on all four.

What remains open for these rows is `landing` — where the glyph is painted
relative to its neighbours — which needs pixels rather than DSR. They stay in
`TerminalLedgerConformanceTests.awaitingLandingMeasurement` until then. The
`ink` half is answered below.

#### The ink half: card-read 2026-09-04, and it is PER HOST

A chrome glyph can paint two cells while advancing one — the grid intact, the
ink over the line — and that is what the `↵` report from Ghostty was: the
status bar's `Shortcut.enter` swallowing the space before its label, so
`↵ activate` reads as `↵activate`. DSR cannot see it, because nothing moved.

**Instrument:** `Tools/TerminalProbes/overhang_card.py`, run inside each host
and **read by a person**. It draws each `chrome_key`/`chrome_glyph` row (29
on 2026-09-04, 34 since the keyboard symbols of 2026-10-05) in ONE cell
between two flanks of solid magenta; ink on a flank is
overhang, and which flank says which way. Two calibration rows (`█` must meet
both flanks, `a` must clear them) say whether the card is legible on the host
before any row under it is believed. This is a **paint** measurement of the
kind a screenshot would give, not a DSR reply — the machine version
(`landing_probe.py`) needs a Screen Recording grant this project does not
have — so it carries a person's judgement where the advance records carry a
terminal's own number.

**Read 2026-09-04** on Apple Terminal 455.1, iTerm2 3.6.11, Ghostty 1.3.1 and
Warp v0.2026.09.02:

| Glyph | Codepoint | Corpus row | Apple Terminal | iTerm2 | Ghostty | Warp |
|---|---|---|---|---|---|---|
| `↵` | U+21B5 | `key_return` | — | — | **overhangs** | — |
| `⎋` | U+238B | `key_escape` | — | — | — | **overhangs** |
| `⏎` | U+23CE | `key_return_symbol` | — | — | — | **overhangs** |
| `⌫` | U+232B | `key_backspace` | — | — | — | **overhangs** |
| `⌦` | U+2326 | `key_delete` | — | — | — | **overhangs** |
| `␣` | U+2423 | `key_space` | — | — | — | **overhangs** |
| `⌥` | U+2325 | `key_option` | — | — | — | **overhangs** |
| `⌘` | U+2318 | `key_command` | — | — | — | **overhangs** |

Every other chrome row is contained on every host: `⇥ ⇤ ↑ ↓ ← → ⇧ ⌃`, and all
thirteen drawing glyphs (`◀ ▶ ▼ ▲ ● ◯ ◌ █ ▌ ▐ ▒ ─ │`) — which is the answer
that mattered most, because a wide claim is never the remedy for a border. The
CJK control `漢` claims two cells and overhangs neither flank on any host, and
the calibration rows read as described everywhere, so the readings under them
stand.

**Not on that card:** the five keyboard symbols the corpus gained on
2026-10-05, when the keys took macOS's symbols — `↩` (`key_return_hook`), `↖`
(`key_home`), `↘` (`key_end`), `⇞` (`key_page_up`) and `⇟` (`key_page_down`),
none of which the framework had drawn before (see "Key symbols" below). Their
ink is **UNREAD on every host**. `↩` matters most: it replaced `↵` as the
status bar's Return, and Ghostty's `returnArrow` claim covers `↵` alone, so
it is the first row to read on Ghostty.

Chrome glyph selection that rests on these rows: `NavigationSplitView`'s
sidebar toggle (2026-09-13). The edge column, shown while a leading column is
hidden, draws `▶` (U+25B6) alone in a one-cell column, and the leftmost divider
draws `◀` (U+25C0) in place of its middle grip dot, both as `Stepper` draws them,
with no VS-15. They are chosen because this reading has both advancing one cell
with their ink contained on all four hosts; a glyph that overhung would paint
into the neighbouring column's content.

The resize grip (`BorderGrip`) — `.userResizable`'s edge and corner handles,
and since 2026-10-06 a detented sheet's grabber, which draws the same handle on
a `─` rule — is doubled Box Drawing (`═` `║` `╝`), heavy (`━` `┃` `┛`) against a
double-line border. Those six are **not rows of the card**: they share the Box
Drawing block with `─` and `│`, which are, and nobody has seen one misdraw, but
neither their advance nor their ink has been measured on its own.

**Chrome that is an emoji: a critical dialog's ⚠️ (2026-10-05).** An alert or
confirmation dialog whose severity is critical starts its title, in the top
border, with U+26A0 U+FE0F — the owner's direction of 2026-10-04 being that
emoji are welcome where they help, with the known hosts' defects worked
around, and a host nobody has measured allowed to draw one wrong. It is spelt
WITH the selector on purpose. Bare, U+26A0 is a text-presentation character
whose width is the host's choice (one cell or two); with the selector it is a
VS-16 pictograph, the measured row of the advance table below (`⚠️` is in it):
claimed two cells, advanced two by Ghostty and Warp, and advanced ONE by
Terminal.app and iTerm2, which the writer squares with `ECH(2)` + glyph +
`CUF(1)` exactly as it does for a VS-16 pictograph in an app's own text. So
the border closes at the claimed width on all four hosts, and the walls below
it line up (`DialogModifierTests` checks the claim). Two things it does NOT
rest on: the `supportsEmojiChrome` allowlist, which is about the VS-15
*monochrome* chrome glyphs and gates nothing here — this sign is drawn on
every host — and the overhang card, which has not been run for it: its ink
is the font's, in the font's colours, and unread.

**Recorded caveat: the FONT was not captured with this reading.** Overhang is a
font property at least as much as a host one, and the card's own instructions
ask for the font and its size. What is recorded here is host + version + date,
so a re-run under a different font may disagree — treat a contradicting reading
as a font difference to be recorded, not as this one being wrong.

**The claim follows the host, and that is a departure.** TUI's standing rule
is that a claim is host-independent and covers the widest painter, with narrow
painters taking a blank cell — the rule stated for Ghostty's SF Symbols below.
Applied here it would give one table, the union of the eight codepoints above,
and that union is **wrong for 24 of the 32 measured (host, glyph) pairs** —
eight codepoints against four hosts, of which only eight cells of the table
above say "overhangs". A stray blank cell after all eight glyphs on Apple
Terminal and iTerm2 (16), after seven of them on Ghostty, and after `↵` on
Warp. The two overhanging sets are
**disjoint** — Ghostty's one glyph is not among Warp's seven — so no single
claim can be right for both, whichever way it leans. This is the case the
`TerminalWidthTraits` note anticipated when it said such a class "would need
its own measured rule": it has one now, on all four hosts, so the set lives in
`TerminalWidthTraits.chromeOverhang` alongside the other two host-dependent
claims and moves with them (including the cache-invalidating `generation` bump
and the `withTraits(_:)` scoped pin the tests need).

**The mechanism.** A codepoint listed for the host in force claims **two**
cells, every per-host advance model keeps reporting the measured **one**, and
the existing `ECH(2)` + glyph + `CUF(1)` walk squares them — the same treatment
SF Symbols, VS-15 chrome and lone regional indicators already take. The grid
stays exactly where it is; the glyph simply gets a blank neighbour to overhang
into. Four consequences are worth naming because none of them is obvious:

- **An unmeasured host claims one.** tmux and `unidentified` take
  `ChromeOverhang.contained` with every terminal nobody has run the card in.
  Widening there would scatter a blank cell after every shortcut glyph in the
  status bar for a defect nobody has seen on that host — and the two hosts that
  do have it disagree about which glyphs, so there is no majority to guess with.
- **The shortfall is ours, so it is owed by whoever emits under the claim.** It
  is not a terminal's defect but the price of a claim TUI widened, so
  `TerminalQuirks` has no switch to turn it off, the empty-quirk-set walk still
  emits it, and an **unidentified** host — which otherwise receives no
  compensation at all — gets `String.withChromeOverhangCompensation()`. Under
  an unidentified host's own traits that walk is the identity; it does the work
  when a diagnostic pinned a measured host's claims. That walk compensates but
  does **not** normalize: the shared walk it borrows also strips a redundant
  VS-16 off a tone cluster and decomposes ZWJ sequences, and those are repairs
  calibrated against the four measured hosts. Handing them to a terminal TUI
  could not name would rewrite its content — `☝️🏽` came back as `☝🏽` — which is
  the one thing an unidentified client is documented never to do.
- **The compensation gate stays the UNION of all four hosts.** It decides only
  whether the per-`Character` walk runs, and the walk then asks the claim in
  force per character. Admitting a row whose glyph this host draws contained
  costs a walk that changes nothing; skipping one it smears shears the row. It
  is derived from the tables rather than written beside them, so the two cannot
  drift (`CompensationGateTests`).
- **Box Drawing and Block Elements (`─ │ █ ▌ ▐ ▒`) can never be listed**, and
  the predicate refuses them rather than trusting whoever edits a table. For a
  border glyph a two-cell claim is not a remedy but a second defect: every row
  inside the border loses a column. If one is ever measured to overhang, the fix
  is a different glyph — chrome glyph selection — not a wider claim. The card
  measured all six contained on all four hosts.

`ChromeOverhangTests` holds the matrix — four hosts against 34 rows — so a
reading edited into one host's table cannot silently become every host's.

### Key symbols — macOS's spelling, adopted 2026-10-05

Since 2026-10-05 every key TUI names on screen — a menu row's shortcut
column, the status bar's keys and its undo and redo hints, the `Shortcut`
constants, `KeyboardShortcut.displayString`, `KeyEvent.displayString` — is
spelled by one formatter (`KeySymbols`), as a macOS menu spells a key
equivalent: the modifiers in the order **⌃ ⌥ ⇧ ⌘**, then the key, a letter
in upper case (`⌃⇧Z`, `⌥F`, `⇧⇥`, `⌘?`). The spelling was read from AppKit's
`NSKeyboardShortcut` (the class that draws menus' and System Settings'
shortcuts) on macOS 15, for every key and modifier set TUI can name, in all
seven of TUI's languages; only the space bar's name changes with the
language (`Space`, `Leertaste`, `Espace`, `Barra spaziatrice`, `Espacio`,
`空格键`, and `Space` again in Japanese). It replaced the terminal spellings
`^S`, `M-s` and `^S-Z` (for Control-Shift-Z), and the names `Esc`, `Return`,
`PgDn`, `Del`, which existed because those four modifier symbols were believed
to be ambiguous-width. Only one of them is. The status bar keeps one spelling
of its own: in it a letter's case is its Shift (an app's `"N"` item is
Shift-N), so its undo and redo hints write a letter held with nothing but
Shift in the case it types — `u`, and `U` for Shift-U — where a menu draws
`U` and `⇧U`.

| Glyph | Codepoint | Key | East Asian Width | Drawn before 2026-10-05? | Advance / ink |
|---|---|---|---|---|---|
| `⌃` | U+2303 | Control | Neutral | status bar constant | measured 2026-09-04: 1 / contained |
| `⌥` | U+2325 | Option | Neutral | status bar constant | measured: 1 / **Warp overhangs** |
| `⇧` | U+21E7 | Shift | **Ambiguous** | status bar constant | measured: 1 / contained |
| `⌘` | U+2318 | Command | Neutral | status bar constant | measured: 1 / **Warp overhangs** |
| `⎋` | U+238B | Escape | Neutral | yes | measured: 1 / **Warp overhangs** |
| `↩` | U+21A9 | Return | Neutral | **no** — `↵` U+21B5 was | 1 (2026-10-05, below) / ink **UNMEASURED** |
| `⇥` | U+21E5 | Tab | Neutral | yes | measured: 1 / contained |
| `⌫` | U+232B | Delete (backspace) | Neutral | yes | measured: 1 / **Warp overhangs** |
| `⌦` | U+2326 | Forward Delete | Neutral | yes | measured: 1 / **Warp overhangs** |
| `↑ ↓ ← →` | U+2191, 2193, 2190, 2192 | arrows | **Ambiguous** | yes | measured: 1 / contained |
| `↖` | U+2196 | Home | **Ambiguous** | **no** — `⤒` U+2912 was | 1 (2026-10-05, below) / ink **UNMEASURED** |
| `↘` | U+2198 | End | **Ambiguous** | **no** — `⤓` U+2913 was | 1 (2026-10-05, below) / ink **UNMEASURED** |
| `⇞` | U+21DE | Page Up | Neutral | **no** (a constant nothing drew) | 1 (2026-10-05, below) / ink **UNMEASURED** |
| `⇟` | U+21DF | Page Down | Neutral | **no** (likewise) | 1 (2026-10-05, below) / ink **UNMEASURED** |

Shift-Tab is `⇧⇥`, as macOS draws it, so `⇤` (U+21E4) is no longer drawn by
the framework; the space bar is a word, so `␣` (U+2423) is not either. Their
corpus rows stay: they were measured, and an app may still draw them. No key
TUI can name is keypad Enter (`⌤`, U+2324, which macOS draws for it): there
is no such `KeyEquivalent`, in SwiftUI or here, and the kitty keyboard
protocol reports it as Return with the numeric-pad flag, which macOS does not
draw.

**Width: every glyph claims one cell, the Ambiguous ones included.** That is
TUI's standing treatment of East Asian Ambiguous chrome, not a new
decision: the four measured hosts advance every Ambiguous chrome glyph one
cell with their default settings (above), and the box drawing every border is
made of (`─ │`) is Ambiguous too. Where a host is set to draw ambiguous
characters wide (iTerm2's "Ambiguous characters are double-width"), every
border and arrow already advances two, and TUI's answer to that setting is
autowrap off — a row too wide by its own count loses its last cells rather
than wrapping and scrolling the screen (see "Autowrap off while the app runs" below) — not a wider
claim, which would be wrong on every other host. `⇧`, `↖` and `↘` join the
arrows and the borders in that class and add no new kind of failure. The
symbols that were measured to overhang on Warp keep the per-host two-cell
claim and `ECH`+`CUF` walk described above.

**Advance measured by the coordinator, 2026-10-05; ink UNMEASURED —
coordinator to fill.** Each glyph was written after a carriage return and an
erase-line on the primary screen, with a cursor-position report before and
after it: `⌃ ⌥ ⇧ ⌘ ⎋ ↩ ⌤ ⇥ ⇤ ⌫ ⌦ ← ↑ → ↓ ↖ ↘ ⇞ ⇟ ⌧ ⇪ ␣`, and the chord
`⌃⇧Z`. Every glyph advanced one cell and the chord three, on every host
reached, the five the framework draws for the first time (`↩ ↖ ↘ ⇞ ⇟`)
included. What a DSR cannot see is the INK — whether a glyph overhangs its
cell, or is drawn at all (a font with no glyph for it draws a box, which also
advances one): that needs `overhang_card.py` read by a person, or a
screenshot. Until a host's ink is read, the claim is one cell and no host
widens it.

| Host | Version | Advance, all 22 glyphs | `⌃⇧Z` | Ink of `↩ ↖ ↘ ⇞ ⇟` |
|---|---|---|---|---|
| Apple Terminal | 455.1 | 1 each | 3 | UNMEASURED |
| iTerm2, ambiguous narrow (the default) | 3.7.3 | 1 each | 3 | UNMEASURED |
| iTerm2, "ambiguous characters are wide" | — | UNMEASURED (`⇧`, the arrows, `↖ ↘` expected 2) | — | UNMEASURED |
| Ghostty | 1.3.1 | not reached on 2026-10-05 (the launch waited on a prompt); on 2026-10-19 `advance_probe.py` read every key row of the corpus at 1, `↩ ↖ ↘ ⇞ ⇟` included, on both screens | not asked | UNMEASURED |
| Warp | v0.2026.09.30.08.29 | 1 each | 3 | UNMEASURED |
| kitty | — | UNMEASURED (did not launch) | — | UNMEASURED |
| tmux, no outer terminal recorded | 3.7c | 1 each | 3 | UNMEASURED |

The tmux row is tmux's own grid. Its stamp names no outer terminal: the
pane's environment has `TERM_PROGRAM=tmux` and
`__CFBundleIdentifier=com.anthropic.claudefordesktop`, which a pane inherits
from the environment its server started in — the Claude desktop app's, not a
terminal's. Whatever client was or was not attached, tmux answers a DSR itself,
from its own cell model, so the row says what tmux counts, not what an outer
terminal draws; tmux inside Ghostty or iTerm2 is a separate, UNMEASURED row.

iTerm2 3.7.3 and Warp v0.2026.09.30 are newer than the versions the
2026-09-04 card recorded; the ink of `⌃ ⌥ ⇧ ⌘ ⎋ ⇥ ⌫ ⌦ ↑ ↓ ← →` is that card's
reading, on those older versions.

That DSR was hand-rolled, not one of the committed probes, so it is recorded
here in prose and in no file under `Tools/TerminalProbes/data/`. The five
glyphs are corpus rows now (`key_return_hook`, `key_home`, `key_end`,
`key_page_up`, `key_page_down`, class `chrome_key`), in `advance_probe.py`'s
battery and on `overhang_card.py`, so a re-run of the committed probes records
their advance and draws them for the ink reading. The re-runs committed on
2026-10-19 read all five at one cell in every host's alternate-screen record,
and `ChromeGlyphAdvanceTests` asserts it from those.
`TerminalLedgerConformanceTests`, which reads landing records, still lists
them as awaiting measurement on every host.

A glyph that overhangs on a host joins that host's table in
`TerminalWidthTraits.ChromeOverhang`, whose rows must be corpus rows — which
these five now are. A host measured to have no
glyph for the symbols at all (a missing-glyph box) is a different case: it
needs the keys' names spelled out instead, not a wider claim.

**Spelled out, where the font has no glyph for them.** The symbols are drawn
in the terminal's font, which TUI cannot see, so the user can turn them off
with `TUI_KEY_SYMBOLS=0` and an app with `Scene.keyNotation(.spelledOut)`;
the status bar and a menu's shortcut column then write `Ctrl-Shift-Z`, `Esc`,
`Return`, `Shift-Tab`, `Backspace`, `Del`, `Home`, `End`, `PgUp`, `PgDn`
(`KeyNotation`). The arrows stay arrows, being in every font a terminal uses,
and the function keys and the space bar are words already. **No host is
measured unable to draw the symbols**, so none defaults to the names: the
symbols are the default everywhere until a measurement above says otherwise,
and such a host's default would be set where the app runner reads
`TUI_KEY_SYMBOLS` (`TerminalClient.keyNotationRequested`).

### The drop-operation badge — advance measured 2026-10-13

Since 2026-10-13 a drag's preview wears a one-cell badge in its top-right
corner naming the operation the destination under it proposes (decisions
B10): `+` for a copy, `↗` for a link, `⊘` for a drop that is not allowed
(`DropOperation.badgeGlyph`). The badge is composited over the preview's
corner cell, so a glyph that advanced or drew two cells would push the
preview's last column out of line or overhang the page beside it.

| Glyph | Codepoint | Operation | East Asian Width | Corpus row | Advance / ink |
|---|---|---|---|---|---|
| `+` | U+002B | copy | Narrow | (ASCII) | 1, by definition |
| `↗` | U+2197 | alias (link) | **Ambiguous** | `chrome_drop_link` | measured 2026-10-13: 1 on every host reached / ink **UNMEASURED** |
| `⊘` | U+2298 | forbidden | Neutral | `chrome_drop_forbidden` | measured 2026-10-13: 1 on every host reached / ink **UNMEASURED** |

**Advance measured with `advance_probe.py`**, its battery extended by the two
rows, run in each host from a `.command` file on the primary screen, on
macOS 15.8.1:

| Host | Version | `↗` | `⊘` |
|---|---|---|---|
| Apple Terminal | 455.1 | 1 | 1 |
| iTerm2, ambiguous narrow (the default) | 3.7.4 | 1 | 1 |
| iTerm2, "ambiguous characters are wide" | — | UNMEASURED (`↗` expected 2, with the borders) | UNMEASURED |
| Ghostty (mode 2027 set) | 1.3.1 | 1 | 1 |
| Warp | v0.2026.09.30.08.29 | 1 | 1 |
| kitty | — | UNMEASURED (did not launch, as on 2026-10-05) | UNMEASURED |
| tmux, its own grid | 3.7c | 1 | 1 |

`↗` therefore joins the arrows and the borders in the class the "Key symbols"
section describes: one cell with each host's default settings, two where a
host is set to draw ambiguous characters wide, which TUI answers with
autowrap off rather than a wider claim. `⊘` is Neutral and measured one cell
everywhere reached.

The same runs re-read every other row of the battery. Apple Terminal, Ghostty
and Warp matched their committed records row for row. **iTerm2 3.7.4 did not,
on nine rows outside the chrome classes**: `hangul_jamo_lv` 3 → 2,
`hangul_jamo_lvt` 4 → 2, `keycap_0`, `keycap_1`, `keycap_hash` and
`keycap_star` 1 → 2, `skin_lifter_bare` 2 → 3, `skin_thumbs` and `zwj_skin`
2 → 4 (committed record → this run). Whether that is the new version or a
profile setting (its Unicode version) was not followed up; the run's record
is kept with the lane's notes, not committed. iTerm2 3.7.6, measured on both
screens on 2026-10-19 with a default profile that sets no Unicode version,
agrees with 3.7.4 on the jamo and the keycaps and moved again on the tones —
all to 2 (see "iTerm2 3.7.6 re-measured"); its records are committed. No record was rewritten, so
`ChromeGlyphAdvanceTests` listed the two badge rows as awaiting measurement on
every host until a re-run was committed. The 2026-10-19 runs were, on all four
hosts, with both rows at 1, and the suite reads them. **The ink is
unmeasured**: what a DSR cannot see — a glyph overhanging its cell, or a font
with no glyph for it drawing a box — needs `overhang_card.py` (which draws the
two rows now) read by a person. Until it is, the claim is one cell and no
host widens it.

### A fill that starts within a cell — read 2026-10-27

A slider's fill from a neutral value starts within a cell under `.blockFine`
(owner ruling B33-SUBCELL): the eighth-block ramps (`▏`…`▉`) grow only from
a cell's left, so that cell is drawn as its complement — the ramp glyph
covering the empty left part, in the track's colour, over the fill's colour
as the cell's background (`TrackRenderer.MirroredEdge`).
`Tools/TerminalProbes/mirrored_ramp_card.py` draws it at every step beside
the plain ramp, in double-width rows, on macOS 15.8.1:

| Host | Version | The mirrored edge |
|---|---|---|
| Apple Terminal | 455.1 | Each step in order; the glyph falls short of the line's height, so a sliver of the fill's colour shows above the empty part. The plain ramp beside it does the same in mirror image (the track's colour above the fill), so the edge is no worse than the ramp already drawn. |
| iTerm2 | 3.7.6 | Clean: full height, each step in order. |
| Ghostty | 1.3.1 | Clean: full height, each step in order. |

Warp, kitty and xterm.js are not read.

## Identifying the host terminal

Every per-terminal model in this document is only as good as the answer to
"which terminal is this?". That question has a clean answer locally and a
poor one over ssh, and the gap is a real, shipped rendering bug rather than
a theoretical one.

**`TERM_PROGRAM` does not cross an ssh hop.** It is not an `LC_*` variable,
and OpenSSH forwards only `LANG` and `LC_*` by default (measured:
`/etc/ssh/ssh_config.d/100-macos.conf` sends `LANG LC_*`). The complete
environment of an `ssh` session into macOS from Apple Terminal, captured
2026-08-26, contains nothing that names the terminal:

```
LANG=en_AU.UTF-8            TERM=xterm-256color
SSH_CLIENT=…  SSH_CONNECTION=…  SSH_TTY=/dev/ttys008
SHELL=/bin/zsh  USER=…  HOME=…  PATH=…  TMPDIR=…  SHLVL=1  PWD=…
```

No `TERM_PROGRAM`, no `LC_TERMINAL`, no `TERM_SESSION_ID`; `TERM` is the
generic `xterm-256color` that dozens of terminals report.

**What that costs.** An unidentified host gets no cursor-advance
compensation, and that default is correct and must stay: absent explicit
evidence otherwise, a terminal is assumed to render correctly. Every
compensation here is a workaround for a measured *defect*, so applying one
blindly would penalise a well-behaved terminal that simply isn't
special-cased — breaking a row that was fine. The bug is upstream of that
choice. Apple Terminal is not an unknown terminal; it is the most heavily
measured host in this document, and it was landing in the unknown bucket
purely because of the transport. Unnamed, it renders (measured on the
`Example` main menu):

| Cluster class | Symptom with no compensation |
|---|---|
| VS-16 pictographs (🛡️ ✏️ ❤️) | paints 2, advances 1 — row pulled 1 cell left per emoji |
| Lone regional indicators (U+1F1E6…) | same 2/1 under-advance |
| SF Symbols (Plane-16 PUA) | same 2/1 — three adjacent symbols sit 1 cell apart, not 2 |
| Fitzpatrick clusters (🤙🏽) | modifier never stripped: over-advances, stranding 2 unpainted cells at the right edge |

The SF Symbols row needs the SF Symbols font on the Mac that runs `Example`;
without it the main menu draws no symbol (see tmux's "The defect this closed").

**The signals, and how far each reaches.**

| Signal | Names | Crosses ssh | Notes |
|---|---|---|---|
| `TERM_PROGRAM` | all four hosts + tmux | ✗ | authoritative when present |
| `VTE_VERSION` / `GNOME_TERMINAL_*` | GNOME Terminal (VTE) | ✗ | authoritative for VTE |
| `LC_TERMINAL` | iTerm2 only | ✓ | set by iTerm2's shell integration; `LC_*` is forwarded |
| `TERM` | **Ghostty only** | ✓ | the termtype travels in ssh's `pty-req` (RFC 4254 §6.2) |
| XTVERSION (`ESC[>0q`) | iTerm2, Ghostty, Warp, GNOME Terminal | ✓ | GNOME Terminal answers `VTE(8001)`; **Apple Terminal answers nothing** |
| Process-ancestry walk | local apps | ✗ | over ssh the parent is `sshd` |
| `TUI_TERM_PROGRAM` | anything | ✓ | explicit override, same vocabulary as `TERM_PROGRAM` |

**`TERM` as an identity — added 2026-08-26.** Measured across the four hosts,
only one names itself:

| terminal | `TERM` |
|---|---|
| Ghostty 1.3.1 | `xterm-ghostty` |
| Apple Terminal 455.1 | `xterm-256color` |
| iTerm2 3.6.11 | `xterm-256color` |
| Warp 2026.07 | `xterm-256color` |

So it closes exactly one gap, and a real one: **Ghostty over ssh was
unidentified.** `TERM_PROGRAM` is gone, Ghostty sets no `LC_TERMINAL`, and the
Device Attributes fingerprint names only Apple Terminal — so its VS-15 chrome
glyphs (⬛︎ ⬜︎, which every Toggle draws) and its SF Symbols went
uncompensated and those rows sheared. Verified end-to-end by running
`TerminalClientQuirks` in Ghostty with the environment scrubbed to what an ssh
hop leaves: identified as Ghostty, compensating.

Generic termtypes are excluded — `xterm-256color` is three of the four hosts
above — as are the multiplexer termtypes (`tmux-256color`, `screen-256color`),
which name the multiplexer rather than the terminal and are answered by
`$TMUX` first anyway. A test pins both exclusions.

A note on the risk that kept this out until now: `TERM` is routinely
*downgraded* to `xterm-256color` when sshing to a host without Ghostty's
terminfo entry (this Mac has ncurses 6.0.20150808 and no `xterm-ghostty`
entry, so that is the common case, not the exotic one). That is a false
NEGATIVE — it makes `TERM` name nothing — and cannot be caused by consulting
it. `TERM_PROGRAM` still outranks it, so a downgraded `TERM` beside a local
`TERM_PROGRAM` is unaffected.

The one host that most needs naming is the one no remote-capable signal
reaches: Apple Terminal sets no forwarded variable and answers no XTVERSION.
Hence `TUI_TERM_PROGRAM`, which a remote shell profile or an ssh
`SendEnv`/`AcceptEnv` pair can set:

```sh
export TUI_TERM_PROGRAM=Apple_Terminal
```

Precedence is `TUI_TERM_PROGRAM` → `TERM_PROGRAM` → `LC_TERMINAL` →
`TERM`: the explicit answer first, the local answer next, the forwarded one
after that because it can arrive stale from a hop further back, and the
termtype last because it is the weakest — most terminals set a value that
names nothing, and a user can set it to anything. An `LC_TERMINAL` naming a
terminal with no model here falls through to `TERM` rather than blocking it:
it did not name *this* host, so it has nothing to outrank.

### A button's face at each control size — advance measured 2026-10-15

Since 2026-10-15 a bordered button's face follows `ControlSize` and
`ButtonBorderShape` (`ButtonFaceEdges.swift`): a rounded rectangle ends in the
one-eighth blocks `▕ … ▏` instead of the half-block caps, and a `.large` or
`.extraLarge` face is three rows, ringed above and below by half blocks met by
quadrant corners (`▗▄▄▖` / `▐ … ▌` / `▝▀▀▘` for the rounded rectangle; a
capsule's ring stops a cell short of each corner). The ring breathes with the
caps, so a glyph that advanced two cells would shear the row it is drawn on and
every run replayed over it.

| Glyph | Codepoint | Where | East Asian Width | Corpus row |
|---|---|---|---|---|
| `▕` | U+2595 | a rounded rectangle's leading edge | **Ambiguous** | `chrome_eighth_right` |
| `▏` | U+258F | a rounded rectangle's trailing edge | **Ambiguous** | `chrome_eighth_left` |
| `▄` | U+2584 | a three-row face's top edge | **Ambiguous** | `chrome_lower_half` |
| `▀` | U+2580 | a three-row face's bottom edge | **Ambiguous** | `chrome_upper_half` |
| `▗` `▖` | U+2597, U+2596 | a rounded rectangle's top corners | Neutral | `chrome_quadrant_lower_right`, `chrome_quadrant_lower_left` |
| `▝` `▘` | U+259D, U+2598 | its bottom corners | Neutral | `chrome_quadrant_upper_right`, `chrome_quadrant_upper_left` |

**Advance measured with `advance_probe.py`**, its battery extended by the eight
rows, run in each host from a `.command` file on the primary screen, on macOS
15.8.1: **one cell for all eight** on Apple Terminal 455.1, iTerm2 3.7.4
(ambiguous narrow, the default), Warp v0.2026.09.30.08.29 and tmux 3.7c (its own
grid). Ghostty was not reached that day: it asks once per new script path
before running one, and nobody was there to answer. On 2026-10-19
`advance_probe.py` read all eight at one cell there, on both screens, mode 2027
set (`ghostty-1.3.1-advance.json`, `ghostty-1.3.1-alternate.json`). The four
Ambiguous rows join the
borders' class (two cells where a host draws ambiguous characters wide, which
TUI answers with autowrap off); the quadrants are Neutral. Ink is
**UNMEASURED** on every host (`overhang_card.py` draws the rows; a person reads
it). As on 2026-10-13 the records were not rewritten, so the rows waited in
`ChromeGlyphAdvanceTests.awaitingAdvanceMeasurement` until the 2026-10-19 runs,
whose alternate-screen records read all eight at one cell on every host. They
still wait in the ledger's `awaitingLandingMeasurement`.

**Since 2026-10-24 a control's face follows the `ControlStyle`, filled by
default**, and no longer the border's `Appearance` (owner, 2026-10-23: "Make
'Block' the default *control* style again … but keep 'Rounded' as the default
border style"). `.controlStyle(.lines)` draws the lines faces described next
under any appearance of lines; `.automatic`, the default, draws filled faces
unless the appearance is `.braille` or `.blank`, looks of the whole interface
whose controls follow it. Plain glass is still rimmed in the border's family.
From 2026-10-15 to 2026-10-23 the face followed the `Appearance`, lines by
default — the owner's choice from a live prototype and two cards of candidate families
(`ButtonLab` on branch `proto/button-looks`; the cards are kept in the session
notes): under `.rounded` (the default), `.line`, `.heavy` and `.doubleLine` it is
drawn in lines with no field — `( OK )`, `│ OK │`, `[ OK ]` at radius zero, `(★)`
for a circle, in a box of the appearance's own glyphs on three rows; under
`.block` it is a filled face — `▐ OK ▌`, square face ends for a rectangle, and
on three rows the shape drawn in quadrants (`▗▟ … ▙▖` for a capsule, `▟ … ▙` for
a rounded rectangle, `▝▜ … ▛▘` and `▜ … ▛` below), the whole face breathing the
focus. The one-eighth edges `▕ ▏` above, and the half-block rings drawn earlier
that day, are drawn by no chrome now; the four three-quadrant glyphs `▙ ▛ ▜ ▟`
(U+2599, U+259B, U+259C, U+259F) are new to chrome (advance below).

**Since 2026-10-24 the one-row controls that are not buttons end as a button
does** (owner, FB3-OTHERCAPS (2), 2026-10-23): a segmented or palette picker and
a compact tab strip's chips take their caps from the button's cap table
(`ControlEnds`), at the control style, appearance and button border shape in
force — `▐ … ▌` round a filled face as before, `( … )`, `│ … │` or `[ … ]` in the
lines' ink under `.controlStyle(.lines)`, the shape's Braille ends under
`.braille`. A `ControlGroup` is drawn the same way, as one segmented face
(CONTROLGROUP-LOOK (a)): those caps at its two ends, `│` between its buttons,
which draw no caps of their own; and a list row's `.standard` badge sits in a
capsule of the family (B72-CAPSULE (c)): a field a cell wider each side when
filled, those caps on no field in lines. No glyph is new to chrome: each is a
button face's or a segmented picker's already. The
switch's knob is not a cap and keeps `▐▌` where controls are filled; its look
under Lines, chosen from a probe card on 2026-10-24, is below ("A switch under
Lines").

**Apple Terminal draws Block Elements short of the line** (seen by the owner in
Terminal.app 455.1 on macOS 15.8.1, 2026-10-15, against Ghostty 1.3 in the same
session): it takes them from the font rather than drawing them as shapes, so a
half block or quadrant stops short of the cell's top and bottom and a face built
of them over three rows came apart into bands. One-row caps (`▐ … ▌`) read as a
face there, and are kept. So on Apple Terminal — natively, and through tmux for a
client the process walk names as Terminal.app (`TerminalHost.blockElementsFillTheLine`,
`ClientCapabilities.blockElementsFillTheLine`) — a solid three-row face is drawn
in whole cells of the face, with no Block Elements glyph: a cell is the face
only where the shape covers all four of its quarters, so a rounded rectangle
loses its four corner cells and a capsule two cells at each end of its top and
bottom rows. (Until 2026-10-24 a cell was the face where the shape covered its
centre, which filled every corner and drew square, rounded and capsule faces as
the same block — owner #20, 2026-10-23.) A background colour
fills the whole cell there, which is what the survey's `█` note below
(*Appearance.block*) leans on too. Not yet measured as pixels (an
`overhang_card.py` page of the rows would show how far short). (A first card of
the families drew nothing in colour on Apple Terminal: it was spelt in 24-bit
SGR, which Terminal.app ignores; TUI spells 256 colours there.)
**A three-row circle** (owner, 2026-10-24: "'Circle' buttons under the
'Blocks' are giant plusses for the large and extra large size classes") is not
sampled as the other shapes are: three rows of an ellipse in quadrants were a
stair (`▗▟███▙▖` / `███+███` / `▝▜███▛▘`), and in whole cells a plus
(`··███··`). Its label's row is the one-row circle's, `▐ + ▌`, and the rows
above and below leave out the first and last cells and cut the next on the
diagonal — the corner triangles `◢ ◣` / `◥ ◤` where
`cornerTrianglesFillTheCell` says they reach the cell's edges (Ghostty, iTerm2:
*A double-width scrollbar's arrows* below), the half block nearer the label
(`▄`, `▀`) where only Block Elements do (Warp), and whole cells on Apple
Terminal, where the label row's `▐ ▌` are the one-row caps that already read as
a face there: nothing above or below them has to meet them. Not yet seen by
eye in each host beyond the probes' measures; the triangles' advance is the
scrollbar's, one cell.
The same flag keeps a gradient at one sample a cell there (decisions B95,
2026-10-24): where Block Elements fill the line, a ramp that changes down a
column draws each blank cell it fills as `▄` in its bottom half's colour over
its top half's — a gradient view, `.background(gradient)` behind the content's
bare cells, and a rectangle-family shape's whole cells — as a rasterized shape
already did everywhere; on Apple Terminal the halves would be stripes, so each
cell keeps the colour at its centre. `▄` is the corpus's `chrome_lower_half`.

**Braille borders and faces** (`.braille`, `.braille(thickness:)`; the same
evening): a box's border and a button's outline in Braille dots, the top and
bottom edges and the two walls each their own glyph (`⡏⠉⢹` / `⡇ ⢸` / `⣇⣀⣸`;
two dots thick `⣿⠛⣿` / `⣿ ⣿` / `⣿⣤⣿`), a button's shape drawn at dot
resolution. **Advance measured** with a DSR probe
(`dots_probe.py`, kept with the cards in the session notes) for the 36 Braille
glyphs the faces and borders draw and the four three-quadrant glyphs `▙ ▛ ▜ ▟`
of the solid faces: **one cell each** on Apple Terminal 455.1, iTerm2 3.7.5 and
Warp v0.2026.09.30.08.29, and on Ghostty 1.3.1 the next evening (2026-10-16;
its first run had not started). That probe's results are kept with the cards,
not under `Tools/TerminalProbes/data/`.
Braille Patterns are East Asian Neutral, so one cell is the rule; how each host
draws a dot's size and spacing — font glyphs or drawn shapes — is not yet
judged, and Apple Terminal's block-element shortfall may apply to them too.

Since 2026-10-19 the four three-quadrant glyphs and the thirteen glyphs a
Braille border draws at its four thicknesses are corpus rows
(`chrome_quadrant_not_*`, `chrome_braille_*`), so `advance_probe.py` and the
cards draw them. A Braille *face* rasterises its shape and can draw any
pattern of the block; the border's thirteen stand for the class. No
committed record has them yet, so they wait in
`ChromeGlyphAdvanceTests.awaitingAdvanceMeasurement` on every host and in the
ledger's `awaitingLandingMeasurement`. The `▕ ▏` rows stay, restated: no
chrome draws them now, but they are one of the bracket pairs a lines face
reads well with (`ButtonBorderShape.brackets(_:_:)`, FB14), and `▄ ▀` are
still drawn, as a shape's half-row edges.

**Advance measured** for the lines faces' glyphs, with a DSR probe run in each
host from a `.command` file, macOS 15.8.1: **one cell each** for `( ) [ ] < >`,
`╭ ╮ ╰ ╯`, `┌ ┐ └ ┘`, `─ │` and `⟨ ⟩` (U+27E8, U+27E9) on Apple Terminal 455.1,
Ghostty 1.3.1, iTerm2 3.7.4 and Warp v0.2026.09.30.08.29. The box glyphs are
East Asian Ambiguous, in the borders' class.

**Enclosed glyphs, for a circular face — advance measured the same way:** one
cell on all four hosts for `Ⓐ ⓐ ① ⑳ ⓪ ❶ ➊ ⓿ ⊕ ⊖ ⊗ ⊙ ⊛ ◉ ◯` and the SMP
`🅐` (U+1F150). The combining enclosing circle U+20DD after a base (`A⃝`,
`★⃝`, `+⃝`) advances **two** cells on Apple Terminal and one elsewhere. How
each looks is not yet judged.

**Bracket pairs for a compact face (E19) — paint measured 2026-10-17** with
`compact_glyph_card.py`: each pair around a label as a one-row button draws it,
plain, focused, padded and in a row of three, every row ending in a `|` that
lines up only when each glyph advances one cell and keeps to it. Read from
window captures on macOS 15.8.1:

| Pair | Codepoints | EAW | Apple Terminal 455.1 | iTerm2 3.7 | Ghostty 1.3.1 | Warp v0.2026.10.14 |
|---|---|---|---|---|---|---|
| `⦇⦈` | U+2987, U+2988 | N | good | good | good | good |
| `⦉⦊` | U+2989, U+298A | N | good | good | good | good |
| `❲❳` | U+2772, U+2773 | N | good | good | good | good |
| `❪❫` | U+276A, U+276B | N | good | good | good | good |
| `❨❩` | U+2768, U+2769 | N | good | good | good | good |
| `⟦⟧` | U+27E6, U+27E7 | Na | good | good | good | good |
| `⟨⟩` | U+27E8, U+27E9 | Na | good | good | good | good |
| `⦅⦆` | U+2985, U+2986 | Na | good | good | good | **overhangs into the label** |
| `⟮⟯` | U+27EE, U+27EF | N | good | off-centre | good | **off-centre** |
| `⸨⸩` | U+2E28, U+2E29 | N | good | good | good | **not drawn** (blank cells) |
| `〔〕` `「」` `『』` `［］` | U+3014… U+FF3B… | W / F | two cells | two cells | two cells | two cells |

So seven pairs are drawn as one clean cell on all four hosts: `⦇⦈ ⦉⦊ ❲❳ ❪❫
❨❩ ⟦⟧ ⟨⟩`. The wide and fullwidth pairs are out everywhere, as their East
Asian Width says. kitty: not measured (it opens no window on this VM). How
each *looks* at size, beyond fitting its cell, is the owner's call; the
captures are kept in the session notes (`plan/e19/`).

The owner's reading of which pairs are best laid out (2026-10-18) — taste at
size, not whether a glyph fits:

| Host | Best laid out |
|---|---|
| Ghostty | `()`, `⦇⦈`, `⦅⦆`, `❨❩`, `⟦⟧`, `⟨⟩` |
| iTerm2 | `❨❩`, `⟨⟩`, `⸨⸩` |
| Apple Terminal | `()`, `❪❫`, `❨❩`, `⟨⟩`, `⸨⸩` |
| Warp | `()`, `⦇⦈`, flattened parentheses (`❪❫`, by the card's name for them), `❨❩`, `⟦⟧`, `⟨⟩` |

Only `❨❩` and `⟨⟩` are on every list. Each pair is a
`ButtonBorderShape.brackets(_:_:)` an app can choose; the Example's Buttons
page offers them beside the shipped shapes.

**A double-width scrollbar's arrows (FB6) — paint measured 2026-10-17** with
`scrollbar_arrow_card.py`: whether a host draws the corner triangles `◢◣` /
`◥◤` (U+25E2, U+25E3, U+25E5, U+25E4) as ONE arrow across two cells, each half
filling its cell to the shared edge, between magenta flanks:

| Host | `◢◣` / `◥◤` | Double width (DECDWL) |
|---|---|---|
| Ghostty 1.3.1 | **one solid arrow**: drawn shapes, edge to edge, no seam | **ignored** |
| iTerm2 3.7 | **one solid arrow**: drawn shapes, edge to edge | honoured |
| Warp v0.2026.10.14 | font glyphs, smaller than the cell; the halves meet near the middle and read as one small arrow, not edge to edge | ignored |
| Apple Terminal 455.1 | font glyphs, well short of the cell edges; the pair reads as **two separate triangles** | honoured |

The double-width column was misread at first: Ghostty's capture shows the
card's labels in that block at single width, and the owner read Ghostty and
Warp as ignoring DECDWL (2026-10-18). Nothing in TUI sends it. The owner
also read the one-arrow rows as good in every host.

So the owner's FB6 rule (`◢◣`/`◥◤` by default, `▲▲`/`▼▼` where a host draws
the triangles badly) puts Apple Terminal and Warp on `▲▲`/`▼▼`, and Ghostty and
iTerm2 on the triangles. kitty: not measured (no window on this VM). Drawn
so since 2026-10-17: `TerminalHost.cornerTrianglesFillTheCell` natively, and
`ClientCapabilities.cornerTrianglesFillTheCell` through tmux (Terminal.app known
by its owning application, Warp by that or its XTVERSION name), into
`EnvironmentValues.cornerTrianglesFillTheCell`; an unmeasured host gets the
triangles.

### The search field's ✕ — chosen 2026-10-19, advance not yet measured

macOS's search field shows a filled ⓧ at its trailing end while it holds text,
and empties it on a click (`Tools/SwiftUIProbes/Search field clear button`).
TUI's `.searchable` field draws `✗` (U+2717, `Shortcut.cross`) there
instead. ⓧ (U+24E7) is East Asian **Ambiguous**, two cells in a terminal set
to CJK widths, and a filled circle with a cross needs a colour font's glyph.
`✗` is a Dingbat of **Neutral** width, one cell by the rule. It is corpus row
`chrome_cross` from 2026-10-19, so `advance_probe.py` and the overhang card
draw it. No committed record has it yet, so it waits in
`ChromeGlyphAdvanceTests.awaitingAdvanceMeasurement` on every host and in the
ledger's `awaitingLandingMeasurement`.

### A file panel's ↰ — chosen 2026-10-24, advance not yet measured

A macOS panel's toolbar goes to the enclosing folder with a button (and ⌘↑).
TUI's file panel draws that button as `↰` (U+21B0, UPWARDS ARROW WITH TIP
LEFTWARDS) before the path, where it had a `..` (`FilePanelPathBar`). `↰` is
an arrow of **Neutral** East Asian width, one cell by the rule, where the
plain arrows `↑ ← ↖` are **Ambiguous** and two cells in a terminal set to CJK
widths; it has no emoji presentation. It is corpus row
`chrome_enclosing_folder` from 2026-10-24, so `advance_probe.py` and the
overhang card draw it. No committed record has it yet, so it waits beside
`chrome_cross` in `ChromeGlyphAdvanceTests.awaitingAdvanceMeasurement` on
every host (GNOME Terminal's included) and in the ledger's
`awaitingLandingMeasurement`.

A file panel's row icons (2026-10-24) are emoji only where
`TerminalHost.supportsEmojiChrome` allows, as the search field's magnifier is:
📁 🚀 🔗 📕 🌄 🎵 🎬 📦 📜 📝 📄, each a single scalar of default emoji
presentation and East Asian Wide, so the corpus's `default_emoji` class
(two cells, no selector), and no new chrome rows. Elsewhere they are SF
Symbols (Plane-16 private use, two cells, Apple Terminal's under-advance
compensated as every symbol's is) where the font is installed, or none.

### A switch under Lines: ○ ● ⦗ ⦘ — chosen 2026-10-24, advance not yet measured

The owner's FB3-OTHERCAPS pick (2026-10-24): under `.controlStyle(.lines)` a
switch is a knob between the caps of the button border shape in force
(`ControlEnds.SwitchTrack`) — `(○ )` / `( ●)` for a capsule, `⦗● ⦘` /
`⦗ ●⦘` for a rounded rectangle, `│● │` / `│ ●│` for radius zero. `●`
(U+25CF) is the radio button's already (`chrome_radio_on`); three glyphs are
new to chrome, corpus rows from 2026-10-24 so `advance_probe.py` and the
overhang card draw them:

| Row | Glyph | Codepoint | EAW | Block |
|---|---|---|---|---|
| `chrome_switch_knob_off` | `○` WHITE CIRCLE | U+25CB | **Ambiguous** | Geometric Shapes, beside `● ◯ ◌` |
| `chrome_switch_cap_open` | `⦗` LEFT BLACK TORTOISE SHELL BRACKET | U+2997 | Neutral | Miscellaneous Mathematical Symbols-B |
| `chrome_switch_cap_close` | `⦘` RIGHT BLACK TORTOISE SHELL BRACKET | U+2998 | Neutral | Miscellaneous Mathematical Symbols-B |

`○` is Ambiguous, as `● ◯ ◌` are: two cells in a terminal set to CJK widths,
and one cell on all four hosts for its neighbours. **Risk to measure:** `⦗ ⦘`
are in the same block (U+2980–29FF) as `⦅ ⦆` (U+2985, U+2986), which
**overhang into the label in Warp** (the bracket-pair table above), and
whatever font a host falls back to for that block decides it; `⦇ ⦈` and `⦉ ⦊`
from it were clean everywhere. Read the overhang card in Warp first. No
committed record has the three yet, so they wait beside `chrome_cross` in
`ChromeGlyphAdvanceTests.awaitingAdvanceMeasurement` on every host (GNOME
Terminal's included) and in the ledger's `awaitingLandingMeasurement`.

### Underline shapes and colours (W11b) — read by the owner 2026-10-18

`line_style_card.py` (session notes, `plan/e19/`) prints "Sample text" under
each SGR line style, labelled with the sequence it sends; the owner read it in
four hosts. kitty: not read.

| Sent | Ghostty 1.3.1 | iTerm2 3.7 | Warp v0.2026.10.14 | Apple Terminal 455.1 |
|---|---|---|---|---|
| `4` single | yes | yes | yes | yes |
| `21` double (ECMA-48) | yes | yes | not drawn | **no underline** |
| `4:2` double | yes | yes | yes | **no underline, green background** |
| `4:3` curly | yes | yes | not drawn as asked | **a background colour** |
| `4:4` dotted | yes | yes | not drawn as asked | **a background colour** |
| `4:5` dashed | yes | yes | not drawn as asked | **a background colour** |
| `4;58;5;196` single, red line | yes | yes | not drawn as asked | underline, and the text **blinks** |
| `4;58:2::255:0:0` the same, colon form | yes | yes | not drawn as asked | the underline only |
| `4:4;58;5;46` dotted, green | yes | yes | **the background changes** | the colour as a **background** |
| `4:5;58;5;33` dashed, blue | yes | yes | **the foreground changes** | the colour as a **background** |
| `9` strikethrough | yes | yes | yes | **not drawn** |
| `9;58;5;196` strikethrough + 58 | struck in the text's colour | **struck in red** | — | struck nowhere; the text **blinks** |

Each misreading fits one model, though none was confirmed beyond the reading.
Apple Terminal drops the colon and reads `4:2` to `4:5` as the backgrounds 42 to
45. Both Warp and Apple Terminal read `58`'s semicolon arguments as codes of
their own: 5 as blink, 46 and 33 as colours. The colon form of 58 is one
parameter to both, and each ignores it.

So TUI (`TerminalHost.lineStyles`, since 2026-10-18):
- spells an underline's colour only in the colon form, `58:5:n` or
  `58:2::r:g:b`, never `58;…` (`SGRState`, `ANSIRenderer`), and spells a
  double line `4:2`, never `21`, which several terminals read as bold-off;
- sends iTerm2 every shape and colour, and colours its strikethrough with 58;
- sends Ghostty every shape and colour, and strikes through in the text's colour;
- sends Warp `4:2` for a double line, the plain `4` for every other shape, and
  no colour;
- sends Apple Terminal the plain `4` for every shape, and no colour;
- under tmux, sends every shape and colour: tmux re-spells them for each
  client from that client's own terminfo (`Smulx`, `Setulc`) and falls back to
  a plain line, so a client never sees what it cannot draw;
- sends a host it has not measured the plain line, as Apple Terminal gets: a
  shape such a host misreads can come out as a background or a blink, and the
  owner would rather have a plain line than that.

### Ghostty's model is conditional on mode 2027 — measured 2026-08-26

Every Ghostty number in this document was measured with DEC mode 2027
(grapheme clustering) **set**, which is Ghostty's default. Nothing checked
that, and the mode is not a constant.

Resetting it moves six of eleven probed classes:

| cluster | 2027 set | 2027 reset |
|---|---|---|
| 🖥️ VS-16 pictograph | 2 | **1** |
| ⬛︎ VS-15 chrome | 1 | **2** |
| 🇺🇸 flag pair | 2 | **4** |
| 👍🏽 skin tone | 2 | **4** |
| 👩‍🚀 ZWJ | 2 | **4** |
| 1️⃣ keycap | 2 | **1** |
| 🖥 bare pictograph · SF Symbol · 🇦 lone RI · 中 · 👍 | unchanged | unchanged |

In the reset state TUI's Ghostty compensation is wrong **in both
directions**: it emits no `CUF` for a VS-16 cluster that now under-advances,
and it emits one for a VS-15 glyph that no longer does. Skin tones, which
Ghostty is the only measured host not to need stripped, over-advance to 4 and
strand two cells.

**And the mode outlives the process.** Measured by resetting it in one program
and reading it back from a separate one launched afterwards: `DECRQM` answered
`ESC[?2027;2$y` and the whole reset-column behaviour was still in force. So
any program that resets mode 2027 and exits without restoring it leaves every
later Ghostty session in a state this document mis-describes — this is not a
hypothetical about user configuration, it is two escape sequences.

**What TUI does.** After identification, and only when the host is Ghostty,
it asks `DECRQM` and — if the answer is "supported, and off" — sets the mode
and restores it on exit. Silence, "not recognised" (`0`) and "permanently
reset" (`4`) all leave the terminal alone, per the governing rule.

The gating is not incidental. `DECRQM` is `CSI ? Ps $ p`: a private-parameter
marker *and* an intermediate byte, which is exactly the shape Apple Terminal
prints instead of consuming (see the CSI rule above). Asking blind would put a
stray `p` on the user's shell. `Tools/Smoke/mode_pin_smoke.py` pins both
halves — asked only of Ghostty, set only when off, reset only if set — and
both were mutation-checked: removing the host gate makes the unidentified case
fail, and pinning unconditionally makes the three already-fine cases fail.

### Asking the terminal — Device Attributes (measured 2026-08-26 and 2026-10-19)

Device Attributes are answered by terminals that answer no XTVERSION, and
cross an ssh hop like any other escape. First measured with
`identity_probe.py` through ssh (Apple Terminal 455.1 / macOS 15.7), with
Ghostty's and Warp's DA strings read out of their shipped binaries and
iTerm2's DA2 format string (`ESC[>%d;%d;0c`) likewise.

**Every host asked directly, 2026-10-19:** `identity_probe.py` run inside
each one on this machine, primary screen, macOS 15.8.1. The records are
`Tools/TerminalProbes/data/apple-terminal-455.1-identity.json`,
`ghostty-1.3.1-identity.json`,
`warpterminal-v0.2026.09.30.08.29.stable_01-identity.json` and
`iterm2-3.7.6-identity.json`, and the table is theirs. Where it differs from
the table this one replaced: Ghostty's DA1 lists `52`, Warp answers DA2, and
iTerm2's DA1 begins `64`, not `62`.

| Query | Apple Terminal 455.1 | Ghostty 1.3.1 | Warp v0.2026.09.30.08.29 | iTerm2 3.7.6 | GNOME Terminal 3.56.2 (VTE 0.80.1) |
|---|---|---|---|---|---|
| XTVERSION `ESC[>0q` | *silent* | `ghostty 1.3.1` | `Warp(v0.2026.09.30.08.29.stable_01)` | `iTerm2 3.7.6` | `VTE(8001)` |
| DA1 `ESC[c` | `ESC[?1;2c` | `ESC[?62;22;52c` | `ESC[?62c` | `ESC[?64;1;2;4;6;17;18;21;22;52c` | `ESC[?61;1;21;22;28c` |
| DA2 `ESC[>c` | `ESC[>1;95;0c` | `ESC[>1;10;0c` | `ESC[>0;95;0c` | `ESC[>64;2500;0c` | `ESC[>61;8001;1c` |
| DA3 `ESC[=c` | `ESC[?1;2c` (!) | *silent* | *silent* | a DCS report, `6954726D` (`iTrm` in hex) | a DCS report, `7E565445` (`~VTE` in hex) |
| XTGETTCAP `TN` | *silent* | `xterm-ghostty` (hex-encoded) | *silent* | `xterm-256color` (hex-encoded) | *silent* |
| `CSI 5 n` | `CSI 0 n` | `CSI 0 n` | `CSI 0 n` | `CSI 0 n` | `CSI 0 n` |

Apple Terminal answers DA3 with a **DA1 reply** — it ignores the `=` and
treats `ESC[=c` as `ESC[c`. Noted as a curiosity; nothing depends on it.

**iTerm2 lists `52` in DA1 whether its clipboard setting is on or off.**
iTerm2 3.7.6 answered the same `ESC[?64;1;2;4;6;17;18;21;22;52c` with
"Applications in terminal may access clipboard" off (its default) and, the
same morning, on (2026-10-19). Off, `clipboard_probe.py`'s three spellings of
an OSC 52 write all went nowhere; on, all three arrived (see "OSC 52
clipboard writes"). So DA1's `52` does not follow the setting, and cannot
tell an application whether a write will land.

⚠️ **Do not send DCS queries at startup.** XTGETTCAP (`ESC P + q … ESC \`)
is not safe: Apple Terminal does not parse DCS and *prints the payload* —
measured, it left a literal `+q544e` on the screen. Every query TUI sends
is a CSI sequence, and every one it sends today is consumed correctly even by
a terminal implementing none of them — but **not because CSI parsing is
generic**, which was the reason recorded here until 2026-08-26 and is false.

**Measured 2026-08-26, Terminal.app 455.1.** Sending `CSI ? 9999 <byte> p`
for each of the sixteen ECMA-48 intermediate bytes `0x20…0x2F`, and reading
the cursor column before and after to see whether the parser emitted text:

| shape | Terminal.app | iTerm2 | Ghostty | Warp |
|---|---|---|---|---|
| all 16 intermediates, with `?` | **leaks the final byte** | clean | clean | clean |
| any intermediate, no `?` | clean | clean | clean | clean |
| `?`, no intermediate | clean | clean | clean | clean |
| neither | clean | clean | clean | clean |

So the rule is narrower and sharper than "CSI is safe", and narrower than the
"any intermediate byte is unsafe" version reported elsewhere:

> Terminal.app leaks a CSI's final byte **if and only if the sequence carries
> both a `?` private-parameter marker and an intermediate byte.** Either one
> alone is consumed correctly.

Verified against all four combinations with two different intermediates
(`SP`, `$`) and two different final bytes (`p`, `z`) — eight sequences, and
the `?`-plus-intermediate quadrant is exactly the leaking one.

What follows for TUI:

- The four queries it sends — `CSI c`, `CSI > c`, `CSI > 0 q` and the
  status fence `CSI 5 n` — have no `?` and no intermediate. The first three
  were re-confirmed clean on Terminal.app on 2026-08-26, together with the
  cursor report `CSI 6 n` that fenced the exchange until 2026-10-05 (see the
  fence paragraph below); `CSI 5 n` was measured clean there, answered with
  nothing printed, by the colour exchange ("Asking the terminal for its
  colours"). `TerminalIdentityQueryTests` pins the shape so a future addition
  cannot quietly break it.
- **`CSI ? Ps $ p` — DECRQM in its DEC-private form — is exactly the unsafe
  shape**, and it is how modes 2026 (synchronised output) and 2027 (grapheme
  clustering) are negotiated. Sending one blind puts a `p` on the user's
  screen; measured here, twice, for both modes.
- The ANSI form `CSI Ps $ p` (no `?`) is clean, so ANSI-mode DECRQM is
  available on Terminal.app even though DEC-private DECRQM is not.
- Apple Terminal answers no DECRQM at all — both mode queries were silent —
  so there is nothing to gain by sending one there in any case.

**The fingerprint TUI ships** (`TerminalHost.nameFromDeviceAttributes`)
names Apple Terminal, and nothing else, by requiring all three of:

- **XTVERSION silence** — excludes the three hosts above, and kitty,
  WezTerm, foot and contour besides.
- **DA1 exactly `ESC[?1;2c`** — "VT100 with the Advanced Video Option", a
  1978 feature set. Modern emulators report VT220 or later (`?62`, `?63`,
  `?64`) because applications gate features on it, so this clause does most
  of the work.
- **DA2 matching `ESC[>1;…;0c`** — excludes the multiplexers, which are the
  real collision risk for the DA1 clause: GNU screen also reports VT100+AVO
  but identifies as terminal type 83 (`'S'`), and xterm as 41. tmux never
  reaches here (`$TMUX` answers first), but screen is not detected at all,
  and compensating inside a multiplexer would corrupt its grid.

The firmware field is deliberately not pinned to the measured `95`: it is a
version number by definition, and matching it exactly would mean a macOS
update silently switching the compensation back off.

The exchange is one write and one round trip, sent only when the environment
named no host, and fenced with a DSR request so a query nobody implements
costs nothing. `Tools/Smoke/identity_smoke.py` runs a real binary under a PTY
impersonating each terminal and asserts the compensation appears for Apple
Terminal and for nobody else — the wiring guard, since `TerminalHost`'s
detectors are `static let` and freeze on first read, so the query must run
before the render loop is built.

**The fence is the status report, `CSI 5 n` (reply `CSI 0 n`), not the
cursor report — since 2026-10-05, for every startup exchange.** The identity,
mode (DECRQM) and graphics exchanges were fenced by `CSI 6 n` until then, and
its reply, `CSI row;column R`, is the shape xterm gives a modified F3:
Shift-F3 is `CSI 1;2 R`, Ctrl-F3 `CSI 1;5 R`. A modified F3 pressed during the
≤0.5 s exchange therefore ended it early. For identity that left the terminal
unidentified, and so uncompensated, and the key was lost. No key sends
`CSI 0 n`, so a key now goes back to the input parser like any other keystroke
typed during the exchange. Every measured host answers `CSI 5 n`, screen and
Warp included (the colour exchange, which always used it, measured it; see
"Asking the terminal for its colours"). Found by reading Ghostty's VT
reference (`Documentation/Terminals/Ghostty VT reference adoption study.md`, K4). `identity_smoke.py`'s
`apple-key` case answers DA1 with a Shift-F3 behind it, and still expects
Apple Terminal identified. **In order, measured 2026-10-05** with
`identity_probe.py`, which now sends `CSI 5 n` alone and behind an XTVERSION:
Apple Terminal 455.1, Warp v0.2026.09.16, tmux 3.7c and GNU screen 4.00.03
each answer `CSI 0 n`, and where XTVERSION is answered (Warp, tmux) its reply
comes first. iTerm2, Ghostty and kitty were not reached (their windows did
not run the probe while the screen was locked). **iTerm2 and Ghostty measured
2026-10-19** with the same probe (the records above): iTerm2 3.7.6 and Ghostty
1.3.1 each answered XTVERSION, then `CSI 0 n`, in that order, and so did Warp
v0.2026.09.30 again; Apple Terminal 455.1 answered `CSI 0 n` alone, as it is
silent to XTVERSION. kitty is still owed.

One cost of a shared fence: a reply that comes in after its own exchange gave
up (a link slower than the half-second deadline) can end the NEXT exchange's
read early. A late cursor report could already do that between the three
exchanges that used it. A link that slow loses its answers either way.

---

## Apple Terminal.app

> **CORRECTED 2026-08-27.** This host reports one thing and paints another, and
> the tables below were built from the report. Measured with `landing_probe.py`
> on 455.1 / macOS 15.7.9, alternate screen:
>
> | cluster | claim | DSR advance | reserve | **paints next at** |
> |---|---|---|---|---|
> | 🤙🏽 👍🏼 ✊🏻 | 2 | 4 | 4 | **2** |
> | ☝🏻 ✌🏼 ✍🏽 ⛹🏾 | 2 | 3 | 3 | **1** |
> | 👩‍🚀 🏴‍☠️ 🧑‍🌾 | 2 | 5 | 5 | **2** |
> | 👨‍👩‍👧‍👦 | 2 | 11 | 11 | **2** |
> | ❤️‍🔥 🏳️‍🌈 ⛓️‍💥 | 2 | 4 | 4 | **1** |
> | 🇺🇸 🇦🇺 1️⃣ #️⃣ | 2 | 2 | 2 | **1** |
>
> One rule predicts every case: **two cells if the cluster's base has emoji
> presentation of its own, one if it does not** — which is why 🏴‍☠️ and 🏳️‍🌈
> differ despite looking like the same kind of thing. Flag pairs and keycaps
> land at 1 regardless.
>
> **FINAL 2026-08-27 — the treatment cards.** The table above is the raw host
> behaviour; the shipped treatments were settled by four "treatment cards"
> (expect/actual row pairs on a blue background, read against a ruler in the
> live terminal, DSR recording the cursor at every atom), which added two
> facts the probes above could not see:
>
> - **Any backward cursor motion over a composed cluster re-renders it as its
>   bare first segment.** A `CUB` pull-back aligns the row and silently strips
>   the tone (or the family, or the tag flag) ON SCREEN — the scalars survive
>   only in the store. `DCH` re-renders the same way.
> - **Stored width is what everything later on the row paints against.** A
>   cluster stored wider than it paints (flags: one surplus column; composed
>   ZWJ under any cursor repair: up to nine) displaces sequential AND
>   absolutely-addressed followers left by the difference. No cursor move
>   edits the store.
>
> The shipped emissions, all card-verified for follower alignment, absolute
> moves, backgrounds, and a full-width row ending in the cluster (no wrap):
>
> | class | claim | emission | on screen |
> |---|---|---|---|
> | tone, emoji-presentation base (🤙🏽 ✊🏿 👍🏽) | 5 | base + **ZWNJ** + modifier, no moves | base, one blank cell, swatch — tone kept |
> | tone, text-presentation base (☝🏻 ✍🏿 ⛹🏾) | 5 | `ECH(5)` + **VS-16-promoted** base+ZWNJ+modifier + `CUF(1)` | emoji base and swatch ADJACENT, one trailing blank (painted by the ECH) — tone kept (2026-08-28; superseded the `CUB(int−2)` pull-back, which re-rendered the bare NARROW glyph beside a blank cell) |
> | ZWJ sequence (👨‍👩‍👧‍👦 ❤️‍🔥 👩🏽‍🚀) | Σ segments | **decomposed** — joiners removed, each segment its own class | component glyphs |
> | flag pair (🇺🇸) | 2 | the **country code** (`US`), since 2026-10-25 | two letters; before it, the keycap row's surgery, which 455.1 now draws as a boxed letter |
> | keycap (1️⃣) | 2 | cluster + `CUB(1)` `DCH(1)` `CUF(1)` | composed (2026-08-27); surplus stored column deleted |
> | BARE keycap (1⃣, no VS-16) | 1 | cluster + `CUB(1)` | advance 2 (DSR record); it used to mis-enter the FE0F surgery on a fall-through model value of 1 and end one column past the claim. Paint/store unmeasured — pixel card queued (2026-08-28) |
> | tag flag (🏴󠁧󠁢󠁳󠁣󠁴󠁿) | 2 | cluster + `CUB(tags)` | aligned; bare 🏴 |
> | VS-16 / bare pictograph / lone RI / PUA | 2 | `ECH(2)` + glyph + `CUF(1)` | composed |
>
> ZWNJ is the ONE separator that stops re-joining: save/restore-cursor, an
> SGR, an 80 ms flush gap and absolute re-positioning all left base and
> modifier adjacent in the store and the terminal composed them again. The
> ZWNJ costs its own internal column (🤙+ZWNJ+🏽 advances 5), hence the claim
> of base + 3. The BARE rewrite fails on text-presentation bases (☝+ZWNJ+🏻
> misaligns), so those first shipped with the pull-back — until 2026-08-28,
> when the pull-back's own cost surfaced (bare narrow glyph, blank cell, tone
> lost) and the VS-16-promoted rewrite measured clean: promote the base to its
> emoji-presentation form, and the cluster becomes an ordinary under-advancer
> (internal 1+1+2 against a claim of 2+1+2) that the standard `ECH`+`CUF` arm
> already handles (point-up cards 1–2).
>
> **Where the ZWNJ's column lands differs by base — measured, both cards
> user-read.** After an emoji-presentation base (🤙‌🏽) the ZWNJ paints its
> own blank column MID-pair: base, gap, swatch. After a VS-16-promoted
> text-presentation base (☝️‌🏻) it paints NOTHING — the pair renders
> adjacent and the spare column trails the swatch, covered by the emission's
> `ECH(5)`. A redundant VS-16 added to an emoji-presentation base does NOT
> buy the adjacent form: 🤙️‌🏽 renders identically to 🤙‌🏽, gap mid-pair,
> same net 5 (adjacency card, 2026-08-28).
>
> **The separator hunt (2026-08-28) — negative result, recorded so it stays
> settled.** Looking for a gap-free separator: U+200B ZWSP, U+2060 WORD
> JOINER, U+00AD SOFT HYPHEN and U+FEFF each cost an internal column exactly
> as ZWNJ does (net 5). U+034F COMBINING GRAPHEME JOINER composes straight
> through — the cluster renders as the merged toned glyph at internal 4 /
> paint 2, the raw cluster's displacement profile: its CHA-60 follower
> painted two cells left, and a full-width row budgeted at its measured
> advance ended two cells short of the edge with the background unpainted in
> both. Reversing the pair (modifier first, net 4, adjacent) is unsafe: a
> leading modifier sits beside whatever PRECEDES the cluster on the row, and
> this terminal composes tone pairs even across cursor moves. The ZWNJ's
> column is the price of separation; on promoted text-presentation bases it
> at least trails rather than splitting the pair. The `DCH` variants of the
> over-advancing classes all wrapped at the row edge and re-rendered bare, so
> DCH is confined to the two classes whose internal column already matches the
> claim.
>
> One candidate was rejected before it reached a card: **interleaving a
> cursor move between base and modifier** (base + `CUF(1)` + modifier —
> "candidate A" of the 2026-08-28 session). In Swift's own grapheme
> segmentation a Fitzpatrick modifier is an Extend scalar, so it FUSES with
> the escape's final byte: `…C` + 🏻 becomes one `Character`, and every
> Character-level escape scanner in the pipeline (`escapeSequenceEnd`, the
> advance oracle, the width scan) mis-parses the emission it itself
> produced — the same `m🏻` hazard the SGR-collapsing code documents. The
> contiguous-cluster emission (`ECH` + whole rewritten cluster + `CUF`) has
> no such seam, which is why it shipped.


**Tested:** `TERM_PROGRAM_VERSION` 455.1, macOS 15.7 (Sequoia), 2026-07-13.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` |
| `TERM_PROGRAM` | `Apple_Terminal` |
| `TERM_PROGRAM_VERSION` | `455.1` |
| `TERM_SESSION_ID` | per-window UUID |
| `COLORTERM` | **not set** (no truecolor advertisement) |

### Output behaviour

- **Colour:** no truecolor — 256-colour palette is the ceiling
  (`ColorDepth` quantises). **A `38;2;r;g;b` that reaches it anyway is not
  skipped but read as five ordinary SGR parameters** (observed 2026-09-05,
  macOS 15.7, via an adaptive image palette that derived RGB triples after
  the depth fit): 38 does little, the **2 is SGR 2 and dims the text** (measured
  2026-09-19; it persists through a colour set after it — see "Reverse
  video (SGR 7)" below, where this was first recorded as "38 and 2 do
  little", which understated it), then a channel value of 5 is *blink*,
  30–37 and 40–47 are the named foregrounds and backgrounds, 90–97 their
  bright twins — a picture came out as blinking primaries in horizontal
  streaks. Anything that changes a colour after `effective(for:)` has fitted
  it must fit it again (`ASCIIConverter.convert`, the adaptive derivation).
  Framework-chosen label colours are floored
  **through the cube**: `Color.ensuringRenderedContrast(atLeast:against:)`
  measures each candidate — and the face — after `downsampledToPalette256()`,
  so the ratio that is guaranteed is the one on screen. It has to be, because
  the cube moves the FACE as well as the label: Green's button face is its
  accent at 20% over black (`#003300`) and the nearest cube green is `#005f00`,
  **3.5× the luminance**, so a `.destructive` label cleared 3:1 where it was
  measured and sat at 2.61:1 where it was read. (Floored in truecolor instead,
  a colour sitting exactly on the floor came out anywhere between 1.4:1 and
  4.7:1 once mapped into the cube.)

  Two floors, because one is not enough here: `labelContrastFloor` (3:1) for a
  live label, `disabledLabelContrastFloor` (2.4:1) for a disabled one — WCAG
  exempts inactive components, and pinned to the same 3:1 six palettes drew
  both states in the *identical* cube entry. `LabelContrastTests` pins all
  three properties across the sixteen built-in palettes: readable, recessive,
  and tellable apart.

  A **surface** (a text field, a tab island) is a different question and takes a
  different measure: not "can this be read on that" but "are these two shades
  visibly different", which a contrast ratio cannot answer — it flattens at both
  ends of the range, scoring two plainly different near-blacks at 1.08 and two
  plainly different creams at 1.05. Surfaces use perceived lightness (CIE L\*,
  `Color.perceivedLightness`) and step the page's own colour until they are far
  enough off it. The step scales the page's channels rather than mixing toward
  black or white, because mixing desaturates: a phosphor palette's near-black
  page mixed 10% toward white is grey, and a green terminal grew grey text
  fields.

  **How far** depends on how big the surface is. A *plane* — a tab body, a
  header strip — is ΔL\* 5 (`Palette.planeSeparation`, behind
  `liftedBackground`), because a large area needs less of a difference to read
  as one. A *well* — the field behind editable text — is ΔL\* 10
  (`wellSeparation`, behind `fieldBackground`), because a small one has to
  announce an edge. One number for both made the choice between them: at a
  plane's step Novel's fields disappeared, and at a well's every tab body read
  as a panel.

  **How far is measured in the colours the terminal will actually paint.** On a
  truecolor terminal the raw step is the step. On a 256-colour one the walk has
  to continue until the 6×6×6 cube separates the two (at half the floor, since
  the cube's own snapping does some of the work), and in dark saturated hues,
  where the cube's rungs are 95 apart, that costs a much bigger jump. Demanding
  the cube's jump on *every* terminal made a field inside a dark tab body come
  out three times its intended step — a bright green block on a theme whose
  point is that it is nearly black. (`Palette.hoveredControlFace` deliberately
  goes the other way and compares through the cube everywhere: a hover's tint is
  small, and looking the same on every terminal is worth more than the fidelity.
  Surfaces cannot look the same on both anyway — the cube moves the page too.)

  **Which way is decided once, for the whole palette** (`surfacesRunLighter`):
  by the palette's stated `appHeaderBackground` where it has a visible opinion,
  else away from the text where the page has room for it, else toward the text.
  Every rung follows that one direction. Asking "away from the text?" afresh at
  each rung folds the ladder back on itself — a dark palette's tab body steps
  lighter (its page has no room to go darker), and a field inside that body,
  asking again from there, steps darker and lands back on the page colour, which
  is what it looked like: a hole punched through the tab, on ten of the sixteen
  built-in palettes. Where the chosen direction runs out (a 256-colour terminal
  brightening Red's field until the cube can tell it apart makes the light text
  on it unreadable first), the other direction is taken instead — but only if it
  lands somewhere still visibly not the page. Red on a 256-colour terminal is
  the one palette where nothing satisfies all three, and its field inside a tab
  body quantises onto the tab's own cube entry.

  The step is taken from whatever is actually **behind** the control, not always
  from the page: a `TextField` inside a `TabView`'s body asked for "a surface on
  the page" and got the tab's own colour, both being the same step from the same
  place. A container that paints a surface publishes it
  (`EnvironmentValues.surfaceBackground`); the field derives from that.
- **VS-16 pictographic emoji** (❤️ ✏️ ☎️ 🖥️ 🛡️ …): paints 2,
  **advances 1** ("Bug A" — see `Historical/Emoji rendering bugs in macOS
  Sequoia's Terminal.app (2026-07).md` for the original investigation).
  Compensated with `ECH(2)` + glyph + `CUF(1)` by
  `withTerminalAppCursorCompensation()` — the erase since 2026-08-23, when a
  coloured run showed the skipped cell keeps the default background with CUF
  alone. Exception: the East-Asian-Wide BMP bases 〰️ 〽️ ㊗️ ㊙️ advance
  their full 2.
- **Fitzpatrick skin tones:** the composed cluster paints one merged glyph in
  2 cells while **advancing the internal column 4** (emoji-presentation bases:
  👍🏽 ✊🏻) or **3** (text-presentation: ☝🏽) — "Bug B" — and any backward
  move to repair that re-renders it as the bare base. **Since 2026-08-27 an
  emoji-presentation base is rewritten as base + ZWNJ + modifier** (claim 5:
  base, the ZWNJ's own blank column, swatch) — the tone survives on screen,
  everything aligns, nothing wraps. **Since 2026-08-28 a text-presentation
  base (☝🏻 ✌🏼 ✍🏽 ⛹🏾) is promoted with VS-16 and rewritten the same
  way**, claim 5: the promoted base is a Bug-A under-advancer, so the walk
  wraps the rewritten cluster in the standard `ECH(5)`+`CUF(1)` — measured
  aligned, tone kept. (Its first shipped treatment, the `CUB` pull-back at
  the composed claim of 2, was user-caught re-rendering the bare NARROW
  glyph: one cell of ink, a blank cell beside it, tone lost.) The strip
  remains only for a caller that has not published the host's traits.
- **Flag pairs** (🇺🇸): paints 2, **advances 2** — and the row STORES one
  column more than it paints, displacing every later write on the row one cell
  left. Repaired with store surgery: `CUB(1)` `DCH(1)` `CUF(1)` (2026-08-27;
  the earlier `CUB(1)+CUF(1)` nudge measured misaligned on the cards). On
  455.1 the surgery leaves a boxed first letter (2026-10-25), so a flag is now
  sent as its country code (`US`) instead ("What Apple Terminal paints").
- **Lone regional indicator** (🇦): paints 2, **advances 1** →
  `ECH(2)`+glyph+`CUF(1)`, like every under-advancer here.
- **Keycaps** (1️⃣ #️⃣, with VS-16): advance 2 ✓ — and store one column
  wide, same surgery as flag pairs. The BARE form (1⃣, claimed 1 — the
  base's own width) also advances 2, an over-advance pulled back with
  `CUB(1)` since 2026-08-28 (it used to mis-enter the surgery on a
  fall-through model value; paint/store unmeasured, pixel card queued).
- **ZWJ sequences:** the internal column decomposes (👩‍🚀 **5**, ❤️‍🔥 **4**,
  👨‍👩‍👧‍👦 **11**) while the glyph composes into 2 — and every cursor-move
  repair either displaced the row's tail (stored width) or re-rendered the
  cluster bare. **Since 2026-08-27 the walk decomposes in software**: joiners
  removed, each segment emitted under its own class, claim = the sum
  (👨‍👩‍👧‍👦 = 8, ❤️‍🔥 = 4, 👩🏽‍🚀 = 7 as a separated 👩+ZWNJ+🏽 plus 🚀).
  Component glyphs on screen — the accepted cost. See *ZWJ: where DSR lies*
  below for the history.
- **SF Symbols (Plane-16 PUA, U+100000+):** paints 2, **advances 1** →
  `ECH(2)`+glyph+`CUF(1)`. BMP PUA (e.g. U+E0B0 powerline): advances 1,
  width 1 ✓.
- **Emoji-repertoire chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): renders as a
  single seamless 2-cell monochrome, SGR-tintable glyph — *preferred*
  here because adjacent FULL BLOCK `█` cells show visible seams
  (incomplete cell coverage) in this terminal. This is why
  `ToggleCharacterSet.automatic` = `.emoji` on this host.
- **Block Elements:** `██` can show a hairline seam between cells;
  half-block pairs like `▐▌` render contiguously (they form the
  TextField caps and the switch knob). Shades ░▒▓ render as fine stipple.
  The image pipeline's half-block mode uses ▀ (upper) rather than ▄
  specifically to avoid a banding artifact observed here.
  **`Appearance.block`** (added 2026-08-20) draws its edges as a run of
  `█`, and takes the mitigation `TrackConfiguration.block` already used:
  ``BorderStyle/paintsBackground`` makes the cell's background the glyph's
  own colour, so the pixels the glyph misses are the right colour and the
  seams have nothing to show through to. The title and the focus dot are
  painted on the band too — and floored against it rather than against the
  page, since that is what they are now read on.
- **Right-edge phantom cells:** rows whose compensation leaves
  advance≠paint at the right edge can leave unpainted phantom cells;
  `FrameDiffWriter.repaintRightEdge` runs a scoped second pass.
- **Bidi controls are painted, not consumed** (measured 2026-09-01): U+202D
  and U+202C come out as the missing-glyph box, one cell each, where the
  other three hosts swallow them at zero width. This is why TUI does not
  wrap right-to-left runs in an override — see
  [Right-to-left text](#right-to-left-text--measured-2026-09-01-in-part).
- **The framework's own chrome keeps its ink inside its cells** — card-read on
  455.1, 2026-09-04 (`overhang_card.py`): not one of the 29 `chrome_key` /
  `chrome_glyph` rows marks a flank, so nothing here takes the widened
  chrome-overhang claim Ghostty's `↵` and Warp's seven keyboard symbols do. A
  negative reading, recorded because a host-independent table would have put a
  stray blank cell after seven glyphs of every status bar drawn here.

### Input behaviour

- **Keys:** sends bare `ESC[A/B` for Up/Down — **all modifiers stripped**
  on the vertical arrows (Shift/Opt/Ctrl/Cmd); Left/Right keep their
  modifiers. Shift+Up/Down accelerators can never work here.
- **Function keys carry no modifier bits at all.** Rather than the
  `ESC[21;2~` (`;2` = Shift) form every other terminal uses, Terminal.app's
  shipped key map re-codes **Shift+F5…Shift+F12** as the *VT220 F13…F20*
  sequences — Shift+F10 arrives as `ESC[32~`, byte-identical to a real F18.
  See "Shifted function keys are re-coded" below.
- **Mouse:** SGR (1006) reporting works: click press/release, wheel
  64/65. **Shift+wheel is intercepted** for the terminal's own scrollback
  — apps never see it (the Mouse demo notes this; use a trackpad's
  horizontal scroll instead). Trackpad horizontal scroll reports the
  standard horizontal wheel buttons 66/67. Right-click is reported to
  apps.
- **Mouse modifiers (byte-captured 2026-07-14, one run per modifier):**
  - **⌘-click: stripped to a plain click.** Eight deliberate ⌘-click
    press/release pairs ALL arrived as bare button code 0, symmetric —
    the app cannot tell a ⌘-click from a plain click, so **⌘-click
    multi-select toggling cannot work here** (the plain click replaces
    the selection). The pointer mirror of the Up/Down key modifier
    stripping above; not an app bug.
  - **⌥-click: forwarded as +8 (meta), symmetric** — the bit is present
    on both the press (`M`) and the release (`m`), and identically
    whether the profile's keyboard **"Use Option as Meta key"** setting
    is off or on (captured under both). TUI maps +8 to
    `MouseEvent.meta`, so **⌥-click** toggles rows in a multi-selection
    here. Note this is the *opposite* forwarding choice from iTerm2,
    which delivers ⌘ as +8 and swallows ⌥ (see its Input section).
- **Dead keys (observed by the owner 2026-10-16, not yet probed):** with
  "Use Option as Meta key" off, ⌥E starts an accent and nothing reaches the
  app until the next key finishes it (`é`, one character). Meanwhile
  Terminal draws the pending `´` itself, **at its cursor, hidden or not,
  pushing the rest of that row one cell right** until the composition ends
  and the app's next frame repaints the row. An app cannot stop the push —
  the composition is the terminal's and is never reported — but it chooses
  where the cursor is. Since 2026-10-17 the run loop parks the hidden cursor
  on the focused text control's insertion point after every frame and
  animation tick (`RenderLoop+Cursor.swift`), so the `´` appears on the
  caret and pushes the text after it, as marked text does in a Mac text
  field; before, it appeared wherever the frame's last write ended. A frame
  that writes nothing moves nothing. Other hosts' dead-key and IME
  composition drawing is unmeasured; they would place it at the cursor too
  if they draw it in the grid at all.

---

## iTerm2

**Tested:** `TERM_PROGRAM_VERSION` 3.6.11, macOS 15.7, default profile,
2026-07-13.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` |
| `TERM_PROGRAM` | `iTerm.app` |
| `TERM_PROGRAM_VERSION` | `3.6.11` |
| `COLORTERM` | `truecolor` |
| `TERM_SESSION_ID` / `ITERM_SESSION_ID` | `wNtNpN:UUID` (both, same value) |
| `ITERM_PROFILE` | profile name |
| `LC_TERMINAL` / `LC_TERMINAL_VERSION` | `iTerm2` / version (propagates over ssh) |
| `COLORFGBG` | e.g. `0;15` |
| `TERMINFO_DIRS` | app bundle terminfo + system |

### Output behaviour

⚠️ Much of iTerm2's width handling is **configuration-dependent**
(Settings → Profiles → Text: Unicode version, ambiguous-width). All
values below are the DEFAULT profile; a profile on Unicode 8 widths would
measure differently — re-run `advance_probe.py` before trusting a
non-default setup.

- **Colour:** truecolor (24-bit) — gradients render smoothly.
- **Bold brightens a named colour** (`Use Bright Bold`, on by default), so
  `SGR 1` over `30`–`37` paints the bright twin. See "Bold is a COLOUR on some
  hosts"; it ruined every 16-colour image until 2026-09-01.
- **VS-16 pictographic emoji — SCREEN-MODE DEPENDENT:** on the primary
  screen paints 2 / advances 2; on the **alternate screen** (where TUI
  apps run) paints 2 / **advances 1** — the same under-advance as
  Terminal.app, with the same EAW exceptions (〰️ 〽️ advance 2).
  Compensated with ECH(2)+glyph+CUF(1) by `withITerm2CursorCompensation()`
  — the erase added 2026-08-28, when a coloured-run card showed the skipped
  cell keeps the default background here exactly as on Terminal.app. (The
  primary-screen alignment card renders correctly; the app misrendered
  until the model was rebuilt from alternate-screen measurements —
  user-reported, byte-capture confirmed identical output bytes, and an
  ad-hoc probe of the day — not kept in `Tools/TerminalProbes` — isolated
  the screen mode as the variable.)
- **Fitzpatrick skin tones — split by plane:**
  - SMP bases (👍🏽): render MERGED (one skin-toned glyph), advance 2 ✓.
  - BMP bases (✊🏻 ☝🏽): render **base + separate 2-cell colour swatch**,
    advancing 4 / 3 — same numbers as Terminal.app's Bug B but with the
    swatch visible. Since the detached-claim widening (`TerminalWidthTraits`,
    skinTone `.detachedOnBMPBases`) the layout claims the 4/3 cells the
    detached rendering actually occupies, so the modifiers pass through
    un-stripped and the swatch the user sees is iTerm2's own rendering.
    (The strip — generic-yellow fallback, `withSkinToneFallback()` — now
    fires only for a caller that has not published the host's traits.)
  - A tone cluster still carrying a redundant VS-16 (☝️🏽 🏋️🏽) renders in
    **3** cells on either plane — narrow base + swatch, NOT the promoted
    base's 4 — measured 2026-08-28 (☝️🏽 in every landing column; the
    siblings by DSR sweep). The old promoted claim of 4 left a one-cell
    hole; since 2026-08-28 the walk strips the redundant selector (the
    modifier alone forces emoji presentation, UTS #51) and the claim
    prices the normalized pair: aligned.
  - The **SMP text-presentation** pair (🏋🏽) breaks the by-plane rule from
    the other side: where BMP bases detach (✊🏻 4, ☝🏽 3), this one merges
    NARROW — advance **1** against the composed claim of 2 (DSR sweep
    2026-08-28; `.detachedOnBMPBases` deliberately does not widen SMP).
    Modelled at 1, so the ordinary ECH(2)+CUF(1) closes it — before the
    sweep the model fell through to 2 and each such pair sheared a cell.
- **Flag pairs:** advance 2 ✓. **Lone regional indicator: advance 2**
  (differs from Terminal.app's 1) — width claim 2 ✓, nothing needed.
- **Keycaps** (1️⃣ #️⃣ *️⃣, bare or with VS-16): paints 2, **advances 1**
  (both screen modes) → ECH(2)+CUF(1) via `withITerm2CursorCompensation()`.
- **SF Symbols (Plane-16 PUA):** paints 2 (monochrome, SGR-tintable),
  **advances 1** → ECH(2)+CUF(1). Same under-advance as Terminal.app, and
  the same unpainted second cell on a coloured run (measured 2026-08-28),
  which is what the ECH fills.
- **ZWJ sequences:** advance 2 ✓ and paint 2 ✓ — confirmed by the paint
  card, not only by DSR. EXCEPT VS-16-leading ones (❤️‍🔥 🏳️‍🌈) which
  advance 1 on the alternate screen — long documented as unhandled, now
  modelled (`iTerm2CursorAdvance` returns 1 for a VS-16-carrying leading
  segment) and closed by the ordinary ECH(2)+CUF(1) repair.
- **Emoji chrome with VS-15** (⬛︎ ⬜︎ + U+FE0E): monochrome, tintable,
  2 cells, no shear — on the `supportsEmojiChrome` allowlist, so
  `ToggleCharacterSet.automatic` = `.emoji` here too.
- **Block Elements:** gap-free full-cell coverage — `██` contiguous, no
  seams; shades ░▒▓ draw as a dotted crosshatch texture (font flavour,
  cosmetically different from Terminal.app's stipple). Half-block images
  (▀) and background-fill images render seamlessly. Because the crosshatch
  covers less of the cell than a solid `█`, a bar that mixes the two — a
  `█` fill against a `░` empty run — reads with the filled part visibly
  TALLER than the empty part here. So `TrackStyle.block` (and `.blockFine`)
  paint the empty run as a solid *background* instead of a `░` glyph,
  giving a uniform-height two-tone bar on every terminal.
- **The framework's own chrome keeps its ink inside its cells** — card-read on
  3.6.11, 2026-09-04 (`overhang_card.py`): none of the 29 chrome rows marks a
  flank, the same negative reading Apple Terminal gives and the reason the
  overhang claim is per host rather than the union of Ghostty's and Warp's.

#### iTerm2 3.7.6 re-measured — advance, 2026-10-19, and it moved

`advance_probe.py` on both screens of 3.7.6, default profile (no Unicode
version set in it), on 2026-10-19 (`data/iterm2-3.7.6-alternate.json`,
`iterm2-3.7.6-advance.json`). Against the 3.6.11 records the models above
were built from, **six skin-tone rows moved on the alternate screen**, all to
2: ✊🏻 4 → 2, ☝🏽 3 → 2, ✌️🏼 and ☝️🏽 and 🏋️🏽 3 → 2, and 🏋🏽 1 → 2. A BMP base
no longer advances base + swatch. On the primary screen the same rows moved,
and so did the keycaps (1 → 2) and the conjoining jamo (3 and 4 → 2, see
"Complex scripts"). Every other row the 3.6.11 records hold came back the same,
the VS-16 and keycap under-advances on the alternate screen included.

**Not acted on, and owed.** The traits still claim the detached widths
(`.detachedOnBMPBases`: ✊🏻 4, ☝🏽 3) and the model reports them, so on 3.7.6
a row carrying a BMP-base skin tone ends two cells (one for ☝🏽) short of where
the layout put its last cell, if the DSR is the whole story; and 🏋🏽 takes a
`CUF` it no longer needs. Whether 3.7.6 now MERGES these into two cells or
draws something else in them is the paint, which is unmeasured: the tone card
and `landing_probe.py` are the instruments, and the version — 3.6.11 and
3.7.4 detached, 3.7.6 does not — would make this the first host whose model
has to follow its version.

### Input behaviour

- **Mouse (byte-captured):** SGR click `0` press/`m` release; wheel
  64/65. macOS translates **Shift+wheel into horizontal wheel deltas**, so
  iTerm2 reports Shift+wheel as the standard horizontal buttons **66/67**
  (+4 Shift) — reaching apps, unlike Terminal.app. (TUI's decoder
  maps 66/67 to `.scrollLeft`/`.scrollRight`; a pre-2026-07 decoder
  collapsed both into `.scrollDown`, which made Shift+wheel always scroll
  right.)
- **Right-click:** by DEFAULT iTerm2 opens its own context menu and the
  app never sees the click; configurable in Settings → Pointer
  (user-reported). **⌘-click is reported to apps as an ⌥-click**
  (user-reported). There is no escape sequence or variable that exposes
  the pointer configuration, so TUI cannot detect the setting; the
  example's Mouse page shows a static note under iTerm2 instead. This is
  why TUI's `.contextMenu` accepts a **Ctrl-click** as a secondary
  trigger in addition to a right-click: where iTerm2 swallows the
  right-click for its own menu, Ctrl-click still reaches the app and
  opens the TUI context menu. (Right-click reaches apps directly in
  Apple Terminal, Ghostty and Warp — see those sections.)
- **Modifier-clicks (byte-captured 2026-07-14, one run per modifier):**
  - **⌘-click → +8 (meta), symmetric.** Six deliberate ⌘-clicks arrived
    as SGR button code **8** with the meta bit present on **both** the
    press (`M`) **and** the matching release (`m`) — every pair fully
    symmetric (`ESC[<8;x;yM` … `ESC[<8;x;ym`). The earlier
    **release-drops-meta hypothesis is refuted** for iTerm2 3.6.11:
    release-acting handlers (List/Table selection, tap gestures) see the
    decorated click intact. `MouseEventDispatcher.stampClickCount` still
    unions the press's modifier bits onto the matching release as
    defence-in-depth for unmeasured terminals; on iTerm2 it is a no-op.
    This is also the byte-level substance of the user-reported "⌘-click
    reads as ⌥-click": ⌘ is delivered as the protocol's meta (alt) bit,
    which apps decode as an option-click.
  - **⌥-click → nothing.** A dedicated ⌥-click run produced **no report
    at all** — the default pointer bindings consume ⌥-clicks (cursor
    placement / rectangular selection), so apps never see them.
  - Net: iTerm2 forwards **⌘** and swallows **⌥** — the *opposite* of
    Apple Terminal (which forwards ⌥ as +8 and strips ⌘; see its Input
    section). Both deliver the surviving key as the same +8 bit, so
    TUI's `ctrl || meta` multi-select toggle works on both — but any
    user-facing hint must name a different physical key per terminal:
    **⌘-click here, ⌥-click in Apple Terminal**.
  - **What a gesture's `modifiers(_:)` hears follows from this.** It reads the
    same bits: `.option` is the +8 bit, so an `.option`-gated gesture answers
    ⌘-click here and ⌥-click in Apple Terminal, and `.command` never arrives
    anywhere. Shift- and Ctrl-left-clicks have not been byte-captured on either
    terminal yet (wave 17g left that measurement owed).

  *Earlier general captures (2026-07-14, before the probe logged
  `TERM_PROGRAM`):* plain clicks are **symmetric** (press `M` and
  release `m` carry the same button code, all SGR — no X10 "any
  release" fallback seen); shift+horizontal wheel arrives as **70/71**
  (66/67 + shift), confirming the Shift-wheel decoding above; drags
  report `+32` motion codes with clean SGR releases.
- iTerm2 honours a large proprietary escape set (OSC 1337) — unused by
  TUI so far.
- **Cell aspect ratio (image distortion):** iTerm2's cell height:width
  ratio differs from Apple Terminal's (font + line-spacing dependent), so
  an `Image` sized for a fixed 2:1 assumption looked horizontally squished
  here (user-reported). **Measured** with `cell_aspect_probe.py`
  (2026-07-14, default fonts/profiles):

  | Terminal | ioctl `TIOCGWINSZ` px fields | CSI `14t`/`18t` | aspect (ioctl / CSI) |
  |---|---|---|---|
  | Apple_Terminal 455.1 | 215×54 ch, 1505×756 px → 7.00×14.00 px/cell | 1515×763 px → 7.05×14.13 | **2.000** / 2.005 |
  | iTerm.app 3.6.11 | 80×25 ch, 1120×850 px → 14.00×34.00 px/cell | 570×458 px → 7.12×18.32 | **2.429** / 2.571 |

  Both terminals DO populate the `ws_xpixel`/`ws_ypixel` fields (the
  historical-zero concern did not reproduce), so the render root's
  auto-detection is live on both. Apple Terminal's two reports agree
  (2.000 ≈ 2.005) and match the framework's 2.0 default exactly. iTerm2's
  two reports **disagree by ~6%** (ioctl 2.429 vs CSI 2.571): the CSI
  report is self-consistent in points, while the ioctl fields look like a
  differently-rounded (retina-scaled) cell metric — either confirms iTerm2
  is meaningfully taller than 2:1, and the ~6% residual between them is
  visually minor. **Defence:** `ASCIIConverter.targetSize` takes a
  `cellAspect` parameter (default `2.0` ≈ Apple Terminal), threaded from
  `environment.imageCellAspect`; the render root auto-detects via
  `Terminal.cellPixelAspect()` (ioctl-based → 2.43 on this iTerm2, within
  the 1.0…4.0 sanity band), and `.imageCellAspect(_:)` overrides
  explicitly. *Residual: if circles still look slightly tall on iTerm2,
  the CSI-derived 2.57 is the candidate correction — verify by eye with a
  known-square image before switching sources.* The ioctl is read every
  frame, and the aspect and the cell's pixel size are part of the render
  loop's environment snapshot (2026-09-26), so a report that moves between
  frames redraws memoized content rather than leaving it drawn for the old
  cell. *Not yet measured: which hosts re-report the pixel fields on a font
  change without a resize.*

---

## Ghostty

**Tested:** 1.3.1 (`TERM_PROGRAM_VERSION`), macOS 15.7, default config,
2026-07-14.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-ghostty` (ships its own terminfo; often overridden to `xterm-256color` for remote hosts, so **do not detect the host on `TERM`**) |
| `TERM_PROGRAM` | `ghostty` |
| `TERM_PROGRAM_VERSION` | `1.3.1` |
| `COLORTERM` | `truecolor` |
| `TERMINFO` | app bundle terminfo |
| `GHOSTTY_BIN_DIR` / `GHOSTTY_RESOURCES_DIR` / `GHOSTTY_SHELL_FEATURES` | set |
| `__CFBundleIdentifier` | `com.mitchellh.ghostty` |

**Colour depth is the one thing `TERM` does decide here** (2026-10-04).
OpenSSH forwards `TERM` and drops `COLORTERM`, so on the far side of a hop
Ghostty arrives as `TERM=xterm-ghostty` with no `COLORTERM`. That name contains
neither `direct` nor `256color`, so `ColorDepth.detect` used to fall through to
**16 colours**. It now treats `xterm-ghostty` as truecolour, and kitty's
`xterm-kitty`, `wezterm`, `alacritty` and `foot` with it — whole names, from
each terminal's own documentation (`ColorDepth.truecolorTerminalNames`). Where
something rewrote `TERM` to `xterm-256color` before the hop (Ghostty's opt-in
ssh integration does), the answer is 256 colours, which is what that `TERM`
says. By reading, not yet checked over a real hop: the check is `ssh localhost`
from Ghostty with `COLORTERM` unset, then Example's Theme page.

### Output behaviour

**Ghostty is the most Unicode-correct terminal measured.** Every class that
Terminal.app and iTerm2 get wrong — VS-16 pictographs, ZWJ sequences,
Fitzpatrick skin tones, keycaps, flags, lone regional indicators — advances
by exactly the 2 cells `terminalWidth` claims, on BOTH screen buffers
(primary and alternate agree on every row of the battery). Skin-toned emoji
render as one merged glyph (👍🏽 = 2 cells), so the iTerm2/Warp swatch strip
is deliberately NOT applied here — it would discard a correct rendering.

- **Colour:** truecolor.
- **Two under-advancers of its own** (on top of the classes every measured
  host under-advances — bare pictographs, and the chrome whose ink overhangs
  its cell (`↵`, below) — all repaired by the one walk,
  `withGhosttyCursorCompensation()`):
  - **VS-15 chrome glyphs** (⬛︎ ⬜︎ = emoji-presentation base + U+FE0E):
    paints 2, **advances 1**. Uncompensated this collides the following
    label with the glyph — observed on the Toggle demo as `■On` where
    `.unicode` correctly showed `■ On`. ECH(2)+CUF(1) fixes it (the erase
    measured harmless here — the ink already covers both cells), which is what
    earns Ghostty its place on the `supportsEmojiChrome` allowlist.
  - **SF Symbols (Plane-16 PUA):** unlike Terminal.app/iTerm2 (which paint
    2 and advance 1), Ghostty renders these grid-strictly at **1 cell** and
    advances 1. The claim of 2 is therefore an over-claim here;
    ECH(2)+CUF(1) keeps the row aligned at the cost of one blank cell after
    each symbol — the ECH added 2026-08-28, because that blank cell is one
    the glyph never paints, so with CUF alone it kept the terminal's
    default background on a coloured run (user-reported, card-measured;
    the only Ghostty class that showed the hole).
    *The claim stays 2 even though Ghostty draws 1: Apple Terminal and
    iTerm2 paint these glyphs 2 cells wide, and `TerminalWidthTraits` only
    widens claims for the classes where a 2-cell claim would force
    substitution — a Ghostty-only 1-cell claim would buy one blank cell at
    the price of a per-host layout difference.*
- **`☝🏽` / `🏋🏽`** (text-presentation base + skin tone, either plane)
  merge to ONE cell — the base is a 1-cell text glyph and Ghostty keeps it
  that way with the modifier folded in. Modelled since 2026-08-26 (BMP;
  the SMP flavour by the 2026-08-28 DSR sweep); ECH(2)+CUF(1) lands each
  on the 2-cell claim, tone kept.
- **`☝️🏽` / `🏋️🏽`** (the same pairs with a redundant VS-16) are the
  opposite: the selector DEFEATS the merge and Ghostty detaches promoted
  base + swatch across **4** cells (ledger + sweep, 2026-08-28) — the only
  over-advance measured on Ghostty, and one the ECH+CUF repair used to
  make a cell worse. Since 2026-08-28 the walk strips the redundant
  selector (the modifier alone forces emoji presentation, UTS #51), so
  Ghostty receives the merging pairs above and the class is closed.
- **Cell aspect ratio:** fills `ws_xpixel`/`ws_ypixel` AND answers CSI
  14t/18t, which agree within ~1.4% (ioctl **2.154**, CSI 2.125 — default
  font). Slightly taller than the 2.0 default; auto-detection handles it.
- **`↵` (U+21B5) paints wider than it advances — advance measured 2026-09-04,
  ink card-read the same day.** User-reported first: the status bar's
  `Shortcut.enter` swallows the space before the label beside it, so
  `↵ activate` reads as `↵activate`. **The advance is 1**, here and on all
  three other hosts, so nothing shifts — what Ghostty does it does to the INK
  alone. `overhang_card.py` confirmed it: `↵` marks the right-hand flank here,
  and it is the ONLY one of the 29 chrome rows that does. U+21B5 is East Asian
  Width *Neutral*, so no width table predicts this; it is a host or font
  rendering decision, and it does not disturb the grid.

  Shipped since that reading: Ghostty's traits carry
  `ChromeOverhang.returnArrow`, so `↵` claims two cells **on this host only**
  and the ordinary `ECH(2)` + glyph + `CUF(1)` gives its ink the neighbouring
  cell. Warp smears seven other glyphs and not this one, which is why the claim
  is per host — see "The ink half" above.

  Since 2026-10-05 the status bar's Return is `↩` (U+21A9), macOS's symbol,
  and `↵` is drawn only where an app writes it. **`↩`'s ink here is UNREAD**,
  and `returnArrow` does not cover it: a claim widened on no reading would put
  a blank cell after a glyph that may fit. Its corpus row, `key_return_hook`,
  is on `overhang_card.py` for that reading — see "Key symbols".

### Input behaviour

- **Mouse (byte-captured 2026-07-14):** textbook SGR (1006). Plain clicks
  are symmetric (`ESC[<0;13;6M` press / `ESC[<0;13;6m` release); wheel is
  64 (up) / 65 (down); **horizontal wheel reports 66/67**, which is
  exactly what TUI's decoder maps to `.scrollLeft`/`.scrollRight`. No
  quirk found — nothing to work around.
- *Not yet captured:* modifier-clicks (⌘/⌥). Ghostty is expected to
  forward more than the Apple terminals do (it has no ⌘-click binding of
  its own by default), but that is a hypothesis until byte-captured —
  run `mouse_probe.py` and ⌘-click, then ⌥-click, in separate runs. The
  key-encoding side (arrows + modifiers, Fn keys, Escape timing) is also
  uncaptured.

---

## Warp

**Tested:** `v0.2026.07.08.17.54.stable_02`, macOS 15.7, default config,
2026-07-14; **re-measured end to end on `v0.2026.08.26.17.59.stable_01`,
macOS 15.7.9, 2026-08-28** — both the advance battery and the landing/ink/
reserve record, with zero drift on every row of either (see the version-drift
note below). Numbers in this section are good for both builds unless a row
says otherwise. The exceptions are the **tmux** and **Device Attributes**
tables further down: those were measured with the July build attached and
have NOT been re-run, so they still name it.

### Environment

| Variable | Value |
|---|---|
| `TERM` | `xterm-256color` (**not** a Warp-specific value — detect on `TERM_PROGRAM`) |
| `TERM_PROGRAM` | `WarpTerminal` |
| `TERM_PROGRAM_VERSION` | `v0.2026.08.26.17.59.stable_01` (was `v0.2026.07.08.17.54.stable_02`; the format is stable, the value is not — never match on it) |
| `COLORTERM` | `truecolor` |
| `WARP_TERMINAL_SESSION_UUID` / `WARP_IS_LOCAL_SHELL_SESSION` / `WARP_HONOR_PS1` … | set |
| `__CFBundleIdentifier` | `dev.warp.Warp-Stable` |

### Output behaviour

Warp is the mirror image of Ghostty: it gets the *selector* classes right
and the *composed* classes wrong.

**Warp does NOT brighten bold** — measured on the card 2026-09-01, its bold
palette is identical to its plain one. What it does instead is
`enforce_minimum_contrast` = `only_named_colors` by default, which lightens a
named foreground it judges illegible; that banded every 16-colour image until
2026-09-01. See "A host may recolour a foreground it cannot read".

> **Version drift check (2026-08-28).** Warp self-updated to
> `v0.2026.08.26.17.59.stable_01`; the full advance battery re-run on that
> build reproduced every one of the 63 previously committed rows exactly —
> including all seven Unicode 16.0 emoji still at 1 — so everything below
> measured on v0.2026.07.08 holds unchanged (committed record:
> `data/warpterminal-v0.2026.08.26.17.59.stable_01-alternate.json`). The
> landing record was re-taken on the new build the same day and likewise
> drifted on nothing, so the July landing file — which no longer describes
> any installed build, and which carried the cursor artefact below — was
> replaced rather than kept.

- **Colour:** truecolor.
- **VS-16 pictographs** (❤️ ✏️ 🖥️) advance 2 ✓ — no Bug-A compensation
  (unlike Terminal.app and iTerm2).
- **VS-15 chrome** (⬛︎ ⬜︎) advances 2 ✓ and paints clean squares → Warp is
  on the `supportsEmojiChrome` allowlist with no help at all.
- **Fitzpatrick skin tones paint base + a separate swatch at 4 cells**
  (3 for BMP bases) against the old claim of 2 — the same shape as
  Terminal.app's Bug B and iTerm2's. **Observed** in the demo's "Unicode
  compatible" feature box: the skin-toned 👍🏽 sheared the box's right
  border two cells out of place. Since the detached-claim widening
  (`TerminalWidthTraits`, skinTone `.detached` — every base, unlike
  iTerm2's by-plane split) the layout claims the cells the detached
  rendering occupies, the modifiers pass through un-stripped, and the
  swatch the user sees is Warp's own. (The `withSkinToneFallback()` strip
  fires only for a caller that has not published the host's traits.) A
  redundant VS-16 on the base (☝️🏽, raw advance 4) is stripped by the walk
  since 2026-08-28 — the modifier alone forces emoji presentation — and
  the normalized pair renders in exactly the 3 cells the claim allocates.
- **Lone regional indicator** (🇦) advances 1 against a claim of 2 — same as
  Terminal.app; ECH(2)+CUF(1) via `withWarpCursorCompensation()`. The erase
  is measured (2026-08-28, Warp tone card): with CUF alone the second cell
  kept the default background under the right half of the glyph's ink — the
  iTerm2 SF Symbol shape — and both the ECH and styled-space variants filled
  it, glyph intact.
- **Unicode 16.0's seven emoji** (🪉 U+1FA89, 🪏 U+1FA8F, 🪾 U+1FABE,
  🫆 U+1FAC6, 🫜 U+1FADC, 🫟 U+1FADF, 🫩 U+1FAE9) advance 1 against the
  2-cell claim — **Warp's width table is Unicode 15.1**. User-reported on
  U+1FAE9 (every later character on the row shifted one left), then the
  whole 1FA70–1FAFF block DSR-swept on all four hosts
  (`recent_emoji_sweep.py`, 2026-08-28): exactly these seven diverge, on
  Warp alone — Apple Terminal, iTerm2 and Ghostty advance all 113
  emoji-presentation scalars in the block by 2, and Warp's own Unicode
  15.0 emoji (🪈 🫎 🩷) advance 2, so 15.1/16.0 is the exact boundary.
  Modelled in `warpCursorAdvance`; the standard ECH(2)+CUF(1) repair
  covers them. Re-run the sweep when Warp updates or a Unicode version
  ships.
- **BMP emoji-presentation clusters ink only ONE of the two cells they
  own** — ⌚ U+231A, ⌛ U+231B, ⏫ U+23EB, ⏬ U+23EC, ⏳ U+23F3 (but not
  ⏩ ⏪ ⏰, which ink both). **Nothing is emitted for these, and nothing
  should be:** Warp advances the full 2, the claim is 2 and the landing is
  2, so no branch of `withWarpCursorCompensation()` fires and every
  follower lands true. What the reader sees is Warp resolving these to a
  monochrome TEXT glyph — from a UI font rather than its colour-emoji font
  — and drawing that narrow glyph in the left half of the pair it correctly
  reserved. No escape sequence can influence a font-fallback choice, so
  there is no treatment to write; the blank right-hand cell is Warp's, not
  ours.

  Recorded because the symptom — low-fidelity glyph, apparent gap after it
  — is indistinguishable at a glance from the under-advances above, which
  we DO compensate and which do produce a blank cell. The two are told
  apart by the ledger, not by eye: an under-advance has `advance < claim`,
  this has `advance == claim == landing` with `ink` short. Warp alone —
  Apple Terminal, iTerm2 and Ghostty ink both cells for all eight (Apple
  inks 3 for ⏩ ⏪ ⏫ ⏬). Re-measured end to end on
  `v0.2026.08.26.17.59.stable_01` (landing record, `ink` column) once Screen
  Recording came back on 2026-08-28: all four facts for all 69 previously
  measured rows reproduced with **zero drift**, this ink split included.
- **Seven keyboard symbols paint two cells while advancing one** — `⎋` U+238B,
  `⏎` U+23CE, `⌫` U+232B, `⌦` U+2326, `␣` U+2423, `⌥` U+2325, `⌘` U+2318.
  Card-read on `v0.2026.09.02` (2026-09-04, `overhang_card.py`): each marks a
  flank, while the advance battery the same day put all 29 chrome rows at
  exactly 1 here. **`↵` U+21B5 is NOT among them** — the glyph the equivalent
  Ghostty reading is entirely about — so the two hosts' overhanging sets are
  disjoint and the claim had to follow the host. Warp's traits carry
  `ChromeOverhang.keyboardSymbols`, so these seven claim two cells on this host
  and take the ordinary `ECH(2)` + glyph + `CUF(1)`. See "The ink half" above
  for the table and the reasoning; the font was not captured with the reading.
- **OVER-advancers, unhandled** (no escape can pull a cursor back to a
  column the glyph has already painted over — the seven entries in
  `TerminalLedgerConformanceTests.knownAdvanceDivergences`, all Warp's):
  keycaps 1️⃣ #️⃣ *️⃣ advance **3**; 〰️ 〽️ ㊗️ ㊙️ (the EAW-base VS-16
  exceptions) advance **3**; the tag-sequence flag 🏴󠁧󠁢󠁳󠁣󠁴󠁿 composes into one
  glyph but advances and lands at **3**.

  **ZWJ sequences left this list on 2026-08-28 — the walk drops the joiners
  in software.** Warp does not compose ZWJ sequences: it draws the
  components with each kept joiner occupying a blank column between them
  (👩‍🚀 advances 5 raw = 2+1+2), which first became the
  `decomposedKeepingJoiners` claim (2026-08-26, rows align but the joiner
  columns read as gaps) and is now emitted with the joiners removed —
  claim and advance are the bare segment sums (👨‍👩‍👧‍👦 8, 👩🏽‍🚀 6,
  ❤️‍🔥 4, 🏳️‍🌈 4). Card-measured (Warp ZWJ + tone cards, user-read):
  every dropped form renders the same components adjacent, gap-free, with
  sequential and absolute followers landing true, and full decomposition
  was the user's preferred rendering. One anomaly on the first card — the
  dropped toned astronaut's CHA follower one cell left — did NOT reproduce
  on the isolation card (👩🏽 alone / +🚀 / +😀 / +ASCII all true); if it
  resurfaces, that card is the instrument.

  ⚠️ Terminal.app's ZWJ story is different: it COMPOSES the glyph and only
  its column accounting runs ahead, so its decomposition exists to keep the
  store honest — see *ZWJ: where DSR lies*. Keycaps and 〰️ remain
  Warp-specific and DO shear.
- ⚠️ **Warp disagrees with itself across screen buffers** — more than any
  other terminal measured. Primary advances VS-16 by 1, alternate by 2;
  keycaps 1 vs 3; ZWJ 4/3/6 vs 5/5/7. The models use the **alternate**
  screen, where TUI apps run. Probe with `PROBE_ALT=1`.
- **Cell aspect ratio:** fills `ws_xpixel`/`ws_ypixel` AND answers CSI
  14t/18t, agreeing within ~2% (ioctl **1.956**, CSI 2.000) — essentially
  the 2.0 default, so images need no correction here.

#### Warp v0.2026.09.30 re-measured — advance, 2026-10-19

`advance_probe.py` on both screens on 2026-10-19
(`data/warpterminal-v0.2026.09.30.08.29.stable_01-alternate.json` and
`-advance.json`). The primary screen reproduced v0.2026.09.02's record row for
row. **The alternate screen moved on ten rows** against v0.2026.08.26's: the
keycaps 1️⃣ #️⃣ *️⃣ 0️⃣ 3 → 2, 〰️ 〽️ 3 → 2, and the raw ZWJ sequences lost
their joiner column — 👩‍🚀 5 → 4, ❤️‍🔥 5 → 4, 👩🏽‍🚀 7 → 6. (The tenth is the
PUA row's rename.) By DSR, then, the keycaps and 〰️ 〽️ no longer
over-advance on the alternate screen (the battery carries neither ㊗️ ㊙️ nor
a tag-sequence flag), and the raw ZWJ advance is the dropped form's segment
sum. Neither changes what TUI emits: the keycaps and 〰️
were left alone at the claim of 2, which they now advance, and the walk drops
the joiners anyway. What is stale is the record behind
`TerminalLedgerConformanceTests.knownAdvanceDivergences` — the 08.26 landing
record — and `warpCursorAdvance`'s raw kept-joiner sum; a landing re-run on
this build would say whether the seven divergences are gone.

### Input behaviour

Mouse SGR (1006) reporting works; **not yet byte-captured** (clicks, wheel,
modifiers, key encodings all remain to be measured — do not assume they
match Ghostty's). Warp defaults to `default_session_mode = "agent"` in
`~/.warp/settings.toml`, and its own UI overlays (tab switcher, command
palette) sit above the app — neither affects the app's byte stream.

**Driving Warp non-interactively** (it has no `-e`): write a launch
configuration to `~/.warp/launch_configurations/NAME.yaml` with a
`commands: - exec: …` entry and open `warp://launch/NAME`. Ghostty by
contrast takes `open -na Ghostty.app --args -e <cmd>`.

---

## xterm.js — the browser (measured 2026-09-05)

**Tested:** xterm.js 6.0.0 in Chromium 148, via `Tools/Web/glyph-probe.html`,
which measures the same corpus the Python probes measure and writes the same
kind of record (`data/xtermjs-6.0.0-graphemes-advance.json`).

A browser terminal is measured differently, and the difference is worth
stating: there is no DSR-versus-paint gap to close, because the buffer *is* the
model. `cursorX` after a write is the advance, the cell a following character
occupies is the landing, and the two cannot disagree. What this record does NOT
carry is `ink` — how many cells the glyph is painted across — because that
would need pixels, and none were read.

### It is a configuration, not an emulator, that gets emoji wrong

xterm.js ships Unicode 6 width tables. Under them an emoji is one cell, so it
is drawn clipped and everything after it on the row sits one column left of
where the app put it — two emoji in a header, two columns of shift, and the
box's right border lands inside the box. That was the WebAssembly demo's first
appearance, and the fix is one script tag:
`@xterm/addon-unicode-graphemes`, with `terminal.unicode.activeVersion` set to
`15-graphemes`. It replaces the tables *and* clusters by grapheme, which is
what makes 🖥️ (pictograph + VS16) two cells rather than one plus a stray.

Measured against the framework's own widths (`data/tuikit-widths.json`), over
the 78 clusters the native probes covered:

| Host | advance agrees with TUI |
|---|---|
| Ghostty 1.3.1 | 63 / 78 |
| **xterm.js 6.0.0 + unicode-graphemes** | **61 / 78** |
| iTerm2 3.6.11 | 53 / 78 |
| Apple Terminal 455.1 | 41 / 78 (landing 51) |
| Warp 2026.08.26 | 35 / 78 |
| xterm.js 6.0.0, default tables | 33 / 78 |
| xterm.js 6.0.0 + unicode11 | 31 / 78 |

Two readings matter here. The first is that a correctly configured browser
terminal is not a poor relation: it sits second in a field of five, above two
shipping native terminals. The second is that `addon-unicode11` — the obvious
choice, and the one most projects load — is **worse than doing nothing**: it
widens the emoji but has no grapheme clustering, so every ZWJ sequence and
skin-tone modifier is counted as its parts (👩‍👩‍👧‍👦 advances 8) and the total
agreement drops from 33 to 31.

### Where it still disagrees, and with whom

Over the full 145-cluster corpus, 29 rows disagree with TUI. They are not
scattered:

| Class | Rows | What happens | Also disagrees |
|---|---|---|---|
| `recent_emoji` | 10 | one cell — the addon's tables are Unicode 15 and these are newer | Warp (7 of the same rows) |
| `spacing_vowel_sign`, `thai_lao` | 7 | one cell where TUI says two — a REGRESSION from the default tables, which say two | — |
| `pua16` (SF Symbols) | 3 | one cell; private-use codepoints carry no width | every native terminal measured |
| `bare_pictograph` | 3 | one cell, matching Ghostty's advance | Ghostty, iTerm2, Apple Terminal, Warp |
| `indic_conjunct` | 3 | three cells where TUI says two | — |
| `format_control`, `regional_indicator` | 3 | one cell where TUI says zero or two | — |

The SF Symbols row is the one to remember for the demo: the Example's symbol
page will shift, and no terminal can do better, because a private-use codepoint
has no width to look up.

### Capabilities — asked, not assumed

Every answer below came back from the terminal itself during the probe:

| Query | Answer |
|---|---|
| DA1 `CSI c` | `CSI ?1;2c` — identifies, so the framework's identity query completes |
| DA2 `CSI > c` | `CSI >0;276;0c` |
| XTVERSION `CSI > 0 q` | *nothing* — no name/version string |
| DSR `CSI 6 n` | `CSI 1;1R` — cursor reporting works, so the advance probes do |
| DECRQM `?1049` / `?2004` / `?1006` / `?1002` | `;2` (recognised, currently reset) |
| DECRQM `?2027` | **`;0` — not recognised.** No grapheme-clustering mode, so the framework keeps its own advance model |
| SGR 38;2 truecolor | the exact RGB written comes back on the cell |
| Alternate screen `?1049` | enters and leaves |
| OSC 8 hyperlink | the row holds the text and none of the sequence |
| SGR mouse `?1006` | a click sends `CSI <0;3;1M` / `CSI <0;3;1m` |

### Graphics — measured 2026-09-05, and the answer has three parts

**The released core has no graphics of any kind.** xterm.js 6.0.0 swallows a
Kitty transmission, a SIXEL and an iTerm2 inline image alike: no reply, and
nothing left in the cells. TUI's handshake therefore gets silence and falls
back to cells, which is what it is for.

**The released image addon does not do Kitty.** `@xterm/addon-image` 0.9.0
supports SIXEL and iTerm2's IIP — its own README says so, and the word "kitty"
does not appear in its source. TUI speaks neither: it emits the Kitty
protocol only, so the addon buys the framework nothing today.

**The beta does — partially, and not the part TUI needs.**
`@xterm/addon-image` 0.10.0-beta.301 (2026-08-30) adds `kittySupport`, and needs
`@xterm/xterm` 6.1.0-beta for it: the addon registers an APC handler, and
`registerApcHandler` does not exist in the 6.0.0 core (loading the beta addon on
the released core throws). With both betas, measured:

| What was sent | What happened |
|---|---|
| `a=t` transmit, `q=0` | `ESC_Gi=31;OK ESC\` — accepted and acknowledged |
| `a=p,U=1` virtual placement, `q=0` | `ESC_Gi=31;OK ESC\` — **acknowledged** |
| `a=q` query | `OK` |
| any of the above | `addon.storageUsage` rises — the image really is decoded and kept |
| U+10EEEE placeholder cells | left in the buffer **as text** |

So the beta acknowledges the protocol and decodes the pixels. Whether it
*places* them, this bench cannot say, and the first version of this section
claimed more than it had measured. On re-testing (2026-09-05, later the same
day) the addon drew **nothing at all** here — not a kitty placement, not a
cursor placement, not a SIXEL, not an iTerm2 inline image — with the DOM
renderer and again with `@xterm/addon-webgl` loaded, while `storageUsage` rose
every time, so every payload was decoded and stored. That is an instrument that
answers questions about parsing and cannot answer questions about drawing.

What can still be said with a source rather than a measurement: the addon's
README calls the kitty support WIP, and xtermjs/xterm.js#6132, *Kitty graphics:
Track placements independently from text cells*, was open at the time of
writing and describes exactly the placement bookkeeping a virtual placement
needs. TUI uses only virtual placements, because one that moves with the
text is no use to a full-screen layout (see `Terminal graphics protocols.md`
§4).

**The trap this sets.** An `OK` to the placement query is exactly what TUI's
handshake looks for, so a framework that trusted it would emit placeholder
cells into a terminal that draws none. Forced on with `TUI_GRAPHICS=1` and
both betas loaded, the Example's Colors page emitted 444 placeholder cells
across six gradient rows and drew **blank space** where the ramps belong —
which, given the paragraph above, says the page drew nothing rather than that
placements specifically are unimplemented. Left
to its own handshake the framework did not turn graphics on at all, which is
the conservative answer and the right one — but it is conservative by
accident here, not by design, and that is worth remembering if the beta's
behaviour changes.

Sixel and IIP are a different question, and an open one: the addon decodes both,
and TUI implements neither. Nothing here recommends adding them — it only
records that the browser could receive them.

### Why not something else

The browser-terminal field is smaller than it looks. Everything that ships a
terminal on a web page — VS Code, ttyd, wetty, Codespaces, Jupyter — is
xterm.js. `hterm` (Google's, inside libapps) is the only other complete VT
emulator for the DOM; it is `wcwidth`-based with no grapheme clustering, which
is the configuration measured at 33/78 above. The rest (jQuery Terminal,
Termino.js, the canvas toys) are consoles, not emulators: no alternate screen,
no SGR mouse, no DECRQM. There is no wasm port of a native terminal that
renders to the DOM.

So the answer to "is there something more capable" is that xterm.js configured
correctly *is* the capable one, and the emoji problem was a missing addon
rather than a missing emulator.

## tmux

**Status: MEASURED — tmux 3.7b (Homebrew, arm64), 2026-07-15.** DSR-probed
with `advance_probe.py` run *inside* a detached tmux session (no client
attached at all — the purest test of the compositor property below: tmux
answered every DSR from its own grid with nothing downstream to ask).

### Environment (measured, confirms the ≥3.2 expectation)

| Variable | Value inside a pane |
|---|---|
| `TERM_PROGRAM` | `tmux` — **overwritten**, does NOT pass the outer terminal's through |
| `TERM_PROGRAM_VERSION` | `3.7b` |
| `TERM` | `tmux-256color` |
| `COLORTERM` | `truecolor` |
| `TMUX` / `TMUX_PANE` | socket path / `%0` |

So under tmux the four native detectors all miss (`Apple_Terminal`,
`iTerm.app`, `ghostty`, `WarpTerminal`) — but tmux is NOT treated as an
unknown host. It is detected in its own right (`TerminalHost.isTmux`, from
`$TMUX`) and is a **first-class host with its own width model**, because tmux
is a **compositor**, not a passthrough: it parses TUI's output into its own
grid with its own width tables and re-renders. The outer terminal's advance
quirks apply to *tmux's* output, not TUI's, so tmux's model is the one
TUI must satisfy — and `FrameDiffWriter` checks `isTmux` FIRST, ahead of
every native host, so a native variable that survived into the pane cannot
select the wrong model (see `String.withTmuxCursorCompensation()`).

> **History.** Until 8c1e06d8 (2026-07-15) tmux WAS treated as unknown and got
> no compensation and no emoji chrome; the paragraphs below were once written
> to argue that was correct. It was not — tmux's grid diverges from TUI's
> width claims (measured, next), so leaving compensation off sheared exactly
> the glyphs a native host would have had fixed. This section now describes the
> shipped behaviour; the "live bug" is closed.

**Colour is fine:** tmux 3.7b preserves 24-bit SGR in its grid
(`ESC[38;2;255;100;0m` survives verbatim) and sets `COLORTERM=truecolor`, so
TUI's depth detection picks truecolor correctly. No `Tc`/`RGB`
`terminal-features` tweak needed at this version.

### Cursor advance — where tmux DISAGREES with TUI, and how it is handled

What matters under tmux is agreement between TUI's width tables and
*tmux's* wcwidth. Measured, with what the tmux path now does about each
divergence (`String.tmuxCursorAdvance` + `withTmuxCursorCompensation()` +
`withSkinToneFallback(scope:)` with the measured keep-set):

| Cluster | tmux 3.7b | TUI claims | Handled how |
|---|---|---|---|
| `U+100038` etc. (Plane-16 PUA, **SF Symbols**) | **1** | **2** (`String+TerminalWidth.swift`, the Plane-16 arm) | CUF: one `ESC[1C` after each, landing the cursor at the claimed column |
| `U+1F5A5`, `U+1F6E1`, `U+1F577`, `U+1F39E`, `U+1F3D9` (bare SMP pictographs) | **1** | **2** | CUF, same as above |
| `U+1F060` domino, `U+1F0A1` playing card | **1** | 2 | CUF, same as above |
| `U+270A U+1F3FB`, `U+1F919 U+1F3FD` (skin tone on a base tmux **detaches** — 64 of the 134 modifier bases, per codepoint) | **4** | 2 | swatch stripped (`.keepingTmuxMerged` strips exactly the detaching bases) → back to a 2-cell advance |
| `U+2B1B U+FE0E` (VS-15 chrome ⬛︎) | **2** | 2 | ✓ already agrees (both 2) — no action |
| `U+1F1E6` lone regional indicator | 1 | 1 | ✓ |
| `U+4E2D` CJK · `U+1F44D` emoji · ZWJ families · `U+1F1FA U+1F1F8` flag | 2 | 2 | ✓ |
| `U+1F44D U+1F3FD` (skin tone on a base tmux **merges** — the measured 70, `Character.tmuxMergedToneBases`) | 2 | 2 | ✓ — NOT stripped when every attached client renders kept tones |
| `U+0065 U+0301` NFD · `U+E0B0` powerline · `U+2588` block | 1 | 1 | ✓ |
| स्त्र ष्ट्र स्त्री (Devanagari conjuncts; tmux 3.7c, both screens, 2026-10-19) | **3 / 3 / 3** | 2 / 2 / 2 | **not handled** — tmux advances per code point, but its table gives a spacing vowel sign no cell; see "Complex scripts" |
| कि को कौ किं ரா កា (a consonant + a spacing vowel sign, `Mc`; tmux 3.7c, 2026-10-19) | **1** | 2 | **not handled**, as above |

**The defect this closed:** the main menu's "Supports SF Symbols" FeatureBox
renders **three** Plane-16 PUA glyphs. TUI reserves 2 cells each (6); tmux
advances 1 each (3). Before 8c1e06d8 nothing compensated, so — measured in
tmux's own grid at 100×60 — that line's right border landed at **cell 65**
while every other line of the box landed at **68**, exactly 3 cells short, one
per glyph, and the border was visibly broken. The tmux path now emits one CUF
per under-advancing cluster, landing the cursor at the claimed column, so the
border closes. Same fix for the bare SMP pictographs and the dominoes/cards.
Re-measuring this needs the SF Symbols font on the Mac that runs `Example`:
since 2026-10-11 the box asks `SFSymbol.isFontAvailable` before it looks a name
up, and without the font it shows its caveat alone, with no PUA glyph to
measure. The compensation's unit tests (`TmuxCompatibilityTests`, and
`FrameDiffWriterTests` for iTerm2's) write the codepoints themselves and need
no font.

The claim's comment ("SF Mono: 2 cells") is right about the *font* in a native
terminal and about the width TUI paints; tmux's wcwidth has never heard of
SF Symbols and advances 1, which is why the tmux path adds the CUF rather than
changing the claim. `withSkinToneFallback(scope: .keepingTmuxMerged)` is
deliberately narrower than the blanket strip: tmux joins 70 of the 134
modifier bases (👍🏽 👋🏽 🤦🏽 🧑🏽 …) into exactly the 2 cells claimed, and
stripping those would discard clusters it gets right. Which bases merge is
**per codepoint** — the full sweep (2026-08-28,
`advance_probe.py --modifier-bases`, headless tmux, record
`data/tmux-3.7b-tonebases.json`) retired two tidy wrong rules in a row: it is
not by base plane (🤙 and 🤚, SMP, detach at 4 while 🧑, also SMP, merges —
caught 2026-08-26 when the Fitzpatrick row rendered short under a policy that
kept every SMP base) and not by Unicode era (Unicode-6.0 🎅 detaches while
the Unicode-10.0 🧍…🧝 run merges). The measured set
(`Character.tmuxMergedToneBases`) is the rule, and
`TmuxCompatibilityTests` pins it against the record row for row.

### Pane geometry (why a "normal" terminal still hits small-size bugs)

tmux reaches tiny panes from an ordinary window in three keystrokes. Measured
from a 100×40 window, splitting horizontally:

| splits | resulting pane heights |
|---|---|
| 1 | 20, 19 |
| 2 | 10, 9 |
| **3** | **5, 4** |
| 4 | 2, 2 |

`resize-window -y 12` is honoured exactly. **A 4-row pane in a 100×40 window
is three keystrokes away** — which is how a user with a perfectly normal
terminal lands in the negative-content-height crash band (see
`contentAreaHeight()`; crash fixed in c02c3678, which renders header + status
bar with an empty content area at 4 rows instead of trapping). Verified: four
Example panes at heights 19/9/5/4, all `pane_dead=0`.

### Does the client terminal change tmux's behaviour? No. (measured)

The compositor property is now demonstrated, not assumed. `advance_probe.py`
was run **five ways** — with Apple Terminal, iTerm2, Ghostty and Warp attached,
and with no client attached at all:

> **All 58 clusters, all five runs: ZERO differences.**

tmux's grid does not depend on which terminal is attached, or on one being
attached at all. That is why there is **one** `tmuxCursorAdvance` model rather
than four, and why the outer terminal's quirks are irrelevant to our output.

### Identifying the client terminal (research)

It IS possible — tmux probes each client with XTVERSION and exposes the answer:

| Client | `#{client_termtype}` | `#{client_termname}` | `#{client_termfeatures}` |
|---|---|---|---|
| iTerm2 | `iTerm2 3.6.11` | `xterm-256color` | 256,bpaste,ccolour,clipboard,hyperlinks,cstyle,extkeys,focus,margins,mouse,osc7,progressbar,RGB,sixel,strikethrough,sync,title,usstyle |
| Ghostty | `ghostty 1.3.1` | `xterm-ghostty` | bpaste,ccolour,clipboard,cstyle,focus,RGB,title |
| Warp | `Warp(v0.2026.07.08…)` | `xterm-256color` | bpaste,ccolour,clipboard,cstyle,focus,RGB,title |
<!-- The XTVERSION string reports whatever build is running; this row records
     what the July build answered and was not re-run on the 2026-08-26 one. -->
| Apple Terminal | *(empty — answers no XTVERSION)* | `xterm-256color` | bpaste,ccolour,clipboard,cstyle,focus,title |

Read from inside a pane with
`tmux display-message -p '#{client_termtype}'`. Three of four are named **and
versioned**. Ghostty is additionally the only one with a distinctive `TERM`.

**Apple Terminal is NOT identifiable from that table — measured.** The feature
set above reads like a fingerprint, and isn't: a bare PTY with
`TERM=xterm-256color` and no terminal behind it at all reports exactly
`bpaste,ccolour,clipboard,cstyle,focus,title` too. tmux derives
`client_termfeatures` from terminfo, so it identifies the `TERM`, not the app.
Identification by elimination fails for the same reason — "empty termtype" is
every silent terminal, not one of them.

**It is identifiable from its process tree.** A tmux client's ancestry is the
window it was launched in, and `#{client_pid}` is the handle:

```
  32465  /opt/homebrew/Cellar/tmux/3.7b/bin/tmux     <- #{client_pid}
  32453  /bin/zsh
  32452  /usr/bin/login
    509  /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
```

This is the CLIENT's chain, not ours — the tmux server is a daemon reparented to
launchd, so our own ancestry says nothing about who is watching. Local only: over
ssh the client's parent is `sshd` and the terminal is on the other end. Costs no
subprocess (`sysctl` per link, `proc_pidpath` per path).

**Environment leakage does NOT work — measured.** Terminals leak their own
variables into panes (`LC_TERMINAL=iTerm2`, `ITERM_SESSION_ID`, `GHOSTTY_*`,
`WARP_*`, `TERM_SESSION_ID`), which looks like a free answer. It is a trap: the
tmux **server** keeps the environment of the client that STARTED it, forever.
Measured by starting a server from Apple Terminal and attaching iTerm2 to the
same session:

```
FIRST client (Apple Terminal started the server)
  client_termtype     =                     <- Apple Terminal
  env TERM_SESSION_ID = 05D12807-…          <- Apple Terminal's
SECOND client attached (iTerm2), same pane, same process
  client_termtype     = iTerm2 3.6.11       <- LIVE, correct
  env TERM_SESSION_ID = 05D12807-…          <- STILL Apple Terminal's. Stale.
  env LC_TERMINAL     = <unset>             <- iTerm2 is attached; still unset.
```

**And the question is malformed anyway: there may be more than one client.**
The same run had both attached simultaneously —

```
attached client: /dev/ttys010 termtype=
attached client: /dev/ttys012 termtype=iTerm2 3.6.11
```

— two terminals, two fonts, painting the same bytes at the same time. There is
no single "the client app" to specialise for. This is a property of a
multiplexer, not a gap in the detection.

**With two clients attached, `display-message` reports the most recently
ACTIVE one** — measured with Apple Terminal and Ghostty on one session: it
returned `ghostty 1.3.1`, the higher `client_activity` (…632 vs …625), and did
not drift afterwards. `list-clients` enumerates them all individually, each with
its own termtype, which is what TUI uses.

**How it is used.** Widths never need the client (the grid is
client-independent, measured), so this drives exactly one decision: the emoji
chrome, whose glyphs are painted by the client's font. Each client is
identified by XTVERSION if it answered, and by its owning application if it did
not; the two are complementary, since XTVERSION crosses an ssh hop and the
process walk doesn't, while the process walk finds a silent terminal and
XTVERSION can't.

- **A client unidentified by BOTH loses the chrome** — a terminal that stays
  silent and isn't a local app we recognise is a real thing (a Linux VT console,
  an old xterm over ssh) and would draw tofu.
- **Every attached client must be recognised**, not just the active one — two
  fonts can be painting the same bytes.

**PUSH, not poll — tmux hooks (measured, 3.7b).** A same-size re-attach sends
no SIGWINCH, so waiting for one would keep a stale answer indefinitely, and
re-probing on a timer would fork in steady state for nothing. Instead, at
startup the app registers three global tmux hooks at array index = its PID —
`client-attached[pid]`, `client-detached[pid]`, `client-session-changed[pid]`
(the complete set of events that can change which terminals paint our output;
all three fire on 3.7b, including for a same-size attach and a SIGKILLed
client) — each running:

```
run-shell -b "kill -s WINCH <pid> || tmux set-hook -gu '<hook>[<pid>]'"
```

Every part measured or load-bearing:

- **Global at a PID index, never session-scoped**: a session-scoped hook
  shadows the user's ENTIRE global array for that hook name (measured — the
  user's `client-attached[0]` stopped firing), while two global hooks at
  different indices coexist. The PID index also keeps several TUI apps on
  one server out of each other's slots.
- **SIGWINCH as the channel**: the app already has a complete, tested SIGWINCH
  pipeline (async-signal-safe flag + self-pipe that wakes the idle-blocked
  loop, full repaint) — a client change rides it with zero new plumbing. And
  SIGWINCH's default action is IGNORE, so a stale hook signalling a recycled
  PID after a crash is harmless (SIGUSR1 would terminate an innocent process).
- **Self-cleaning**: `kill` fails once the PID is gone, and the `||` arm
  removes the hook on its first firing after an uncleaned death. Measured: all
  three orphaned hooks removed themselves within one attach/detach cycle.
  A clean exit removes them explicitly (`set-hook -gu`, ours and only ours).
- **The probe is asynchronous**: the SIGWINCH path kicks a background
  `list-clients` (bounded 250ms; coalesced to at-most-one-in-flight plus one
  queued re-run, so a resize drag costs one or two probes, not one per event).
  Frames keep rendering with the previous answer while it runs; if the landed
  answer differs, the whole screen is invalidated and re-rendered proactively —
  the loop is woken even if it was idle, no keypress needed.

Steady state — no client changes, no resizes — runs **no subprocess at all**.
A tmux too old for these hooks degrades gracefully: registration fails, and
the app adapts only on real SIGWINCHes.

**A client's THEME, on the same channel — measured 2026-09-15 (tmux 3.7c).** A
client that switches between a light and a dark theme changes what the pane is
painted in without changing which client is attached, so none of the three hooks
above fires. tmux does know — it sets mode 2031 on its clients at attach and
reads the `CSI ? 997` they send (see "Colour-palette update notifications") — and
it offers `client-light-theme` and `client-dark-theme`. TUI registers both,
identically to the three above (global, PID-indexed, `run-shell -b`, SIGWINCH,
self-cleaning), because the resize path already throws the screen away and asks
the terminal for its colours again, which is exactly what a new theme needs.

**In their own `set-hook` invocation**, and that is measured rather than
cautious: on a private socket with an empty config, both names were accepted and
appeared in `show-hooks -g`, while an unknown hook name was refused with
`invalid option: …` and a non-zero exit — **and the commands after it in the same
argv did not run**. With a bogus name first, the real hook that followed it was
never set; with the bogus name last, the real one before it was. So sharing one
invocation with the client-change hooks would let a tmux too old for these two
take the other three down with it.

*Unmeasured:* whether either hook actually fires on a real client's theme change,
which needs a terminal that reports its theme attached to tmux and its appearance
changed under it. What is measured is that tmux accepts the registration, and
that the hook body — a backgrounded `kill -s WINCH` — is the same one the three
client-change hooks have been firing all along.

**The attach race (measured).** `client-attached` fires — and the hook-driven
probe runs — BEFORE the new client's XTVERSION reply has arrived, so
`#{client_termtype}` is empty at that instant even for a terminal that names
itself milliseconds later (a hook logging `list-clients` at attach time
recorded an empty termtype for an iTerm2 that reported "iTerm2 3.6.11"
moments later). Two mitigations:

- The process walk covers the common silent cases immediately — including
  iTerm2 with session restoration enabled (the default), whose shells' parent
  chains end at `~/Library/Application Support/iTerm2/iTermServer-<version>`
  rather than the app bundle (measured; the bundle never appears in the chain).
- A reading derived from a still-silent, unidentified client is retried on a
  bounded backoff (250ms/500ms/1s), long enough for the XTVERSION round trip
  and burning out quickly for a genuinely unknown silent terminal.

A probe that FAILS outright (wedged tmux, deadline) keeps the previous answer
rather than reading as "no clients": one slow `list-clients` under load must
not restyle every glyph on screen and flip it back a moment later.

**The through-tmux bar is stricter than the native one — Ghostty fails it
(measured, 2026-07-16).** Natively a terminal qualifies with our compensation
applied; through tmux no compensation can reach the client (a CUF we emit
lands in tmux's grid and corrupts it). And tmux does not replay our bytes: it
redraws a VS-15 cell to the client as

```
⬛ BS BS ⬛︎        (bare U+2B1B, two backspaces, U+2B1B U+FE0E)
```

(byte-captured from a logging client, 3.7b). The client must advance that
sequence by the 2 cells tmux believes it occupies, unaided. DSR-measured on
the alternate screen against exactly those bytes:

| client | net advance | through-tmux emoji chrome |
|---|---|---|
| Apple Terminal 455.1 | 2 | ✓ |
| iTerm2 3.6.11 | 2 | ✓ |
| Warp v0.2026.07.08 | 2 | ✓ |
| **Ghostty 1.3.1** | **1** | ✗ — excluded |

Ghostty's net-1 is its known VS-15 under-advance (bare ⬛ advances 2, the two
BS go back 2, the re-write with U+FE0E advances only 1) — the single quirk
`withGhosttyCursorCompensation()` patches natively. Uncompensated, every row
containing a chrome glyph shears left by one — observed in Example as
`⬛Enable Notifications` losing its gap and the right-edge scrollbar
checkering, one sheared row at a time. So tmux+Ghostty draws the safe ■ □
while native Ghostty keeps the emoji chrome.

**Skin tones through tmux are per-client too — and the mirror image
(measured, 2026-07-16).** tmux re-emits SMP-base skin-tone clusters (👍🏽)
**verbatim** — no backspace trick (byte-captured) — so each client applies its
NATIVE advance while tmux's grid believes 2 cells:

| client | 👍🏽 verbatim advance | tones through tmux |
|---|---|---|
| Ghostty 1.3.1 | 2 | ✓ kept |
| iTerm2 3.6.11 | 2 | ✗ stripped — paints the tone as a broken separate swatch, the same appearance its native path strips for |
| Apple Terminal 455.1 | **4** | ✗ stripped — row shears right by 2 |
| Warp v0.2026.07.08 | **4** | ✗ stripped |

So the per-client policy converges exactly on the native one: Ghostty alone
keeps skin tones. The strip happens at SOURCE (`FrameDiffWriter`'s
`tmuxSkinToneScope`, `.keepingTmuxMerged` for all-Ghostty clients, `.all`
otherwise) — the one fix that survives the hop, because tmux's grid then
holds and re-emits the toneless cluster. The scope rides the same
push-refreshed client probe as the chrome, so a client change restyles both
in the same full redraw. Tones on the 64 bases tmux itself DETACHES (✊🏻 ☝🏽
🤙🏽 — the complement of `Character.tmuxMergedToneBases`) are always
stripped under tmux: its own grid over-advances those, client-independent,
so no client choice can save them.

**A chrome flip invalidates the render cache**, not just the frame diff: the
diff invalidation rewrites every line, but line content comes from the render
pass, and value-memoized subtrees would otherwise serve buffers with the old
glyphs baked in — observed as a mixed-style screen (touched rows in the new
style, untouched rows in the old) with misaligned labels where a stale 2-cell
⬛︎ buffer met fresh 1-cell ■ measurements.

**It follows a client change mid-run**, which is the point — `ToggleCharacterSet.automatic`
is a marker resolved at render, not a style decided when the value was made, so
even an app's own explicit `.toggleCharacterSet(.automatic)` adapts. Verified end to
end on one running app with the client swapped underneath it: it drew ⬛ while
Ghostty watched, and still ⬛ when Apple Terminal took the session with
`attach -d` — same process, no restart, and no termtype to go on the second time.

| client attached | identified by | checkbox glyphs |
|---|---|---|
| iTerm2 / Warp | `#{client_termtype}`, named + versioned | ⬛ ⬜ emoji |
| Ghostty | `#{client_termtype}` — identified, and **excluded** | ■ □ (see below) |
| Apple Terminal, local | owning application (termtype is empty) | ⬛ ⬜ emoji |
| Apple Terminal, over ssh | nothing — silent, and sshd owns the client | ■ □ |
| an unknown silent terminal | nothing | ■ □ |
| several, all recognised | either signal, per client | ⬛ ⬜ emoji |
| several, any unrecognised | — | ■ □ |

### Mouse

**SGR (1006) reporting passes through and the coordinates are correct.**
Verified end to end: with tmux at its default (`mouse off`), Example's own
`ESC[?1006h` / `?1002h` reach the client, and a synthetic press/release injected
into the pane —

```
tmux send-keys -t <pane> -H <hex of ESC[<0;45;11M then ESC[<0;45;11m>
```

— landed on the menu row at screen line 11 and navigated the app to that page.
So tmux neither eats the enable sequence nor shifts the reported cell.

Not yet measured: the encoding under `set -g mouse on` (tmux then consumes
reports for its own pane management and re-emits to the focused pane), and
whether modifier bits survive that path.

### Still unverified

- Cell pixel aspect for images: tmux does not forward the client's
  `ws_xpixel`/`ws_ypixel`, so `cellPixelAspect()` returns nil and callers keep
  their default. Not yet measured whether that default is right under tmux —
  and it cannot be right for every client at once when two are attached.
- Focus reports: which real client terminals get `?1004h` from tmux. tmux
  sends it only with `focus-events` on and a client that answered DA1
  (measured with a harness client, see "Focus reporting (mode 1004)"). No real
  client has been checked.

**Reproduce:** `tmux -L probe new-session -d -x 120 -y 40 -e PROBE_OUT=/tmp/t.json
'python3 Tools/TerminalProbes/advance_probe.py; sleep 2'` then read `/tmp/t.json`.
Always use a dedicated `-L <socket>` and set `TUI_CONFIG_DIR` so probes
never touch a real session or the user's preferences.

---

## GNOME Terminal / VTE (measured 2026-10-23)

**Tested:** GNOME Terminal 3.56.2 using VTE 0.80.1 (`VTE_VERSION=8001`), Debian GNU/Linux 13 (trixie),
Linux 6.12.107+deb13-arm64, GNOME Shell 48 on Wayland, 2026-10-23. DSR-probed with `advance_probe.py`,
`identity_probe.py`, `hyperlink_probe.py`, `clipboard_probe.py`, `graphics_probe.py`, `title_probe.py`,
`sync_probe.py`, and `progress_probe.py`. Records committed in `Tools/TerminalProbes/data/`.

### Environment & Identification

| Variable | Value | Notes |
|---|---|---|
| `VTE_VERSION` | `8001` | set by VTE; encodes `major * 100 + minor` (`8001` = 0.80.1) |
| `GNOME_TERMINAL_SCREEN` | `/org/gnome/Terminal/screen/...` | D-Bus path for the terminal tab/screen |
| `GNOME_TERMINAL_SERVICE` | `:1....` | D-Bus service bus name |
| `TERM` | `xterm-256color` | standard xterm termtype |
| `COLORTERM` | `truecolor` | 24-bit direct colour supported |
| `TUI_TERM_PROGRAM` | `gnome-terminal` | explicit override |

Over ssh or across detached contexts where environment variables are absent, GNOME Terminal answers Device Attributes:
- **DA1 (`ESC[c`):** `ESC[?61;1;21;22;28c` (starts with `?61;`, identifying VT220 / VTE).
- **DA2 (`ESC[>c`):** `ESC[>61;8001;1c` (starts with `>61;`, followed by the VTE version `8001`, and ends with `;1c`).
- **DA3 (`ESC[=c`):** DCS report `ESC P !| 7E565445 ESC \` (`7E565445` is hex for `~VTE`).
- **XTVERSION (`ESC[>0q`):** `ESC P >| VTE(8001) ESC \`.

`TerminalIdentity` uses DA1 prefix `ESC[?61;` and DA2 prefix `ESC[>61;` with suffix `;1c` to reliably identify GNOME Terminal / VTE remotely.

### Output behaviour & Advance quirks

VTE's text layout engine is built on Pango and HarfBuzz, but cursor advance for terminal cells adheres strictly to its internal character width tables:

- **VS-16 pictographs (🛡️ ✏️ ❤️):** advances **1 cell** (under-advances against TUI's claim of 2).
- **Bare SMP pictographs (🚀 🦀 🦄):** advances **1 cell** (under-advances against claim of 2).
- **VS-15 chrome glyphs (⬛︎ ⬜︎):** advances **2 cells** (matches claim of 2). Unlike Apple Terminal, VTE does not require extra cursor compensation for VS-15 chrome; toggles render cleanly.
- **Lone regional indicators (U+1F1E6…):** advances **1 cell** (under-advances against claim of 2).
- **Keycaps (1️⃣):** advances **1 cell** (under-advances against claim of 2).
- **Plane 16 PUA (SF Symbols):** advances **1 cell** (under-advances against claim of 2).
- **Unicode 16.0 additions (🫩 🪚):** advances **1 cell** (under-advances against claim of 2).
- **Fitzpatrick skin tones (🤙🏽 👍🏼 ✊🏻):** Base and modifier swatch are **detached** for all bases (both emoji-presentation and text-presentation bases). Bases advance 1 or 2, and the swatch advances 2 on its own (`base.advance + 2 * swatches.count`).
- **ZWJ sequences (👨‍👩‍👧‍👦 ❤️‍🔥 👩🏽‍🚀):** Decomposed into individual component segments; the joiner (U+200D) advances 0 cells.
- **Complex scripts:** Measured identical to claim on all 38 rows across both screen buffers (zero divergences from the per-code-point sum).

### Cursor compensation walk

Compensated via `String.withGnomeTerminalCursorCompensation()` which uses `withCursorForwardCompensation(advance: \.gnomeTerminalCursorAdvance)`:
- Emits `ECH(claim) + cluster + CUF(claim - advance)` for under-advancing glyphs.
- Leaves correctly advancing glyphs (including VS-15 chrome) untouched.
- Erases the right-edge cell cleanly so that subsequent characters land on their true columns without shearing or leaving unpainted voids.

### Capabilities

| Feature | Supported | Notes |
|---|---|---|
| **OSC 8 Hyperlinks** | **yes** | Native VTE support; Ctrl+Click opens links. Plain, `id=`, and BEL/ST terminations are swallowed cleanly without leakage. |
| **OSC 52 Clipboard** | **no** | Disabled by default in VTE. DA1 does not advertise `52`. All OSC 52 sequences are swallowed cleanly. |
| **OSC 5522 MIME Clipboard** | **no** | Unsupported. |
| **Synchronized Output (mode 2026)** | **no** | DECRQM `?2026` returns `0` (permanently reset). Sequences are swallowed cleanly without leaking. |
| **Window Title (OSC 2, XTWINOPS 22/23)** | **swallowed** | Swallowed cleanly on both screens; does not report via `CSI 21 t`. |
| **Progress & Attention (OSC 9;4, OSC 9)** | **swallowed** | Swallowed cleanly on both screens; progress bar is not drawn; attention falls back to terminal bell. |
| **Graphics Protocols** | **no** | Kitty graphics, Sixel, and iTerm2 inline protocols are not supported in standard VTE; probe confirms all payloads are swallowed cleanly without cursor shift or text leakage. |
| **Emoji Chrome (`supportsEmojiChrome`)** | **yes** | Safe with `withGnomeTerminalCursorCompensation()`. |

---

## A cell's size in points — what the hosts report, and in which unit

An `Image` that is not resizable takes its natural size, as SwiftUI's does
(decisions B42): its size in points, in cells of the terminal's size in
points. So TUI needs a cell's size in **points**, and the hosts report
pixels — in two different units. Every number here is already measured
elsewhere in this document (the cell-aspect probe of 2026-07-14, the
placement records of 2026-09-02 in `Tools/TerminalProbes/data/*-placement.json`,
all on one Retina Mac); this section is what they say about units:

| Host | `TIOCGWINSZ` per cell | `CSI 14 t` per cell | the unit | points |
|---|---|---|---|---|
| Apple Terminal 455.1 | 7 × 14 | 7.05 × 14.13 | points | 7 × 14 |
| Warp v0.2026.08.26 | 8 × 16 | (aspect 2.000) | points | 8 × 16 |
| iTerm2 3.6.11 | 14 × 34 | 7.125 × 18.32 | ioctl retina-scaled; `14 t` in points | 7.125 × 18.32 |
| Ghostty 1.3.1 | 16 × 34 | (aspect 2.125) | device pixels | 8 × 17 at scale 2 |

**What TUI does with it** (`CellPointsCalibration`, chosen once at startup,
applied to every frame's `TIOCGWINSZ` reading, so a font change moves the
points with the pixels):

- **Apple Terminal, Warp:** the reported pixels are points.
- **iTerm2:** asked `CSI 14 t` once at startup (fenced with the status report
  `CSI 5 n`, as every startup question is, so a Shift-F3 pressed during it
  neither ends the read nor is lost); the area over the grid is the cell in points, and the
  ratio to the ioctl's cell is kept. The area rather than `CSI 16 t`'s cell,
  because iTerm2's cell is not a whole number of points and `16 t` answers
  whole numbers.
- **Ghostty:** device pixels, so divided by the display's scale — known only
  when the app runs on the Mac the terminal is on (`TERM_PROGRAM` set, no
  `SSH_CONNECTION`/`SSH_TTY`), from CoreGraphics' main display. A window on a
  display of another scale is sized by the main display's: an image there is
  half or twice its natural size. Over ssh, unknown.
- **tmux:** unknown. tmux does not forward the client's pixel fields (see
  "tmux" above), and two attached clients would not agree on a cell anyway.
- **Every other host:** unknown — its pixels are of a kind nobody has
  measured. An image there that is not resizable fits what it is offered, as
  every image did before images had a natural size.

`\.imageCellPoints` carries the answer (`nil` for unknown), and an app can
state it for a terminal TUI cannot ask with `.imageCellPoints(_:)`.

## What an ANSI colour actually paints

**Status: palettes MEASURED for Apple Terminal.app 455.1 (default "Basic"
profile) on 2026-08-24, and for iTerm2 3.7.1 (profile "Default") and Ghostty
1.3.1 (default config) on 2026-09-14. Ghostty's had been read from its own
configuration on 2026-09-01, and the live answers matched it. Warp 0.2026.09.02
does not report its palette: it left OSC 4 unanswered on 2026-09-14. How each
host answers the queries themselves, and what tmux and GNU screen do to them,
was measured on 2026-09-14; see "Asking the terminal for its colours" below.
So was whether reverse video (SGR 7) prints or moves the cursor. What a reversed
cell paints was measured on 2026-09-19; see "Reverse video (SGR 7)" below. Hyper was not
measured.**
`Tools/TerminalProbes/palette_probe.py` asks a terminal directly (OSC 4 /
OSC 10 / OSC 11) and writes the answer as JSON; run it in each host and record
the results below. `osc_colour_probe.py` measures the exchange itself.

### Apple Terminal.app 455.1, "Basic" — measured

It answered all 25 queries, and **15 of the 16 ANSI names differ from xterm's
table**. Only slot 0 (black) matches.

| slot | reported | xterm | | slot | reported | xterm |
|---|---|---|---|---|---|---|
| 1 red | 153, 0, 0 | 205, 0, 0 | | 9 | 230, 0, 0 | 255, 0, 0 |
| 2 green | 0, 166, 0 | 0, 205, 0 | | 10 | 0, 217, 0 | 0, 255, 0 |
| 3 yellow | 153, 153, 0 | 205, 205, 0 | | 11 | 230, 230, 0 | 255, 255, 0 |
| 4 blue | 0, 0, 179 | 0, 0, 238 | | 12 | 0, 0, 255 | 92, 92, 255 |
| 5 magenta | 179, 0, 179 | 205, 0, 205 | | 13 | 230, 0, 230 | 255, 0, 255 |
| 6 cyan | 0, 166, 179 | 0, 205, 205 | | 14 | 0, 230, 230 | 0, 255, 255 |
| 7 white | 191, 191, 191 | 229, 229, 229 | | 15 | 230, 230, 230 | 255, 255, 255 |
| 8 br.black | 102, 102, 102 | 127, 127, 127 | | | | |

**Default foreground `(0, 0, 0)` on background `(255, 255, 255)` — black on
white.** The out-of-the-box Apple terminal is a LIGHT one, which is worth
knowing before assuming a dark surface anywhere.

**The 6×6×6 cube and the greyscale ramp match xterm exactly** — 21, 46, 52,
124, 196, 231, 232, 240 and 255 were all sampled and all agreed. So this host
remaps the sixteen NAMES and nothing else, which is the pattern the section
above called conventional, now with one host's evidence behind it.

#### What that costs, computed

Terminal.app's palette is systematically MUTED — every name darker or less
saturated than xterm's. Against its own white background that makes contrast
*better* than the table predicts, uniformly:

| slot | believed | actual |
|---|---|---|
| 1 red | 5.84 | 8.92 |
| 2 green | 2.16 | 3.25 |
| 3 yellow | 1.70 | 3.04 |
| 4 blue | 9.40 | 12.72 |
| 6 cyan | 1.98 | 2.96 |
| 7 white | 1.26 | 1.84 |
| 8 br.black | 4.00 | 5.74 |
| 12 br.blue | 4.74 | 8.59 |

Measured by xterm's table, `ensuringContrast` believed every ANSI colour less
legible than it is here, and **over-corrected**, which is the safe direction to
be wrong in. Since 2026-09-15 it measures a slot as the terminal reported it,
and as nothing until then (see "Why this is load-bearing rather than trivia",
below). A slot, or 39, that falls short of the floor is swapped for another
name the terminal keeps, never re-spelled as RGB: a standard slot's bright twin,
then 39, then slots 0, 7, 8 and 15, and where none of them reaches the floor,
whichever reads best, the colour itself included. The terminal's background is
never one of them. Computed from this host's reported colours (black 39 on the
white page):

| asked, on | measured | at 3:1 | at 4.5:1 |
|---|---|---|---|
| `.ansi(.yellow)`, the page | 3.04 | kept | 39 (its twin reads at 1.34) |
| `.ansi(.cyan)`, the page | 2.96 | 39 (its twin reads at 1.56) | 39 |
| `.ansi(.white)`, the page | 1.84 | 39 (its twin reads at 1.25) | 39 |
| `.ansi(.brightWhite)`, slot 9 | 3.86 | kept | 39 at 4.36, the best: nothing reaches 4.5 (slot 0 ties with 39, and 39 comes first) |
| 39, slot 4 at 60% over the page, (102, 102, 209) | 4.39 | kept | 39, the best: slot 15 reads at 3.84, slot 7 at 2.60 and slot 8 at 1.20 |

The last row is a text field's selection on a palette whose grounds and ink are
the terminal's. The page itself would read better on it, at 4.79:1, but drawn as
text it is spelled as the page's RGB, so `readableText(on:)` never picks it.
Before this rule the text was that RGB white, and the slot 9 row came back as
RGB (248, 248, 248). Two things still follow:

- An app asking for `Color.ansi(.cyan)` as text over this host's page, where a
  floor applies, gets 39, black. It gets a name the profile keeps, not a darker
  cyan the profile does not.
- Slots 3 and 7 are below 4.5:1 on either table, so an `.ansi(.yellow)` or
  `.ansi(.white)` foreground on a light terminal is illegible however it is
  measured.
  That is a fact about light backgrounds, not about the table.

None of this reaches colours TUI chooses itself: those are palette roles,
which resolve to RGB and are stated exactly.

### Ghostty 1.3.1, default theme — read from its own configuration

**Provenance: `ghostty +show-config --default`, 2026-09-01, with the user's
`config.ghostty` empty (0 bytes) so the defaults are what runs. Confirmed in a
live window on 2026-09-14: over OSC 4, 10 and 11, a default-config Ghostty
reported every value below, the eight slots not listed, and the background and
foreground, exactly as configured (see "Asking the terminal for its
colours").**

Ghostty's stock scheme is Tomorrow Night, and it is muted on purpose. **Slot 0
is not black**, which is the whole of why a near-black photograph renders
visibly lighter here than in Terminal.app:

| slot | Ghostty | Apple Terminal (measured) | xterm (assumed) |
|---|---|---|---|
| 0 black | `#1d1f21` (29, 31, 33) | 0, 0, 0 | 0, 0, 0 |
| 4 blue | `#81a2be` (129, 162, 190) | 0, 0, 179 | 0, 0, 238 |
| 6 cyan | `#8abeb7` (138, 190, 183) | 0, 166, 179 | 0, 205, 205 |
| 7 white | `#c5c8c6` (197, 200, 198) | 191, 191, 191 | 229, 229, 229 |
| 8 br.black | `#666666` (102, 102, 102) | 102, 102, 102 | 127, 127, 127 |
| 12 br.blue | `#7aa6da` (122, 166, 218) | 0, 0, 255 | 92, 92, 255 |
| 14 br.cyan | `#70c0b1` (112, 192, 177) | 0, 230, 230 | 0, 255, 255 |
| 15 br.white | `#eaeaea` (234, 234, 234) | 230, 230, 230 | 255, 255, 255 |

Two consequences for a 16-colour image, and neither is a defect:

- **`#1d1f21` is the darkest colour Ghostty has.** A black pixel cannot paint
  darker, whatever the quantiser picks, so "the background came out lighter"
  is the answer and not a symptom.
- **The blues and cyans are desaturated steel and sage**, so a picture whose
  subject is saturated blue reads as teal. Terminal.app's slot 4 is a pure
  `(0, 0, 179)`; Ghostty's is a grey-blue two thirds of the way to neutral.

Default background `#282c34` and foreground `#ffffff` — but a TUI app paints
its own page, so those reach nothing an image draws.

### Asking the terminal for its colours: OSC 10, 11, 4 and `?996n` — measured 2026-09-14

**Provenance.**
- Hosts: `Tools/TerminalProbes/osc_colour_probe.py`, run inside each host.
- tmux: that probe run in a pane, plus `tmux_colour_harness.py`.
- macOS 15.7.9 (24G830), system appearance Light. The probe records are not
  committed (see the probes' README).
- **Latency** runs from just before the write to the read that completed the
  reply, and includes Python's `select` wake-ups. It is one or two runs per host
  on one machine, so read it as an order of magnitude.
- **Two passes the same day.** The first measured Apple Terminal, iTerm2, Warp,
  screen and tmux. The second measured Ghostty, and iTerm2 again, with the
  same unchanged probe.
- The host runs of both passes predate the probe's batch and multi-pair
  sections. So for native hosts, only single queries and the OSC 10 + 11 pair
  were measured.
- The machine is a virtual Mac (`hw.model` VirtualMac2,1).

**Not measured:**
- **Hyper 3.4.1**, because it did not start on this machine. Gatekeeper no
  longer blocked it, but all three launches (08:03, 08:12 and 09:13) crashed
  within 0.4 s, before any window: `EXC_BREAKPOINT` in
  `v8::internal::wasm::WasmCodeManager::WasmCodeManager()`, called from
  `WasmEngine::InitializeOncePerProcess()` inside `v8::V8::Initialize`. That is
  V8 setting up WebAssembly, before any JavaScript ran. This was observed on
  this virtual Mac. Whether Hyper fails the same way elsewhere was not tested.
- **Ghostty as a tmux client.** After the two runs below, Ghostty stopped
  opening usable windows. Six launches produced either no window, or a window
  whose log says `error initializing surface err=error.OutOfMemory`, with no
  child started. The cause was not established.
- **Ghostty's `?996n` under a Dark system appearance**, which would need a
  system setting changed.
- ssh, and Apple Terminal with a dark profile.

**Launching Ghostty.** `open -na Ghostty.app --args -e <script>` ran the probe
with no prompt, in both runs below. Running the `ghostty` binary directly with a
bare script path did not. A stack sample shows AppKit passing the path to
`application(_:openFile:)`, which put up a modal `NSAlert`. The first pass's
failed direct launch fits that, but it was not sampled.

**iTerm2 3.7.1: where its records came from.**
- **First pass.** The launch (`open -a iTerm` on a `.command` file) first showed
  only a 276×312 window, probably an alert, and the probe did not run then. The
  record came from the same launcher, timestamped 07:48, well after that
  attempt. It carries iTerm2's own environment: `TERM_PROGRAM=iTerm.app`,
  `TERM_PROGRAM_VERSION=3.7.1`, `ITERM_PROFILE=Default`, `TERM_FEATURES` and
  `COLORFGBG=0;15`. Nobody noted who dismissed the window, or when.
- **Second pass.** Two more launches, one of a new `.command` file and one of
  the file approved in the first pass, each put up another 276-wide window
  (276×326 and 276×312) and did not run. Both probes ran at 09:02, 1.5 s apart, presumably once
  someone approved the windows. So **iTerm2's alert has to be approved on every
  `.command` launch**, even for a file approved before. Nobody saw the alert's
  text, because screen capture returned only the wallpaper.
- **The 09:02:12 record agrees with the 07:48 one** on every colour,
  terminator, ordering and `?996n` result, and on latency (below).
- **The other 09:02 record is set aside.** It started 1.5 s earlier in a second
  iTerm2 window, so the two probes overlapped. While they did, its replies fell
  up to a second behind. Three fence replies were counted as timed out and then
  turned up in later exchanges. Once the other probe finished, it was back to
  15–33 ms. That two sessions querying at once slowed each other is inferred.

| Host | OSC 10 (fg) | OSC 11 (bg) | OSC 4, slots 0–15 | `?996n` | Reply terminator | Latency | Reply in the fence's read |
|---|---|---|---|---|---|---|---|
| Apple Terminal 455.1, default profile | 0, 0, 0 | 255, 255, 255 | all 16; byte for byte the Basic table above | silent | **always BEL**, even for an ST query (40 of 40) | ~0.1 ms (0.07–0.5) | 74 of 76 |
| iTerm2 3.7.1, profile "Default" | 16, 16, 16 | 250, 250, 250 | all 16 (below) | `997;2` | **always ST**, even for a BEL query (36 of 36, in each of two runs) | **~15–20 ms**, median by query (2.8–33; fences 15–36): two orders of magnitude slower than any other host | none: an earlier read |
| Ghostty 1.3.1, default config | 255, 255, 255 | 40, 44, 52 | all 16; the configured table above, byte for byte | `997;2` | mirrors the query | ~0.05 ms (0.03–0.13; fences 0.05–0.20) | none: an earlier read |
| Ghostty 1.3.1, `--background=000000 --foreground=ffffff` | 255, 255, 255 | **0, 0, 0** | the same 16 | **`997;2` again** | mirrors the query | as above | none: an earlier read |
| Warp v0.2026.09.02.08.27.stable_01, light theme | 17, 17, 17 | 255, 255, 255 | **silent** in all 64 exchanges; the fence still came back in ~0.1 ms | silent | mirrors the query | ~0.03 ms | all |
| GNU screen 4.00.03, inside Apple Terminal | silent | silent | silent | silent | — | fences ~0.1–0.3 ms | — |
| tmux 3.7c | a client's (see below) | a client's | forwarded to one client (see below) | answered by tmux | mirrors the query | ~0.1 ms when answered | all |

iTerm2's sixteen, as reported. They are not xterm's table either:

| slot | reported | | slot | reported |
|---|---|---|---|---|
| 0 black | 21, 25, 30 | | 8 | 104, 104, 104 |
| 1 red | 167, 69, 50 | | 9 | 208, 126, 120 |
| 2 green | 87, 191, 56 | | 10 | 130, 228, 152 |
| 3 yellow | 199, 196, 63 | | 11 | 234, 226, 74 |
| 4 blue | 46, 67, 192 | | 12 | 167, 171, 237 |
| 5 magenta | 177, 73, 184 | | 13 | 212, 131, 220 |
| 6 cyan | 89, 194, 198 | | 14 | 142, 250, 253 |
| 7 white | 199, 199, 199 | | 15 | 255, 255, 255 |

**Across every measured host:**
- **Reply form:** always `rgb:` with four hex digits per channel. There was no
  `rgba:` and no shorter spelling.
- **Order:** no reply arrived after the fence reply sent behind it, on any host.
  There were no stray or late bytes, and nothing printed: the cursor never
  moved.
- **Fences:** both `CSI 6n` and `CSI 5n` were answered in every exchange on every
  host, including screen and Warp's unanswered OSC 4. That holds for every
  record used here; the one set-aside iTerm2 record is above.
- **Terminator:** a parser has to take BEL and ST whatever it sent.
  - mirrors the query: Ghostty, Warp and tmux;
  - always BEL: Apple Terminal;
  - always ST: iTerm2.
- **`?996n`:** answered by Ghostty, iTerm2 and tmux (under tmux, tmux itself
  answers). Apple Terminal, Warp and screen were silent. Both native answers
  were `997;2`.
- **Ghostty's `997` follows neither the background it paints nor its own
  OSC 11.** It answered `997;2` (light) on its default 40, 44, 52 and on 0, 0, 0
  alike, while its OSC 11 reported each of those backgrounds correctly in the
  same run — so the two contradict each other on the same host, within
  milliseconds. The system appearance was Light for both runs, so Ghostty may
  follow that instead. *Inferred*, not measured: it needs a run under Dark.
  iTerm2's `997;2` came with a light background, so it cannot tell the two rules
  apart. Under tmux, `997` followed the client's background (below). This is why
  a `997` is treated as a signal to ask rather than as an answer: the framework
  re-reads OSC 10, 11 and 4 when one arrives, and ranks `prefersDark` from the
  reported background first.
- **`COLORFGBG`:** only iTerm2 set it (`0;15`). It was unset in Apple Terminal,
  Ghostty and Warp, and in the screen and tmux panes.
- **screen:** its panes inherit `TERM_PROGRAM=Apple_Terminal` from the outer
  host, which is stale there.
- **What the framework takes from this about light and dark.**
  `TerminalColorQuery.resolve` ranks the answers the startup exchange (below)
  gets.
  - A default colour the terminal did not report stays unknown. It is never
    inferred from the other one.
  - The reported background decides first: dark when white contrasts with it
    at least as much as black does.
  - Then `997`. It ranks below the background because Ghostty's did not follow
    the background it painted, and under tmux it restates that background.
  - Then `COLORFGBG`'s last field, dark for slots 0–6 and 8. It is ignored
    under tmux (`TMUX`, or `TERM_PROGRAM=tmux`) and screen (`STY`).
    *Inferred*, not measured: a pane's environment comes from whatever started
    the session, so an inherited `COLORFGBG` can describe a terminal that is no
    longer attached. It was unset in every pane measured here.

#### What the framework asks at startup

`TerminalClient.detectColors(using:)` runs once, after graphics detection and
before `RenderLoop` is built, so the first frame is drawn with whatever came
back. It asks only when stdin is a TTY in raw mode.
- **Native hosts:** OSC 10, OSC 11, then OSC 4 for slots 0–15, one query each,
  all ended in ST, then `CSI 5n`: 170 bytes in one write.
- **tmux:** OSC 10, OSC 11 and `CSI 5n` only. The slots are left out because
  tmux forwards OSC 4 to one client and holds the fence about half a second
  when that client is silent (below). They are asked for after the first frame
  instead, where nothing that draws waits for them: see "Asked again" below.
- **Waiting:** until the `CSI 0 n` fence, or 0.5 s, the deadline the other
  startup exchanges use. Replies that arrived before the deadline are kept.
  Keystrokes and focus reports that arrive among the replies go back to the
  input parser.
- **Published:** `TerminalColors.current` gets what `resolve` makes of the
  answers, unless that says nothing. So a silent terminal leaves the record
  unknown, but a `COLORFGBG` hint is still published.
- **Asked again, once the first frame is on screen:** under tmux only, and for
  the sixteen slots only, since they are the ones left out above
  (`TerminalColorRequester`). The request is written and not waited for — tmux's
  half second holds no output of ours (a line printed straight after each batch
  reached the client in 0.15–0.9 ms while the fence was still outstanding), and
  the answer comes back as a late reply, below.
- **Asked again when the screen is thrown away:** on a resize, on a resumed
  suspend, and on the tmux client change — or, since 2026-09-15, the tmux client
  THEME change — that our hooks turn into a SIGWINCH; each of them a moment when
  the terminal in front of the user may be a different one, or the same one
  painting differently. The whole request goes out again, the default pair included, since the
  pair belongs to whichever client answers now. A terminal that has never said
  anything of its own about its colours is left alone, unless this is tmux (the
  silent client may not be the one attached now) or it has reported its own
  theme with a `997`. A burst — a resize drag — is one request and one resend:
  at most one is outstanding, and its fence releases the next. A fence that has
  not come back in a second is taken as lost, the request goes out once more,
  and after that it is given up rather than polled.
- **Asked again when the window comes back:** a focus report (mode 1004) that
  moves the scene from inactive to active. Nothing on screen was thrown away —
  but the user has been looking at another window, and may have changed this one
  while they were: switched its profile, or flipped its theme with the system's.
  Only a host that reports its own theme would have volunteered that, and most
  do not. The same request, the same skip rule and the same coalescing as above,
  so flicking focus back and forth is one request and one resend. A report of
  the focus the scene already has asks nothing — a terminal may send one as
  reporting is enabled, and the startup exchange has just run — and neither does
  focus going away, nor a report while the app is suspended (the resume asks by
  itself).
- **Asked again when the terminal says its theme changed:** a `CSI ? 997 ; Ps n`
  report, which a host sends unprompted while mode 2031 is set — TUI sets it
  for the life of the app (see "Colour-palette update notifications"). The report
  names light or dark and no colour at all, so the whole request goes out: what
  the terminal PAINTS now is what nothing has said. No skip rule applies, since a
  host that sent one has answered by definition. A reply to a request of ours is
  not a report and asks nothing back, or every answer would ask the question
  again.
- **A reply later than the deadline is still read.** The input parser keeps an
  OSC 10, 11 or 4 answer and a `CSI ? 997 ; Ps n` report instead of dropping it
  with everything else nobody typed, the run loop takes what it kept once per
  drain, and `TerminalColorRefresher` publishes what the reply adds to what was
  known — each field it does not mention keeping its published value — and
  repaints the screen. A reply that changes nothing publishes nothing. That is
  also how a terminal that changes its own theme mid-run is heard, and the only
  way tmux's sixteen slots could arrive at all, since its silent client holds
  the fence past the deadline.

**Round trip.** The native request itself, one write with eighteen queries,
was measured on one host only:
- **Apple Terminal 455.1**, default profile, macOS 15.7.9, 2026-09-15, with the
  probe's `batch-native` exchange, which is byte for byte the framework's
  request. All 18 replies arrived before the fence, whose reply completed at
  0.28 ms. Every reply ended in BEL, and nothing printed.

The other hosts are known from single queries and the OSC 10 + 11 pair, on
2026-09-14 (table above):
- Ghostty 1.3.1: about 0.05 ms per query; the pair's replies took 0.10 and
  0.12 ms, and its `6n` fence 0.15 ms.
- iTerm2 3.7.1: 15–20 ms median per query (2.8–33 ms), fences 15–36 ms.
- Warp: about 0.03 ms. OSC 4 is silent there, but the fence still came back in
  about 0.1 ms.
- GNU screen 4.00.03: every colour query silent; fences 0.1–0.3 ms.
- tmux 3.7c: OSC 10 + 11 alone took 0.02–0.8 ms.

*Inferred*, not measured: the batch costs about what its slowest query does,
since tmux's batch shared one wait. **Not measured:** the native batch on
iTerm2, Ghostty and Warp. On 2026-09-15 the Warp run blocked before its first
exchange: 0.01 s of CPU in three minutes, and no record. The Ghostty instance
started no child, as after 08:03 on 2026-09-14. iTerm2 was not launched.

#### tmux 3.7c

**Two sets of clients**, with a private socket and an empty config both times:
- **Real ones.** Apple Terminal alone; Apple Terminal with Warp attached
  second; then Warp alone after Apple Terminal detached.
- **Scripted ones**, from `tmux_colour_harness.py`, whose answers are known and
  whose logs show every query tmux forwarded:

| client | fg | bg | OSC 4 | its own `?996n` report |
|---|---|---|---|---|
| A | ffffff | 000000 | answers | `997;1` |
| B | abb2bf | 282c34 | silent | `997;2`, contradicting its own dark background |

**OSC 10 and 11: tmux answers from what the client said at attach**, in
0.02–0.8 ms. Each client was asked `OSC 10;?` and `OSC 11;?` twice at attach, and
never again, however often the pane asked. The pane sees **the earliest-attached
client that is still attached**:
- Scripted runs: in both attach orders and all four configurations. That
  includes a second client attached later, and one that typed more recently.
- Real clients: OSC 10 stayed Apple Terminal's `0, 0, 0` while Warp, attached
  second, was the pane's current client. It became Warp's `17, 17, 17` only once
  Apple Terminal detached.
- *Inferred:* "earliest attached" could equally be "first in tmux's client
  list"; these runs cannot tell the two apart.

**OSC 4 goes to exactly one client: the one attached or active most recently.**
The other client's log shows no OSC 4 at all. So fg/bg and slots can come from
different clients: with B attached first and A last, the pane got B's colours
and A's slots.

**When that client does not answer OSC 4**, no reply ever comes, and the fence
reply behind the query is held about half a second:
- **One query per exchange:** 503–552 ms each, over 312 exchanges across the
  scripted runs and the real Warp client (median 522 ms with Warp). A probe asking slot by slot runs
  out of its 20 s partway through the slots.
- **A batch shares one wait:**
  - the startup batch (OSC 10, OSC 11, OSC 4 for slots 0–15, then `CSI 5n`):
    515–542 ms, with fg/bg still answered;
  - one slot: 516–539 ms;
  - the multi-pair spelling: 511–531 ms.
- **Pane output is not held.** A line printed straight after each batch reached
  the client 0.15–0.9 ms after the write, while the fence reply was still
  waiting.
- **For comparison:** fg/bg alone took 0.02–0.8 ms, and a client that answers
  returned the startup batch, all 16 slots included, in 0.5–1.9 ms.
- *Inferred:* tmux waits up to about 500 ms for a forwarded reply, and queues
  the pane's later requests behind it. This was not read from tmux's source.

**`?996n`: tmux answers it itself, even when the client does not.** The answer
followed **the client's background, not the client's report**:
- With only B attached, `997;1`. B reported `997;2`, and `list-clients` shows
  B's `client_theme` as `light`.
- For A (black), `997;1`.
- For Apple Terminal and Warp (both white, and both silent on `?996n`
  themselves), `997;2`.
- With two clients attached, their backgrounds agreed in every run. So which
  client it follows is unmeasured.
- *Inferred:* under tmux, `997` restates a background the pane can already read
  over OSC 11.

**The multi-pair spelling `OSC 4;0;?;1;?;2;?` works.**
- tmux forwards it as three single queries.
- An answering client's three replies reached the pane in 0.16–1.0 ms.
- A silent client held the fence once (511–531 ms, above).

A throwaway run earlier the same day reported this spelling broken under tmux
(one slot, after 0.51 s). **That was the harness.** Its client re-sent a stale
OSC 4 reply alongside the fresh ones. The same script, changed only to answer
each query once, got all three slots. That a stale reply makes tmux return one
slot and hold the fence was observed; why was not established.

**Sent to each client** (empty config):
- at attach: `?2004h`, `?2031h`, `?996n`, DA1, DA2 and XTVERSION, then `OSC 10;?`
  and `OSC 11;?` twice;
- at detach: `?2004l`, `?1004l` and `?2031l`.

### Colour-palette update notifications (mode 2031) — measured 2026-09-14, Ghostty 2026-10-19

DEC private mode 2031 is how an application asks to be TOLD its colours changed
rather than having to ask: with it set, a terminal that repaints its palette
sends `CSI ? 997 ; Ps n`, the same report `CSI ? 996 n` asks for on demand
(above). tmux sets it on its own clients at attach and resets it at detach
(measured, listed just above), which is what made it worth measuring here.

**Status:** measured on six hosts. Ghostty, the sixth, was measured on
2026-10-19, for this and for reverse video's cursor half (below). Before that
it was unmeasured: `open -na Ghostty.app --args -e <script>` made a window and
started no child, on 2026-09-14 (twice) and again on 2026-09-15 — on
2026-09-14 at least, Ghostty was waiting to be allowed to run a script path new
to it, and nobody was there to answer (the probes' README). Its record is
`Tools/TerminalProbes/data/ghostty-1.3.1-m3m7.json`: primary screen, macOS
15.8.1, 8.6 s, no fence timed out.

| Host | `CSI ? 2031 h` / `l` | Unsolicited `997` on enable | DECRQM `CSI ? 2031 $ p` | Does the DECRQM print? |
|---|---|---|---|---|
| Apple Terminal 455.1, "Basic" | nothing printed, cursor unmoved, in all 7 steps | none | *silent* | **yes — one cell (+1 column)**, and so did the `?25` control |
| iTerm2 3.7.1, profile "Default" | nothing printed, cursor unmoved | none | `ESC[?2031;2$y` reset, `ESC[?2031;1$y` set, `ESC[?2031;2$y` after reset — it tracks the mode | no |
| Warp v0.2026.09.02.08.27.stable_01 | nothing printed, cursor unmoved | none | *silent* | no |
| GNU screen 4.00.03, inside Apple Terminal 455.1 | nothing printed, cursor unmoved | none | *silent* | no — screen consumes the query, so Apple Terminal's leak never reaches the outer screen |
| tmux 3.7c, inside Apple Terminal 455.1 | nothing printed, cursor unmoved | none | `;2` reset, `;1` set, `;2` after reset, in 0.03–0.13 ms — per pane | no |
| Ghostty 1.3.1 (2026-10-19) | nothing printed, cursor unmoved, in all 9 steps | none | `ESC[?2031;2$y` reset, `ESC[?2031;1$y` set, `ESC[?2031;2$y` after reset, in 0.04–0.11 ms — it tracks the mode | no, nor did the `?25` control (`ESC[?25;1$y`) |

The `?25` control matters: on Apple Terminal it leaked a cell exactly as `?2031`
did, so the leak is that host's `?`-plus-intermediate CSI rule (see "Asking the
terminal — Device Attributes") and not something about this mode. **So mode 2031
may be set and reset anywhere, and its DECRQM may not be sent to a bare Apple
Terminal.** There is also nothing to gain by asking: the hosts that answer it
natively are iTerm2 and Ghostty, and the answer only says whether the mode this
process just set is set.

**Provenance.**
- `Tools/TerminalProbes/osc_colour_probe.py` with `PROBE_SUITE=m3m7`, run inside
  each host; macOS 15.7.9 (24G830), system appearance Light, on the virtual Mac
  above. Those records were not committed. Ghostty's, of 2026-10-19 on macOS
  15.8.1, is: `Tools/TerminalProbes/data/ghostty-1.3.1-m3m7.json`, which
  `python3 osc_colour_probe.py --summarise` prints a line per step.
- Judged by the cursor, as the reverse-video rows below are: a step "printed"
  when the cursor is not where it should have left it. Output that moves no
  cursor goes unseen, and under screen and tmux the report comes from the
  multiplexer's own grid.
- Where iTerm2's record came from: the same launch that produced its
  reverse-video row, and the same caveat — see that section's provenance.

**What TUI does.** `Terminal.enableRawMode` sets mode 2031 straight after
focus reporting's `?1004h`, and `disableRawMode` resets it just after `?1004l`,
so a suspend (SIGTSTP, or a Ctrl-Z the undo keys leave unbound) and quitting both turn it off and resuming turns it back on —
the mode outlives the process, and the shell never asked to be told about themes.
`Tools/Smoke/suspend_probe.py` checks all four, beside the focus-reporting rows
it already checked. It is sent blind to every host, as the focus request is: six
printed nothing, tmux sets it on its own clients anyway, and the DECRQM that
could ask first is the one shape Apple Terminal prints. A `CSI ? 997` that then
arrives is not a colour — it names light or dark — so the framework asks the
whole colour request again rather than believing it (see "What the framework asks
at startup").

**What "no unsolicited `997`" does and does not say.** It says none arrived
within 1.5 s of each of four enables, plus a 0.8 s final drain, on a host whose
appearance nobody touched during the run. It says **nothing** about whether a
host reports when its theme actually changes, which is the case the mode exists
for: measuring that needs a system appearance or a profile changed under a
running probe, and no run here has done it. Under tmux the question is doubly
open — whether tmux forwards a client's report into a pane that set the mode was
not measured either.

### A host may recolour a foreground it cannot read — measured 2026-09-01

**Status: the framework no longer emits the sequence that provokes it.**

Warp has `appearance.text.enforce_minimum_contrast`, and it defaults to
**`only_named_colors`** — "FG color can be changed, but only if the FG is
specified with default colors" (its own settings schema, read from
`Warp.app/Contents/Resources/settings_schema.json` on 2026-09-01; the three
values are `never`, `only_named_colors`, `always`). So a foreground stated as
one of the sixteen and judged illegible against its background is LIGHTENED.

That is a reasonable thing for a terminal to do to text and a ruinous thing to
do to a picture. A half block whose two pixels quantise to the same colour is
emitted with foreground == background, which is the most unreadable text there
is; Warp lifted the foreground of every such cell, so the lower half of the
cell went grey while the upper half — the background, which the feature does
not touch — stayed put. **The picture banded at cell pitch**, exactly as it did
on iTerm2, and for an unrelated reason: Warp does not brighten bold at all.

Two hosts, two causes, one symptom. The card separates them:
`bold_bright_card.py` draws a flat colour as a space, as a block with
foreground == background, and as that block emboldened.

| what bands | cause | hosts |
|---|---|---|
| the bold block only | bold is read as a colour | iTerm2 |
| the plain block AND the bold one | a named foreground is being made legible | Warp |
| neither | no adaptation applies | Ghostty, Terminal.app |
| the space | the host is not painting a cell background across the whole cell — nothing TUI emits can help | none seen |

**The fix** is not to state a foreground the cell does not use: a cell whose two
pixels paint the same colour is emitted as a SPACE with only a background. It
is also the honest spelling — one colour is a field, not a shape — and most of
a picture is such cells: 41.8% at true colour, 73.6% at 256, **86.5% at
sixteen**, since the coarser the palette the more often two neighbours land on
one entry. Measured on the Example's demo photograph at 183×60.

`enforce_minimum_contrast` reaches only NAMED foregrounds at its default, which
is why the report was about 16-colour mode: a `38;2` triple was never touched.
Set to `always` it would reach those too, and there is nothing an application
can do about that — nor should there be.

### Bold is a COLOUR on some hosts — measured 2026-09-01

**Status: the framework no longer relies on it. Per-host readings still wanted;
run `Tools/TerminalProbes/bold_bright_card.py` in each.**

`SGR 1` is documented as a weight. xterm and most of its descendants also treat
it as a colour: with bold in force, a foreground named as one of the standard
eight (`SGR 30`–`37`) is painted in its BRIGHT twin. Backgrounds are never
brightened, and an explicit `38;2;r;g;b` triple has no twin to be swapped for,
so the reinterpretation reaches exactly the sixteen NAMES.

Each host spells the choice differently, and they do not agree:

| host | setting | this machine's value | brightens bold? |
|---|---|---|---|
| iTerm2 | `Use Bright Bold` (profile) | `True` — the default | yes |
| Warp | none | — | **no** — measured on the card 2026-09-01 |
| Ghostty | bold is weight-only; `bold-color` overrides the colour explicitly | unset | no |
| Apple Terminal.app | "Use bright colors for bold text" (profile) | absent from `Basic`, so off | no |

Read from `com.googlecode.iterm2.plist`, `ghostty +show-config --default` and
`com.apple.Terminal.plist` on 2026-09-01, and confirmed by eye on the card in
all four. Warp was assumed to brighten when this was first written, because it
banded; it does not, and the section above is what it actually does. **Two
hosts can produce one symptom for two causes — measure each rather than
generalising from the first one solved.**

**What it cost.** `ASCIIConverter+HalfBlocks` emboldened every `▄` it emitted,
to close a rasterisation gap under SF Mono in Terminal.app (see the advance
table below). In `.trueColor` that is free. In ``ASCIIColorMode/ansi16`` the
foreground is `30`–`37` / `90`–`97`, so on iTerm2 **every cell's lower half was
painted in the bright twin of the colour asked for** while its upper half — the
background — stayed correct. A picture drawn entirely out of half blocks
therefore came out in horizontal stripes at cell pitch. Measured on the
Example's demo photograph at 183×60: 5724 cells, all bold, and 86.5% of them
with foreground == background, which is precisely where a stripe is most
visible because the cell should be flat.

The emission was identical under every `TERM_PROGRAM` — this was never a
per-host code path, just a per-host reading of one universal sequence.

**The fix** is ``ASCIIColorMode/foregroundSurvivesBold``: spend the weight only
where the foreground has no bright twin — a `38;2` triple, or `38;5;n` where
*n* ≥ 16, which is every index the 256-colour quantiser can produce. A palette
is only as safe as its least safe entry, and ``ASCIIPalette/downsampled(to:)``
turns any palette into unsafe names at `.basic16`. Where the weight is refused
the Terminal.app hairline returns, which is the lesser evil: a hairline on one
host beats a ruined image on two.

**The general rule for the framework**: any attribute that a host may read as a
colour must not be used decoratively over a colour stated as one of the sixteen.
Bold is the one that exists today; `SGR 2` (faint) is the same shape of hazard.

**Where the framework asks for the twin itself (2026-09-15).** A hover on a
control whose fill cannot be measured lifts a standard slot to its bright twin
(Opacity as composition §82). A focused button's label is also bold, so on a
host that brightens bold, such as iTerm2 with `Use Bright Bold` on (its
default, above), the bold slot is already painted as the twin, and hovering a
focused button with a standard-slot label shows no change. An unfocused label
is not bold, and on the hosts that treat bold as a weight the twin is a step
wherever the profile paints it differently from its slot. Inferred from the
table above; not measured on a hovered control.

**Under a bold legibility weight (2026-10-13).** `\.legibilityWeight == .bold`
draws every piece of text bold (decisions B2), and only text: never a border, a
bar, a glyph or a picture, so the rule above about decorative bold still holds
for all of those. It is not decoration — it is the weight the app asked for —
so a label drawn in one of the sixteen named colours is painted in its bright
twin on a host that brightens bold (iTerm2 by default), and a hover's lift on it
shows no change there, as for a focused button's label above. Colours stated as
`38;2` or `38;5;n ≥ 16` keep their colour. Inferred from the table; not measured
under the setting.

### Reverse video (SGR 7) — cursor behaviour measured 2026-09-14; paint measured 2026-09-19

**Status:**
- **Measured:** SGR 7 printed nothing, and text under it advanced exactly as
  plain text. The hosts were Apple Terminal 455.1, iTerm2 3.7.1, Warp
  v0.2026.09.02.08.27.stable_01, and GNU screen 4.00.03 and tmux 3.7c, both
  inside Apple Terminal; and Ghostty 1.3.1 on 2026-10-19.
- **Measured 2026-09-19** — what a reversed cell PAINTS, read by eye off
  `Tools/TerminalProbes/reverse_video_card.py` by the owner, in six hosts.
  **iTerm2, Ghostty and Warp render the card correctly** on every row.
  **Apple Terminal does not, raw or under GNU screen** — and the fault is in the
  card's REFERENCE column, not in SGR 7. Under tmux the same card is correct.
- **Ghostty:** measured for paint on 2026-09-19 (correct), and for the cursor
  half on 2026-10-19 (the row below; record
  `Tools/TerminalProbes/data/ghostty-1.3.1-m3m7.json`).

**What Apple Terminal actually showed** (owner's reading): row A's reference is
missing its background colour, row C's reference is neither reversed nor bold,
and row D's reference is missing its background colour. Those are exactly the
three rows whose reference is spelled in **24-bit colour** — A and C from the
host's own OSC 10/11 answer, D swapping two `48;2;…` values — which is why the
reversed half of every row is fine and only the comparison is broken.

**Why, measured the same day** with `scratchpad/faint-probe.command`, four
readings from one screen:

| spelling | Apple Terminal paints |
|---|---|
| `ESC[2m` (faint) | faint text |
| `ESC[38;2;200;30;30m` | **identical to `ESC[2m`** — faint, no colour |
| `ESC[48;2;200;30;30m` | **identical to `ESC[2m`** — faint, no background |
| `ESC[38;9;99m` (non-`2` sub-parameter) | normal text — so it is the `2`, specifically |
| `ESC[38;5;160m`, `ESC[48;5;160m`, `ESC[41m` | correct colour |
| `ESC[38;2;…m` then `ESC[31m` | **washed-out** red, not red — the faint PERSISTS |

So the `2` of a truecolor introducer lands as **SGR 2 (faint)** and stays latched
until something resets it. That is a stronger statement than "the sequence is
ignored": it actively dims, and it contaminates the colours set after it.

**SGR 7 itself is not implicated on Apple Terminal.** In the same probe
`ESC[7;1m` reversed and emboldened correctly. What the card cannot do there is
build a reference to compare against. Under tmux it can, because tmux converts
24-bit for the host it is drawing through (see the tmux section); GNU screen does
not, which is why screen reads the same as raw.

**Consequence for the card, not for the framework.** `ColorDepth.detect()` reads
`COLORTERM` then `TERM`; Apple Terminal sets `TERM=xterm-256color` and no
`COLORTERM`, so TUI resolves `.palette256` there and never emits a truecolor
introducer to it. The card does, deliberately, to build an exact reference — and
that is the one thing this host cannot be asked for.

**Why it is recorded.** Today the framework emits SGR 7 only for
`Text.inverted()`, and for a cell composited over or under one where the
terminal's pair is unreported (2026-09-15): the compositor reads a reversed cell
with its colours exchanged, and states that pair with the 7 again where 39 and 49
cannot state it without (`Opacity as composition` §85). That relies on the 7
exchanging the pair in force, below — and so does the other direction: a
dissolve (`.transition(.opacity)`) DROPS the 7, with the glyph, where the pair
a reversed cell would show has faded to that unreported page, since reversed
over the terminal's own defaults it would paint a full-strength bar of its
foreground (§91). It is also in the output path's vocabulary
("SGR codes the output path emits", below), which never emits `27` and restates
from `ESC[0m` instead. And, since 2026-09-15, for a highlight whose colours it
cannot measure, below. And, since 2026-09-26, for a cell composited over a
reversal of the terminal's own ink, whose field only a 7 over 39 can show
(`Opacity as composition` §107; card rows I and J). So what each host paints for
SGR 7 is now relied on.

**What the framework draws reversed.** A highlight is a tint of a palette role
over the page, and where that tint or the page has no RGB — the terminal's own
foreground or background, or one of its sixteen slots, until it reports them —
no share of the blend can be drawn at all (`Opacity as composition` §75, §86).
Reverse video is drawn instead, because it is legible whatever colours the host
keeps there:

| Site | Where the colours cannot be measured | Otherwise |
|---|---|---|
| A `List`'s or a `Table`'s cursor row, selected or not | a steady `ESC[7;<ink>;<field>m` over the palette's own ink and page, restated after every reset in the row, keeping its ● | the accent's breath over the page on a selected row, the focus wash's breath on one that is not, under `.rowSelectionIndicator(.hidden)` too |
| A selected row that is not the cursor; an alternating row | nothing at all: the ● says which row is selected | a tint of the accent over the page |
| A text input's selection (`TextField`, `SecureField`, `TextEditor`) | `ESC[7;<ink>;<field>m` over the cell's OWN pair: the field's ink and its well | the accent at 60% over the well |
| A block text caret | the cell under it with its reversal flipped — a plain cell reversed, a selected cell's reversal taken off. A blink alternates the two; a pulse holds one | the caret's colour with the character punched out of it in the well |
| A menu's highlight bar (a pop-up `Menu`, a `.contextMenu`, a `Picker`'s drop-down, a combo box's suggestions) | a steady `ESC[7;<ink>;<field>m` over the palette's own ink and page, restated after every reset in the row. A drop-down reverses its interior only: its frame and its scrollbar column are chrome | the accent's breath over the page |
| A menu row under the pointer | nothing: its wash is the page there, and the label's ink lifts instead | a quiet accent tint over the page |
| A date field's active component (`DatePicker`) | `ESC[7;<ink>;<field>m` over the palette's own ink and page, keeping the component's underline. Never a BARE 7 here: that would exchange the terminal's defaults and collapse to dark-on-dark on a mid-tone theme | the accent's breath as a block, with the digits punched out of it |
| A `NavigationSplitView`'s focused or dragging divider, and the sidebar toggle's edge column | `ESC[7;<ink>;<field>m` over the palette's own ink and page, cell by cell down the column; the grip dots and the ◀ come through in the page's colour on a bar of the foreground's | the accent's breath filling the column |

**A 16-colour row breath (since 2026-09-29).** On a 16-colour terminal a `List`'s
or a `Table`'s row fills are slots of the table the host REPORTS (OSC 4), or of
xterm's until it has reported one. The shipped palettes carry picks for xterm's
default table and for Apple Terminal 455.1's "Basic" (above); any other table, and
every other palette, is placed by the row-fill rule against the table reported.
Sixteen slots are sometimes too few to keep the selected row, the cursor row and
the selected cursor row apart, and then one end of a cursor row's breath is
reverse video: on those frames the row is `ESC[7;<ink>;<field>m` over the
palette's own ink and page, with every colour the row's content states dropped
first, so the whole row is the text's colour and everything on it — text,
secondary text, the ●, a badge — the page's. The other frames are an ordinary slot
fill. Of the shipped palettes: Violet on Apple's table, White and Red Sands on
xterm's. A menu's bar, a drop-down's highlighted row, a date field's active
component and a split view's active divider breathe the same way (the selected
cursor row's breath, which on Red Sands reverses).
What a host paints for it is what the card's rows A, B and D ask, and what
`Tools/TerminalProbes/breath_card.py` shows with the exact frames. **Read
2026-09-30** on Apple Terminal 455.1, iTerm2, Ghostty 1.3.1 and Warp, each in its
own profile, from full-screen captures (a window capture timed out on every
host):

| Host | Reversed frame | Fill frame | Verdict |
|---|---|---|---|
| Apple Terminal 455.1 (Basic) | one light-grey band, every glyph (●, secondary text) red | the blue fill, white text, the ● yellow | as intended |
| iTerm2 | one light-grey band, every glyph red | the blue fill; the secondary text (bright black) is faint on iTerm2's lighter blue | as intended; the faint secondary is the fill frame's, not the reversal's |
| Warp | one near-white band, every glyph Warp's magenta | a light blue fill, and Warp recolours ALL its text dark, the ● included — its own contrast handling, not the frames | legible both ways |
| Ghostty 1.3.1, default config | one light-grey band, every glyph red | xterm's picks: slot 4 is Tomorrow Night's steel blue `#81a2be` and the white text on it all but vanishes | xterm's picks do not hold here — but they are not what TUI draws on Ghostty, which reports its sixteen (OSC 4) and so gets fills placed against them. `breath_card.py --host ghostty` shows rule.py's picks for that table (page bright red, text white; F = bright black ↔ reverse, B = reverse ↔ black; blue unused), and those read cleanly: text 3.4:1 on the bright-black fill, 9.8:1 on the black |

Without colour, every host tells the bold+reversed frame from the reversed one at
a glance (a heavier glyph on all four; iTerm2's is also whiter), and both stand
apart from a plain row. Not read: an app actually capped to 16 colours on Ghostty
drawing these rows — the Ghostty rows on the card are derived from rule.py, not
captured from the framework.

The trigger is those colours and never the terminal's silence: a palette of
ordinary RGB roles keeps its tints on a host that answers nothing. The one other
trigger is a terminal that draws no colour at all (`ColorDepth.noColor`, e.g.
`TERM=dumb`), where a fill is nothing: there a list's or table's cursor row, a
menu's or drop-down's bar, a date field's active component and a split view's
divider reverse (since 2026-09-29; before, a cursor row there looked like every
other row). A list's or table's cursor row, a menu's bar, a drop-down's highlighted
row, a date field's active component and a split view's active divider there
breathe by weight — reversed on every frame, bold on the
bright ones — on every host TUI identifies, since each
draws bold visibly (the bold/bright card above: iTerm2 brightens, Apple Terminal,
Ghostty and Warp thicken, tmux passes it through). On an unidentified host it holds
still, reversed. How a host paints bold under reverse video without colour
was read on the same card (above): heavier on all four. The ink and
the field are stated beside the 7 for the reason ECMA-48 gives below — a bare 7
exchanges the pair IN FORCE, so a row's padding, which follows its content's
last reset, would fill with the terminal's own foreground on a page the palette
paints. What a host actually paints for such a row or cell is what the card's
rows A, B and D ask, and they are UNMEASURED on every host.

**What follows from the sequence itself, on any host.** ECMA-48 calls SGR 7
"negative image", conventionally drawn by exchanging the foreground and
background colours.
- It exchanges the colours in force. Where no colour is stated, those are the
  terminal's own default pair, not an application palette's. So an app that
  wants its own pair reversed has to state both colours beside the 7.
- `ESC[0m` ends it, and so does `ESC[27m`. So a run that resets part way has to
  state the 7 again after the reset.

Whether each host paints exactly that is what the card's rows A, B, D, G and H
check, below.

**Provenance.**
- macOS 15.7.9 (24G830), system appearance Light, on the virtual Mac above.
- **The probe** is `osc_colour_probe.py` run with `PROBE_SUITE=m3m7`, the suite
  it carries for mode 2031 and SGR 7. Its records are not committed, as that
  probe's own are not (see the probes' README).
- **How a step is judged:** by the cursor, read from the reply to a `CSI 6n`
  sent behind the step. A step counts as "printed" when the cursor is not where
  the step should leave it: at its starting point, or two columns right of it
  for a step that writes `ab`.
  - Output that does not move the cursor goes unseen.
  - Under screen and tmux, the report comes from the multiplexer's own grid,
    not the outer terminal's.
- **The four spellings:** A `ESC[7m`, B `ESC[7;31;44m`, C `ESC[7;1m` and
  D `ESC[7;38;2;10;20;30;48;2;200;200;200m`.
- **The steps.** For each spelling:
  1. the SGR alone;
  2. DECRQSS for SGR (`DCS $ q m ST`), where that is safe to send;
  3. `ESC[0m`;
  4. the SGR, then `ab`, then `ESC[0m`.

  After all four: `ESC[7m ESC[27m`, a bare `ESC[m`, and DECRQSS once more.
- No fence timed out.
- **Where iTerm2's record came from.** Its `open -a iTerm` launch of a
  `.command` file, at about 12:09, raised what looked like an alert, and nothing
  ran within 40 s. The record is timestamped 12:24:48. It carries iTerm2's own
  environment (`TERM_PROGRAM=iTerm.app`, `TERM_PROGRAM_VERSION=3.7.1`,
  `ITERM_PROFILE=Default`). As in the colour-query passes, nobody noted who
  dismissed the window.

| Host | The SGR alone; `ESC[0m`; `ESC[7m ESC[27m`; bare `ESC[m` | SGR, `ab`, `ESC[0m` | DECRQSS `DCS $ q m ST` |
|---|---|---|---|
| Apple Terminal 455.1, "Basic" | nothing printed; the cursor stayed put | exactly +2 columns, all four spellings | not sent: this host prints DCS payloads (see "Apple Terminal parses OSC and does NOT parse DCS or APC") |
| iTerm2 3.7.1, profile "Default" | nothing printed; the cursor stayed put | exactly +2, all four | answered, ST-terminated, in 7–15 ms; the replies are below |
| Warp v0.2026.09.02.08.27.stable_01 | nothing printed; the cursor stayed put | exactly +2, all four | silent, 5 of 5; nothing printed |
| GNU screen 4.00.03, inside Apple Terminal 455.1 | nothing printed; the cursor stayed put, in screen's grid | exactly +2, all four | not sent: screen passes a DCS payload to its outer terminal |
| tmux 3.7c, inside Apple Terminal 455.1 | nothing printed; the cursor stayed put, in tmux's grid | exactly +2, all four | `ESC P 0 $ r ESC \`, 5 of 5, in ~0.03 ms. `0` means "invalid request", so tmux does not report SGR state |
| Ghostty 1.3.1 (2026-10-19, macOS 15.8.1) | nothing printed; the cursor stayed put | exactly +2, all four | answered, ST-terminated, 5 of 5, in 0.03–0.07 ms; the replies are below |

**iTerm2 reports a reversed pair already exchanged, and the 7 as well.** Its
DECRQSS replies, verbatim:

| State set | iTerm2's reply |
|---|---|
| `ESC[7m` | `ESC P 1 $ r 0;7m ESC \` |
| `ESC[7;31;44m` | `ESC P 1 $ r 0;34;41;7m ESC \` |
| `ESC[7;1m` | `ESC P 1 $ r 0;1;7m ESC \` |
| `ESC[7;38;2;10;20;30;48;2;200;200;200m` | `ESC P 1 $ r 0;38:2:1:200:200:200;48:2:1:10:20:30;7m ESC \` |
| `ESC[m` | `ESC P 1 $ r 0m ESC \` |

- Asked for 31 on 44 with 7, it reports 34 on 41 with 7.
- The 24-bit pair also comes back exchanged, in the colon form with colour
  space 1.
- Replayed as SGR, the reply would reverse the pair a second time.
- Whether iTerm2 stores the pair exchanged or only reports it that way, the reply
  cannot say. What it paints is the question of the card's rows B and D.
- TUI never sends DECRQSS, so nothing reads this today.

**Ghostty reports the state as it was set, the 7 included** (2026-10-19):

| State set | Ghostty 1.3.1's reply |
|---|---|
| `ESC[7m` | `ESC P 1 $ r 0;7m ESC \` |
| `ESC[7;31;44m` | `ESC P 1 $ r 0;7;31;44m ESC \` |
| `ESC[7;1m` | `ESC P 1 $ r 0;1;7m ESC \` |
| `ESC[7;38;2;10;20;30;48;2;200;200;200m` | `ESC P 1 $ r 0;7;38:2::10:20:30;48:2::200:200:200m ESC \` |
| `ESC[m` | `ESC P 1 $ r 0m ESC \` |

- The pair is not exchanged: 31 on 44 with 7 comes back as 31 on 44 with 7.
- The 24-bit pair comes back in the colon form with the colour-space field
  empty (`38:2::10:20:30`), where iTerm2 writes `1` there.
- So iTerm2 and Ghostty answer the same question two ways, and a reader of the
  reply would have to know which host it asked.

**What a reversed cell paints: UNMEASURED on every host.** Screen capture on
this machine returns only the wallpaper, so nobody has seen the card in a real
terminal. Each row is a question the card asks, and it is answered by eye:

| Card row | Question | Apple Terminal 455.1 | iTerm2 3.7.1 | Ghostty 1.3.1 | Warp 0.2026.09.02 | screen 4.00.03 | tmux 3.7c |
|---|---|---|---|---|---|---|---|
| A `ESC[7m` | ground in the default foreground, glyphs in the default background? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| B `ESC[7;31;44m` | the same cells as `ESC[34;41m`? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| C `ESC[7;1m` | does bold change the ground, the glyphs, or neither? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| D the 24-bit pair | the same cells as the pair exchanged? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| E `ESC[7;1;31;44m` | the same cells as `ESC[1;34;41m`? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| I `ESC[7;39;48;2;200;40;40m` | ground in the default foreground, glyphs red, as the reference from OSC 10? (a cell over a reversal of the terminal's own ink, 2026-09-26) | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| J the same, bold | does bold change the ground, the glyphs, or neither? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| F `ESC[K` while reversed | do the erased cells take the reversed ground? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| G `ESC[27m` part way | reversed up to it, plain after? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| H `ESC[0m` after a reversed pair | nothing left over? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| keys 1–6 | the terminal's cursor visible over a reversed cell, and the cell readable? | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |

A reading goes into this table with the host's version, its colour profile or
theme, and the date.

**Warp's minimum contrast, on and off: UNMEASURED.** At its default,
`only_named_colors` (see "A host may recolour a foreground it cannot read"),
Warp may lighten a named foreground. Which of a reversed cell's two colours it
treats as the foreground is unknown. Reading the setting "off" would mean
changing a Warp preference, and that is for the owner to do.

**Not measured, and why:**
- **Ghostty 1.3.1, until 2026-10-19:** two launches with
  `open -na Ghostty.app --args -e <script>` on 2026-09-14 each opened a window
  but started no child, so the probe never ran: Ghostty asks before it runs a
  script path it has not run before, and nobody answered. The 2026-10-19 run
  went through a script path it had been allowed to run.
- **Not captured:** what tmux sends its outer terminal during these steps.
- **Not attempted:** screen or tmux inside iTerm2, Warp or Ghostty, and ssh.
- **Hyper:** dropped from these measurements.

### The three colour spellings are not equally literal

| what we emit | what the terminal does with it |
|---|---|
| `SGR 30–37` / `90–97` (the 16 slots, `Color.ansi(_:)`) | Looks up slot *n* of the **user's colour scheme**. "Red" is a name, not a colour, and the user may make it green. |
| `Color.red`, `.white`, `.gray` and the other named colours | Not slots: they are RGB, Apple's light or dark values by the colour scheme where they are drawn, so they emit the 24-bit row below, and on a 16-colour terminal they are quantised to the nearest slot like any other RGB: nearest to the colours the terminal reported for its slots, or by xterm's table while it has reported none. Only `Color.ansi(_:)` (or a 256-colour index below 16) asks for a slot. |
| `SGR 38;5;n` (256-colour) | Slots 0–15 are the same sixteen, so they are remapped identically. 16–231 (the 6×6×6 cube) and 232–255 (the grey ramp) are conventionally fixed — but `OSC 4` can set any index, so "conventionally" is the strongest word available. |
| `SGR 38;2;r;g;b` (24-bit) | The colour is stated exactly and there is nothing to look up. It can still be *adjusted* — iTerm2's minimum-contrast setting will move a foreground it judges illegible against its background, and a terminal applying a colour profile shifts everything. |
| `SGR 39` / `49` (default fg/bg) | The user's configured default. This is what ``Color/default`` means, and it is the only spelling that is *defined* as "whatever the user chose". |

### Why this is load-bearing rather than trivia

`ANSIColor.xtermRGB` carries xterm's conventional table — and its doc comment
says so. Two things derived real decisions from it:

- **The contrast floor.** `ensuringContrast` computes a WCAG ratio, which needs
  luminances, which need RGB. Against a remapped scheme the ratio it computed
  was not the ratio on screen. **Since 2026-09-15 a slot no longer measures as
  xterm's table.** `Color.ansi(_:)` and `Color.palette256(0...15)` measure as the
  colour the terminal reported for the slot, which the startup exchange asks
  for (see "Asking the terminal for its colours"), and as nothing until it has
  reported all sixteen. A floor, a blend and a focus breath then read the
  terminal's own sixteen, or leave the slot as asked. A floor never re-spells a
  slot as RGB: one that falls short becomes its bright twin, 39, or slot 0, 7,
  8 or 15, or stays, whichever reads best ("What that costs, computed", above).
  A hover never re-spells a
  slot as RGB: it climbs from a standard slot to its bright twin to 39, and once
  the terminal has reported them takes a rung only if it is a visible step that
  reads no worse (Opacity as composition §82). On Apple Terminal
  "Basic", where 15 of the 16 differ from xterm's (above), that is the
  difference between measuring slot 1 as (205, 0, 0) and as (153, 0, 0).
- **Quantisation.** On a 16-colour terminal an RGB colour is drawn as the slot
  nearest to it by RGB distance. If the sixteen are not where the table thinks,
  the "nearest" one may not look nearest. (A 256-colour terminal is not
  affected: its search is over the cube and the grey ramp, 16–255, and never
  the sixteen.) **Measured, 2026-09-01:** quantising against Ghostty's real
  sixteen instead of xterm's table changes the slot chosen for **66.8%** of the
  RGB cube, and the colour actually painted lands **24% closer** in OKLab — the
  same 24% over the cube as over dark pixels alone. So the approximation cost
  about a quarter of the accuracy the mode is capable of. **Since 2026-09-15 RGB
  quantises to the sixteen the terminal reported**, once it has reported all
  of them, and by xterm's table until then: the same RGB distance, the lower
  slot on a tie, measured against what each slot paints. Computed with that
  rule from the reported tables in this document, over every fifth level of
  the cube (140,608 colours), the slot changes for 43.4% of them on Apple
  Terminal "Basic" and 46.6% on iTerm2 "Default", and the slot painted lands
  22.8% and 28.2% closer in OKLab. `Color.red`, (255, 59, 48), is SGR 91 by
  xterm's table and on "Basic", and 31 on iTerm2 "Default", whose slot 1
  (167, 69, 50) is nearer than its slot 9 (208, 126, 120).

xterm's table is kept where a number is needed before the terminal has
reported its slots: a colour editor's reading of a slot, an image palette's
match candidates, and quantising RGB to sixteen colours. Each takes the
reported slot once there is one. Until then they degrade rather than break,
because **an app cannot know the user's scheme unless it asks**, and a
terminal that does not answer `OSC 4` (Warp and GNU screen, measured) leaves
the slots unknown.

### What follows for the framework's own colours

A colour TUI chooses for the user — a focus highlight, a disabled label —
should not be a fixed ANSI slot, because the slot's appearance is not ours to
predict. It should be either a **palette role**, which the app's theme defines
and which resolves to something we did choose, or ``Color/default``, which is
explicitly the user's. Naming `Color.ansi(.blue)` and hoping is the one option
with no defensible reading. (This is the reasoning that re-pointed
``Color/primary``/``Color/secondary``/``Color/accentColor`` at palette roles;
see `Documentation/Historical/SwiftUI parity process/Completing the SwiftUI API.md` §1–2 for the decision.)

---

## OSC 8 hyperlinks — measured 2026-09-02

`ESC ] 8 ; <params> ; <URI> ST` attaches a destination to the cells that
follow, until `ESC ] 8 ; ; ST` ends it. What that buys a framework which
already handles clicks itself is that **the terminal now knows where those
cells point**, so the URI becomes something it can show and offer to copy
even though the label reads "Documentation" and the destination appears
nowhere on screen. No application can produce that; a click it handles
itself leaves the URL as invisible as it was.

Measured with `Tools/TerminalProbes/hyperlink_probe.py`, which asks two
different questions and can only answer one of them from inside.

### Safe: measurable, and it is the question that licenses emitting

A terminal with an OSC parser consumes the whole sequence whether or not it
implements the command — costing nothing, painting nothing. A terminal
**without** one prints the payload: the URI sprayed across the row, the
cursor left wherever that ended, and every later write on the row landing in
the wrong column. DSR sees that difference. Print a known-width label wrapped
in OSC 8, ask where the cursor is, and compare against the same label bare.

| Host | version | plain | with `id=` | BEL-terminated | bare close | unknown OSC command |
|---|---|---|---|---|---|---|
| Apple Terminal | 455.1 | swallowed | swallowed | swallowed | swallowed | swallowed |
| iTerm2 | 3.6.11 | swallowed | swallowed | swallowed | swallowed | swallowed |
| Ghostty | 1.3.1 | swallowed | swallowed | swallowed | swallowed | swallowed |
| Warp | v0.2026.08.26.17.59.stable_01 | swallowed | swallowed | swallowed | swallowed | swallowed |
| GNOME Terminal | 3.56.2 (VTE 8001) | swallowed | swallowed | swallowed | swallowed | swallowed |

Both screen buffers, every host, every spelling: the cursor lands exactly
where the bare label leaves it. The `unknown OSC command` column is the
control — a command number nothing implements — and it is the reason the
result generalises: these hosts swallow **any** OSC, so the answer is a
property of their parsers rather than of this one sequence.

**So being wrong about the second question costs a link that does nothing,
not a corrupted row.** That asymmetry is what lets the capability table be
generous, and it is the opposite of how the cursor-advance quirks work,
where being wrong corrupts output that was fine. See
`TerminalClient.honoursHyperlinks(_:)`, which says so at the code.

### Which gestures reach it — observed 2026-09-02, in a running TUI app

Not measurable from inside: the affordance is a mouse gesture over a live
terminal, which is exactly the gesture no probe in this directory can
perform. `hyperlink_probe.py`'s card asks a human, and this is that answer —
the project owner's, in each terminal, with a TUI app running and mouse
reporting held open. It **replaces** an earlier paragraph here that reasoned
from the mouse-event measurements instead and got the important one
backwards.

| Host | Click over an OSC 8 link | Seeing the destination | Shift-click |
|---|---|---|---|
| iTerm2 | **⌘-click: the terminal opens it** (asking which browser). Other clicks reach the application. | hold ⌘ and hover → the URL appears bottom-left of the window | selects text |
| Ghostty | — | hold ⌘-shift and hover → the URL appears | selects text |
| Warp | n/a (does not honour OSC 8) | n/a | selects text |

Three things follow, and the first is the one that was wrong before.

- **In iTerm2 the gesture chooses the opener, and the outcome does not reveal
  which.** ⌘-click is taken by the terminal; any other click is reported to
  the application — which, since 3a96d8fc, does NOT open it by default: it
  raises the destination popover, and opens through ``OpenURLAction`` only
  when the app or the user has said this session is local (the ssh paragraph
  below is why). When the application does open it, the browser that appears
  is identical either way, which is why this entry first read "the terminal
  opens it, on every modifier" — that observation was of the OUTCOME, and the
  outcome cannot tell them apart. Distinguishing them
  needs the application to say when it acted: `Example`'s Buttons & Links
  page now prints a line every time TUI does the opening, and that readout
  is the instrument this row should be re-measured with.

  It also means the two openers put the URL on **different machines** over
  ssh — see below.
- **Shift pressed partway through a reported drag — UNMEASURED.** A
  rectangular screen selection swaps which corner the pointer moves when a
  drag's motion reports start or stop carrying Shift (since 2026-10-17,
  `ScreenSelection.extend(to:shift:)`). Apple Terminal has no Shift bypass,
  so it should report the bit; whether a host whose Shift-drag is its own
  selection (Ghostty, Warp, kitty, xterm) keeps reporting a drag it began
  reporting once Shift goes down has not been probed.
- **Shift-click is NOT the bypass.** The xterm convention says shift means
  "handle this yourself, do not report it", and the earlier paragraph here
  recommended it on that basis. In practice Ghostty and Warp both take
  shift-click as *select text* — over OSC 8 links and over auto-detected
  ones alike — and iTerm2 opens the link. Nothing observed here treats it as
  a way to reach the application.
- **The destination is shown behind a modifier, not on plain hover.** Both
  hosts that honour OSC 8 reveal the URL while a modifier is held (iTerm2 ⌘,
  Ghostty ⌘-shift) rather than on hover alone. Ghostty's `link-previews`
  setting has an `osc8` mode, but no unmodified hover preview was observed.

### Which MACHINE opens it — the axis this table was missing

`OpenURLAction` runs `/usr/bin/open` or `/usr/bin/xdg-open` (`SystemURLOpener`)
**on the machine the application is running on**. So the gesture above decides more than which
component acts:

| | terminal opens it | application opens it |
|---|---|---|
| local | the user's browser | the user's browser — indistinguishable |
| over ssh | **the user's browser** | the *server's* browser, or nothing at all |

Over a hop, the terminal taking the click is the only path that reaches the
user's own browser. The application path runs on the server, where
`xdg-open` ships in `xdg-utils` — a **desktop** package, absent from Debian
and Ubuntu server images, Fedora minimal, Alpine and every distroless image.
Where it is absent, `SystemURLOpener.open`'s loop body never executes and **nothing is
spawned at all**: no process, no output, no trace. Where it is present on a
headless box it exits 3 into a `/dev/null` stderr, which the doc comment on
`SystemURLOpener.open` explains — an `xdg-open` complaint would otherwise land mid-frame
at the renderer's cursor. Both failures are therefore silent by construction,
and the keyboard route (Enter on a focused link) is *always* the application
path, so it never reaches the user's browser over ssh at all.

**As of 2026-09-03 TUI does not take the application path at all.**
`OpenURLAction`'s system opener is gated behind
`TerminalClient.urlOpeningSupport` / `TUI_OPEN_URLS`, and both default to
off. The reasoning is that the framework cannot tell which machine it is on:
`SSH_CONNECTION`, `SSH_TTY` and `SSH_CLIENT` are reliable when PRESENT and
prove nothing when absent — gone under `sudo` and `su`, and a tmux, screen or
zellij session started before the hop, or reattached after it, carries the
environment of whenever it began rather than of the client now looking at it.
No escape sequence asks a terminal which machine it is on. And the two wrong
answers do not cost the same: guessing local when remote sends somebody's URL
to a machine they are not at and leaves it in their history, while guessing
remote when local costs a copy and paste.

So the terminal's column above is the only one TUI relies on, and a `Link`
is not silent as a result: it carries the OSC 8 escape where the host honours
one, and activating it raises a popover with the destination to read and copy
(`LinkDisplay`). An app that knows it is local sets `urlOpeningSupport = true`;
a user answers for their own session with `TUI_OPEN_URLS=1`; and an app
with its own opening handler is not gated at all, because what is gated is
only the framework launching a process on the user's behalf. That launcher is
injected (`URLOpenerBackend`), and only the app's run loop installs it, into the
`TUIContext` `AppRunner` creates: a headless run, a `renderOnce` snapshot or a
test hands a deferred URL to an in-memory opener and launches nothing,
whatever the setting. The run loop also publishes it for the length of the run
(`TerminalURLOpening.runLoopOpener`), so an `OpenURLAction` the app made
itself and calls directly, which no environment handed an opener, reaches it
too.

**The remedy that already exists** for the escape is identification, not code:
`TERM_PROGRAM`
does not survive an ssh hop, so a terminal that would have got an OSC 8 escape
often falls to `.unidentified` and gets none. `TUI_HYPERLINKS=1` on the
remote host restores emission (`TerminalHyperlinkSupport.swift`), via `SendEnv`
/ `AcceptEnv` or a line in a remote profile. `LC_TERMINAL` survives the hop on
its own where iTerm2's shell integration is installed.

### Terminals also detect URLs in the TEXT, which is not this feature

Independently of OSC 8, these hosts scan displayed characters for things
that look like URLs and make those clickable too. It matters twice:

- A demo of "this text carries no hyperlink" must not be spelled as a URL,
  or the terminal linkifies it anyway and the demo shows the opposite of
  what it claims. `Example`'s Buttons & Links page uses ordinary words for
  exactly this reason.
- The modifier-hover readout distinguishes them: in iTerm2, holding ⌘ over
  an **OSC 8** link shows the destination bottom-left, and holding ⌘ over an
  auto-detected URL does not. So that tooltip is a usable oracle for
  "did the escape actually land", which is otherwise invisible.

### Honoured: not measurable from inside, and no query reports it

There is no escape sequence that asks. DA1, DA2 and XTVERSION say nothing
about it, no reply distinguishes a terminal that stored the URI from one
that discarded it, and the affordance itself is a mouse gesture the
application never sees. The probe therefore prints a card for a human and
records the answer beside the measurement rather than pretending to have
derived it. What the table below rests on instead:

| Host | Honours | Evidence |
|---|---|---|
| iTerm2 | **yes** | its own setting, `Drawing: Underline OSC 8 hyperlinks` (`underlineHyperlinks`); and tmux gives it the `hyperlinks` feature |
| Ghostty | **yes** | per-page hyperlink storage in its cell model (`cell_hyperlink`, "Maps cell positions to hyperlink IDs"); `link-previews` has an explicit `osc8` mode; and ⌘-shift-hover shows the destination (observed) |
| GNOME Terminal | **yes** | native VTE hyperlink support, honoured with Ctrl+click |
| tmux | **yes** | stores links in its grid, and `capture-pane -H` reads them back — the one machine-checkable oracle here |
| Apple Terminal | **no** | the app names no hyperlink handling at all; the sequence is swallowed and nothing is kept |
| Warp | **no** — deliberately, see below | the only hyperlink handling its binary names is bounded by `HighlightedLink is not within the alt screen` |

**Warp is a decided `false`, not an unknown.** It swallows the sequence like
the others, so emitting there would be safe; the reason not to is that the
alternate screen is the only buffer a TUI app ever draws into, and the
one string in Warp that bounds its link handling excludes exactly that.
Claiming a capability this framework's own users could not reach is worse
than claiming none — it turns "this terminal does not do that" into "this
framework is broken here". `TerminalClient.hyperlinkSupport = true`
(or `TUI_HYPERLINKS=1`) overrides it for anyone who finds otherwise.

### tmux honours it, and then decides who else may see it

`capture-pane -H` is the oracle: a pane sent `ESC]8;;https://example.com ST`
reports that URI back, and `capture-pane -F` flags the row `H`. The link is
stored whether or not any client is attached.

Forwarding is a separate decision. tmux sends hyperlinks only to clients
whose `terminal-features` include `hyperlinks`, which it derives from its own
table keyed on XTVERSION. Measured with tmux 3.7c, `-f /dev/null`, one
server per host:

| Client | `#{client_termtype}` | `hyperlinks`? |
|---|---|---|
| iTerm2 3.6.11 | `iTerm2 3.6.11` | **yes** |
| Ghostty 1.3.1 | `ghostty 1.3.1` | no — identified, and still given nothing |
| Warp | `Warp(v0.2026.08.26.17.59.stable_01)` | no |
| Apple Terminal | *(empty — answers no XTVERSION)* | no |

So a link inside tmux inside Ghostty is stored and never shown, until the
user says `set -ga terminal-features "*:hyperlinks"`. That is tmux's
decision and not one an application can override, which is why TUI emits
regardless: the link costs nothing where it is dropped and works wherever
the user has told tmux it can.

> **Measurement artefact worth knowing.** tmux's feature detection is
> asynchronous — it probes the client with XTVERSION after the attach. Asking
> `#{client_termfeatures}` immediately reports the terminfo-derived set and an
> EMPTY termtype, which is indistinguishable from a terminal that answers no
> XTVERSION. The first run of this measurement recorded iTerm2 that way. Sleep
> a few seconds after attaching before asking. (The same shape as the July
> reading in "Identifying the client terminal": an empty termtype is not
> evidence of anything.)

### Which terminator, and why the URI is re-encoded

`ST` (`ESC \`), not the `BEL` xterm also accepts. It is the form the
specification gives, it is what tmux writes, both were measured to be
swallowed everywhere above — and `BEL` would put a C0 control inside every
link, which `String.sanitizedForTerminalRow()` then has to reason about in
exchange for nothing.

The sequence **ends** at an `ESC` or a `BEL`, so a destination containing
either does not render oddly: it terminates the sequence, and the rest is
text the terminal draws. A URL is exactly the kind of value an application
builds out of data it did not author, so `TerminalHyperlink` percent-encodes
every byte that is not a printable non-blank ASCII character rather than
assuming the caller did. Same reasoning as `String.sanitizedForTerminal`:
the gate belongs where the escape is written.

**An escape the URI already has is kept (2026-10-05).** `Link` and a text
run pass `URL.absoluteString`, which Foundation has already encoded, so
`URL(fileURLWithPath: "/Users/x/Read me.txt")` arrives as
`…/Read%20me.txt`. The encoder used to encode every `%` as well, sending
`Read%2520me.txt`; a terminal decodes a URI once, so that named a file called
`Read%20me.txt` that is not there — every local path with a space or a
non-ASCII letter, and every `https` URL with an escape in it. Now a `%`
followed by two hex digits passes as it is, and only a `%` that cannot begin
an escape becomes `%25`. Encoding is idempotent as a result: a URI given
raw and the same URI given encoded both reach the host encoded once. An `id`
is opaque data rather than a URI, so there every `%` is still encoded.

### A `file:` link names its host, and an over-long URI is not wrapped — 2026-10-04

Two rules from the OSC 8 specification (egmontkob's gist) and Ghostty's VT
reference, adopted together (`Documentation/Terminals/Ghostty VT reference adoption study.md`, K5).
Both are read, not measured here; the card is `hyperlink_probe.py` with
`file://` rows on Ghostty, iTerm2 and kitty.

- **A `file:` URI must name a host.** `URL(fileURLWithPath:)` spells a local
  file `file:///path`, with an empty host, and Ghostty documents refusing such
  links, so a `Link` to a local file did nothing on the host that otherwise
  handles OSC 8 best. TUI now writes `file://<hostname>/path`, as the
  specification asks of applications: over ssh that names the REMOTE machine,
  which is what stops a terminal opening a same-named file on the user's own.
  `file:/path` (no authority at all) is rewritten the same way; `localhost`
  and any explicit host are left alone; so is a `file:` URI when the host name
  is unknown or is not a plain DNS name. The name is `gethostname()`, read once
  above the lower modules (`TerminalClient.localHostName`, in
  TUITerminalHost, a module of its own since module split step B2) and
  handed to
  `TerminalHyperlink` — the lower module never calls POSIX — rather than
  `ProcessInfo.hostName`, which may wait on a DNS lookup on macOS (a
  hypothesis; nothing here measured it).
- **A URI over 2083 bytes, after encoding, is not wrapped at all.** VTE and
  iTerm2 drop links that long, and Ghostty 1.1.1 fixed a crash on very large
  ones. The label still draws and activating it still raises the destination
  popover; only the terminal's own link is missing.
  `TerminalHyperlink.opening` is `nil` for such a destination, so every
  caller has to decide what to do without one.

**UNMEASURED: a host-named `file:` link on iTerm2.** iTerm2 honours OSC 8,
and until 2026-10-04 it was sent `file:///path`; it is now sent
`file://<hostname>/path`, the name being whatever `gethostname()` says
(`my-mac.local`, say). Whether it still opens that, or treats a host other
than `localhost` as remote — refusing it, or with shell integration
offering to fetch it over SCP — is not known. If it does not, a local
file link that worked on iTerm2 stopped working with this change, and the
rule needs an exception there. The answer is `hyperlink_probe.py`'s three
`file` rows (no host, the machine's name, `localhost`) run on iTerm2, owed
alongside Ghostty and kitty. Until it is recorded here, nothing about
host-named file links on iTerm2 is established.

---

## The window title: OSC 2, and its stack (XTWINOPS 22 and 23) — measured 2026-10-19

TUI titles the terminal's window, or tab, with the window in front's
title (`TerminalHostState`, refusal review P15; decisions O9, B-O9-13): its
scene's title, or a root `.navigationTitle` no top bar shows. What it sends,
and when:

| When | Bytes |
|---|---|
| The first title | `CSI 22 ; 2 t` (push the window title), then `ESC ] 2 ; title ESC \` |
| Another title | `ESC ] 2 ; title ESC \` alone |
| No title (a window with none in front), a suspend, the exit, a fatal signal | `CSI 23 ; 2 t` (pop), where it pushed |
| The first title after one of those | the push and the title again |

The title is UTF-8 with every control character dropped (a `BEL` or `ESC`
would end the OSC early) and line breaks as spaces. `OSC 2`, not `OSC 0`,
which sets the icon name as well; nothing is sent for an app that names no
title.

Measured with `Tools/TerminalProbes/title_probe.py` (records:
`Tools/TerminalProbes/data/*-title.json`): the cursor column after each
sequence on both screens (a moved cursor means the host printed some of it),
and the title as `CSI 21 t` reports it, after a set, a push and a set, and a
pop.

| Host | Every sequence swallowed, both screens | Reports the title (`CSI 21 t`) | Takes OSC 2 | Keeps the stack |
|---|---|---|---|---|
| Apple Terminal 455.1 | yes | no answer | unmeasured | unmeasured |
| iTerm2 3.7.6 | yes | no answer (default settings) | unmeasured | unmeasured |
| Warp v0.2026.09.30 | yes | no answer | unmeasured | unmeasured |
| GNOME Terminal 3.56.2 | yes | no answer | unmeasured | unmeasured |
| tmux 3.7c | yes | no answer; its `#{pane_title}` read instead | yes: the pane's title | **yes**: a pop restores the title before the push, and the last pop the pane's own |
| Ghostty 1.3.1 | not run (a new script path needs Ghostty's consent, with no one there to give it) | only with `title-report = true`, per its reference | — | — |

So the writes are **safe on every host measured**: nothing is printed, on
either screen, and a pop with nothing pushed is swallowed too. Whether the
GUI hosts show the title in the tab or window, and whether they keep the
stack, no answered query says; it is owed to a look, with
`title_probe.py --hold 20` holding the probe's title up. Where a host keeps
no stack, the pop does nothing and the app's title stays until the shell's
prompt sets its own, which shell integration does on every host that has it.

Under tmux the title is the PANE's (`#{pane_title}`); the outer terminal's
window changes only with `set-titles on`, off by default, as the Ghostty
adoption study (C2) expected.

---

## Progress and attention: OSC 9;4, OSC 9 and BEL — documented 2026-10-19, tmux measured

A terminal can draw an app's progress itself, outside its cells: a bar on
the tab, the window or the pane, seen from other tabs and windows too.
TUI puts a view's `.terminalProgress(_:)` there (`TerminalHostState`, on
the ledger the window title uses; the Ghostty adoption study, C3, step V8).
The sequence is ConEmu's progress report, `OSC 9 ; 4`. And it can ask for the
person's attention: `\.requestAttention` posts a desktop notification where
the terminal posts one (iTerm2's `OSC 9`), and rings the bell everywhere else
(C6, step V10; below).

### What TUI sends, and to whom

| When | Bytes |
|---|---|
| A view drawn states progress, and on a change of its state or its whole percent | `ESC ] 9 ; 4 ; s ; p ESC \` — `s` is `1` a value, `2` an error, `3` indeterminate, `4` paused; `p` is `0`–`100`, left out (with its `;`) for indeterminate, and for an error or a pause stated without a value |
| The bar has gone 5 s unsent, on any host but tmux | the same again, written between frames when no frame is due: nothing is drawn for it. Not under tmux, which keeps the bar with no time limit and passes a report the same as the bar on to no client (measured below), so the repeat would reach no terminal |
| No view drawn states progress any more; a suspend; the exit; a fatal signal (the signal debt) | `ESC ] 9 ; 4 ; 0 ESC \` |
| The first frame after a resume | the bar again |

Only to a host documented to take one (`TerminalClient.honoursProgressReports`):
Ghostty and iTerm2, which draw it, and tmux, which keeps it for the pane and
passes it on to a client that draws it. Elsewhere nothing is sent.
`TUI_PROGRESS=1` turns it on for any host, `0` off for every one. The
5 s is a margin inside Ghostty's limit (below); a host that keeps a bar
unprompted is sent the same dozen bytes again every 5 s, but for tmux, which
is sent none (it keeps the bar, and passes no repeat on).

**Whether the person sees it** is `\.terminalCapabilities`'
`.progressReports`, which an app reads to draw its own progress where the
terminal shows none: not supported wherever nothing is sent, supported on
Ghostty and iTerm2, and under tmux supported
only while every client attached has tmux's `progressbar` feature — the
clients tmux passes the bar on to (measured below). TUI asks tmux
(`#{client_termfeatures}`, in the `list-clients` it already runs to name the
clients) at launch and again whenever a client attaches or detaches, so the
answer changes while the app runs; a client that has not yet answered
XTVERSION but that its process names as iTerm2 is asked about again shortly,
since the answer is what earns it the feature. In Ghostty, Apple Terminal or
Warp under tmux it is `false` unless the user gives the client the feature.
The bar is sent to tmux whether or not a client draws it: tmux hands it to
one that attaches later.

### What each host documents

| Host | Draws it | Evidence | A bar no program updates |
|---|---|---|---|
| Ghostty 1.3.1 | yes, by default | `progress-style` (default `true`): "graphical progress bars using the ConEmu OSC 9;4 escape sequence" (its configuration reference, `ghostty.5`) | removed after about 15 s (its VT reference, as the adoption study read it, C3); unmeasured |
| iTerm2 3.7.6 | yes | an "Enable Progress Bars" setting, and its triggers' help text naming "the progress protocol (OSC 9;4)", both read from the app's binary; the setting's default is not read | unknown |
| tmux 3.7c | keeps a bar per pane, and passes it on to a client with the `progressbar` feature (iTerm2's, by its built-in table) | its manual: `#{pane_pb_state}`, `#{pane_pb_progress}` "(can be set by application)", and the `progressbar` terminal feature; measured below | kept (measured) |
| kitty 0.49.1 | yes, from 0.47.0 (`progress_bar`, default `top`) | its changelog and configuration reference. Not a host TUI models, so not sent; before 0.38 kitty posted every `OSC 9` as a notification, a report's digits included | unknown |
| Apple Terminal 455.1 | no | nothing in the app | — |
| Warp v0.2026.09.30 | no | nothing in its binary names the sequence | — |
| GNOME Terminal 3.56.2 | no | nothing in VTE draws OSC 9;4; sequences swallowed cleanly | — |

### Measured: tmux 3.7c, 2026-10-19 — `Tools/TerminalProbes/progress_probe.py`

In a pane (record: `data/tmux-3.7c-progress.json`):

- **Every spelling is swallowed**, on both screens: the cursor did not move.
- **tmux takes each as meant**, read back as its pane's bar
  (`#{pane_pb_state} #{pane_pb_progress}`): `normal 50`, `normal 0`,
  `normal 100`, `error 30`, `indeterminate`, `paused 70`, `hidden`.
- **A state sent without a value keeps the bar's value**: `9;4;2` after
  `9;4;2;30` is `error 30`, and `9;4;3` keeps it too. That is ConEmu's
  reading of a missing value, and what `.error(nil)` and `.paused(nil)` ask.
- **No timeout**: a bar sent once and left for 20 s was still up.

What tmux passes on (record: `data/tmux-3.7c-progress-forwarding.json`;
`--tmux-forwarding`, where the probe plays the terminal tmux draws in, and
runs itself in the pane to send every sequence):

- To a client whose terminal has the `progressbar` feature (`tmux -T
  progressbar`): every **change**, spelled with both parameters, a missing
  value filled in from the bar (`9;4;3;50` for `9;4;3` after `9;4;1;50`, and
  `9;4;0;70` for the removal). **A report the same as the bar is not passed
  on**: `9;4;1;50` sent twice, a second apart, reached the client once. So a
  report sent again to keep a bar up never gets past tmux, which keeps the
  bar itself.
- To a client without it: nothing.
- **A client that attaches later is handed the bar tmux keeps**: a pane put
  `9;4;1;50` up with no client attached, and a client with the feature that
  attached a second later received it (the record's `late_attach`).
- **tmux says which clients have the feature**: `#{client_termfeatures}`
  lists `progressbar` for the client given it and not for the other
  (`bpaste,ccolour,clipboard,cstyle,focus,progressbar,title` against the same
  without it). That is how an app asks tmux whether the person sees its bar.
- tmux gives a client the feature from its XTVERSION answer: iTerm2's and
  mintty's, by the table of terminals built into tmux 3.7c (read from its
  binary), and not Ghostty's, Apple Terminal's (which answers none) or Warp's
  ("Identifying the client terminal", under tmux). Inside tmux in Ghostty,
  Apple Terminal or Warp the bar is kept for the pane and shown nowhere until
  the user gives the client the feature
  (`set -as terminal-features ',xterm-ghostty:progressbar'`) — tmux's call, as
  with hyperlinks.

### Attention: a notification, else the bell

| When | Bytes |
|---|---|
| `requestAttention(message)`, on a host that posts notifications, with the next frame | `ESC ] 9 ; message ESC \`: the message sanitised as a title is (control characters dropped, line breaks and tabs as spaces), and after a space where it starts with a digit, so that no host reads it as a ConEmu command (`9 ; 4 ; …` is a progress report) |
| The same, anywhere else, or with a message that is nothing but spaces once sanitised | `BEL`, outside any string sequence |
| Several requests between two frames | each message once, in order; the bell once, with any a control rang for input it turned away |
| Requests made as the app quits | written in the exit's farewell, before the alternate screen is left |

Only to a host documented to post one (`TerminalClient.honoursNotifications`):
Ghostty and iTerm2. `\.terminalCapabilities`' `.notifications` says which
this is; `TUI_NOTIFICATIONS=1` sends notifications to any host, `0` keeps every
request to the bell. Nothing reports whether the person saw either.

| Host | Posts `OSC 9` | Evidence | The bell |
|---|---|---|---|
| Ghostty 1.3.1 | yes, by default | `desktop-notifications` (default `true`), "using certain escape sequences such as OSC 9 or OSC 777" (`ghostty.5`) | `bell-features`: by default bounces the Dock icon once while unfocused, and marks the tab's title with 🔔 until it is focused |
| iTerm2 3.7.6 | yes | the sequence is iTerm2's own; its triggers name a notification "posted by a control sequence (OSC 9)", and its default profile's notifications are on (`BM Growl`, in the app's `DefaultBookmark.plist`) | as its profile sets it; the default profile's keys: `Silence Bell` off, `Visual Bell` on, `Flashing Bell` off |
| tmux 3.7c | **no**: passes no `OSC 9` on (measured) | — | passes it on (measured), and marks the window |
| kitty 0.49.1 | yes (its desktop-notifications documentation, "the legacy OSC 9 protocol developed by iTerm2"); from 0.38 it drops one that starts `4;` | not a host TUI models: the bell | — |
| Apple Terminal 455.1 | no | nothing in the app | its profile's |
| Warp v0.2026.09.30 | no | nothing in its binary names the sequence | — |
| GNOME Terminal 3.56.2 | no | passes no OSC 9 notification | terminal bell |

Measured on tmux 3.7c with `progress_probe.py --tmux-forwarding` (record
`data/tmux-3.7c-progress-forwarding.json`): a pane's `OSC 9` reached neither
client, with the `progressbar` feature or without, and its `BEL` reached both.

### Owed

- **A look on Ghostty and iTerm2**: whether the bar appears, where, and how
  long one no program updates stays up (`progress_probe.py --hold 20`, and
  `--timeout 20`); and whether a notification appears
  (`progress_probe.py --notify`, which a host may first ask the person's
  permission for). Ghostty's run needs its consent for a new script path,
  with someone there to give it.
- **The leak check on the GUI hosts**: both screens, on Ghostty and iTerm2,
  which TUI sends it to, and on Apple Terminal and Warp, which it sends it
  to only under `TUI_PROGRESS=1`.

---

## Graphics protocols, and a parser gap — measured 2026-09-02, iTerm2's placeholders 2026-09-03, classic placements 2026-10-08

Full treatment, including what TUI should do about it, is in
`Documentation/Images and terminal graphics/Terminal graphics protocols.md`. Two facts belong here because
they are facts about the terminals rather than about a design.

### Apple Terminal parses OSC and does NOT parse DCS or APC

All three graphics protocols ride string-terminated escape families — DCS for
Sixel, OSC 1337 for iTerm2's, APC for Kitty's — so it is tempting to reason
that any terminal with an escape parser consumes them whole and ignores the
ones it does not implement. That is what all four hosts do with OSC 8
(previous section). Apple Terminal does it for **OSC only**.

Measured with `graphics_probe.py`: a payload printed between two brackets on a
cleared row, and the cursor asked where it landed.

| Payload | Apple Terminal 455.1 |
|---|---|
| OSC 1337 (161 B) | Δ0 — swallowed |
| DCS Sixel (25 B) | **Δcol +21 — printed** |
| APC Kitty (123 B) | **Δrow +1, Δcol +39 — printed** |

`ESC P` has its `P` consumed as though it were a two-byte escape and the rest
of the payload goes to the screen — exactly `25 − ESC − P − ESC − \` visible
cells. Same for `ESC _`. A page-sized image would be tens of kilobytes of
base64 across the screen.

**So a string-terminated escape is not automatically safe, and which family it
is decides.** The same parser weakness is already recorded here twice over:
`probe_stamp.py` skips DECRQM on Apple Terminal because it prints that query's
final byte, and this host is why. Anything DCS- or APC-shaped must be gated on
positive evidence.

The handshake therefore saves the cursor before its payload and restores it
and erases to the end of the screen after, for an unmeasured host with the
same gap. Since 2026-10-05 it saves with DECSC (`ESC 7`) and restores with
DECRC (`ESC 8`), not SCOSC/SCORC (`CSI s`/`CSI u`). Ghostty's VT reference
(read, not measured here) gives `CSI s` a second meaning: DECSLRM, set left
and right margins, whenever DEC mode 69 is on. Its reference also leaves to
the terminal whether SCORC restores the SGR state; DECSC saves position and
SGR on every VT100 descendant. No measured host leaves mode 69 on, so this
changes nothing seen today. The card that would show it is the graphics probe
re-run on Ghostty and Apple Terminal, expecting nothing printed
(`Documentation/Terminals/Ghostty VT reference adoption study.md`, K6).

The frame dump (`TUI_DEBUG_FRAME_DUMP=1`, the backtick key) made the same
swap later the same day for the notice it draws over the frame's top-left
corner. That one mattered more than cosmetically: the diff writer carries its
styling from one frame to the next, so a restore that left SGR reset by the
notice's own `ESC[0m` drew the next frame's carried styling wrong. DECRC
restores it, and the run loop also tells the writer to forget what styling
the terminal is in, so the next frame states it afresh whatever the host's
DECRC does. `TerminalOutputTests` pins the notice's bytes.

### What each host advertises

| Host | version | Sixel in DA1 | Kitty `a=q` | Kitty Unicode placeholder |
|---|---|---|---|---|
| Apple Terminal | 455.1 | no | silent | silent |
| iTerm2 | 3.6.11 | **yes** (`4` in `ESC[?64;1;2;4;6;17;18;21;22;52c`) | **`OK`** | **`OK`** — and draws, given the third mark (below) |
| Ghostty | 1.3.1 | no | **`OK`** | **`OK`** |
| Warp | v0.2026.08.26.17.59.stable_01 | no | **`OK`** | **refused, by name** |
| GNOME Terminal | 3.56.2 (VTE 8001) | no | silent | silent |
| tmux | 3.7c | **yes** (`ESC[?1;2;4c`) | silent | silent |

**iTerm2 needs the spec-optional third combining mark** (iTerm2 3.6.11,
measured 2026-09-03 with `Tools/TerminalProbes/placeholder_spelling_probe.py`).
The Kitty spec lets a placeholder cell omit the diacritic that carries the
image id's high byte, inheriting it from the cell to the left, and TUI did
omit it. kitty and Ghostty read a two-mark cell and a three-mark cell
identically; iTerm2 draws NOTHING for the two-mark cell and the picture for the
three-mark one, whichever way the foreground is spelled (24-bit, or the
256-colour form the spec's own example uses). The encoder therefore writes all
three marks on every cell — `KittyGraphics+Placeholders.swift` says so at the
line — and the section stamp above predates this row. iTerm2 is absent from the
advance table further down: its cursor advance over a placeholder row was not
captured, and the codepoint exemption applies to it regardless.

Warp's refusal is a named answer rather than a silence to be interpreted —
`InvalidKittyAction(InvalidControlData(UnicodePlaceholderUnsupported))` — which
makes the Kitty protocol the only terminal capability in this document that can
be interrogated **per feature** instead of looked up in a table keyed on an
identified host. A table written from Warp's feature list would have recorded
it as supporting placements.

**`XTGETTCAP Su` is not a Sixel signal.** iTerm2 answers `DCS 0 + r … ST` (not
present) while its DA1 advertises Sixel; Ghostty answers `DCS 1 + r 5375 ST` —
a success flag with no value — while supporting no Sixel at all. Use DA1.

### Deflated transmissions (`o=z`) — asked by the handshake; Ghostty acknowledges and draws them (measured 2026-10-19), the other hosts NOT YET MEASURED

TUI's startup handshake asks a second question since 2026-09-04: whether a
zlib-deflated transmission is understood. It transmits a 32×32 block as
twenty-six deflated bytes with `o=z` and `q=0`, and credits an `OK` under that
id (`TerminalGraphicsQuery.compressionProbeID`). The size is the honesty of
the probe — twenty-six bytes cannot be a raw 32×32 picture, so a host that
ignored the key would have to refuse it. Where it answers `OK` and the host
has a `libz` to borrow (`SystemZlib`), every image is sent deflated; a
gradient rendered as pixels shrinks by an order of magnitude, a photograph by
a little.

| Host | `o=z` acknowledged | deflated picture DRAWS |
|---|---|---|
| Apple Terminal | never asked (prints APC) | — |
| iTerm2 | unmeasured | unmeasured |
| Ghostty 1.3.1 | **yes**, 2026-10-19 | **yes**, the same as raw (the owner's reading, 2026-10-19) |
| Warp | unmeasured | unmeasured (draws no placeholders anyway) |

**Ghostty 1.3.1, 2026-10-19** (`graphics_compression_probe.py`, primary
screen, macOS 15.8.1; record
`Tools/TerminalProbes/data/ghostty-1.3.1-graphics-compression.json`). Every
command was acknowledged: the handshake's virtual placement
(`ESC _ G i=16777215;OK ESC \`), its twenty-six-byte deflated block
(`i=16777214;OK`), and both displays of the card's hue ramp, raw (`i=901;OK`)
and deflated (`i=902;OK`) — 24,576 bytes raw, 1,002 deflated. Both ramps
draw, and look the same (the owner's reading; the record's `rendered`
field). The first run, at 08:36, showed only the space the ramps took: the
probe deleted both images in the write that followed them, so nothing was
left to see. It now keeps them up until Return; the record is the 11:05
rerun, whose replies are identical.

Run `Tools/TerminalProbes/graphics_compression_probe.py` inside each host: it
asks both questions and prints the same ramp raw and deflated, one under the
other, for a person to compare. Until a host has a row here, the answer TUI
acts on is the host's own at startup — and `TUI_GRAPHICS_COMPRESSION=0`
turns it off for a host that acknowledges and then draws nothing.

### The image placeholder advances ONE cell, on every host — measured 2026-09-02, iTerm2 added 2026-09-04

U+10EEEE, the Kitty protocol's Unicode image placeholder, sits inside the
Plane-16 Private Use Area — the range this document records as painted two
cells and advanced one on every measured host, because that range is where SF
Symbols live. The placeholder is the exception, and it has to be, because
`FrameDiffWriter`'s Plane-16 compensation (`ECH` + glyph + `CUF`) applied to a
picture would move every column of it one cell further right than the last.

Measured with `Tools/TerminalProbes/placement_probe.py`: a row of twelve
placeholder cells written on a cleared row, with the cursor asked where it
landed, against twelve `x` characters.

| Host | plain text | placeholders, diacritics on every cell | placeholders, run-length elided |
|---|---|---|---|
| Ghostty 1.3.1 | 12 | **12** | **12** |
| Warp v0.2026.08.26… | 12 | **12** | **12** |
| Apple Terminal 455.1 | 12 | **12** | **12** |
| iTerm2 3.6.11 | 12 | **12** | **12** |

**Including the two hosts that do not implement the protocol.** No font carries
the codepoint, so it is not painted two cells the way an SF Symbol is; a host
that implements placements intercepts it, and one that does not draws nothing
and moves on. iTerm2's row was the gap this table carried as *not measured*
until 2026-09-04: run from inside an iTerm2 window, `placement_probe.py`
advances one cell per placeholder and draws the card correctly (hue L→R,
fade T→B) — so iTerm2's decode is specification-ordered and its only defect is
that it treats the spec-optional third diacritic as required (the desktop bug
report, and `KittyGraphics+Placeholders.swift`, cover that; the encoder writes
all three marks, so TUI is unaffected). Either way it is one cell, which is why the exemption is by
codepoint (`Unicode.Scalar.terminalImagePlaceholder`) rather than gated on
detection.

Three further things that run settled, each of which the encoder would
otherwise have had to guess:

- **Run-length elision works.** A cell with no diacritics continues the
  previous one; a 12-cell row costs a fraction of its explicit form. TUI does not
  use it — see `Documentation/Images and terminal graphics/Terminal graphics protocols.md` — because a
  self-describing cell survives being written out of sequence and an elided
  one does not.
- **Both id encodings work** — through the 256-colour foreground (`38;5;n`)
  and through a direct-colour triple.
- **Delete by id frees the image**: `a=p,U=1` on a deleted id answers
  `ENOENT: image not found` where it answered `OK` before. Ghostty
  acknowledges the delete itself with silence, so the placement request is the
  only usable evidence.

**Cost, Ghostty at 49×17 cells with 16×34-pixel cells:** a full-screen image is
1.8 MB of base64, transmitted and acknowledged in 43 ms. One-time per image and
size, not per frame.

> **`q=2` or the terminal talks back into your keyboard.** Every graphics
> command is acknowledged with `ESC_G…;OK ESC\` unless suppressed, and in an
> application those bytes arrive on **stdin**, where the input parser reads
> them as keystrokes. Anything on a render path sets `q=2`.

### Pixels of another aspect than their placeholder box — filmed 2026-10-28, Ghostty 1.3.1 and iTerm2 3.7.3

A Unicode-placeholder placement (`a=p,U=1,c=…,r=…`) of pixels whose aspect is
not the box's is fitted to the box with the pixels' aspect kept and centred,
in both: the part of the box the picture does not cover shows the cells'
own ground (the page's background, in the filmed scene), with no artefact at
the picture's edge. TUI relies on it for `.scaledToFit()` pictures, sent at
their own aspect (`Terminal graphics protocols.md`, §8, PICTURE-ASPECT).
Filmed with `Tools/ScreenClips --child aspectreview`; kitty and WezTerm not yet
checked.

### A line on a row boundary: Kitty classic placements — measured 2026-10-08, Ghostty 1.3.1 and iTerm2 3.7.3

Every separator TUI draws between rows costs a whole row:
`.listRowSeparator` puts its faint `─` rule on a line of its own. (A vertical
divider, a column of `│`, costs a column instead, and is not the question
here.) A Kitty **classic**
placement, drawn at the cursor and outside the cell grid (not the Unicode
placeholders `Image` uses, whose cells hold no text), could instead draw a
line one or two pixels thick on the boundary between two rows, at no cost in
rows. `Tools/TerminalProbes/hairline_probe.py` asks whether it can. Its
docstring states the plan and the kill criteria. The owner ran it
interactively, with every card answered, on macOS 15.8.1 (arm64), on the
alternate screen:

- `Tools/TerminalProbes/data/ghostty-1.3.1-hairline.json` (99 × 35 cells)
- `Tools/TerminalProbes/data/iterm2-3.7.3-hairline.json` (125 × 48 cells)

The line is one 2048 × 2 px strip (raw RGB, `f=24`), sent again on each card
(each card first deletes the previous card's lines; only Q6 places a line
again without re-sending, because that is its question) and placed
with `a=p,i,p,x=0,y=0,w,h=2,C=1,z,q=0` at the run's first cell on the
**lower** row, so that the line's top edge is the boundary. `w` crops the
strip to the run. 2 px is the probe's `max(1, cell height // 17)` at both
hosts' 34 px cell. Both hosts answered `a=q` with `OK`, and a placement of an
id never sent with `ENOENT`. So their `OK`s are evidence, unlike the xterm.js
beta's (xterm.js, "Graphics").

**Neither host meets a kill criterion.** On both, the line is drawn on the
boundary (Q1), shows in some layer (Q4), is removed by its `(i, p)` (Q6) and
stays steady with mode 2026 (Q7). The records name two changes to the plan.
Ghostty needs `z=+1` in place of the design's `z=-1`, and so needs the host
identified first (the record: "which needs an identity for it"). iTerm2 is
excluded until its pixel unit is known. A third item confirms the design
rather than changing it: cleanup must delete every line by id, which the
design already does, because on iTerm2 a line outlives `ESC[2J` and the
screen switch.

| Question | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| Q1 placement acknowledged | `OK` | `OK` |
| Q1 drawn, on the boundary | yes, yes | yes, yes |
| Q1 ends at its bars, within a pixel or two (40 columns, cropped `ws_xpixel × 40 // ws_col`) | yes, at 643 px | **no**, at 560 px |
| Q2 `C=1` holds the cursor (DSR before and after) | yes | yes |
| Q3 the unit, coarse | 16 px, by all three measures | **none found** |
| Q3 a fine line ends exactly at its bar | **neither of two (OPEN, below)** | neither of two |
| Q4 layering | `z=-1` not on every band; `z=+1` over the glyphs | `z=-1` on every band, under the glyphs; `z=+1` not over them |
| Q5 the line survives `ESC[2K` + text, overwriting, ECH + text | yes, all three | yes, all three |
| Q6 delete one by `(i, p)`, re-place without re-sending | yes | yes |
| Q7 steady at 60 Hz, without and with mode 2026 | yes, yes | yes, yes |
| Q8 after `ESC[2J` | line gone, strip freed | line gone, strip kept |
| Q8 after `?1049l`, then `?1049h` | line gone, strip freed | **line shown on the primary screen** and after the return; strip kept |
| Q8 image store | one per screen | one for both screens |
| Q9 resize | not judged | the line moved |
| Q10 SGR 4 + 58 underline colour; SGR 53 overline | grey; drawn | grey; **not drawn** |

#### The pixel unit, and where the line ends (Q1, Q3)

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| `TIOCGWINSZ` | 1592 × 1192 px | 1750 × 1632 px |
| `CSI 14 t` text area | 1584 × 1190 | 885 × 849 |
| `CSI 16 t` cell | 16 × 34 | no answer |
| Cell width: ioctl (integer), `CSI 14 t` ÷ columns, `CSI 16 t` | 16, 16.0, 16 | 14, 7.08, — |

The coarse check places a line 10 cells wide by each measure with `C=0` and
reads the cursor's advance. It catches a 2× error (points against device
pixels). Rounding up to whole cells hides anything finer.

- **Ghostty: the coarse unit is 16 px; the exact width is OPEN.** The three
  measures agree, and a 160 px line advanced the cursor 10 cells by each (the
  record's `unit_revealed_by` is the ioctl, which the probe names whenever the
  ioctl's measure is among those that agree, so it is no tie-break).
  `ws_xpixel` is 8 px more than the 1,584 px text area (99 × 16) that
  `CSI 14 t` reports, and `ws_ypixel` is 2 px more than 1,190 (35 × 34).
  Perhaps the ioctl's size counts the window's padding; no record measures
  padding. If a column is exactly 16 px, an n-column run is
  n × (`ws_xpixel` // `ws_col`) = 16n px wide, and the probe's crop rule,
  `ws_xpixel × n // ws_col`, runs long by up to 8n/99 px: 3 px at Q1's 40
  columns (643 against 640) and 7 px at Q3's 95. That is arithmetic, not a
  measurement, and the one direct reading of a 16n width contradicts it: Q3's
  line B, at 1,520 px, was judged not to end at its bar (below). The only
  "yes" on where a line ends is Q1's, for the probe's own 643 px, under a
  question that allowed "a pixel or two". The record recommends no unit:
  `q3_widths_ending_at_the_bar` is empty, and the probe went on cropping
  every later card by its own rule (`crop_from_here_on`).
- **OPEN, Ghostty Q3:** neither fine line was judged to end at its bar.
  Line A, `ws_xpixel × 95 // ws_col`, is 1,527 px. Line B,
  `95 × (ws_xpixel // ws_col)`, is 1,520 px, the width `CSI 14 t`'s and
  `CSI 16 t`'s measures also give. Each line starts at column 1's left edge,
  so with 16 px columns B ends exactly at the bar: the probe writes ▏ in
  column 96 (`self.text(upper, run + 1, "▏")`), so the bar's left edge is
  column 95's right edge. Three explanations fit, and
  the records cannot tell them apart: the host draws the bar somewhere else;
  the unit is not what it seems; or the yes/no judgement was off. Q1 asked
  for "within a pixel or two" and was answered yes for a line that, by the
  arithmetic above, runs 3 px past its bar, while Q3 asked for "neither short
  of it nor past it", with no tolerance. This is **unresolved**. The card asks
  only yes or no, so the record does not say whether either line fell short
  or ran past its bar. Either of two things would settle it: a zoomed
  screenshot of Q3's card on a re-run, whose pixel columns at the bar answer
  it outright, or a Q3 card that asks "short, exact or past" in place of yes
  or no.
- **iTerm2: no query reveals the unit.** The coarse check names none. A
  71 px line (10 × `CSI 14 t`'s 7.08) and a 140 px line (10 × the ioctl's 14)
  each moved the cursor from column 1 of its row to column 125, the last, of
  the next row. The record files that as "12.40x: unexplained". `ws_xpixel`
  is exactly 125 × 14, yet no line ended at its bars: not Q1's 560 px
  (40 × 14), not Q3's A at 1,694 px (121 × 14, which the ioctl's rule and its
  integer cell both give), and not B at 856 px (`CSI 14 t`'s measure). The
  record's plan change is to exclude this host.

#### Layering (Q4)

The card has four bands: the default background, a grey fill, a stripe and a
selection colour. Each band is a row of `gjpqy` over a row of
`│┼█▀ ÉÅ 😀`, with a line along the top of the lower row at three z values.
Every placement answered `OK` on both hosts.

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| `z=-1` shows on all four bands | **no** | yes |
| `z=-1`: `│ ┼ █ ▀` draw over the line | yes | yes |
| `z=+1` draws over those glyphs | yes | **no** |
| `z=-1073741825` (below INT32_MIN/2) shows on the default band only, as the spec says | yes | **no** |
| On the boundary, wherever the line shows | yes | yes |

The records do not say which band hid Ghostty's `z=-1` line. Nor do they say
in which direction iTerm2's lowest z departs from the spec. Ghostty needs
`z=+1` (the record's plan change, "which needs an identity for it"), so its
line crosses the top edge of the lower row's `│ ┼ █ ▀`. On iTerm2, `z=-1` is
the only z known to work. Its `z=+1` line was asked one thing, whether it
draws over the glyphs (no); nobody judged whether it shows on every band. If
it does, `z=+1` shows on every band on both hosts: over the glyphs on
Ghostty, as its plan change accepts, and under them on iTerm2, as the design
intends. So one z for both hosts is **untested**, not ruled out.

#### Rewrites, deletes and motion (Q5–Q7)

- **Rewrites keep the line on both hosts:** `ESC[2K` then text (the way every
  whole-line rewrite TUI sends begins), text written over it, and ECH then
  text. The untouched control row kept its line too.
- **Delete and re-place, both hosts.** `a=d,d=i,i,p` removes that one line
  and leaves the other. The same `(i, p)` placed again without re-sending the
  strip draws it back. That also works after both lines are deleted and the
  strip has no placement left, so neither host freed a strip for having no
  placement. The probe puts no quota pressure on the store, so this says
  nothing about eviction. Uppercase `d=I` frees the data: a placement after
  it answers `ENOENT`. Both hosts acknowledge that delete with silence, even
  at `q=0`.
- **Motion.** Both answer DECRQM `?2026` with `reset` (recognised, off), and
  `?2026h ?2026l` leaves the cursor where it was. Two coloured rows moved
  down and back three times at 60 Hz, 23 rows on Ghostty and 30 on iTerm2,
  one row per frame: the text first, then the same `(i, p)` placed again
  (`q=2`). The line stayed on its seam with no flicker, gap or tearing on
  both hosts, both with mode 2026 and without it.

#### `ESC[2J`, the alternate screen, and the image store (Q8)

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| After `ESC[2J`: the line visible | no | no |
| After `ESC[2J`: the strip re-placed by id | **`ENOENT`** (freed) | `OK` |
| After `?1049l`: the line visible on the primary screen | no | **yes** |
| After `?1049h`, back: the line visible | no | yes |
| After the round trip: the strip re-placed by id | **`ENOENT`** (freed) | `OK` |
| The strip sent again and placed | drawn | drawn |
| An image sent on the primary screen, placed from the alternate | `ENOENT` (`OK` back on the primary) | `OK` |
| Store | one per screen | one for both screens |

On Ghostty, `ESC[2J` and a screen round trip each take both the line and the
strip, and the strip has to be sent again on the alternate screen. On
iTerm2, `ESC[2J` hides the line and keeps the strip. A line placed on the
alternate screen shows on the primary one after `?1049l`, and is still there
after `?1049h`. So a line TUI fails to delete by id is left on the shell's
screen.

#### Resize (Q9)

iTerm2 went from 125 × 48 to 108 × 48 (`ws_xpixel` 1750 → 1512), and the
line **moved**. The card offered three answers: stayed on its boundary,
moved, or gone. The record does not say where the line went. On Ghostty the
card was skipped, so nothing was judged, although the readings show the
window going from 99 × 35 to 123 × 37.

#### Without graphics: SGR 4 + 58, and SGR 53 (Q10)

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| SGR 4 + `58;2;150;150;160`: a grey underline, not the text's colour | yes | yes |
| The colon form, `4:1` + `58:2::150:150:160` | yes | yes |
| That underline within a couple of pixels of the row below | can't tell | **no** |
| SGR 53: an overline along the top of the lower row | yes | **no** |
| Stray characters or styling (58 misread) | none | none |

#### Replies a parser must allow for

- iTerm2 answers the strip's chunked transmit, whose control keys ride on the
  first chunk only, with `i=0;OK` instead of the strip's id, so the records
  file those transmits as `silent`. It answers single-chunk transmits (the
  4 × 1 px scratch and store images) with their own id. Ghostty answers the
  strip with its id.
- Within a single run, iTerm2 writes a reply's keys in either order:
  `i=…,p=…` or `p=…,i=…`.
- The error text differs. Ghostty says `ENOENT: image not found`. iTerm2 says
  `ENOENT:Put command refers to non-existent image with id: … and number: 0`.
  Only the code before the colon is shared.

#### What a hairline layer needs on each host

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| z | `+1`, crossing the top of `│ ┼ █ ▀`; the host must be identified first | `-1`, the only z known to show on every band (`+1` per band unmeasured) |
| Crop unit | **OPEN**: 16n px, n × (`ws_xpixel` // `ws_col`), by arithmetic, but Q3's one direct reading of that width was "no"; Q1's "yes" was for `ws_xpixel × n // ws_col` | none found: exclude the host until one is |
| Re-send the strip | after `ESC[2J` and after every `?1049l`/`?1049h`; send it on the alternate screen (a store per screen) | neither `ESC[2J` nor the screen switch needs it (one store, kept) |
| Resize | not judged | the line moved (where to is not recorded); whether deleting it and placing it again puts it back is untested |
| Cleanup | delete every line by its id | delete every line by its id; a line left behind shows on the primary screen |

On both hosts, a strip with no placement left was placed again without being
re-sent (Q6), and `d=I` frees a strip's data.

#### What TUI draws — built 2026-10-24, from the records above; looked at live in Ghostty the same day

The `.hairline` list separator look (`ListSeparatorStyle`, decisions
A-D6L-2) draws on the hosts below. The table is the measured one above, and
nothing in it was re-measured for the prototype: the owner's look with
`Tools/TerminalProbes/hairline_review.py` is what confirms it. The owner
looked in Ghostty on 2026-10-24 (the Stress megalist): "The new KGP row
dividers look great in Ghostty!" — the 16n px crop reads right there, so Q3's
unit is settled for Ghostty by eye; iTerm2 and the rest stay unconfirmed.

| | Drawn | z | Crop of a run of n columns | Why |
|---|---|---|---|---|
| Ghostty (any version; 1.3.1 measured) | yes, where the handshake says it places pictures and `TIOCGWINSZ` reports pixels | `+1` | n × (`ws_xpixel` // `ws_col`) px — 16n on the measured window | the one host meeting every criterion; Q3's exact unit OPEN |
| iTerm2 3.7.3 | only under `TUI_HAIRLINES=1` | `-1` | the same rule: 14n px, which Q1 found short of the run | no pixel unit found (Q3) |
| kitty, WezTerm, Rio, Konsole, Warp, xterm.js, anything else | only under `TUI_HAIRLINES=1` | `-1` | the same rule | unmeasured (Konsole: `z<0` hidden under painted cells, source-read) |
| tmux, Apple Terminal | never by default | — | — | tmux keeps no placement; Apple Terminal prints APC |

What every drawn line is: a strip per colour, the screen's width by
max(1, cell height // 17) px (2 at Ghostty's 34), raw RGB (`f=24`, `o=z` where
the handshake took it), sent before the frame's synchronized hold; then, in
the hold, `CUP` to the run's first cell on the LOWER row and
`a=p,i,p,x=0,y=0,w,h,C=1,z,q=2`, so the line's top edge is the boundary, as
the probe placed it. A placement id is the screen row above eight bits and
the run's place in the row below. Each frame sends only what changed: a run
that moved is placed again under its `(i, p)`, one that went is deleted by
it (`d=i`), and a strip left with no placement is deleted (`d=I`) rather than
kept for quota eviction to take silently. A resize or a resumed suspend
deletes every strip and places every line again, which also covers Ghostty
freeing strips on `ESC[2J` and the screen switch. A suspend and a quit delete
every strip before leaving the alternate screen (iTerm2 would otherwise show
the lines on the shell's screen, Q8). A `SIGQUIT`'s farewell deletes images,
not strips: on Ghostty the screen switch frees them; under `TUI_HAIRLINES=1`
on iTerm2 a line can be left behind.

Open, to be read off the review: whether Ghostty's line ends short, exact or
past the run's last cell (Q3's OPEN item, now on TUI's own rows); and the
look beside the focused and selected rows, which draw no line.

---

### Resizing a virtual placement: name the placement — measured 2026-10-26, Ghostty 1.3.1 and iTerm2 3.7.6

A picture already in the terminal is resized by placing it again at the new
size (`a=p,U=1` with the new `c` and `r`) and drawing the new box's
placeholder cells: no pixels are sent. Whether a second placement REPLACES the
first depends on the spelling (`Tools/TerminalProbes/replacement_probe.py`,
one ramp image per panel, drawn in a 20 × 10 box):

| Panel | Ghostty 1.3.1 | iTerm2 3.7.6 |
|---|---|---|
| A — placed 10 × 5, then 20 × 10, no placement id | **first size kept**: 10 × 5 in the box's corner | fills the box |
| B — the same, placements deleted between (`a=d,d=i`, pixels kept) | fills the box | **draws nothing** |
| C — placed once at 20 × 10 (reference) | fills the box | fills the box |
| D — `p=1` both times, cells naming placement 1 (underline colour) | fills the box | fills the box |
| E — `p=1` both times, cells naming no placement | fills the box | fills the box |

So every virtual placement TUI makes names placement 1
(`KittyGraphics.placement(id:columns:rows:)`, since 2026-10-26), and a resize
is a second placement, which replaces it in both. Before, a picture growing
frame by frame in Ghostty — the Navigation clip's photo zooming into its
screen — stayed at its first frame's size while its cells grew; it went
unnoticed because a resize used to resample and re-send the picture under a
fresh id almost every time. kitty 0.49.1 is not measured (it needs OpenGL
3.3, which the VM the probe ran in lacks); the protocol says a placement
with an existing placement id replaces it, which is the behaviour E relies on.

### A picture under text: a classic placement at z=-1 — measured 2026-10-26, Ghostty 1.3.1 and iTerm2 3.7.6

A glyph over a frosted picture cannot be the picture's placeholder cell, so
TUI lays the picture under it instead, where the terminal can: a classic
placement of the frosted copy, cropped to the run of glyphs and scaled to its
cells, at `z=-1` (`Tools/TerminalProbes/frost_over_image_card.py`, panel D):

| Host | Result |
|---|---|
| Ghostty 1.3.1 | **Drawn exactly**: below the glyphs, above the cells' default field. A cell with any field of its own hides it, so the glyph's cell states the terminal's own (`ESC[49m`). |
| iTerm2 3.7.6 | **Refused** ("invalid payload"); its z order differs too (z=0 under text, z=-1 over a cell's fill — the hairline probe) |
| kitty 0.49.1 | not measured (no OpenGL 3.3 in the VM); the spec draws `z<0` as Ghostty does |

So only Ghostty does it unasked (`TerminalClient.picturesUnderTextSupported`);
everywhere else the glyph stands on the copy's average colour, a block behind
each letter. `TUI_PICTURES_UNDER_TEXT=1` tries it anywhere. Graphics notes
§14.5.

## Measured advance table (divergences and key rows)

DSR-measured on the ALTERNATE screen (the app's buffer). Terminal.app +
iTerm2 2026-07-13; Ghostty + Warp 2026-07-14; the bare-pictograph and
non-emoji rows re-measured across ALL FOUR on 2026-07-14 (Terminal.app
re-measured the same day too — identical, so the harness is
cross-validated). Every cell here is measured; none is inferred. Full battery in
`Tools/TerminalProbes/` (`PROBE_ALT=1`). Claim = `Character.terminalWidth`.
Terminal.app and Ghostty measure identically in both screen modes; iTerm2
and (much more so) Warp do NOT — always probe with `PROBE_ALT=1`. Ghostty's
column was measured again on 2026-10-19, mode 2027 set, on both screens
(`ghostty-1.3.1-advance.json`, `ghostty-1.3.1-alternate.json`): every row below
came back the same, and the two screens agreed on every row of the battery.

**Bold = diverges from the claim** (i.e. needs compensation, or shears).

| Cluster | Claim | Terminal.app 455.1 | iTerm2 3.6.11 | Ghostty 1.3.1 | Warp 2026.07.08 / 08.26 |
|---|---|---|---|---|---|
| `a`, `─`, `▒`, `■`, `⣿`, NFD `é` | 1 | 1 | 1 | 1 | 1 |
| CJK 中, `██`(2), `▐▌`(2) | 2 | 2 | 2 | 2 | 2 |
| ⬛︎ ⬜︎ (VS-15 chrome) | 2 | 2 | 2 | **1** | 2 |
| ⌚ ⌛ ⏩ ⏰ 👍 ✊ (emoji presentation) | 2 | 2 | 2 | 2 | 2 |
| ❤️ ✏️ ☎️ ☂️ ✔️ 🖥️ 🛡️ ⚙️ ⚠️ ✂️ ⚒️ (VS-16) | 2 | **1** | **1** | 2 | 2 |
| 〰️ 〽️ (EAW base + VS-16) | 2 | 2 | 2 | 2 | **3** |
| 🇺🇸 (flag pair) | 2 | 2 | 2 | 2 | 2 |
| 🇦 (lone regional indicator) | 2 | **1** | 2 | 2 | **1** |
| 1️⃣ #️⃣ *️⃣ (keycaps) | 2 | 2 | **1** | 2 | **3** |
| 1⃣ (bare keycap, no VS-16) | 1 | **2** | 1 | 1 | 1 |
| ⤷ *(modelled + pulled back with `CUB(1)` since 2026-08-28 — it used to fall through to the claim and mis-enter the FE0F form's store surgery)* | | ✓ | | | |
| 👍🏽 (SMP base + skin) | 2 | **4** | 2 (merged) | 2 (merged) | **4** |
| ✊🏻 (BMP emoji-pres. + skin) | 2 | **4** | **4** (swatch) | 2 (merged) | **4** |
| ☝🏽 (BMP text-pres. + skin) | 2 | **3** | **3** (swatch) | **1** | **3** |
| ☝️🏽 (…+ VS-16) | 2 | **3** | **3** | **4** | **4** |
| ⤷ *(normalized since 2026-08-28 — the redundant selector is stripped by the non-Apple walks, so what those hosts receive is the ☝🏽 row above; Apple's separation re-promotes it identically either way)* | | ✓ | ✓ | ✓ | ✓ |
| 👩‍🚀 / ❤️‍🔥 / 👩🏽‍🚀 (ZWJ) | 2 | **5 / 4 / 7** | 2 / **1** / 2 | 2 / 2 / 2 | **5 / 5 / 7** |
| U+100038 etc. (SF Symbols PUA) | 2 | **1** (paints 2) | **1** (paints 2) | **1** (paints 1) | **1** |
| 🏽 (standalone modifier) | 2 | 2 | 2 | 2 | 2 |
| 🖥 🛡 🕹 🕷 🎞 🏙 (bare SMP pictograph) | 2 | **1** | **1** | **1** | **1** |
| ⤷ *(compensated since 2026-07-14 — all four CUF)* | | ✓ | ✓ | ✓ | ✓ |
| 🁠 🂡 (domino / card — in-block non-emoji) | 2 | **1** | **1** | **1** | **1** |
| स्त्र ष्ट्र स्त्री (Devanagari conjuncts of three consonants or more, one cluster under GB9c) | per host since 2026-10-19: 2 / 2 / 2 on Ghostty, 3 / 3 / 4 on the other three (`TerminalWidthTraits.textClusters`) | 3 / 3 / 4 (2026-10-19) | 3 / 3 / 4 (3.7.6, 2026-10-19) | 2 / 2 / 2 (2026-10-19) | 3 / 3 / 4 (v0.2026.09.30, 2026-10-19) |

The conjunct row and the rest of the 38 complex-script rows are in "Complex
scripts", below, measured on both screens of every host on 2026-10-19. The
same runs re-read this table's rows on iTerm2 3.7.6 and Warp v0.2026.09.30,
newer than its columns, and some moved: see "iTerm2 3.7.6 re-measured" and
"Warp v0.2026.09.30 re-measured".

tmux is a fifth advance model and is measured separately (its grid is
client-independent, so it needs no per-client column) — see
[the tmux cursor-advance table](#cursor-advance--where-tmux-disagrees-with-tui-and-how-it-is-handled).

### A skipped cell is not a painted cell — Terminal.app, FIXED 2026-08-23

Cursor advance is only half of an under-advancing cluster. The other half is
what happens to the cell the cursor was pushed PAST.

`CUF` moves without painting, so inside a coloured run that cell keeps whatever
was in it — and a wide glyph is drawn across it regardless. On a highlighted row
the emoji therefore came with a hole in it: the row's fill stopped at the
glyph's first cell and resumed after its second, in the terminal's default
background. Reported against a file list drawing `⚙️ .swiftlint.yml` on a
selected row.

**Measured** (`Tools/TerminalProbes/background_probe.py`, `PROBE_ALT=1`,
2026-08-23) by drawing eight clusters in a row on a coloured run, which turns a
one-cell hole into stripes no screenshot can be ambiguous about:

| host | cell the cursor skipped | with `CUF` alone |
|---|---|---|
| Terminal.app 455.1 | **not painted** | a comb: every second cell the terminal's default |
| iTerm2 3.6.11 | painted *(not reproduced — see the revision below)* | unbroken run *(ditto)* |
| Ghostty 1.3.1 | painted *(not reproduced for SF Symbols — see below)* | unbroken run *(ditto)* |

`withTerminalAppCursorCompensation` therefore
emits **ECH** (`CSI n X`) before the cluster: it erases n cells from the cursor
in the current background and does not move it, so the glyph is then drawn over
cells that already carry the fill. Measured identical advance (2), unbroken
fill, and the glyph is NOT clipped by the erase.

**REVISED 2026-08-28 — the fix is NOT Terminal.app's alone.** User-reported
from the live app (SF Symbols on a coloured run showed the default background
under their second cell on both iTerm2 and Ghostty), then card-measured
(`bgfill` treatment card: each under-advancer drawn three ways — bare `CUF`,
`ECH`+glyph+`CUF`, glyph+styled-space — on a blue run, DSR-verified nets):

- **iTerm2 3.6.11** (alternate screen): SF Symbols, keycaps AND VS-16
  clusters all left the skipped cell at the default background with `CUF`
  alone; both the `ECH` and styled-space variants filled it, with the glyph
  intact. This contradicts the 2026-08-23 row above, which did not reproduce;
  the walk now erases, which is correct under both readings.
- **Ghostty 1.3.1**: only SF Symbols showed the hole — the one class whose
  claimed second cell Ghostty (grid-strict, 1-cell symbol) never paints at
  all. VS-15 chrome (ink across both cells) showed no hole, and `ECH` under
  it measured harmless.

`withITerm2CursorCompensation` and `withGhosttyCursorCompensation` now use the
same `ECH` + glyph + `CUF` shape as Terminal.app — and `withWarpCursorCompensation`
followed the same day, when the Warp tone card showed a lone 🇦 with the
default background under the right half of its ink. Only tmux remains
bare-`CUF`, pending the same coloured-run measurement.

ECH rather than "n spaces, then CUB(n)", which also works and was tried first:
the spaces are visible CHARACTERS, so every width measured after compensation —
`strippedLength` above all — inflates by the width of each emoji on the line.
ECH writes none.

Also measured, on the same run: an ECH-compensated cluster, a natively 2-cell
cluster (`📁`), and plain ASCII each put the character AFTER them in the same
column. The layout arithmetic is exact; what remains is only how Apple's font
paints a narrow glyph inside the two cells it owns.

#### The skin-tone path needed the same erase — FIXED 2026-08-26 (strip-era; SUPERSEDED 2026-08-28)

> This section documents the STRIP-era treatment: a text-presentation tone
> cluster had its modifier removed and `U+FE0F` restored. Since 2026-08-28 the
> modifier is KEPT — the cluster is rewritten as the VS-16-promoted base +
> ZWNJ + modifier (see the treatment-card table) — but the finding stands:
> the promoted form is a paint-2/advance-1 under-advancer, and the
> `ECH`-before-glyph this section measured is exactly what the new emission
> wraps the whole rewritten cluster in.

The erase above was added to the branch that handles under-advancing clusters.
Terminal.app's walk has a *second* branch, for the clusters that OVER-advance:
a Fitzpatrick cluster on a text-default base (`☝🏽`) has its modifier stripped
and `U+FE0F` restored, so that the base still paints the two cells the layout
claimed. That restoration turns the cluster into a VS-16 pictograph — which is
to say, into exactly the paint-2/advance-1 case the first branch exists for —
and it was emitting `CUF` with no `ECH`.

**Measured** (Terminal.app 455.1 / macOS 15.7.9, 2026-08-26, six `☝🏽` on a
blue run, `DECDWL` so a one-cell hole is unmistakable in a capture):

| output | advance per cluster | the cells the glyph covers |
|---|---|---|
| `☝️` + `CUF(1)` (what shipped) | 2 | a white cell after every hand |
| `ECH(2)` + `☝️` + `CUF(1)` | 2 | unbroken blue |

Same defect, same remedy, same advance — the erase was simply missing from one
of the two places that produce an under-advancing glyph. The affected clusters
are the nine text-default emoji-modifier bases, five tones each: `☝ ⛹ ✌ ✍ 🏋
🏌 🕴 🕵 🖐`. Emoji-default bases (`✊🏻`) are unaffected: they are stripped bare
to a glyph that already advances as far as it paints, so there is nothing for an
erase to fix, and the walk must not emit one for them.

Found by sweeping `TerminalQuirks` — the open switch set the
`TerminalClientQuirks` app exports — against the hand-written per-host model
and diffing the emitted bytes over 46,073 clusters. The two are independent
encodings of the same measurements, so anywhere they disagree, one of them is
wrong; this was the only disagreement Apple Terminal had.

#### …and on a FULL-WIDTH row, which is the case an app actually draws

The report that prompted the section above had a second half — the row also
appearing to sit one cell left, borders and scrollbar included — and a short
line cannot ask that question: `FrameDiffWriter.repaintRightEdge` documents a
family that consumes more line budget than it claims and WRAPS, and a row padded
to the terminal's exact width is where that would show.

**Measured** (`row_probe.py` — retired 2026-08-28, see `Tools/TerminalProbes/README.md` — with `PROBE_ALT=1`, Terminal.app
455.1 / macOS 15.7, 80 columns). Each row carries one cluster and is padded to
four cells short of the edge, where the cursor is read — at the edge itself it
CLAMPS, and reports the same column whatever the row spent:

| row | end column | verdict |
|---|---|---|
| `📁`, no compensation | 77 | the reference |
| plain ASCII | 77 | the reference |
| `⚙️` + `CUF(1)` | 77 | correct |
| `⚙️` + `ECH(2)` + `CUF(1)` | 77 | correct |
| `⚙️` **bare** | **76** | one cell short |
| `🖥️` bare | **76** | one cell short |

Nothing wrapped, in any case. So a full-width row spends exactly what it claims,
both compensation strategies are exact, and **the one-cell shift is what an
UNCOMPENSATED emission looks like**.

##### Which is what it was — FIXED 2026-08-24

The shift WAS seen, on Terminal.app, and the table above is what identified it:
the bytes were uncompensated, so the question was which path emitted them
without a model rather than which model was wrong. The report named the path
precisely — the row drew correctly when it was selected and wrong on every
frame afterwards.

Only the FIRST of those frames is built by `FrameDiffWriter`. The rest are the
animation replay (`RenderLoop.replayAnimations`), which advances a pulsing row
by splicing the run's current picture into the row already on screen — and a
run's frames are content as the view rendered it, which has never been through
the host's advance model, because the model lives in the builder the replay
exists to skip. So a focused `⚙️ .swiftlint.yml` painted correctly once and then
shifted a cell left, at the pulse rate, for as long as it stayed focused.

The splice now goes through `FrameDiffWriter.patchingAnimatedRun`, which
compensates the frame first. The compensation writes no visible characters
(ECH and CUF, per the section above), so the run still claims the cells it
claimed and the splice arithmetic is untouched.

**The general rule this is an instance of:** every byte that reaches the
terminal passes through this file's advance model exactly once. Any future path
that writes without going through `FrameDiffWriter` — a partial repaint, a
direct cursor-addressed write — owes the same, and will show the same one-cell
shift if it does not. A host with no model here (the `else` arm) legitimately
receives uncompensated bytes; if the shift is seen on such a terminal, that
terminal is one to measure and add.

### Bare (selector-less) pictographs — FIXED 2026-07-14

**Not to be confused with `🖥️`** (U+1F5A5 **+ U+FE0F**) — the form the demo
app and virtually all real text uses, and which has always been correct on
all four terminals (Apple/iTerm2 under-advance it and the CUF fixes it;
Ghostty/Warp advance it natively). **This section is the BARE form**, no
variation selector: a different grapheme cluster.

`terminalWidth` ended with a blanket `0x1F000...0x1FBFF → 2` rule (narrowed
2026-08-26 — see below), so a bare 🖥 claims 2. Advance is 1 on **every** terminal, and no model said so — a
single scalar cannot trip `isVS16UnderAdvancer`, so each model fell through
to `terminalWidth` and reported 2, contradicting its own probe data. Model
== claim ⇒ no CUF ⇒ the row sheared one cell left.

**Both halves measured 2026-07-14** — advance by DSR (`advance_probe.py`),
paint by eye (`Tools/TerminalProbes/visual_card.py`, a `|<c>|<c>|<c>|X` row: if the closing pipe
survives the glyph painted 1):

| Class | Example | `isEmojiPresentation` | Claim | Advance | Paint (Apple) |
|---|---|---|---|---|---|
| BMP text-presentation | ✏ ❤ ☝ ☂ ✔ ☎ | false | 1 ✓ | 1 | 1 ✓ |
| SMP text-presentation | 🖥 🛡 🕹 🕷 🎞 🏙 | false | 2 | 1 | **2** |
| SMP emoji-presentation | 👍 🀄 | true | 2 ✓ | 2 | 2 ✓ |
| In-block non-emoji | 🁠 🂡 🬀 🜀 | false | 1 ✓ | 1 | 1 ✓ |

The paint row is what decides the fix, and it overturned the first guess.
The claim of **2 is correct** for the SMP pictographs: macOS has no text
glyph for them, so font fallback reaches Apple Color Emoji and paints 2
cells — the glyph eats the closing `|` exactly as a VS-16 cluster does,
while its BMP twins leave it intact. So this was never a claim bug: it is a
**model** bug, and the fix is `Character.isBarePictographUnderAdvancer`,
which all four models now consult. Verified end-to-end in Apple Terminal:
`|🖥X` (pipe eaten) became `|🖥|X` (pipe restored), with 👍 unaffected.
A claim of 1 would have been actively wrong — Apple would then paint over
the following cell. Ghostty, the one host that paints these at 1 cell, takes
a blank cell instead of a shear — the same trade already accepted for its SF
Symbols, and the right one, since a host-independent claim must cover the
widest painter.

**The in-block non-emoji row — FIXED 2026-08-26.** These claim 1 now. The
row above stood open on the reasoning that narrowing the blanket rule was
risky, because the same range holds U+1F200–1F2FF (Enclosed Ideographic
Supplement, 🈁 🈚) which IS East Asian Wide and mostly NOT emoji, so gating on
`isEmoji` alone would wrongly drop those to 1. That hazard is real and the
measurement resolves it exactly.

**Measured 2026-08-26** over **all 1361 assigned non-emoji scalars** in
U+1F000–1FBFF, by DSR on Terminal.app 455.1 and Ghostty 1.3.1 — two terminals
that disagree about almost everything else and agree here on every single
scalar:

| | count |
|---|---|
| advance 1 | 1312 |
| advance 2 | 49 |
| host disagreements | **0** |

and all 49 wide ones are U+1F200–U+1F2FF, with no narrow scalar inside that
block and no wide one outside it. So the split is a clean range boundary,
which is what makes the narrowing safe:

```
0x1F200...0x1F2FF                    → 2   (Enclosed Ideographic Supplement)
0x1F000...0x1FBFF, isEmoji           → 2   (Apple Color Emoji fallback paints 2)
0x1F000...0x1FBFF, otherwise         → 1
```

The earlier note also **understated the reach**: it read as dominoes and
playing cards only (U+1F000–1F0FF). The affected set is 1312 scalars across
47 runs, and includes the Enclosed Alphanumeric Supplement (🅲), ornamental
dingbats (🙐), alchemical symbols (🜀), Supplemental Arrows-C (🠀), chess
(🨀) and — the most damaging — **Symbols for Legacy Computing** (U+1FB00–1FBF9,
🬀), which are block graphics, siblings of the U+2500–259F chrome the width
model already fast-paths to 1 cell. A framework that draws with block
graphics was claiming two cells for a quarter of them.

Verified end-to-end on all five hosts: rows of mahjong, dominoes, cards,
legacy-computing, alchemical, chess, Supplemental-Arrows-C, Enclosed
Ideographic and a mixed ASCII/CJK/emoji row were emitted through each host's
real compensation path and DSR-measured — **claimed width == measured advance
in all 50 checks**. It moved no golden snapshots.

With the claim corrected, `tmuxCursorAdvance`'s broader rule became dead
weight — it existed only to return 1 for scalars the claim had wrongly put at
2 — and now consults `isBarePictographUnderAdvancer` like the other four.

**SF Symbols PUA** is a third claim-vs-advance mismatch (no terminal advances
2) but is already handled: Apple/iTerm2 genuinely paint 2, so the claim is
right and the CUF is correct; only Ghostty paints 1 and takes the blank cell.

### Three shears only a real page revealed — 2026-08-26

Checking the Example emoji page on each client, cluster by cluster, found three
advance errors that every unit test and every row-width check had passed.

| host | cluster | claim | model said | terminal does |
|---|---|---|---|---|
| Warp | SF Symbols (Plane-16 PUA) | 2 | 2 | **1** |
| Ghostty | ☝🏻 ✌🏼 ✍🏽 ⛹🏾 (BMP base + tone) | 2 | 2 | **1** |
| iTerm2 | ❤️‍🔥 🏳️‍🌈 (VS-16-leading ZWJ) | 2 | 2 | **1** |

Warp's was the visible one: its model was the only one of the five with no
Plane-16 case, so every SF Symbol sheared its row a cell left and the emoji
page's SF Symbols panel drew its right border displaced, with the scrollbar
jammed against it. Ghostty's and iTerm2's are on rows that have been on that
page all along; iTerm2's had been documented as unhandled for months.

All three are fixed by the same means the framework already uses: the model
reports what the terminal does, and the existing CUF closes the gap.

**The methodological point, and it is the one worth keeping.** A row-width
check does NOT find these. The framework and the model share the same numbers,
so a model that is wrong about the terminal produces rows that add up perfectly
and still render wrong — verified directly: with Warp's Plane-16 case removed,
every one of the 44 rows still summed to exactly the terminal width while every
SF Symbol sheared. Self-consistency is not correctness, and only a measurement
against the terminal tells them apart.

`Tools/TerminalProbes/page_clusters_probe.py` is that measurement: it takes the
clusters an app actually draws — 90-odd for this page — and measures each on
the terminal under test. A hand-picked battery cannot do the same job, because
a battery only contains what somebody already thought to doubt.

### The claim follows the host now — 2026-08-26

For most of this document's life the **claim** — how many cells TUI's layout
reserves for a cluster — was host-independent, on the reasoning that it must
cover the widest painter so content is never overwritten, with narrower painters
taking a blank cell rather than a shear. That holds when the spread is one cell
(an SF Symbol: 2 on Apple Terminal, 1 on Ghostty). It does not hold when the
spread is nine, which is what 👨‍👩‍👧‍👦 costs on a host that does not compose
ZWJ sequences.

Where the claim could not stretch, TUI **substituted**: stripped the
Fitzpatrick modifier, so 👍🏽 reached the screen as 👍. That kept every row
aligned and changed what the user wrote. Taken to its conclusion the same
remedy turns 🏳️‍🌈 into 🏳️ — a pride flag into a white flag, which is not a
rendering compromise but a different message.

So the claim follows the host, and the layout accommodates the true width. A
cluster Warp draws across eleven cells is allocated eleven: the border lands
where it should, text wraps around it, and every scalar survives.

**The two rules, measured on the alternate screen.**

| host | ZWJ sequences | skin-tone clusters |
|---|---|---|
| Apple Terminal 455.1 | **decomposed reservation** (painted composed) | base + swatch |
| iTerm2 3.6.11 | composed, 2 | base + swatch on a **BMP** base only |
| Ghostty 1.3.1 | composed, 2 | merged, 2 |
| Warp 2026.07 | **decomposed** | base + swatch |
| tmux 3.7b | composed, 2 | **not modelled — still stripped** |

**tmux is deliberately not widened**, and the reason is worth recording because
it is the one host whose skin-tone widths do not follow a rule this model can
state. Measured 2026-08-26 on 3.7b:

| cluster | tmux advance | a base-plane rule predicts |
|---|---|---|
| 👍🏽 🙏🏽 👋🏽 | 2 (merged) | 2 ✓ |
| 🤙🏽 🤚🏽 | **4** | 2 ✗ — also SMP, and they do NOT merge |
| ✊🏻 ✌🏽 ✍🏽 | 4 | 4 ✓ |
| ☝🏽 | **4** | 3 ✗ — a 1-cell base, so base-plus-two gives 3 |

The line falls between Unicode 6.0 modifier bases (👍 🙏 👋) and 9.0 ones
(🤙 🤚), i.e. where tmux's own Unicode data has a modifier base and where it
does not. That is a per-codepoint fact, not a plane or a base width, so until
the whole modifier-base set is measured tmux keeps the old behaviour and the
modifier is stripped: a claim that is wrong in **both** directions misaligns
rows, whereas the strip at least aligns them.

**A tmux rendering defect, distinct from all of this.** While checking the
Example emoji page under tmux, both the BMP skin-tone row and the ZWJ row came
out visually scrambled — brackets displaced, adjacent clusters merged. That is
**not** a width miscount and not TUI's: drawing the identical row with no
TUI involved, `[c] [c] [c] …` written straight to a tmux pane, reproduces it
exactly, and the arithmetic is right to the cell (measured 29, expected 29).
tmux's cursor accounting says 2 per cluster and its painting does not match.
The BMP row is broken identically on `main`, so it predates the width work. It
is a tmux bug to report, not a TUI one to fix.

**How it was caught** is the point. The unit tests passed, the geometry probes
passed, and the defect appeared only when the Example emoji page was rendered
under tmux on a real terminal: the Fitzpatrick row came out SHORT, leaving
unpainted cells at the right edge — which is precisely the defect the strip was
introduced to avoid. Widths that are wrong in a way no synthetic probe asks
about still show up on a real page.

- **Decomposed ZWJ** is the sum of the ZWJ-separated segments **plus one cell
  per joiner** — the joiner takes a column. That predicts every measured case:
  👩‍🚀 = 2+1+2 = 5, 👨‍👩‍👧‍👦 = 11, and 👩🏽‍🚀 = 4+1+2 = 7, the last of which
  resolves its first segment through the skin-tone rule, so the two compose
  rather than duplicating each other.
- **A detached skin tone** is the base's width **plus two** for the swatch:
  👍🏽 and ✊🏻 at 4, ☝🏽 at 3 (a 1-cell text-presentation base). A redundant
  VS-16 on the base (☝️🏽) does NOT widen the claim, because since
  2026-08-28 the walks strip it before emission — the modifier alone
  forces emoji presentation (UTS #51), and the normalized pair is the
  measured-aligned one on both detaching hosts (iTerm2 painted the spelled
  form in 3 cells against the promoted claim of 4, a one-cell hole; Warp
  painted it in 4 where the normalized pair takes 3).

**Claim equals advance for every one of these**, because they are all cases
where the host is self-consistent — it advances as far as it paints. So the
compensation machinery simply stops firing: no CUF, no ECH, no rewrite, and the
Fitzpatrick strip no longer triggers because the over-advance it existed to
prevent is no longer an over-advance.

**Verified on the terminals, by the test that cannot be misread.** A row is
budgeted at the claim and filled; if the cursor's ROW number changes, the
budget was too small and the line wrapped.

| cluster | old claim | at the old claim | new claim | at the new claim |
|---|---|---|---|---|
| 👍🏽 (Apple) | 2 | **wraps** | 4 | fits |
| 👩‍🚀 (Apple) | 2 | **wraps** | 5 | fits |
| 👨‍👩‍👧‍👦 (Apple) | 2 | **wraps** | 11 | fits |
| 👩‍🚀 (Warp) | 2 | **wraps** | 5 | fits |
| 👨‍👩‍👧‍👦 (Warp) | 2 | **wraps** | 11 | fits |
| 👍, 中 (controls) | 2 | fits | 2 | fits |

So the widened claim does not introduce the ragged right edge that drove the
Fitzpatrick strip — **it removes its cause**. A kept modifier at a 2-cell claim
over-runs the line; at a 4-cell claim it fits exactly and the tone survives.

Also checked, on both hosts: full-width rows in normal AND inverted (selection)
video end exactly on the last column — 10/10 on Warp including the 11-cell
family, and every widened case on Apple Terminal. And mid-row, a two-colour
probe (background before the cluster, a different one after) shows **no
unpainted cell** between them: the "swatch" of a detached skin tone is ink, so
every cell the cluster owns is painted.

**Where the claim over-reserves, the existing CUF closes it.** ❤️‍🔥 and 🏳️‍🌈
lead with a VS-16 segment, which Apple Terminal under-advances, so they advance
4 against a claim of 5. The per-host advance model reports 4, the compensation
emits `CUF(1)`, and the cluster lands exactly on the claim — measured. This is
the same trade already accepted for a Ghostty SF Symbol that paints narrower
than the layout allocated.

**Cost.** Measured with `Tools/Profiling/ab_bench.py` over six scenarios
(`megalist`, `kitchensink`, `textwall`, `deep`, `dashboard`, `table`): all six
indistinguishable, −0.5% to +0.0%. The first attempt showed `megalist` at
+1.3%, which turned out to be an inlining artifact — the widening path is now
`@inline(never)` so `terminalWidth`'s inlinable body barely grows, and the
regression disappeared. A null A/B (the same binary against itself) confirmed
the harness resolves ~1% on that scenario, so the effect was real and so is its
absence.

**What this does NOT cover.** Only the two classes TUI was substituting —
the ones that can change a message. Classes that merely misalign are unchanged
and still limitations: Warp's keycaps and 〰️ at 3 cells against a claim of 2,
and its tag-sequence flags at 3. Each needs its own measured rule, and none of
them alters what the user said.

### ZWJ: where DSR lies, and where the defect actually is — measured 2026-08-26

> **SUPERSEDED 2026-08-27 — kept as history.** The conclusion below ("the
> claim of 2 is correct and no compensation is wanted") was the second wrong
> answer for this class: the composed glyph paints 2, but the row wraps at the
> internal width AND the stored width displaces everything later on the row.
> The shipped treatment is software decomposition — see the treatment table at
> the top of this host's section. The measurements below remain correct as
> measurements, and the Warp analysis stands.

Every advance number in this document comes from DSR (`ESC[6n`), and for ZWJ
sequences on Terminal.app **DSR is not telling the truth**. This was recorded
for a year as "Terminal.app badly over-advances ZWJ, rows will shear here,
known limitation". Rows do not shear. The measurement was right and the
conclusion drawn from it was wrong.

**The probe that settles it** draws three copies of a cluster separated by
pipes and terminated by an `X` — `|<c>|<c>|<c>|X` — on every host, and asks
where the `X` lands *on screen*. A cluster that occupies more cells than
claimed pushes the `X` right; one that occupies fewer pulls it left. Paint,
not report.

> **CORRECTED 2026-08-26 (same day).** The row below originally read
> "Terminal.app … rows shear? **no**", on the strength of an alignment card
> read by eye. That was wrong, and the error was mine: a row budgeted at a
> 2-cell claim **wraps** on Terminal.app, measured by the cursor's ROW number
> changing — a state the terminal enters, not a number it reports. What is
> true is narrower and is kept below: Terminal.app *paints* the cluster
> composed into about two cells while *reserving* five. The glyph looks right
> and the row still over-runs. The primary/alternate difference I blamed does
> not exist here either: both buffers give 5 / 8 / 11.

| host | composes a ZWJ cluster? | painted cells | reserved | rows shear at a 2-cell claim? |
|---|---|---|---|---|
| Terminal.app 455.1 | yes, one glyph | **2** | 5 / 8 / 11 | **yes — wraps** |
| iTerm2 3.6.11 | yes | 2 | 2 | no |
| Ghostty 1.3.1 | yes | 2 | 2 | no |
| tmux 3.7b | yes (own grid) | 2 | 2 | no |
| Warp 2026.07 | **no — draws the components** | **4–11** | 4–11 | **yes — wraps** |

On Terminal.app the astronaut, the four-person family, the England tag flag,
👍 and 中 all put their `X` in the **same column**, though DSR claimed 21, 39,
30, 12 and 12 for those rows. The composed glyph is two cells and printing
resumes two cells along; only the *report* runs ahead.

**Both hosts are affected, in different ways.** Warp does not compose ZWJ at
all — 👩‍🚀 draws as 👩 then 🚀 — so paint and reservation agree with each
other and disagree with a 2-cell claim. Terminal.app composes the glyph but
reserves the same decomposed width, so it looks right and still over-runs. On
both, a row budgeted at 2 wraps; on both, budgeting the reserved width fixes
it. Warp COMPOSES tag-sequence flags into one glyph — but advances and lands
them at 3 against the 2-cell claim (`flag_scotland` in its landing ledger; a
recorded known divergence, uncorrectable forward), so the class is aligned
everywhere except Warp, where it shears one cell.

**The lesson, again.** The paint card was the right instrument for the
*previous* question (does 🀀 paint one cell or two) and the wrong one for this
one. Neither a cursor report nor a glyph's appearance answers "how much room
does this cluster consume". The instrument that does is a row budgeted at the
claim: if the cursor's ROW changes, the budget was too small. That is a state
change, and it cannot be misread.

**Still unhandled, and now correctly scoped.** A Warp ZWJ cluster cannot be
fixed with `CUF`: paint equals advance, so there is no gap to close. The
remedies are a host-dependent width claim — which the whole model is built to
avoid, since a claim must be host-independent — or a skin-tone-style
substitution down to the first component. Neither is obviously worth it for a
class TUI's own chrome never emits, so it stays documented rather than
fixed. What has changed is that the cost is now known: it is one host, not
two, and it is Warp.

**Methodology, which this changes.** `Tools/TerminalProbes/advance_probe.py`
measures with DSR and is the source of every number in the advance table.
Those numbers are still correct *as cursor reports*, and for every class in
this document other than ZWJ they also match the paint. ZWJ is the one place
they come apart, so:

> A DSR advance that disagrees with the claim is a *hypothesis* about
> rendering, not a finding. Confirm it by drawing — `|<c>|<c>|<c>|X` and look
> at the column — before compensating for it.

The same discipline had already caught one error in the other direction: the
in-block non-emoji row above (🀀 🁠 🂡) was assumed to paint 2 and under-advance
until a paint test showed it painting 1, which turned a proposed `CUF` into a
width fix. Two classes, two wrong conclusions from advance alone, in opposite
directions.

**A residual, genuinely broken — RESOLVED 2026-08-27:** VS-16-leading ZWJ
(❤️‍🔥 ⛓️‍💥 🏳️‍🌈) on Terminal.app misbehaves visibly — in the same probe its
separating pipes were overpainted and the `X` landed left of the others. Under
software decomposition the leading VS-16 segment gets its own `ECH`'d
under-advance treatment (❤️‍🔥 → `ECH(2)` ❤️ `CUF(1)` 🔥, claim 4), which the
treatment cards measured clean: aligned, background intact, edge-safe.

## Keyboard modifiers on key events

Recorded 2026-07-27 alongside `KeyboardShortcut`'s key-equivalent support.
Read this before designing any binding that depends on a modifier.

### Command is never reported

No terminal forwards the Command key on a **key** event in its legacy
encodings. `⌘S` cannot arrive. Under the kitty keyboard protocol a ⌘ chord the
terminal does not keep for itself can arrive, as the Super bit (kitty and
Ghostty on macOS, by their documentation; not measured), and reports ⌘ held
alone as a modifier key. This is why `CommandKeyBinding` exists: SwiftUI source
says `⌘S`, and an app states once at its root which terminal modifier stands in
for it (`.commandKey(.control)`), rather than every shared shortcut being
rewritten. Which ⌘ chords a terminal keeps varies from terminal to terminal
(⌘C, ⌘V and ⌘Q nearly always), so a shortcut stays on its stand-in by default
and fires on a real ⌘ only where the app asks (`.keyboardShortcutsMatchCommand()`,
the owner's ruling B-D1K-1, 2026-10-23). Since that ruling a ⌘ chord that does
arrive is delivered, with `.command`, to `onKeyPress` and to those shortcuts
alone (see "The kitty keyboard protocol").

Note the asymmetry with **mouse** reports, where the meta bit is real but means
different things: iTerm2 forwards ⌘ as meta, Apple Terminal forwards ⌥ (see the
mouse sections above). The standing rule from that measurement holds here too —
never design around one specific macOS modifier key being available.

### A release is never reported, and a repeat is another press — in the legacy encodings

Recorded 2026-10-03, adding SwiftUI's `onKeyPress` and `KeyPress.Phases`.
Since 2026-10-04 this is the legacy encodings' story only: where the terminal
speaks the kitty keyboard protocol, TUI turns on its event types and both
are reported (see "The kitty keyboard protocol").
From the legacy encodings' definitions, not a per-terminal capture: a key
event is the bytes the key produces, sent when it goes down and again for each
auto-repeat while it is held, with nothing to tell a repeat from a fresh press.
Releasing a key sends nothing. So `KeyPress.phase` is always `.down`, a
`.repeat` handler hears every press, and `KeyPress.Phases` has no `.up`. The
kitty keyboard protocol's "report event types" enhancement reports all three
explicitly; TUI negotiates it where the terminal answers (2026-10-04).

### Caps Lock and the numeric pad are never reported — in the legacy encodings

Recorded 2026-10-03, adding SwiftUI's `EventModifiers.capsLock`. From the
encodings' definitions rather than a per-terminal capture: neither the C0 /
UTF-8 bytes of a printable key nor xterm's CSI modifier parameter (Shift, Alt,
Ctrl, Meta — see below) has a bit for a lock state or for the keypad. A letter
typed under Caps Lock arrives as the uppercase character, indistinguishable
from Shift and that letter; a keypad digit arrives as the digit, unless the
keypad is in application mode (DECKPAM). The kitty keyboard protocol does
carry both (`caps_lock`, `num_lock`, and distinct keypad key codes) once an
app negotiates it, and TUI does where the terminal answers (2026-10-04,
"The kitty keyboard protocol").

**Application mode, since 2026-10-05.** DECKPAM (`ESC =`) and its cursor-key
twin DECCKM (`CSI ? 1 h`) outlive the program that set them: a killed `vim`,
`less` or `htop`, or a shell that sends terminfo's `smkx` without `rmkx`,
leaves them on. The keys then arrive in their SS3 spellings, which the parser
dropped, all but F1–F4, so a TUI app started after such a program had dead
arrow keys. Now TUI puts both back at startup and on resume ("Inherited
state: the defaults raw mode asserts"), and reads every SS3 spelling anyway,
for a terminal that sends them regardless (xterm's table, ctlseqs):

| `ESC O` + | Key |
|---|---|
| `A` `B` `C` `D`, `H` `F` | the arrows, Home, End (the main keys, not the keypad) |
| `P` `Q` `R` `S` | F1 to F4 |
| `p` … `y` | keypad 0 to 9, with `.numericPad` |
| `j` `k` `l` `m` `n` `o`, `X` | keypad `*` `+` `,` `-` `.` `/`, `=`, with `.numericPad` |
| `M`, `I`, space | keypad Enter, Tab, Space, with `.numericPad` |
| `E` | the keypad's Begin: consumed, no key |

A modifier between the `O` and the key's byte (`ESC O 2 P`, xterm's older
spelling, or `ESC O 1;5 A`) is read as the CSI forms' is; only those two
shapes, with a code from 1 to 16 (`SS3Modifier`). A keypad key decodes
to exactly the event the kitty protocol's report of it does, so a binding sees
one key whichever encoding the terminal is in; `ApplicationModeKeyTests` pins
both, `InputSplitInvarianceTests` every spelling split at every byte, and the
CI PTY smoke walks Example's menu with `ESC O B` arrows
(`tui_walk.py --application-keys`).
`ESC O` is also how a meta-sending terminal spells Alt-Shift-O. Followed by
another escape sequence, it is read as that chord. Followed by a byte no
modifier spells (`17`, `123`, a `;` not after a lone `1`, a second `;`, a
non-digit), or by `1;` and then anything but a digit, or by a modifier (or
none) and then a byte no SS3 key ends with (`ESC O z`, `ESC O 2 a`), it is the
chord at once and the bytes after it typing: the parser gives up on the key at the first
byte that cannot be one, rather than holding up to eight and then dropping the
lot. What no parser can separate is the chord followed, within the
dead-sequence wait (about 8 idle frames), by bytes that spell a key: `ESC O A`
is Up, and `ESC O 5 x` Ctrl and keypad 8. The parser is split-invariant, so
timing cannot decide. A modifier the key's byte never follows is dropped with
its `ESC O` when that wait runs out, as an unfinished CSI is. Found by reading
Ghostty's VT reference (`Documentation/Terminals/Ghostty VT reference adoption study.md`, K1).
**To measure** on each host: run
`printf '\e[?1h\e='`, then launch Example; the arrows must move the focus
(UNMEASURED, 2026-10-05).

So in the legacy encodings `EventModifiers.capsLock` never appears in a key
press's modifiers, and `.numericPad` only on a keypad in application mode,
which TUI turns off. Where the protocol is on (2026-10-04) they
do, as SwiftUI reports them — Caps Lock on every key while it is on, the
numeric pad on a keypad key (not on the arrows, which macOS also flags). A
keyboard shortcut ignores both either way, as AppKit's key equivalents do, so
Ctrl-S with Caps Lock on is still Ctrl-S; `KeyboardShortcut.isDeliverableInTerminal`
therefore answers `false` for a chord that requires either, as it does for an
unresolved `.command`. The exit and delete commands ignore them too.

### Shift on a printable key is the character, not a bit

A terminal sends a shifted printable as the shifted **character** with no
modifier bits: "A" is one byte, 0x41, and `KeyEvent.parse`'s printable branch
builds `KeyEvent(character:)`, with `ctrl` and `alt` false and `shift` the
character's case (`isUppercase`: `true` for "A", `false` for "!" and "a").
There is no shift flag on the wire to read; the event's is derived.
(Corrected 2026-10-05: this said `shift` was false too, which the protocol
rule below, written against the case rule, contradicted.)

So a shortcut's Shift has to be derived from case, both when it is declared and
when a key arrives. `KeyboardShortcut` does exactly that: it reads
`KeyEquivalent("A")` as `"a"` + `.shift`, and matching sets `.shift` from
`character.isUppercase` and ignores `event.shift`. Trusting the flag instead
would leave `("a", [.shift])` permanently dead while `("a", [])` fired for "A"
as well. The `KeyEquivalent` itself keeps its case (since 2026-10-03, as
SwiftUI's does: `"A"` is not `"a"`), so the folding is the shortcut's, not the
key's.

**Under the kitty keyboard protocol too** (decided 2026-10-04, after a review
found the opposite shipped). The protocol does report Shift as a bit on a key
that typed text — `+` is `CSI 61:43;2;43u`, Shift-`=` typing `+` — and the
decoder first kept it. Every handler in TUI was written against the legacy
encodings, where `+` has no Shift, and some read the flag: a focused
`Stepper` or `Slider` steps by its Shift multiplier when Shift is held, so
under the protocol `+` and `_` stepped by five where they step by one
everywhere else. The rule now: **a key that typed a character carries Shift
as the character's case**, exactly what `KeyEvent(character:)` makes of the
legacy byte — `true` for `A` (Caps Lock's capital included), `false` for `!`,
`+`, `_` and a space. A chord whose key is reported as its shifted character
(Ctrl-Shift-Z as `Z`, Option-Shift-minus as `_`) follows the same rule; one
whose shifted character is not reported (flag 4 not taken) is its capital for
a letter and keeps the bit for anything else, the only way left to say it. So
an event is the same event on every terminal, and nothing tuned on one needs
to know which encoding it came in. The cost is SwiftUI's `KeyPress.modifiers`,
which on macOS has Shift on `!`; here it has not, on any terminal.

The flag IS meaningful on **non-printable** keys (arrows, function keys), where
it arrives in the CSI parameters — and there it is unreliable in a different
way: Apple Terminal sends bare `ESC[A`/`ESC[B` for Up/Down, dropping every
modifier, while keeping them on Left/Right. A Shift+Up binding therefore cannot
work in Apple Terminal. That is a terminal limitation, not a framework bug.

### Option arrives in two different spellings

Recorded 2026-08-13, while making ⌥←/⌥→ collapse and expand an outline
recursively.

A terminal set to treat **Option as Meta** does not report it in xterm's Alt
bit. The CSI modifier parameter is `1 +` a bitfield whose bits are
`1`=Shift, `2`=Alt, `4`=Ctrl, `8`=**Meta**, and Option-as-Meta lands in that
fourth bit — so the same keypress reaches an app as either of:

| Spelling | Bytes for ⌥→ | Sent by |
|---|---|---|
| xterm Alt bit | `ESC[1;3C` | terminals that report Option as Alt |
| xterm Meta bit | `ESC[1;9C` | terminals configured "Option as Meta", CSI form |
| ESC prefix | `ESC ESC[C` | the same setting's other encoding ("Esc+") |

TUI has no `meta` flag on a **key** event (unlike `MouseEvent`, where the
bit is real and the sections above measure what each terminal puts in it), and
there is no separate Meta key on a Mac keyboard for the bit to mean instead.
So `KeyEvent.parse` folds Meta onto `alt`, and all three spellings above decode
to the same `KeyEvent`. The ESC-prefixed form always did; the CSI Meta form did
not until now, and a ⌥-chord sent that way arrived as the **bare key** — the
modifier looked ignored rather than undelivered, which is the worse failure of
the two because the unmodified action happens instead.

The ESC-prefixed spelling is read as a prefix only on a key. An `ESC` in front
of anything that is not one — a terminal reply, a focus or mouse report, a
paste's start marker, a sequence that a new one cuts short — is the Escape
key, pressed just before the terminal sent that, and arrives as Escape, with
the rest parsed on its own (`Terminal.tryExtractMetaPrefixed()`, 2026-10-11).
Before that the pair was read as Option+Escape and the report lost, or the
paste typed out as keys, and an `ESC` in front of a sequence cut short went
on to the one that cut it: `ESC ESC [1;2 ESC [A` was Option+Up. One level
further in it still did until 2026-10-18: an `ESC` in front of that
(`ESC ESC ESC [1;2 ESC [A`) was Escape and Option+Up, and so was Option on a
UTF-8 lead that a sequence cut short (`ESC 0xC3 ESC [A`, with or without an
`ESC` in front). Each is now Escape for every `ESC` that had nothing to
prefix, then the sequence (`ParserNestedEdgeTests`).

The ESC-prefixed spelling of Option-[ is `ESC [`, the CSI introducer, so it
is read as the start of a control sequence and never reaches an app as a
key. (From the encoding: a terminal that sends Option as an `ESC` prefix
sends the `[` after one. Not captured on a terminal.) What follows decides
what it becomes. A key's bytes before the dead-sequence wait runs out
(about 200 ms) finish it: Option-[ then `A` is Up, and Option-[ then `M`
and three more bytes is a legacy mouse report. Nothing else finishes it, and
it is dropped when the wait runs out. An `ESC` straight after it, or among
the three bytes a legacy report has after its `M` — a paste, a mouse report
or an arrow that the terminal sends — cuts it short, and that sequence
parses on its own (2026-10-11). Before that, the sequence's first bytes were read as the rest of this one, and
what followed them was typed out as keys: a paste's text, a report's
coordinates.

A legacy report's coordinate past 223 does not fit its byte. xterm sends a
0 byte past the end (from its source; not captured), which the parser
refuses with the report. A terminal that let the byte wrap would spell
column or row 251 as `ESC` (a hypothesis: no measured terminal wraps, and
those measured with a mouse report in SGR, 1006, which TUI asks for). Read as a new sequence, that `ESC` and the row's byte
arrived as an Option chord; since 2026-10-18 an `ESC` in a coordinate's place
cuts the report short only when `[`, `O` or a string introducer follows it,
and is otherwise the coordinate, the report dropped as malformed.

*Not yet captured (2026-08-13):* **what Apple Terminal actually sends for
⌥←/⌥→.** The parser change above was verified against all three spellings by
feeding them to a real app through a PTY — that part is measured — but which
spelling (if any) Apple Terminal emits was not. Its shipped key map is believed
to bind that pair to `ESC b` / `ESC f`, the Emacs word-motion pair, which would
decode as **alt+`b`** / **alt+`f`** and never reach an app as arrows at all;
that is an expectation from the profile's Keyboard tab, not a byte capture, and
the parenthetical belongs in this section only once someone has run `cat -v` in
Terminal.app and pressed the two chords. Do that before relying on either
reading. The same run should cover iTerm2, Ghostty and Warp, whose Option
handling is a per-profile setting in each ("Esc+" vs "Meta" vs "Normal").

Since 2026-10-24 TUI learns from these spellings whether Option is sent as
Meta (`TerminalCapabilities.Feature.optionAsMeta`): an Option chord on a
printable key settles it as supported. Option-B, -D and -F do not count, because
`ESC b`, `ESC d` and `ESC f` are what key maps send for ⌥←, ⌥⌦ and ⌥→ with the
setting off (Apple Terminal's, by the expectation above; iTerm2's "Natural Text
Editing" preset). Nothing settles it as unsupported: Option composing `≈` cannot
be told from `≈` typed on a layout that has it, so there it stays undetermined.
Escape followed by a letter within one read is an Option chord to the parser,
and counts.

Either way the framework's rule stands on its own: **a ⌥-arrow binding must be
an accelerator, never the only route.** `OutlineGroup`'s recursive disclosure
follows it — plain Right and Left reach every branch one level at a time on
every terminal, and Option only makes that faster where the chord survives.

#### Option + Control + a letter (recorded 2026-08-20)

Select-all in the text controls is **⌥⌃A**, and it is the one binding in the
framework that deliberately breaks the accelerator rule above: there is no
other route to it. That was a decision made with the trade-off stated — "I know
that won't work in some terminal clients by default, but that's okay; I don't
want to move it even further away from the platform canonical shortcut
(⌘A)" — and ⌘A cannot reach a terminal app at all.

The bytes, for a terminal in "Esc+" mode:

| Chord | Bytes | Decodes to |
|---|---|---|
| ⌃A | `0x01` | `.character("a")`, ctrl |
| ⌥⌃A | `ESC 0x01` | `.character("a")`, ctrl + alt |

The second is the ESC-prefix spelling applied to a C0 byte rather than to a CSI
sequence, and `KeyEvent.parse` already handled it: a two-byte `ESC <byte>`
recurses into the single-byte path, which maps 0x01–0x1A back to a letter with
`ctrl: true`, and the ESC contributes `alt: true`. No new modifier flag was
needed — verified through a PTY.

*Not yet captured:* **which spelling each terminal emits for ⌥ + a C0 chord.**
This is the same survey the section above still wants, now with a second reason
to run it. A terminal in "Normal" Option mode will send the letter's ⌥-composed
character instead (⌥a is `å`), which decodes as a plain character and inserts
it; a terminal in "Meta" mode sets the high bit. Neither reaches the binding.
Run `cat -v`, press ⌃A and then ⌥⌃A, in Terminal.app, iTerm2, Ghostty and Warp,
and record the four pairs here.


### Control collides with the C0 range

`Ctrl`+letter arrives as 0x01–0x1A and `KeyEvent.parse` maps it back to the
lower-case letter with `ctrl: true` — but only for the letters the C0 range has
not already spent:

| Combination | Arrives instead as | Why |
|---|---|---|
| Ctrl-H | Backspace | 0x08 is BS, matched before the Ctrl range (`parseSingleByte`) |
| Ctrl-I | Tab | 0x09 is HT, matched before the Ctrl range |
| Ctrl-J | Ctrl-J itself, since 2026-10-26 | 0x0A is LF, which Return never sends in raw mode (it sends CR), so `parseSingleByte` reads it as the chord (owner ruling B63-CTRLJ); one that nothing takes goes round again as Enter, as before |
| Ctrl-M | Enter | 0x0D is CR |
| Ctrl-[ | Escape | 0x1B, outside the 0x01–0x1A range |
| Ctrl-\\ | `SIGQUIT`: the app quits — unless it binds the chord | 0x1C is the user's quit key, which the driver turns into the signal; masked while the app binds it, and then a key (see "The quit key, ⌃\\" below) |
| Ctrl-4, Ctrl-\| (Ctrl-Shift-\\) | Ctrl-\\, on some terminals | Measured per chord (the owner's `cat -v` readings, 2026-10-06; table below): iTerm2 3.7.3 and Warp 0.2026.09.30 send 0x1C for both; Ghostty 1.3.1 for Ctrl-4 only (Ctrl-Shift-\\ is `CSI 124;5u`); Apple Terminal 2.14 for Ctrl-Shift-\\ only, and nothing at all for Ctrl-4. xterm, VTE, Konsole and the Linux console send it for both *by their tables of the legacy encoding, not measured*. Tried as these where no Ctrl-\\ binding takes it, on a host that may send it for them (below) |

These cannot be delivered under `.commandKey(.control)` reliably in
the legacy encodings (Ctrl-\\ can, since 2026-10-06); under the kitty keyboard protocol's "disambiguate"
enhancement they arrive as themselves (see "The kitty keyboard protocol"), and
one that nothing binds goes round the input chain again as the key it would
have been, so Ctrl-[ still leaves and Ctrl-H still rubs out (Ctrl-H added 2026-09-24: `isDeliverableInTerminal` used to call it deliverable, though a ⌘H button could never fire). Ask
`KeyboardShortcut.isDeliverableInTerminal` (after `resolved(commandKey:)`)
rather than wondering why one menu item is dead. `.commandKey(.option)` has no
such collision, at the cost of Option itself being less reliable: Apple
Terminal composes accented characters unless "Use Option as Meta key" is on.

**Where 0x1C reaches the app** — the driver's quit masked because the app
binds a chord it could be (below), or the user's quit key turned off or
moved — the parser reads it as ⌃\\, and a ⌃\\ no binding takes is offered
once more as ⌃4, ⌃| and ⌃⇧\\ in turn — each only on a terminal in its legacy
encoding that may send 0x1C for that chord: measured to, or not measured at
all (`TerminalClient.quitByteAliases`, per host and chord; the readings
below) — as an unbound Ctrl-H goes round as Backspace —
but only to the bindings the app declares for them (those that mask the
quit, below), not round the whole chain: a handler that hears every key, or
a field's `.decimalDigits`, hears the byte once, as ⌃\\, and never types a 4
for it (the coordinator's ruling, round 6); nor does a field's
`onKeyPress(keys:)` on the digit keys, which names no Control chord (the
coordinator's ruling, 2026-10-06). A binding on ⌃\\ wins over one
on ⌃4: the bytes are the same.
Where none of the four is taken and 0x1C is the user's quit key, the chain
raises `SIGQUIT`, as the driver would have.

**The three that share ⌃\\'s 0x1C** (2026-10-06). Before the quit key was
the driver's, a legacy 0x1C was dropped, so a ⌘4 shortcut (⌃4 under
`.control`) never fired on those terminals; for a few hours of 2026-10-06 the
driver raised `SIGQUIT` for it instead. The owner's decision (decisions F2
A-F2-1): a binding on ⌃4, ⌃| or ⌃⇧\\ masks the driver's quit, as one on ⌃\\
does, so the byte reaches the chain and the retry above fires it. Nothing in
the byte says which key sent it, so `isDeliverableInTerminal` stays `false`
for them. Under the kitty keyboard protocol ⌃4 and ⌃| arrive as themselves
and fire.

**Which hosts send 0x1C for which chord — the owner's measurement**
(2026-10-06, `cat -v` in a cooked tty, so "quits" means the terminal sent
0x1C and the driver raised `SIGQUIT`; versions read from the app bundles that
day; a US keyboard, where ⌃⇧\\ is ⌃|; Ghostty's column is its legacy
encoding, since `cat` pushes no kitty flags):

| Chord | Apple Terminal 2.14 | iTerm2 3.7.3 | Warp 0.2026.09.30 | Ghostty 1.3.1 |
|---|---|---|---|---|
| ⌃4 | nothing | 0x1C | 0x1C | 0x1C |
| ⌃⇧\\ (⌃\| on US) | 0x1C | 0x1C | 0x1C | `CSI 124;5u` |
| ⌃, | not reported | `,` (Control dropped) | `,` (Control dropped) | `CSI 44;5u` |

Plain ⌃\\ was not separately reported for any of the four (Apple Terminal's
"none do anything except ⌃⇧\\" may cover it; to confirm). TUI acts on the
first two rows: `TerminalClient.quitByteAliases` has Apple Terminal alias
⌃⇧\\ (and ⌃|) only, iTerm2 and Warp both, and Ghostty ⌃4 only; tmux and an
unidentified host, not measured, may alias both. So on Apple Terminal a ⌘4
shortcut (⌃4 under `.control`) neither masks the quit nor is offered an
unclaimed ⌃\\ — the chord sends nothing there, so it cannot fire at all —
and on Ghostty in its legacy encoding a ⌃| or ⌃⇧\\ binding leaves the quit
live, the chord arriving as itself. The ⌃, row is recorded only; nothing in
TUI depends on it yet.

**Ctrl-minus arrives as 0x1F** (2026-10-04, from the encodings' definitions,
not a capture): the C0 unit separator, `^_`, which most terminals also send for
Ctrl-_ (Ctrl-Shift-minus) and Ctrl-/, so the three cannot be told apart in a
legacy encoding. `KeyEvent.parse` reads it as Ctrl-minus, the key undo is on
(see "Undo and redo"); before then 0x1F, like 0x1D and 0x1E still are, was
dropped (0x1C is read as ⌃\\ since 2026-10-06). Under the
kitty keyboard protocol the three arrive apart.

**Ctrl-6 sends nothing in Apple Terminal; Ctrl-Shift-6 sends 0x1E** (`^^`, the
C0 record separator) — the owner's `cat -v` reading, 2026-10-05, Apple Terminal
(version not recorded). Many terminals send 0x1E for Ctrl-6 itself; on Apple
Terminal only the shifted chord reaches the app. `KeyEvent.parse` drops 0x1E,
and nothing in TUI is bound to it (it was weighed, and declined as too
obscure, for the mouse hand-off key: decisions A13).

**Ctrl-C and Ctrl-Z do arrive** (corrected 2026-09-24; this table used to list
them as "taken by the shell's job control"). That is true of a cooked terminal,
not of TUI's: `Terminal.enableRawMode()` turns `VINTR` and `VSUSP` off (until
2026-10-06 it cleared `ISIG` altogether; see "The quit key, ⌃\\" below), so
the driver sends 0x03 and 0x1A as bytes instead of raising SIGINT and SIGTSTP,
and they decode as `.character("c")` and `.character("z")` with `ctrl`. What becomes of them is the
input chain's business. Ctrl-C goes to anything of the app's first — an app's
⌘C under `.control`, or `QuitShortcut.ctrlC` — and where nothing takes it, it
asks whether to quit (2026-10-31, the owner's choice). Ctrl-Z is the app's undo by default (2026-10-04, the owner's choice; see
"Undo and redo"), with nothing to undo doing nothing; where the app takes it
out of its undo keys (`.undoShortcuts`), an unclaimed Ctrl-Z reaches layer 4,
which re-raises it as SIGTSTP, as it always did. A shortcut on ⌃Z (an app's
⌘Z under `.control`) comes before either, for as long as it is on screen.
SIGINT itself still shuts the app down; it comes from `kill -INT`, not from
the keyboard.

**Ctrl-Q arrives, as 0x11** (2026-10-31), and is the default quit key since then.
`Terminal.rawModeAttributes(from:)` clears `IXON`, so the driver has no XON to
take it for. Measured on a PTY on Darwin 24.6, where nothing but the line
discipline stands between the bytes and the app (`Tools/Smoke/quit_key_smoke.py`
checks `IXON` is off and ⌃Q quits), and through tmux 3.7c (`send-keys C-q`,
into an app in the same raw mode: it quits). Under the kitty keyboard protocol it
is `CSI 113;5u`, read the same. **Apple Terminal, iTerm2, Ghostty and Warp are
unmeasured for ⌃Q itself**: this session can't type at a terminal window. Their
documented defaults keep ⌘Q on a Mac and bind nothing to ⌃Q. On Linux, VS Code's
integrated terminal is documented to keep ⌃Q for its own Quit unless the user says
otherwise, and GTK and Qt terminals keep Ctrl-Shift-Q instead, so ⌃Q reaches the
app there. None of that is measured; `StatusBarState.quitShortcut` moves the key.

#### The quit key, ⌃\\ — asks first since 2026-10-31; the driver's before then, from 2026-10-06

**Since 2026-10-31, the app takes the key from the driver to ask first, while it
is to (`.quitConfirmation`, by default): `VQUIT` is masked as of the first frame,
and `UnreadQuitKeyWatch` quits a hung app in the driver's place. See "⌃\\ quits a
hung app" in `KeyboardShortcuts.md`. What follows is still so of an app under
`.whenWarned` with no warning active, and of the moments before its first frame.**

The owner's request: ⌃\\ is the backup to ⌃C, which TUI hands the app as a
key, and it has to work when the app has HUNG. So it is the kernel's, not the
app's. `Terminal.rawModeAttributes(from:)` keeps `ISIG` as the user had it and
turns every signal character off but `VQUIT`: `VINTR` (⌃C) and `VSUSP` (⌃Z),
and on Darwin `VDSUSP` (⌃Y, the delayed suspend) and `VSTATUS` (⌃T, `SIGINFO`),
all set to `_POSIX_VDISABLE`, asked of the system with `fpathconf` (0xFF on
Darwin and the BSDs, NUL on Linux; a guess by C library would make NUL a live
signal character on a BSD). `VQUIT` is left as inherited: ⌃\\ (0x1C) by default, so the driver raises `SIGQUIT` before the app
reads a byte, and over ssh the remote pseudo-terminal's line discipline does
the same. A user's `stty quit undef` stays undefined (0x1C then arrives as
⌃\\, a key an app can bind; until 2026-10-06 `KeyEvent.parse` dropped it), a
moved quit key stays moved, and
`stty -isig` stays off. The teardown, a suspend and the fatal-signal handler
put the user's termios back exactly. `SIGQUIT` then leaves the terminal as a
quit does (`FatalSignalTerminalRestore`).

**An app's own binding masks it** (the owner's decision, 2026-10-06). After
every frame the run loop asks whether the app declares a binding on a chord
the quit key's byte could be — ⌃\\ itself (with or without Option, whose ESC
the driver ignores), and in the legacy encoding ⌃4, ⌃| and ⌃⇧\\ — counting
what can be read without running the app's code: `.keyboardShortcut`s (menu
items' too) and framework defaults, `onKeyPress` on keys (not on a set of
characters, which asks for typed text; and for a Control chord only on a key
that names one — `"|"` for ⌃|, never a digit for ⌃4, so a PIN field's
`onKeyPress(keys:)` on "0"…"9" masks nothing: the coordinator's ruling,
2026-10-06) on the path to the focused view, the
status bar's items and quit key, the scene's undo keys
(`InputHandler.quitKeyBindings`). While one is, `VQUIT` is `_POSIX_VDISABLE`
too (`Terminal.maskQuitKey(for:)`), set with `TCSANOW` — no
typed-ahead input thrown away — and only when the answer changes; a resume's
raw mode is made with it, and the teardown puts the user's termios back
whole. The byte then reaches the chain as ⌃\\ (above). A handler that hears
every key (`onKeyEvent`, `onKeyPress(phases:action:)`) masks nothing: only
running it would say what it takes. While masked, a hung app does not quit by
⌃\\ — the backup the binding trades away. A moved quit key is masked for its
own chord (`stty quit ^X` and a ⌘X under `.control`); the alias retry is
⌃\\'s alone. Which of ⌃4, ⌃| and ⌃⇧\\ count depends on the host, by the
owner's measurement of 2026-10-06 ("Which hosts send 0x1C for which chord",
above): ⌃4 not on Apple Terminal, ⌃| and ⌃⇧\\ not on Ghostty, both on iTerm2,
Warp and any host not measured. The PTY smoke checks it (case 9): ⌃4 or ⌃\\ bound, `VQUIT` off
while the app runs and 0x1C runs the binding; ⌃⌥\\ bound, the unclaimed 0x1C
quits by `SIGQUIT`. The driver reads every byte of input,
a bracketed paste's included, so pasted text holding a 0x1C quits the app, as
it would a shell.

Measured on Darwin 24.6 (macOS 15.8), on a pseudo-terminal with `ECHO`,
`ICANON` and `IEXTEN` off, `ISIG` on and `VINTR`/`VSUSP` off: ⌃T and ⌃Y arrive as
bytes and raise nothing whether `VSTATUS` and `VDSUSP` are left as inherited
(0x14, 0x19) or turned off — Darwin's tty driver checks `VSTATUS` only in
canonical mode with `IEXTEN`, and `VDSUSP` only with `IEXTEN` — and 0x1C raises
`SIGQUIT`. TUI turns the two off anyway, so nothing rests on that. On Linux,
`n_tty` never treats NUL as a signal character (`__DISABLED_CHAR` is cleared
from its map), so a ⌃Space (NUL) is still a key; with `ISIG` on it reads input
on its ordinary path rather than its raw-mode fast path, a cost per byte of
input only. The PTY smoke `Tools/Smoke/quit_key_smoke.py` checks all of this
against `IdleProbe`, a hung one included (CI runs it).

**Under the kitty keyboard protocol the driver never sees ⌃\\.** Its
"disambiguate" flag has the terminal send every Control chord on an ASCII key
as a report — ⌃\\ as `CSI 92;5u`, not 0x1C — so no byte reaches the line
discipline to raise the signal (from the specification; the hosts are
unmeasured, like the rest of that section). `InputHandler` therefore offers
the report of the user's quit key (the chord whose legacy byte is the inherited
`VQUIT`, `Terminal.quitKeyByte`) to the app's bindings as any key — the
owner's rule of 2026-10-06, that an app's own ⌃\\ overrides the quit; until
then the report was taken ahead of every layer — and where none takes it sends
`SIGQUIT` where the driver would have, to the app's whole process group, so a
child the app started ends with it (`QuitKeyReport`); a release quits
nothing, and with the quit key turned off the report is an ordinary key.
Signalling processes, not the thread as `raise` did, the handler may run on
another thread after `kill` returns (on Linux the main actor need not be the
main thread), so the sending thread then waits in `sigsuspend` for the signal
to end the process, and runs nothing more of the batch the report came in:
no key read after it acts, no frame lands on the shell's screen after the
handler left the alternate one. Where `SIGQUIT` would end nothing — ignored,
or a handler of the app's own — it does not wait. The smoke checks the report
too, against a PTY that plays a terminal speaking the protocol, with a key in
the same read that must not show.

**A hung app under the protocol: the stall watchdog** (2026-10-06, decisions
B-F2-4). The report needs the app to read its input, and a hung app reads
none, so a thread of its own (`StallWatchdog`) sleeps in `poll` on standard
input and, when input has waited unread for 1.5 s with the loop draining
nothing, writes `CSI < u`: the terminal sends keys in the legacy encoding
from then on, and the next ⌃\\ is 0x1C, which the driver quits on. The
report that tripped it stays unread, so a hung app quits at the second ⌃\\,
about two seconds after the first. A loop that was only slow pushes the
flags back at its next drain (`Terminal.recoverFromStall`); meanwhile the
parser still reads the protocol's grammar, which decodes the legacy bytes
sent after the pop as well. The pop is written under the lock every terminal
write takes (`TerminalWriteGate`), so it never lands inside a frame; a main
thread hung INSIDE a write — the terminal not reading its output — leaves
the watchdog waiting behind it, and nothing is popped. A pop counts only
when the terminal was sent it whole: none at all where a non-blocking
standard output is full (tried again a grace later), and once begun it is
finished, as a blocking write would. Armed only while the flags are pushed
and the quit key is live in the driver and would stay so after the pop: not
with the key turned off, nor while a binding would mask it in the legacy
encoding the pop puts the terminal in — ⌃\\ itself, or on a host that may
alias ⌃4, ⌃| or ⌃⇧\\, which under the protocol leave the driver's quit live
but after a pop would be its 0x1C, and quit the app on the binding's key —
nor during a suspend, whose own pop disarms it and takes back a pop of the
watchdog's in one step (a pop it made is not written twice). The quit's own
debt pops the flags again; on the alternate screen a pop of an empty stack is
harmless. The smoke (case 10): a hung
IdleProbe pops nothing with no key pressed, pops within 2.5 s of an unread
report, and the byte then quits it; a slow frame pops and pushes back, a
report sent before the pop and a byte after both read; with a ⌃\\ binding
nothing is popped. Against the smoke's terminal, not a real one: Ghostty,
kitty, WezTerm and foot are unmeasured.

#### ⌘ shortcuts meet the text controls' Emacs chords (recorded 2026-09-24)

A framework rule rather than a terminal measurement, recorded here because it
is the other half of the collision above. The letters the C0 range leaves
deliverable are not all free either: the macOS text system (Cocoa's
`StandardKeyBinding.dict`) gives a Control letter an Emacs editing command,
readline gives Option-B and Option-F the word motions, and TUI's text
controls read them the same way, from one table (`TextEditingCommand`). The ⌘
shortcuts an app is most likely to carry land on them:

| ⌘ shortcut | Arrives as | Byte | The editing chord there | Who gets the key |
|---|---|---|---|---|
| ⌘F Find | ⌃F | `0x06` | forward a character | the app's shortcut |
| ⌘D Duplicate | ⌃D | `0x04` | delete forward | the app's shortcut |
| ⌘B Bold | ⌃B | `0x02` | back a character | the app's shortcut |
| ⌘K | ⌃K | `0x0B` | kill to the end of the line | the app's shortcut |
| ⌘T | ⌃T | `0x14` | transpose | the app's shortcut |
| ⌘Y | ⌃Y | `0x19` | yank | the app's shortcut |
| ⌘N New, ⌘O Open, ⌘P Print | ⌃N, ⌃O, ⌃P | `0x0E`, `0x0F`, `0x10` | `TextEditor`: next line, open a line, previous line | the app's shortcut |
| ⌘V Paste | ⌃V | `0x16` | `TextEditor`: page down | the app's shortcut |
| ⌘A Select All, ⌘E | ⌃A, ⌃E | `0x01`, `0x05` | a field: start, end of the line | the app's shortcut |
| ⌘B, ⌘F under `.option` | ⌥B, ⌥F | `ESC b`, `ESC f` | back, forward a word | the app's shortcut |
| ⌥⌘B, ⌥⌘F | ⌥⌃B, ⌥⌃F | `ESC 0x02`, `ESC 0x06` | a field: back, forward a word; `TextEditor`: a character | the app's shortcut |
| ⌘A Select All, ⌘E | ⌃A, ⌃E | `0x01`, `0x05` | `TextEditor`: start, end of the line | the editor |
| ⌥⌘A | ⌥⌃A | `ESC 0x01` | select all | the text control |
| ⌘V Paste | ⌃V | `0x16` | a field: paste | the field |
| ⌘C, ⌘X | ⌃C, ⌃X | `0x03`, `0x18` | copy, cut the selection | the text control while text is selected, else the app's shortcut |
| ⌘Z | ⌃Z | `0x1A` | undo | the text control |
| ⌘U | ⌃U | `0x15` | kill to the start of the line, readline's `unix-line-discard` (2026-10-24; it erased a whole field before) | the text control |

A focused text control is offered a key before the app's shortcuts (layer 0
before layer 3.5), so a focused editor used to swallow the app's Find and move
its caret instead, and a field would have done the same once it took the Emacs
chords too. The owner's decision (2026-09-23): the app's shortcut wins,
because the Emacs chords are a bonus, and whatever one does can be done some
other way. `InputHandler` does not offer the focused text control a chord it
gives way on (`TextInputFocusHandler.givesWayToKeyboardShortcut(_:)`, answered
from the control's own reading of the chord) when an app shortcut is
registered on it (`KeyboardShortcutRegistry.hasAppShortcut(for:)`, the same
match `trigger(for:)` fires by). The last five rows keep the key, because
each is the only way to do what it does or stands in for the ⌘ chord itself
(copy and cut only while there is a selection to act on): select-all has no
other route at all (see the ⌥⌃A section above); the editor's Home and End go
to the ends of the document, so Ctrl-A and Ctrl-E are its only keys for the
ends of a line (a field's Home and End go to the ends of its line, so there
the pair gives way); and the clipboard and undo chords are what ⌘C, ⌘X, ⌘V
and ⌘Z would do anyway. A framework default, such as the split view's ⌃S
below, never takes a key from the focused control.
`TextInputShortcutPrecedenceTests` pins every row through the input chain.

#### ⌃S and ⌥⌃S: the split view's sidebar chords (recorded 2026-09-13)

`NavigationSplitView` registers SwiftUI's sidebar chords, ⌃⌘S (View ▸ Show
Sidebar) and ⌥⌘S (Toggle Sidebar), through `commandKey`. Under the default
`.control` they are:

| Chord | Resolves to | Bytes | Decodes to |
|---|---|---|---|
| ⌃⌘S | ⌃S | `0x13` | `.character("s")`, ctrl |
| ⌥⌘S | ⌥⌃S | `ESC 0x13` (where Option is sent as ESC) | `.character("s")`, ctrl + alt |

**⌘S and ⌃⌘S collapse.** Removing ⌘ and inserting ⌃ turns an app's plain ⌘S
(Save) into ⌃S as well, so the two are one trigger. The chords therefore register
in the shortcut registry's framework-default tier, which any app shortcut beats
whatever the registration order; on a screen that binds Save, ⌃S saves and ⌥⌃S
still toggles the sidebar, but only in a terminal that sends ⌥⌃S as `ESC 0x13`.
Of the four measured below, that is Ghostty alone.

**Why plain `cat -v` showed nothing for ⌃S.** The owner first ran `cat -v` in
Apple Terminal and pressed ⌃S and ⌃⌥S: nothing appeared. The tty was to blame,
not the terminal: IXON flow control takes ^S as XOFF and pauses output instead of
delivering the byte (^Q resumes). ICANON also holds input back from `cat` until
Return, but the tty echoes each byte as it arrives, so with IXON cleared that
echo is a reading. TUI's raw mode clears IXON and ICANON
(`Terminal.enableRawMode`), so `0x13` reaches the parser;
`NavigationSplitViewSidebarChordTests` pins that through the `readSource` seam,
and pins `ESC 0x13` too.

**What the terminals send.** Measured 2026-09-13 by the owner, `stty -ixon; cat -v`,
reading the echo. The terminal versions and Option-key settings were not
recorded.

| Pressed | Apple Terminal | Ghostty | iTerm2 | Warp |
|---|---|---|---|---|
| ⌃S | `^S` | `^S` | `^S` | `^S` |
| ⌥⌃S | `^S` | `^[^S` | `^S` | `^S` |

The echo (ECHOCTL) spells a C0 byte and ESC faithfully, `^S` for `0x13` and `^[`
for ESC, so the readings are `0x13` and `ESC 0x13`. It does not spell a
Meta-mode high-bit byte that way: a macOS PTY with `-ixon` echoes `0x13` as `^S`
and `ESC 0x13` as `^[^S` before any Return, but echoes `0x93` back as the raw
byte (checked 2026-09-14). So a `^S` reading is `0x13`, not a Meta byte, and a
Meta-mode reading needs raw mode: `stty raw -echo -ixon; od -c`, or a PTY probe.

At those settings ⌃S arrives as ⌃S everywhere. ⌥⌃S arrives as ⌥⌃S (Alt+Ctrl+S,
`ESC 0x13`) only in Ghostty. Apple Terminal, iTerm2 and Warp drop the Option and
send plain `0x13`, which is ⌃S, the show-sidebar chord. On a bare split view the
difference is invisible, since both chords toggle. It matters where the app binds
⌃S: there ⌥⌃S toggles the sidebar in Ghostty and runs the app's shortcut in the
other three. Under `.commandKey(.option)`, which binds ⌥⌃S and ⌥S but not ⌃S, the
other three's ⌥⌃S toggles nothing.

Ghostty's reading matches its documentation. The `macos-option-as-alt` entry in
its ghostty.5 man page (the copy shipped in Ghostty 1.3.1) says an Option
sequence that produces no printable character is treated as Alt whatever that
setting is. Its example is `alt+ctrl+a`, the ⌥⌃A select-all chord above, which
still has not been measured.

*Not yet captured:* **whether an Option setting changes the other three.** Apple
Terminal's "Use Option as Meta key" and iTerm2's per-profile Esc+/Meta/Normal
choice may make ⌥⌃S send `ESC 0x13` or a high-bit byte, and Warp has its own
setting. Record each terminal's version and setting with the reading.

### Keys a sheet's grabber uses — since 2026-10-06; ↖ ↘ ⇞ ⇟ NOT yet measured

A detented sheet's grabber (`presentationDragIndicator(_:)`, decisions A19) is a
focus stop moved by **bare ↑ and ↓** (the next detent), **↖ ↘ Home and End**
(the smallest, the largest) and ↩ or Space (round them). The bindings were
chosen against what reaches an app:

- **⌃↑ and ⌃↓ were rejected.** Apple Terminal strips every modifier from the
  vertical arrows (Apple Terminal, "Input behaviour"), so they arrive as bare
  ↑ and ↓ there. And **macOS takes ⌃↑ and ⌃↓ itself, in every terminal**: they
  are Mission Control's and Application windows' default shortcuts (System
  Settings → Keyboard → Keyboard Shortcuts → Mission Control), consumed by the
  system before any terminal sees them, unless the user has turned them off.
  Noted when the list's row moves gained ⌥↑ ⌥↓ beside ⌃↑ ⌃↓ (73e77659); not
  recorded here until now, and not yet captured by a probe on each host.
- **⇧↑ ⇧↓ and ⌥↑ ⌥↓** are stripped the same way in Apple Terminal.
- **Bare ↑ and ↓** reach the app on every host measured; they are the split
  view divider's keys, so a reader who has moved a divider knows these.
- **Bare ↖ ↘ (Home, End) and ⇞ ⇟ (Page Up, Page Down): NOT YET MEASURED.** A
  host's default profile may keep them for scrolling its own buffer — Apple
  Terminal's is the doubt — and send the app nothing. `.userResizable` binds
  Home and End already. Until measured, the grabber's ↑ and ↓ are its
  documented route and Home and End a convenience; ⇞ ⇟ are bound to nothing.

**To measure — `Tools/TerminalProbes/key_probe.py`**, run inside each host from
its default profile, on both screens (`PROBE_ALT=1` is the one TUI draws on):
it asks for each of the keys above in turn and records the bytes that arrived, or
that NOTHING did, within six seconds. Record whether the Mission Control
shortcuts are on.

### A file panel's Finder chords — since 2026-10-28; ⌃2 ⌃3 ⌃. NOT yet measured

The file panels (TUIFilePanels, `FilePanelCommand`) answer Finder's chords,
each written with ⌘ and resolved through `commandKey`, so under the default
`.control`: ⌃2 and ⌃3 (the views), ⌃⇧P (the preview), ⌃↑ and ⌃↓, ⌃⇧G,
⌃⇧H, ⌃⇧D, ⌥⌃L, ⌃⇧O, ⌃⇧A, ⌃⇧N, ⌃⇧. (hidden files) and ⌃. (cancel). What
reaches the app, from the records above and NOT re-measured for this:

- **⌃⇧ and a letter** arrives as ⌃ and the letter in every legacy encoding:
  the C0 byte has no case ("Control collides with the C0 range"; the
  `reportsShiftedKeys` capability). Under the kitty keyboard protocol it
  arrives with its capital. So these fire only under the protocol; a legacy
  ⌃P, ⌃D … is left to whatever reads it (a field's Emacs chord).
- **⌃↑ and ⌃↓** are Mission Control's on macOS, and Apple Terminal strips the
  modifiers from ↑ and ↓ ("Keys a sheet's grabber uses").
- **⌃⇧.** has no capital to carry its Shift: under the protocol with its
  alternate keys (flag 4) it arrives as ⌃> on a US layout, and without them
  as `.` with the Shift bit kept ("Shift on a printable key is the
  character"). The panel answers both, and does not read the second as ⌃.,
  its cancel.
- **⌃2, ⌃3 and ⌃.: NOT YET MEASURED.** By xterm's convention a legacy
  encoding sends ⌃2 as NUL (0x00, which `KeyEvent.parse` drops), ⌃3 as ESC
  (read as Escape: in a panel, Cancel) and ⌃. as a bare `.`, so none would
  arrive as itself; whether each host here follows the convention has not
  been checked. Measure with
  `Tools/TerminalProbes/key_probe.py` from each host's default profile.

So the panel's typed keys (Backspace, `~`, `/`, `+`, Escape) remain its route
on every terminal, and its status bar names the chords only where the kitty
keyboard protocol is on.

### Shifted function keys are re-coded (Apple Terminal)

Measured 2026-07-27, `cat -v` in Terminal.app 2.14 (455): **Shift+F10 emits
`^[[32~`**, not the `ESC[21;2~` that xterm, iTerm2, Ghostty and Warp send.
Terminal.app has no modifier parameter for function keys in either direction;
its key map instead substitutes a *different* key:

| Chord | Apple Terminal sends | Which is really | Everyone else sends |
|---|---|---|---|
| Shift+F5 | `ESC[25~` | F13 | `ESC[15;2~` |
| Shift+F6 | `ESC[26~` | F14 | `ESC[17;2~` |
| Shift+F7 | `ESC[28~` | F15 | `ESC[18;2~` |
| Shift+F8 | `ESC[29~` | F16 | `ESC[19;2~` |
| Shift+F9 | `ESC[31~` | F17 | `ESC[20;2~` |
| **Shift+F10** | **`ESC[32~`** | **F18** | `ESC[21;2~` |
| Shift+F11 | `ESC[33~` | F19 | `ESC[23;2~` |
| Shift+F12 | `ESC[34~` | F20 | `ESC[24;2~` |

(The VT220 block is 25–34 with 27 and 30 unassigned, which is where the gaps
come from. Option+Fn is aliased the same way onto F(n+5).)

The collision is unresolvable from the bytes, so TUI picks the reading that
is reachable on a Mac keyboard: **on Apple Terminal only**, `Terminal.finalize`
rewrites a decoded F13…F20 as Shift+F5…Shift+F12
(`KeyEvent.normalizingLegacyShiftedFunctionKeys()`). Elsewhere those sequences
stay F13…F20, which is what a keyboard that has those keys means by them.

Deliberately NOT normalised: Apple Terminal's **Option**+Fn aliasing. Its
collision partner is the plain F6…F12 that people press all the time, so
rewriting it would cost more than it buys.

This is why `.contextMenu`'s Shift+F10 route appeared dead: the binding was
correct, but `parseExtendedKey` stopped at 24, so `ESC[32~` decoded to nothing
and never became an event at all.

### The menu bar's keys — F10 and Alt-letter, documented, NOT yet measured

Added 2026-10-18 with the menu bar (lane O13; the owner's A28 answer of
2026-10-04 and the O13-KEYS default: F10, Alt and a letter, and a click). Nothing
here has been captured from a key press yet: pressing a key needs a person at the
keyboard, which the lane did not have. What follows is what each encoding and the
hosts' documentation say, and how TUI reads it.

| Key | What a host sends | TUI reads it as | Under the kitty keyboard protocol |
|---|---|---|---|
| **F10** | `ESC[21~`, the VT220 code, in the xterm family and Apple Terminal alike (Apple Terminal re-codes only the *shifted* function keys, above) | F10: the menu bar's bar mode, its first title lit and no menu open (`_MenuBarCore.isMenuBarKey`; owner, 2026-10-26, O13-KEYS) | `CSI 21~`, unchanged |
| **⌥ and a letter** | `ESC` and the letter where Option is sent as Meta (Apple Terminal's "Use Option as Meta key", iTerm2's Esc+, Ghostty's `macos-option-as-alt`; none the default — expected, not measured); otherwise the character Option composes (⌥F is `ƒ`), which no binding names | Alt and the letter: the menu whose letter it is opens (one per title, no two the same: `MenuBarMnemonics`), below any app shortcut on the chord (a framework default) | `CSI <letter>;3u` where the host reports Option as Alt; and where it composes (Ghostty 1.4.0's default, measured 2026-10-28 with `keyboard_events_probe.py`: ⌥F is `CSI 102;3;402u`, the key `f` with Alt and the text `ƒ`; ⌥⇧F `CSI 102:207;4;207u`; ⌥/ `CSI 47;3;247u`; ⌥⇧/ `CSI 47:191;4;191u`), the text is typed where something takes it, and otherwise the chord fires as the key Option was held with (`KeyEvent.optionComposedKey`; a non-letter's Shift form from a US layout, ⌥⇧/ as ⌥?) |
| A click on a title | SGR mouse reporting, as every click | opens that menu | the same |

**F10 on a Mac keyboard.** macOS gives the top row to the media keys: F10 is
Mute unless fn is held, or System Settings → Keyboard uses "F1, F2, etc. keys as
standard function keys". So the key is fn-F10 on a default Mac, and F10 on a
keyboard set the other way or a full-size one. No macOS default shortcut is on
F10 (unverified). Shift-F10 stays the context menu's (above).

**What reaches the bar on every host:** a click, and F10 (or fn-F10). Alt and a
letter work only where Option is sent as Meta, which is why the bar has F10 and
the click as well, and why every command's own shortcut works with the bar
closed. F10 enters the bar mode (2026-10-26, O13-KEYS): the first title lit, the
letters underlined whatever the host reports of Option, and the plain letter
opening its menu — so the letters reach every host there, where ⌥ and a letter
does not. macOS's own route to a menu bar, Control-F2, belongs to the terminal
emulator's menu bar and never reaches the app (expected, not measured).

*Still unmeasured (2026-10-26):* pressing a key needs a person at the keyboard —
the session that built the bar mode cannot send one (AppleScript is not
authorised, and the terminals take only clicks from it).

**Showing the letters (2026-10-24, lane MENUBAR).** Each title's letter is
underlined while Option is held — where the terminal tells TUI that Option
is held, which only a modifier key reported on its own does: the kitty keyboard
protocol's flag 8, "report all keys as escape codes" (below). So the letters
show in the hosts documented to speak the protocol — iTerm2, Ghostty, Warp,
kitty, WezTerm with its setting on — and never in Apple Terminal or under tmux,
neither of which speaks it; there the bar looks as it always did. None of this
is measured. Two things to check when it is: whether each host reports a lone
Option at all with its Option setting at the default (composing), and whether
it does so with Option sent as Alt. Where Option composes, the letters are
underlined while ⌥ and a letter types `ƒ` rather than opening the menu — the
letter shows a chord the host does not deliver.

**Which letter.** In bar order each title takes its first ASCII letter not
taken by a title before it, then the next letter of its own title; a title
with none left (or no ASCII letter, as a Japanese title) has none, and F10 and
the arrows reach it. A focused text field keeps the Option-letters it edits with
(⌥B and ⌥F, a word back and forward) — it is asked for a key before the bar's
letters, which are framework defaults — so while one has the focus the title
whose letter it keeps takes its next free letter (File's F becomes I in
English), and every other title keeps its own. An app's own shortcut on an
Option-letter chord wins over the bar's letter, as any app shortcut wins over a
framework default.

*To measure — `Tools/TerminalProbes/key_probe.py`*, which asks for F10 and ⌥F
after the grabber's keys: run it in Apple Terminal, iTerm2 and Ghostty from each
default profile, and record whether F10 or fn-F10 was pressed, the
standard-function-keys setting, and each host's Option setting.

### The help key, `?`, `⌥?` and `⇧F1` — ⇧F1 measured 2026-10-28, ⌥? in Ghostty only

Added 2026-10-24 (lane MENUBAR; the owner's B-HELP-2 answer: no one key for
two purposes, and a modifier on `?` for showing every tooltip). `?` reveals the
focused control's tooltip (`TooltipState.helpKey`); `⌥?` shows every tooltip on
the screen, or hides them again — the menu bar's Help ▸ Show All Tooltips.

| Key | What a host sends | TUI reads it as | Under the kitty keyboard protocol |
|---|---|---|---|
| **?** | `?` | the help key, unless a focused text control types it | the text `?` |
| **⌥?** | `ESC ?` where Option is sent as Meta (none the default, as for the menu bar's letters above); otherwise the character Option composes (`¿` on a US layout), which is typed or ignored | Alt and `?`: every tooltip shows, or hides. A focused text field does not type an Option chord, so it reaches the key inside a field too, where `?` alone is typed | `CSI 47:63;4u` (Shift and Alt on `/`, its shifted key `?`) where the host reports Option as Alt; where it composes (Ghostty 1.4.0's default, measured 2026-10-28) `CSI 47:191;4;191u`, read as ⌥? through `KeyEvent.optionComposedKey` (the menu bar's row above) |
| ⌃? | `DEL` (`0x7F`), the Backspace byte, in every legacy encoding | Backspace | unusable: the legacy encodings cannot tell it from Backspace, so it is not used |
| **⇧F1** | `CSI 1;2P` in iTerm2 3.7.6, Ghostty 1.4.0 and Warp v0.2026.10.21 (measured 2026-10-28 with `key_probe.py`, default profiles, macOS 15.8.1); **nothing at all in Apple Terminal 455.1**, for ⇧F1 or fn-⇧F1 — its re-coding of the shifted F-keys (below) does not reach F1 | Shift and F1: every tooltip shows, or hides, as for ⌥?, but in the chain's last layer, so any handler of the app's or a built-in view's on the chord takes it first (owner ruling B-HELP-2, 2026-10-26: the portable key, where Option does not arrive) | `CSI 1;2P` |

**Why Option and not another modifier:** Shift is already in `?` on most layouts,
and Control-? is Backspace wherever the kitty protocol is not spoken. Option is
the one that survives, where the host sends it as Meta; elsewhere the menu item
is the way to it (F10, ← to Help, ↓), as the menu bar is to everything. An F-key
was declined for the help key itself (F-keys are often taken system-wide).

**Apple Terminal reaches neither chord from its default profile:** it sends no
Meta, so ⌥? arrives as `¿`, and it sends nothing for ⇧F1 (measured above).
There Help ▸ Show All Tooltips is the way to it (F10, ← to Help, ↓), or ⌥? once
"Use Option as Meta key" is on. ⇧F1 still earns its place in the three hosts
that send it, where Option may compose instead (iTerm2's and Warp's defaults).

*Still to measure:* `⌥?` with `Tools/TerminalProbes/key_probe.py` in Apple
Terminal, iTerm2 and Warp, with each Option setting.

### Modified F1–F4 are CSI letters (xterm) — decoded since 2026-10-05

F1–F4 alone arrive as SS3 (`ESC O P` … `ESC O S`), but with a modifier xterm,
iTerm2, Ghostty and Warp send them as CSI letters with the modifier code:
`CSI 1 ; m P` … `CSI 1 ; m S`, so Shift-F3 is `ESC[1;2R` and Ctrl-F1
`ESC[1;5P` (from xterm's ctlseqs; not captured here). The parser dropped all
four until 2026-10-05. It reads them now, for the first parameter 1 and a
modifier code from 1 to 16, and nothing else ending in those letters.

`CSI 1;m R` is also a cursor-position report for row 1, column m. That is safe
to read as F3 only because TUI asks for no cursor report: since the startup
exchanges moved to the `CSI 5 n` fence (same day, "Asking the terminal —
Device Attributes"), nothing in TUI sends `CSI 6 n`, and
`CursorReportRequestScanTests` fails if any code under `Sources/` spells one.
Anything that brings a cursor-report request back must stop decoding `R`
first, or its report arrives as Shift-F3 and the like. (An app that writes
`CSI 6 n` to the terminal itself is outside what the scan can see.) Under the kitty keyboard protocol F3 is
`CSI 13 ~`, precisely to avoid this collision; P, Q and S keep their letters
there and are decoded by `KittyKeyDecoder`.

## The kitty keyboard protocol — documented, NOT yet measured

Added 2026-10-04 with TUI's negotiation of it (decisions A4). **Nothing in
this section has been captured from a real terminal yet.** It records what the
specification says and what each terminal's own documentation, or the
specification's list of implementations, says, so the measurements can be
checked against it. The probes that will measure it are
`Tools/TerminalProbes/keyboard_protocol_probe.py` (does it answer, which flags
does it take) and `Tools/TerminalProbes/keyboard_events_probe.py` (what each key
sends with the flags pushed). Replace each "documented" below with a
version-stamped measurement as it is made.

### What TUI does

The specification is <https://sw.kovidgoyal.net/kitty/keyboard-protocol/>.

- **Asks** at startup, after raw mode is on: `CSI ? u` (report the current
  flags), at the head of the startup colour exchange, whose `CSI 5 n` fence
  every measured terminal answers. A fence answered without a `CSI ? flags u`
  answer means the terminal does not speak the protocol: the specification's
  own detection, which fences with `CSI c` (DA1), with another fence — a
  terminal answers in order, so any answered request behind the question
  serves. So a terminal that does not speak the protocol pays no round trip
  for being asked (until 2026-10-04's review it paid one, `CSI ? u CSI c` on
  its own). Not asked of Apple Terminal, which does not speak it (and is not
  in the specification's list). `CSI ? u` is a `?` with no intermediate byte, the shape
  measured clean on Apple Terminal 455.1 ("Asking the terminal — Device
  Attributes"), so an unidentified Apple Terminal behind ssh is asked safely.
- **Pushes** `CSI > 31 u` where it answered, and asks again: a terminal may
  take only some flags, and the second answer is what TUI reads keys by. If
  it took flag 8 without flag 16, the push is replaced by one without 8 (see
  the flags below). One round trip in all, two with that replacement, and
  only on a terminal that speaks the protocol. **A second answer that misses the
  window** (0.5 s; a slow ssh link) is taken as the push granted, since the
  terminal that answered the first question now encodes keys by the push:
  read as legacy bytes, Return, `q` and Ctrl-C would all be dropped and the app
  could not be typed at or quit (found in review, 2026-10-04). The protocol's
  grammar decodes a key whichever flags were taken, so the only cost of the
  guess is `\.terminalCapabilities` claiming the keyboard features asked for; the late answer
  is dropped as input, as any reply is.
- **Pops** with `CSI < u` on quit, on a suspend (SIGTSTP, or a Ctrl-Z the undo
  keys leave unbound), on `SIGINT` and `SIGTERM` (an
  orderly shutdown), and on any signal that would end the process with
  nothing run on the way out — a trap, a bad access, `abort`, `SIGQUIT`,
  `SIGSYS`, and the quiet terminations nothing in TUI handles (`SIGHUP`,
  `SIGUSR1`, `SIGUSR2`, `SIGALRM`, `SIGVTALRM`, `SIGPROF`, `SIGXCPU`,
  `SIGXFSZ`, each taken only while the app has not installed a handler or an
  ignore of its own) — always before leaving the alternate screen; **pushes
  again** on resume without asking. On those signals the handler also turns
  off every other input mode the app turned on and puts the shell's termios
  back, so the shell echoes and reads lines again; it leaves the alternate
  screen up, with a crash's report on it (`FatalSignalTerminalRestore`) —
  except on `SIGQUIT`, the user's quit, which since 2026-10-05 leaves it as
  a quit does and ends by its default action, never through the Swift
  runtime's crash reporter (until then a `kill -QUIT` printed a backtrace on
  the alternate screen and waited half a minute for a key).
  Until 2026-10-04's review only the crash signals were taken, and a
  `kill -HUP` left the flags pushed and the line discipline raw. The specification keeps a separate
  flag stack per screen and TUI pushes on the alternate one, so the shell's
  own screen is never changed.
- **Quits on ⌃\\'s report**: under the protocol the user's quit key is a
  `CSI u` report the line discipline never turns into `SIGQUIT`, so the input
  chain raises the signal for it where none of the app's bindings takes it
  ("The quit key, ⌃\\").
- **Pops its flags when the app stalls**: input left unread for 1.5 s has the
  stall watchdog pop them, so a hung app's next ⌃\\ is the byte the driver
  quits on; a loop that recovers pushes them back ("The quit key, ⌃\\").
- **Publishes** what was taken as `\.terminalCapabilities`' keyboard features
  (`.disambiguatedKeys` to `.numericPad`), so an app can tell which of
  SwiftUI's keyboard features work here.
- **Stays out** where `TUI_KEYBOARD_PROTOCOL=0` is set: the user's way out
  should a terminal claim the protocol and encode keys in a way TUI
  misreads, as `TUI_HYPERLINKS=0` is for links.

`Tools/Smoke/keyboard_protocol_smoke.py` checks all of that against a PTY
that plays a terminal by the specification (CI runs it). That checks TUI,
not any terminal.

### The flags, and why all five

| Flag | Enhancement | What it buys | Why it is safe |
|---|---|---|---|
| 1 | disambiguate escape codes | Escape as `CSI 27 u` (no Escape-vs-sequence timeout); Ctrl-H, Ctrl-I, Ctrl-J, Ctrl-M and Ctrl-[ as themselves; every Control/Option chord on an ASCII key as a `CSI u` report | one of the five chords that nothing binds is offered again as Backspace, Tab, Return or Escape, what the legacy encodings made of it |
| 2 | report event types | repeats (`:2`) and releases (`:3`) | every layer but `onKeyPress` ignores a release; a repeat is a press to all of them |
| 4 | report alternate keys | the shifted key of a chord (Ctrl-Shift-Z reports `z:Z`, decoded as `Z`), and the base-layout key, so Ctrl-С on a Russian layout is Ctrl-C | — |
| 8 | report all keys as escape codes | a modifier key pressed alone; Caps Lock on every key; the keypad's digits as keypad keys; releases of Return, Tab and Backspace | the text a key types is taken from flag 16, not reconstructed |
| 16 | report associated text | the text a key typed, inside its report | — |

**Flag 8 is the dangerous one, and flag 16 is what makes it safe.** With 8 on,
a plain letter is no longer sent as its text: `a` arrives as `CSI 97 u`. Text
reconstructed from key codes would be wrong for every shifted character on a
non-US layout, every dead key (´ then e), every compose sequence and every
input method. Flag 16 puts the text the terminal composed back into the report
(`CSI 97 ; ; 97 u`, `CSI 101 ; ; 233 u` for é), and TUI takes the text as
the keystroke, as it took the legacy bytes. Text arrives without the Control or
Option it consumed (Option-S typing ß arrives as ß, as it does in a legacy
encoding) and with Shift as the text's case ("Shift on a printable key is
the character, not a bit").

**What 8 costs:** with it on, Return is `CSI 13 u`. A process that dies with
the flags pushed and the alternate screen still up leaves a shell that cannot
read Return, so `reset` cannot even be typed. Hence the pop on every signal
that ends the process and that TUI can catch (above). `SIGKILL` (and an
out-of-memory kill) cannot be caught: the terminal is then left on the
alternate screen with the flags pushed. Closing the tab recovers it, and so does any terminal action that
resets the terminal (kitty's "reset terminal", for one); typing `tput rmcup`
blind does not, Return being an escape code. Flags 1 and 2 alone would not have
this problem — the specification keeps Return, Tab and Backspace legacy under
them for exactly this reason — and would lose the modifier keys, Caps Lock and
the keypad.

**Bracketed paste is separate** and unchanged: a paste still arrives between
`CSI 200 ~` and `CSI 201 ~`, not as key reports.

### How keys decode (`KittyKeyDecoder`)

- A report with text **is** the text, one key event per character (an input
  method committing a word through one key gives several), Shift as the
  character's case (`A` has it, `!` does not, as in a legacy encoding),
  Control and Option dropped.
- A report without text (a Control or Option chord, a release, a key that types
  nothing) uses the shifted key when Shift is held, its Shift then being that
  key's case; else, with Shift held on a letter and no shifted key reported,
  the capital; else the base-layout key for a Control/Option chord on a
  non-ASCII key, else the key itself.
- **A release is the key its press was.** A release carries no text, only the
  key's code, so decoded on its own it would disagree with the press: Caps
  Lock's `A` came up as `a`, a dead key's `é` as `e`, and
  `onKeyPress("A", phases: .up)` never heard the key it heard go down (found
  in review, 2026-10-04). The parser remembers each key's press by its code
  (`KittyKeyMemory`) and delivers its key events again on the release, with
  the press's modifiers; a release of a key it did not see go down is decoded
  from its code.
- **Bit 8 means Super (⌘), not Meta.** In xterm's legacy modifier parameter the
  same bit is Meta, which terminals send for Option, and TUI's legacy parser
  reads it as Option ("Option arrives in two different spellings"). Under the
  protocol a chord on Super that types no text is **delivered as ⌘**
  (`KeyEvent.command`; the owner's ruling B-D1K-1, 2026-10-23 — until then it
  was dropped), and the input chain offers it only to `onKeyPress` handlers and
  to the shortcuts an app has asked to match a real ⌘
  (`InputHandler.dispatchCommandChord`): delivered to anything that matches a
  bare key, ⌘K would type a `k`. A chord on Hyper or Meta that types no text is
  still **dropped**, reporting only the modifier state: SwiftUI has no modifier
  for either. ⌘ held on its own is reported as a modifier key. *If a host sends
  Option-as-Meta in bit 8 under the protocol, its ⌥ chords arrive as ⌘ chords —
  check this when measuring.*
- A modifier key's own report sets its modifier from the keys of its kind
  known to be down, this one included or not by its event, whatever the
  terminal reported for the bit: with both Shift keys held, letting one go
  leaves Shift held (it reported Shift released until 2026-10-04's review).
  The specification says the bit includes the event's own effect; the decoder
  does not depend on every terminal agreeing. Caps Lock toggles, so its bit is
  taken as reported.
- Every other key report carries the modifiers held too, and where they
  disagree with the state last reported, the state is reported again first:
  a modifier's release that went to another window, or a press made before
  the app started, is put right by the next key. And when the terminal
  reports losing the focus (mode 1004), every key and modifier held is
  forgotten and reported released (Caps Lock kept): a ⌘ held for ⌘-Tab would
  otherwise stay held, its release sent to the other window, and a
  `modifierKeyAlternate(.command)` stay drawn on the way back. Whether a
  terminal itself reports releases on losing the focus is unmeasured; the
  rule holds either way.
- **A pop forgets them too** — on the way into a suspend, as on the way out:
  the decoder's memory goes with the protocol, and every modifier is reported
  released (Caps Lock kept, as at a focus loss) if one was held in the state
  last reported, delivered at the first read after the resume. After the
  re-push, the first key report that differs from that state reports the
  state again: a modifier held through `fg`, or Caps Lock changed in the
  shell. That needs the lock bit in the report, so where negotiation drops
  flag 8 (typed text then arrives as plain bytes), a Caps Lock turned off in
  the shell reads as on until the first key that is not text, as after a
  focus loss. Until the 2026-10-05 review the app kept the state it had: a Ctrl
  held for the Ctrl-Z that suspended it and released in the shell matched
  the fresh memory's "nothing held", so no report came, and a
  `modifierKeyAlternate(.control)` stayed drawn after `fg` until Ctrl was
  pressed again. The first fix reported Caps Lock off at the pop too, so an
  app watching it heard it go off at every resume and on again at the first
  key (the third review).
- The PC keyboard's Menu key (functional key 57363) decodes as `Key.menu`
  (added 2026-10-05), which opens a context menu wherever Shift+F10 does — a
  `.contextMenu`, a list's or table's row menu, a tab's. The legacy encodings
  send nothing for it that tells it from another key, so it arrives only
  here. Which terminals report it, and under which flags, is unmeasured: the
  specification lists it among the functional keys.
- Keys TUI has no `Key` for are dropped: Insert, the keypad's Begin, Print
  Screen, Pause, F21 and up, the media keys.

### Which terminals — documented

The specification lists these implementations (fetched 2026-10-04): kitty
itself, AbsoluteTelnet, Alacritty, foot, **Ghostty**, **iTerm2**, Microsoft
Terminal, rio, TuiOS, **Warp**, WezTerm (behind its `enable_kitty_keyboard`
setting) and xterm.js. Of the hosts measured elsewhere in this document:

| Host | Documented | Notes |
|---|---|---|
| Apple Terminal | **no** | not in the list; TUI does not ask |
| iTerm2 | yes | in the list; iTerm2's own CSI u page says its CSI u mode "is no longer recommended. Applications should implement the Kitty keyboard protocol instead". Which flags it takes, and what Option set to Esc+ sends under the protocol, unmeasured |
| Ghostty | yes | in the list; its configuration reference names no setting for it |
| Warp | yes | in the list, by an issue comment; nothing else known |
| tmux | no | not in the list. Its own `extended-keys` (CSI u or modifyOtherKeys) is a different scheme TUI does not ask for; under tmux the query is answered (or not) by tmux, not by the client |
| xterm.js | yes | in the list |

### To measure, per host

Run `keyboard_protocol_probe.py` (one line of JSON: whether it answered, and
the flags before, after the push and after the pop), then
`keyboard_events_probe.py`, and press in order: `a`, Shift-`a`, Shift-`1`, Caps
Lock then `a` (and Caps Lock again), Option-`e` then `e` (a dead key), Ctrl-`h`,
Ctrl-`i`, Ctrl-`m`, Ctrl-`[`, Escape, Ctrl-Shift-`z`, Ctrl-`-`, Ctrl-Shift-`-`,
Option-Shift-`-`, ⌘-`k`, Shift alone, Option alone, ⌘ alone, keypad `5` and
keypad Enter (where there is a keypad), an arrow held until it repeats, and a
paste. Record per host and version:

1. Whether it answers, and which flags it takes of 31.
2. Whether a release is reported for each key, and whether a held key's repeats
   are `:2`.
3. Whether text arrives in the report (flag 16) for each typing key, the dead
   key included, and for an input method if one is installed.
4. What Option sends — Alt (bit 2), text, or bit 8 — under each of the host's
   Option settings.
5. Which ⌘ chords reach the app at all (bit 8), and whether ⌘ alone is
   reported.
6. Whether a modifier key's own bit, on its press and on its release, includes
   the event (the decoder copes either way; the record is for the
   specification).

## Undo and redo — the keys, documented, NOT yet measured

Added 2026-10-04 with the app's `UndoManager` (`\.undoManager`, decisions A1).
A terminal app has no Edit menu and cannot receive ⌘Z, and no key reaches every
terminal unclaimed; the owner chose these, and the status bar's "undo" and
"redo" items (shown while there is a step for each, performed by a click) are
the route on every terminal. Nothing below has been captured yet — measure it
with `keyboard_events_probe.py` (kitty protocol hosts) or `cat -v` / a raw-mode
`od -c` (the rest), and replace "expected" with what the host sent.

The keys are data: `UndoCommand.defaultShortcuts`, which an app replaces for
either command, app-wide, with the TUI-only scene modifier
`.undoShortcuts([.undo: …, .redo: …])` (a `ShortcutSet` each, under the rules
of `rowShortcuts`). The defaults, and what each terminal makes of them:

| Key | Legacy bytes | Read as | Kitty protocol |
|---|---|---|---|
| **Undo:** Ctrl-Z | `0x1A` | Ctrl-Z: **undo** (since 2026-10-04; before, the shell's suspend) | `CSI 122;5u`: undo |
| **Undo:** Ctrl-minus | `0x1F` (`^_`), by the xterm convention most terminals follow | Ctrl-minus — `KeyEvent.parse`, since 2026-10-04 (it used to drop the byte) | `CSI 45;5u` |
| **Undo:** Ctrl-/ | `0x1F` too, on most terminals | Ctrl-minus: **undo** | `CSI 47;5u`: undo |
| **Redo:** Ctrl-Y | `0x19` on every terminal in raw mode, which clears BSD's delayed-suspend character (`Terminal+LineDiscipline.swift`) | Ctrl-Y: **redo** — but in a focused text field or editor, its **yank** (since 2026-10-24, FB9-REDO) | `CSI 121;5u`: the same |
| **Redo:** Ctrl-Shift-minus (Ctrl-_) | `0x1F` — the same byte | Ctrl-minus: **undo**, not redo | `CSI 45:95;6u`: redo (with flag 4; Ctrl-Shift-minus, so undo, without it) |
| **Redo:** Ctrl-Shift-Z | `0x1A`, Ctrl-Z | Ctrl-Z: **undo**, not redo | `CSI 122:90;6u`: redo (with or without flag 4: a letter's capital is known) |
| **Redo:** Option-_ (Option-Shift-minus) | `ESC _` where Option is sent as Meta; otherwise the composed `—` | Option-_, once the parser's dead-sequence wait (about 200 ms) is up — `ESC _` is also an APC reply's introducer; see below | `CSI 45:95;4u` where the host reports Option as Alt; the text `—` where it composes |

So on a legacy terminal undo is always on the keyboard, and so is redo, as
Ctrl-Y, outside a text control (the owner's ruling FB9-REDO, 2026-10-23); in a
text field or editor, which keeps Ctrl-Y for its yank, redo is on the keyboard
only where Option is sent as Meta (Apple Terminal's "Use Option as Meta key",
iTerm2's Esc+, Ghostty's `macos-option-as-alt`; none of them is the default on
every host — expected, not measured), and otherwise is the status bar's and the
menu bar's. Where the kitty keyboard protocol is on (see that section),
Ctrl-Shift-Z and Ctrl-_ redo as on a Mac.

**A bound key is its command's, step or no step.** With nothing to undo,
Ctrl-Z does nothing: it never suspends the app some of the time and undoes
the rest. **Ctrl-Z unbound suspends again, exactly as before:** an app whose
users expect the shell's `^Z` writes
`.undoShortcuts([.undo: .only(.init("-", modifiers: .control), .init("/", modifiers: .control))])`,
and an unclaimed Ctrl-Z — or Ctrl-Shift-Z, which a legacy encoding cannot tell
from it, wherever redo leaves it unbound — reaches layer 4 and is re-raised as
SIGTSTP. A focused text control's own Ctrl-Z, the stand-in for ⌘Z, stays its
undo either way, as it was before the app had one.

**The suspend key is wider than undo's.** Layer 4 suspends on any Control
chord on `z` that reaches it, whatever else is held — the matcher
(`InputHandler.dispatchPress`) is the one it was before the app had an undo,
kept as it was. So:

- **Ctrl-Option-Z suspends**, with the default keys too: it is not one of
  undo's, so nothing takes it before layer 4. It arrives as `ESC 0x1A` where
  Option is sent as Meta and `CSI 122;7u` under the kitty protocol. That is
  the shell's own reading of it: in a cooked terminal `ESC 0x1A` is an Escape
  and then the `^Z` byte the line discipline turns into SIGTSTP (from the
  line discipline's definition; not measured).
- **Under the kitty protocol, `.redo: .unbound`** (or any redo list without
  Ctrl-Shift-Z) leaves Ctrl-Shift-Z to suspend again, as it does in the shell,
  where it is `0x1A`. With redo's defaults it is redo, step or no step.

Narrowing the matcher to the chords undo would take was weighed and not done:
it would make Ctrl-Option-Z and an unbound Ctrl-Shift-Z do nothing at all in
a TUI app while they suspend at the shell prompt beside it, and the rule
"a bound key is its command's, step or no step" is about the bound keys
only. An app that wants either chord to do something else binds it.

**The status bar names the first key the terminal can deliver** as itself:
the bound keys in `KeyboardShortcut` order, TUI's own first, filtered by
what the terminal's keyboard features (`\.terminalCapabilities`) say can be
sent — in a legacy encoding a Control chord only on a letter (bar Ctrl-H, I, J, M) or
minus, and never with Shift; under the protocol any Control chord, one on a
shifted character only with flag 4; an Option chord always, since whether
Option is Meta cannot be asked. With the defaults that is `^-` for undo
everywhere, and for redo `⌃⇧Z` under the protocol and `⌃Y` elsewhere — but
`⌥_` while a text control has the focus, whose Ctrl-Y is its yank: the hint
follows the focus (`AppUndoKeys.hint(for:sparing:)`, FB9-REDO), and so does the
menu bar's Edit ▸ Redo. A command
with no key the terminal can deliver is shown with none, its click still
working. **The bar names the key; it does not bind it** — the undo keys above
are matched only at the bottom of the input chain. Until the 2026-10-05 review
the items took the name as their own shortcut, which the bar reads as a bare
key at layer 1, ahead of every view: an app's Option-← undo (`M-←`) made a
plain ← undo, and a vim-style bare `u` undid ahead of a list's type select
while there was a step and reached it while there was not.

**Ctrl-Y is redo, but in a text control** (the owner's ruling FB9-REDO,
2026-10-23, option (a); until then it was not bound): it is the one redo key
every terminal sends, `0x19` — on BSD-derived ttys the "delayed suspend"
character, which raw mode clears — and redo on Windows and in many Linux
editors. It is also the text controls' yank (the Emacs and Cocoa binding),
and a focused field or editor takes it first, as it takes every key it edits
with, so there it yanks, with or without a kill to yank. An app that wants it
gone lists the others:
`.undoShortcuts([.redo: .only(.init("z", modifiers: [.control, .shift]), .init("_", modifiers: .control), .init("_", modifiers: .option))])`.

**`ESC _` is two things.** A meta-sending terminal's Option-_ and the introducer
of an APC reply (`ESC _ G … ESC \`, a graphics acknowledgement) are the same two
bytes. The parser waits for the reply's terminator; when nothing at all follows
the pair for the dead-sequence wait, no reply can be meant, and it delivers
Option-_ (`Terminal+Input.swift`, `resolveStuckPartial`). The same rule makes
Option-], Option-P, Option-X and Option-^ deliverable. A key pressed within that
wait after the chord still ends it as an interrupted reply, and the chord is
lost.

**An app's own shortcut wins.** The undo and redo keys are default bindings at
the bottom of the input chain: under `.commandKey(.control)` an app's ⌘- (zoom
out) is Ctrl-minus, and it keeps the key; undo is then on the others. **So
does a focused control that takes the key** — but a Slider or Stepper declines
a Control or Option chord on its `+ = - _` keys (until the 2026-10-04 review it
took Ctrl-minus and Option-_ as a decrement, and undo and redo never ran).

## Mouse button codes: bit 7 means two different things

The SGR button code packs modifiers and group bits around a two-bit button
number, and **bit 7 (`+128`) is overloaded**:

| Code | With bit 6 (wheel) set | Without it |
|---|---|---|
| `+128` | horizontal wheel — the form some terminals use instead of buttons 66/67 | xterm's extended button **group 8–11** |

Both forms are real and both are in the wild, so the reading depends on the
wheel bit. Buttons 8–11 are a five-button mouse's back/forward pair plus two
more with no agreed meaning; they are numbered in the *same low two bits* that
mean left/middle/right, so a decoder that ignores bit 7 outside the wheel group
turns a press of "back" into a left click wherever the pointer happens to be.
TUI has no notion of those buttons and declines the report
(`MouseEvent.decodeSGRButton`); the horizontal-wheel reading is unaffected.

Not measured per terminal — this follows xterm's `ctlseqs` definition rather
than an observation, and no terminal surveyed here was seen to send 8–11 during
the probes (no five-button mouse was attached).

## Wheel reports per notch — a host's choice, not normalised

Terminals send different numbers of wheel reports for one notch of a mouse
wheel, because most of them pass on the operating system's accelerated scroll
delta. A third-party measurement on one Mac (OpenAI Codex's tui2
`scroll_input_model.md`, logs of 2025-12-19; that machine's scroll settings are
unknown, and it was **not reproduced here**) counted: iTerm2 1, WezTerm 1,
Apple Terminal 3, kitty 3, Alacritty 3, Ghostty 9, Warp 9. TUI scrolls 3 rows
per report, so one notch moves 3 to 27 rows depending on the host.

**Decided 2026-10-12 (the owner): TUI does not normalise it.** "Each
terminal client's scroll speed is a choice they make, and by extension their
users' choice for using that client." Merging the reports that arrive in one
read into one step was considered and declined.

No terminal sends a scroll delta, a phase or a velocity (session notes
`SCROLLX/notes.md`, 2026-10-12, from each host's source): SwiftUI's
`ScrollPhaseChangeContext.velocity` is therefore (0, 0) at the start and end of
scrolling (B27). Mode 1016 (SGR-Pixels) reports pixel positions, not scroll
amounts, and shares one setting with 1006 (the last mode set wins); see
[Future options](<../Future options.md#sgr-pixels-mouse-reports-mode-1016>).

## Shift-clicks reaching the app (XTSHIFTESCAPE)

**Status: sent since 2026-10-18; every host UNMEASURED.**

**What TUI does.** Whenever it turns mouse reporting on it sends
XTSHIFTESCAPE, `CSI > 1 s`, asking the terminal to report Shift-modified
mouse events to the app rather than keep them for its own selection; as
reporting goes off it sends `CSI > 0 s`, handing Shift back, and the teardown
and the debt a signal pays owe the same (`Terminal.applyMouseSupport`,
`inputModesOwed`). App-wide, as the Ghostty study's C5 recommended once
TUI drew its own screen selection (A13): a Shift-click extends a list's,
a table's or a text control's selection, and TUI's own drag selects the
screen, so the terminal's Shift-drag selection is the one given up. Not sent
on Apple Terminal, which reports the Shift bit and has no Shift bypass to
turn off, and whose reading of `CSI > … s` is unmeasured (a parser that
ignored the `>` would save the cursor, SCOSC). `TUI_SHIFT_CLICKS=0` keeps
it from being sent anywhere, the user's way back to the terminal's own
Shift-click and Shift-drag.

**What each host is expected to do**, from its documentation, none of it
measured here:

| Host | `CSI > 1 s` | Shift-click with it | Measured |
|---|---|---|---|
| Ghostty | honoured under the default `mouse-shift-capture = false`; its `never` and `always` override the app (Ghostty's VT reference) | reported, +4 | UNMEASURED |
| iTerm2 | nothing documented; expected to ignore it | selects text (the OSC 8 table above) | UNMEASURED |
| Warp | nothing documented; expected to ignore it | selects text (the OSC 8 table above) | UNMEASURED |
| kitty, xterm | xterm defines it (`shiftEscape`); kitty unknown | — | UNMEASURED |
| Apple Terminal | not sent | reported, +4 (no bypass; the Shift-drag note above) | UNMEASURED |
| tmux | unknown whether it forwards it | — | UNMEASURED |

**To measure**, by hand, since a probe cannot press Shift on a click:
`PROBE_SHIFT_ESCAPE=1 python3 Tools/TerminalProbes/mouse_probe.py` in each
host, Shift-click and Shift-drag, then the same without the variable; a
reported Shift-click is a `<4;x;yM` line in the log, one the terminal kept is
no line at all, and anything the terminal answers to the sequence is logged
ahead of the first event.

## Pointer shapes (OSC 22)

**Status: sent since 2026-10-19 where a host DOCUMENTS it. iTerm2 3.7.6
MEASURED 2026-10-19, its names and its reset, so TUI's own controls' shapes
are on there; every other host UNMEASURED, and
`Tools/TerminalProbes/pointer_shape_card.py` awaits the owner's reading of
each.**

**What TUI does.** `View.pointerStyle(_:)` files a region the size of its
view with the style's shape. After every batch of input, and after every
frame, the run loop resolves the shape under the pointer — the innermost
style on the view in front there, or the control's own — and writes
`ESC ] 22 ; name ESC \` when it differs from what it last sent
(`Terminal.showPointerShape`, `TerminalHostState`), in the host's own names
(`PointerShapeHost`). Motion reporting (mode 1003) is asked for only while a
style is on screen. Once a shape has been sent, the teardown — a quit and a
Ctrl-Z alike — writes the empty name, every host's reset, BEFORE the mouse
modes go off, and the debt a fatal signal pays begins with the same
(`Terminal.inputModesOwed`); an app that has sent none writes no OSC 22 as it
leaves: it has nothing to put back, and on a host whose reset is unread the
empty name is unmeasured too. After any
mouse mode change the shape is written again, because Ghostty resets it on
one. A host not in the table below is sent nothing and owed nothing.
`TUI_POINTER_SHAPES=0` turns it off, and `1` turns it on for a host not in
the table (in CSS names). TUI's own controls' shapes (the I-beam over a text
field, a hand over a link, a resize arrow over a divider or a table's column
edge) are on wherever shapes are set at all, and `apps` keeps the shapes to
the app's own `pointerStyle(_:)`. Until 2026-10-28 they were on only where a
host's reset had been read off the card (iTerm2); the owner ruled to take
every documented reset as so, since the teardown writes it in every way out.

**What each host is documented to do**, read 2026-10-19 from its
documentation and its source (copies under the lane's notes, `O12/docs`):

| Host | Since | Names | No style, mid-run | Reset | Detected by | Measured |
|---|---|---|---|---|---|---|
| Ghostty | 1.0.0 (its VT reference) | CSS, and xterm's X11 names as aliases (`mouse.zig`) | `default`: an empty name is ignored before its `mouse_shape_reset` | any mouse mode set gives the arrow, any reset the I-beam (`stream_handler.zig`); an empty name gives one of those (newer releases) | `TERM_PROGRAM=ghostty` with its version, or `TERM=xterm-ghostty` | 1.3.1 on macOS, 2026-10-19: seven CSS names ignored, the pointer kept as it was; the reset UNREAD (below) |
| kitty | 0.31.0 (its pointer-shapes page) | CSS (thirty) | empty | empty; a stack per screen, so leaving the alternate screen leaves its shapes behind | `TERM=xterm-kitty`, or `KITTY_WINDOW_ID` where no other terminal is named (every program a shell starts inherits it) | UNMEASURED |
| foot | 1.12.0 (its changelog) | CSS, X11 fallbacks | empty | empty | `TERM=foot`, `foot-…` | UNMEASURED |
| iTerm2 | 3.5.0, the table unchanged to 3.6.11 (`PTYSession.screenSetPointerShape`) | nineteen X11 names; no open or closed hand, zoom, vertical I-beam or diagonal | empty | empty (an unknown name is its own pointer) | `TERM_PROGRAM=iTerm.app` or `LC_TERMINAL=iTerm2`, with the version beside it | 3.7.6, 2026-10-19: every name draws; a new shape shows only after a click; the shell's pointer is back after the card (below) |
| xterm | patch #367 (its changelog) | the X11 cursor font | empty | empty: the `pointerShape` resource's default | `XTERM_VERSION`, where no other terminal is named | UNMEASURED |
| Apple Terminal | — | documents none | — | — | not sent | — |
| Warp | — | documents none | — | — | not sent | — |
| tmux | — | unknown whether it forwards OSC 22; the hypothesis is that it drops it | — | — | not sent | UNMEASURED |
| GNU screen, zellij | — | unknown whether either forwards OSC 22; like tmux, each draws its panes itself, and `TERM_PROGRAM` inside names the terminal outside | — | — | not sent (`STY`; `ZELLIJ`, `ZELLIJ_SESSION_NAME`) | UNMEASURED |

A version stated in the environment below the "since" column turns a host
off; a host that states none is taken to be recent, since every one of them
parses OSC and an older one swallows the sequence. A style a host has no name
for gives it its own pointer rather than leaving the last shape up.

**What is unmeasured, and what the card asks.** Everything that matters here
happens outside the byte stream, so nothing above is measured: whether each
name draws the shape its style describes; whether the empty name, the mouse
modes going off, or leaving the alternate screen gives the shell its own
pointer back on a quit and on a Ctrl-Z; whether a mode change loses a shape
(Ghostty's source says it does, and TUI writes it again); and what tmux
does with the sequence. `python3 Tools/TerminalProbes/pointer_shape_card.py`
draws a box per style, gives the pointer each box's shape as it moves on, and
offers four ways out (TUI's, and three others that tell which reset a host
needs) and a suspend. Its reading, per host, belongs in this section; a host
whose reset reads clean turns on TUI's own controls' shapes there
(`PointerShapeHost.resetIsMeasured`). `pointerVisibility(_:)` stays refused
unless the card shows a name that hides the pointer.

**iTerm2 3.7.6, 2026-10-19** (the card, which took iTerm2's names from the
environment, read by the owner on this machine, primary screen, macOS
15.8.1):

- **Every box with an iTerm2 name drew its shape**: the twelve the table
  gives one, `arrow`, `xterm`, `hand2`, the four single arrows, the two
  double arrows (for a column, a row and a frame's top edge both ways) and
  `crosshair`.
- **Every box without one showed iTerm2's own pointer**, the I-beam over its
  text: `.verticalText`, `.grabIdle`, `.grabActive`, `.zoomIn`, `.zoomOut`
  and the three diagonal frame boxes. That is the empty name doing what the
  table says it does, and what TUI sends for a style a host has no name
  for. (`.horizontalText` shows the I-beam too, as its own name, `xterm`.)
- **A new shape showed only after a click in the window**, even with the
  window frontmost and focused: moving onto a box was not enough. So on
  iTerm2 a style's shape appears under a resting pointer only once the
  person clicks; TUI's sequence is the same as to every other host, and
  nothing it can send was found to make iTerm2 show the shape sooner.
- **The pointer is put back:** once the card closed, the owner had the
  shell's own pointer over the window again. So iTerm2's reset is measured
  (`PointerShapeHost.resetIsMeasured`), and TUI's own controls' shapes —
  the I-beam over a text field, the hand over a button, the resize arrows —
  are on there, shown, like any shape there, once the person clicks. A
  suspend writes the same reset as a quit, the empty name. The mode change
  (`m`), the suspend (`z`) and which of the card's ways out was taken were
  not reported.

**Ghostty 1.3.1 on macOS, 2026-10-19** (the card in CSS's names, read by the
owner on this machine, primary screen, macOS 15.8.1):

- **Thirteen boxes drew their shape.** Seven did not: `.columnResize`
  (`col-resize`), `.rowResize` (`row-resize`), the three diagonal frame
  boxes (`nw-resize`, `nesw-resize`, `nwse-resize`), `.zoomIn` and
  `.zoomOut`.
- **Why, from its source:** Ghostty reads every CSS keyword
  (`mouse.zig`), but its macOS app gives only some of them a cursor —
  `default`, `text`, `vertical-text`, `grab`, `grabbing`, `pointer`, the
  four single arrows, `ns-resize`, `ew-resize`, `context-menu`,
  `crosshair`, `not-allowed` — and ignores the rest
  (`SurfaceView.setCursorShape`: "We ignore unknown shapes"), so the
  pointer keeps whatever shape it had. That is worse than the host's own
  pointer: moving from a button onto a column's divider left the hand up.
- **So TUI now speaks to Ghostty in the names its macOS app draws**
  (`PointerShapeHost.ghosttyName`): a divider either way takes the two-way
  arrow it does draw (`ew-resize`, `ns-resize`), and a diagonal or a
  magnifying glass, which it has no cursor for, Ghostty's own pointer
  (`default`). Ghostty on Linux draws all of CSS's names, but a terminal
  reached over ssh cannot be told apart by its platform, so every Ghostty
  is spoken to as macOS's is.
- **Its reset is not yet read:** whether the shell's own pointer is back
  once the card closes. Until it is, TUI's own controls' shapes stay off
  on Ghostty.

## Focus reporting (mode 1004)

**Status: tmux 3.7c MEASURED; every native host UNMEASURED.**

**What TUI does.** Focus reporting is always on while an app runs.
`Terminal.enableRawMode` writes `CSI ?1004h` straight after bracketed paste's
`?2004h`, and `disableRawMode` writes `CSI ?1004l` just before `?2004l`. So a
suspend (SIGTSTP, or a Ctrl-Z the undo keys leave unbound) and quitting both
turn it off, and resuming turns it back on.
`Tools/Smoke/suspend_probe.py` checks all four. A terminal reports
`ESC [ I` when its window, tab or pane gains focus and `ESC [ O` when it loses
it. The parser (`Terminal.finalize`) reads both as `TerminalInput.focusChanged`,
never as a key, including directly behind an Escape. The run loop
(`AppRunner.terminalFocusChanged`) then moves `ScenePhase` between `.active` and
`.inactive`. Nothing is detected: a terminal without the mode ignores the
request, sends nothing, and the phase stays `.active`.

**Focus out lets go of the pointer** (since 2026-10-18,
`MouseEventDispatcher.pointerLeft()`): the control and the hover observers
under it are exited, the pointer rests nowhere known, and its help goes, held
through the status bar's reflow or not. No mouse mode reports the pointer
leaving the window (xterm's protocols have no leave report), and a terminal
reports no motion once the pointer is outside it, so until then a control
stayed lit and a help stayed in the bar for as long as the pointer was away.
Focus out is the one report there is that the pointer has gone elsewhere; a
pointer that leaves the window without the window losing the focus is still
not heard. Nothing is entered again until the pointer next reports motion;
whether a host reports motion over an unfocused window is the table's
"Motion while unfocused" column, unmeasured.

**No startup loss window.** `enableRawMode` runs before the identity query,
Ghostty's DECRQM and the graphics query, which read stdin. A report a terminal
sends the instant reporting is enabled lands in whichever of them is reading,
and each hands every byte that is not its own reply or the fence back to the
parser:
- the identity query through its own walk, pinned in
  `TerminalIdentityQueryTests`;
- the mode and graphics queries through `TerminalQueryReplies.unconsumed`,
  pinned in `TerminalExchangeTests` with a keystroke and `ESC [ I` interleaved
  in each.

The mode query runs again on resume, under the same rule. A report that comes
after an exchange has stopped reading reaches the parser the ordinary way. The
mode and graphics queries used to throw stray bytes away, so such a report could
be lost and the phase stayed `.active` until the next focus change.

**A crash leaves it on**, as it leaves the mouse modes on: the restore runs in
the loop's cleanup and `Terminal.deinit`, which a crash skips. The mouse modes
are the noisier leak, so this adds no new class.

### tmux 3.7c — measured

Measured while designing this feature, with a throwaway harness that is not
yet committed. The harness used private `-L` sockets, a Python PTY as the tmux
client, and an inner program in the pane logging its stdin. `focus-events` was
set in a config file before the client attached.

| `focus-events` | Client answers DA1 | tmux sends `?1004h` to the client | A pane with 1004 on gets injected `ESC[O` / `ESC[I` | `select-pane` away and back |
|---|---|---|---|---|
| off | either | never | yes | nothing |
| on (set before attach) | no | no | yes | `ESC[O`, `ESC[I` |
| on (set before attach) | yes | **yes** | yes | `ESC[O`, `ESC[I` |

- tmux asks its client for focus reports (`?1004h`) only when `focus-events` is
  on **and** the client answered Device Attributes (`ESC[c`, answered
  `ESC[?62;22c` in the harness). With no answer it never did, and with the
  option off it never did either way.
- Every run, tmux sent its client `?1004l`, `?2031h`, `ESC[c`, `ESC[>q` and
  `ESC]11;?` at startup.
- Reports injected at the client reached a pane that had turned 1004 on, under
  both settings.
- The man page says clients must re-attach after the option changes, so
  setting it in a running session does not reach a client already attached.
- **Detection:** `tmux show-options -gv focus-events` answers read-only. DECRQM
  from inside a pane (`CSI ? 1004 $ p`) reports only the pane's own mode, so it
  cannot tell whether tmux will forward anything. TUI has no detection code,
  because nothing would use the answer.
- *Rejected:* tmux's `client-focus-*` / `pane-focus-*` hooks on the existing
  SIGWINCH hook channel (see "Identifying the client terminal"). The pane hooks
  need the option on (man page), tmux learns client focus only from reports it
  requested with the option on (measured), and SIGWINCH carries no payload. So
  the hooks add no coverage.

### Native hosts — UNMEASURED

No native host has been measured. The plan is a committed
`Tools/TerminalProbes/focus_probe.py` that turns 1004 on, sends DECRQM and logs
every byte with timestamps, driven by hand. Each row below stays UNMEASURED
until that run records it, with the host's version.

| Host | Window blur | Tab switch | Split switch | ⌘-Tab | Minimise | Report on enable | Focusing click also a mouse report | Motion while unfocused | Its own cursor unfocused |
|---|---|---|---|---|---|---|---|---|---|
| Apple Terminal | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| iTerm2 | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| Ghostty | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| Warp | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| tmux inside each, `focus-events` on and off | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |

## Synchronized output (mode 2026) — sent since 2026-10-05, mostly NOT yet measured

A terminal that implements DEC mode 2026 holds its display between
`CSI ? 2026 h` and `CSI ? 2026 l`, so a frame that reaches it in several reads
is shown whole. Ghostty's help names the defect it prevents: an app that
redraws a large area tears or flickers, worst where it erases a row and
redraws it, which is what TUI's whole-line row is (`ESC[2K`, then its
content). Adopted from Ghostty's VT reference
(`Documentation/Terminals/Ghostty VT reference adoption study.md`, O1).

### What TUI does

- **A frame that moves the cursor to a row is held**: the begin marker after
  the frame's image transmissions and before its first cell, the end marker as
  its last bytes, all in the one write that sends the frame. 16 bytes more per
  frame. Until 2026-10-29 a frame of one row was not held, on the reasoning
  that one row cannot tear; but a changed row is rewritten whole, `ESC[2K` and
  then its content, and a focused toggle's breath on the Example's Images page,
  its row running beside a picture drawn in glyphs, was about 2 KB: two reads
  of a macOS pty, sent every ~50 ms unheld (captured in a PTY). Ghostty painted
  the erased row in between, which was the toggle's flicker there, worst with
  terminal graphics off (#27; the owner's report, not yet re-checked live). The transmissions stay outside because they draw
  nothing and can be megabytes, which inside a hold could outlast Ghostty's
  limit on one (below). An animation tick's frame is held by the same rule.
- **Image deletes go inside the hold, after the cells** (since 2026-10-27): a
  picture that changes is sent under a fresh id ahead of the hold, and the
  old one deleted after the cells that stop naming it, so the swap is shown
  in one update rather than as a blank while the new bytes travel
  (`TerminalImageStore.takeDeletes()`; `Terminal graphics protocols.md`
  §8.6). That a host defers a graphics delete's effect on screen to the
  hold's end, as it does a cell's, is read from what the mode promises (the
  display, not the parser, is held) and NOT yet measured on any host; where
  a frame is not held, the delete still follows the cells.
- **A frame that writes no row is not**: one that writes nothing sends
  nothing, and one that only transmits images sends them unheld. The begin
  marker is reserved in the frame buffer and skipped when unused, so nothing
  is copied.
- **Teardown.** The end marker is the first thing `disableRawMode` sends (quit,
  suspend, `SIGINT`, `SIGTERM`) and heads the debt a fatal signal pays
  (`FatalSignalTerminalRestore`). A write that gives up partway through a held
  frame is followed by the end marker on its own. Only those paths can leave
  a hold open, since each frame carries its own end marker.
- **A non-blocking terminal.** The terminal's file description is shared
  with the shell, and a crashed program (a Node CLI is the known case) can
  leave it `O_NONBLOCK`. A frame larger than the pty's buffer then met
  `EAGAIN` partway, and so did the end marker's retry straight after: the
  display stayed held until the next held frame. Every write now waits for room on `EAGAIN` (`poll` for `POLLOUT`),
  as a blocking write would, so only a hard error gives up partway
  (`Terminal.writeAll`, pinned by `SynchronizedOutputTests` and over a real
  non-blocking pipe by `TerminalOutputTests`). TUI never sets the flag
  itself; a dispatch read source on stdin does not either (checked, macOS 15).
- **Sent to every host, nothing asked.** `CSI ? Pm h` has a `?` and no
  intermediate byte, the shape measured clean on Apple Terminal, iTerm2,
  Ghostty and Warp ("Asking the terminal — Device Attributes"), and `?2031h`,
  the same shape, printed nothing on five hosts. Its DECRQM query
  (`CSI ? 2026 $ p`) is the shape Apple Terminal prints, and setting the mode
  needs no answer, so TUI never sends it.
- **`TUI_SYNCHRONIZED_OUTPUT=0`** turns it off: no markers, and none owed.

`SynchronizedOutputTests` pins all of the above, the marker's place in a
rendered frame included.

### What each host is documented to do

| Host | Implements 2026 | A hold nobody ends |
|---|---|---|
| Ghostty 1.3.1 | yes: its help page, and `synchronized_output = 2026` in `src/terminal/modes.zig` | ended after 1000 ms (`sync_reset_ms`, `src/termio/Thread.zig`) |
| iTerm2 | hypothesis: yes; 3.7.3 recognises the mode, answering DECRQM `?2026` with `reset` (measured, below) | unknown |
| kitty, Warp | hypothesis: yes | unknown |
| Apple Terminal 455.1 | hypothesis: no, ignored | — |
| GNOME Terminal 3.56.2 | no (DECRQM `?2026` reports permanently reset `0`, measured 2026-10-23) | — |
| tmux 3.7c | unknown, and unknown whether a pane's hold reaches the client | unknown |

Ghostty's facts are read from its source on 2026-10-04, not measured. A
process killed mid-frame (SIGKILL, which no handler sees) freezes Ghostty's
display for a second at most; elsewhere for as long as the host holds. So does
one stopped mid-frame by `SIGSTOP` (`kill -STOP`, a debugger), which no
handler sees either: the shell's "Stopped" line is held with it, until the
process is continued or the host's timeout ends the hold. Nothing TUI can
do about that is specific to the hold: a stopped process also leaves raw mode,
the alternate screen and mouse tracking on. The window is one frame's write.
`Ctrl-Z` is `SIGTSTP`, which TUI handles: its suspend sends the end marker
first.

### To measure — `Tools/TerminalProbes/sync_probe.py`

Run it inside each host, and inside a tmux 3.7c pane in Ghostty and in
iTerm2, on the alternate screen (`PROBE_ALT=1`):

1. `python3 sync_probe.py` checks that the pair prints nothing (cursor column
   before and after), and asks DECRQM `?2026` of a host that identifies itself
   (`TERM_PROGRAM`, or an XTVERSION answer, which Apple Terminal never gives).
2. `python3 sync_probe.py --hold-timeout` opens a hold, never ends it, and
   runs a millisecond counter for 8 seconds; the first value seen is the
   host's timeout. Watch it, or record the screen.
3. By eye, on Ghostty: drag Example's split divider (the gesture
   `Tools/Profiling/drive.py --scenario splitdrag` scripts), with
   `TUI_SYNCHRONIZED_OUTPUT=0` and without.

Bytes, captured 2026-10-05 with `drive.py --scenario tour --dump` (160×50,
debug build): 146 and 149 frames held in two runs, 2.3 KB of markers in
about 289 KB (0.8%). Without the markers the two runs held 286.8 KB and
289.2 KB, against 286.1 KB and 286.4 KB in two runs with
`TUI_SYNCHRONIZED_OUTPUT=0`: the tour's timing moves a few frames from run
to run, a spread as large as the markers. On `splitdrag`, which needs
`--answer-fence` (without it the scripted press lands before the app is up and
misses the divider, B-G1-2 in `Historical/Terminals/Adopting what Ghostty documents - synchronized output, autowrap, progress and attention.md`): 58
frames held, 928 bytes of markers in 196 KB (0.5%); the run with the switch
off wrote 211 KB, the drag's frame count moving with its timing.

| Host | Pair prints nothing | DECRQM `?2026` | Hold timeout | Tearing on `splitdrag`, off → on |
|---|---|---|---|---|
| Apple Terminal | UNMEASURED | not asked | UNMEASURED | UNMEASURED |
| iTerm2 | clean, 3.7.3 | `reset`, 3.7.3 | UNMEASURED | UNMEASURED |
| Ghostty | clean, 1.3.1 | `reset`, 1.3.1 | UNMEASURED | UNMEASURED |
| Warp | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| kitty | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| tmux in Ghostty, in iTerm2 | UNMEASURED | UNMEASURED (the pane's) | UNMEASURED | UNMEASURED |

iTerm2's and Ghostty's first two cells were read on 2026-10-08 by
`hairline_probe.py`'s Q7, which calls this probe's own `leak_check` and
`decrqm` (`Tools/TerminalProbes/data/*-hairline.json`). The same run found a
Kitty graphics line, re-placed every frame, steady with the mode and without
it ("A line on a row boundary", under the graphics protocols), which is a
different test from the `splitdrag` column's.

## OSC 52 clipboard writes — sent since 2026-10-05; measured on tmux, and on four hosts 2026-10-19

OSC 52 (`ESC ] 52 ; c ; <base64> ESC \`) asks the terminal to set the
clipboard. The terminal acting on it runs on the user's machine, so it is the
one route to the user's clipboard that crosses ssh. No terminal acknowledges a
write, so whether one happened is known only from what a host is documented or
measured to do.

### What TUI does

Every copy TUI makes — a text field's or editor's Ctrl-C and Ctrl-X, a
`copyable` view's ⌘C — goes through one writer (`ClipboardWriter`), which
takes ONE route per copy, in this order:

1. **OSC 52, where the terminal writes it by default** (the table below,
   `TerminalClient.clipboardWrites`). Over ssh too: that is the point.
2. **This machine's clipboard helper, only on positive evidence that the user
   is at this machine** (`SessionLocality`): no `SSH_CONNECTION`,
   `SSH_CLIENT` or `SSH_TTY`; this process's parents reach the root without
   passing `sshd` (or `sshd-session`), `mosh-server`, `dropbear`, `telnetd`,
   `etserver` (or `etterminal`), `ttyd` or `gotty`; and inside tmux, at
   least one client is attached and every client's parents pass the same
   test (the pane's own chain ends at the tmux server, which says nothing of
   who is watching) — a tmux above the client itself in its chain, a tmux
   run inside another tmux's pane, counting as a keeper. The other session
   keepers TUI knows — GNU `screen`, `zellij`, `dtach`, `abduco`,
   `shpool`, `tmate`, WezTerm's `wezterm-mux-server`, in the chain or by
   their variable (`STY`, `ZELLIJ`, `ZELLIJ_SESSION_NAME`, `ABDUCO_SESSION`,
   `SHPOOL_SESSION_NAME`) — answer "not here": a keeper's server is detached
   from the terminal that started it, so a session begun at the desk may be
   attached over ssh with nothing in this process to say so, and none can be
   asked for its clients as tmux can. A keeper not on that list passes as a
   plain parent. A chain that cannot be read to the root is not evidence.
   (The same test decides whether the host's own Reduce Motion counts: see
   `HostSettingsRefresher`, refusal review O1.)
   At the desk this costs: a copy under a keeper goes by OSC 52 only where
   the outer terminal is named and takes it, and a paste chord pastes the
   app's own last copy, not the desk's clipboard (below). The helper is
   `pbcopy` on macOS; on Linux `wl-copy` with `WAYLAND_DISPLAY`, then `xclip`
   or `xsel` with `DISPLAY`, and none without a display.
3. **OSC 52, where the terminal MAY write it**: iTerm2 (a setting decides),
   tmux with `set-clipboard on`, a terminal whose DA1 lists `52`, and since
   2026-10-24 GNU screen and tmux's `allow-passthrough` through their
   passthroughs (below).
4. **Nothing**, said so.

Rung 2's clipboard is injected (`ClipboardBackend`), and only the app's run
loop installs the one that runs the helper (`SystemClipboard.Backend`, into
the `TUIContext` `AppRunner` creates). Every other context — a headless run,
a `renderOnce` snapshot, a test — keeps rung 2's copies in memory
(`InMemoryClipboard`), and a view rendered with no context's services at all
has no clipboard (`ClipboardAccess.unavailable`), so nothing but a running app
ever writes the user's pasteboard. The rule and its order are the same
whichever stands behind it.

**Inside GNU screen (`STY`), OSC 52 through screen's DCS passthrough**,
whatever terminal the environment names, since 2026-10-24 (owner ruling
D4X-LOCALITY): screen drops an application's bare OSC 52 and passes one on
inside its DCS passthrough (`ESC P … ESC \`), so TUI sends the write
BEL-terminated and cut into DCS strings of at most 256 bytes. The terminal's
name is inherited from wherever screen was started, so it says nothing of the
terminal screen is drawn in now: every such copy is "Sent", never "Copied"
(rung 3), at the desk too (screen is a keeper, so rung 2 does not apply).
Measured on screen 4.00.03 driven by a scripted terminal (below); screen 5
unmeasured. Before, every copy under screen was "Not copied".

**In a tmux pane, tmux's clients say whether screen is in the way**, not
`STY` and not the pane's own chain of parents. tmux's server daemonizes
(`daemon(1, 0)` in its `proc_fork_and_daemon`) and is reparented to launchd,
init or `systemd --user`, so every pane's chain is `[app, shell, tmux,
launchd]` however its session is attached; and a server started inside
screen keeps screen's `STY` whoever attaches, while one attached from inside
screen later has none. So under `set-clipboard on` TUI asks tmux for its
clients (`list-clients`) and walks each one's parents, as the clipboard's
locality does: where every client runs in a screen window — `screen` (or
`SCREEN`) holds its terminal: the first process above the client attached
to another terminal, or to none, which is the one that opened the client's
pty — nothing is sent and the copy is "Not copied" — such a client's `TERM` is
`screen*`, which tmux's default `terminal-features` give no clipboard, and
screen drops a bare OSC 52 besides (both read from the sources; unmeasured
on a host). screen's server runs on no terminal and its windows' processes
on the window's pty (measured, screen 4.00.03 on macOS 15, 2026-10-07: `ps`
shows `SCREEN` on `??` and its window's `login` on `ttys005`). A screen
further up does not count: a GUI terminal started from a shell inside
screen draws a client in itself, and its pty is the terminal's. The rule
looks one hop: any relay with a pty of its own between the client and screen
(a second multiplexer, an `ssh` inside the screen window, `script`) is taken
for the terminal, and the answer goes back to "Sent" where nothing arrives.
Following the chain past such relays is not built (the FU3T follow-ups'
review, recorded 2026-10-23). Where at
least one client is outside screen, tmux's answer stands ("Sent"). Only the
clients that see the write count: tmux passes a
pane's write on to the clients whose session holds the pane's window
(`session_has` in `screen_write_set_client_cb`, read from its source), so
`list-clients` also prints each client's session's panes
(`#{W:#{P:#{pane_id}}}`, the ids run together as `%0%1%2`; a loop given a
comma takes what follows it as the active pane's format, which printed
nothing for it) and the ladder keeps the clients whose list names the app's
`TMUX_PANE`. Measured, tmux 3.7c, 2026-10-07, on a private server with
three clients attached through ptys: a two-window, three-pane session
`A` listed `%0%1%2`, a session `B` `%3`, and a session grouped with `A`
`%0%1%2` too. A client on another session neither receives the write nor
makes up for one that receives it inside screen. A screen run inside a tmux
pane is told by the app's own chain (screen above it before tmux), and
nothing is sent. Where it cannot be told — tmux not listing its clients, a
client's chain unreadable, a client attached to no terminal, no client showing
the pane — the write goes as the maybe it is, reported "Sent", never "Copied".
A tmux that lists its clients but not their panes (one too old for the loops;
unmeasured) keeps every client as one the write may reach
(`writeRecipients`), and each is judged by its chain as above, so screen
holding all of them still says "Not copied". (The follow-ups' reviews: `STY` alone said
"Not copied" of a tmux attached straight from the terminal; the pane's chain
alone then said "Sent" of a tmux still attached from inside screen, where
nothing arrives; counting every client of the server said "Sent" of the
app's session attached from inside screen while another session was
attached from the terminal; and screen anywhere above a client said "Not
copied" of one in a GUI terminal started from inside screen.)

The status bar says what became of a copy for three seconds, in place of the
items of the line of key hints (`StatusBar()`, where the app places it) and
cut to one row, so the page keeps its height (with no line of items drawn, it
takes a row at the top of the bottom bar, as a tooltip does): "Sent to the
terminal's clipboard" for rung 3 — a
hope, not a fact — "Not copied: no clipboard reachable from here" for rung 4,
"Not copied: the clipboard helper failed" when the helper ran and failed. A
text control's plain success says nothing, as a Mac's does not.

**Never both routes.** The text-editing design study proposed writing both
when both apply (§4.4). The owner's rule (2026-10-04) is that this machine's
clipboard is written only when it is the user's; when it is, it is also the
surer route, so a second write adds nothing.

**Paste chords read on the same evidence.** A field's Ctrl-V, a
`PasteButton` and a `pasteDestination` read this machine's clipboard only when
rung 2's evidence holds, because over ssh it is the server's clipboard and
holds nothing the user put there. Otherwise they find the latest copy the app
itself made, whatever became of it, so a field's Ctrl-C pastes into another
field and a `copyable` value into a `PasteButton`, as the server's pasteboard
used to carry them (and as tmux's buffer or vim's register does). With no such
copy they find nothing, and the status bar says "Nothing to paste here: use
the terminal's paste" for three seconds; with one, it says "Pasted this app's
last copy: for your clipboard, use the terminal's paste", since that copy may
be older than what the user last copied on their machine. The terminal's own paste — ⌘V,
bracketed, from the user's machine — brings in what was copied there, and
works everywhere. Inside tmux each chord asks tmux for its clients, as a copy
does.

**The spelling** follows Ghostty's OSC 52 page, which is stricter than
xterm's (`Documentation/Terminals/Ghostty VT reference adoption study.md`, C1):

- the selector `c`, spelled out — an empty one means `c` to Ghostty and `s0`
  to xterm;
- one selector per sequence, which is all Ghostty takes;
- unwrapped base64 (Foundation's default), and **never an empty or malformed
  payload**: Ghostty clears the clipboard on a payload that is neither valid
  base64 nor `?`. An empty copy sends nothing;
- ST, as TUI's other OSCs;
- never `?`: a read prompts the user on Ghostty by default and its reply
  arrives in the input stream. Paste stays the terminal's own, through the
  bracketed paste TUI already turns on.

**Delivery.** A copy is made between frames, by a key; its OSC 52 is queued
and written at the start of the next frame, with the image transmissions and
outside the synchronized-output hold, and the writer asks for that frame. A
copy still queued when the app quits is written on the way out. tmux gets the
plain sequence under `set-clipboard on`, which it passes on itself; otherwise,
where the pane's `allow-passthrough` (`show-options -pvA`, inherited from the
window and the global setting) is `on` or `all`, the write wrapped in tmux's
passthrough (`ESC P tmux;`, every ESC doubled, `ESC \`), which tmux passes
on to the terminals showing the pane whatever `set-clipboard` says ("Sent").
`set-clipboard on` is asked first, so a copy is never sent twice; the probe
saw exactly one write arrive with both on. `allow-passthrough` is off by
default from 3.3, so a default tmux still gets nothing. Where screen holds
the client's terminal, the wrapped write reaches screen bare and is dropped
there, and the copy is "Not copied", as under `on`. Through either
passthrough a copy is its text alone: its other types (OSC 5522) are not sent.

`TUI_OSC52=1` makes every copy an OSC 52 to a terminal taken to honour it,
for a host TUI does not know; `0` never sends one. An app can do the same
with `TerminalClient.clipboardWriteSupport`. `TerminalClient.simulated`, the
diagnostic that draws as another terminal, does not change where a copy
goes: the ladder reads the terminal actually detected, unlike OSC 8's.

### What each host is documented to do

| Host | Writes OSC 52 | Source | TUI's rung |
|---|---|---|---|
| Ghostty 1.3.1 | yes, by default (`clipboard-write = allow`) | its OSC 52 page and config reference; measured 2026-10-19 (below) | 1 |
| kitty | yes, by default (`clipboard_control` allows writes) | its documentation | 1 (`TERM=xterm-kitty`, `KITTY_WINDOW_ID`) |
| WezTerm | yes, by default | its documentation | 1 (`TERM_PROGRAM=WezTerm`, `TERM=wezterm`) |
| foot | yes, by default | its documentation | 1 (`TERM=foot`, `foot-extra`) |
| iTerm2 3.6, 3.7.6 | only with Settings > General > Selection > "Applications in terminal may access clipboard", off by default | its documentation; measured 2026-10-19 both ways: off, no write arrived; on, every spelling did, up to 512 KiB; its DA1 lists `52` either way (below) | 3 |
| tmux 3.7c | `external` (the default) ignores an application's write; `on` keeps it as a paste buffer and passes it on to clients whose features include `clipboard`; under `allow-passthrough` a wrapped write is passed on whatever `set-clipboard` says | measured, below; the manual | 3 with `on`, or with `allow-passthrough` wrapped; else none |
| GNU screen 4.00.03 | drops a bare write; passes one on inside its DCS passthrough, at most 256 bytes a string | measured 2026-10-24 (below) | 3, wrapped |
| Apple Terminal 455.1 | no | no OSC 52 anywhere in the app; measured 2026-10-19 (below) | none |
| Warp v0.2026.09.30.08.29 | no | measured 2026-10-19 (below) | none |
| GNOME Terminal 3.56.2 | no | DA1 omits `52`; measured 2026-10-23 | none |
| unidentified | — | — | none, unless its DA1 lists `52` (rung 3) |

DA1 can only ADD a host: a terminal that writes by default need not say so.
(Ghostty was the example here, with the `ESC[?62;22c` read out of its binary;
asked on 2026-10-19, Ghostty 1.3.1 answered `ESC[?62;22;52c`, which does list
it.) Nor does DA1 follow iTerm2's setting: iTerm2 3.7.6 lists `52` with the
setting off, when no write lands, as with it on, when every write does.

Where TUI stands on locality inside tmux depends on tmux: the clients are
asked for (`list-clients`) and `set-clipboard` read (`show-options -sv`) when
a copy is made, two bounded subprocesses per copy and none per frame.

### Measured: tmux 3.7c, 2026-10-05

`clipboard_probe.py` in a private, detached server (`tmux -L`, no client
attached, so nothing could reach an outer terminal): with `set-clipboard
external` the write left no buffer; with `on` tmux kept it as its newest
buffer (`show-buffer` returned the nonce). Whether tmux then passes the
write to an attached client is the next row to measure.

### Measured: four hosts, and tmux with a client, 2026-10-19

`clipboard_probe.py` in its default mode — not `--destructive`, so no empty
or malformed payload was sent — run inside each host on this machine, primary
screen, macOS 15.8.1, one host at a time, reading the clipboard back with
`pbpaste` and putting it back after every run (every record says
`restored: true`). The records, in `Tools/TerminalProbes/data/`, are
`apple-terminal-455.1-clipboard.json`, `iterm2-3.7.6-clipboard-off.json`,
`iterm2-3.7.6-clipboard-on.json`, `ghostty-1.3.1-clipboard.json` and
`warpterminal-v0.2026.09.30.08.29.stable_01-clipboard.json`.

- **Ghostty 1.3.1 writes every spelling** — ST, BEL, and the empty selector
  (which it reads as `c`) — and every size tried, 1 KiB to 1 MiB, arrived
  whole. Its DA1 lists `52`.
- **iTerm2 3.7.6 writes only with its setting on**, and its DA1 lists `52`
  either way. With "Applications in terminal may access clipboard" off (its
  default) nothing arrived, in any spelling. The owner turned it on, with
  "Allow sending of clipboard contents?" at Always, and the run was made
  again: ST, BEL and the empty selector all arrived, and so did every size
  to 512 KiB. 1 MiB arrived cut short, at 786,430 bytes, which fits a cap of
  1 MiB on the base64 text (1,048,576 characters decode to 786,432 bytes;
  the cause is not established).
- **Apple Terminal 455.1 and Warp v0.2026.09.30.08.29 ignore OSC 52**: no
  spelling arrived. Neither lists `52`.
- **None of the four printed any of it**: the cursor did not move across
  the write.

tmux 3.7c was run in a server of its own (`tmux -L tuikitprobe -f /dev/null`)
with one client attached, an Apple Terminal window, twice: with
`set-clipboard on` and then `external`
(`tmux-3.7c-clipboard-on.json`, `tmux-3.7c-clipboard-external.json`). tmux
listed the client's features as including `clipboard`. With `on` it kept the
write as its newest buffer, and with `external` it kept none, as on
2026-10-05. Nothing reached the clipboard either way, which is what a client
that ignores OSC 52 predicts; whether tmux sent the write on to the client was
not captured. With a client that writes it (Ghostty), unmeasured. (Both tmux
records name `com.anthropic.claudefordesktop` as the bundle: the pane
inherits the environment the server was started in, not the client's.)

### To measure — `Tools/TerminalProbes/clipboard_probe.py`

Run it inside each host, on the machine the host runs on, so the probe reads
the clipboard back itself (`pbpaste`, `wl-paste`, `xclip`, `xsel`); over ssh,
`--manual` asks for a paste instead. `--destructive` adds the empty and the
malformed payloads. Still to run: kitty,
`--destructive` on every host, and tmux with `on` under a client that writes
OSC 52.

| Host | Prints nothing | DA1 lists 52 | Write arrives | Largest copy | Empty payload | Malformed payload |
|---|---|---|---|---|---|---|
| Apple Terminal 455.1 | yes | no (`ESC[?1;2c`) | no | — | — | — |
| iTerm2 3.7.6, setting off | yes | **yes** | **no** | — | — | — |
| iTerm2 3.7.6, setting on | yes | yes, the same reply | yes — ST, BEL and an empty selector | 512 KiB; 1 MiB cut to 786,430 bytes | UNMEASURED | UNMEASURED |
| Ghostty 1.3.1 | yes | yes (`ESC[?62;22;52c`) | yes — ST, BEL and an empty selector | 1 MiB, the largest tried | UNMEASURED | documented: cleared; UNMEASURED |
| Warp v0.2026.09.30.08.29 | yes | no (`ESC[?62c`) | no | — | — | — |
| kitty | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |
| tmux 3.7c, `external` | yes | no (`ESC[?1;2;4c`, tmux's own) | no buffer; nothing arrived through an Apple Terminal client | — | — | — |
| tmux 3.7c, `on` | yes | no | buffer kept; nothing arrived through an Apple Terminal client; through Ghostty UNMEASURED | UNMEASURED | UNMEASURED | UNMEASURED |

The tmux rows' first two columns are tmux's own: under tmux the probe's cursor
and DA1 are the pane's, not the client's.

### OSC 52 through screen and tmux — measured 2026-10-24, `Tools/TerminalProbes/keeper_passthrough_probe.py`

What a session keeper passes on to its terminal, which is a different
question from what a terminal then does with it (the tables above). The probe
runs each keeper on a pty whose master side it plays (`TERM=xterm-256color`),
a program in the keeper's window writes one form of the write with a fresh
nonce, and the probe counts the writes that reach the terminal whole. No GUI
terminal is involved. Record:
`Tools/TerminalProbes/data/keepers-screen-4.00.03-tmux-3.7c-passthrough.json`
(macOS 15.8.1, `/usr/bin/screen` and Homebrew's tmux).

| Keeper | Case | Bytes sent | Reaches the terminal |
|---|---|---|---|
| screen 4.00.03 | bare OSC 52 | 73 | **no** |
| screen 4.00.03 | one DCS around the BEL-terminated write | 76 | yes |
| screen 4.00.03 | a 3 KiB write in DCS strings of at most 256 bytes | 3,132 | yes, whole |
| screen 4.00.03 | a 64 KiB write the same way | 66,588 | yes, whole |
| screen 4.00.03 | one DCS of 252 or 256 bytes | 252, 256 | yes |
| screen 4.00.03 | one DCS of 260 to 4,096 bytes | 260 … 4,096 | **no**: dropped whole, nothing passed on |
| tmux 3.7c | bare, `set-clipboard external` | 73 | no |
| tmux 3.7c | bare, `set-clipboard on` | 73 | yes |
| tmux 3.7c | wrapped (`ESC P tmux;`), `allow-passthrough off` | 84 | no |
| tmux 3.7c | wrapped, `allow-passthrough on`, `set-clipboard external` | 84 | yes |
| tmux 3.7c | a 64 KiB write wrapped, the same options | 65,556 | yes, whole |
| tmux 3.7c | bare, with `set-clipboard on` and `allow-passthrough on` | 73 | yes, once |

screen's limit is a DCS string's whole length, its `ESC P` and `ESC \`
included: 256 passes, 260 does not. Chromium hterm's `osc52.sh` gives the
history as 256 bytes until screen 4.2.0 (2008-2014), 512 then, and 768 from
4.2.1; 256 serves every release, so TUI cuts at 256. Still unmeasured:
screen 5, what a real terminal does with what screen and tmux pass on (the
tables above say what each host does with a write), tmux's own limit past
64 KiB, and a nested keeper — tmux inside screen gets the passthrough's
write bare at screen, which drops it, so TUI sends nothing there.

## OSC 5522 clipboard: any MIME type — measured 2026-10-17 on three hosts

kitty's clipboard protocol (https://sw.kovidgoyal.net/kitty/clipboard/)
copies and pastes any MIME type, where OSC 52 carries text alone: a write
opens with `ESC ] 5522 ; type=write ST`, sends each type as `type=wdata`
packets (its MIME type and at most 4096 bytes before encoding, base64), and
closes with an empty `type=wdata`; the terminal acknowledges
`type=write:status=DONE` or an error (`EPERM`, `EINVAL`, `EBUSY`, `EFBIG`).
Support is asked with DECRQM, `CSI ? 5522 $ p`; 0 or 4 is none.

Measured with `Tools/TerminalProbes/clipboard_mime_probe.py` (support, a
four-type write, the type list), each run inside the host:

| Host | DECRQM 5522 | Write acknowledged | Pasteboard after |
|---|---|---|---|
| iTerm2 3.6 | `4` (permanently reset) | no | unchanged |
| Apple Terminal 455.1 | no reply (DSR answered) | no | unchanged |
| Warp | no reply (DSR answered) | no | unchanged |
| kitty (the owner's run, 2026-10-17; version not recorded) | `2` (reset, recognised) | **yes** (`DONE`) | **the types landed**: `utf8`, `HTML`, `PNGf` and the rest of macOS's own representations of them |
| Ghostty 1.3.1 | NOT MEASURED (its `-e` consent prompt); the protocol is on Ghostty's development branch, not in 1.3.1 | | |

None of the three printed anything. TUI asks only Ghostty, and kitty,
WezTerm and foot where the environment names them
(`TerminalClient.mayAskMIMEClipboard`): Apple Terminal prints the final `p`
of any DECRQM, and iTerm2's answer is known. Where the answer is yes, a copy
sent to the terminal goes by OSC 5522 with every form the app has of it — a
link as `text/uri-list`, Markdown as `text/markdown` — and its text as
`text/plain`, and a screen selection as `text/html` (its cells' colours,
weight and decoration); `TUI_OSC5522=1` or `0` overrides.

**Paste events (mode 5522, kitty 0.44.1 and later).** Where a terminal says
it takes OSC 5522, TUI also sets `CSI ? 5522 h` (and resets it with the
other input modes on exit and suspend). A paste then arrives not bracketed
but as an unsolicited read reply listing the clipboard's types under a
one-time password — `type=read:status=OK:pw=…`, one `status=DATA` packet
with `mime=.` whose payload is the types, space-separated, then
`status=DONE`, the OK carrying `loc=primary` for a paste of the primary
selection (kitty's `send_paste_event`, read from its source; the
specification shows no packet). kitty sends this INSTEAD of the bracketed
text — `boss.py`'s `paste_from_clipboard` returns once `send_paste_event`
has — so the text comes only through the read. TUI reads, with that password
and `name=Paste event` (so no permission prompt appears), the first text type
and every other listed type a paste command on the path to the focused view
takes — `onPasteCommand(of:)`'s types, by `UTType` conformance, so `.image`
takes each picture type and `.pdf` a PDF (`InputHandler.acceptsPaste(ofMIMEType:)`);
with nothing to ask, the first `image/*`. The reply's `DATA` packets (each
type's in order) become one paste key event: its text, and every other type's
bytes beside it, which the view's `onPasteCommand` is offered as its `UTType`. A refused or failed
read loses the paste, as one the terminal never delivered would be.
The paste is unmeasured on any host here, for the reasons the table gives (the
owner's kitty run measured the write). The acknowledgement is swallowed with
every other reply. A paste in kitty, and Ghostty-tip, are owed a run.

## modifyCursorKeys (XTMODKEYS) — set to 2, and reset to its initial value since 2026-10-29; read from ctlseqs, NOT measured

`Terminal.enableRawMode` (startup and every resume) sends `CSI > 1 ; 2 m`,
modifyCursorKeys = 2, so a modified arrow arrives in the canonical
`CSI 1 ; <mod> <letter>` form with every modifier bit (Shift+Option+Left
with both). The teardown, and the debt a signal pays, put it back with
`CSI > 1 m` (`Terminal.inputModesOff`).

**Why `CSI > 1 m` and not `CSI > 1 ; 0 m`.** xterm's control-sequence notes
(ctlseqs, XTMODKEYS, `CSI > Pp ; Pv m`): "If the second parameter is
omitted, the resource is reset to its initial value" — the value the
terminal started with, from the user's resources, and xterm's own default
for modifyCursorKeys is 2. `CSI > 1 ; 0 m` does not reset anything: it SETS
the resource to 0, xterm's obsolete encoding of a modified cursor key.
Until 2026-10-29 every quit, suspend and crash debt sent it, so each run of
a TUI app changed the user's xterm Ctrl/Shift/Alt-arrow encoding for the
rest of the terminal's life.

This is read from ctlseqs and nowhere measured. Hosts that do not implement
XTMODKEYS ignore both spellings (Apple Terminal ignores the set as well; its
shape — `>`, no intermediate — is the DA2 shape it consumes, "Asking the
terminal — Device Attributes"). What remains to measure, per host: after an
app quits, does `cat -v` show Ctrl+Left as `^[[1;5D` as it did before launch?

| Host | Implements XTMODKEYS 1 | Initial value restored by `CSI > 1 m` |
|---|---|---|
| xterm | yes (ctlseqs) | yes, by ctlseqs — UNMEASURED |
| iTerm2, Ghostty, kitty, WezTerm, VTE | UNMEASURED | UNMEASURED |
| Apple Terminal | no (ignores the set) | — |
| tmux | UNMEASURED | UNMEASURED |

## Inherited state: the defaults raw mode asserts — since 2026-10-05

Modes outlive the program that set them. A killed `vim`, `less` or `htop`, or
a shell that sends terminfo's `smkx` without its `rmkx`, hands the next program
a terminal out of its defaults, and every TUI frame assumes them. So
`Terminal.enableRawMode` (at startup and on every resume) sends, before
anything else, `Terminal.inheritedDefaults`:

| Sequence | Puts back | What it cost when left changed |
|---|---|---|
| `CSI r` | the scrolling region (DECSTBM) to the whole screen | scrolling confined to the old region. With origin mode off no absolute cursor move minds a region, and no frame scrolls today; hardware scrolling (O2 in the adoption plan) will, with a region of its own |
| `CSI ? 69 l` | left-right margin mode (DECLRMM) off, and with it any left and right margins (DECSLRM) | every row stopped (autowrap off) or wrapped (on) at the old right margin, and `CSI s` read as DECSLRM rather than a cursor save. tmux sets such margins where the terminal has them |
| `CSI ? 6 l` | origin mode (DECOM) off | every row and column number taken relative to the region and margins and clamped into them: what offsets or clamps a frame |
| `CSI ? 1 l` | normal cursor keys (DECCKM) | arrows, Home and End sent as `ESC O A`… |
| `ESC >` | the numeric keypad (DECKPNM) | the keypad sent as `ESC O p`… instead of its digits |

None is restored on the way out: they are the defaults a shell expects. DECSTBM
and DECOM also home the cursor, which no frame minds, since each positions
every row it writes. That resetting DECLRMM also resets the margins is xterm's
and the VT510 manual's account; with the mode off they do not apply either
way.

**Shapes.** `CSI r` has neither a `?` nor an intermediate byte; `?69l`, `?6l`
and `?1l` have a `?` and no intermediate; both shapes were measured clean on
Apple Terminal 455.1, iTerm2, Ghostty and Warp ("Asking the terminal — Device
Attributes"). `ESC >` is a two-byte VT100 escape, not measured here.
`TerminalOutputTests` pins `enableRawMode`'s bytes and checks every sequence
it and `disableRawMode` send against the shapes Apple Terminal prints.

**To measure.** On each host and in tmux, run
`printf '\e[5;10r\e[?6h\e[?69h\e[10;40s\e[?1h\e='` and then launch Example:
the frame must start at row 1 and fill the screen, every row must reach the
right edge, and the arrows must move the focus. (`CSI 10;40 s` sets margins only
where `?69h` took; elsewhere it is a cursor save, harmless.)

| Host | Frame at row 1 after a stale region | Rows full width after stale margins | Nothing printed |
|---|---|---|---|
| Apple Terminal | UNMEASURED | — (no DECLRMM, hypothesis) | UNMEASURED |
| iTerm2 | UNMEASURED | UNMEASURED | UNMEASURED |
| Ghostty | UNMEASURED | UNMEASURED | UNMEASURED |
| Warp | UNMEASURED | UNMEASURED | UNMEASURED |
| tmux in Ghostty, in iTerm2 | UNMEASURED | UNMEASURED | UNMEASURED |

Found by reading Ghostty's VT reference (`Documentation/Terminals/Ghostty VT reference adoption study.md`,
K2). It must land before any hardware scrolling (O2 there), which sets a
region of its own and must not inherit one.

## Autowrap off while the app runs — since 2026-10-05, NOT yet measured; not on Apple Terminal

`Terminal.enableRawMode` (startup and every resume) turns autowrap off with
`CSI ? 7 l` (DECAWM), and `Terminal.outputModesOff` turns it back on with
`CSI ? 7 h`: first in `disableRawMode` (quit, suspend, `SIGINT`, `SIGTERM`),
and in the debt a fatal signal pays. On is every terminal's default (Ghostty's
source has wraparound, mode 7, default on), and it is not per screen, so
leaving the alternate screen does not restore it. `?`, no intermediate: the
shape Apple Terminal consumes.

**Except on Apple Terminal, until its card** (`Terminal.keepsAutowrap`). The
plan made that card the precondition, so Apple Terminal keeps the default,
named by the environment or, over ssh, as soon as the startup exchange names
it: raw mode has sent `?7l` by then, and `?7h` follows at once, before the
first frame. `?7h` is still in its teardown and debt, where it is harmless.

The frame dump's notice (`TUI_DEBUG_FRAME_DUMP=1`, the backtick) turns
autowrap on for itself and off again inside its `ESC 7` / `ESC 8`, so a path
wider than the screen wraps onto the rows below it as it always did, rather
than losing its file name at the right edge.

**What it buys.** Every row TUI writes is as wide as the screen by TUI's
count, and nothing it draws relies on wrapping. Where a host advances a cluster
further than that count — a host TUI has not measured, or iTerm2 (and, once
its card allows, Apple Terminal) with "ambiguous characters are wide" on — the row used to wrap its
tail into the next row, and on the bottom row scroll the whole screen up a
line, after which the diff writer's picture of the screen was wrong until
something invalidated it. With autowrap off, the row loses its own last cells
instead. Nothing per frame.

**The peak guard, everywhere a model has an over-advancer.** A cluster whose
claim fits the row but whose emission reaches past the edge before its `CUB`
repair — Apple Terminal's tag flags and bare keycaps, a hand-built set's
`.pullBack` tones — wraps the row with autowrap on, and with it off pins the cursor at the last
column, so the repair pulls back too far. Terminal.app's clip already replaced
such a cluster with spaces of its claim. The quirks explorer's hand-built sets
(`TerminalClient.simulatedQuirks`) now get the same guard, priced by
`TerminalQuirks.peakAdvance(of:)`, and one cell stricter: a peak that ends ON
the last cell is replaced too, because the repair needs the cursor a column
past the peak and none exists (pinned with autowrap off; held there with its
wrap pending on an xterm-family host with it on), so the `CUB` lands a column
short and the next cell overwrites the cluster's right half.
`QuirksRightEdgeClipTests` checks it against a cursor model rather than its own
arithmetic — every cell of a clipped, padded, compensated row lands on its
claim — and pins the Apple-shaped set to Terminal.app's clip with the same rule
at the edge over the whole width corpus. Terminal.app's own clip still keeps a
peak that ends on the last cell, the bet it has made since 2026-08-28 with
autowrap on (unmeasured; its edge card is owed), so Apple Terminal keeps
autowrap on until its card (above) — turned on at startup and on every
resume (`CSI ? 7 h`), not inherited, so a window a killed program left with
it off runs that bet on a row that wraps. The measured hosts other than Apple Terminal
advance no cluster past its claim, except Warp's keycaps, its EAW-base VS-16
exceptions and its tag flag, which no escape can repair and which still go
out unguarded.

**Apple Terminal first, by card — and kept on until then.**
`FrameDiffWriter.repaintRightEdge`, its phantom right-edge repaint, was written
against a row that *wraps*, and so was its clip's bet that an over-advancer's
peak may end on the last cell. With autowrap off the repaint may have
nothing left to do, or may need adjusting; an over-wide last-row card on Apple
Terminal (light and dark), run once with `printf '\e[?7l'` sent by hand since
TUI no longer sends it there, decides, then the same card on iTerm2 with
ambiguous-wide on, Ghostty, Warp, kitty and tmux. `Stress --selfcheck`
passes; it draws no terminal.

| Host | Over-wide last row stays on its row | Bottom row does not scroll the screen | Apple's right-edge repaint still needed |
|---|---|---|---|
| Apple Terminal (light, dark) | UNMEASURED; autowrap kept on | UNMEASURED | UNMEASURED |
| iTerm2, ambiguous-wide on | UNMEASURED | UNMEASURED | — |
| Ghostty | UNMEASURED | UNMEASURED | — |
| Warp | UNMEASURED | UNMEASURED | — |
| kitty | UNMEASURED | UNMEASURED | — |
| tmux in Ghostty, in iTerm2 | UNMEASURED | UNMEASURED | — |

Found by reading Ghostty's VT reference (`Documentation/Terminals/Ghostty VT reference adoption study.md`,
K3).

## Where the adaptations live

- `TerminalHost` — `TERM_PROGRAM` detection (`Apple_Terminal`,
  `iTerm.app`, `ghostty`, `WarpTerminal`) + the `supportsEmojiChrome`
  allowlist (all four; Ghostty only because its CUF fixes the VS-15
  under-advance).
- `Character.terminalAppCursorAdvance` / `.iTerm2CursorAdvance` /
  `.ghosttyCursorAdvance` / `.warpCursorAdvance` — the per-host advance
  models (TUICore), pinned to the committed measurement records in
  `Tools/TerminalProbes/data/` by `TerminalLedgerConformanceTests` (which
  also carries the known-divergence ledger), with spot batteries in
  `GhosttyWarpCompatibilityTests` / `StringTerminalWidthTests`.
- `TerminalWidthTraits` + `TerminalClient.widthTraits(of:)` — the per-host
  CLAIMS the models answer against: what a ZWJ sequence, a skin tone, the
  overhanging chrome and, since 2026-10-19, a multi-scalar cluster of text
  (`textClusters`) are allocated on each host. Published once at startup and
  read by `Character.terminalWidth`; `ComplexScriptHostAdvanceTests` pins the
  text-cluster claim to every host's advance records.
- `TerminalClient.detectColors(using:)` — asks OSC 10, 11 and (outside tmux)
  OSC 4 once at startup through `Terminal.queryColors`, and publishes the
  answer to `TerminalColors.current` before the first frame. See "What the
  framework asks at startup"; `Tools/Smoke/colour_query_smoke.py` checks the
  wiring — the sixteen OSC 4 queries sent exactly once in a run where the screen
  is never thrown away, the focus never comes back and the terminal never
  reports its theme: in the startup request off tmux, after frame one under
  tmux (`TerminalColorRequester`, below, which asks them again on each of those
  three) — and that frame one of an app with clear grounds leaves them to the
  terminal (SGR 49) over a reported page and over silence.
- `TerminalColorRefresher` — what the terminal says about its colours after that
  exchange has closed. `Terminal.noteVolunteeredColorReply` keeps an OSC 10, 11
  or 4 answer and a `CSI ? 997` report where the input parser would have dropped
  them, `AppRunner` hands them over once per drain, and a report that changes the
  record is published to `TerminalColors.current` with a full repaint. A
  `CSI ? 997` is handed on separately (`takeAppearanceReport`), because it says
  the theme changed rather than what anything paints.
- `Terminal.enableRawMode` / `disableRawMode` — DEC mode 2031 on and off, so the
  terminal reports its own palette changes while the app runs and stops the
  moment it suspends or quits. See "Colour-palette update notifications
  (mode 2031)".
- `TerminalHost.installTmuxThemeChangeHooks()` — the tmux half of the same
  question: `client-light-theme` and `client-dark-theme`, registered in their own
  invocation so a tmux that does not know them cannot take the client-change
  hooks down too, and firing the same backgrounded SIGWINCH. See "Identifying the
  client terminal".
- `TerminalColorRequester` — when the terminal is asked again. Under tmux the
  first frame is followed by the sixteen-slot request the startup exchange left
  out, written and not waited for, because tmux holds the fence about half a
  second when the client it forwards OSC 4 to is silent; its answer arrives as a
  late reply, through the refresher above. A thrown-away screen (resize, resumed
  suspend, tmux client change) asks the whole request again, skipping a terminal
  that has never answered unless it is tmux or has sent a `997`, and so does a
  window taking the focus back (`AppRunner.terminalFocusChanged` →
  `RenderLoop.terminalFocusRegained`), which is the only notice most hosts give
  that the user was away while their terminal changed. One request is
  outstanding at a time — `Terminal.takeStatusFence` hands over the `CSI 0 n`
  that releases the next, and a fence still missing a second later is taken as
  lost and the request sent once more.
- `Terminal.enableRawMode` / `disableRawMode` — focus reporting (mode 1004)
  on and off; `Terminal.finalize` reads the reports as
  `TerminalInput.focusChanged`; `AppRunner.terminalFocusChanged` moves
  `ScenePhase` between `.active` and `.inactive`. See "Focus reporting
  (mode 1004)".
- `ClipboardWriter` + `TerminalClient.clipboardWrites` + `SessionLocality` —
  where a copy goes: OSC 52 to a host that writes it, this machine's
  clipboard helper only when the user is at this machine (behind
  `ClipboardBackend`; the helper's is `SystemClipboard.Backend`, installed by
  `AppRunner` alone), and the status bar's line when neither reaches them.
  See "OSC 52 clipboard writes".
- `Terminal.maxControlSequenceBytes` + `Terminal.maxStringSequenceBytes` —
  how much of a sequence the input parser holds before it skips the rest
  (never typing it): 16 KiB for a CSI, 64 KiB for an OSC, DCS, APC, PM or
  SOS, since 2026-10-12 (4 KiB for both before). Sized against the longest
  replies on record: an xterm-class device-attributes answer of 37 bytes
  (the CSI walk's, `Terminal+Input.swift`; iTerm2's is 33, "What each host
  advertises"), and a graphics error in words, iTerm2's `ENOENT` of some
  eighty characters (the classic placements, under "Graphics protocols, and
  a parser gap"). An OSC 52 clipboard answer is unbounded by nature; TUI
  sends no OSC 52 query, so one arriving answers another program and is
  skipped. Every reply TUI asks for, with its longest:
  `Documentation/Historical/Input, keys and gestures/Large pastes and over-long input sequences.md`, B-PASTE-2.
- `KeyEvent.normalizingLegacyShiftedFunctionKeys()` +
  `Terminal.finalize` — Apple Terminal's shifted-function-key re-coding
  (F13…F20 read back as Shift+F5…F12), gated on `TerminalHost.isAppleTerminal`.
- `String+CursorCompensation.swift` — the per-host line rewriters.
  `withCursorForwardCompensation(advance:)` is the shared erase-and-push
  walk (iTerm2, Ghostty, Warp, tmux), which also drops ZWJ joiners and the
  redundant tone VS-16 where the traits say so; Terminal.app keeps its own
  walk for its rewrites (tone separation) and store surgery.
  `String.withSkinToneFallback(scope:)` — the swatch strip: live only for
  tmux (the measured `.keepingTmuxMerged` set) and as the no-traits
  fallback on iTerm2/Warp.
- `TerminalCapabilities` + `\.terminalCapabilities` (decisions TERMCAPS-API,
  2026-10-24) — what this document's tables decide, published to an app
  feature by feature as supported, unsupported or undetermined: the line
  styles from `TerminalHost.lineStyles(for:)` and the strikethrough row of
  "Underline shapes and colours"; pictures from the graphics handshake; the
  keyboard from the kitty protocol's negotiation; links, clipboard writes,
  notifications, the progress bar and pointer shapes from the ladders TUI
  sends them by (`TerminalCapabilities+Launch.swift`); and Option as Meta from
  the keys ("Option arrives in two different spellings"). A host this document
  has not measured for a feature is undetermined, not unsupported, and a row
  re-measured here reaches the app through the table it already changes.

### Per-host output pipeline (FrameDiffWriter)

The branch is checked in this order, **tmux first** — its grid is what our
output lands in, so it must win over any native host flag that leaked into the
pane. (`FrameDiffWriter.init` also zeroes the four native flags when `isTmux`,
so the tmux-first rule holds at the clip and right-edge repaint too, not only
here.)

| Host | Clip | Then |
|---|---|---|
| tmux | plain | `withSkinToneFallback(scope:)` (`.keepingTmuxMerged` when every client renders kept tones, `.all` otherwise — per-client, push-refreshed) → `withTmuxCursorCompensation()` |
| Apple Terminal | cursor-aware | `withTerminalAppCursorCompensation()` |
| iTerm2 | plain | `withITerm2CursorCompensation()` (the strip is inert under the published `.detachedOnBMPBases` claims — no-traits fallback only) |
| Ghostty | plain | `withGhosttyCursorCompensation()` |
| Warp | plain | `withWarpCursorCompensation()` (strip inert under `.detached` claims, as iTerm2) |
| GNOME Terminal | plain | `withGnomeTerminalCursorCompensation()` |
| anything else | plain | **untouched** (compensation would corrupt a correct terminal) |
- `FrameDiffWriter` — applies the rewriters on its build path; Apple-only
  right-edge repaint.
- `ToggleCharacterSet.automatic` + `SwitchIndicatorGlyphs` — chrome glyph
  selection per host.

#### The animation replay reset to the TERMINAL's background — FIXED 2026-08-29

Every styled fragment ends in `ESC[0m`, and a reset returns the terminal to ITS
default: white on Apple Terminal's light profile, black on a dark one. A
rendered row has the page's background put back after every reset by
`FrameDiffWriter.buildLine`, which is why the Animation page's *fading* text was
fixed by splitting the collapsed `ESC[0;…m` so the restoration could find it.

The *breathing* text was still white, and by the one path that does not build a
row: the animation replay splices a run's frame into an already-built line, and
the frame comes straight from the view having been through neither the
compensation nor the background restoration. Captured under
`TERM_PROGRAM=Apple_Terminal`, one tick read

```
ESC[38;3H ESC[0;38;5;34m Still here, still breathing. ESC[0m
```

— no background code anywhere in it, so the run's own cells took the terminal's.
The restoration is now a shared function that `patchingAnimatedRun` applies to
the frame before compensating it; the same capture now reads
`ESC[0;38;5;34;48;5;16m`.

**Superseded 2026-09-24: the field recorded beneath each cell, restated before
the compensation.** The fix above answered "what is under a cell the frame
leaves bare?" in two ways, and both were wrong somewhere:

- **After a reset in the frame, the page.** Right for a row on the page, wrong
  in any container that paints a field of its own, and a frame that names a
  background is one the splice leaves alone — so every bare cell after the
  frame's first reset came out in the page's colour whatever it sat on. Seen as
  a compact tab chip nested in another tab: while the inner strip held the
  focus, its right cap (`▌`, ink on no field, after the label's reset) was drawn
  in the page's colour inside the outer tab's surface on every tick, and its
  left cap, before the first reset, kept the surface. Measured live
  (`Example --page tabViews`, a 140×60 PTY read through pyte in truecolor, eight
  samples at each focus stop where the nested strip breathes): the right cap
  read `050a05`, the page, at every sample, the left cap `0d1a0d`. The blank
  beside a plain button's focus dot and an indeterminate `ProgressView`'s track
  did the same in any container with a field.
- **Before the first reset, the field the row showed under the run's first
  cell.** That is whatever the render DREW there, which is the drawn frame's own
  field wherever the frame named one. A block caret drawn visible in a `.plain`
  `TextField` (no field of its own) was read back as the caret's colour, and the
  blink's hidden frame, which leaves the cell bare, was painted in it: the caret
  never blinked off.

Both are replaced by one record. A run now carries its GROUND
(`AnimatedCellRun.ground`): what the containers around it painted beneath its
cells, recorded by each painter as it paints — a `.background` (flat or ramp),
compositing and a floating layer made opaque, a `List` row's fill, a menu row's
bar — with the very function it paints the lines with; and rewritten by every
pass that rewrites the fields of lines already painted, with the function it
rewrites them with — the flatten `.dimmed()` and a modal's backdrop go through,
the colour effects, and a transition's fade (see the later notes below). The
replay reads it on the row's page, exactly as `buildLine` reads a row (the page
in front, restated after every reset: `AnimatedCellRun.groundFields(onPage:)`),
so a cell no painter reached sits on the page and every other cell on its
innermost painter's field.
`String.paintedOver(fields:)` puts that field under each cell the frame leaves
bare: at the start, after every SGR that leaves the frame naming no field of its
own (a reset in either spelling included), and before a cell whose field
differs. The page restoration survives for whole rows only (`buildLine`).

**The order stays: fields first, then the host's compensation.** On Apple
Terminal, iTerm2, Ghostty and Warp the compensation writes an erase (`ECH`) in
front of a glyph the host advances too little over, and an erase paints in
whatever background is in force when it runs. With the page restored first, a
glyph inside a container was erased in the page's colour: rendered and replayed
through each host's writer, a `⚙️` / `⬛︎` / `🇦` on a panel erased
`[2 at 3 in …48;2;5;10;5m]` on replay against the render's
`[2 at 3 in …48;2;13;26;13m]`, on all four hosts. Now the erase runs in the
panel's field on every host, on the page and in a panel. (With the restatement
after every SGR, the ECH the compensation puts after a reset follows the
restated field either way round for these frames; the order is kept because it
is the one that cannot depend on where the compensation puts its escapes.)

The bytes are host-independent; the erase is where the hosts differ. Pinned end
to end through the run loop by `ReplayedTabChipBackgroundTests` (the chip,
top-level, nested in a bordered tab and in a compact one),
`ReplayedCaretBlinkTests` (the caret on the page, on a colour and under a fade),
`ReplayedWholeRowFadeTests` (a whole-row fade, on a painted page and on
`Color.default`) and `ReplayedRunFieldTests` (every run of a catalogue of
controls on every ground listed there, each replayed tick against a render at
the same instant); per host by `ReplayedEraseFieldTests`; the record by
`AnimatedRunGroundTests`.

**2026-09-24, later: a pass that rewrites the fields rewrites the grounds.** The
painter list above first named only the painters that put a field under content.
The passes that REWRITE the fields of lines already painted were left out, and
each left every run's ground as it was while the lines moved on. The flatten
behind a modal and under `.dimmed()` repaints every line and every frame of every
run it keeps in its wash. When the wash is `Color.default` every frame states
`ESC[49m`, which then named no field of its own to the splice (the note after
this one gives a stated 49 a record of its own), so every cell was drawn over a
ground that still held what was painted beneath the dim. Measured through
the run loop (`ReplayedRunFieldTests`: a catalogue of controls on a colour, on a
`Color.default` palette, dimmed and behind a sheet), three rows per ground:
`replayed '⠦' … on "…48;2;90;20;120m", rendered '⠦' … on ""`. The flatten now
washes each kept run's ground with its frames. A ground no painter had reached is
washed too, so a fill painted OUTSIDE the dim finds the wash in front of it, as the
row does. Pinned per placement and wash by `AnimatedRunGroundTests`. Washing only
a ground that already existed fails a fill outside the dim on both washes.

**2026-09-24, later: a frame that STATES the terminal's own field.** A frame
can put a cell on the terminal's own field by stating `ESC[49m`. Scanning every
run that the replay suites and the catalogue keep turned up three sources:
- the flatten on a `Color.default` wash (above);
- a tab chip's label on a `Color.default` palette
  (`ESC[1;38;2;230;120;40;49m Gamma`);
- a `.plain` block caret, reversed over the terminal's own
  (`ESC[7;38;2;220;220;220;49m `).

A `.background(Color.default)` puts its 49 in the ground, not in a frame. The
painters disagree about a stated 49:
- One that restates its field only after a reset lets it through, and the cell
  shows the terminal's own. That is a `.background`, a `List` row, a menu row's
  bar, and the page in `buildLine`. A ramp is a `.background` here too: each of
  its pieces puts its own colour in front of a slice of the row that opens with
  the row's styling so far (`BackgroundModifier`, `ansiAwareSlicedRuns`), a
  stated 49 included, so the 49 lasts until the frame's next reset, as it does
  under a flat one.
- Compositing (`String.paintedOver(background:)`: a `ZStack`, an `.overlay`)
  reads it as no field and fills it with the field it lands on. A floating
  layer made opaque (`OverlayLayer.isOpaque`) fills it too, but with its own
  surface: the page's colour, painted onto the layer before it is composited
  (`FrameBuffer.paintedOver(background:)`), after which the layer is
  composited as painted and asks nothing of what it lands on (2026-09-25,
  below).

Neither blanket rule matches the render. Measured through the run loop (a
compact chip and a block caret on a `Color.default` palette, focus walked):

| inside | 49 = no field (round 3) | 49 = the frame's own field |
|---|---|---|
| `.background(.blue)` | chip and caret replay on blue, render on the terminal's own | match |
| a `ZStack` over blue, an `.overlay` on blue | match | replay on the terminal's own, render on blue |

So the answer is recorded rather than chosen. A run carries a second record,
`AnimatedCellRun.groundUnderStatedDefault`. It is painted by every painter with
the function it paints the lines with, starting from a row that states `ESC[49m`
in front of its cells, so it holds whatever each painter did to a stated 49. The
splice (`String.paintedOver(fields:)`) draws a cell over that record from the
frame's `ESC[49m` until the frame next resets or names a colour, and over the
ground otherwise. `AnimatedRunGroundTests` holds the drawn frame of a probe that
states `ESC[49m`, spliced over its row, to that row inside every painter. Before
this change it failed seven of the nine painters: none (the page), a background, a
background around padding, nested backgrounds, a ramp, a `List` row's fill, and a
tab's surface. It passed the two compositors. `ReplayedRunFieldTests` gains the
catalogue on a colour on `Color.default`, painted as a `.background` (3 rows
failed before: the caret and both chips) and composited under a `ZStack`.
Reading a stated 49 as the frame's own field instead fails the compositors
there: 3 rows, and the `ZStack` and `.overlay` painters. The record states the
49 once, in front of the run's first cell, and that answers for a 49 stated
anywhere in a frame: no painter's answer depends on where in its row the 49 is
stated. The same test splices a second probe, which leaves its first cell bare
and states 49 under its second, inside every painter.

**2026-09-24, later: a fade reads a stated 49 as the terminal's own field.** The
row opens on the page and the writer puts the page back after every reset, so on
a page with an RGB a stated 49 is a colour of its own — on Apple Terminal's light
profile, white on a dark page. The opacity blend read it as no field, and its
rebuild of a covered row netted a reset and a 49 as one state, so a faded row
could put either field where the unfaded one has the other: a cell after a
coloured one on the terminal's own (the rebuild spelled its reset `ESC[49m`), and
`Text("ab").background(Color.default).opacity(0.6)` on the page. Both are fixed
at the blend, not the terminal: `Opacity as composition.md` §94 and §95, pinned by
`FadedTerminalFieldTests` through `FrameDiffWriter`'s row builder, which is what
tells the two apart. A transition's fade (`.transition(.opacity)`, `OpacityFade`)
read a stated 49 as the page outright, and now reads it as `.opacity` does.
Compositing's reading of a stated 49 (above) is unchanged, and a fade resolved against
a compositor's base reads the layer's stated 49 the same way: as the field the composite
fills it with, where the base shows one. Read as the terminal's own, it was mixed with the
page the terminal reported (OSC 11) — a label on `Color.default` faded in a `ZStack` over red
came out between the two, where unfaded it is on the red. Unreported, no RGB was there to mix.

**2026-09-24, later: the colour effects rewrite the runs too.** `.colorInvert()`,
`.grayscale(_:)`, `.hueRotation(_:)`, `.brightness(_:)`, `.contrast(_:)`,
`.saturation(_:)` and `.colorMultiply(_:)` rewrite every colour a subtree's
lines name (`SGRColorRewrite`) and left its runs alone. The ground still held
the field from before the effect, so a `Spinner().background(.blue)
.colorInvert()` replayed on blue where the render drew yellow. The frames still
held the ink from before the effect, so the glyph replayed in its old colour.
The ink was already wrong before grounds existed; the field went wrong when the
replay began reading the ground. Measured through the run loop
(`ReplayedRunFieldTests`, the catalogue on a colour, inverted), 22 rows, e.g.
`replayed '⠦' in "…38;2;102;255;102m" on "…48;2;90;20;120m", rendered '⠦' in
"…38;2;153;0;153m" on "…48;2;165;235;135m"`. The effect now puts every run's
frames and both of its records through the same rewrite as the lines
(`FrameBuffer.restyleRuns`). Pinned per effect by `ColorEffectRunTests`.

**2026-09-24, later: so does a transition's fade.** `.transition(.opacity)`
fades a view's lines by the same colour rewrite (`OpacityFade.fading`) and left
its runs unfaded. A transition renders on the view-animation lattice, every 2
ticks, and a run's step that lands between two renders is replayed onto the
frame the last one left. Driven through the loop, a `.dots` spinner (7 ticks a
step) inserted with a one-second `.opacity` transition changes at 4 ticks where
no render is due. Each of those replays drew the spinner at full strength, on
its unfaded field, in a view half faded out. The ink was never faded; the field
went wrong when the replay began reading the ground. The fade now puts the runs
through the rewrite it puts the lines through (`FrameBuffer.restyleRuns`).
Pinned at three phases by `TransitionFadeRunTests`, and there through the run
loop as well: `ReplayOracle` renders on the transition's lattice and replays
between, checking each replayed cell's colours against the render the loop last
made, which is what the screen shows between two of them.

**2026-09-24, later: and so does a fade's blend.** `.opacity(_:)` blends each
run's frames where it blends the lines (`OpacityResolution.faded`), and blends a
cell the frame states no field for from the field beneath it, the run's ground.
It blended a cell the frame puts on the terminal's own field by stating
`ESC[49m` from the ground too, where the splice draws that cell over the second
record. So a frame stating 49 inside `.background(c).opacity(0.6)` on a
`Color.default` palette — a tab chip's label, a `.plain` block caret — was
blended from `c` and stated it, while the row, whose `.background` lets the 49
through, shows the terminal's own. The blend now takes such a cell's field from
`groundUnderStatedDefault`, telling the two apart by the frame's own statement
as the splice does. Pinned per painter at the faded level by
`AnimatedRunGroundTests`; before, the probe inside a `.background` and inside
nested ones failed, e.g. `(drawn → ["…48;2;200;40;40m", …]) == (shown → ["",
""])`.

Found beside it, and in the render rather than the replay (fixed in the next
note): the opacity splice (`FrameBuffer.splicing`) paints the field under its
span's first column beneath every cell the span spells `ESC[49m`, because it
composites and compositing reads 49 as no field. On a `Color.default` palette
every cell that blends to the terminal's own is spelled that way, a stated 49
included. So a faded row takes the colour of the cell its span starts on
wherever it should show the terminal's own: `HStack { Text("x").background(.blue);
Text("y") }.opacity(0.6)` draws `y` on blue, where `.opacity(1)` draws it on the
terminal's own (measured on this tree; the splice is main's). `AnimatedRunGroundTests`
held the probe inside padding and a border, and on a ramp, as known issues.

**2026-09-24, later: the opacity splice takes its span literally.** The span
the fade splices back into its row states every field it has: a covered cell
names one (the surface where the blend leaves none), and a cell it passes over
between two regions is the row's own. Nothing about it wants the compositor's
reading of 49, which was never chosen: `splicing` predates compositing painting
an overlay over the field it lands on (`590e71a4`), and inherited that step from
the insert both share. It now inserts the span as the animation tick inserts a
frame, without painting it (`overlayIsPainted`). Measured before, on a
`Color.default` palette in truecolor: the faded `y` above was drawn on
`48;2;0;122;255`, the UNFADED blue; `FadedTerminalFieldTests`, which holds a
probe with a coloured cell, a bare one and a stated 49 inside every painter
(`TestHelpers/FieldPainter.swift`) faded to 0.6 around it, failed five of the
nine — none, a background, one around padding and a border, nested ones, a
ramp — each with every terminal-own column of its row coloured (e.g. `[] ==
[5, 6]` around padding). The other four passed for three different reasons,
not one: the `List` row and the tab's surface because their spans open on no
field (a list's rows are unfilled or reversed on such a palette, and a tab's
surface is the page); the two compositors because compositing had already filled
every 49 under the probe with its colour, and at 0.6 a colour outweighs the page,
so the faded span stated no 49 for the splice to fill. (An earlier version of
this note gave the first reason for all four.)

The replay takes the same literal reading of a faded frame. A covered cell of a
faded frame names its field too, a 49 the blend made among them, and the tick
read that 49 as a STATED one, drawn over the record of what the painters made of
a stated 49 — under a compositor, its colour. So with the render's splice literal,
a probe run faded to 0.4 over green in a `ZStack`, or in an `.overlay` on green,
rendered on the terminal's own (the page is the heavier side below one half) and
replayed on the green, for a frame stating 49 and for one stating none alike
(`AnimatedRunGroundTests`, at 0.6 and 0.4). The fade now rewrites that record to
the terminal's own at the columns every frame was blended at, and a painter the
run meets afterwards paints it as it paints the line.

Through the run loop, `ReplayedRunFieldTests` gains the catalogue faded on the
terminal's page three ways: to 0.6 around the colour (a `.background`), and to
0.4 inside it and inside a `ZStack` over it — faded below one half AROUND the
colour, every colour and ink blends to the page there and nothing is left to
replay. Before, faded around it, four rows disagreed, each rendered on
`48;2;90;20;120` (the colour, unfaded) where the replay drew the terminal's own
or the bar's colour — two tab chips' labels, and the spinners in a menu's focused
row and a list's cursor row. After, the chips agree; the two spinners still
disagree, only because their rows are reversals (below). `AnimatedRunGroundTests`
drops its two known issues. `AnimatedRunPatchGoldenTests` re-captures the splice
half of the four rows that land a field-less frame on a field. A reversed cell
stating 49, a `.plain` block caret, is §95's in `Opacity as composition.md`: its
49 is in the slot a reversal shows as ink, and the faded frame now takes the
record there.

Open when this was written (2026-09-24): the replay restated the ground's field
only. A reversal (SGR 7) a row paints over its content was recorded in the
ground but not restated by the splice, so a run inside a reversed row replayed
unreversed; a persistent dim was neither recorded nor restated (`Opacity as
composition.md`, the reversed rows' limits). The reversal was inferred at first
and measured on 2026-09-24: a `Spinner` in the focused row of an inline `Menu`
on a `Color.default` palette, whose bar is a reversal because there is no RGB to
breathe between, replayed `⠹` in `ESC[38;2;220;220;220m` where a render at the
same instant drew it in `ESC[7;38;2;220;220;220m`. The dim was inferred.
`ReplayOracle` then compared each cell's glyph and field and a glyph's ink, not
its attributes, so neither showed there — unfaded. Faded, the reversal did show:
the fade blended a run's frame over its ground, which read the row's reversal as
a field, the bar's colour, so the frame stated that field under its own ink,
unreversed, while the render kept the reversal (the page as ink has no spelling
without it). The same spinner, and one in a list's cursor row, replayed in their
own ink on `48;2;220;220;220m` where the render drew them reversed. Faded INSIDE
a colour, the render resolved the reversal at the painter, where it can be
spelled without the 7, and the same two spinners replayed inked in the colour
the render drew as their field. For as long as that stood, `ReplayOracle` took a
cell-level excuse (`holding`) and reported the rows it held apart from its
mismatches — a held cell did not stop the comparison, so a row's other
disagreements still failed — and `ReplayedRunFieldTests` held, on each faded
ground, exactly those two rows, named by what they drew and asserted to be all
it held. Both are gone. Closed 2026-09-25: the reversal faded and unfaded, and
the dim — the last three notes of this section.

**2026-09-25: a floating surface is composited as it is painted.** The compositor
above fills a stated 49, and a floating surface on a palette whose page is the
terminal's own is spelled exactly that: the layer is painted onto the page's
colour first (`OverlayLayer.isOpaque`), and that colour is `ESC[49m`. So every
menu, drop-down, context menu, popover, toast, drag preview and full-screen cover
on such a palette showed the field under its first cell through its whole surface
(a sheet and an alert dim the page to one field first), and each run
inside it recorded the same in its ground. A surface states every cell's field
once painted, so it is now composited without being painted again
(`FrameBuffer.composited(with:at:overlayIsPainted:)`), its runs' grounds likewise;
on an RGB surface the bytes are unchanged. `Opacity as composition.md` §98;
`FloatingLayerOpacityTests` (every presentation on the terminal's own page) and
`AnimatedRunGroundTests`.

**2026-09-25, later: compositing fills under each cell's own column.** The
compositor read the field it paints an overlay over — and fills a stated 49
with — ONCE per overlay row, under the overlay's first column, so a label over
two colours was drawn all on the first, and the runs inside it recorded that
one field in their grounds. Each cell now takes the field under its own column,
a stated 49 included, and each run's ground records the same, column by column
(`FieldsUnderOverlay`, `String.paintedOver(fieldsUnder:)`). Where the base has
no field under a column, the overlay goes back to none with a reset and its own
styling restated — the page, as the row builder puts it back — not with
`ESC[49m`, which would be the terminal's own; a stated 49 over no field stays
the terminal's own. One field under the whole overlay is painted in the same
bytes as before. `Opacity as composition.md` §99; `CompositedFieldPerColumnTests`,
and through the run loop `ReplayedRunFieldTests`' catalogue composited over a
ramp.

**2026-09-25, later: a stated 49 in the base is a field too.** The compositor
read the base's field under an overlay from the netted SGR state, where a
reset and `ESC[49m` are one "no background" — exact for bytes that go to the
terminal as they are, not for a row the writer has yet to finish, which puts
the page back after every reset. So on a page with an RGB an overlay cell over
a stated 49 in the base, and every cell after the overlay while that 49 was in
force, took the page where the base shows the terminal's own (on Apple
Terminal's light profile, a dark page for a white field). The split now tracks
the field as the row builder will read it, and says a stated 49 again after the
overlay's reset; the tick's splice restores the cells after a frame the same
way. `Opacity as composition.md` §99.1; `CompositedFieldPerColumnTests`.

**2026-09-25, later: a reversed base's field is its ink.** Under SGR 7 a cell
shows its foreground as its field, and the compositor read the field slot: a
label laid over a list's reversed cursor row (`ESC[7;<ink>;49m`) was drawn on
the terminal's own field in the middle of the row's bar. The split now takes the
ink as the field there, spelled for the background slot. A reversal of the
terminal's own ink (`ESC[7;39…m`) has no such spelling and is left as it was
(until 2026-09-26, below).
No built-in view composites over a reversed cell (measured through the suite
and the Example on both of its palettes); an app's own `ZStack`, `.overlay` or
`Layout` does. `Opacity as composition.md` §99.2.

**2026-09-25, later still: faded, a run in a reversed row is blended as the row
draws it.** The reversal left open above reached the fade too, and there it
drew something different from the unfaded replay. Measured live before the
change: a temporary `IdleProbe` mode, an inline `Menu` whose first row is `Busy`
and a `Spinner` and a `List` whose rows each end in one, on a palette whose page
is `Color.default` and whose roles are RGB (the catalogue's `terminalPagePalette`);
a 60×20 PTY, `TERM=xterm-256color`, `COLORTERM=truecolor`, read through pyte after
every burst the app wrote, for 0.6 s after each Tab. Faded to 0.6 around a
`.background` colour, with the menu row focused, the render drew the spinner
reversed (`38;2;220;220;220` on the terminal's own field, SGR 7) and each of the
five ticks after it drew the glyph in `220;220;220` on `220;220;220` — nothing to
see; the list's cursor row the same, its spinner in `230;120;40` on
`220;220;220`. Faded to 0.4 inside the colour, the menu's render drew
`90;20;120` on `142;100;160` and every tick `142;100;160` on `142;100;160`; the
list's render `90;20;120` on `146;60;88`, every tick `146;60;88` on
`142;100;160`. The fade blended a frame over its ground and took a bare cell's
field from the record, but a reversed row records `ESC[7;<ink>;<field>m`, and the
blend's parse — which exchanges a reversed cell's colours — read the record's ink,
the bar, as that field, under a frame cell it blended unreversed. The frame is
now drawn in what the painters restated beside the field before it is blended
(`AnimatedCellRun.groundStyle`, `String.restatingGroundStyle(_:)`: the 7 and its
ink, in front of each cell, the frame's own statements since its last reset over
them), and the field goes into the cell's background slot from the record's own.
After, every burst matched the render. `ReplayedRunFieldTests` holds nothing on
its faded grounds any more, and `ReplayOracle` loses its `holding`;
`AnimatedRunGroundTests` drops its known issue. `Opacity as composition.md` §100.
Unfaded, the tick still restated the field alone — the note after this one.

**2026-09-25, and unfaded: the tick restates a reversed row's style with its
field.** The same probe, unfaded, measured before the change: with the menu row
focused, the render drew the spinner reversed and each of the five ticks after
it drew `⠹` in `38;2;220;220;220` on the terminal's own field, no 7 — the bar one
cell short at its end; the list's cursor row with a one-cell hole where its
spinner sits, the glyph in the accent. On the Example's own Terminal palette
(`LiveTerminalPalette`, reached by F2 from the default; the terminal's pair and
slots, unreported through a PTY that answers nothing), the menu row the same in
the terminal's own pair, still so after `ESC[O` reports the window's focus lost
(the bar stays reversed); and in the Example itself (`--page lists`, the
multi-line list focused, 120×40), the cursor row's spinner reversed on the
render and unreversed on each of the seven ticks after it, the row reversed at
114 of its 115 cells. Not reached: a row that is not the cursor, a list without
the focus, and a breathing bar or cursor row on a palette with RGB, which drops
its label's runs and wakes for their steps instead — unchanged, measured the
same way. `ReplayOracle` could not see it: it compared colours as spelled and no
attributes, and the two spellings differed only by the 7; it now compares cells
as they look (`PaintedCell.looksLike(_:)`). The tick now draws a frame in the
painters' style under each cell (`AnimatedCellRun.GroundFields.style`, read with
the fields once per render) before the field, and a run a fade has blended
drops its record under a bare cell (every cell of its frames is re-spelled from
the frame composed over it, so the 7 restated again would reverse those cells a
second time). A run whose painters restate only a field — nearly every run — has
no style, and its bytes are as they were (`AnimatedRunPatchGoldenTests`). After,
every burst of every variant above matched the render: reversed on every tick,
before and after the focus report, and the Example's cursor row reversed at all
115 cells on every tick. `Opacity as composition.md` §101; `RowStyleReplayTests`,
and `ReplayedRunFieldTests` under the new oracle. Still open from the paragraph
above at that point: a persistent dim, neither recorded nor restated — closed by
the next note.

**2026-09-25, and the dim.** A `List` row under `.selectionDisabled()` is drawn
faint — `ESC[2m` restated after every reset in its lines — and the modifier
painted nothing into its runs' grounds, so a spinner in it was drawn faint by
every render and at full intensity by every tick between them. Measured through
the run loop only (`ReplayedRunFieldTests`, its list's last row refusing
selection: on every ground but the two the flatten washes, e.g. `.page: … '⠦' in
rgb(102, 255, 102) on rgb(5, 10, 5), rendered … [2]`); pyte, which the PTY probes
read the screen through, keeps no SGR 2. The modifier now paints its runs'
grounds with the same dim, and the tick and the fade restate it as they restate a
reversal. `Opacity as composition.md` §102; `RowStyleReplayTests`' faint row.

**2026-09-26: a transition fades a run in a reversed row as the row draws it.**
Over the terminal's unreported page, a transition's fade drops a glyph whose ink
and field, as the cell displays them, are both that page, and clears the
reversal with it. A spinner's frame in a reversed row carries no 7 of its own,
so, faded alone, it kept its glyph while the line dropped it, and the tick drew
it in the terminal's foreground between the transition's renders. A frame is now
faded in the row's style, with a reversal's `39` kept as stated.
`Opacity as composition.md` §101.1; `TransitionFadeRunTests`.
**2026-09-26: a cell over a reversal of the terminal's own ink is drawn on that
ink.** Such a reversal (`ESC[7;39…m`) shows the terminal's FOREGROUND as its
field, which no background code spells, and an overlay cell over it took the
background slot, the terminal's own background. The compositor now draws that
cell reversed itself — `ESC[7;39;<its ink as a background>m`, the 7 showing 39 as
the field and the moved ink as ink — or, where the terminal has reported its
foreground (OSC 10) and colour is 24-bit, on that RGB, unreversed. An ink that is
the terminal's own foreground has no background spelling, and on that field is
invisible: the glyph is dropped. This relies on the exchange the reversed rows
rely on; `reverse_video_card.py` asks it as rows I and J (bold), UNMEASURED.
`Opacity as composition.md` §107; `ReversedTerminalInkOverlayTests`.

**2026-09-26: a fade inside a reversed row is spent against the row.** A label
faded below one half in a reversed row (a focused list's cursor row, or a menu's
focused row, on a palette whose highlight has no RGB) was carried up past the
reversal. At the root it met the reversal's field as its own. Where that field
has no RGB (the palette's ink over a `Color.default` page, or the terminal's own
foreground), the page won below one half, and the label came out as two blanks on
the terminal's own field in the middle of the bar. With an RGB page and a slot
accent, the label's field was mixed toward the page at every alpha. The row now
spends its content's fades against the reversal, whose field is its ink. It does
so over its finished lines, after it has restated `ESC[7;<ink>;<field>m` after
every reset, so nothing restates the 7 over the spent cells again. This was
measured through the render (`ReversedRowFadeTests`), not live.
`Opacity as composition.md` §86.1.

#### The animation replay compensates a second time — FIXED 2026-08-29

A row is compensated when it is rendered. When an `AnimatedCellRun` on that row
ticks, the replay splices a fresh frame over the run's cells — and compensates
THAT, because the frame may carry a different cluster from the one the render
drew (a spinner's frames do).

Both walks therefore own the same cells, and the splice works in COLUMNS while
an escape claims none: the `ECH` the render put before the cluster and the `CUF`
it put after both survived, on either side of a frame that had brought its own
pair. The row was left one `CUF` long and every cell after the run sat one place
to the right — until the next full render redrew it correctly, so the offset
came and went with no period.

Reported against a focused `Toggle` in **Ghostty**, whose `⬜︎` (a chrome glyph
under VS-15) is compensated there and bare on every other host — so only Ghostty
showed it for that glyph. The class is not Ghostty's: the conservation test added
with the fix catches it on Apple Terminal and iTerm2 too, with `⚙️`.

Fixed at the splice (`FrameBuffer.patchingAnimatedCells`), which now removes the
render's compensation for the columns it is replacing before inserting the
frame. Which side a pair belongs to is decided by KIND, not position: at the
span's far edge an `ECH` introduces the cluster AFTER the span and stays, while
a `CUF` there closes the last cluster INSIDE it and goes.

Measured on the Example's Toggles page, Ghostty, the focused row:

    render   ESC[2K ' ' SGR ESC[2X ⬜︎ ESC[1C SGR ' ' SGR 'Enable…'
    replay   ESC[2K ' ' SGR ESC[2X SGR ESC[2X ⬜︎ ESC[1C SGR ESC[1C SGR ' ' …
                              ^^^^^^^^^^^^^^ frame's own pair    ^^^^^^^ leftover

### SGR codes the output path emits (recorded 2026-08-20)

`String.collapsingAdjacentSGR()` states a line's styling once and then emits
each subsequent change as a **delta** from the state it last established, not
as a reset-prefixed absolute. That narrows the emitted vocabulary to codes
that must be safe on every host in this document, so the set is worth writing
down:

| Codes | Used for | Portability |
|---|---|---|
| `0` | the line's first statement, and any attribute-off | universal |
| `1 2 3 4 5 7 8 9` | attributes ON | universal |
| `30–37 90–97 38;5;n 38;2;r;g;b` | foreground | per the depth rules above |
| `40–47 100–107 48;5;n 48;2;r;g;b` | background | per the depth rules above |
| **`39` / `49`** | foreground / background back to the terminal's own | ECMA-48 core; present in every host here, in tmux, and in the Linux console |

The codes deliberately **not** emitted are the attribute-*off* ones —
`21 22 23 24 25 27 28 29`. `21` is the reason: ECMA-48 assigns it
double-underline and several terminals read it as bold-off, so the two
readings disagree about what a line looks like afterwards.
``SGRState/rendered(changingFrom:)`` therefore declines to turn an attribute
off by delta at all and restates from `ESC[0m`, which every terminal agrees
about. (``SGRState/apply(_:)`` still *honours* both readings when parsing,
because there the conservative direction is the opposite one — treating an
off-code as a no-op would leave styling on that the source cleared.)

## Right-to-left text — measured 2026-09-01, in part

Run in each host with `Tools/TerminalProbes/bidi_card.py`, in the four installs
this document records elsewhere (no version was re-checked at the time). The
card prints nine-cell samples as `|<sample>|X` rows, twice: `plain` as TUI
would emit them today, and `forced` with each RTL run wrapped in U+202D LEFT-TO-
RIGHT OVERRIDE … U+202C POP DIRECTIONAL FORMATTING.

| Host | `plain` — RTL runs keep their columns | `forced` — the LRO/PDF controls |
|---|---|---|
| Apple Terminal.app | ✓ every X aligned | ✗ **painted as the missing-glyph box**, one cell wide, shifting every X one column right |
| iTerm2 | ✓ | ✓ consumed at zero width — every X still aligned |
| Ghostty | ✓ | ✓ consumed at zero width |
| Warp | ✓ | ✓ consumed at zero width |

**The decision this settles: TUI does not emit the override.** It was the
candidate fix for RTL, and on Apple Terminal — the one host RTL was reported
against — it is a visible regression: two junk glyphs per run and a column of
shear per run, in a host that was already painting the plain row's columns
correctly. The other three neither need it nor object to it. A per-host quirk
could apply it to those three only, but nothing measured here asks for one.

**What the card does not answer.** The X column tests *advance*, and a terminal
implementing the Unicode bidirectional algorithm does not change it: every row
here begins with ASCII, so the paragraph direction is LTR and an RTL run is
reversed *within the columns it already occupies*. Reordering therefore garbles
a run's contents without shearing the layout, which is consistent with the
original report ("using a Hebrew character messes up rendering") and with this
card showing every plain X aligned. A copy-paste cannot settle it either, since
the buffer hands back logical order however it was painted.

One row does expose it to a reader who does not read Hebrew: under the
algorithm `digits_after_rtl` (`אב 123 ab`) displays as `123 בא ab` — the digits
jump to the *left* of the Hebrew, hard against the opening `|`. The card now
says so on the row itself. Until someone reads that row in each host, "does
this terminal reorder?" stays open, and the answer changes nothing about the
override, which is refused on Terminal.app either way.

**The arithmetic is settled.** The bidi controls — LRM, RLM, ALM, the
embeddings and overrides (U+202A…U+202E) and the isolates (U+2066…U+2069) —
are `Default_Ignorable_Code_Point` with no advance, and TUI measured them as
one cell each until 2026-09-01. A line carrying one, as text pasted from a
bidirectional document does, measured a cell wider than it drew. They are
zero-width now (`BidiControlWidthTests`).

### RTL characters as image PIXELS — measured 2026-09-01, still OPEN

**Apple Terminal mirrors a picture made of right-to-left glyphs.** A
`TUIImage` `.customRamp` of Hebrew letters draws a gradient whose flat end
comes out at the wrong side of every row. The stakes differ from text:
reordering a run of letters is arguably the right thing there and merely looks
odd, but in a picture every character is a pixel, so moving one is corruption
with nothing gained.

`Tools/TerminalProbes/rtl_image_card.py` draws a gradient whose flat run of one
repeated glyph grows along the LEFT edge row by row, so the reading needs no
Hebrew — reversal moves that block to the right, against an ASCII control
drawing the same picture. Read on Apple Terminal:

| Block | Apple Terminal |
|---|---|
| `control` (ASCII ramp) | flat run on the left — this is the picture |
| `hebrew` | flat run on the **right** — mirrored |
| `coloured` (an SGR per cell) | mirrored, identically — the colour changes make no difference |
| `lrm` (U+200E after each cell) | flat run back on the **left**, and every `X` still in one column |
| `positioned` (`ESC[nG` per cell) | mirrored, identical to `hebrew` |

Two of those are settled and one is not:

- **The host reorders what it has STORED, not what it is handed.** Cursor-
  addressing every cell changes nothing, so `FrameDiffWriter`'s span machinery
  was never going to be the answer.
- **It is not the finished line's SGR structure**, since a colour change per
  cell leaves the result identical.
- **U+200E is NOT (yet) the fix, whatever that table says.** Emitting it from
  `ASCIIConverter` for every RTL glyph was tried (171c39c4) and REVERTED
  (this commit): in the Example's Image page it does not merely fail to help,
  it destroys the page — the controls panel is drawn tens of columns left of
  where it belongs and the right of the screen goes unpainted.

**What the card's `lrm` block does not cover, and what the real render adds.**
The card's rows are plain text, about forty cells wide, and stand alone. An
image row is full width, carries a foreground change per cell, and sits inside a
composed layout with a panel beside it. Somewhere in that difference the mark
stops being free. It is not TUI's arithmetic: captured from the running app
with `TERM_PROGRAM=Apple_Terminal`, every emitted row is exactly the terminal's
width in cells with the marks costing nothing, no cursor compensation fires, no
right-edge repaint fires, and `strippedLength`, `ansiAwarePrefix` and
`ansiAwareSlice` all measure a marked row as its cell count and not its scalar
count.

The card now has two more blocks — `lrm+coloured` and `lrm+wide` — which are
exactly the two axes the working block lacked. Until those are read, the mark
is not emitted.

**The first version of the probe measured nothing, and why is the useful part.**
It drew a staircase out of ONE repeated Hebrew letter and blanks. A run of
identical characters looks exactly the same reversed, and the blanks are
neutrals which at end-of-line take the paragraph's own direction and do not
move — so a host doing precisely what is suspected drew that card correctly, and
Apple Terminal did. **A card about ordering has to be made of things that can be
told apart** — and, this round's lesson, a card about a rendered PAGE has to be
made of rows like the page's.

That leaves **a known divergence on Apple Terminal in the other direction**: it
paints U+202D and U+202C as a box that occupies a cell TUI no longer counts.
Only those two were measured there; the rest of the family was not tested
individually, and the box strongly suggests the host treats none of them as
default-ignorable. Zero is still the right number for three hosts out of four
and for the standard, and TUI emits none of these controls itself — this can
only arrive in content the user pastes.

## Complex scripts — 38 corpus rows: the advance measured on five hosts, the paint on Apple Terminal

Added to the corpus 2026-09-04. **Their ADVANCE is measured** — the DSR
column, which governs wrapping (see "What the hosts advance", below):

- on both screens of every host, on 2026-10-19: Ghostty 1.3.1 with mode 2027
  set (`Tools/TerminalProbes/data/ghostty-1.3.1-advance.json` and
  `ghostty-1.3.1-alternate.json`), Apple Terminal 455.1
  (`apple-terminal-455.1-alternate.json`; its primary screen matched
  `Apple-Terminal-advance.json` row for row), iTerm2 3.7.6
  (`iterm2-3.7.6-advance.json`, `iterm2-3.7.6-alternate.json`), Warp
  v0.2026.09.30 (`warpterminal-v0.2026.09.30.08.29.stable_01-advance.json` and
  `-alternate.json`) and tmux 3.7c's own grid (`tmux-3.7c-advance.json`,
  `tmux-3.7c-alternate.json`). On each of the four native hosts the two
  screens agreed on all 38 rows; tmux's did too;
- on the primary screen of Apple Terminal 455.1, iTerm2 3.6.11, Ghostty 1.3.1
  and Warp v0.2026.09.02, on 2026-09-04. The `advance_probe.py` run that
  measured the chrome glyphs that afternoon carried these rows too, and its
  records (`Apple-Terminal-advance.json`, `iTerm2-advance.json`,
  `Warp-advance.json`, and Ghostty's, which the 2026-10-19 run reproduced row
  for row and replaced) were committed. This section had been written that
  morning, and was not updated with them until 2026-10-19.

**Their PAINT is measured on Apple Terminal alone** (2026-10-25, below: it
cannot be aligned from the application), and on no other host. Landing and ink come from
`landing_probe.py`, and every row is still listed in
`TerminalLedgerConformanceTests.awaitingLandingMeasurement`, which is what stops
"no landing record has it" from reading as "the models pass". Also unmeasured:
Ghostty with mode 2027 reset, and kitty and xterm (VTE measured 2026-10-23, zero divergences).

### Why they exist

Until this date the corpus was emoji, flags, selectors and Plane-16 PUA: 78 rows
whose most complicated member was a four-person ZWJ family. That is not the
whole of what a terminal is handed, and it left one question with no sample able
to ask it.

`Character.terminalWidth` has two rules that answer for the same scalars. The
**cluster** rule (`String+TerminalWidth.swift`) answers a flat **2** for any
multi-scalar cluster carrying a scalar that adds width. The **per-scalar** rule
(`Unicode.Scalar.loneTerminalWidth`) prices each scalar and sums: a combining
mark 0, a consonant or a spacing matra 1. For every cluster in the old corpus
the two coincide, because an emoji sequence has exactly two advancing scalars —
a base and a modifier, or a base and a joined base — and 1 + 1 = 2.

Unicode 15.1's rule GB9c broke the coincidence. Swift 6.2 implements it, so a
Devanagari conjunct is ONE grapheme cluster however many consonants it stacks:

| Cluster | Scalars | Cluster rule | Per-scalar rule |
|---|---|---|---|
| क्ष | U+0915 U+094D U+0937 | 2 | 2 — agree |
| स्त्र | U+0938 U+094D U+0924 U+094D U+0930 | 2 | **3** |
| ष्ट्र | U+0937 U+094D U+091F U+094D U+0930 | 2 | **3** |
| स्त्री | U+0938 U+094D U+0924 U+094D U+0930 U+0940 | 2 | **4** |

The framework therefore contains two answers for the same text, and which one
you get depends only on whether the standard library fused it — nothing about
the host. `ComplexScriptWidthTests` records both numbers for every new row and
wraps the disagreements in `withKnownIssue`, so they are visible in every test
run and neither answer can quietly become the other. Since 2026-10-19 the
CLAIM is the host's (below), and `ComplexScriptHostAdvanceTests` asserts it
against each host's own records for every one of the 38 rows, on every screen
they hold — and that Ghostty's were taken with mode 2027 set.

**Five of the 38 rows disagree, and not all in the same direction.** Asking
every new row rather than only the Indic ones turned up a second divergence
pointing the other way:

| Row | Cluster rule | Per-scalar rule | Which is suspect |
|---|---|---|---|
| स्त्र `conjunct_deva_stra` | 2 | 3 | the cluster rule's 2 |
| ष्ट्र `conjunct_deva_shtra` | 2 | 3 | the cluster rule's 2 |
| स्त्री `conjunct_deva_stri` | 2 | 4 | the cluster rule's 2 |
| U+1112 U+1161 U+11AB `hangul_jamo_lvt` | 2 | 4 | the per-scalar rule's 4 |
| U+1112 U+1161 `hangul_jamo_lv` | 2 | 3 | the per-scalar rule's 3 |

한 is two cells however it is spelled, so the cluster rule is right about the
jamo and the per-scalar rule is wrong: it prices the conjoining V and T jamo at
one cell each, where `wcwidth` gives the whole U+1160…U+11FF range zero. That
is why "make one rule call the other" is not the fix for either half.

Both rows are pinned rather than repaired, because what a host does with a
lone jamo is unmeasured. A syllable spelled as jamo is claimed 2 on every host
— the cluster rule's number where graphemes are clustered, and on a host that
advances per code point the sum with its vowel and trailing jamo priced zero —
which every current host advances (below); the per-scalar 1 is only reachable
for a **lone** V or T jamo — orphaned text, not a spelling of a syllable — and
no terminal has been asked what it advances one by. Correcting it to
`wcwidth`'s zero would be a change nothing here measured, in a file whose
per-scalar answers are otherwise derived from measurements.

### What the hosts advance

DSR, from the records named above: every column is both screens, measured on
2026-10-19, and each host's two screens agreed on every row. Ghostty's was
taken with mode 2027 set; tmux's is its own grid, which is client-independent.
**Bold** is an advance that differs from that host's claim, which since
2026-10-19 is the cluster rule's number on Ghostty and tmux and the
per-code-point sum on Apple Terminal, iTerm2 and Warp (below) — so the
conjuncts' 3 and 4 there are the claim now, and only tmux's are bold.

| Row | Cluster rule | Per-scalar rule | Ghostty 1.3.1 | Apple Terminal 455.1 | iTerm2 3.7.6 | Warp v0.2026.09.30 | tmux 3.7c | GNOME Terminal 3.56.2 |
|---|---|---|---|---|---|---|---|---|
| स्त्र `conjunct_deva_stra` | 2 | 3 | 2 | 3 | 3 | 3 | **3** | 3 |
| ष्ट्र `conjunct_deva_shtra` | 2 | 3 | 2 | 3 | 3 | 3 | **3** | 3 |
| स्त्री `conjunct_deva_stri` | 2 | 4 | 2 | 4 | 4 | 4 | **3** | 4 |
| `hangul_jamo_lvt` | 2 | 4 | 2 | 2 | 2 | 2 | 2 | 2 |
| `hangul_jamo_lv` | 2 | 3 | 2 | 2 | 2 | 2 | 2 | 2 |
| कि को कौ किं `matra_deva_*`, កា `matra_khmer_aa` | 2 | 2 | 2 | 2 | 2 | 2 | **1** | 2 |
| ரா `matra_tamil_aa` | 2 | 2 | 2 | 2 | 2 | **1** | **1** | 2 |
| ന്‍ `chillu_malayalam_zwj` | 1 | 1 | 1 | **2** | 1 | 1 | 1 | 1 |
| a‍ `latin_zwj`, a‌ `latin_zwnj` | 1 | 1 | 1 | **2** | 1 | 1 | 1 | 1 |
| LRM `bidi_lrm`, RLM `bidi_rlm` | 0 | 0 | 0 | **1** | 0 | 0 | 0 | 0 |
| the other 22 rows | — | — | the claim | the claim | the claim | the claim | the claim | the claim |

- **Ghostty with mode 2027 set advances the claim on all 38 rows, on both
  screens**, and gave the same numbers on the primary screen on 2026-09-04. On
  the one host measured that clusters graphemes, the cluster rule is right
  about all five rows where the two rules disagree — the three conjuncts
  included.
- **Apple Terminal, iTerm2 and Warp advance per code point**: each consonant
  and each spacing vowel sign a cell, a virama none — the per-scalar number for
  every conjunct, on both screens. Until 2026-10-19 the claim was a cell
  short for स्त्र and ष्ट्र and two for स्त्री on each of them. Their primary
  screens gave the same on 2026-09-04 (Apple Terminal 455.1, iTerm2 3.6.11,
  Warp v0.2026.09.02), and iTerm2 3.7.4 the same again on 2026-10-13.
- **Every current host advances the jamo 2**, the cluster rule's number: a
  host that advances per code point gives the conjoining vowel and trailing
  jamo no cell, which is `wcwidth`'s answer for U+1160…U+11FF. iTerm2 3.6.11
  was the exception, at the per-scalar 3 and 4 on its primary screen on
  2026-09-04; 3.7.4 (primary, 2026-10-13) and 3.7.6 (both screens) advance 2,
  so that column was its version's.
- **tmux advances per code point by a table of its own**, which gives every
  spacing vowel sign (`Mc`) no cell: the six matra rows are 1, and स्त्री is 3,
  its ी adding nothing. Measured on tmux 3.7c built from Homebrew on macOS;
  a tmux built against another width table may differ.
- Warp gives the Tamil vowel sign ா U+0BBE no cell (ரா is 1) while giving the
  Devanagari ी U+0940 one.
- Apple Terminal advances a ZWJ, a ZWNJ, an LRM and an RLM a cell each, where
  the claim counts none. Two other format characters, the bidi overrides, were
  seen drawn there as a box (see "Right-to-left text").

**The claim follows the host — since 2026-10-19, from the advance alone.**
This section once predicted 3 for a host that advances per code point and 1
for one that clusters graphemes (DEC mode 2027), each differing from 2 in its
own direction. The first half held; the second did not: Ghostty with mode 2027
set advances 2, the cluster rule's number. So the right answer is the host's,
as it is for emoji, and it is a per-host trait:
`TerminalWidthTraits.textClusters`. `.clustered` keeps the cluster rule —
Ghostty, which TUI runs with mode 2027 set, tmux (below) and every
unidentified host. `.perCodePoint` — Apple Terminal, iTerm2 and Warp — claims a
multi-scalar cluster of TEXT as its scalars' sum by the per-scalar rule, with a
conjoining vowel or trailing jamo after the first scalar priced zero: स्त्र 3,
ष्ट्र 3, स्त्री 4, 한 as jamo 2, every other row's claim unchanged. Emoji
clusters never take that sum; they have measured rules of their own.

The claim is what the layout allocates and what the writer counts, so a border
after the cluster now lands where those hosts' cursors put it — and nothing
needs compensating, because the per-host advance models report the claim for
these clusters and so agree with it. `ComplexScriptBorderTests` draws a
bordered row of the five and advances it by each host's MEASURED numbers, not
the model's.

**What this rests on is the advance alone.** The paint — where the glyph's ink
lands inside the cells it advances — is unmeasured on every host but Apple
Terminal (above, where it cannot be aligned), and every row stays in
`awaitingLandingMeasurement`. If a host drew स्त्र in two cells while
advancing three, the row would now be aligned with a blank cell inside the
cluster, which is the trade TUI already takes for SF Symbols on Ghostty;
`landing_probe.py` would say. Also unmeasured: the advance on Ghostty with mode
2027 reset and on kitty, xterm and VTE.

**tmux keeps the cluster rule**, although it advances per code point: its table
gives a spacing vowel sign no cell, so the per-code-point claim would put
स्त्री at 4 against tmux's 3, and the six matra rows, which tmux advances 1,
are claimed 2 under either. A pricing of tmux's own — per code point, spacing marks zero — matches
all 38 of its rows; it waits on a tmux built against another width table being
measured, since the one measured is Homebrew's on macOS.

### What Apple Terminal paints — measured 2026-10-25, and nothing repairs it

Found by the README's Unicode clip, filmed in Apple Terminal 455.1 (profile
Basic, SF Mono 11, macOS 15.7): its Hindi row's second column and the table's
right border were drawn about two cells left of the other rows'. The advance
was right — हिन्दी advances 5 and नमस्ते दुनिया 10, the per-code-point claim —
so the error is in the paint, which `landing_probe.py` then measured, over the
38 corpus rows and a 103-row Devanagari battery (every common matra on four
consonants, with anusvara, chandrabindu and visarga, sixteen conjuncts and
seven words), each page captured with `screencapture -l` of the window
(`Tools/TerminalProbes/data/apple-terminal-455.1-complex-script-paint.json`).

**Apple Terminal draws text it shapes at the font's own proportional advance,
and everything after it on the row — absolutely addressed text included — is
drawn that much left of its cell.** The emoji half of this was already known
(the table at the top of the Apple Terminal section); these scripts are the
rest of it. In Devanagari roughly one cell is lost per non-spacing mark
(ु ू ृ े ै ं ँ, and the virama of a conjunct), so कु, के and कं advance 1 and
draw their follower ON the consonant, स्ते advances 2 and draws it on the
cluster's first cell, and spacing matras (ा ि ी ो ौ ः) lose nothing. The
rule has exceptions that only shaping explains — कां, निं, र्क and क़ lose
nothing, किं and मिं lose one — and the loss is FRACTIONAL: a follower after
नमस्ते was drawn at column 17.5, after संस्कृत at 16.43. Thai and Lao tone
marks, Khmer's coeng and Latin with stacked marks (e◌́◌̈◌̧) lose a cell the same
way. Apple Terminal also dropped a glyph outright: संस्कृत drew no त.

`reanchor_card.py` asked what puts the row back on the grid, aiming a marker
at column 20 after हिन्दी (drawn at 19): `CHA`, `CUP`, `CR` then `CHA`, `EL`
then `CHA`, two tabs, a space in another colour, U+3000, a box-drawing glyph,
and the text on a background of its own — **none**, every one drawn at 19.
The store surgery that repairs flags (`CUB DCH CUF`, the surplus columns
deleted) lands the follower true and **destroys the text**: न्दी lost its ी,
स्ते was not drawn at all.

**Flags on 455.1 (same session).** The surgery no longer leaves a flag
composed either: 🇯🇵 after `CUB DCH CUF` drew as a boxed **J**, and the bare
pair drew the flag and moved the rest of its row one cell left (the store
defect the surgery was for, 2026-08-27). So on Apple Terminal TUI now sends a
flag pair as the **country code** its regional indicators spell, `JP` in the
same two cells (owner, 2026-10-25: convey the information, crudely, rather
than a box or a shifted row). Keycaps keep the surgery; whether 455.1 still
composes them after it is unmeasured.

Warp, filmed in the same clip (the build on this machine, 2026-10-25), draws a
flag pair as its two regional-indicator letters, each in a box, on its claim.
TUI sends Warp the plain letters too (`withWarpCursorCompensation`), which read
the same and draw cleanly.

So **TUI does not align these scripts on Apple Terminal**, and documents
it rather than degrading the text: the displacement is the font's, fractional,
and depends on what follows on the row, so no claim, compensation or cursor
move can match it, and the one edit of the row store that moves the paint
deletes glyphs (owner, 2026-10-25). Text after such a run on the same row —
a table's next column, a border — is drawn up to a few cells left. In the
same clip iTerm2 3.7 and Ghostty 1.3.1 drew the Hindi row on its claim; their
paint over the battery, and Warp's, is not measured.

The rows stay in `TerminalLedgerConformanceTests.awaitingLandingMeasurement`:
that ledger holds one whole-cell landing per row, and a displacement that
moves with what follows is not one number. The record above keeps the
analyser's rounded readings for reference.

### What the 38 rows cover

- **`indic_conjunct`** — Devanagari क्ष स्त्र ष्ट्र स्त्री, Bengali ক্ষ, Telugu క్ష.
  The GB9c fusions, at two, three and four advancing scalars.
- **`virama_final`** — Tamil ஸ், Kannada ಕ್, Khmer ក្. GB9c's `InCB=Linker` set
  is six scripts, and these three are not in it: க்ஷ, ಕ್ಷ and ក្ក are each **two**
  grapheme clusters, so the half-form is the whole cluster and a shear would be
  per half rather than per conjunct.
- **`spacing_vowel_sign`** — कि को कौ किं ரா កា. `Mc` marks, which the per-scalar
  rule says advance and the cluster rule prices at 2.
- **`nukta`** — क़ ड़. A non-advancing `Mn` that changes the glyph.
- **`chillu`** — ൻ atomic against ന്‍ spelled with a ZWJ: the same Malayalam
  letter reaching two different code paths, the second of them the one shaped
  for emoji.
- **`thai_lao`** — ก่ กิ้ กำ ກີ່. Stacked marks, plus sara am, which is a
  *spacing* vowel.
- **`tibetan_stack`** — ཀྐ ཀྐུ. A vertical stack of three scalars in one cell.
- **`arabic`** — the lam-alef ligature as its presentation form U+FEFB, بَ, بَّ.
  (The لا a keyboard produces is U+0644 U+0627: two letters, two clusters, so
  the corpus cannot hold a row for it — shaping is the renderer's business.)
- **`hebrew_points`** — בִ, בָּ. Marks inside a right-to-left run.
- **`hangul_jamo`** — U+1112 U+1161 U+11AB and U+1112 U+1161: 한 as conjoining
  jamo rather than the precomposed U+D55C already in the corpus.
- **`format_control`** — a‍ a‌ (letter + ZWJ / ZWNJ, which is what pasted Indic
  or Arabic text and a truncated emoji both leave), and LRM/RLM alone.
- Plus **Ａ** (fullwidth Latin) in `cjk` and **e◌́◌̈◌̧** (three stacked NFD marks)
  in `combining`.

### Measure them

The DSR half needs no display, no screenshot and no Screen Recording grant —
`advance_probe.py` carries all 38 under the same ids as the corpus. It has run
on Ghostty on both screens and on the other three on the primary screen
(above); their alternate screen is owed:

```sh
cd Tools/TerminalProbes
PROBE_ALT=1 PROBE_OUT=data/<terminal>-<version>-alternate.json python3 advance_probe.py
```

The full four facts — advance, landing, ink, reserve — come from the landing
pair, which reads `data/width-corpus.json` and so already carries every row:

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
python3 landing_analyze.py /tmp/landing.json \
    -o data/<terminal>-<version>-alternate-landing.json
```

Run both inside each of the four hosts this document records, then delete the
measured ids from `awaitingLandingMeasurement`. Read `advance` before believing
anything: it is the internal column, which governs wrapping, and on Apple
Terminal it has disagreed with the paint by nine cells.
