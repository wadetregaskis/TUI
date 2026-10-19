# Layout parity: guides, wrappers, spacing and priorities — decisions from lane LAYOUT

*Lane LAYOUT, 2026-10-18, built the layout items the owner had ruled on or
that prior rulings settle: guides out of an app's own view types (B19),
SwiftUI's rule by kind for guides out of a container (A-GUIDE-2), guides
through single-child wrappers (SA-L11), and the items listed below. SwiftUI was
measured with offscreen `NSHostingView`s on macOS 15.8.1 (SwiftUI 6.5.4,
Xcode's Swift 6.2.4), in `Tools/SwiftUIProbes/Alignment guides/layout1.swift`
and its `layout1.out`. The format is that of the main decisions file:*

- **A-LAYOUT-n — needs your decision.**
- **B-LAYOUT-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-LAYOUT-n — declined.** With the reason.

## B. Shipped the safe option

### B-LAYOUT-1. A row type of the app's own that holds a guide forfeits a loop's row memo

*`View.alignmentGuide(_:computeValue:)`, `ForEach`, decisions B19*

Since B19 a view of the app's own answers `_providesAlignmentGuide` with its
body's answer, so a guide anywhere in `struct Row: View`'s body is a guide of
`Row`. Two places read that answer as a reason to do more work, and both now
do it for such a row type where they did not before:

- **A `ForEach` keeps no row memo for a row type that may hold a guide**
  (`ForEach.makeChild`): the memo wrapper is opaque, and a guide inside it
  would not reach the stack. Before B19 that was only a row that set a guide
  itself; now it is any row type whose body holds one, even one that a stack
  inside the row keeps to itself (an edge guide of a stack of several views,
  A-GUIDE-2), because the static question cannot tell the guide's kind.
- **A stack around such a view asks it for its guide**, evaluating its body in
  a measure, where it answered nothing before. A stack of several views
  answers an edge or centre guide before resolving its children (A-GUIDE-2),
  so the common query stops at the first such stack in the body.

Apps with no guide inside a view type of their own pay one table read per
child of a composite type (`BodyWitnessMemo`), where they read a constant.

**The fuller version** keeps the memo: `_MemoizedRow` forwards the guide
witness and answers the guide query by building its row, so a memoised row
is still asked for its guide (only on a stack that aligns on one, and only
rows whose type may hold one). About half a day, plus the A/B below, since it
puts a query on the memo's hit path for such rows.

**A/B owed (B19's three arms):** off (the patch in the lane's notes,
`LAYOUT/b19-off-arm.patch`), the base before B19, and B19; scenarios `deep`,
`kitchensink`, `table`, `customlayout`, `fanout`, `anyview`. Over about 1% on
`deep` or `kitchensink` it goes back to the owner.

### B-LAYOUT-2. An `AnyView` passes no guide out of itself

*`AnyView`, `View.alignmentGuide(_:computeValue:)`*

Measured: SwiftUI's `AnyView(G)`, as a stack's child, reports `G`'s leading
guide (C at 5), and `VStack { AnyView(G) }` reports none, an `AnyView`'s
count being unknown from its type (A-GUIDE-2). TUIkit's `AnyView` reports
none in either case: its static witness cannot say what it erases, and
answering "may" for every `AnyView` would put every loop of erased rows off
its row memo and every stack holding one on the guide path. The second case
matches; the first does not.

**The fuller version:** a container building a child that is an `AnyView`
asks the erased view's witness dynamically (one existential open per
`AnyView` child per walk), and an `AnyView` answers the guide query by
opening its view. That reaches a guide in an `AnyView` that is a stack's own
child; one further in (an `AnyView` inside a `VStack` inside the stack)
still needs the static "may", with the costs above. About half a day for the
first part, plus an A/B on `anyview` and `kitchensink`.

### B-LAYOUT-3. A border moves a guide by its ring, and a few wrappers stop one

*`.border(_:style:width:)`, `.badge`, `.toolbar`, `listRowInsets`,
`listRowBackground`, `BufferModifier`; deviations L11*

A guide now passes every single-child modifier written after it, as SwiftUI's
does: `.padding`, `.frame` and `.position` move it by where they put their
content, `.offset` passes it from the layout's place, `.overlay` and
`.background` pass their base's (measured, `layout1.out` case B), and the
wrappers that keep their content where it is pass it unmoved. That last set
is decided by a witness for size-neutrality,
`SingleContentWrapper._keepsContentGeometry` (with `BufferModifier`'s twin),
which every `DrawsContentUnchanged` wrapper meets a fortiori; the paint
wrappers (`.opacity`, `.hidden()`, the colour effects, `.dimmed()`), drag and
spring-loading regions, `.help`, `.fixedSize()` and a transition state it
themselves.

Two differences remain:

- **`.border()` moves the guide in by its ring**, a line and a blank cell
  across and a line down per ring, where SwiftUI's border strokes inside the
  view and moves nothing (measured: 5 under `.border(_:width: 2)`). A terminal
  border takes cells round its content, so the content's guide is where the
  content is.
- **A `.badge`, a `.toolbar`, a list row's insets, colour or background, and a
  `BufferModifier` of the app's own** stop a guide: each moves or resizes its
  content without saying by how much (a list row's colour fills the row's
  width, wider than its content), and a guide passed through unmoved would
  report the wrong position.

**The fuller version:** a requirement on `BufferModifier` that states where
the modifier puts its content (its insets), so an app's own modifier
translates a guide as padding does, and the same for the badge (its content
sits at the leading edge, the badge after it) and the list row styles. About
half a day for the requirement; the others an hour each, with a probe each.

### B-LAYOUT-4. A `Grid` reports no guide out of itself

*`Grid(alignment:horizontalSpacing:verticalSpacing:content:)`, `GridRow`*

Measured: SwiftUI's `Grid` reports a custom guide and a text baseline set in
a cell, and no edge guide, even from a grid of one cell (`layout1.out` case
C). TUIkit's `Grid` forwards the static witness but answers no guide query,
so it reports none of any kind; `GridLayout`, the same grid as a `Layout`,
reports custom guides and baselines through the layout's default.

**The fuller version:** the grid answers the query from its lattice: each
cell's guide moved by where the grid placed the cell, merged by the guide's
rule, edge guides never. About two hours with tests.

### B-LAYOUT-5. `EmptyView` is no member to a container; drawn on its own it is still a view

*`EmptyView`, `.frame`, `.padding`, `.overlay`, `.background` (the settled
question S3-EMPTYVIEW-FRAME, option 2)*

Shipped: `EmptyView` is a `ChildViewProvider` of no members, as SwiftUI counts
it, so a stack, a layout, a grid or a list gets nothing from it, and nothing
from a frame, a padding, an `.id` or a `Group` around it, which reach their
content's members and find none (measured on SwiftUI, `layout1.out` case D:
each adds nothing to a `VStack`). A view of the app's own whose body is an
`EmptyView` is none too, and an overlay or a background on an `EmptyView`
draws nothing, as SwiftUI's does. Three shapes still draw what they did:

- **Drawn on its own**, not by a container (a sheet's whole content, a
  page's root), a padded or framed `EmptyView` is padding or a frame round a
  view that draws nothing. SwiftUI's was not measured there.
- **An effect modifier between** (`EmptyView().onAppear {}.frame(height:
  5)`): an effect wrapper does not hand its content's members on, since it
  must fire once, not once per member, so the frame frames one child.
- **A modifier on a view of the app's own whose body is a modified
  `EmptyView`** (`struct V { var body: some View { EmptyView().frame(height:
  5) } }`): the view is one child, as any view whose body is a modifier is
  (B-D1S-6).

**The fuller version** answers the first by drawing nothing for a wrapper
whose content statically has no members (a check on every such wrapper's
render, which needs its cost measured), the second by letting an effect
wrapper hand on an empty member list (it has nothing to fire for), and the
third with B-D1S-6. About half a day for the first two.
