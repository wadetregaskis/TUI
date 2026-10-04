# Completing the SwiftUI API: Wave 10b decisions

*Pinned section headers and footers: `PinnedScrollableViews` and the
`pinnedViews:` initialisers of the lazy stacks and grids. The format is
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md)'s;
the entries fold into it as the coordinator lands the wave.*

What SwiftUI does was measured on macOS 15.8, with offscreen `NSHostingView`s
in scroll views scrolled through their `NSScrollView`, reading the pixels down
a column (probes in the session notes, `w10b/probe/`):

- A header pins to the viewport's top while its section's **content** is under
  it. The content's last row pushes it up and away — the footer's top when the
  footer scrolls, the next header's top when there is none — so a header never
  sits over its own footer, and a header taller than what is left of its
  section rides up with it.
- A footer pins to the bottom, never above its section's first content row:
  with only a sliver of the content showing, it sits on that sliver, clipped by
  the viewport's edge.
- Pinned views draw over the content with no background of their own: rows
  show through wherever the header draws nothing.
- Only the stack's own sections pin — a `ForEach` of them, or ones written in
  its content, with any modifiers (a `.padding` on a section is applied to each
  of its parts, and its header still pins). A section in a row's `VStack` does
  not. Outside a scroll view nothing pins.
- A pinned stack below other content in the scroll view (a title above it)
  pins exactly as one at the top.
- Grids: a header and a footer span every column and pin the same way.
  Horizontal stacks and grids pin to the leading and trailing edges.
- `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge, under a
  pinned header: nothing allows for it.
- `List`: `.plain` and `.inset` (and the macOS default) keep the first
  section's header at the top as the list scrolls; `.sidebar` does not. Read
  from the header's reported frame, which a floating table row may not update,
  so weaker evidence than the pixels above.

---

## A. Needs your decision

### A-W10b-1. Pinned sections in a horizontal stack or grid

*`LazyHStack.init(alignment:spacing:pinnedViews:content:)`,
`LazyHGrid.init(rows:alignment:spacing:pinnedViews:content:)`*

In SwiftUI a section in a `LazyHStack` is laid out along the row: its header
at the leading end, its views after it, its footer at the trailing end; in a
`LazyHGrid` the header spans the rows. Pinned, a header stays at the
horizontal scroll view's leading edge while its section's views are under it,
and is pushed off by the last of them; a footer stays at the trailing edge
(both measured on macOS 15.8, the vertical rule turned on its side).

Here a section in a `LazyHStack` draws as one unit, which is a column — header
above, views below, footer under them (B16) — and in a `LazyHGrid` it takes a
single cell. Pinning a header to the leading edge needs the header to BE at
the leading edge, so these two `pinnedViews:` initialisers are not offered:
SwiftUI code using them does not compile, rather than compiling and pinning
nothing.

**Options.**

1. **Lay sections out along the row, and pin to the leading edge.** A
   section whose container is horizontal (the stack cores publish their axis
   to their children already) draws header, views and footer side by side;
   a `LazyHGrid` takes its sections apart as `LazyVGrid` now does (B-W10b-5);
   the scroll pin gains a leading and a trailing edge, which a horizontal
   scroll view resolves against its horizontal offset before it slices each
   line to the viewport. About a day and a half with the tests. It changes
   the drawing of every `Section` in an `HStack` — from a column to a row —
   which is B16's fuller version for the horizontal stacks, and B16 asked you
   whether a header outside a list keeps its dimmed styling.
2. **Leave them out** (what ships). Nothing that compiles misbehaves.
3. Accept `pinnedViews:` on the horizontal pair and pin nothing. Ruled out by
   the second parity rule.

**Recommendation:** 2 now, and 1 with B16's fuller version when that is
decided: the drawing change is the same change, and doing it twice would cost
more than once.

### A-W10b-2. Should a `List` pin its section headers?

*`List`, `Section`, `PlainListStyle`, `InsetGroupedListStyle`*

SwiftUI's `List` has no `pinnedViews:`. On macOS, though, a plain or inset
list floats its section headers: the first section's header stayed at the
top as the list scrolled, under `.plain`, `.inset` and the default style, and
did not under `.sidebar` (measured on macOS 15.8 through the header's reported
frame, which an AppKit floating row may not update faithfully, so weaker
evidence than the pixel probes above). Footers did not float in any style.
TUIkit's `List` draws a section's header as a row, which scrolls away.

**Options.**

1. **No pinning** (today). Honest, and matches iOS's grouped lists; a long
   section loses its title as it scrolls.
2. **Pin headers in the plain style** (and whatever inset styles Wave 8b adds),
   not in a sidebar style: the list's own windowed draw finds the section
   whose rows are at the top and draws its header over the first visible
   line, as the scroll pin does for a stack, with the keyboard cursor kept
   below it (`ensureFocusedItemVisible`) and the covered row's mouse region
   taken away. About a day with tests — `_ListCore` is its own scroll engine,
   and anchors, selection and the row memo all touch the first line.
3. A TUIkit modifier choosing, defaulting to 1.

**Recommendation:** 2, after Wave 8b's list styles land, since which styles
pin is a question about those styles; it is what a macOS user sees.

## B. Shipped the safe option

### B-W10b-1. A pinned header covers the rows under it; SwiftUI's lets them show through

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`, `PinnedScrollableViews`*

SwiftUI's pinned header has no background, so a row scrolling under it shows
through every point the header leaves empty (measured: a 50-point header over
300-point rows leaves the rows visible beside it). A cell holds one glyph,
and a row's text showing beside a short header reads as one garbled line:
"Header 0ow 3 text".

So a pinned header's cells replace the rows' glyphs across the section's
width (the copy is padded to it), along with what rides on those cells — runs,
fades and hit regions, so a click there never reaches a row no one can see.
What it does not replace is a cell's background: a blank cell of the header
keeps the field under it, so a highlighted row stays highlighted beside the
header's text, which is SwiftUI's transparency for everything a terminal can
show twice.

**The alternative** is SwiftUI's literal reading: the header's trailing blanks
trimmed (`FrameBuffer.trimmingTrailingBlankCells()`, one call), so a row's
text continues past the header's. Free to build, and I recommend against it.

### B-W10b-2. Under the "N more above" line, a pinned header sits below it

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

With `.scrollIndicatorStyle(.text)` the scroll view writes "▲ N more above"
over the viewport's first line whenever it is scrolled. Pinned to that line, a
one-line header — the usual terminal header — would never be seen. So it
goes below it, as a revealed control does (the same `edgeInset` reasoning),
and a pinned footer goes above "▼ N more below". Under the default scrollbar,
and under `.visible`, which reserves the pair outside the viewport, nothing
is charged.

SwiftUI has no such line, so there is nothing to measure. The alternative is
the header under the line, and only its second line onward showing.

### B-W10b-3. Which sections are the stack's own: the next stack down, and one sibling step

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

SwiftUI pins the sections in the stack's own list of subviews, however
wrapped, and not one inside a row. TUIkit's stack sees each section as one
child — a section in a stack draws as one unit (B16) — so the question is
asked from the section's side, by two tests:

- the stack hands its rows the scope in the environment entry every stack
  core replaces for its own children (`ContainerRelationship`, beside the
  axis `Divider` reads), so a section inside a row's `VStack`, `HStack`,
  `Grid` or custom `Layout` never sees it;
- and the section must be one sibling step below the stack
  (`ViewIdentity.siblingSteps(belowDepth:)`): a `ForEach` row or a child of
  the content, through any number of bodies, modifiers and `if`s.

What the two miss: a section that is the only child of a container that
publishes nothing to its children — a row that is `ZStack { Section { … } }`
— is taken for the stack's own and pins (seen in a test). A `ZStack` of one
child is not a shape anything needs.

**The fuller version** is structural: the stack marks each of its children's
contexts as it renders them, and nothing else can. That is a change to every
place the three windowed paths render a row (about a dozen), and to
`ChildView`, whose size is load-bearing (`ChildView.swift`'s note). Half a day,
and an A/B on `megalist` and `fanout`.

### B-W10b-4. Focus keeps a row clear of a pinned header; a seek does not

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`, `ScrollViewProxy.scrollTo(_:anchor:)`*

SwiftUI's `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge,
under the header pinned there (measured: the row is drawn, and the header
covers it). A seek here does the same, unchanged: it is SwiftUI's API, and a
program that wants the row clear can say `.center`.

The reveal that follows focus is TUIkit's own, and it does allow for pinned
chrome: a focused row is kept clear of the lines a pinned header or footer
covers, as it is kept clear of the "N more" lines. Without that, stepping up
through rows with Shift-Tab put each one under the header as it arrived —
focused, and not seen — which for a keyboard user is a hole in the screen. A
control inside a pinned header is found where the header is drawn, so a key
it takes leaves the view where it is.

What macOS's own focus ring does under a pinned header was not measurable
offscreen. If it lets a focused row sit under the header, this is a deviation
toward the terminal's need; I would keep it either way.

### B-W10b-5. A sectioned `LazyVGrid` is a stack of sections, each around a grid of its views

*`LazyVGrid.init(columns:alignment:spacing:pinnedViews:content:)`, `Section`*

A section in a `LazyVGrid` took a single cell: its header, its views stacked
under it and its footer, all in the first column. SwiftUI lays it out across
the grid (measured): the header starts a row and spans the columns, placed
across them where the grid's `alignment` places a view in a cell; the views
flow from the start of the row below; the footer spans after them; views
outside any section flow between the sections. That is what ships, and it is
how `pinnedViews:` could be offered at all.

It is built from parts that exist: the section APIs take the grid's content
apart (`SectionCollection`, which also makes the implicit sections), and
each section is drawn as a `Section` around a grid of its own views, in a
stack that pins as `LazyVStack(pinnedViews:)` does. A grid with no section
among its views is drawn as it always was. Three consequences:

- A sectioned grid fills the width it is offered — the header has to be
  placed across it — where a grid of only `.fixed` columns used to hug them.
- `spacing` falls between rows and between sections, but not between a
  header and its section's first row, nor before the footer, where SwiftUI
  puts it as well (measured). It is the deviation a `LazyVStack`'s sections
  have already, since a section draws as one unit (B16).
- The header keeps the dimmed, bold styling a section's header has in every
  container that is not a `List`, where SwiftUI's is plain.

`spacing:` is `Int? = nil` now, SwiftUI's spelling, where it was `Int = 0`;
`nil` is still no blank rows.

**The fuller version** places a header and a footer as spanning cells of the
grid's own layout, with the spacing exactly SwiftUI's, and pins them from
there. That needs the layout to emit the pinned copy, knowing the section's
extent only as it places its views — a hook into `_LayoutCore` that no other
layout needs. Half a day; worth it only if the header spacing matters to
someone.

### B-W10b-6. The cost of pinning, and the measurement owed

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

Two things are paid by stacks that do not pin:

- The stack cores' environment entry for their children is now a struct (the
  axis, and an optional scope) rather than an optional axis: still one
  dictionary write per stack render, and still inside an existential's inline
  buffer, which a test pins. No allocation was added.
- A lazy stack notes its scope (`nil` when it does not pin) once a pass in the
  render cache's environment record, so that turning `pinnedViews:` on or off
  drops the section rows a memo kept — without it a memoized section came back
  without its pinned copy (a test fails so). One dictionary probe per lazy
  stack per pass.

And by a scroll view: one scan of its content's floating layers for a pinned
one per frame, and one more on a frame whose focus moved — usually a scan of
nothing. A pinned section pays a copy of its header per render.

None of this was measured: the machine is shared. The A/B owed is `deep`,
`kitchensink` and `megalist` on a quiet machine, against the parent commit.

## C. Declined without asking

## D. Deferred to other waves
