# Completing the SwiftUI API: lane O4's new judgement calls

*Lane O4, 2026-10-18, shipped the owner's ruling on
[O4](<../Refusals re-examined, wave 17 (2026-10-03).md#o4-matched-geometry-matchedgeometryproperties--w12-matchedgeometryeffect-zoom-matchedtransitionsourceconfiguration-emptymatchedtransitionsourceconfiguration--w09-matchedtransitionsource-navigationtransitionzoom>)
(2026-10-12: a full re-layout at the interpolated frame each animation frame
as the baseline, whole-cell translation where the sizes are equal), and with
it decisions A36 (`matchedGeometryEffect`, `MatchedGeometryProperties`).
Where the work met a judgement call the ruling did not settle, the safe
option shipped and is written up here, in the three parts the other lanes
use: A needs a decision, B shipped the safe option (with the fuller version
and its price), C declined with a parity-map reason.*

*SwiftUI's behaviour is the one measured on this Mac (macOS 15.8, Xcode 26's
SDK, 2026-10-18) by offscreen `NSHostingView` probes,
[`Tools/SwiftUIProbes/Matched geometry/`](<../../../Tools/SwiftUIProbes/Matched geometry/>)
(`mg1.swift`, `mg2.swift`, `mg2b.swift`, `mg3.swift`, each with what it
printed), which read the presentation frames of the layer tree, so they see
where SwiftUI draws a view rather than where it lays it out.
`Tests/TUIkitEffectsTests/MatchedGeometryEffectTests.swift` pins each finding
in cells.*

## What was measured

- **A follower keeps its own place in its parent's layout.** A view with
  `isSource: false` following a larger source leaves the views after it where
  its own size puts them; its content is proposed the source's size
  (`mg1` S1, S1f, S11; `mg2` F12).
- **Its anchor lands on the point the source's anchor names** (`mg2` F2, F6,
  F7, F9, F10). The source's `anchor` says which point of it is shared; the
  follower's says which of its own goes there.
- **Matching `.size` alone, a follower stays at its own top-leading corner**,
  whatever its anchor (`mg2` F3–F5).
- **A content that does not take the size it is offered** (a fixed `.frame`)
  is drawn from the matched frame's corner offset by twice its anchor's share
  of the difference: a centred 10×10 in a 40×20 frame at (30, 10), against the
  frame's bottom-trailing corner (`mg1` S1, S9, S10, S11; `mg2b` G1–G7). It
  looks like an alignment applied twice; TUIkit draws it there too, since it
  is what SwiftUI code ported here was written against.
- **A source's own `properties` change nothing**; a follower's do (`mg2` F13).
- **Two sources:** the follower took the later one's frame, and so did the
  earlier source (`mg1` S10). Apple calls it undefined.
- **Under an animation** (`mg3`): a view inserted as another of its id is
  removed moves from that one's frame to its own along a straight line, edge
  for edge, and is laid out at every size in between (A2: its
  `GeometryReader` reported 40×20, 41×20, … 100×60); the removed view moves
  toward the inserted one's frame as it fades (A1, A2). A follower whose `id`
  changes moves to its new source the same way, but is laid out once, at its
  new size, its drawing scaled between (A3). A source moved by its layout is
  followed in step (A4). A view inserted with nothing of its id leaving
  appears in place (A5), and so does a follower inserted beside a standing
  source (A8).

## B. Shipped the safe option

### B-O4-1. A removed member stays where it was while it leaves

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

SwiftUI carries the removed view toward the inserted one's frame while its
removal transition plays (`mg3` A1, A2). TUIkit draws a removed view from the
picture it last drew, at its slot (Deliberate deviations A3), so the picture
stays where it was and fades there; the inserted view is carried from it. An
`if`/`else` whose branch flips changes at once (Deliberate deviations,
Slated), so the classic hero written that way shows only the inserted view,
carried — which reads as one view moving; two separate `if`s show the
leaving one fading where it was as well.

**Fuller version:** move the leaving picture with the inserted view, a whole
cell at a time — option (a) of O4 for the view that leaves, since its content
no longer exists to be laid out again. The departure slot would ask the
registry where the member that left its picture is being carried to, and draw
the picture past its slot by the difference (`FrameBuffer.drawnPastSlot`).
About a day, mostly in `DepartureStore` and `DepartingSlot`, which lane FB16
is reworking now; best done after it lands.

### B-O4-2. A transition fades a member where it is laid out, not where it is drawn

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`, `AnyTransition.opacity`*

A member drawn at another view's frame draws there as content past its slot
(`FrameBuffer.drawnPastSlot`), in layers drawn past the footprint. The
default transition's fade (`DefaultTransition.faded`) and the `.opacity`
transition's (`TransitionEffects.faded`) fade the cells of the slot, not those
layers, so a view carried into place under the default fade is drawn at full
strength while it moves. SwiftUI fades it as it moves (`mg3` A1, A2). The
same gap is older than this lane: an `.offset` child inside an `if` is not
faded by the `if`'s fade either, while `.opacity` fades its displaced drawing
(`_OpacityView.fadingOverlays`).

**Fuller version:** fade a view's own layers in both transition fades as
`.opacity` does — which moves `fadingOverlays` down to `TUIkitView`, beside
`DefaultTransition` — so a carried view fades in as it moves, and an
`.offset` child fades with its `if`. About half a day with tests; it touches
the transition code lane FB16 is changing, so it waits for that lane. Whether
a carried view should fade at all in a terminal is worth a look then: a solid
view moving reads better on a cell grid than one fading in as it moves.

### B-O4-3. With two sources, the last one drawn is the group's, and the others keep their own frames

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

Apple's documentation calls more than one source undefined. SwiftUI was
measured giving followers the later source's frame, and giving it to the
earlier source too (`mg1` S10). TUIkit gives followers the last source drawn,
and draws every source at its own frame.

**Fuller version:** draw the earlier sources at the last one's frame as well,
as measured. An hour; not done because the case is undefined and an app
relying on it is relying on a bug.

### B-O4-4. A follower of another size draws its content twice a frame

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

A member drawn at a size other than its own is drawn once at its own size —
which gives the footprint its parent laid out, exactly — and again at the
matched size, the walk's registrations put back between the two
(`RenderWalkCheckpoint.rewind`). A follower at rest whose source is another
size pays the second drawing on every frame; a member at its own size, or
carried at its own size, draws once. (Every member also declines the memos of
the views above it, as `onGeometryChange` does: it joins its group on every
frame it draws.)

**Fuller version:** take the footprint from the measure instead of a drawing,
which is one drawing a frame, but a measure reports a flexible view's
minimum where the drawing fills its offer, so the footprint would have to
re-derive what each container gives a flexible child. An A/B on a page of
followers decides whether it is worth it; none is owed until one is slow.

## Interaction with lane FB16 (stack children gliding)

FB16 animates a stack child's placement when the layout changes under an
animation; this effect animates only what matching adds: a view arriving as
another of its id leaves, and a follower whose source changes. A source moved
by its layout is drawn where its layout puts it and is not animated by the
effect; its followers follow it frame by frame (`mg3` A4 shows SwiftUI's
follower moving in step with its source). So a view under both moves once.
The assumption this rests on: the effect reads a view's frame from its
geometry marker, so a glide must move the view's marker with its drawing (a
child placed in flow at the interpolated offset does) for followers to track
a gliding source. A glide drawn past the slot with the marker left in it
would have followers lead the source to where it is going.
