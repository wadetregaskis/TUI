# Sharing space: overfull columns and ideal sizes

*How a stack shares out space it does not have enough of, and what a frame
with an ideal size answers when it is offered nothing. Ids: A-LAYOUT-1,
B-LAYOUT-6; deviations L14 (rows), the slated column half, L16.*

## In short

A stack shares its length among children of one priority by flexibility, as
SwiftUI's does: a row since 2026-10-13 (L14), a column since 2026-10-27, once a
column's minimum height was answered without measuring it (A-LAYOUT-1; the
first attempt cost up to +34% and was reverted). A frame with an ideal width is exactly that wide
when offered no width; the ideal height is not yet honoured (L16).

## How it unfolded

1. **2026-10-13, the owner: follow SwiftUI.** Rows shared their width that day
   (L14). The column half (47171484d) followed and was reverted (2400f2948) for
   its A/B: `tables-vstack` +32%, `stateful` +34%, the table scenarios +11 to
   +24%.
2. **2026-10-15, the owner on ideal sizes: match SwiftUI.** Lane LAYOUT
   (2026-10-18) shipped the ideal width (B-LAYOUT-6) and counted, rather than
   timed, why the column was slow: every overfull column asks each child its
   minimum, down the whole tree, every frame, and the measure memo cannot
   serve a minimum (A-LAYOUT-1).
3. **2026-10-18, A-LAYOUT-1** was put to the owner with three options
   (recommended: make the minimum cheap, then land, about two days). It was
   never answered, and has been on the open-decisions page again since
   2026-10-26.
4. **2026-10-27, the owner: optimise, then decide.** A column offered no
   height answers none, so its minimum needs no measure; answering it so took
   `stateful` from +35% to +1.5%, and the column half landed (below).

## Where it stands

Rows and columns share; the ideal width is SwiftUI's, the ideal height not.

## For a future reader

- **A column's minimum height is free only because a column clamps to its
  offer.** A container that stops doing so (one that reports its content's
  full height offered nothing) must leave `ClampsHeightToOffer`, or the column
  around it will squeeze it below what it draws.
- **That minimum is a lie wherever a column has room.** Taken at its word
  beside a child that fills, a column of fixed rows was dealt half a stack
  that could hold it whole, and a `ScrollView`'s page lost the Colors page's
  mesh block (2026-10-28, #10). So a column asks minimums only when it is
  overfull; with room for everyone, fixed children keep their natural
  heights (`fitsAtNaturalHeights`, deviation L18).
- **`tables-vstack` will never return to the base's time** when shared: it
  draws all eight tables where in order it drew the first few (+7.5%). Judge it
  by what it draws.
- **The ideal height** needs a measure-generation bit (six are left) and a
  flag for the drawing, as the width has; about half a day.

## The record

### A-LAYOUT-1. A column shares an overfull height, its children's minimums answered cheaply

*`VStack`, `VStackLayout`, `View.layoutPriority(_:)`; deviations, slated
"A column places its children of one priority in order" (L14, the column
half); your ruling of 2026-10-13, "follow SwiftUI"*

**Landed 2026-10-27** (the owner, that day: "optimise it this time", then
decide). The cost was the minimum walk below; two changes removed it, neither
of them option 2's memo:

- **A column's minimum height is answered without measuring it.** Offered no
  height a `VStack` answers none, whatever it holds, because it clamps its
  children's total to its offer; so `minimumLength` returns its stated minimum
  (a frame's `minHeight`, or 0) for any `ClampsHeightToOffer` view: a `VStack`,
  and a `.environment(_:_:)` around one. That walk was 23.8% of a `stateful`
  frame once shared (profile, `minimumLength` inclusive); after it, `stateful`
  went from +35.1% to +2.5%.
- **A `Table`'s height is flexible** (it was reported rigid, so a column never
  offered it less): a separate commit, which lets the shared column squeeze a
  table as SwiftUI's does instead of placing it whole.

The final A/B against main (`ab_bench.py`, 4.5 s × 10, paired, 95% CI):
`tables-vstack` +7.5% (inherent, below: all eight tables now draw),
`stateful` +1.5%, `table-churn-wrapped` +0.8%, `kitchensink` +1.1%; every
other scenario indistinguishable. Within the owner's tolerance (a few per
cent), and `tables-vstack` is judged by what it draws.

What follows is the record from before the ruling. The column half of L14
(47171484d) was reverted by 2400f2948 for
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

**Not shipped: the height** (deviations L16). A TUI stack asks a child its
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
