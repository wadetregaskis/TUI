# Conjunct widths on hosts that don't compose: decisions from lane WIDTHS

*Lane WIDTHS, 2026-10-19. A Devanagari conjunct is one grapheme cluster, and
TUIkit claimed two cells for it on every host — the cluster rule's number —
while Apple Terminal, iTerm2 and Warp advance it per code point: स्त्र and
ष्ट्र 3, स्त्री 4. Every cell after one on a row was placed a cell or two left
of where those hosts draw it. The evidence is the DSR advance records in
`Tools/TerminalProbes/data/`, taken on both screens of five hosts on
2026-10-19; the tables and the reasoning are in
`Documentation/Terminals/Terminal compatibility survey.md`, "Complex scripts".
The format is that of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-WIDTHS-n — needs your decision.** Nothing has shipped for these.
- **B-WIDTHS-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-WIDTHS-n — declined.** With the reason.

No SwiftUI API is involved. SwiftUI lays text out by the font's glyph advance;
TUIkit lays it out by the cells the terminal advances, and this lane only makes
that number right on more hosts, so it adds no deliberate deviation.

## B. Shipped the safe option

### B-WIDTHS-1. A cluster of text claims what its host advances — decided by the advance alone

*`TerminalWidthTraits.textClusters` (`.clustered`, `.perCodePoint`),
`TerminalClient.widthTraits(of:)`, `TerminalQuirks.advancesTextPerCodePoint`*

What shipped: a per-host trait beside the ZWJ, skin-tone and chrome-overhang
ones, read by `Character.terminalWidth` where a multi-scalar cluster carries
width-adding extras and is not an emoji sequence.

| Host | `textClusters` | स्त्र ष्ट्र स्त्री | 한 as jamo |
|---|---|---|---|
| Ghostty (mode 2027 set, as TUIkit runs it) | `.clustered` | 2 2 2 | 2 |
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
blank cell inside the cluster — the trade TUIkit already takes for SF Symbols
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

## A. Needs your decision

### A-WIDTHS-1. What does an unidentified host claim for a conjunct?

Today: `.clustered`, the cluster rule — the same "assume it renders correctly"
reasoning every other unidentified-host claim follows, and right for a host
that clusters graphemes. But of the five hosts measured, four advance per code
point, and the terminals TUIkit cannot identify (xterm, VTE, Alacritty, kitty
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

## Owed, outside this lane

Found by the same probe runs and recorded in the survey, not acted on:

- **iTerm2 3.7.6 no longer detaches BMP-base skin tones** on the alternate
  screen: ✊🏻 advances 2 (3.6.11: 4), ☝🏽 2 (3), 🏋🏽 2 (1). The traits still
  claim the detached widths, so on 3.7.6 such a row ends short by the
  difference, if the DSR is the whole story. Needs the tone card or a landing
  run on 3.7.6, and probably a version-aware iTerm2 model — the first host
  whose model would follow its version. (Survey: "iTerm2 3.7.6 re-measured".)
- **Warp v0.2026.09.30 stopped over-advancing** keycaps and 〰️ 〽️ on the
  alternate screen (3 → 2), and a raw ZWJ sequence's joiner no longer takes a
  column. Nothing TUIkit emits changes, but the landing record behind
  `knownAdvanceDivergences` is v0.2026.08.26's; a landing re-run would say
  whether those seven divergences are gone. (Survey: "Warp v0.2026.09.30
  re-measured".)
- Apple Terminal advances ZWJ, ZWNJ, LRM and RLM a cell each, and Warp gives
  ரா's U+0BBE no cell — pinned as known divergences in
  `ComplexScriptHostAdvanceTests`, unmodelled.
