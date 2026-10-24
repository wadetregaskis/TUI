# Completing the SwiftUI API: lane O4's new judgement calls

*Lane O4, 2026-10-18, shipped the owner's ruling on
[O4](<../../Refusals re-examined, wave 17 (2026-10-03).md#o4-matched-geometry-matchedgeometryproperties--w12-matchedgeometryeffect-zoom-matchedtransitionsourceconfiguration-emptymatchedtransitionsourceconfiguration--w09-matchedtransitionsource-navigationtransitionzoom>)
(2026-10-12: a full re-layout at the interpolated frame each animation frame
as the baseline, whole-cell translation where the sizes are equal), and with
it decisions A36 (`matchedGeometryEffect`, `MatchedGeometryProperties`)
and A23 (`matchedTransitionSource` and the zoom navigation transition).
Where the work met a judgement call the ruling did not settle, the safe
option shipped and is written up here, in the three parts the other lanes
use: A needs a decision, B shipped the safe option (with the fuller version
and its price), C declined with a parity-map reason.*

*SwiftUI's behaviour is the one measured on this Mac (macOS 15.8, Xcode 26's
SDK, 2026-10-18) by offscreen `NSHostingView` probes,
[`Tools/SwiftUIProbes/Matched geometry/`](<../../../../Tools/SwiftUIProbes/Matched geometry>)
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

**Done 2026-10-19 (lane TRANSITIONS2).** A member arriving as another of its
group leaves notes, on each frame it is carried, how far the one that left
moves (`DepartureStore.noteCarried`): its picture is placed in the frame the
arriving one is drawn at, as a content of its size is placed in a matched
frame, so the two move together. Whatever plays the removal — the `nil` an
`if` became, the stack that saw a branch or a row with a transition of its
own go (decisions B-TRANSITIONS2-1; one with none goes at once since
B-TR2PERF-1), a conditional drawn whole — draws the picture past its
place by that much: the matched view's own cells, found in the picture by
its geometry marker, so a branch holding a card and a line of text carries
the card and fades the text in place, and one holding two matched views
carries each with its own; a picture that is all one matched view moves
whole. A picture drawn before the arriving member has drawn takes the last
frame's carry, and one whose removal outlasts the carry stays where the
carry landed — in the frame the arriving one ends at, as SwiftUI's does —
for as long as it is drawn.

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

**Done 2026-10-19 (lane TRANSITIONS2).** Both fades reach a view's layers
drawn past its slot (`OpacityFading`, moved down to `TUIkitView`): a carried
view fades as it moves, and an `.offset` child with its `if`, as SwiftUI's do
(`mg3.out` A1, A2; `Tools/SwiftUIProbes/Transitions/tr3.out` T14, T15).

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

### B-O4-5. The zoom transition is a reveal, and a push zooms under the default animation

*`NavigationTransition.zoom(sourceID:in:)`, `ZoomNavigationTransition`,
`View.matchedTransitionSource(id:in:)`, `View.matchedTransitionSource(id:in:configuration:)`*

SwiftUI's zoom is iOS-only, so it could not be measured on this Mac; Apple
documents it as the pushed view zooming from the source. The ruling makes it
a reveal: the pushed screen, laid out at its full size, is uncovered through
a rectangle that grows from the source's frame to the stack's, edge by edge
(`MatchedEdgeOffsets`, as matched geometry interpolates), over the picture of
the screen it replaces; popped, the rectangle shrinks back into the source
over the screen it returns to, which is live. The source is a member of the
matched geometry registry (its id wrapped, so a transition source and a
`matchedGeometryEffect` of the same id stay two groups), so its frame is the
scene root's finding. Nothing finds a source on the root while a screen covers
it, the root being drawn off-screen, so a pop starts from where the source was
when the screen was pushed, and folds into where the root finds it once it is
back — from the zoom's second frame, the first that draws the source's
rectangle, so a source the root moved while covered is folded into where it
is now.

Four calls the ruling left open:

- **Which animation.** TUIkit's stack changes at once, and a `NavigationLink`
  pushes outside any `withAnimation`; SwiftUI animates a push regardless. The
  zoom takes the change's animation where it has one and `Animation.default`
  where it does not, and does not play where the transaction disables
  animations, the frame cannot animate (a headless render), or motion is
  reduced.
- **No source.** With no `matchedTransitionSource` of the id on screen the
  stack changes at once, as `.automatic` does; what SwiftUI does then is not
  documented.
- **Which declaration.** A screen can declare more than one transition — a
  view inside it declaring `.automatic`, say, under the `.zoom` written on the
  screen. The outermost is the screen's, the one written where it is pushed,
  and of two side by side the first; SwiftUI's rule could not be measured. A
  stack inside a screen keeps its own screens' declarations to itself.
- **The pictures.** The screen being covered is drawn from its last picture,
  so it holds still while the new one grows over it; what is uncovered is
  live, so its controls take clicks inside the rectangle from the first frame.

**Fuller version:** none that a cell allows for the scale itself. The
rectangle is drawn with the source's corners since shapes landed (B-O4-6).

### B-O4-6. A transition source's configuration has its background; clip shapes and shadows wait

*`MatchedTransitionSourceConfiguration.clipShape(_:)`,
`MatchedTransitionSourceConfiguration.shadow(color:radius:x:y:)`*

`background(_:)` ships: the colour fills the revealed rectangle behind the
screen's own cells, the cells the screen paints with no background of their
own taking it. `clipShape(_:)` takes a `RoundedRectangle`, which arrives with
shapes (lane W1, after O0), and `shadow(color:radius:x:y:)` a shadow, which is
O6's; each fails to compile until then (parity-map entries), as the parity
rules ask. SwiftUI already refuses every other clip shape and every other
background style (`unavailable` in its interface), so those are not offered
either.

**Fuller version:** once W1 lands, draw the rectangle's corners with the
rounded corner glyphs and clip the uncovered screen to them — half a day; once
O6 lands, draw the source's shadow round the rectangle — a couple of hours on
top of O6's own drawing.

**Shipped** by lane W1B (2026-10-19), the clip and the shadow both:
[B-W1B-2](<What the shapes unblocked (W1B).md#b-w1b-2-a-zoom-sources-clip-shape-and-shadow-shrink-to-nothing-as-the-rectangle-grows>).

### B-O4-7. A carried member floats over every view while it moves

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

At rest, a member drawn at another view's frame is drawn there at its own
place in the stacking order, over the views before it and under the views
after it, as SwiftUI draws a view past its frame. Carried by an animation,
that hid it: a terminal's blank cells paint, so a chip carried from the
right-hand list back to the left one (the left list being earlier in the
tree) was lost under the right list's box, blanks and all, until it had
cleared it — the Example's "Reopen one" showed the chip vanish and reappear
half-way. So while it is carried it floats over every view, a layer of its
own over the page, and drops back into the stacking order when it arrives.
(It floated as `.offset` did then; since 2026-10-18 `.offset` and `.position`
are drawn at their place in the stacking order, Deliberate deviations L6, and
the carried view is the one that still floats.)

**Fuller version:** draw a carried view in the stacking order with the
later views' unstyled blanks letting it through — a notion of "painted"
for covering that leaves out blank cells with no background, which the
overflow machinery (`FrameBuffer.coverOverflow(under:at:)`) does not have.
About a day, and it would change how every overflowing view is covered, so
it wants an owner's look first.

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
