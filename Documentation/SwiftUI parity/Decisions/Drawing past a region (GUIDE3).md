# Completing the SwiftUI API: lane GUIDE3's new judgement calls

*Lane GUIDE3, 2026-10-12, shipped the owner's rulings on decisions
[B-GUIDE-2](<Alignment guides outside their view (GUIDE).md#b-guide-2-one-guide-pushes-a-view-at-most-4096-cells-whatever-the-containers-extent--decided-220-and-a-push-past-it-reported>)
(a guide may push a view 2^20 cells; a push past that, or a guide that is not
a number, is a logic error) and
[B-GUIDE-3](<Alignment guides outside their view (GUIDE).md#b-guide-3-one-child-whose-guide-would-put-it-outside-its-region-is-held-inside-it>)
("try to support" SwiftUI's unclipped placement), and B-GUIDE-1's fuller
version on top of that. Where the work met a judgement call the rulings did
not settle, the safe option shipped and is written up here, in the three
parts the other lanes use: A needs a decision, B shipped the safe option
(with the fuller version and its price), C declined with a parity-map reason.
SwiftUI's behaviour is the one measured by lanes GUIDE and GUIDE2 (SwiftUI
6.5.4 on macOS 15.8.1; probes in
[`Tools/SwiftUIProbes/Alignment guides/`](<../../../Tools/SwiftUIProbes/Alignment guides/>)
and the session notes of GUIDE2).*

## B. Shipped the safe option

### B-GUIDE3-1. Content larger than its frame or base is still cut

*`.frame(width:height:alignment:)`, `.overlay(alignment:content:)`,
`.background(alignment:content:)`, `.fixedSize(horizontal:vertical:)`*

SwiftUI draws content larger than its frame or base past it, placed by the
alignment (measured, GUIDE2 `g2c`: a 40-wide view in a 20-wide
`.frame(alignment: .leading)` draws 20 cells past the frame's trailing edge,
centred it draws 10 past each). The lane's mechanism draws past a region
whatever a placement puts outside it, and it ships for the placements a guide
makes. It does not ship for content larger than its region, because in TUIkit
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

### B-GUIDE3-2. Which guide a push past the bound blames, and how far the variable may raise the bound

*`AlignmentGuideRun.maximumPush`, `TUIKIT_MAX_ALIGNMENT_PUSH`*

A push is the gap between two guides, so a push past 2^20 does not say which
of the two is wrong. The owner's ruling places "such a view at its own
origin". The lane takes the guide furthest from its own view's origin as the
runaway, reports it, and takes it as that origin, one guide at a time until
the run's spread fits: `1e300` beside a `0`, and `-1e300` beside a canvas row
at `-3`, which keeps its place (`AlignmentGuideTests` "A push past the bound
is reported…"). A single child in a frame, overlay or background is bounded
the same way against the region's guide; a region guide that is itself a
runaway (a custom `AlignmentID`) is held to the bound.

The environment variable takes a whole number of cells from 1 up and is held
to 2^30: a pushed run is drawn as lines that long, and its extent plus a
view's size has to fit an `Int` where `Int` is 32 bits (WebAssembly). Anything
else (0, a negative number, text, `1e9`) leaves 2^20.

**The fuller version** would name the guide in the report (which view, which
key). The report has no view to name: a guide is a closure, and the run sees
only its values. Recording the call site of each `.alignmentGuide` (a
`#fileID`/`#line` default argument, as `SoftTrap.report` takes) would do it,
at the cost of two stored words in every guide wrapper. About half a day
(estimate); not done, since the debug build's assertion already stops in the
stack that placed the run.

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
