# SwiftUI's insertion and removal model: decisions from lane FB16

*Lane FB16, 2026-10-18, built the owner's ruling "FB16: (a′)" — SwiftUI's
model as measured in a real SwiftUI app on macOS 15.8 (`Tools/SwiftUIProbes/Insertion and removal (FB16)/FB16Probe.swift`,
Core Animation presentation frames every 0.5 s in `Tools/SwiftUIProbes/Insertion and removal (FB16)/samples.txt`):
a change of layout takes effect at once; under `withAnimation` every view
whose frame changed glides from its old frame to its new one, siblings
included, for every transition (`.identity` too); the transition decides only
how the inserted or removed view itself arrives or leaves, and a view leaving
plays its removal where it was while its siblings close up over it. The format
is that of the main decisions file:*

- **A-FB16-n — needs your decision.**
- **B-FB16-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-FB16-n — declined.** With the reason.

## What shipped

- **A glide** is a child's placement in its container as an animated value in
  the `AnimationStore`, keyed by the container's identity and what the child
  is (`ChildGlide`). It exists only while the child moves, so it is
  interrupted (merged or added, decisions O3), held still by reduce motion
  (a glide is motion, A-D3M-1) and waited on by a `withAnimation` completion
  as every animated value is.
- **Where each child was** is remembered per container (`PlacementStore`)
  while it is on screen: while the container renders, or while a memo serves
  a subtree it stands in. A record pruned by re-declaration, as the animation
  store prunes, made the first change after a memo-served frame a first
  sight, which never moves anything. One kept as long as `@State` is —
  through a window's skip as well — was a record per stack in every row a
  list had been scrolled through, walked at the end of every pass; a stack
  scrolled back into view has nothing on screen to glide from, and is drawn
  where its layout puts it.
- **A settled container pays** one dictionary lookup and a comparison of each
  child's place and identity with what it remembers — no store write, no
  environment read, no allocation but the targets array. Anything moving or
  leaving draws the container as a `ZStack` draws its layers
  (`FrameBuffer.layered`), what lies past its frame drawn past it at its
  place in the stacking order, and declares the picture a function of the
  clock, so no memo keeps a frame of it.
- **A removal** in an eager stack or a `ZStack` takes no room: the slot a
  `nil` keeps (`DepartureSlot`, now marked `ChildView.isDeparting`) is laid
  out nowhere and drawn where the view last was.
- **The opt-out**, `.transitionSpace(.held)`, keeps the room as before.
- **The Example's** Animation page offers close up (the default, SwiftUI's),
  hold then close up, and keep the space.

## A. Needs your decision

### A-FB16-1. A container's own size changes at once, where SwiftUI's frame glides

**Re-checked 2026-10-18 (evening):** this is the unbuilt part of your ruling, not a new question. "FB16: (a′)" took SwiftUI's measured model, in which every view whose frame changes glides from its old frame to its new one: its size as well as its position. The lane built the positions. So option 1 would mean recording positions-only as a deviation from (a′).

*`.border`, `.background`, `.frame`, `DemoSection` in the Example*

SwiftUI animates every view's frame, its size as well as its position: a
bordered card whose content loses a row draws its border shrinking over the
animation. Here places glide and sizes do not. On the Example's Animation
page, hiding the panel draws the section's border at its new, shorter size on
the first frame, and the panel fades out below the border while the next
section glides up over it.

**The options:**

1. **Leave it** (shipped). Places glide; sizes change at once. Free.
2. **Glide the size of what draws around its content** — a border, a
   background, an overlay: each would keep its last drawn size beside the
   placement record and draw at a size gliding from it to the new one, the
   difference past its frame. About two days, with the drawing past a frame
   that a border already has (`coverOverflowUnderBorder`), and a cost on
   every bordered view of a lookup a frame, to be measured.
3. **Glide every frame**, SwiftUI's whole model: a presented size for every
   view, which every container would lay its child out in while it moves.
   Re-lays children every frame of a change. Not priced; a project, not a
   lane.

**Recommendation:** 1 now, 2 if the Example's section borders read badly in
use.

## B. Shipped the safe option

### B-FB16-1. Glides live in the eager stacks, `ZStack` and `Layout`

*`_VStackCore`, `_HStackCore` (`.clip`), `_ZStackCore`, `_LayoutCore`*

The containers that place their children by computed offsets and render them
all: a column's and a row's children by the running sum of what each draws,
a `ZStack`'s layers by their alignment in the union of their sizes, a
`Layout`'s subviews where `placeSubviews` put them (which covers the lazy
grids, `AnyLayout` and the stack layouts).

**The fuller version** is every container: B-FB16-2 to B-FB16-5 price them.

### B-FB16-2. A lazy stack moves its children at once and keeps a removal's room

*`LazyVStack`, `LazyHStack` (`.window`)*

A lazy stack draws a window of its rows, by four paths (the append-while-fits
walk, the viewport window, the uniform window, the anchored window), whose
placements are relative to the window, not the stack. A record of them would
see every scroll as a change of every placement, and a scroll is not animated
here (deviations R1) — but an insertion above the window under an animation
would glide rows that are only moving because the window moved. The design
does not carry over cleanly, so the lane stopped at the eager stacks, as the
brief allowed.

**The fuller version:** placements kept in stack coordinates (window origin
plus the row's place in it) through each of the four paths, the departure
slots taken out of the slot walk (`naturalRowSlots`, the uniform and anchored
windows), and a row scrolled into view placed directly. About two days, and an
A/B on `megalist`, `table` and the scroll scenarios, which are where a cost
per row would show.

### B-FB16-3. A `Grid`'s cells move at once

*`Grid`, `GridRow`*

A grid places cells in a lattice of rows and columns (`_GridCore`), two levels
of identity deep, and is not a `Layout`.

**The fuller version:** a placement record per grid keyed by each cell's
identity under its row, the lattice's origins as targets, drawn through
`FrameBuffer.layered` while anything moves; departure slots in a row taken out
of the lattice. About half a day.

### B-FB16-4. A `Layout`'s subviews glide, but a removal keeps its room

*`_LayoutCore`, `LayoutSubviews`*

The slot a `nil` keeps is one of the subviews a `Layout` is handed, so the
layout places it at the size the view had until the removal has played.

**The fuller version:** the departure slots taken out of the `LayoutSubviews`
an app's layout sees — as SwiftUI's never include a removed view — keeping
`FlattenedRowIDs` aligned with what remains, and drawn where each view last
was. About half a day; an app's own layout code then sees one subview fewer on
the first frame of a removal, which is SwiftUI's behaviour.

### B-FB16-5. `List` and `Table` rows change at once

*`List`, `Table`, `ForEach` rows*

Out of the lane's scope (the brief): rows are laid out by the list's own
row machinery, and a `ForEach` row's removal plays nothing (deviations,
Slated to change).

**Follow-up:** a placement record per list keyed by row id, and the row
removal the default transition does not play yet. Priced with the list's
row work, not here.

### B-FB16-6. A view leaving is drawn beneath its siblings, as measured, not in declaration order

*`StackGlide.glidingStackBuffer`*

The lane brief asked for a removed view to be drawn "over or under its
siblings in its declaration order". The probe says otherwise: in every
removal sample the removed view's layer comes first in its column, beneath
both siblings, whatever its transition (`samples.txt`, the `remove` lines),
while an inserted view's layer is in declaration order. That is SwiftUI's
well-known removal z-order, and why apps put a `.zIndex` on a view whose
removal should draw on top. TUIkit draws it so: beneath the present children
of its z-index, above those of a lower one, a `.zIndex` written inside the
transition lifting it.

**The alternative**, declaration order, is a change to one sort key. Not
recommended: it would differ from what was measured, and only for transitions
that move a view up or left over the sibling before it.

### B-FB16-7. A `nil` rendered on its own keeps the view's room while it leaves

*`Optional.sizeThatFits`, a page's body, a modifier's content*

Where the optional is the thing being rendered, nothing places it: there is no
container to give the room back to. It keeps the size the view had until the
removal has played, as before.

**The fuller version** would follow the container above it, which is the size
glide of A-FB16-1.

### B-FB16-8. A glide moves in whole cells, rounded half away from zero

*`ChildPlacement.init(_:)`*

As `.offset` rounds its animated value. A row gliding one cell moves at the
half-way point of the animation going one way and just after it going back.

**The fuller version** — a sub-cell picture — is not drawable in a terminal.

### B-FB16-9. `ViewThatFits` has nothing to glide

*`ViewThatFits`*

It draws one of its candidates at its own origin; a change of candidate is a
change of view, which SwiftUI also swaps rather than moves.

### B-FB16-10. A change seen in a later walk of the pass that first drew a container moves nothing

*`PlacementStore.appearedEarlierThisPass`*

A pass may walk the tree twice (the scene root's geometry correction); what
the first walk drew is never shown. A container first seen in an earlier walk
of this pass treats a different layout in a later one as its appearance, as
the animation store treats a value (`AnimationStore.beginWalk()`).

### B-FB16-11. The Example's "grow with it" choice is gone

*`AnimationPage.PanelSpace`*

It animated the slot's height to imitate SwiftUI's stack, which is now what
the default does: the page below glides as the panel comes and goes. In its
place, "hold, then close up" shows `.transitionSpace(.held)`. Strings in all
seven languages.

### B-FB16-12. The opt-out is a TUI-specific modifier, `.transitionSpace(.held)`

*`TransitionSpace`, `View.transitionSpace(_:)`, `EnvironmentValues.transitionSpace`*

No SwiftUI API holds a removed view's room; the SDK has none, and the room
going at once is the measured behaviour. The modifier is per subtree, as the
modifier-first rule asks, and reaches every eager stack and `ZStack` below it:
the slot is then laid out at the view's size until the removal has played,
and given back at once after. Insertions still glide; the hold is about a
removal's room.

### B-FB16-13. A stack emptied by a removal stands where it was while the change plays

*`ChildGlide`, `PlacementStore.Record.held`, `ChildPlacementEntry.drawsNothing`*

A view leaving the only stack it is in — `VStack { if show { Card() } }`,
which is a view's whole body as often as not — leaves that stack drawing
nothing. Here a child with no extent takes no stack spacing (compatibility
guide §3, an open divergence: SwiftUI's empty stack keeps its gaps), so in a
stack with gaps its place moves by the gap, and in a `ZStack` it is
re-centred. Glided there, it carried the view's removal with it: the view
drifted a row while it faded or slid out, where SwiftUI's plays where it
was. Found by review, in the Example's own panel, whose test had been
loosened to accept it.

A container now holds a child that has come to draw nothing (no rows or no
columns) where it was while its glide runs, and places a child that has come
to draw something directly, as it places a view seen for the first time:
what such a child shows is what it carries past its frame, a view leaving or
arriving in it, and that stays where it is drawn. Pinned by
`StackGlideTests` (a column and a layer, removal and insertion) and the
Example's `hidingSlidesOut`.

**What is left:** the hold ends when the change's glide lands, so a removal
with a longer animation of its own (`.transition(t.animation(…))`) finishes
at the stack's new place, a row from where it started. **The fuller
version** is the open divergence itself: an empty stack keeping its gaps, as
SwiftUI's does, which moves nothing at all and leaves the gap SwiftUI leaves.
It changes every page with a stack that can be empty, so it waits on a
ruling on §3.
