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

## A. Needs your decision

### A-LAYOUT-1. A column shares an overfull height only once a child's minimum is cheap to ask

*`VStack`, `VStackLayout`, `View.layoutPriority(_:)`; deviations, slated
"A column places its children of one priority in order" (L14, the column
half); your ruling of 2026-10-13, "follow SwiftUI"*

Not landed. The column half of L14 (47171484d) was reverted by 2400f2948 for
its A/B: `tables-vstack` +32%, `stateful` +34%, the table scenarios +11 to
+24%. The lane re-applied it and counted, rather than timed, what it does per
frame (`Stress --bench --cold`, a debug build, temporary counters, all
reverted):

| Scenario | Measure-memo lookups per frame, before → shared | Measures the memo could not answer, shared: elsewhere / in the minimum walk / in the squeezed child's sizing |
|---|---|---|
| `tables-vstack` | 242 → 684 | 2486 / 2486 / 2283 |
| `stateful` | 705 → 1263 | 5951 / 3916 / 33 |
| `table` | 15 → 39 | 165 / 143 / 121 |

The cause: sharing by flexibility needs every child's minimum, and a child's
minimum is its size offered no height. A column inside the child answers that
by asking each of its own children its minimum, which the measure memo cannot
serve (it keeps natural sizes, and a natural size does not answer an offer of
nothing), and so on down: the walk is as deep as the tree, every frame, for
any column taller than its space. Not a missing early exit: a column of
children all of one priority still shares by flexibility in SwiftUI, so the
walk is needed whenever the column overflows. `tables-vstack` also draws more
when shared, inherently: its eight tables in 40 rows each get a share and are
all drawn, where in order the first ones take the rows and the rest are not
drawn at all, so that scenario cannot come back to the base's time.

The options:

1. **Keep placing in order** (today). Free; the deviation stays slated, and a
   column cuts its trailing children where SwiftUI squeezes them all.
2. **Make the minimum cheap, then land** (recommended): a static witness for
   the views that shrink to nothing down the column — the clipping
   containers (`List`, `Table`, `ScrollView`) and a frame with no minimum —
   answers their minimum without a walk, and the measure memo keeps the
   answer to an offer of nothing beside the natural one, so a nested column
   asks each child once per change rather than once per frame. About two
   days, then the full A/B (the table scenarios, `tables-vstack`, `stateful`,
   `truncate`, `menus`); `tables-vstack` judged by what it draws, as above.
   The two drawing fixes the slated row names (a squeezed control of several
   lines in the middle of a column; the squeezed inline `Menu`, 45e860b55
   kept) come with it.
3. **Share only between children whose minimum is already known** (leaves,
   frames with a stated minimum), placing the rest in order: about a day,
   cheap at run time, but a third rule SwiftUI does not have, and a column's
   layout would change when a child's type changes.

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
- **A lazy stack gives up its window over such rows** (`StackUniformWindow`,
  `StackAnchoredWindow`): placing a row by its guide needs the whole run, so
  every row is built and measured on every walk, as it was before B19 for a
  row that set a guide itself. Only a row type that may report a guide of
  the kind the stack aligns on does: a stack of several views keeps its edge
  and centre guides (A-GUIDE-2), and the type says whether one can leave it
  (`mayReportEdgeOrCentreGuide(_:)`, kept per type). This entry recorded only
  the memo until the review, which found a row type holding an edge guide
  inside an `HStack` of two views costing a `LazyVStack` of 3,000 rows
  18,011 body evaluations to draw ten; it keeps its window again.
- **A stack around such a view asks it for its guide**, evaluating its body in
  a measure, where it answered nothing before — for an edge or centre guide
  only where the type says one can leave it, so a view whose guides all sit
  inside a stack of several views is not evaluated to ask.

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
themselves. Such a wrapper's content is asked for its guide in the context the
wrapper lays it out in (`SingleContentWrapper.wrappedContentContext(_:)`, the
one its measure hands its content), and a wrapper that has not said what that
is stops the guide. Asked in the wrapper's own context, the content answered
from a layout that is never drawn wherever the wrapper's environment changes
what it lays out: `HStack { Text("ßß"); Text("x").alignmentGuide(.mark) {
$0[.leading] } }.textCase(.uppercase)` placed the guide two cells in, where
the drawn row is `SSSSX` (found in review).

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

### B-LAYOUT-6. A frame's ideal is its size offered nothing across, not down

*`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`,
`.fixedSize(horizontal:vertical:)` (the owner's 2026-10-15 ruling,
"idealWidth: match SwiftUI")*

Shipped: offered no width, a frame with an ideal width is exactly that ideal
(`FlexibleFrameAxis.extentOfferedNothing(content:)`), its content offered the
ideal and placed in it by the frame's alignment, as SwiftUI's is (measured,
`layout1.out` case D2: `Text("short").frame(idealWidth: 10).fixedSize()` is
ten wide, the text at 2.5). "Offered no width" is the ideal-width ask, and the
drawing under `.fixedSize()` that follows it: `_FixedSizeView` sets
`EnvironmentValues.offeredNoWidth` for its content, beside the
`fixedSizeWidth` a `List` reads, and a frame with an ideal width reads it as
"offered nothing" and clears both for its own content, which it offers a
width (so a `List` inside such a frame no longer hugs). The flag goes where
SwiftUI passes an unspecified width on (measured,
`Tools/SwiftUIProbes/Flexible frames/ideal-placed.out`): through modifiers, a
row, `HStackLayout` and a stack of one view; a column or a `ZStack` of
several, `VStackLayout`, `ZStackLayout`, a `Grid` and an overlay's layer offer
their views a width as they place them, and clear it. It rides on the
container's axis entry, which every stack writes anyway, so a column clears it
for nothing and a row pays one read. The first version read `fixedSizeWidth`
itself, which reaches the whole subtree: `VStack(alignment: .leading) {
Text("abc").frame(idealWidth: 10, alignment: .trailing); Text(long) }
.fixedSize()` drew the frame ten wide where SwiftUI's, and the base's, is
its content's (found in review). Measure and render agree
(`FrameIdealOfferedNothingTests`).

**Not shipped: the height** (deviations L16). A TUIkit stack asks a child its
natural height with no height, so a frame answering its ideal height to that
ask would be laid out at its ideal in every column.

**The fuller version:** a measure-generation bit for "asks the ideal height",
set by `.fixedSize(vertical:)`'s probe and a vertical scroll view's content,
and an environment flag for the drawing that follows, as the width has. The
bit is the generation counter's (six bits are left), so the cost is a smaller
counter. About half a day. A horizontal `ScrollView` offers its content
nothing across too, in SwiftUI (measured: the frame is 10 there as well);
here its content is drawn without the flag, so a frame with an ideal width
in one is drawn as offered a width — not checked beyond that (an hour, with
a test). Setting the flag for a scroll view's content would also make a
`List` in it hug its rows, which wants its own look.

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
