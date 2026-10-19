# Default focus, drop badges and stack spacing: decisions from lane BITEMS1

*Lane BITEMS1, 2026-10-13, shipping decisions B35 (the automatic first-control
focus is nobody's until something happens to it), B10 (the drop-operation
badge) and B20 (a row's `spacing: nil` per pair of neighbours). The calls below
are the ones the owner's rulings left open. The format is that of the main
decisions file:*

- **A-BITEMS1-n — needs your decision.**
- **B-BITEMS1-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-BITEMS1-n — declined.** With the reason.

## A. Needs your decision

### A-BITEMS1-1. Should a `Spacer` prefer no spacing, as SwiftUI's does?

*`Spacer`, `ViewSpacing`*

Measured on SwiftUI (`distances.out`, `spacer|box`): a `Spacer`'s preference
is zero on every edge, so `HStack { Text("a"); Spacer(); Text("b") }` puts no
gap either side of the spacer — the spacer takes it all. TUIkit's `Spacer`
prefers the default like any view, so the row keeps one column either side.
Wherever the row has room the difference cannot be seen (the spacer absorbs
it); it shows where the row has none — at its ideal width, or squeezed — as
two columns more than SwiftUI's reading would give it (TUIkit's side not run
for this note).

- **(a) Keep TUIkit's.** A spacer's gaps stay as they are; documented as a
  deviation.
- **(b) SwiftUI's.** A spacer states `.zero`. Every `HStack` with a spacer
  then resolves its gaps per pair (B20's path): a static witness makes that
  cost nothing for rows without one, but rows with a spacer — common — would
  take the per-pair path every walk. Measured cost unknown (an A/B on
  `kitchensink`, `deep` and `table`), and every fixed-size row with a spacer
  narrows by two columns.

**Recommended: (a)** until the A/B prices (b); the visible difference needs a
spacer squeezed to its minimum.

**Decided 2026-10-13, owner: (b), follow SwiftUI** — "it seems to me that
it's trying to behave as if the spacer simply disappears if there's not
enough room for any of it … between two buttons it'll let the buttons spread
out, but it'll never *force* them to spread out." Measured the same day
(`Tools/SwiftUIProbes/Stack spacing per pair/spacer.out`): SwiftUI's
`Spacer()` is never shorter than the system spacing, 8 points, so
`HStack { box; Spacer(); box }` at its ideal width is 28, exactly
`HStack { box; box }`; with `spacing: 5` it is 38, the stated spacing kept
beside the spacer; squeezed, the spacer keeps its 8 points and the texts
beside it truncate. The note above was wrong about the cost: faithful, the
row with no room narrows by one column (from `a  b` to `a b`), not two, and
one with a stated `spacing` widens by one (a spacer of no `minLength` is a
gap long). Shipped: a spacer states `.zero`, so where a row's `spacing` is
`nil` the gap beside it is none; its default length is one default gap along
the axis — a column in a row, none in a column; and a row learns that its
spacers are its only children that state a spacing from their flags and
the views' static witnesses, so it casts nothing and allocates nothing.

## B. Shipped the safe option

### B-BITEMS1-1. A delete wears no badge, and only the item-provider drops propose one

*`DropOperation`, `DropProposal`, `View.onDrop(of:delegate:)`,
`View.dropDestination(for:action:isTargeted:)`*

The ruling of 2026-10-12 confirmed three glyphs: `+` for a copy, `↗` for a
link and `⊘` for a forbidden drop, with nothing for a move. Three things it did
not settle:

- **`.delete`.** The entry offered `×` (U+00D7, East Asian Ambiguous) or `✕`
  (U+2715, Neutral); neither was confirmed. **Shipped:** no badge, as for a
  move — the delete is still accepted, and the delegate's `performDrop` is
  where it means anything. **`.cancel`** wears none either: it proposes no drop
  at all, which macOS shows with a plain pointer (unmeasured here; drag and
  drop needs a window server an offscreen probe does not have).
- **TUIkit's other destinations.** `dropDestination(for:action:isTargeted:)`,
  a `List`'s or `Table`'s insertion and reordering, and a tab's drop zone
  propose no operation, so they wear no badge. SwiftUI documents no operation
  for `dropDestination`; on macOS it is believed to draw `+` (unmeasured).
  **The fuller version:** `dropDestination` proposes `.copy` and a reorder
  `.move` (which wears nothing anyway): one line in `DropDestinationModifier`,
  plus a decision on whether a TUIkit-only API should look like macOS's
  `Transferable` drop.
- **The destination's highlight.** The proposal said the drop target's
  highlight "can" shift colour to match. TUIkit draws no highlight for these
  views — the app draws its own from `isTargeted` — so there is nothing to
  shift. **The fuller version** would hand the app the proposed operation,
  which SwiftUI does not do either.

The badge sits on the preview's top-right cell, not beside it: the preview's
frame is what a `DropInfo` reports and what a cancelled drag walks home from,
and a cell beyond it would make the carried picture wider than that frame. It
hides the preview's corner cell while it shows. Precisely, it covers the last
cell of the top row, which is that corner for a rectangular preview, and
every row keeps its own width, so a ragged preview shows the page after its
short rows as it does unbadged. A top row of one cell wears the badge beside it, the one
place the picture grows by a cell: covering it hid a one-glyph drag whole.

### B-BITEMS1-2. A stated spacing edge outweighs a default one, as in SwiftUI

*`ViewSpacing`, `ViewSpacing.distance(to:along:)`, `ViewSpacing.formUnion(_:edges:)`,
`Layout.spacing(subviews:cache:)`*

B20's entry described TUIkit's `ViewSpacing`: a union takes each edge's larger
value, a distance the larger of the two facing edges, and `ViewSpacing()` is
one column beside a view. Probing SwiftUI for B20's fuller version
(`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`) found its
arithmetic is not that. `ViewSpacing()` is the DEFAULT, not a number: `.zero`
facing it is 0 apart either way round (TUIkit said one column), `.zero`
merged with it is still `.zero` (TUIkit said `ViewSpacing()`), and two views
are the default apart only when both facing edges are the default. So a
layout that asks for no space beside it gets none from a plain neighbour
either (`spacing.out`: a tight layout beside a box, 0 points).

**Shipped:** SwiftUI's arithmetic. An edge of `ViewSpacing()` is stored as
unstated (the smallest `Int`, so a merge is still `max` and a stated edge
always wins); `distance` answers the default — one column, no row — only
where both facing edges are unstated. `Layout`'s default
`spacing(subviews:cache:)`, and `GridLayout`'s, merge from the default rather
than from `.zero` (from `.zero` every layout would now answer `.zero`), and
answer `.zero` for a layout with no subviews, as SwiftUI's did. An `EmptyView`
member counts as none, as SwiftUI counts none: stating `.zero` for it, as this
shipped at first, let one `else { EmptyView() }` make a layout's whole merge
`.zero`. What moves
for an app: a custom layout that spaces its subviews by `LayoutSubview.spacing`
now puts no column between a plain view and a neighbour that states `.zero`;
`ViewSpacing().union(.zero, edges: .leading)` now asks for no space on its
leading edge, where it asked for the default before (no TUIkit spelling could
say that before).

**The alternative** is TUIkit's old arithmetic, which would have the stacks
of B20 keep a column between a plain view and a tight layout where SwiftUI
keeps none. It has no use but the old answer.

### B-BITEMS1-3. A row's `spacing: nil` per pair reaches layouts, and the wrappers that move no edge

*`HStack.init(alignment:spacing:content:)`, `LazyHStack`, `HStackLayout`,
`ViewSpacing`, `Layout.spacing(subviews:cache:)`*

**Shipped:** B20's fuller version, with B-BITEMS1-2's arithmetic: a gap is
the distance the pair's facing edges ask for wherever either neighbour states
a preference. A view states one when it is a `Layout`'s view, a `Subview`, or
inside a single-content wrapper — every modifier that wraps one view:
`.id`, `.tag`, `.onAppear`, the focus and gesture modifiers, `.foregroundStyle`
and the other environment modifiers, `.background`, `.border`, `.offset` —
except on the edges a wrapper moves its content off, where it states the
default: `.padding` on the edges it pads, a frame on the axis it sets a width
or a height on, and `.position` all round. Measured on SwiftUI
(`Tools/SwiftUIProbes/Stack spacing per pair/spacing.out`): +0 through `.id`,
`.padding(0)`, `.foregroundStyle`, `.background`, `.border`, `.offset` and
`.frame(height: 30)`; the default (+8) through `.padding(4)`,
`.frame(width: 40)`, `.frame(maxWidth: 40, alignment: .leading)` and
`.position`. A `.border` here takes a cell each side where SwiftUI's strokes
inside the view; the neighbour touches the ring either way, as SwiftUI's
touches the stroke. A frame that exactly fits its content agrees too: SwiftUI's
states the default on both sides (`all.frame|box` +8, `box|all.frame` +8,
measured 2026-10-13 after the review of ff7a14acc), as a frame that sets a
width does here. An earlier reading that it kept its content's preference
rested on `all.frame|all` +0, whose right neighbour is itself a layout that
asks for none: that +0 was the neighbour's. Where TUIkit differs:

- **`AnyView`.** SwiftUI's forwards what it erases (+0, measured with the
  erased layout on either side); here an `AnyView` states the default. Its
  static witness cannot say what it erases, and answering "may" for every
  `AnyView` would put every row of erased views on the per-pair path — the
  reason `fd5b3eb27` gave for not looking into an `AnyView` under a modifier
  for its container values. Pinned by `anyViewDoesNotForward`.
- **A view of the app's own whose body is a layout** (SwiftUI: +0) states
  the default: its body would have to be asked, which is B19's open
  question. One whose body is several views, a layout among them, is taken
  apart into them and asked, as are a `Section`, a `GridRow` and a subview
  collection: each forwards the static witness (a view of the app's own
  answers its body's), since the review of be3ee7385 found a row of them
  never asking. **A nested `HStack`** states the default too, where SwiftUI's
  states its children's preferences merged.
- **An app's own `BufferModifier`** (a TUIkit API with no SwiftUI
  counterpart) keeps its content's preference, as `.border` does; one that
  draws cells beside its content, as the Custom Views article's
  `QuoteModifier` does, puts a
  neighbour that asks for no space against those cells, as `.border`'s ring
  is. It has no way to say otherwise.
- **`.padding`** puts the default back on the edges it pads and keeps the
  others: measured for `.padding(4)` (the default) and `.padding(0)` (the
  layout's own); one-edge padding is unmeasured and follows the same rule
  edge by edge.
- **A lazy row's pinned sections** lay out their header, rows and footer at
  the row's default distance, as before.
- **A column** needed nothing: every vertical distance is 0 rows either way.

**Cost.** A row given a stated `spacing`, or whose content's type holds no
layout (`View._statesSpacingPreference`, a compile-time chain), asks no child
anything: it pays a gap value of three words per walk and an optional check
per gap (the refactor before this commit). That holds for `HStackLayout` and
`AnyLayout(HStackLayout())` too since the review of B20, which found them
asking every subview whatever their content: a layout's subviews carry their
content's witness (`LayoutSubviews.mayStateSpacing`). A row whose content may hold one
asks every child each walk — a few conformance casts through its wrappers,
and for a layout its `spacing(subviews:cache:)` over its resolved subviews —
and a lazy row asks every child, not only those its window reaches.

**The fuller version:** an `AnyView` that forwards (a static "may"
for every `AnyView`, so every row holding one takes the per-pair path: an
A/B on `anyview` and `kitchensink` first); nested rows stating their
children's merged preference (half a day, and it puts a row holding a nested
row of layouts on the per-pair path); app views' bodies, with B19; a
`BufferModifier` requirement naming the edges it draws beside; and a lazy row
asking only the children its walk reaches.

**Shipped 2026-10-18 (lane LAYOUT): app views' bodies and nested stacks.**
Measured first (`Tools/SwiftUIProbes/Stack spacing per pair/nested.out`): a
nested row's leading edge is its first child's and its trailing edge its last
child's (`HStack { HStack { tight; box }; box }` keeps the default gap after
the inner box, `HStack { HStack { box; tight }; box }` none); a column's
leading and trailing edges, and a `ZStack`'s every edge, are every child's
merged — but a spacer's "none" only along the stack's own axis (`HStack {
VStack { box; Spacer() }; box }` keeps the gap, `HStack { HStack { box;
Spacer() }; box }` does not); a lazy stack states nothing (the default gap);
and a view of the app's own states its body's through a stack, an `if`/`else`
and a padding.

- `View._statesSpacingPreference` defaults to the body's answer, asked once
  per type through `BodyWitnessMemo` as B19's guide witness is (so a recursive
  body ends, and a body that holds no layout states none, where the old
  default, `_handsOverChildren`, said "may" for every body of several views).
- `statedSpacing(of:context:)` looks into the body of a view of the app's own
  (evaluated as the walk evaluates it, at its identity), and through an
  `if`/`else` or an `if` to its live view.
- The eager `HStack`, `VStack` and `ZStack` state the edges their children
  form (`edgesFormed(by:along:context:)`), their witnesses their content's;
  `LazyVStack` and `LazyHStack` state none.

Still the default here, where SwiftUI's is not: an `AnyView` (the A/B on
`anyview` and `kitchensink` comes first, and was not run in this lane: no
benchmarks while other lanes build), an app's own `BufferModifier` (no
requirement yet names its edges), and a lazy row still asks every child, not
only those its window reaches. **A/B owed:** a row whose children's types hold
a layout now asks each child each walk, through its body where it is a view of
the app's own: `deep`, `kitchensink`, `table`, `customlayout`.

Since the review of that lane, a row asks a child only where the child's type
may state a preference on the edges a row reads, its leading and trailing ones
(`mayStateSpacing(_:along:)`, kept per type and axis): a column's are its
views' but a spacer's, so a view whose body is `VStack { …; Spacer() }` beside
a text — the commonest sidebar — is not asked. The witness alone said "may"
for any type holding a `Spacer`, and the row evaluated such a view's body once
more on every walk, and resolved its column, to find nothing.
