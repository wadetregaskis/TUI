# Completing the SwiftUI API: lane D1S's new judgement calls

*The lane that implemented the owner's decisions on B15, B16, B17 and A44 of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Where the work met a judgement call those decisions did not settle, the safe
option shipped and is written up here, in that document's three parts: A needs
a decision, B shipped the safe option (with the fuller version and its price),
C declined with a parity-map reason. SwiftUI's behaviour was measured on macOS
15.8 with offscreen `NSHostingView`s (probes in the session notes,
`D1S/probe/`).*

## B. Shipped the safe option

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
  screen.
- **Unpinned**, it keeps the sections a `ForEach` makes as its rows whole —
  `ForEach(groups) { Section … }`, Apple's own shape, and `ForEach(groups) {
  GroupView(group: $0) }` where `GroupView`'s body is the section — and takes
  any other apart (`SectionWholeness.loopRows`). Taken apart, such a loop's rows make a
  number of children only each row knows (B15), so every row of every section
  was built on every walk that asked the stack for its children; kept whole,
  the stack windows over the sections and builds only those it draws, as it did
  before a section was its parts. A stack whose content's type shows no section
  can be among its children (`mayHandOverSections(_:)`) — nearly every lazy
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

### B-D1S-3. An `AnyView` that is a loop's row is one child

*`AnyView`, `ForEach`, `Group(subviews:transform:)`, `LayoutSubviews`*

Measured, SwiftUI takes an `AnyView` apart like a `Group` —
`ForEach(0..<2) { _ in AnyView(Group { a; b }) }` is four subviews, and an
`HStack` of it lays out four views in a row (probe `b15`; the Wave 5 probe `s`
measured one `AnyView(Group { a; b })` as two subviews). An `AnyView` is now a
provider of what it erases wherever a container resolves it — a stack's, a
`Layout`'s, the subview APIs', a `List`'s child walk — and one child, at the
identity it always had, when it erases one view. As a `ForEach`'s ROW it stays
one child (`AnyView.staticRowMemberCount`), so the probe's loop is two children
here: the row type cannot say how many views it erases, and counting them
means building every row on every walk — the `anyview` scenario's loop would
lose its row memo, and a lazy stack of erased rows its window.

**The fuller version.** B-D1S-5's: a loop whose rows vary counted without
building every row on every walk (an element-to-first-child index kept across
frames while the data is unchanged), after which an erased row can be taken
apart as a `.varying` one. A/B owed for the provider conformance as landed:
`anyview`, `deep`, `modifiers`.

### B-D1S-5. A loop whose rows vary is built to be counted

*`ForEach`, `LazyVStack`, `LazyHStack`*

Where a row's type says how many views it is — a `Group { a; b }`, a tuple,
`if`/`else` arms of one view each — the loop maps a child's ordinal to its
element by arithmetic, and a lazy stack over a million such rows builds only
the rows it draws. Where only the row knows — a loop in the row, an `if` whose
arms differ, an `if` without `else` anywhere among the row's views (none of
them while false), a section the walk takes apart — every row is built and
resolved, though not drawn, on every walk that asks for the children; its
views are still selected and tagged by their element, placed by the key each
carries (`FlattenedRowIDs`). An `if` without `else` around ONE view that is
the row's only view stays one child, empty when false, as before, where
SwiftUI counts none: no stack draws or spaces an empty child, and a `Layout`
counts it. Counting it as it is spliced would build every row of a loop that
filters its elements with an `if` — a common shape — to learn which are
there.

**The fuller version.** An index from element to first child, built once and
kept across frames while the data is unchanged (the loop's `listRowsSignature`
already says when it is), so a lazy stack over varying rows is O(window) after
the first frame. A day, with an A/B on `megalist` shaped with such rows.

### B-D1S-6. A modified view of the app's own, or one whose body is an `if`/`else`, is one child

*`View`, `Group(subviews:transform:)`, `HStack`, `Layout`, `List`*

A view of the app's own whose `body` is several views is now, to the container
resolving it, those views, as SwiftUI's is (measured, `D1S/probe2/composite`):
a tuple, a loop, an `if` (none while false), a `Group` of those or a `Section`
as a body is taken apart in a stack, a `Layout`, the subview APIs and a `List`
— one inside another, and a loop of them, too — with the view's `@State` bound
at its own identity and every view of its body at the identity it had drawn
whole (`compositeMembers(of:context:)`, gated by the static witness
`View._handsOverChildren`, a few witness calls down the chain of `body` types).
Three shapes are still one child:

- **A modifier on such a view** (`Rows().padding(3)`): SwiftUI applies it to
  each of the body's views (measured: two subviews, each padded). The modified
  view is no provider here, as a modifier reaches members only through a
  provider it wraps.
- **A body that is an `if`/`else`, or an `AnyView`**: they answer the default
  witness (their own body is `Never`), so an `if`/`else` whose arms are
  several views is one child. Most of the framework's own controls have an
  `if`/`else` body (`TextField`'s does) and hand over one view either way;
  answering `true` for it would evaluate their bodies on every walk to find
  that out.
- **In a `List` beside other rows**, the rows of a loop in such a view are
  drawn as rows but selected and edited by the hand-written rule (their tag,
  else their place): a list's row placement cannot see into a body without
  evaluating it (`KeyedRowRun.opaque`). A section of the app's own there is a
  section, its loop's rows selected by element and deletable.

**The fuller version.** `ModifiedView` (and the wrappers that hand a provider's
members their modifier) answering for content that is such a view — a
provider conformance that holds for a content TYPE only a witness can name, so
a forwarding conformance on every wrapper; and the placement told a view's
body when the walk evaluates it. A day or two. A/B owed for what landed:
`fanout`, `deep`, `kitchensink`, `megalist`, `anyview`.

### B-D1S-7. A stack around a loop over subviews asks it for guides it may not have

*`ForEach(subviews:content:)`, `Group(subviews:transform:)`, `Subview`,
`HStack`, `VStack`, `ZStack`, `Layout`*

A proxy lays out as its member (B17), and a member may carry an alignment
guide; `Subview` is one type for every member, so its static witness
(`_providesAlignmentGuide`) says it MAY, and every container type holding a
proxy says so too, up the tree. A `ChildView` built for a proxy asks the
instance and is exact, so the container placing the proxies pays nothing; the
containers AROUND it cannot ask without resolving it. So an aligning stack
with such a container among its children — `HStack { VStack {
ForEach(subviews: content) { $0 } }; Text("x") }` — asks it for its guide on
each of its passes (its measure and its render, and each enclosing stack asks
its own child the same way, up the chain). What that costs, when no member
carries a guide:

- **A stack** (`VStack`, `HStack`, `ZStack`) resolves its children to answer
  and stops there: the loop's members — the content they come from resolved
  again, a proxy built for each — then `nil`. A walk over the members per
  question, not a layout.
- **A built-in `Layout`** (`HStackLayout`, `VStackLayout`, `ZStackLayout`,
  the lazy grids, `GridLayout`) did a whole layout pass per question; it now
  resolves its subviews and answers `nil` when none carries a guide, as a
  stack does.
- **A `Layout` of the app's own** does the pass whatever its subviews hold,
  as it always has: whether its `explicitAlignment` is the default cannot be
  told from its type (`_definesExplicitAlignment` is `true` for it).

**The fuller version.** The answer cached per pass where the members are
resolved — "no member of this loop carries a guide", kept by the loop's
identity in the render cache's per-pass store — and consulted by a container's
guide question before it resolves anything, so the question costs a lookup.
Half a day, with an A/B on `deep` and `kitchensink` shaped with such loops.
