# Stripes, surfaces and separators

*How a table came to stripe its rows by default, what a stripe may be at 256
and 16 colours, the distinct-surface look, separators as rule lines and then as
Kitty hairlines, and what striping cost and won back. Ids: A29, A46, A47,
A-D6L-1, A-D6L-2, B-D6L-1 to 4, A-SPF-1, B-SPF2-1, B-SPF2-2.*

## In short

Tables stripe every other row by default (A29); a stripe is the accent at 15%
over the rows' ground, and at 256 or 16 colours the nearest quiet entry that
keeps the text readable and cannot be mistaken for a selection, or none
(B-D6L-1). Stripes count across a list's sections, as macOS's do. Separators
are off under every style where they would take a whole line; on Ghostty,
`.automatic` separators are SwiftUI's default, drawn as Kitty hairlines that
take no row (A-D6L-2 option 4). The `.surface` look (no border, rows on a
lifted plane) is an opt-in prototype whose fate the owner has not decided
(A-D6L-1).

## How it unfolded

1. **2026-10-07, lane D6L** built the owner's A29, A46, A45 and A47: striped
   tables by default, the surface look as an opt-in prototype, pinned section
   headers in `List`, separators as a rule line. It asked two questions
   (A-D6L-1, A-D6L-2).
2. **2026-10-07, lanes SPF and SPF2.** The looks lane's A/B found stripes cost
   `table` +10.7% warm and +15.1% cold. SPF took it back without changing what
   is drawn, and the owner took its fuller option: a row states its cells' ink
   once per run of plain cells (A-SPF-1, built by SPF2).
3. **2026-10-18, lane LISTS** made the stripes count across a list's sections,
   as measured on macOS, and covered the separator guides' remaining shapes.
4. **2026-10-23, the owner.** A-D6L-1: "not deciding yet; keep open" (a
   reminder at the end of the queue). A-D6L-2: option 4, the hairline.
5. **2026-10-24, lane HAIRLINE** built the prototype: `.listSeparatorStyle(_:)`,
   `HairlineMarker` and `HairlineLayer`; Ghostty only, where it was measured.
   The cost was later halved (HAIRKEY, HAIRKEY2, 2026-10-26: hairlines over
   none about 15% → 7%); the owner accepted the remainder on 2026-10-25, with a
   note to revisit.

## Where it stands

Shipped as above. **Deferred by the owner:** A-D6L-1, the surface look as a
default (a reminder is owed when the queue runs out).

## For a future reader

- **The thin lines between rows with Kitty graphics** were investigated on 2026-10-08 (the summary is the last entry below).
- **At 16 colours the surface does not show** on 13 of 16 palettes, so if it
  ever becomes a default it needs the border back there (A-D6L-1).
- **Hairlines are Ghostty-only by measurement**: iTerm2 drew them in an
  unknown pixel unit (lines end short), kitty and WezTerm are unmeasured,
  Konsole hides the layer. `hairline_probe.py` and `hairline_review.py` are
  the tools; the survey is the record.
- **Hairlines are hidden, not dimmed, under a fade or a sheet's veil**, until
  the mark's colour is blended as cells are.
- **Revisit the hairlines' remaining cost** (the owner's note of 2026-10-25).

## The record

### A-D6L-1. The surface look: try it, then decide what (if anything) becomes the default

*`SurfaceTableStyle` / `.tableStyle(.surface)`, `SurfaceListStyle` /
`.listStyle(.surface)` — TUI's own, a prototype (decisions A29, A46)*

**Shipped, opt-in, no default changed:** a table or list in the `.surface`
style draws no border; its rows inset a cell from the edges, as `.inset`'s
do, on the surface a `TabView`'s body is drawn on (one plane's step off what
the collection sits on, the ladder `Palette.liftedBackground` /
`lifted(from:)` already climbs, now shared through
`EnvironmentValues.liftedSurface`). The table's header line, and a list's
title and section headers, sit a step stronger still; the table header's
titles are bold in the PRIMARY ink rather than the secondary. Every other
table row stripes over the surface (and a stripe anywhere now tints over the
surface it sits on, not the page). Selected and cursor rows keep the fills
they have today.

Where to look: the Example's **Lists** page (Styles section: `.automatic`
beside `.surface`, sectioned, scrolling) and **Tables** page (Table styles
section: `.automatic` beside `.surface`, both with selection). Text and colour
dumps of both pages, at 24-bit, 256 and 16 colours, are in the session notes
under `D6L/renders/` (`lists-*-surface` and `tables-*-surface`, `.html` for the colours, `.txt` for the cells).

What the measurements say (`CollectionSurfaceTests`, `StripeLegibilityTests`,
the sixteen stated palettes):

- **Truecolour and 256 colours:** the surface is visibly off the page on every
  palette (1.11–1.76:1), and the text stays readable on it everywhere. The
  header's second step costs too much contrast on four palettes (Silver
  Aerogel at truecolour; Red, Violet and Novel on the cube), so there the
  header sits on what the collection sits on instead — a band the rows are
  lifted from, still a tone of its own.
- **16 colours: the surface does not show.** On 13 of 16 palettes the step off
  the page quantises back to the page's own slot (the `TabView` body has the
  same limit), so a `.surface` table at 16 colours looks like `.inset`: no
  border and nothing else to tell it from the text around it.

**Options.**

1. **Keep it opt-in** (shipped). Free; `.automatic` stays bordered for both.
2. **Make `.surface`'s look the default for tables, lists or both** — what
   `.automatic` draws, keeping `.bordered` and `.inset` as named. The two
   lines of border go to the rows; click targets move a line up and a cell
   left; golden and render tests that read a list's or table's bytes are
   re-baselined (about half a day, most of it tests, as A29/A46 priced). At 16
   colours it needs a fallback: draw the border there (the surface cannot be
   seen), about an hour.
3. **Fold the surface into `.inset`** rather than keeping a TUI-only
   style: `.inset` is then "no border, on a surface", and `.surface` goes. Free
   apart from the docs; changes the look of every app that names `.inset`.

**Recommendation:** try it on the Example pages first; if it reads well, 3
then 2 for tables (whose border reads heaviest), with the 16-colour fallback.
Lists can follow, or keep the border, by the same test.

### A-D6L-2. Should a list draw separators by default?

*`View.listRowSeparator(_:edges:)` and its family; `ListStyle`'s defaults
(decisions A47)*

**Shipped:** separators as a rule line between rows, the owner's option 2 —
every modifier of the family and both guides implemented, a faint `─` line
of its own under a row, under a section's header and under its last row. A
row's `.automatic` resolves to **hidden** under every built-in style, so a
list looks as it always has until something asks for `.visible`; written on
the `List`, the modifiers are every row's or every section's.

SwiftUI's default is the other way: a macOS list draws a hairline under
every row, and under every section header, in `.automatic`, `.inset`,
`.bordered` and `.plain` — not `.sidebar` (measured, w08b's section probes).
A hairline costs a window nothing; a terminal line doubles a list of
single-line rows. With them on, the Example's Lists page styles demo shows
three entries where it showed six (renders: `D6L/renders/lists-*-separators`,
with the default beside them in `lists-*-surface`). The brief was to take
SwiftUI's default only if the Example still read well; it reads as a
different, airier list, and every list in every app would halve its rows, so
the default is left to the owner.

**Options.**

1. **Off by default** (shipped). Free.
2. **SwiftUI's default: on under `.automatic`, `.inset`, `.bordered` and
   `.plain`**, off under `.sidebar` and TUI's `.insetGrouped`. Every list
   doubles in height, every row's click target and page distance with it;
   tests that read a list's lines need re-baselining (most of a day — lists
   are everywhere in the suite).
3. **On for the inset family only** (`.inset`, `.surface`), where the rows
   have no border to tell them apart — or tied to rows of more than one line,
   where a separator costs proportionally less.

4. **Wait for the Kitty hairline:** build the TUI-only `.hairline` look,
   then take SwiftUI's default wherever the host can draw a line that takes
   no row, and stay off elsewhere.

**Recommendation:** 1 for now; try the Example's toggle (Lists page, Styles
section, "Separators between rows") and decide with A-D6L-1, since a
surface-styled list is where separators would most help.

**Owner: option 4.** **Prototype shipped 2026-10-24.**

- **The look:** `ListSeparatorStyle` and `.listSeparatorStyle(_:)`, TUI-only,
  beside SwiftUI's separator modifiers, which keep their signatures. `.line`
  is the rule line of its own; `.hairline` is a line a pixel or two thick
  along the top of the row below, which takes no row on any terminal and is
  drawn only where the terminal can draw it; `.automatic`, the default, is
  `.hairline` where the terminal draws hairlines and `.line` elsewhere.
- **What `.automatic` visibility means:** under `.line`, hidden in every
  style, as shipped. Under `.hairline`, SwiftUI's default: shown under
  `.automatic`, `.inset`, `.bordered`, `.plain` and `.surface` (TUI's own,
  an inset list, so shown as `.inset` is), hidden under `.sidebar` and
  `.insetGrouped`. Section separators likewise. A `.visible` separator is a
  hairline where they are drawn, a rule line elsewhere.
- **Which terminals:** Ghostty, where the startup handshake says it places
  pictures and the terminal reports its cell's pixel size — the one host
  measured to draw the line on the boundary (`hairline_probe.py`, Ghostty
  1.3.1). iTerm2 drew it too, but in a pixel unit no query revealed, so a line
  there ends short; kitty and WezTerm are unmeasured; Konsole hides the layer.
  `TUIKIT_HAIRLINES=1` (or `TerminalClient.hairlineSupport`) turns them on
  anywhere, `0` off (`TerminalClient.hairlinesSupported`).
- **How it is drawn:** the list marks the cells of the next row's first line
  with a private SGR parameter carrying the line's colour
  (`HairlineMarker`); the mark rides every cell stage — a scroll clip cuts
  it, an overlay replaces it — and the diff writer reads the runs off the
  finished frame and takes the mark out. `HairlineLayer` keeps what the
  terminal holds: one strip per colour, sent once and cropped per run, a
  classic placement per run (`z=+1` on Ghostty, `-1` elsewhere), and only the
  difference sent each frame; nothing at all on a frame whose lines did not
  move, and nothing ever on a host that draws none. A resize or a resumed
  suspend deletes the strips and places every line again; a suspend and a
  quit delete them.
- **Look calls made in the prototype, for the owner:** no line touches the
  focused or a selected row (a line across a highlight reads as a seam;
  macOS's own is unmeasured); no line along the top of the window's first
  row, whose row above is scrolled away; under a fade or a sheet's dimmed
  backdrop the lines are hidden, not dimmed, until the mark's colour is
  blended as the cells' are; a tint with no RGB (a palette slot the terminal
  never reported) draws no line.
- **Not covered:** `Table` (no separators to draw), Ghostty's exact crop
  unit (the probe left it OPEN: a run of n columns is cropped to
  n × (`ws_xpixel` // `ws_col`) px), a `SIGQUIT` (its farewell deletes images,
  not strips; Ghostty frees both with the alternate screen).
- **Where to look:** `python3 Tools/TerminalProbes/hairline_review.py` in
  Ghostty (`--force` in iTerm2), or the Example's Lists page.

### B-D6L-1. A stripe at 256 and 16 colours is the nearest QUIET entry, or none

*`AlternatingRowBackgroundBehavior.automatic` on a `Table` (decisions A29),
`View.alternatingRowBackgrounds(_:)`*

The stripe is the accent at 15% over the rows' ground. At truecolour that is
what is drawn (eased off a few points where the text would fall under the
floor below; on no stated palette does it need to be over the page). A
coarser terminal draws the NEAREST entry, and the first sweep of the sixteen
stated palettes showed that is not good enough for a band under every other
row: the cube drew five palettes' stripe in the selected row's own entry
(every other row reading as selected), Green's and Homebrew's as `#005f00`
on black (2.6:1 off the page, where 1.3:1 was asked for) and Red's text at
3.5:1; the sixteen slots striped Red Sands' rows red.

**Shipped:** at 256 colours the stripe is the cube or grey-ramp entry nearest
the asked-for colour among those that (1) differ from the ground's entry, (2)
are none of the five row fills (`RowFills`: S, F's two ends, B's two ends),
(3) sit nearer the ground than a selection's fill, and (4) keep the text at
4.5:1, or four fifths of what the page gives where it gives less. At 16
colours the same rule over the four grey slots only (every other slot is a
saturated hue, and the nearest by distance striped Basic in bright yellow).
Where no entry qualifies, no stripe: the rows are as readable without one.
Result: every stated palette still stripes on the cube (several in a quiet
grey rather than a tint — Green's is grey 234, not a green); at 16 colours
the dark palettes draw none.

**The fuller version:** per-palette stripe picks generated at coding time,
beside the row fills in `RowFillTable.swift` (`Tools/RowFillValues/
generate.py`), so a shipped palette's stripe can be hand-checked like its
S/F/B — about half a day with the generator's tests.

### B-D6L-2. A row's `.top` separator is the style's to decline

*`View.listRowSeparator(_:edges:)`, `View.listRowSeparatorTint(_:edges:)`
(decisions A47)*

**Shipped:** the line between two rows is the upper row's `.bottom` edge, and
only that: a row's `.top` edge is declined, which SwiftUI documents a style
may do ("The list style might already decide to not display separators for
some edges, typically the top edge"). Two rules — one per side — would be a
gap, not a line. So `.listRowSeparator(.hidden, edges: .top)` on a row leaves
the line above it to the row before it.

**The fuller version:** the line between two rows answers to BOTH sides — drawn
only where the upper row's `.bottom` and the lower row's `.top` both allow it,
tinted by whichever states a tint. It needs the next row's preference before
this row's height is known, so laying out a row would render the row after
it: about half a day, and a row's render more per window.

### B-D6L-3. Where a separator's preference is read

*`listRowSeparator` and family, the separator guides (decisions A47)*

**Shipped:** a row reports its preference as it renders, on the per-frame
collector the list already stamps rows on (`RowEditRestrictions`) — so it is
found anywhere inside the row's content, and a row carrying a separator
modifier that changes what it draws opts out of the row memo, as a
`.deleteDisabled(true)` row does. One that changes nothing — the ported
`.listRowSeparator(.hidden)` under a list that draws none — stays memoized
(`ListSeparatorChange.changesRow(over:)`; the review's round 1).
Hand-written rows, in a list and in a `Section`, are now stamped too (they
were not, so `.selectionDisabled()` on one named no row; by the same stamp it now names its own, which this lane reasoned rather than tested).
A section's preference rides `SectionInfo`. The guides are read from the
row's view and carried up through stacks, as any explicit guide is.

Not covered at first, each by construction rather than by choice, and each
covered since: a `Section` a `ForEach` makes (`ForEach(regions) { Section … }`)
draws its section separators as a hand-written one does (found so by
`ListSeparatorGapsTests` on 2026-10-18, the path having been routed through
the sections' own extraction since); a guide inside a wrapper that draws its
content unchanged — `.onTapGesture`, `.tint`, `.onAppear`, an environment
write, any `DrawsContentUnchanged` wrapper — is seen through it, as one
inside a stack or a separator modifier always was (2026-10-18, lane LISTS:
such a wrapper is its content's size, so the guide needs no translating; it
reaches a stack's alignment the same way); and a row of several views
(decisions B15) reads the guide each of its views states (2026-10-18). A
guide behind a wrapper that moves or resizes its content — a `.frame`, an
`.offset`, a `.border` — still stops there, rather than report the wrong
position (decisions B19).

The rule line is the row's own bottom line, as a separator is the row's
`.bottom` edge in SwiftUI's API: a selected or cursor row's highlight runs
under its own rule, so the highlight is the row's full height, and a click on
the rule selects the row above it, and a drag begun on it holds the row by
its last line of content — the floating copy carries no rule, and a block of
several rows grabbed there hung a line high until 2026-10-18 (census D-13,
reproduced in `ListReorderMultiRowTests`). (Whether macOS paints a selected
row's highlight over its separator is unmeasured.) A row lifted out of the list —
a drag's floating copy — leaves its rule behind; the landing slot keeps the
rule's line, so the rows below do not jump while the drag is held. **The
fuller version:** the rule drawn outside the row's fill and click band, as a
line between rows that belongs to neither — its own claims and its own
`AnimatedCellRun` exclusion for the cursor row's breath, about half a day.

### B-D6L-4. Stripes count on across a list's sections, as macOS's do

*`alternatingRowBackgrounds` on a sectioned `List` (decisions A29/A46)*

**Measured (macOS 15.8, offscreen `NSHostingView`, each row's background
sampled; [`Tools/SwiftUIProbes/List pinned headers and row stripes/phase.swift`](<../../../Tools/SwiftUIProbes/List pinned headers and row stripes/phase.swift>)):** a list's
stripes tint the second content row and every other after it — the phase
TUI now draws, for tables and lists alike — and in a sectioned list they
count the content rows across the sections, headers not counted: three rows
under A then three under B tint A's second and B's first and third.

**Shipped at first:** TUI's count restarted at each section's first row
(`ListStyle.alternatingRowColors`), so B's first row was plain.

**Shipped since 2026-10-18 (lane LISTS):** one count across the list, as
measured. The composers no longer restart it at a header, and seed it from the
rows above the window (`RowSource.contentRowIndex(at:)`) as the row's index
less the headers and footers above it — a binary search of the section chrome
the extraction already keeps, so no row is asked its type (the walk back to the
section's header it replaces asked every row above the window). Every row but
a header or a footer counts, a row the selection cannot name (`.unselectable`)
too: it is drawn as a content row is, and it used to share the stripe of the
row after it. Unmeasured for a sectioned `Table` (decisions A31), which counts
its own way and is unchanged.

### A-SPF-1. A table row's bytes: one ink introducer per row, not one per cell — shipped

*`Table`'s rows — performance only, no API*

**Owner (2026-10-07): the fuller option. Shipped:** a table row states its
cells' ink once for every run of cells whose text carries no escapes of its
own, and closes it once at the run's end (`TableRowInk`), striped or not — so
a row of plain columns opens with ONE ink introducer and closes once, where it
stated and closed the ink around every cell. The blank cells between cells
are drawn in the ink, which a blank does not show. A blank selection mark (an
unselected row's) states no colour at all. A cell with escapes of its own (a
styled `Text`, a view cell's line) still closes with a reset, which its bold
or underline needs, and the ink is stated again for the cell after it — so a
styled column costs a row one more introducer, not one per cell (the rule
applied per run of cells, not per row: decisions-SPF2 B-SPF2-1). Two rows keep
the close around every run, exactly as before: a REVERSAL (under SGR 7 a
cell's ink is the colour it is filled with, so a blank's ink shows), and a
row whose ramp varies along it (painted per cell). Only `Table`: a `List`
row's content is its own views' buffer, with no row-wide ink to state. An
ANCESTOR's reversal a row cannot see — a table nested in a `List`'s cursor row
or another table's view cell, under a palette whose highlight cannot be
measured — shows the blanks' ink: decisions-SPF2 B-SPF2-2.

What is drawn did not change, but for that. `TableRowInkTests` composes 600 random rows
(plain, empty and escaped cells, a mark or none) both ways at each depth —
truecolor, 256, 16, mono — under each paint a row is finished with (none, a
still fill, a breathing fill's frame, a dim, a dim on a fill) and compares
every column's glyph and VISIBLE state (`PaintedCell.visibleState`: a blank
cell's ink and weight are not seen unless an underline, a strike or a
reversal shows them), and the column after the row; and pins why a reversal
is the exception. Across the change, 12 tables (selection, cursor row,
stripes on and off, a bold column first and in the middle, a wrapped
multi-line table, rows refusing selection, a scrolled table with its bar, a
translucent ink and a translucent fill over text, two reversal palettes) at
the four depths, each as rendered and as resolved on screen, matched the
build before cell for cell (96 renders, 0 mismatches). No test or golden
pinned a plain row's escape bytes, so none was re-baselined; the suite passed
unchanged.

Bytes in the frame's lines, `Stress --bench` (deterministic counts), the
build before and this one, stripes on (`--stripes disabled` in brackets),
warm and cold alike; and how the rows composed cold divide — a row of plain
cells, or one with a cell of escapes of its own:

| scenario | before | after | rows composed cold |
|---|---|---|---|
| `table` | 15,992 (15,567) | 9,976 (9,687) −37.6% | 35 plain |
| `table-multiline` | 11,821 (11,475) | 9,307 (9,018) −21.3% | 12 plain |
| `table-churn` | 15,289 (14,371) | 11,529 (10,696) −24.6% | 35 with a styled cell |
| `table-churn-wrapped` | 11,015 (10,686) | 9,253 (8,964) −16.0% | 12 plain |
| `table-tail` | 13,179 (12,295) | 10,923 (10,090) −17.1% | 35 with a styled cell |
| `table-api` | 15,429 (14,511) | 11,669 (10,836) −24.4% | 35 with a styled cell |
| `truncate` | 15,562 (14,372) | 11,802 (10,697) −24.2% | 35 with a styled cell |
| `tables-scroll` | 13,124 (12,816) | 9,904 (9,666) −24.5% | 200 plain |
| `tables-vstack` | 11,658 (11,372) | 8,758 (8,537) −24.9% | 33 plain |
| `megalist` | 11,995 | 11,995 (a `List`) | — |

A striped table now draws fewer bytes than any table drew before stripes;
the stripe itself costs `table` +3.0% bytes (one fill statement per striped
row).

**Measured (2026-10-07, coordinator):** release `Stress` before (`59e04b011`)
against this change, `ab_bench.py`, 15 reps, CPU time per frame, on a quiet
machine:

| scenario | warm | cold |
|---|---|---|
| `table` | 388.7 → 301.3 µs, −23.0% | −23.2% |
| `table-churn` | −16.4% | −14.6% |
| `table-api` | −16.2% | −14.0% |
| `truncate` | −13.7% | −7.1% |
| `table-tail` | −10.6% | −10.1% |
| `table-multiline` | −7.8% | −4.9% |
| `table-churn-wrapped` | −4.1% | −1.5% |
| `tables-scroll` | indistinguishable | −11.8% |
| `tables-vstack` | indistinguishable | −5.4% |
| `megalist` (a `List`) | indistinguishable | indistinguishable |

A striped `table` now draws in less time than an unstriped one did before
stripes (378.8 µs a frame at `14d09c6a0`). On one binary, stripes on against
`--stripes disabled`, the stripe costs +1.2% to +4.6% warm.

**First shipped, before the owner's call — a row under a still fill states
the fill once.** A table row opened every cell with its ink and closed it with a reset (`ESC[0m`), and a
persistent background has to be stated again after every reset, so a striped
row of eight columns stated its stripe nine times: +160 bytes a row at
truecolor, +17.5% bytes in a static table's frame, carried up through every
container, copied and scanned for width on every frame the table is drawn. A
row under a still fill (a stripe, a selected row's tint) now closes its runs
with SGR 39 — the terminal's ink again, the fill left in force — so the paint
states the fill once (`inkClose(under:)` then, `TableRowInk` now). Every cell is the cell it was
(`stripeStatedOnce` compares every cell's SGR state with the unstriped row's
under the stripe); a cell whose text carries escapes of its own keeps its
reset, and the stripe is stated again after it. Rows with no fill are
unchanged, byte for byte: under `--stripes disabled` the frames of six table
scenarios match the build before stripes.

Counted on `Stress --bench`, one build, `--stripes disabled` against stripes on
(deterministic counts, not timings), bytes in the frame's lines, warm:

| scenario | before | after |
|---|---|---|
| `table` | +17.5% (15,567 → 18,287) | +2.7% (→ 15,992) |
| `truncate` | +18.9% | +8.3% (a styled column restates) |
| `table-churn` | +17.0% | +6.4% |
| `table-tail` | +15.5% | +7.2% |
| `table-multiline` | +12.7% | +3.0% |
| `tables-scroll` | +12.2% | +2.4% |

**The fuller option (as proposed; shipped above):** every row, striped or
not, opens with ONE ink introducer and closes once at its end, wherever no cell carries escapes of its
own (every column but a view or a styled `Text` draws plain text): the spacing
between cells is then drawn in the ink, which a space does not show. An
eight-column row sheds about 150 bytes of escapes (207 → about 45 at
truecolor), striped or not — fewer bytes than any table drew before stripes.

**Its price (as proposed):** every table row's bytes change — not what is drawn: the same
glyphs in the same colours on the same fields — so every test and golden that
pins a plain row's escapes is rewritten, and the spacing cells' SGR state
carries the ink, which a cell-by-cell comparison sees though the screen does
not. Unmeasured in time.

### B-SPF2-1. A row with a styled cell shares the ink among its plain cells too

*`Table`'s rows — performance only, no API*

A-SPF-1 put the rule as "one ink introducer per row, wherever no cell carries
escapes of its own", and the lane's brief as "keep the per-cell path for rows
whose cells carry escapes of their own". Read per ROW, a row with one styled
cell — a bold `Text` column, a view cell — would keep stating and closing the
ink around every cell.

**Shipped: the rule per RUN of cells.** A cell with escapes of its own is
closed with a reset, as before (its bold or underline needs it), and the ink
is stated again for the next plain cell; the plain cells on either side of it
share one introducer as in any other row. A row with a bold middle column
states the ink twice, not once per cell.

Both readings draw the same picture — the safety criterion here, since the
bytes are the only thing either changes. `TableRowInkTests` composes random
rows that mix plain, empty and escaped cells (a reset-closed bold, an
underline closed with SGR 24, an italic left running, an ink of the cell's
own) and checks every column's visible state against the per-cell spelling at
four depths under five paints; the change's capture matched the build before
cell for cell for a bold column first and in the middle. So the choice was on
cost alone, and the run is the cheaper one: it is the per-cell scan the row
already makes as it writes each cell, where the per-row reading needs a scan
of every cell BEFORE the row is composed.

**The per-row reading, and its price:** a second walk over every cell's bytes
per composed row, and no saving at all on a table with a styled column —
`truncate`, `table-churn`, `table-tail` and `table-api` would keep their bytes
(every one of their rows has a styled cell: 35 of 35 composed cold), where the
run takes them down 17–24% (`truncate` 15,562 → 11,802 bytes a frame).

### B-SPF2-2. A table nested in a reversed row shows its shared ink in the blanks between its cells

*`Table` rows drawn inside a `List` row or another table's view cell — drawing, no API*

A-SPF-1 rests on a blank cell showing no ink. Reverse video is the exception:
under SGR 7 a cell is FILLED with its ink. A table row's own reversal keeps its
closes, as A-SPF-1 says. An ANCESTOR's reversal the row cannot see: a `List`'s
cursor row, a table row around a view cell, a menu item's or a drop-down row's
highlight and a picker's segment reverse their content
(`ANSIRenderer.applyPersistentReverse`) where the palette's highlight cannot be
measured — an accent, a page or a focus wash with no RGB. They paint it over
lines already composed: a `List` renders a row's content once, whatever its
background, and paints the background over it. So a table nested in such a
row, on the row the cursor is on, shares its ink there, and its blanks show it.

What differs, pinned by `TableRowInkTests.ancestorReversalDiffersOnlyInBlankCells`
(random rows through the `List` row's own reversal paint, at four depths):
- No glyph: every cell that draws one is in the state it was.
- The spacing between two cells is filled with the cells' ink, not the
  reversal's. The colour is the same unless the nested table's ink differs
  from the palette's foreground (a `.foregroundStyle` on it, say), which is the
  reversal's ink.
- An unselected nested row's blank selection mark is filled with the
  reversal's ink. It was a block of the mark's colour.
- The gap after a nested row's ● is filled with the mark's colour. It was the
  reversal's.

Nothing differs without colour, where no ink is stated, or under a breathing
reversal's reversed frame, which drops every colour of the row's own first
(`applyReversedPair`).

**Shipped: a table inside a `List` row keeps the per-cell closes.** Every `List`
row installs `\.listRowEditRestrictions`, so a table reads it as it builds a row's
ink (`TableRowInk`'s `insideListRow`) and does not share there: the main case,
a table nested in a list, draws exactly as it did, and loses only the byte
saving (`TableRowInkTests.tableInsideAListRowDoesNotShare`). **Left as
described above:** a table inside another table's view cell, and inside a menu
item's, drop-down row's or picker segment's highlight, on the highlighted row,
under a palette whose highlight cannot be measured. With the table's default ink
only the mark column differs there, and the old picture was no more deliberate
than the new: a blank mark, which says "not selected", drawn as a coloured block.

**The fuller version, and its price:** tell the nested table it is drawn under
reverse video, and stop the sharing there. The reversing rows would pass that
down to their content as an internal environment value. The table would read
it once per render. For a `List`, its cursor row's content would render again
whenever the cursor arrives or leaves under such a palette. The focused,
selected row already does that for `\.backgroundProminence`
(`raiseBackgroundProminence`, in `_ListCore` and in `Table`). The fuller
version extends it to the focused row the selection does not include, in both
twins, with their memo clearing, and to the menu, drop-down and picker rows,
or leaves those documented as uncovered.

A cruder version would not need the cursor row at all: a table nested in any
list row or table cell keeps the per-cell closes. A list row says so already,
through `\.listRowEditRestrictions`. A table's view cells would need a marker
written per view cell, which every table with a view cell pays. Every nested
table would lose the saving, reversed or not, and the menus and pickers would
stay uncovered.



## Appendix: thin lines between rows with Kitty graphics (2026-10-08)

> **Status:** landed 2026-10-24 (`3e60414ac`: lists draw SwiftUI's separators as hairlines where the terminal can),
> its row marking memoised on 2026-10-25 (`e807fce55`); moved here from `Investigations/` on 2026-10-26. Before
> that: prototype built 2026-10-24 (lane-hairline), after the owner chose option 4 of decisions A-D6L-2: a
> `.hairline` separator look on `List`, drawn on Ghostty only, and SwiftUI's default separators there. Researched
> 2026-10-08; the probe that gates it was run the same day by the owner, on Ghostty and iTerm2. What was built, and
> what it left open, is in the D6L decisions' A-D6L-2 and the survey's "What TUI draws". **Asked by:** the owner, 2026-10-04 (A47: Kitty-graphics thin lines are "a later project …
> keep in mind, not now"). **Working notes** (not in git): `KGP/research.md` (the design, revised after a review),
> `KGP/records/`; the probe's own records are committed (below).

### Question

Every separator TUI draws between rows costs a whole row: `.listRowSeparator(.visible)` puts its `─` rule on a
line of its own, which is why separators are off by default where macOS draws a hairline under every row. Could a
terminal that speaks the Kitty graphics protocol draw a line one or two pixels thick on the boundary between two
rows instead, at no cost in rows, and what would it take?

### Answer

- **Feasible, but only with Kitty's classic placements,** which TUI had never emitted. The Unicode placeholders
  `Image` uses cannot do it: a placeholder cell is the picture and holds no text, so the line would cost the row it
  is meant to save. A classic placement is drawn at the cursor, outside the cell grid, with a pixel offset.
- **Ship it as a look, not a layout:** a TUI-only `.hairline` separator style that never takes a row on any host,
  and draws nothing where the graphics handshake says no. SwiftUI's separator modifiers stay as they are; SwiftUI has
  no separator-style API, so this would be a TUI addition beside them. With it, A-D6L-2 could take SwiftUI's
  default (separators on) without halving every list.
- **Draw it at the writer, from the composited frame:** the list marks the next row's first cells with a private
  marker; the writer turns marker runs into placements and keeps a model of what the terminal holds. A sheet or menu
  over the list then hides the line without special cases, and a scroll clip cuts it. SGR 58 is not the marker: it
  is the code SwiftUI-style underline colours will need, and it would colour a link's underline on a marked row.
- **Per host:** from source reading, kitty, Ghostty and Rio looked clean and iTerm2 workable with quirks; the probe
  then found that Ghostty needs the line above the text (`z=+1`), and so the host identified first, and that iTerm2
  gives no pixel unit to crop by. WezTerm deletes the line on `ESC[2K`, which starts every whole-line rewrite, so the
  layer must re-place it there; Konsole hides `z<0` under painted cells, and TUI cannot yet recognise Konsole.

### Key measurements

`Tools/TerminalProbes/hairline_probe.py` (`c25452779`), run interactively by the owner on macOS 15.8.1 (arm64), on
the alternate screen, every card answered: Ghostty 1.3.1 and iTerm2 3.7.3. A 2048 × 2 px strip, placed with
`C=1` at the run's first cell on the lower row, so that its top edge is the boundary. Records are committed in
`Tools/TerminalProbes/data/` and written up in the
[Terminal compatibility survey](<../../Terminals/Terminal compatibility survey.md#a-line-on-a-row-boundary-kitty-classic-placements--measured-2026-10-08-ghostty-131-and-iterm2-373>)
(`963018543`, `ad855dcf8`).

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| a line on the boundary | yes | yes |
| the layer that shows on every fill | `z=+1`, over glyphs (`z=-1` does not show on every fill band); the host must be identified first | `z=-1`; `z=+1` per fill band unmeasured |
| crop to the run's width | open: the arithmetic unit (16n px) was judged "no" once | no unit found: leave the host out until one is |
| after clear or a screen switch | re-send the strip (one store per screen) | nothing needed (one store, kept) |
| cleanup | delete by id | delete by id; a line left behind shows on the primary screen |

On both, whole-line rewrites kept the line, delete-and-re-place worked, a strip with no placement left could be
placed again without re-sending, and the line held steady at 60 Hz, with and without synchronized output (mode
2026).

### Reasoning

- **Why the writer, not the list:** the line must follow the final composited frame. Drawing it from the list would
  re-implement clipping, overlays and scrolling, which the writer already gets from the frame's cells (the
  argument of §11 of [Terminal graphics protocols](<../../Images and terminal graphics/Terminal graphics protocols.md>)).
- **The risks:** the line lives outside the cell grid, so a missed resize, resume, modal, replay or scroll leaves a
  ghost; the marker must survive every stage that rewrites cells; a marker-only change leaves the built row identical,
  so the layer must diff its own runs. Tests must cover each.
- **The price:** about 5–6 days for the prototype on `List`, 5½–7 with a Konsole identity (estimates). The same
  writer path is what `Image` needs to reach WezTerm, Konsole and Warp through classic placements.

### Links

Decisions [D6L](<Stripes, surfaces and separators.md>)
(A-D6L-2, the separator default); the compatibility guide's list-separator entry in
[SwiftUI compatibility guide](<../../SwiftUI parity/SwiftUI compatibility guide.md>).
