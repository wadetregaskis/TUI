# Sections and pinned headers in lazy stacks

*How a `Section` outside a list became its parts, why a lazy stack keeps its
own sections whole, and how a pinned header behaves: what it covers, where it
sits under the "N more" line, how focus and a seek treat it, a sectioned
`LazyVGrid`, and what pinning costs. Ids: B-D1S-1, B66 to B71; deviation L8;
B-D1S-1's settled follow-up of 2026-10-18.*

## In short

Outside a `List`, a `Form` and a `Table`, a `Section` is its parts, as in
SwiftUI. A lazy stack is the exception: pinned, it keeps every section of its
own whole, so it can draw a header whose rows are still on screen after the
header itself has scrolled out of the band; unpinned, it keeps a loop's
sections whole so it builds only the sections it draws. A pinned header covers
the rows beneath it (SwiftUI's lets their blanks show through), sits below the
"▲ N more" line, and keeps the focused row clear of it.

## The problem

SwiftUI's lazy stack pins a header by knowing which of its rows is whose
header. Handed a section's parts as anonymous rows, TUI's windowed paths (the
uniform seek, the anchored window over 256 rows of estimated positions) could
not say which row heads which section, nor draw a header outside the band. And
taking a loop's sections apart made every row of every section a child that
only its row knew how to count — built on every walk.

## How it unfolded

1. **2026-10-04 to 05, lane D1S**, after the owner's B15 to B17 and A44: a
   section became its parts everywhere but the list family; lazy stacks kept
   their own sections whole, pinned or not, in the cases B-D1S-1 lists, with
   the differences it lists (a centred view can be a cell off; a modifier on
   such a section wraps it whole).
2. **The pinned-header calls B66 to B71**, each written up with its fuller
   version; B71 records that pinning's cost was not measured, the machine
   being shared, and names the A/B owed.
3. **2026-10-18, settled.** Asked in the record whether to build SwiftUI's
   model (the stack takes its sections apart and pins from row positions,
   about three days), the recommendation adopted was option 2: build it, as
   one lane with B68's structural fuller version and B-D1S-5's element index,
   scheduled after the cheaper items. **Not yet built.**

## Where it stands

Shipped as D1S and B66 to B71 describe; L8 records that a lazy stack lays its
sections out whole. The fuller lane is owed.

## For a future reader

- **Owed: one lane, about three days** — B-D1S-1's fuller version, B68's
  structural version and B-D1S-5's element index together. Without the index,
  taking sections apart costs every row again.
- **B71's A/B, run 2026-10-27:** pinning costs a stack that does not pin
  nothing measurable (B71 has the numbers).
- **Centre alignment inside a section kept whole** can land a view a cell from
  where an unpinned stack would; leading and trailing are exact.

## The record

### B-D1S-1. A lazy stack keeps its own sections whole: all of them pinned, a loop's unpinned

*`LazyVStack(alignment:spacing:pinnedViews:content:)`,
`LazyHStack(alignment:spacing:pinnedViews:content:)`, the lazy grids'
sections, `Section`*

Everywhere outside a `List`, a `Form` and a `Table` a `Section` is now its
parts (B16): the container lays its header's, content's and footer's views out
as its own children. A lazy stack is the exception, in two ways:

- **Pinned**, it keeps every one of its own sections whole. Pinning is done by
  the section, which knows where its header, content and footer are and emits a
  copy of the header marked to pin; a stack handed the parts as anonymous rows
  could not say which row is whose header, and its windowed paths would not
  draw a header that has scrolled out of the band while its rows are still on
  screen. A loop's row of the app's own whose body is a section —
  `ForEach(groups) { GroupView(group: $0) }` — is drawn whole, as unpinned
  (`SectionWholeness.pinned`): its section pins as the stack's own, and the
  stack builds only the sections it draws, beside a sibling too.
- **Unpinned**, it keeps the sections a `ForEach` makes as its rows whole —
  `ForEach(groups) { Section … }`, Apple's own shape, and `ForEach(groups) {
  GroupView(group: $0) }` where `GroupView`'s body is the section — and takes
  any other apart (`SectionWholeness.loopRows`). Taken apart, such a loop's rows make a
  number of children only each row knows (B15), so every row of every section
  was built on every walk that asked the stack for its children; kept whole,
  the stack windows over the sections and builds only those it draws, as it did
  before a section was its parts. A stack whose content's type shows no section
  can be among its children (`mayHandOver(_:in:)`) — nearly every lazy
  stack — keeps no scope and pays nothing.

Each section kept whole lays its parts out as the stack would — along its
axis, its `spacing` between every two (between the header and the first row
too, as SwiftUI spaces them), each aligned across by its alignment — so the
stack draws what it would with the parts as its children, but for:

- **Centre alignment can be a cell off.** The section centres its views within
  its widest view, and the stack centres the section. Where those two widths
  differ in parity a view lands a cell from where the stack would centre it
  unpinned. Leading and trailing alignment are exact.
- **A modifier on such a section wraps it whole**, where SwiftUI applies it to
  each part (`Section { … }.padding(.top, 10)` pads the section once, above
  its header, not above each row).
- **The stack windows by section.** A section in the band draws all of its
  rows, as before this lane; a section written in an unpinned stack's content
  is taken apart, and the stack windows over its rows.
- **A loop's section under an `if` is kept whole too**, empty while the `if`
  holds nothing: `ForEach(groups) { g in if g.visible { Section … } }`, an
  `if`/`else` with a section in one arm and a section, nothing or one view in
  the other, and a view of the app's own whose body is either
  (`mayBeSectionRowType(_:)`). Such a row is one child, pinned or not, so
  the stack builds only the rows it draws and its section pins as the
  stack's own wherever the loop is — taken apart, as it was, every row was
  built on every walk to be counted, and beside a sibling the section did not
  pin. SwiftUI counts no child for an `if` that holds nothing; no stack draws
  or spaces an empty one (B-D1S-5). A `List` and the section APIs still count
  such a row, a section or nothing. An `if` around a section among other views
  in the row is taken apart, and every row built, as any loop whose rows vary
  is (B-D1S-5).

**The fuller version.** The stack takes its own sections apart like any other
container and does the pinning itself: it keeps a map from each section to its
header row, content rows and footer row; every windowed path (the uniform
seek, the anchored window, the exact walk, and the append-while-fits walk)
draws the header and footer of any section that meets the band even when they
are outside it; and the stack emits the pin layers from the rows' positions.
About two days with the tests, most of it in the anchored window, whose rows
away from the band have estimated positions. Unpinned, it needs B-D1S-5's
fuller version too — a loop of sections counted without building every row —
or taking them apart costs every row again.

### B66. A pinned header covers the rows under it; SwiftUI's lets them show through

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

### B67. Under the "N more above" line, a pinned header sits below it

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

### B68. Which sections are the stack's own: the next stack down, and one sibling step

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`*

SwiftUI pins the sections in the stack's own list of subviews, however
wrapped, and not one inside a row. TUI's stack sees each section as one
child — a section in a stack draws as one unit (B16; shipped 2026-10-05, so
the compatibility doc now says where a section is taken apart) — so the question is
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

### B69. Focus keeps a row clear of a pinned header; a seek does not

*`LazyVStack.init(alignment:spacing:pinnedViews:content:)`, `ScrollViewProxy.scrollTo(_:anchor:)`*

SwiftUI's `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge,
under the header pinned there (measured: the row is drawn, and the header
covers it). A seek here does the same, unchanged: it is SwiftUI's API, and a
program that wants the row clear can say `.center`.

The reveal that follows focus is TUI's own, and it does allow for pinned
chrome: a focused row is kept clear of the lines a pinned header or footer
covers, as it is kept clear of the "N more" lines. Without that, stepping up
through rows with Shift-Tab put each one under the header as it arrived —
focused, and not seen — which for a keyboard user is a hole in the screen. A
control inside a pinned header is found where the header is drawn, so a key
it takes leaves the view where it is.

What macOS's own focus ring does under a pinned header was not measurable
offscreen. If it lets a focused row sit under the header, this is a deviation
toward the terminal's need; I would keep it either way.

### B70. A sectioned `LazyVGrid` is a stack of sections, each around a grid of its views

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
- `spacing` falls between rows, between sections, between a header and its
  section's first row and before the footer, as SwiftUI puts it (measured).
  It was left out around the header and footer when a section drew as one
  unit; B16 and da4409000 take sections apart, and a render on 2026-10-23
  shows the blank row on both sides.
- The header is drawn plain, in the text's own ink, as SwiftUI's is; the
  dimmed bold styling it once kept is gone (B16).

`spacing:` is `Int? = nil` now, SwiftUI's spelling, where it was `Int = 0`;
`nil` is still no blank rows.

**The fuller version** places a header and a footer as spanning cells of the
grid's own layout, with the spacing exactly SwiftUI's, and pins them from
there. That needs the layout to emit the pinned copy, knowing the section's
extent only as it places its views — a hook into `_LayoutCore` that no other
layout needs. Half a day; worth it only if the header spacing matters to
someone. **Moot since da4409000 and B16:** the spacing is SwiftUI's already;
only the pinning-from-the-layout half would remain, and nothing asks for it.

### B71. The cost of pinning, and the measurement owed

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
nothing. Every `Section` reads the scope once per render. A pinned section
pays a copy of its header per render. A `LazyVGrid` resolves its views once
more per measure and render, to ask whether a section is among them — the
grid's layout resolves them again — which is the one cost a grid with no
sections pays.

None of this was measured at the time: the machine was shared. The A/B owed —
`deep`, `kitchensink` and `megalist` against the parent commit — ran on
2026-10-27: release `Stress` before `caf92aca2` against `701d6588d` (the
stack's pinning, focus scrolling clear of a pinned header, the grid's
sections), `ab_bench.py` at 4.5 s × 10 reps, CPU time, with the two
lazy-scroll scenarios that existed then added:

| scenario | warm | 95% CI | cold | 95% CI |
|---|---|---|---|---|
| `deep` | −0.0% | −1.4…+1.1 | +0.5% | −1.1…+1.5 |
| `kitchensink` | +0.4% | −1.5…+3.5 | +0.3% | −2.6…+3.1 |
| `megalist` | −0.0% | −1.4…+1.6 | +0.3% | −1.2…+2.1 |
| `scrollfollow` | +0.6% | −0.6…+2.1 | +1.2% | −1.2…+3.5 |
| `scrolleager` | +0.4% | −1.8…+2.3 | +0.1% | −0.9…+1.0 |

Every verdict indistinguishable: the costs above are real but too small to
see. No scenario has a lazy grid, so the grid's extra resolve is still
unmeasured.
