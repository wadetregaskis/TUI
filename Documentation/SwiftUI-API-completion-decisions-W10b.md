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

### B-W10b-5. The cost of pinning, and the measurement owed

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
