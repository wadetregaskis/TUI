# Drawing past a region

*How TUI came to draw a view outside the space it was given — a guided view
past its frame, an overhanging run, content larger than its frame, an
`.offset` or a transition's overshoot — in SwiftUI's stacking order, and which
containers still cut it. Ids: B-GUIDE-1, B-GUIDE-3, B-GUIDE3-1, B-GUIDE3-3 to
5, B-LAYOUTPERF-3; deviations L5, L6, L15.*

## In short

SwiftUI clips nothing by default: a view drawn past its frame shows over the
views before it and under the views after it. TUI clipped every view to its
space as a safety net. Since 2026-10-12 one mechanism, the overflow layers
first built for `scrollClipDisabled`, draws whatever a placement puts past a
region: a guided child, an overhanging run, `.fixedSize()` text or a natural
size image larger than its frame, an `.offset` or `.position` view, a
transition's overshoot — each in the stacking order, its hit regions with it.
Scroll views, `.clipped()`, lists, a table's cells and surfaces (menus,
sheets, dialogs) cut it at their box; a border, a footer and a box's rules
are drawn over it.

## The problem

A cell holds one glyph, so overflow hides what is under it completely; and
every TUI container assumed that a buffer is exactly its reported size. So
"draw past the region" needed a way for content to leave a region without
changing what containers report, and a rule for who cuts it.

## How it unfolded

1. **2026-10-12, lane GUIDE.** A single guided child was held inside its
   region (B-GUIDE-3) and an overhanging run kept its leading edge
   (B-GUIDE-1), as the safe options. The owner, asked, disliked forced
   clipping (a bouncing scale-in, say): "Try to support it. If you run into
   significant issues, let me know and we'll discuss."
2. **2026-10-12, lane GUIDE3** generalised `scrollClipDisabled`'s overflow
   layers into the one mechanism (B-GUIDE-3 shipped), drew B-GUIDE-1's
   overhang with it, decided which containers cut overflow (B-GUIDE3-3), and
   — after review — drew borders and footers over it (B-GUIDE3-5).
3. **2026-10-18, lane LAYOUT** extended it to content larger than its region
   (`.fixedSize()`, an image at its natural size: B-GUIDE3-1 parts 1 and 2)
   and to `.offset` and `.position` (B-GUIDE3-4, closing L6's old float over
   every sibling).
4. **2026-10-19, lane LAYOUTPERF** made the cut under a later view read only
   the lines the overflow reaches (B-LAYOUTPERF-3).

## Where it stands

Shipped, with one part deferred: a fixed `.frame(width:)` still squeezes to
its offer (L5), because making it keep its width changes every container's
contract (B-GUIDE3-1 part 3, priced at 1.5 to 2.5 weeks).

## For a future reader

- **Deferred, large: containers reporting the size their content needs** past
  the proposal (SwiftUI's model). B-GUIDE-1, B-GUIDE3-1 part 3 and B-GUIDE3-5
  all point at it. Everything here works around its absence.
- **`List` and `Table` rows on macOS were never measured for overflow**
  (AppKit rows); an hour if it matters (B-GUIDE3-3).
- **A bounce past a surface's edge** while a guided view stays inside would
  need a second kind of overflow layer (B-GUIDE3-3's fuller version).
- **`kitchensink` still copies environments** about 0.9% of a frame across a
  dozen writers that could skip unchanged writes (B-LAYOUTPERF-3).

## The record

### B-GUIDE-1. A region smaller than the run keeps the run's leading edge on its own

*`AlignmentGuideRun.resolve`: a `.frame` or `.overlay` narrower than its
content, a column a flexible child fills, a lazy column's window*

SwiftUI's rule, measured, is that each view sits at `max(guides) - its guide`
and the stack is as big as that needs. TUI now places a run so, and when the
region is bigger than the run, moves the run as a whole toward the region's own
guide only as far as all of it still fits: `anchor = min(max(M, regionGuide(E)),
M + room)`, where `room = max(0, E - contentExtent)`.

The brief wrote the room without the `max(0, …)`. That differs only for a
region SMALLER than the run, where it would move the run back so its far edge
met the region's — a leading-aligned column then lost the alignment of every
row whose base is less than the overhang, where today it loses only the rows
that overhang. With the `max`, a run in a region too small for it keeps its
leading edge on the region's, as a `.leading` run always did, and the per-child
clamp pulls back only the views that would fall outside, as before.

**The fuller version** is SwiftUI's: the stack reports the size the run needs,
past its proposal, and the parent places and clips it. Measured: in a 400-point
host, `VStack(alignment: .trailing)` holding a 3-wide view with trailing guide
0, a 6-wide view and a view with `maxWidth: .infinity` is 403 wide, the
flexible view at 0 and the 3-wide one at 400. **Price:** every TUI container
holds its report to its proposal ("never advertise a size larger than the
constraint", `_VStackCore.sizeThatFits`), and the parent's buffer is the size
it reported, so this is a change to every container's contract, not to the
guide run.

**2026-10-12, answered: keep the safe option for now.** The case arises only
when an explicit guide pushes a view past the widest child and the region
cannot grow (a child that fills it, a fixed `.frame`, or the screen). Measured:
`GGG` sits three cells left of where its guide puts it. Changing what
containers report would take 1.5 to 2.5 weeks (estimate) and risk every
layout; drawn as an overflow layer, B-GUIDE-3's mechanism, it is about a day
more than that mechanism.

**Shipped (2026-10-12, lane GUIDE3): the overflow-layer version.** A run of
explicit guides larger than a region that cannot grow — a column a flexible
child fills, a lazy column's window, the space a `VStack`, `HStack`, `ZStack`
or lazy stack was given — keeps every guide on one line (`AlignmentGuideRun.resolve`
with `holdsChildrenInside: false`), and what hangs past the region's edge is
drawn past it through B-GUIDE-3's mechanism
(`FrameBuffer.placedHorizontallyDrawingOverhang`, its vertical twin, and the
`ZStack`'s split): under the views after the stack, cut by a scroll view
around it, off the screen where the edge is the screen's. Measured above,
`GGG` now sits at 20 with its guide on the line, drawn past a 20-wide column
(`PlacementOverflowTests`). What the stack reports is unchanged — the
proposal, not SwiftUI's 403 — so a sibling after it is placed where it always
was and draws over the overhang. A measure pass places nothing past the
region, and a stack reporting a guide out of itself reports it from where it
is drawn. Each child is padded to the region, never to the run, on a measure
pass too, so a push under the 2^20 bound does not build a line (or a column of
blank rows) that long every frame (review of the lane, 2026-10-12).

### B-GUIDE-3. One child whose guide would put it outside its region is held inside it

**Owner, 2026-10-12 (second message):** "Try to support it. If you run into significant issues, let me know and we'll discuss."
Lane owed: generalise `scrollClipDisabled`'s overflow layers so a single child, a guide placement, fixed-size content
and a move/offset bounce can draw past their region in SwiftUI's stacking order, while lists, tables, menus, sheets and
scroll views keep clipping (session notes `GUIDE2/notes.md` §5).

*`.frame(width:height:alignment:)`, `.overlay(alignment:content:)`,
`.background(alignment:content:)` — `horizontalGuidePlacement`,
`verticalGuidePlacement`*

Measured (`Tools/SwiftUIProbes/Alignment guides/guide2.out`, `guide5.out`): SwiftUI places a single
child so its guide meets the region's, wherever that puts it. In
`.frame(width: 20, alignment: .leading)` a 6-wide view with leading guide 5 is
at -5, with guide 25 at -25; with `.trailing` and guide 0 it is at 20, past the
frame's far edge; an `.overlay` or `.background` on a 20-wide view does the
same, and `.frame(height:alignment: .top)` likewise down the column. SwiftUI
does not clip a frame, so the child draws outside it.

TUI places the child at the nearest position to SwiftUI's that keeps all of
it inside the region — `min(max(0, x), extent - size)` — as it places a child
wider than its region (`childOffset(childWidth:in:)`), so the six-cell view is
drawn whole. Before this lane's two fixes the guide was first held to the
view's own size, so a trailing guide of 25 put the view at 8 instead of 0;
every other measured placement is unchanged
(`AlignmentGuideContainerParityTests`).

**The fuller version** draws the child where SwiftUI puts it: the part inside
the region, clipped, or all of it as an overflow layer outside the frame's
buffer (`OffsetView` draws one). **Price:** a region would stop containing its
content, which every TUI container assumes of a buffer (its size is its
extent), or a child past the edge would be cut — showing six cells' worth of a
view as one or none, where today it is whole.

**Asked 2026-10-12: build the overflow layers?** You dislike forced clipping
(a bouncing scale-in, say), and asked to explore SwiftUI's unclipped
placement. SwiftUI does not clip a view to its frame by default (measured for
frame, overlay, background, offset and scale; scroll views and the clipping
modifiers do clip). TUI clips every view to the space it was given, as a
safety net, but `scrollClipDisabled`'s overflow layers already draw past a
region in SwiftUI's stacking order, painting only the cells they draw, with
their hit regions travelling with them. Generalised to the placement sites,
they would fix this entry, B-GUIDE-1's overhang, a badge on a corner
overwriting its label, fixed-size content larger than its frame, and `.move`
and `.offset` bounces drawing over every sibling instead of in order. A cell
has no transparency, so overflow hides what is under it completely: lists,
tables, menus, sheets and scroll views keep clipping. The bouncing scale-in
is a different limit: `.scale` uncovers a view a cell at a time, and past 100%
there is nothing more to show. About three to four days.

**Shipped (2026-10-12, lane GUIDE3).** `scrollClipDisabled`'s overflow layers
are now the one mechanism for content drawn past its region
(`FrameBuffer.splitPlacing(at:inWidth:height:)`, `OverlayLayer.isOverflow`).
A single child that its guide places outside its `.frame`, `.overlay` or
`.background` sits where SwiftUI puts it (`AlignmentGuideRun.place`, bounded
as a run's push is): the part the region holds is drawn in it, the rest past
it, over the views before it and under the views after it, clicked where it
is drawn. The badge measured above draws `3` a row above `Inbox` and a column
right of it; a 4-wide view in a 4-wide frame whose leading guide is 3 sits 3
cells left of the frame, over the view before it (`PlacementOverflowTests`,
and `AlignmentGuideContainerParityTests` now expects SwiftUI's positions, past
the region, for every row). A `.move` or `.offset` transition's overshoot is
drawn the same way, so it no longer bounces over the views after it, and its
hit regions travel with it (`TransitionOvershootTests`). A view that fits its
region pays one static check and four comparisons; a measure pass draws
nothing past the region and sizes as before. A scroll view, `.clipped()`, a
`List`, a `Table`'s cell and a surface (a menu, a sheet) cut these layers at
their box (decisions-GUIDE3 B-GUIDE3-3). Not shipped: content larger than its
frame or base (B-GUIDE3-1: `.fixedSize()` does not make a `Text` rigid
here), and `.offset`/`.position`, which still float over every sibling
(B-GUIDE3-4).

### B-GUIDE3-1. Content larger than its frame or base is still cut

*`.frame(width:height:alignment:)`, `.overlay(alignment:content:)`,
`.background(alignment:content:)`, `.fixedSize(horizontal:vertical:)`*

SwiftUI draws content larger than its frame or base past it, placed by the
alignment (measured, GUIDE2 `g2c`: a 40-wide view in a 20-wide
`.frame(alignment: .leading)` draws 20 cells past the frame's trailing edge,
centred it draws 10 past each). The lane's mechanism draws past a region
whatever a placement puts outside it, and it ships for the placements a guide
makes. It does not ship for content larger than its region, because in TUI
no content reaches a placement site larger than its region in a way that
means what it means in SwiftUI:

- **`.fixedSize()` makes only a `List` rigid.** It is an environment flag that
  `List` reads; a `Text` wraps and truncates to the width it is offered as
  before, so `Text("0123456789").fixedSize().frame(width: 4)` draws `012…`,
  where SwiftUI's draws all ten digits centred, three past each side.
- **A fixed frame squeezes to its offer.** `.frame(width: 40)` offered 20
  reports 20 (deviations L5), so a 40-wide view inside a 20-wide frame is 20
  wide by the time the outer frame places it.
- **A `Text` reports every line it wraps to, whatever height it is offered,**
  and is cut by the clamp every view passes through — what SwiftUI's `Text`
  does by truncating. A rule that drew any rigid content larger than its
  region past it would draw a wrapped `Text` past a one-row frame, below the
  frame, where SwiftUI shows one line.

So a view larger than its frame or base is cut to it, as before (deviations
L5); only an image with a natural size reports a size larger than it is
offered and means it, and it is cut from its top-leading corner (B-D3M-2).

**The fuller version**, in three parts that can ship apart:
1. `.fixedSize()` as SwiftUI's: the view proposes no size on its fixed axes,
   so the `Text` inside it reports its unwrapped width, and the frame, overlay
   or background placing it draws it at that size, by its alignment, the rest
   past the region. The environment flag would become a wrapper whose proposal
   a frame inside it overrides (in SwiftUI a nested `.frame(width: 10)` still
   proposes 10). About 1.5 to 2 days, plus the A/B of every page that uses
   `fixedSize` (estimate).
2. An image with a natural size placed by its frame's alignment, past the
   frame, instead of cut from its top-leading corner: about half a day
   (estimate).
3. A fixed `.frame(width:)` that keeps its width when offered less: the change
   to every container's contract that B-GUIDE-1 prices at 1.5 to 2.5 weeks.

**Shipped 2026-10-18 (lane LAYOUT): parts 1 and 2.** `.fixedSize()` had become
SwiftUI's in the meantime (c3faf8a02): a `Text` under it reports and draws its
unwrapped width. A view drawn at its own size whatever it is offered —
`.fixedSize()`, an `Image` at its natural size (`DrawsAtItsOwnSize`, found
through single-content wrappers and app views' bodies, kept per type) — is now
offered its own size by a `.frame`, an `.overlay` or a `.background` it is
larger than, so it comes back whole rather than cut to the region, and placed
by the region's alignment past its edges, the part past it drawn as overflow at
the view's place in the stacking order: `Text("0123456789").fixedSize()
.frame(width: 4, alignment: .center)` draws three digits past each side, over
the views before it and under the views after it (`OwnSizeOverflowTests`), and
a picture at its natural size in a centred frame shows its middle, the rest
past the frame (`ImageNaturalSizeTests`). Other content larger than its region
is cut to it as before: a `Text` is truncated to its offer, as SwiftUI's is,
and a `Text` taller than a one-row frame keeps its rows past the frame cut.
Part 3 stays deferred (B-GUIDE3-1-P3). A view that is neither pays one table
read per frame or layer render; one that is pays a measure more.

### B-GUIDE3-3. Which containers keep what is drawn past a region inside them

*`List`, `Table`, menus, popovers, sheets, dialogs; `.move` and `.offset`
transitions inside them*

The brief: lists, tables, menus, sheets, dialogs and scroll views keep
clipping. Before this lane a guided view never left its region, so the
question did not arise for it; a transition's overshoot and an `.offset`
view did leave it, and a `ScrollView` and a `List` cut them at their box, a
`Table` and a surface not at all. Each container now cuts the overflow
layers (`OverlayLayer.isOverflow`) its content carries at a box of its own:

- **`ScrollView`** at its viewport, as before, and **`.clipped()`** at its frame.
- **`List`** inside its border: a row's overflow may still draw over the rows
  beside it, as any of its layers always could, but never over the border or
  past the list. A list composes its rows as lines, so the stacking order
  (over the rows before, under the rows after) does not reach inside it.
- **`Table`** at the cell: drawn past it, the overflow would cover the next
  column, the column separators and the border, and the table composes its
  cells as lines too.
- **A surface** (an opaque layer: a menu, a popover, a sheet, a dialog, a
  toast) at its edge, where the screen root lifts its content's layers.

A transition's overshoot is now overflow (B-GUIDE-3), so the same cuts apply
to it: a row bouncing one cell past a dialog's edge, or past a table cell's,
now stops there, where it used to draw past it (`TransitionOvershootTests`
"An overshoot on the page stays under a dialog…" now uses a dialog two cells
wider than its bouncing row). An `.offset` view is not overflow and keeps
what it had: cut by a `List` and a `ScrollView`, not by a `Table` or a
surface.

**The fuller version** has two halves. SwiftUI's `List` and `Table` rows on
macOS were not measured for overflow (they are AppKit table rows), so the
row-level rule is unmeasured either way; measuring them is about an hour. And
drawing a bounce past a surface's edge while keeping a guided view inside
would take a second kind of overflow layer (one more stored flag on
`OverlayLayer`, read at the four cuts above): about half a day (estimate).

### B-GUIDE3-5. A border, and a box's footer, are drawn over what the content draws past its region

*`.border()`, `ContainerView` (`Panel` and the other boxes), their footers;
a bordered `TabView`'s panel; the window bars; a `Section`'s parts*

A bordered box composes its rules, its divider and its footer around its
body by hand, not through a combining operation, so the overflow its body
carried was drawn over all of them. The review of the lane found it through
B-GUIDE-1's overhang: a hanging marker whose guide pushes a full-width line
past the body drew the line's last letters over the box's right rule (the
box's one-cell padding takes the first). SwiftUI draws a border over what its
content draws past the content's frame, and what lies past the border is
still drawn (measured 2026-10-12, probe `GUIDE3/probe/g3b.swift`: a 20-point
view pushed 5 points past its frame by a guide or an `.offset`, under
`.border(green, width: 2)`: the border's pixels are green, the 5 points past
it red; with `.padding(2)` before the border, the same).

Shipped: the box cuts the overflow its body and footer carry under its rules
and its divider (`FrameBuffer.coverOverflow(underRects:)`), and the footer,
which comes after the body, cuts the body's overflow where it paints, as a
stack's next child does; a borderless box's divider and footer do the same,
and its title, which comes before the body, does not. Past the rules the
overflow is still drawn, under whatever comes after the box
(`PlacementOverflowTests` "A border is drawn over…", "A footer, and its
divider…"). The borderless box's divider cuts the footer's overflow as well
as the body's, as the bordered box's does; it cut it only when the body
carried overflow too ("A borderless box's divider…").

The same holds wherever a border is drawn around content by hand
(`FrameBuffer.coverOverflowUnderBorder`). A `.bordered` or `.grouped`
`TabView` draws its strip, its panel's walls and its bottom rule around the
selected tab, and they are drawn over what the tab draws past its region; the
strip, which ends in the panel's top rule, is taken whole as the panel's top
edge. A hanging marker in a tab pushed the tab's lines over the panel's right
wall ("A tab view's panel…"). A window bar (`.appHeader`, the bottom bar)
frames content laid out before it: a `.bordered` bar's four rules, and a
`.rule` bar's one rule, are drawn over what that content draws past its
region ("A window bar's rules…"). And a `Section` drawn as one view (a view's
whole body, a scroll view's content) stacks its header, content and footer by
hand: what a part draws past its region is now cut where a later part paints,
as a stack's next child cuts it, where every part's layers were lifted uncut
("A section's parts…").

An alert's row of buttons, and a confirmation dialog's column, are built by
hand as well, and lifted each button's layers uncut: a label pushed past its
button drew over the next button. Each button now cuts the overflow of the
buttons before it where it paints, as `Section`'s parts do (lane BUGS13;
"An alert's later buttons…").

A windowed stack (a `LazyVStack`, or a `VStack` in a scroll view) renders
its focused row when the row is outside the window, and grafts the row's
layers in at its place, after the rows it draws. A row above the window
comes before them, so its overflow is now cut where they paint; a badge it
hung down onto them was drawn over them (lane BUGS13; "A windowed stack's
focused row above the window…").

**The fuller version** is SwiftUI's picture of the case that found it: the
stack grows past its proposal and the border moves out to enclose the
overhang. That is the change to every container's contract that B-GUIDE-1
prices at 1.5 to 2.5 weeks.

### B-GUIDE3-4. `.offset` and `.position` still float over the views after them

*`View.offset(x:y:)`, `View.position(x:y:)`; deviations L6*

The brief moved a `.move` or `.offset` transition's overshoot into the
stacking order, and this lane did; the modifiers `.offset` and `.position`
were not in it, and still draw over every sibling, before and after
(deviations L6), as a layer whose hit regions travel with it. SwiftUI draws
them in the stacking order (unmeasured; Apple's documentation of `clipped`
says a view's frame is used only for layout).

**The fuller version** draws them as overflow, which is the mechanism this
lane generalised: an `.offset` view would split at its own region, as a
transition picture does, and be cut under the views after it. The one
difference to settle is the geometry markers: a reader inside an offset view
is answered where the view is drawn (the floating layer carries them), and an
overflow layer's markers are not read, so they would move into the footprint
and be shifted by the offset. About half a day, plus the A/B of the pages
that offset views (estimate).

**Shipped 2026-10-18 (lane LAYOUT): the fuller version.** `.offset` and
`.position` draw their view as a transition's overshoot does
(`FrameBuffer.drawnDisplaced(by:footprintWidth:footprintHeight:)`): a
footprint in flow, where the view is laid out, that paints nothing, and every
cell the view paints drawn past it as overflow — over the views before it,
under the views after it, its hit regions travelling with its cells, cut by a
scroll view, `.clipped()`, a `List`, a `Table`'s cell or a surface as any
overflow is (B-GUIDE3-3; an offset view in a `Table` cell or a surface was
not cut before). Its geometry markers ride in the footprint, moved by the
offset, so a reader inside is still answered where the view is drawn. Only
the cells it paints are drawn, so a label's leading blank no longer covers
what lies under it. **A/B** where views are offset or positioned on
every frame: Stress's `geometry` scenario (a header offset by the tick, a
marker by its anchor) ran at the landing, 2026-10-12: +1.4% warm and +1.1% cold (indistinguishable). The rest of that sweep
was within 1%, bar `customlayout` +1.1% warm and +1.7% cold and `menus` +0.8%
cold; the stripped binary grew 33 KB. The Example's ZStack layering and animator
demos were not measured.

### B-LAYOUTPERF-3. Overflow is cut under the lines it reaches; three environment writes are skipped where they change nothing

*`.offset`, `.position` (LAYOUT's L6), `FrameBuffer`'s combining operations;
`VStack`, `HStack`, the bordered containers, `.disabled(_:)`*

Shipped: since L6 an offset view's cells overflow, and the cut under a later
view read every line of it — in `geometry`, the whole scroll view under a
one-row offset view, every frame (3.3%; now none). The cut now reads only the
lines an overflow reaches, giving the same layers (`OverflowCoverReachTests`).

Three writers of the environment wrote a value already in force, each write
copying the whole environment dictionary: a stack publishing the container
relationship it was given (a column in a column or in a box), a box clearing
a focus indicator that is not there, and `.disabled(false)` in an enabled
subtree. Not costs LAYOUT added — taken because `deep` and `kitchensink` are
the scenarios B19's 1% rule names: `deep`'s environment copies went from
1.9% of its frame to none, and `framedcolumns`' `isEnabled` writes from 0.7%
to none.

**The fuller version:** every framework writer of the environment skips a
write that changes nothing. `kitchensink` still spends about 0.9% copying
environments, across a dozen writers of 0.1–0.2% each
(`containerRelativeSize`, `drawsListSectionChrome`, a row's container
relationship, …). A helper that writes an `Equatable` value only where it
differs, adopted writer by writer: about half a day, plus an A/B.
