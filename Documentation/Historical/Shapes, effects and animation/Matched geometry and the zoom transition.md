# Matched geometry and the zoom transition

*How `matchedGeometryEffect` and the navigation zoom came to TUI: a full
re-layout at the interpolated frame each animation frame, removed members,
two sources, a follower of another size, the zoom as a reveal, and the
pictures it carries. Ids: O4 (refusal review), B-O4-1 to 7, B-W1B-2.*

## In short

The owner's O4 ruling (2026-10-12): a full re-layout at the interpolated frame
each animation frame. A removed member stays where it was while it leaves; a
carried member floats over every view while it moves; the zoom transition is a
reveal, and a push zooms under the default animation. Since 2026-10-26 a zoom
scales and moves the Kitty pictures it reveals (graphics notes §14) — since
2026-10-27 from the source's frame to their own, so a photo lands exactly on
its thumbnail (Deliberate deviations A9).

## The record

### B-O4-1. A removed member stays where it was while it leaves

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

SwiftUI carries the removed view toward the inserted one's frame while its
removal transition plays (`mg3` A1, A2). TUI draws a removed view from the
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
`.opacity` does — which moves `fadingOverlays` down to `TUIView`, beside
`DefaultTransition` — so a carried view fades in as it moves, and an
`.offset` child fades with its `if`. About half a day with tests; it touches
the transition code lane FB16 is changing, so it waits for that lane. Whether
a carried view should fade at all in a terminal is worth a look then: a solid
view moving reads better on a cell grid than one fading in as it moves.

**Done 2026-10-19 (lane TRANSITIONS2).** Both fades reach a view's layers
drawn past its slot (`OpacityFading`, moved down to `TUIView`): a carried
view fades as it moves, and an `.offset` child with its `if`, as SwiftUI's do
(`mg3.out` A1, A2; `Tools/SwiftUIProbes/Transitions/tr3.out` T14, T15).

### B-O4-3. With two sources, the last one drawn is the group's, and the others keep their own frames

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

Apple's documentation calls more than one source undefined. SwiftUI was
measured giving followers the later source's frame, and giving it to the
earlier source too (`mg1` S10). TUI gives followers the last source drawn,
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

- **Which animation.** TUI's stack changes at once, and a `NavigationLink`
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
[B-W1B-2](#b-w1b-2-a-zoom-sources-clip-shape-and-shadow-shrink-to-nothing-as-the-rectangle-grows).

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

### B-W1B-2. A zoom source's clip shape and shadow shrink to nothing as the rectangle grows

*`MatchedTransitionSourceConfiguration.clipShape(_:)`,
`MatchedTransitionSourceConfiguration.shadow(color:radius:x:y:)`*

The zoom (B-O4-5) is a rectangle growing from the source's frame to the stack's.
The source's clip shape cuts the rectangle's corners — a cell kept where the
shape covers at least half of it, the rule `clipShape(_:)` keeps
(B-W1-11) — and the screen it grows over shows in the corners cut away; its
shadow is cast from the rectangle, or from the clip shape where there is one,
onto that screen, in cells as every shadow here is (C10), and is cut at the
stack's edge. SwiftUI interpolates a source's configuration into the
destination's (Apple's documentation; the zoom is iOS-only, so not measured);
a pushed screen has neither, so the radius shrinks with what is left of the
zoom and the shadow's alpha fades with it, the source's at the start and
nothing once the rectangle is the stack's.

While a corner is cut, a click there reaches the screen being uncovered, not
the one showing through: the hit regions are the screen's whole rectangle, as
they were before the clip.

**The fuller version:** the screen's hit regions cut with its corners — an
hour, with the mask a `contentShape` uses (B-W1B-3).
