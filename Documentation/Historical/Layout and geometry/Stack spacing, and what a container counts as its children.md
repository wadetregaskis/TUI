# Stack spacing, and what a container counts as its children

*How a stack spaces its children (`spacing: nil` per pair of neighbours, a
`Spacer`'s zero preference) and how it decides what its children are: a
`Group`'s members, an `AnyView`, an `EmptyView`, a modifier on several views,
an app's own view whose body is several views, a loop whose rows vary. Ids:
B20, A-BITEMS1-1, B-BITEMS1-2, B-BITEMS1-3, B-LAYOUTPERF-2, B-LAYOUT-5,
B-LAYOUT-7, B-LAYOUT-8, B-D1S-3, B-D1S-5, B-D1S-6; S3-EMPTYVIEW-FRAME,
S3-NO-EXTENT-SPACING; deviations L9, L17.*

## In short

`HStack(spacing: nil)` resolves each gap from the two neighbours'
`ViewSpacing`s, with SwiftUI's arithmetic (a stated edge outweighs a default
one), and a `Spacer` prefers no spacing, as SwiftUI's does. To a container, a
`Group`, a tuple, a loop, an `if`, an `AnyView` that erases several views, a
modifier on several views and an app's own view whose body is several views
are all those views, as in SwiftUI; an `EmptyView` is none. What is still one
child is recorded: a modifier on an app's view whose body is several views, a
body that is an `AnyView` or an effect on several views, and an `AnyView` that
is a loop's row. One deliberate difference: a child with no extent takes no
spacing (L17, kept by the owner on 2026-10-26).

## The problem

TUI's stacks took a fixed `spacing: Int = 1` (rows) or `0` (columns), and
treated much of what SwiftUI takes apart as single children. Taking things
apart costs: a container that cannot tell from a type how many views a child
is must build every row, every walk, to count them — which a lazy stack exists
not to do. Every shape SwiftUI takes apart had to be weighed against that.

## How it unfolded

1. **Lane D1S** (after the owner's B15, B16, B17 and A44) taught containers
   to take apart sections, `AnyView`s, loops whose rows vary and app views
   whose bodies are several views, keeping one child wherever counting would
   cost every row (B-D1S-3, B-D1S-5, B-D1S-6).
2. **2026-10-12, B20.** `spacing: nil` compiled but was a constant. The owner,
   advised against the per-pair version, asked for it "mindful of
   performance".
3. **2026-10-13, lane BITEMS1** built it with a static witness so rows with no
   layout ask nothing (B-BITEMS1-3), found SwiftUI's arithmetic differs from
   the design (B-BITEMS1-2), and asked about `Spacer`: the owner chose
   SwiftUI's zero preference (A-BITEMS1-1) — "it'll never *force* them to
   spread out".
4. **2026-10-18 to 19, lanes LAYOUT and LAYOUTPERF.** `EmptyView` became no
   member (the owner's settled S3-EMPTYVIEW-FRAME, B-LAYOUT-5); the value and
   trait wrappers hand a group's members on (B-LAYOUT-7); a body that is an
   `if`/`else` or a modifier on several views is those views (B-LAYOUT-8);
   the spacing witness stopped evaluating framed columns (B-LAYOUTPERF-2).
5. **2026-10-26, S3-NO-EXTENT-SPACING.** SwiftUI spaces a child of no extent
   like any other; the owner kept TUI's rule that it takes no gap, recorded as
   deviation L17.

## Where it stands

Shipped. The cases still one child, and why, are in B-LAYOUT-8 and B-D1S-6.

## For a future reader

- **The counting cost is the constraint.** Every "still one child" here exists
  because counting it would build every row on every walk. B-D1S-5's fuller
  version (an element-to-first-child index kept while the data is unchanged)
  would lift several of them at once; it is about a day plus an A/B.
- **A/Bs owed**: the provider conformance of `AnyView` (`anyview`, `deep`,
  `modifiers`), B-D1S-6's landing (`fanout`, `deep`, `kitchensink`,
  `megalist`, `anyview`), and B-LAYOUT-8's witness reads.
- **An `EmptyView` drawn on its own** (a sheet's whole content) with padding or
  a frame is still padding round nothing; SwiftUI's was not measured there.

## The record

### B20. A stack's `spacing: nil` is resolved per pair of neighbours

*`HStack.init(alignment:spacing:content:)`, `VStack`, `LazyHStack`, `LazyVStack`,
`HStackLayout`, `VStackLayout`, `ViewSpacing`, `Layout.spacing(subviews:cache:)`*

The stacks now take SwiftUI's `spacing: Int? = nil` (it was `Int = 1` and
`Int = 0`), so `HStack(spacing: nil)` compiles. In SwiftUI, `nil` means "for
each pair of neighbours, the distance their `ViewSpacing`s ask for". Here
`nil` resolves, at `init`, to the distance two views of default preference ask
for — one column in a row, none in a column — and is used between every pair.

The two readings differ less than they sound. `ViewSpacing` has SwiftUI's
surface only: `init()` (one column beside, no row above or below), `.zero`,
and unions, which take per-edge maxima. So every preference a TUI view can
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

**Decided 2026-10-12: attempt the fuller version, mindful of performance.**
(You asked for an example on 2026-10-04; on 2026-10-05 I gave
`HStack { MyLayoutA(); MyLayoutB() }`, both asking for no space on the facing
edges, and advised against it. Your ruling overrides that.) **Lane owed** (shipped
2026-10-13, below): 2–3 commits and an A/B on `deep`, `kitchensink` and `table`
(`megalist` with B19's caveat). The shape that keeps the common path as it is (estimate): a
static witness, "states a spacing preference", true only for `Layout`-backed
views and their forwarding wrappers; a per-stack flag set while children are
built; and per-gap distances only where two neighbours both state one.

**Shipped 2026-10-13 (BITEMS1):** `HStack`, `LazyHStack` and `HStackLayout`
resolve `spacing: nil` per pair of neighbours, so `HStack { MyLayoutA();
MyLayoutB() }`, both asking for no space on the facing edges, draws them
touching. Probing it found SwiftUI's `ViewSpacing` arithmetic is not the one
this entry describes: a stated edge outweighs a default one, so ONE
neighbour asking for none is enough (`Tools/SwiftUIProbes/Stack spacing per
pair/spacing.out`). That shipped first, as
[B-BITEMS1-2](#b-bitems1-2-a-stated-spacing-edge-outweighs-a-default-one-as-in-swiftui),
and a gap is the pair's wherever either neighbour states a preference. The
shape is the estimate's: a static witness, `View._statesSpacingPreference`
— true for a `Layout`'s view and a `Subview`, forwarded by `ForEach`,
`Group`, `if`, `Optional` and the single-content wrappers (the environment
modifiers, `.background`, `.border` and `.offset` among them, as SwiftUI's
measured), and by padding and a frame on the edges they leave alone — read
once per row, so a row whose content holds no layout asks no child anything;
and `StackGaps`, which carries no preferences on that common path. A column
needed nothing: every vertical distance is 0 either way. Where it differs from
SwiftUI (an `AnyView`, an app's own view whose body is one layout, a nested
row) and the cost are in
[B-BITEMS1-3](#b-bitems1-3-a-rows-spacing-nil-per-pair-reaches-layouts-and-the-wrappers-that-move-no-edge).
The A/B at the landing (2026-10-13, against the batch before it, the machine not quiet, so
indicative) was neutral: the largest change `table-tail` +1.4% cold, several
scenarios 0.5 to 1.0% faster; the stripped binary grew 33,776 B.

### A-BITEMS1-1. Should a `Spacer` prefer no spacing, as SwiftUI's does?

*`Spacer`, `ViewSpacing`*

Measured on SwiftUI (`distances.out`, `spacer|box`): a `Spacer`'s preference
is zero on every edge, so `HStack { Text("a"); Spacer(); Text("b") }` puts no
gap either side of the spacer — the spacer takes it all. TUI's `Spacer`
prefers the default like any view, so the row keeps one column either side.
Wherever the row has room the difference cannot be seen (the spacer absorbs
it); it shows where the row has none — at its ideal width, or squeezed — as
two columns more than SwiftUI's reading would give it (TUI's side not run
for this note).

- **(a) Keep TUI's.** A spacer's gaps stay as they are; documented as a
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

### B-BITEMS1-2. A stated spacing edge outweighs a default one, as in SwiftUI

*`ViewSpacing`, `ViewSpacing.distance(to:along:)`, `ViewSpacing.formUnion(_:edges:)`,
`Layout.spacing(subviews:cache:)`*

B20's entry described TUI's `ViewSpacing`: a union takes each edge's larger
value, a distance the larger of the two facing edges, and `ViewSpacing()` is
one column beside a view. Probing SwiftUI for B20's fuller version
(`Tools/SwiftUIProbes/Stack spacing per pair/distances.out`) found its
arithmetic is not that. `ViewSpacing()` is the DEFAULT, not a number: `.zero`
facing it is 0 apart either way round (TUI said one column), `.zero`
merged with it is still `.zero` (TUI said `ViewSpacing()`), and two views
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
leading edge, where it asked for the default before (no TUI spelling could
say that before).

**The alternative** is TUI's old arithmetic, which would have the stacks
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
asks for none: that +0 was the neighbour's. Where TUI differs:

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
- **An app's own `BufferModifier`** (a TUI API with no SwiftUI
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

### B-LAYOUTPERF-2. A frame, a padding, a position and a `ZStack` say by type whether they may state a spacing

*`.frame`, `.padding`, `.position`, `ZStack`, `HStack(spacing: nil)`;
decisions B-BITEMS1-3*

Shipped: each answers `mayStateSpacing(_:along:)` from its type
(`SpacingReaching`) — a frame and a padding their content's answer, a
position never, a `ZStack` any non-spacer layer's — where the generic
reading said "may" for every view that states a preference itself. A row of
framed columns (`framedcolumns`) asked each column its spacing on every
pass, evaluating its body to find the default: `StackGaps.init` 4.1% of the
frame, now 0.1%.

**The fuller version:** an answer per instance, so a frame that sets a width
is known to state nothing on its leading and trailing edges whatever its
content holds (a framed custom `Layout` beside a row's other views is still
asked). It needs the child to carry a value-level answer beside its type's;
not wanted by any scenario measured. About half a day.

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

### B-LAYOUT-7. A modifier on several views reaches each through the value and trait wrappers, not the effect ones

*`.badge`, `.tag`, `.containerValue`, `.zIndex`, `.layoutValue`,
`.layoutPriority`, `.position`, `.help` (the S3-WRAPPERS item)*

Shipped: `_TaggedView`, `_ZIndexView`, `_LayoutValueView`, `BadgeModifier`,
`PositionView` and `HelpModifier` hand a `Group`'s or a loop's members on to
the container, each member inside a copy of the wrapper
(`ContentRewrapping`), as the environment, paint and geometry wrappers
already did: `HStack { Group { a; b }.badge(2) }` lays `a` and `b` side by
side, where it drew `a` over `b`, and `ZStack { Group { a; b }.zIndex(1); c
}` lifts both over `c` (`GroupRenderTests`, `HelpOnGroupTests`). A member
rewrapped in a z-index or layout-value wrapper takes the wrapper's value
(`ChildView.rewrapped(by:)`), which it kept from before the wrapper until now.

Kept opaque, by judgement: the effect wrappers, which SwiftUI fires once on a
`Group` of several (measured: `.onAppear` fires once on a two-member `Group`,
semantic audit item 50), so handing
each member a copy would fire the effect per member; the presentation and
list-row traits, which a container reads through a wrapper list of its own;
`.toolbar`, `.transition`, `.coordinateSpace`, the preference writers and
`.gradientExtent(.subtree)`, each of which means something different per
member than once.

**The fuller version** distributes the effect wrappers' layout while firing
their effect once: the members reach the container as separate children, and
the effect is put on exactly one of them. About a day, with a test per effect
wrapper that the effect fires once.

### B-LAYOUT-8. A body that is an `if`/`else` or a modifier on several views is those views; a modifier on such a view is still one child

*`View`, `HStack`, `Layout`, `List`, `Group` (the settled question B-D1S-6,
option 2)*

Shipped: a view of the app's own whose body is an `if`/`else` with an arm of
several views, or a modifier on several views that hands each member a copy
of itself (`Group { a; b }.padding()`, `.frame`, `.opacity` — the thirty
wrappers of the compatibility guide §3, and `ModifiedView`), is those views to
a container, as SwiftUI's is (measured,
`Tools/SwiftUIProbes/Sections and subview counting/composite-bodies.out`:
`if flag { a; b } else { c }` as a body lays `a` and `b` along an `HStack`,
and `Group { a; b }.padding(.leading, 5)` pads each). `_handsOverChildren`
answers through an `if`/`else`'s arms and a modifier's content, and a view of
the app's own asks it once per type and keeps the answer
(`BodyWitnessMemo`), as the guide witness does since B19: an arm can hold
the view's own type (`CompositeMembersTests`). An `if`/`else` of one view
each — `TextField`'s body — still answers `false`, and is never evaluated to
find out. One of one view and an `EmptyView` (a `switch` whose `default` is
one, too) is one view or none, as an `if` is, and a loop places such a row
whole, as it places an `if`'s (`staticRowMemberCount`): counted as its arms
disagree, a lazy stack of 3,000 of them evaluated 9,000 row bodies to draw
ten (found in review; an `if` takes 71).

Not shipped:

- **A modifier on such a view** (`Rows().padding(3)`): SwiftUI pads each of
  the body's views (measured: `a` at 5, `b` at 30); here the padded view is
  one child. Taking it apart evaluates `Rows`'s body where the walk meets the
  modifier, which must be in the context the modifier gives its content
  (`Rows().disabled(true)`), so that a body that reads `@Environment` to
  choose its views chooses them as drawn whole.

**A defect found on the way, fixed after review:** the wrappers that hand a
`Group`'s members on resolved them in the context they were given, so a view
of the app's own among the members had its body evaluated without the value
the wrapper publishes: `HStack { Group { LabelledPair() }
.environment(\.memberLabel, "set") }`, whose body is `Text(label);
Text("x")`, drew `unset x`. Taking apart more shapes (an `if`/`else` with an
`EmptyView` arm or an arm of several, a modifier on a group) exposed more
bodies to it, and one choosing its views by the value could choose the wrong
arm — an `EmptyView`, so the view vanished. A wrapper now says what context
it lays its content out in (`SingleContentWrapper.wrappedContentContext(_:)`, the
one its measure hands its content; `nil` where it has not said), and its
content's members are resolved there, at the wrapper's own identity
(`membersContext(_:)`): the environment, style, tint, disabled, theme,
redaction, transaction, selectability, animation, badge and help wrappers
say (`CompositeMembersTests.takenApartUnderAnEnvironmentWrapper`).
- **A body that is an `AnyView`** (SwiftUI: several, measured): an `AnyView`'s
  type says nothing of what it erases, and answering "may" for every one
  would evaluate each such view's body in the walk.
- **A body that is an effect on several views** (`Group { a; b }.onAppear
  {}`): one child, its effect fired once (B-LAYOUT-7). SwiftUI lays the views
  out apart and fires it once (measured).
- **A list's row placement** is told nothing new: the rows of a loop in such
  a view, beside other rows in a `List`, are selected by the hand-written rule
  (D1S).

**The fuller version:** with the wrappers' content context in place (the
defect above), a wrapper over
such a view hands on the view's members, each in a copy of the wrapper, and
the static counts (`staticMemberCount`, the row counts, `mayHandOver`, a
loop's row shape, the keyed row runs, `List`, `Form`, `Section`) are taught
the same. About a day and a half, with a test per site. `AnyView` bodies:
about two hours, plus an A/B on `anyview` and `kitchensink`.

**A/B owed:** the witness now reads a kept answer for each child of a
composite type, as the guide's does; with B19's arms, on `fanout`, `deep`,
`kitchensink`, `megalist`, `anyview` and `table`.

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
lose its row memo, and a lazy stack of erased rows its window. So does one in
an arm of an `if`/`else` that is the row, or under an `if` that is
(`ConditionalView.staticRowMemberCount`, `Optional.staticRowMemberCount`):
`.border()` is `if width <= 0 { self } else { AnyView(rings) }`, and counted as
spliced every bordered row was built and taken apart on every walk, its row
memo never consulted (`modifiers`, 2026-10-06: 1,611 measures a frame to
22,412, no row served). Spliced, a bordered view counted as unknown too, so a
row of several views with one bordered — `Text(a); Text(b).border()` — was
`.varying` where it counted two before (a lazy stack of such rows lost its
window); the rings are handed over as `_BorderRings` now (follow-up FU3), an
`AnyView` under a type that counts one, so a bordered view counts as one
wherever it is spliced, and the rings stay erased.

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
carries (`FlattenedRowIDs`), between the loops beside it wherever those can
still be placed (`KeyedRowTiling`). Only a key's spelling tells two such loops
apart where they sit side by side in one slot (in one `Group`): when the
first ends on an id spelled as the second's first, the first takes that row —
wherever they sit, after a view of the app's own whose rows the placement
cannot see into too, where the placement `KeyedRowTiling` replaced gave the
row to the second.
An `if` without `else` around ONE view that is the row's only view stays one
child, empty when false, as before, where SwiftUI counts none: no stack draws
or spaces an empty child, and a `Layout` counts it. So does one in an arm of
the row's `if`/`else`, an `if` around what a loop places whole as one — an
`AnyView`, a bordered view (B-D1S-3) — and an `if`/`else` whose arms are each
such a row. Counting it as it is
spliced would build every row of a loop that filters its elements with an
`if` — a common shape — to learn which are there.

**The fuller version.** An index from element to first child, built once and
kept across frames while the data is unchanged (the loop's `listRowsSignature`
already says when it is), so a lazy stack over varying rows is O(window) after
the first frame. A day, with an A/B on `megalist` shaped with such rows.

### B-D1S-6. A modified view of the app's own, or one whose body is an `if`/`else`, is one child

*`View`, `Group(subviews:transform:)`, `HStack`, `Layout`, `List`, `Form`,
`Picker`, `View.alignmentGuide(_:computeValue:)`*

A view of the app's own whose `body` is several views is now, to the container
resolving it, those views, as SwiftUI's is (measured,
`Tools/SwiftUIProbes/Sections and subview counting/composite.swift`):
a tuple, a loop, an `if` (none while false), a `Group` of those or a `Section`
as a body is taken apart — one inside another, and a loop of them, too — with
the view's `@State` bound at its own identity and every view of its body at
the identity it had drawn whole (`compositeMembers(of:context:)`, gated by the
static witness `View._handsOverChildren`, a few witness calls down the chain of
`body` types). Every container that resolves its content as views takes it
apart: the stacks and lazy stacks, `ZStack`, a `Layout`, `Grid` and the lazy
grids, `ViewThatFits`, the split views, a menu's items, a `List` and its
sections, the subview and section APIs; and a `Form` reads through it
(measured, `Tools/SwiftUIProbes/Sections and subview counting/formcomposite.swift`), evaluating its body in its walk. A
`Picker`'s options and a text field's suggestions are read by walks of their
own that see nothing in such a view, as in any view of the app's own. Four
shapes are still one child:

- **A modifier on such a view** (`Rows().padding(3)`): SwiftUI applies it to
  each of the body's views (measured: two subviews, each padded). The modified
  view is no provider here, as a modifier reaches members only through a
  provider it wraps.
- **A body that is an `AnyView`**, or an effect on several views
  (`Group { a; b }.onAppear {}`), is one child. *Since 2026-10-19 (lane
  LAYOUT, decisions B-LAYOUT-8) a body that is an `if`/`else` with an arm of
  several views, or a modifier on several views (`Group { a; b }.padding()`),
  is taken apart:* an `if`/`else` answers the witness with its arms, so one
  of a view in each arm — `TextField`'s body — still answers `false` and is
  never evaluated to find out.
- **In a `List` beside other rows**, the rows of a loop in such a view are
  drawn as rows but selected and edited by the hand-written rule (their tag,
  else their place): a list's row placement cannot see into a body without
  evaluating it (`KeyedRowRun.opaque`). It costs only its own rows that: the
  loops beside it are placed slot by slot, and one whose body holds no loop
  (a heading of two views) is no run at all. A section of the app's own there
  is a section, its loop's rows selected by element and deletable.
- **An alignment guide on one of its views** is honoured by the container
  that takes it apart, and since 2026-10-18 a stack around that container is
  told a guide is inside, as SwiftUI's is: a view of the app's own answers
  `_providesAlignmentGuide` with its body's answer (decisions B19).

**The fuller version.** `ModifiedView` (and the wrappers that hand a provider's
members their modifier) answering for content that is such a view — a
provider conformance that holds for a content TYPE only a witness can name, so
a forwarding conformance on every wrapper; the placement told a view's body
when the walk evaluates it; `_providesAlignmentGuide` forwarded from such a
view's body, with the guide query following it there; and the `Picker` and
suggestion walks given a context to evaluate bodies in, as the `Form`'s now
has. Two or three days. A/B owed for what landed:
`fanout`, `deep`, `kitchensink`, `megalist`, `anyview`.
