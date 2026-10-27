# Grapheme widths on hosts that do not compose

*How many cells a cluster of text takes, when the terminal decides: a
Devanagari conjunct is one grapheme cluster, and some hosts advance it per
code point. Ids: B-WIDTHS-1 and 2, A-WIDTHS-1; the emoji rendering notes of
July 2026, appended.*

## In short

A cluster claims what its host advances, decided by the advance alone; tmux
keeps the cluster rule. What an unidentified host claims (A-WIDTHS-1) was
listed for the owner on 2026-10-18 and never answered (recommended: the
cluster rule for now, then measure xterm and VTE with `advance_probe.py`).

## How it unfolded

1. **July 2026:** emoji rendering bugs in macOS Sequoia's Terminal.app were
   written up (appended), the start of measuring what each host draws.
2. **2026-10-19, lane WIDTHS:** TUI claimed two cells for a conjunct on every
   host while Apple Terminal, iTerm2 and Warp advance it per code point; the
   claim now follows the host. A compiler bug found on the way (a `Character`
   literal rejecting a GB9c conjunct) is on the Desktop for the owner to file.

## The record

### B-WIDTHS-1. A cluster of text claims what its host advances — decided by the advance alone

*`TerminalWidthTraits.textClusters` (`.clustered`, `.perCodePoint`),
`TerminalClient.widthTraits(of:)`, `TerminalQuirks.advancesTextPerCodePoint`*

What shipped: a per-host trait beside the ZWJ, skin-tone and chrome-overhang
ones, read by `Character.terminalWidth` where a multi-scalar cluster carries
width-adding extras and is not an emoji sequence.

| Host | `textClusters` | स्त्र ष्ट्र स्त्री | 한 as jamo |
|---|---|---|---|
| Ghostty (mode 2027 set, as TUI runs it) | `.clustered` | 2 2 2 | 2 |
| Apple Terminal, iTerm2, Warp | `.perCodePoint` | 3 3 4 | 2 |
| tmux, unidentified | `.clustered` | 2 2 2 | 2 |

`.perCodePoint` claims the cluster's scalars' sum by the per-scalar rule
(`Unicode.Scalar.loneTerminalWidth`), with one exception that the records
demand: a conjoining vowel or trailing jamo after the cluster's first scalar
adds nothing, because every current host gives it no cell. Of the 38
complex-script rows only the three conjuncts change claim; an emoji cluster
never takes the sum (a test flips the trait on every host and checks every
other corpus row is unchanged). The claim is what the layout allocates and
what the writer counts, and the per-host advance models report the claim for
these clusters, so they agree with it under each host's traits and nothing is
compensated. The quirk explorer (`TerminalClientQuirks`) has a switch for it,
and lists the conjunct rows among the contentious ones — a host can now
disagree by its claim as well as its advance — so an unmeasured terminal can
be tried both ways.

**The advance decides the layout; the paint is unverified.** DSR says where
the next character goes and when the row wraps. Where the host draws the
conjunct's ink inside the three cells it advances is measured on no host —
`landing_probe.py` needs screenshots — and all 38 rows stay listed in
`TerminalLedgerConformanceTests.awaitingLandingMeasurement`, so a claim that
matches the advance cannot read as a row known to render right. If a host
draws स्त्र in two cells and advances three, the row is now aligned with a
blank cell inside the cluster — the trade TUI already takes for SF Symbols
on Ghostty — where before it was sheared.

Tests: `ComplexScriptHostAdvanceTests` asserts each host's claim for all 38
rows against that host's records on every screen they hold, with the
divergences nothing models listed (Apple Terminal's format characters, Warp's
ரா, tmux below); `ComplexScriptBorderTests` lays out a bordered row of the five
disagreement rows under each host's traits, emits it through the host's walk
and advances it by the host's MEASURED numbers, and finds the border where the
layout put it. Both fail with the hosts' traits set back to `.clustered`.

**What it costs: unmeasured, and an A/B is owed.** The claim for a cluster of
text with an advancing extra — nearly every Indic syllable carrying a matra or
a conjunct, and Thai's sara am, Khmer and Myanmar clusters — now reads the
task-local traits on every host, where it used to answer after one scan of its
scalars. On Apple Terminal, iTerm2 and Warp it also makes standard-library
property lookups the cluster rule never made: three for कि, six for स्त्र.
An emoji cluster whose decomposition the traits decline (on iTerm2, a ZWJ
sequence or a toned SMP base) pays one lookup more there; Latin text, flags
and every other emoji pay nothing new. The measure memos hide this on a
settled view, and every re-measure of such text pays it. The harness cannot run the A/B yet: no Stress
scenario carries Indic text (a `textwall` variant of synthesised Devanagari
would), and a headless `--bench` never applies a host's traits, so it would
time only the clustered hosts' share — the per-code-point arm needs a way to
pin a host's traits there. If the A/B shows a cost, two exact remedies are
ready: no scalar in U+00AF…U+203B is `Emoji`, so a range test answers the
first scalar's lookup for every one of those scripts' bases; and no scalar
below U+231A is `Emoji_Presentation`, so `loneTerminalWidth` could skip its
lookup for all of them — a change to every path, so it would need its own
measurement.

**The fuller version:** the paint, measured — `landing_probe.py` and
`landing_analyze.py` run in each host (Screen Recording, or a person reading
the shots), then the rows taken out of `awaitingLandingMeasurement`. About half
a day for the four native hosts. Until then a model with a raw-truth arm for
these clusters (as Apple Terminal's has for ZWJ) would add nothing: it differs
from the claim only under traits no host publishes, and the output walks'
byte gate never admits Devanagari or Hangul anyway.

### B-WIDTHS-2. tmux keeps the cluster rule

tmux 3.7c advances per code point too (both screens, its own grid), but by a
table that gives a spacing vowel sign (`Mc`) no cell: कि को कौ किं ரா កា are 1,
स्त्र and ष्ट्र 3, स्त्री 3. Under `.perCodePoint` the matras would stay wrong
(2 against 1) and स्त्री would move from a cell short to a cell long, so tmux
keeps `.clustered`: three conjunct rows a cell short and six matra rows a cell
long, recorded as known divergences rather than hidden.

**The fuller version:** a third case — per code point, spacing marks zero —
which predicts all 38 of tmux's rows. One case, one general-category lookup on
an off-hot path, tmux's traits, and the tests' divergence list emptied for
tmux: an hour. It waits on a second tmux build being measured, because tmux's
widths come from the width table it was built against (Homebrew's, on macOS,
here), and a Linux tmux on glibc's `wcwidth` may well give `Mc` a cell.

### A-WIDTHS-1. What does an unidentified host claim for a conjunct?

Today: `.clustered`, the cluster rule — the same "assume it renders correctly"
reasoning every other unidentified-host claim follows, and right for a host
that clusters graphemes. But of the five hosts measured, four advance per code
point, and the terminals TUI cannot identify (xterm, VTE, Alacritty, kitty
without its grapheme mode) are `wcwidth` terminals, which also advance per code
point — none of them measured here (kitty cannot open a window on this VM).

1. **Keep `.clustered`.** Free. Right on a grapheme-clustering host, a cell or
   two short per conjunct on a `wcwidth` one.
2. **`.perCodePoint` for unidentified hosts.** One line. Right on a `wcwidth`
   host that prices `Mc` a cell; a cell or two long per conjunct on a
   clustering host; and an unidentified host is otherwise treated as having no
   width quirks at all, which this would be the first exception to.
3. **Ask the host (DECRQM 2027) and choose by the answer.** "Set" → clustered,
   "reset" / "not recognised" → per code point, silence → option 1. The query
   machinery exists (`TerminalModeQuery`), but it is asked only of Ghostty
   because Apple Terminal prints the query's final byte — and an Apple Terminal
   reached over ssh may be unidentified. About half a day, with the ssh case
   to settle.

**Recommendation:** 1 for now, and measure xterm and VTE (and kitty where it
can run) with `advance_probe.py` before choosing between 2 and 3 — the same
"measure, then claim" order this lane followed.

### Owed, outside this lane

Found by the same probe runs and recorded in the survey, not acted on:

- **iTerm2 3.7.6 no longer detaches BMP-base skin tones** on the alternate
  screen: ✊🏻 advances 2 (3.6.11: 4), ☝🏽 2 (3), 🏋🏽 2 (1). The traits still
  claim the detached widths, so on 3.7.6 such a row ends short by the
  difference, if the DSR is the whole story. Needs the tone card or a landing
  run on 3.7.6, and probably a version-aware iTerm2 model — the first host
  whose model would follow its version. (Survey: "iTerm2 3.7.6 re-measured".)
- **Warp v0.2026.09.30 stopped over-advancing** keycaps and 〰️ 〽️ on the
  alternate screen (3 → 2), and a raw ZWJ sequence's joiner no longer takes a
  column. Nothing TUI emits changes, but the landing record behind
  `knownAdvanceDivergences` is v0.2026.08.26's; a landing re-run would say
  whether those seven divergences are gone. (Survey: "Warp v0.2026.09.30
  re-measured".)
- Apple Terminal advances ZWJ, ZWNJ, LRM and RLM a cell each, and Warp gives
  ரா's U+0BBE no cell — pinned as known divergences in
  `ComplexScriptHostAdvanceTests`, unmodelled.

## Appendix: emoji rendering bugs in macOS Sequoia's Terminal.app (2026-07)

> **Status (2026-08-28): HISTORICAL — superseded twice over.** This is the
> July 2026 investigation record. Its "shipping fix" (#18/#19: strip the
> modifier when content follows, VS-16-promote text-presentation bases) was
> retired on 2026-08-27, and its concluding claim — that Bug B admits no
> workaround which keeps both the modifier and an intact right edge — was
> **falsified**: the base+ZWNJ+modifier separation preserves the modifier
> everywhere, at the cost of one column (mid-pair after an emoji-presentation
> base, trailing after a promoted one). The current treatments, the
> three-facts-per-row model (internal / paint / store) that explains what
> this document could only catalogue, and the follow-up separator hunt are
> all in `Documentation/Terminal-compatibility.md`, which is canonical.
>
> What remains valuable here — and why the file is kept — is the
> **nineteen-approach rejection ledger**: which repairs were tried against
> Bug B, in what order, and how each failed. Approaches #3/#6/#10 (every
> CUB variant strips the modifier), #11/#12 (deferral discovers the
> row-wide LEFT shift), and #14 (DECRC counts as backward movement in
> context) are measurements that still constrain any future attempt.
> References to the "working tree" reflect the state during the
> investigation; helpers it names now live in
> `Sources/TUICore/Extensions/String+CursorCompensation.swift` and
> `String+TerminalWidth.swift`, much evolved.

This document catalogues the Terminal.app rendering quirks that TUI has
to work around in macOS 15 (Sequoia), the approaches that were tried during
the investigation in this branch (12 commits on top of `a95d7164`), and why
the bug class that affects Fitzpatrick skin-tone clusters has no clean
workaround using pure ANSI escape sequences.

The empirical statements below were verified against Terminal.app on a
Sequoia VM by a combination of frame dumping (via the `` ` `` debug
shortcut added in `f19d0b59`) and pixel-level inspection of the rendered
output.

### The bugs

Terminal.app exhibits **two distinct cursor-advance quirks** around emoji.
Both involve the glyph's *visible cell width* (1–2 cells) disagreeing with
the *number of cells Terminal.app advances its internal cursor counter*.

#### Bug A — VS-16 pictographic emoji under-advance

Any grapheme cluster of the form `<pictographic-base>` + `U+FE0F`
(emoji-presentation variation selector), where the base lies in the
`U+1F000`–`U+1FBFF` block, **paints 2 cells but advances the cursor by 1**.
Example: `🖥️` (= `U+1F5A5` `U+FE0F`).

Subsequent characters written inline land on top of the glyph's right
half. There is also a "phantom cell" left at the default terminal
background at the row's right edge if the cluster sits near it.

#### Bug B — Fitzpatrick skin-tone cluster over-advance

Any grapheme cluster of the form `<pictographic-base>` + `U+1F3FB`–`U+1F3FF`
(Fitzpatrick skin-tone modifier), where the base lies in the
`U+1F000`–`U+1FBFF` block, **paints 2 cells but advances the cursor by 4**.
Example: `🤙🏽` (= `U+1F919` `U+1F3FD`).

Worse, Bug B is *compound*:

- **B1 — Modifier-killing on backward movement.** Any backward cursor
  movement on the same row after the cluster — `CUB`, `CHA`, `CUP`,
  backspace, `DECRC` — makes Terminal.app silently strip the Fitzpatrick
  scalar and re-render the base emoji in the default ("Simpson yellow")
  tone. The strip happens regardless of what is written in between
  (a committing space, multiple frames, intervening SGRs).

- **B2 — Row-wide LEFT shift.** When the modifier is preserved (no
  backward movement), Terminal.app applies a **row-wide visual shift of
  ~2 columns to the LEFT** to every cell on the row. Bytes written at
  column N visually render at column N − 2. The rightmost 2 cells of the
  row are left at the default terminal background (typically white in
  light themes) — they fall off the right edge in the LEFT shift and
  are never painted by the line's content. This shift applies row-wide
  and survives every recovery attempt (overdraw past the edge, `CUP`
  past the edge, separate-frame writes, `DECSC`/`DECRC`).

- **B3 — Cluster-overflow wrap-to-next-row.** If the cluster's *visible*
  cells fit on the row but the cluster's *cursor advance* (4) would
  push the cursor past the terminal's right edge, Terminal.app **wraps
  the entire glyph onto the start of the next row**, corrupting that
  row's content. (B3 is what makes width 88/89/90 special — the
  cluster's last visible cell fits at the rightmost column, but the
  4-cell advance pushes the cursor past the right edge.)

### Approaches tried

Twelve commits, four working theories. The table summarises each approach,
in chronological order, and the failure mode that drove the next attempt.

| # | Commit     | Strategy                                                                                     | Modifier preserved? | Layout intact? | Verdict |
|---|------------|-----------------------------------------------------------------------------------------------|---------------------|----------------|---------|
| 1 | `f19d0b59` | Add `` ` `` shortcut that dumps the current frame to a file                                   | n/a                 | n/a            | Tooling for the investigation, not a fix |
| 2 | `96f4ad60` | Two-pass `repaintRightEdge` (erase + rewrite suffix) for VS-16 phantom cells                  | n/a (VS-16 fix)     | n/a            | Fixed Bug A's right-edge phantom cells; scaffold for Bug B work |
| 3 | `880f1086` | Detect Bug B and emit `CUB(actual − claimed)` after the cluster to rewind the cursor          | ❌ dropped           | ✅              | Backward movement → Bug B1, modifier silently stripped |
| 4 | `b4388087` | Pre-clip lines to terminal width before compensation (visible-cell budget only)               | n/a (clip path)     | partial        | Prevented over-wide wraps; didn't address Bug B3 |
| 5 | `d513c2c8` | Scope `repaintRightEdge` to rows that actually contain a quirky character                     | n/a                 | improved       | Stopped the repaint from destroying CJK glyphs at the clip boundary |
| 6 | `4398ecfc` | Drop the CUB compensation; accept the cursor over-advance, let `repaintRightEdge` fix the edge | ✅                  | ❌ (shift right) | Approach gave up alignment; subsequent inline chars shifted ~2 cells right of layout |
| 7 | `d68b3791` | Cursor-based clip: keep an over-advancer as the last visible char on the row whenever its visible cells fit | ✅                | ❌ (right border lost) | "Pretty close" per user — border dropped within 4 cells of right edge; otherwise OK |
| 8 | `25b75b93` | Drop the over-advancer entirely at the right edge (don't try to keep it)                      | ❌ dropped           | ✅              | Clean but loses the emoji; trade-off rejected |
| 9 | `ccc632db` | Always strip the Fitzpatrick scalar in cursor compensation                                    | ❌ dropped           | ✅              | Same trade-off, applied universally — rejected at the time |
| 10 | `01f17d9e` | `cluster + space + CUB(3)` — write a space to commit the cluster, then rewind                | ❌ dropped           | ✅              | Tested empirically: backward movement *after* the commit still strips the modifier |
| 11 | `ca8c0427` | Defer the cluster to end-of-line via `CHA(col) + cluster`; main pass writes a `CUF` over its cells | ✅              | ❌ (shift left)  | Modifier preserved; row-wide LEFT shift (Bug B2) discovered — `│` lands 2 cells left of corners |
| 12 | `8698eec0` | Same deferral as #11, but use real spaces as placeholder and re-emit `bgCode` before the deferred section | ✅              | ❌ (shift left)  | Cleaner bytes than #11, same visual shift |
| 13 | (working tree, abandoned) | "Bare under-advancer" theory — add `🥳` (`U+1F973`) etc. to the under-advance set with `CUF(1)` compensation | depends | ❌ | Empirical re-test showed `🥳` does *not* under-advance — direction was wrong |
| 14 | (working tree, abandoned) | DECSC/DECRC around the cluster — save cursor before any emoji is written, restore after the row is laid out, write the cluster last | ✅ (some widths) | ❌ | DECRC is backward movement on emoji rows in Terminal.app's logic — modifier was stripped in TUI context, even though isolated tests preserved it |
| 15 | (working tree, abandoned) | Absorb the over-advance by consuming subsequent skippable spaces from the input without emitting them | ✅ (some widths) | ❌ | Compressed the row by 2 cells visually → `│` ended up 2 cells *further* left, not aligned |
| 16 | (working tree, abandoned) | `+2` bump to `repaintRightEdge` CUP target on skin-tone rows                                  | ✅                  | partial         | `│` appeared at the right column in some screenshots; rightmost 2 cells still left at default bg |
| 17 | (working tree, abandoned) | Append 2 overdraw `bg`-spaces past the line's logical end on skin-tone rows                  | ✅                  | ❌               | Bytes past terminal width either wrap or clamp; right-edge cells stay at default bg |
| 18 | (superseded by #19 for text-default bases) | Combine **cursor-aware clip** (Bug B3) + **followed-by-content strip** (Bug B2)         | ✅ when last on row | ✅ for emoji-default bases; ❌ for text-default bases | Worked for emoji-default-presentation bases (🤙 ✊ 👍 etc.) — base emoji renders at the cluster's 2-cell width.  Broke for **text-default-presentation** bases (☝ ✌ ✍ ⛹ 🏋 🏌 🕴 🕵 🖐): their bare base is a 1-cell text glyph, so stripping the Fitzpatrick shrank the cluster from 2 cells to 1 and pushed every following cell on the row 1 column LEFT.  A row of 4 such clusters (the EmojiPage `BugCaseRow`) left its rightmost 4 cells at default bg. |
| 19 | **Shipping fix** (shipped) | Same as #18, plus: when the stripped base is `isEmoji && !isEmojiPresentation`, append U+FE0F (VS-16) and inject CUF(1)         | ✅ when last on row | ✅              | VS-16 promotes the base back to a 2-cell coloured-emoji glyph so the row layout is preserved.  The resulting `<base>+FE0F` cluster is a VS-16 under-advancer (Bug A) but the existing CUF(1)-after-the-cluster compensation handles that.  Also: `terminalAppCursorAdvance` now returns **3** (not 4) for text-default-base + Fitzpatrick clusters — the empirical over-advance is +2 from the 1-cell baseline, not the 4 we previously assumed.  Skin tone is still lost in the followed-by-content case; the layout never breaks. |

### Detail on selected approaches

#### CUB after the cluster (#3, #6, #10)

The naive symmetric reading of Bug B says: cursor advances 2 cells more
than it should, so emit `CUB(2)` (or `CUB(actual − claimed)`) right after
the cluster to rewind.

Doesn't work. **Any backward cursor movement after the cluster strips the
modifier** (Bug B1) — verified at every variant: bare CUB, CUB after a
committing space (#10), CUB with intervening SGR-only sequences, CUB
across separate writes/frames. The modifier dies the moment Terminal.app
sees a backward cursor command on the row.

#### Cursor-based clipping that keeps the cluster (#7)

When the cluster's visible cells fit at the right edge, accept the
over-advance — the cluster becomes the last visible character and there
is no inline content after it to be displaced. Worked at most widths;
broke at widths where the right border `│` would have been within 4
cells of the edge — the clip dropped the border too, because the
border's column was past `terminal_width − advance_overflow`.

#### Defer the cluster to end-of-line with CHA (#11, #12)

The main pass writes the line with a `CUF` (or, in #12, two real
spaces) covering the cluster's visible cells. The cluster itself is
emitted at the very end of the row as `\e[<col>G<bytes>` so it lands
where the layout reserved it *after* the rest of the row's content.

Preserved the modifier — no backward movement was needed in the
deferred path. But this is the approach that brought Bug B2 — the
row-wide LEFT shift — to light. With the cluster on the row, all
previously-painted cells visually shifted ~2 columns left, the
rightmost cells fell off the right edge, and the `│` border ended up
visually 2 columns left of the box's corners.

#### DECSC/DECRC bracketing (#14, abandoned in working tree)

The idea: save the cursor with `\e7` *before* any emoji has been
written on the row (so Terminal.app's cursor frame is still unbroken),
write the row's normal content with plain-space placeholders where the
cluster will go, and finally — after all other writes on the row are
done — restore the cursor with `\e8` and write the cluster bytes last.

Worked in isolated test scripts. In TUI's `FrameDiffWriter` context
the modifier was stripped — most likely because the longer SGR-rich
content path between the DECSC and DECRC counts as backward movement
once `\e8` fires. Inconclusive but unreliable.

#### Absorb-by-skipping (#15, abandoned in working tree)

Emit the cluster inline (no compensation escape), advance the
internal `col` counter by `actual` (4) rather than `claimed` (2), and
*consume — but do not emit* — up to `actual − claimed` cells of
subsequent plain-space input. The cells the over-advance "skipped" are
bg-painted by the row's initial `ESC[2K`, visually indistinguishable
from the spaces we dropped.

Conceptually clean and the cleanest theoretical fit — but the
empirical row-wide LEFT shift (Bug B2) made the absorbed cells
visually land *further left*, not at the layout's reserved column,
and the `│` came out 2 cells further left of the corners than #12 had
produced.

#### `+2` CUP bump + overdraw past edge (#16, #17, abandoned)

Tried to use the LEFT shift constructively: write the cluster's
trailing content 2 cells past the right edge in counter terms, and
Terminal.app's row-wide LEFT shift should pull it back to the layout
position. Both `+2` on the `repaintRightEdge` CUP target and inline
overdraw bytes appended past the line's end were tried. Results were
inconsistent — Terminal.app sometimes clamps `CUP` to `terminalWidth`,
sometimes wraps inline writes that overflow, and either way the
rightmost 2 cells stayed at the default terminal background.

#### Shipping fix (#18/#19, shipped)

Three coordinated changes that *don't* try to undo the bug, only avoid
provoking it:

1. **`ansiAwarePrefixForTerminalApp` — cursor-aware clip.** When an
   over-advancing cluster's `terminalAppCursorAdvance` would push
   Terminal.app's internal cursor past `visibleCount`, replace the
   cluster with `claimed` plain spaces. This is the only thing that
   prevents Bug B3 (cluster wraps to next row) at widths where the
   advance overflows.

2. **`withTerminalAppCursorCompensation` — followed-by-content
   strip.** When an over-advancing cluster has *any* visible
   character following it on the same input line, strip the
   Fitzpatrick scalar and emit only the base pictographic scalar(s).
   Terminal.app renders a normal 2-cell emoji with no over-advance,
   no row-wide shift, and no white phantom cells. When the cluster
   is the line's last visible character, the modifier is kept —
   nothing follows the cluster for the shift to displace.

3. **VS-16 promotion for text-default bases (#19).** Stripping the
   Fitzpatrick from a text-default base (`isEmoji &&
   !isEmojiPresentation` — ☝ ✌ ✍ ⛹ 🏋 🏌 🕴 🕵 🖐) leaves a 1-cell
   text glyph in place of what the layout reserved 2 cells for. To
   keep the row layout intact, the strip path also appends U+FE0F
   (VS-16), promoting the bare base back to a 2-cell coloured-emoji
   glyph. The resulting `<base>+FE0F` cluster is then a Bug A
   under-advancer; a `CUF(1)` is emitted right after it to compensate.
   Emoji-default bases (✊ U+270A, 🤙 U+1F919) don't need this — their
   bare base is already 2 cells.

VS-16 emoji (Bug A) continue to be handled with `CUF(claimed − actual)`
plus the existing two-pass `repaintRightEdge` for the phantom-cell
right-edge bug — those workarounds were never the problem.

### Conclusion: why Bug B can't be worked around perfectly

> **Falsified 2026-08-28** — kept as written because the reasoning shows
> exactly which premise fell: "preserving the modifier requires never
> writing anything to the row after the cluster" assumed the cluster must
> reach the terminal COMPOSED. Emitting it as base + ZWNJ + modifier — one
> rewritten grapheme the terminal never re-joins — preserves the modifier
> with an intact right edge, and no backward move is ever needed. See the
> treatment table in `Terminal-compatibility.md`.

The bug has two independent halves that pull against each other:

- **Any backward cursor movement on the row after the cluster strips
  the Fitzpatrick scalar.** This rules out every "undo the
  over-advance" approach: `CUB`, `CHA`, `CUP`, `DECRC`, and any
  technique that depends on writing the cluster first and repositioning
  afterward.

- **Keeping the modifier triggers a row-wide LEFT shift of ~2 columns
  that survives every recovery attempt.** The shift is uniform across
  the row, applies regardless of whether the cluster was written
  inline or via `CHA` to its column, and is not undone by any ANSI
  sequence — `CUP` past `terminalWidth` clamps, inline writes past
  `terminalWidth` wrap, and writes in subsequent frames land at the
  same shifted positions. The rightmost 2 cells of the row are simply
  unreachable when the cluster is present.

These two halves form a no-win: preserving the modifier requires never
writing anything to the row after the cluster, but a layout with the
cluster anywhere except at the row's end *has* content to write after
it (padding, borders, the rest of a centred string). You can have the
modifier and a corrupted right edge, or you can have an intact right
edge and a stripped modifier. The shipping fix takes the second
option in the followed-by-content case and the first in the
cluster-at-end-of-row case — that's the best ANSI-only outcome
reachable in Terminal.app on macOS 15 with the tools available today.

