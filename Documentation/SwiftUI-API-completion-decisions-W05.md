# Wave 5 (composition and layout): decisions for review

*Written by the worktree that implemented the Subviews, Sections,
ContainerValues and `Layout`-completeness half of Wave 5, to be folded into
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Same three parts: **A** needs your decision, **B** shipped the safe option,
**C** declined without asking. The SwiftUI behaviour quoted here was measured
on a SwiftUI build (the W05 probes), not read off the documentation.*

---

## B. Shipped the safe option

### B-W05.1 A `ForEach` row of several views is one subview, not several

*`Group(subviews:transform:)`, `ForEach(subviews:content:)`,
`SubviewsCollection`, `LayoutSubviews`, `SectionCollection`*

SwiftUI takes a multi-view row apart: `ForEach(0..<2) { _ in Group { a; b } }`
is four subviews, and so is the same row as a `TupleView`. It does not take
`AnyView(Group { a; b })` apart: that is one subview per `AnyView`.

TUIkit resolves one child per element everywhere — stacks, `List`, `Table`,
layouts — and the subview APIs inherit that, so the loop above is two
subviews here, and `HStack { ForEach(…) { Group { a; b } } }` stacks each pair
vertically inside the row. A row of one view, which is nearly every row, is
exact.

**The fuller version** flattens a row that is itself a provider of several
views. That changes `ForEach.makeChild` (one element → several children), the
lazy child collection (its count is no longer the data's count, so a lazy
stack's window over a million rows needs an index from element to first
child), the row memo (keyed per element today) and the identity keys (a
row's children need a step under the element's key). It is a resolver change
for every container, not a subviews change, and it needs an A/B on `fanout`,
`megalist` and `table`, the scenarios whose frames are mostly row
resolution. Two to three days with the measurement.

### B-W05.2 A `Section` is taken apart only by the subview and section APIs

*`Section`, `Group(subviews:transform:)`, `Group(sections:transform:)`*

SwiftUI flattens a `Section` in a stack into its header, content and footer,
as the subview counts show (a section of two views with a header and a footer
is four subviews). TUIkit's `Section` in a stack still draws as one unit, with
the dimmed, bold header styling it has in a `List`.

The subview and section APIs take sections apart as SwiftUI counts them, and
hand the parts over as written — no header styling — because there the
custom container decides how a header looks.

**The fuller version** makes `Section` a provider of its parts in every
container that is not a `List`, `Form` or `Table`. That moves the drawing of
every page with a sectioned stack, so it is its own commit with the Stress
self-check, and it needs a decision on whether a header outside a list keeps
any styling. Half a day.

### B-W05.3 A subview proxy does not pass on a spacer flag or an alignment guide

*`Subview`*

`Subview` is a view that draws its member. A container laying out
`ForEach(subviews: content) { $0 }` sees the proxy, which says nothing about
being a `Spacer` or carrying an `.alignmentGuide` — those are static
properties of the member's type, and the proxy is one type for every member.
A stack therefore gives a proxied `Spacer` the share a flexible view gets,
which is close to but not the same as a spacer's.

Placing the collection or a slice (`HStack { subviews }`) hands the members
to the container directly, flags and guides intact, and that is the shape
SwiftUI's own examples use. The fuller version reads the flags off the
member at run time wherever a container meets a `Subview`; it is a cast per
child on the stack path, so it would be gated behind a stored flag. Half a
day.

### B-W05.4 `SectionConfiguration.actions` is always empty

*`SectionConfiguration.actions`, `SectionConfiguration.Actions`*

Nothing in TUIkit can attach an action to a section yet: SwiftUI's
`sectionActions(content:)` is a gap with its natural home in Wave 8, where
`List` draws actions in section headers. So every section's actions are an
empty view, which is the truth. When `sectionActions` lands, `actions` must
start returning what it set.

### B-W05.5 A guide does not travel out of a view type of the app's own

*`View.alignmentGuide(_:computeValue:)`, `Layout.explicitAlignment(of:in:proposal:subviews:cache:)`*

SwiftUI resolves a guide recursively through everything between it and the
container aligning on it. TUIkit now does the same through `VStack`,
`HStack`, `ZStack`, `.padding` (each moving the guide by where it put its
content) and a custom `Layout` (`explicitAlignment`), which closes the gap the
compatibility notes
recorded: `.alignmentGuide(.decimalPoint)` on a `Text` inside each row of a
column aligns the rows on the point.

It stops at a view type of the app's own: a guide inside
`struct Row: View`'s `body` does not travel out of `Row`. A container decides
whether to ask a child about guides from a static witness
(`View._providesAlignmentGuide`), which the framework's containers now
forward from their content; an app's view states none, so it is not asked. It
also stops at any modifier that does not translate guides (`.border()`,
`.frame`, `.offset`): there a wrong position is the alternative.

**The fuller version** makes every composite view forward its `body`'s
witness by default (`Body._providesAlignmentGuide`, `false` for a `Never`
body), so the question reaches into every body type. The cost is where the
witness is read: `ChildView` construction, per child per walk, would recurse
through the child's whole static body type, not only the framework containers
in it. That is O(static subtree) per construction, which the per-pass measure
memo keeps to roughly O(nodes × depth) witness calls a frame — small on paper,
and exactly the kind of thing that has measured as a percent on `fanout` and
`deep` before. Half a day, plus an A/B on `deep`, `kitchensink`, `megalist`
and `table` on a quiet machine before it ships.

**A/B owed for what did ship.** The witness now forwards through `TupleView`,
`Group`, `ForEach`, `ConditionalView`, `Optional`, the three eager stacks and
padding, so constructing a `ChildView` for a container child ORs its
framework subtree's witnesses instead of reading one constant. A tree with no
guide still pays one stored `Bool` per child at layout time, as before; the
added cost is in the construction, and it was not measured (no benchmarks on
a shared machine). `deep` and `kitchensink`, the structure-heavy scenarios,
are the ones to A/B. One more: an app's own `Layout` cannot be known not to
override `explicitAlignment`, so inside a stack it is laid out once more per
walk to answer the stack's guide question (the framework's layouts state
`_definesExplicitAlignment = false` and are asked only when a subview may
hold a guide). Stress's `customlayout` scenario is the one to A/B for that.

### B-W05.6 A stack's `spacing: nil` is the default preference, not each pair's

*`HStack.init(alignment:spacing:content:)`, `VStack`, `LazyHStack`, `LazyVStack`,
`HStackLayout`, `VStackLayout`, `ViewSpacing`, `Layout.spacing(subviews:cache:)`*

The stacks now take SwiftUI's `spacing: Int? = nil` (it was `Int = 1` and
`Int = 0`), so `HStack(spacing: nil)` compiles. In SwiftUI, `nil` means "for
each pair of neighbours, the distance their `ViewSpacing`s ask for". Here
`nil` resolves, at `init`, to the distance two views of default preference ask
for — one column in a row, none in a column — and is used between every pair.

The two readings differ less than they sound. `ViewSpacing` has SwiftUI's
surface only: `init()` (one column beside, no row above or below), `.zero`,
and unions, which take per-edge maxima. So every preference a TUIkit view can
state is the default or less, edge by edge, and every vertical edge is 0.
Each pair's distance in a column is therefore always 0 — exact — and in a row
it is 1 unless BOTH neighbours are custom layouts whose
`spacing(subviews:cache:)` asks for no space on the facing edges. That pair
gets a column here and none in SwiftUI. A custom layout that spaces its
subviews by `LayoutSubview.spacing` does get the per-pair answer.

**The fuller version** resolves `nil` per pair inside the stacks: a stored
flag on `ChildView` saying the child can state a preference (it fits the
struct's tail padding), and per-gap spacings through
`distributeLinearSpace`, `totalLinearSpacing`, the assembly in both cores, the
lazy windows and the guide placement. That is a structural change to the
hottest layout path for a case that needs two zero-spacing custom layouts side
by side. A day, and the plan's rule applies: an A/B on `deep`, `kitchensink`,
`megalist` and `table` on a quiet machine before it lands. What shipped
changes nothing on the stack path — `nil` becomes the old constant at `init` —
so no A/B is owed for it.

### B-W05.7 `GridRow` outside a grid is its cells, not an `HStack`

*`GridRow`*

`GridRow`'s body was `HStack(alignment: alignment ?? .center, spacing: 1)
{ content }`, on the stated belief that SwiftUI degrades a row outside a grid
to a horizontal arrangement. The W05 probe refutes it: in SwiftUI
`VStack { GridRow { a; b } }` is pixel-identical to `VStack { a; b }` and
different from `HStack { a; b }`, and a custom `Layout` over two rows of two
sees four subviews. So this is a parity fix, not the reversal of a deliberate
deviation — but it moves pixels, so it is listed.

A row now hands its cells to the container around it, as a `Group` hands its
members, each marked so a grid still knows where one row ends and the next
begins. What changes for an app:

- A `GridRow` in a stack or a custom layout contributes its cells, not one
  row-shaped child. A `GridRow` drawn on its own stacks its cells vertically,
  as any run of views does.
- A `ForEach` of rows inside a `Grid` now lines its cells up in the grid's
  columns. Before, each looped row reached the grid wrapped in `ForEach`'s row
  memo, was not recognised as a row, and spanned the grid as one cell.
- A row with no cells at all (`GridRow { if false { … } }`) is no row.
  `GridRow { EmptyView() }` is still a row one line tall: an `EmptyView` is a
  child here.

**Residual:** a `ForEach` of rows is taken apart only by containers that lay
cells out — `Grid`, `GridLayout`, and the stack layouts `AnyLayout` switches
it with. In a `VStack`, an `HStack` or an app's own layout each looped row is
still one child (B-W05.1's multi-view row), drawn as its cells stacked
vertically.
