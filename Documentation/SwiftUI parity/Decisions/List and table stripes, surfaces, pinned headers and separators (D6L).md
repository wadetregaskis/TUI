# SwiftUI API completion — lane D6L (lists and tables: stripes, surfaces, pinned headers, separators): new judgement calls

*Lane D6L implemented the owner's decisions A29 (tables striped by default),
A29/A46 (a distinct-surface look, as an opt-in prototype), A45 (pinned
section headers in `List`) and A47 (separators as a rule line between rows),
2026-10-07. Each call below came up on the way. The safe option shipped; the
alternative and its price are given. Numbered as the main decisions document
is: A = owner decision, B = basic shipped, C = declined.*

## A. For the owner

### A-D6L-1. The surface look: try it, then decide what (if anything) becomes the default

*`SurfaceTableStyle` / `.tableStyle(.surface)`, `SurfaceListStyle` /
`.listStyle(.surface)` — TUIkit's own, a prototype (decisions A29, A46)*

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
3. **Fold the surface into `.inset`** rather than keeping a TUIkit-only
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
   `.plain`**, off under `.sidebar` and TUIkit's `.insetGrouped`. Every list
   doubles in height, every row's click target and page distance with it;
   tests that read a list's lines need re-baselining (most of a day — lists
   are everywhere in the suite).
3. **On for the inset family only** (`.inset`, `.surface`), where the rows
   have no border to tell them apart — or tied to rows of more than one line,
   where a separator costs proportionally less.

**Recommendation:** 1 for now; try the Example's toggle (Lists page, Styles
section, "Separators between rows") and decide with A-D6L-1, since a
surface-styled list is where separators would most help.

## B. Shipped the safe option

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

Not covered, each by construction rather than by choice: a `Section` a
`ForEach` makes (`ForEach(regions) { Section … }`) draws without its section
separator (that path reads `SectionParts`, which carries none); a guide
inside a wrapper that is neither a stack nor a separator modifier (the two
separator modifiers forward their content's guides, so Apple's documented
row — the guide inside an `HStack`, `.listRowSeparator` on the stack — draws
from the guide; `.onTapGesture`, `.tint` and the other modifiers that draw
their content unchanged do not forward guides yet, a framework-wide gap
older than this lane) is not seen; a row of several views (decisions B15)
reads no guides. Each is an hour or two where it matters.

The rule line is the row's own bottom line, as a separator is the row's
`.bottom` edge in SwiftUI's API: a selected or cursor row's highlight runs
under its own rule, so the highlight is the row's full height, and a click on
the rule selects the row above it. (Whether macOS paints a selected row's
highlight over its separator is unmeasured.) A row lifted out of the list —
a drag's floating copy — leaves its rule behind; the landing slot keeps the
rule's line, so the rows below do not jump while the drag is held. **The
fuller version:** the rule drawn outside the row's fill and click band, as a
line between rows that belongs to neither — its own claims and its own
`AnimatedCellRun` exclusion for the cursor row's breath, about half a day.

### B-D6L-4. Stripes restart at each section; macOS counts on across them

*`alternatingRowBackgrounds` on a sectioned `List` (decisions A29/A46)*

**Measured (macOS 15.8, offscreen `NSHostingView`, each row's background
sampled; `D6L/probe/phase/phase.swift` in the session notes):** a list's
stripes tint the second content row and every other after it — the phase
TUIkit now draws, for tables and lists alike — and in a sectioned list they
count the content rows across the sections, headers not counted: three rows
under A then three under B tint A's second and B's first and third.

**Shipped:** TUIkit's count restarts at each section's first row, as it always
has (`ListStyle.alternatingRowColors`), so B's first row is plain. Unmeasured
for a sectioned `Table` (decisions A31), which counts its own way.

**The fuller version:** one count across the list. The composers seed the
count from the rows above the window (`RowSource.sectionContentIndex(at:)`),
which today walks back only to the section's header; across sections it walks
to the list's top, asking every row above the window its type — O(rows above)
a frame on a long list whose types are still to be asked. A prefix count of
the content rows, kept per source beside its section chrome, makes it a binary
search again: about two hours.
