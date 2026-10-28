# Inserting and removing views: transitions and the default fade

*How views arrive and leave: SwiftUI's insertion and removal model as measured
(frames glide, a leaving view keeps its room and is drawn beneath), the
default fade for what is not an `if`, custom and scale transitions, content
transitions, `BlurReplaceTransition`, and what it all cost. Ids: A40, B52,
B54, B61, A34, FB16 (a′), A-FB16-1, B-FB16-1 to 13, A-TRANSITIONS2-1,
B-TRANSITIONS2-1 to 4, B-TR2PERF-1 and 2.*

## In short

SwiftUI's model, measured in a real app on macOS 15.8: when a container's
children change, every view whose frame changes glides to its new frame, a
leaving view keeps its room and is drawn beneath its siblings, and the eager
stacks, `ZStack` and a `Layout` glide in whole cells; lazy stacks, `Grid`,
`List` and `Table` change at once. A branch, a case or a row fades in with no
`.transition` written; it goes at once, except an `if`'s view, which keeps its
fade-out. A content change dissolves each text and image.
`.transitionSpace(.held)` is the TUI-only opt-out. A container's own size still
changes at once (A-FB16-1, never answered).

## How it unfolded

1. **2026-10-14, the owner on the default transition:** prototype B (fade
   both ways) with an A/B, falling back to C (fade in only) if costly.
2. **2026-10-18, FB16 (a′):** SwiftUI's measured model; lane FB16 built it
   (positions, not a container's own size: A-FB16-1).
3. **2026-10-19, lanes TRANSITIONS2 and TR2PERF:** the default fade where a
   container remembers its children, then its cost cut by making the default
   fade in only (B-TR2PERF-1), keeping an `if`'s fade-out.
4. **2026-10-23 to 24, VISUALS:** A34 option 2 (`BlurReplaceTransition` as a
   scale and a fade); B61 option 2 (the dissolve in `Text` and `Image`),
   landing within a few percent.

## Where it stands

Shipped. **Open:** A-FB16-1 and A-TRANSITIONS2-1 (both recommended as they
are).

## The record

### A40. Should a content change dissolve by default under an animation?

*`EnvironmentValues.contentTransition`'s default; the drawing of `Text` (and
`Image`) when what it shows changes inside `withAnimation`*

SwiftUI's environment holds an unnamed default content transition (measured:
equal to none of `.identity`, `.opacity`, `.interpolate`), under which a
`Text` whose string changes inside an animation cross-fades. TUI's default
draws the change at once, as it always has; `contentTransition(_:)` shipped
(B61) dissolves only where it is written.

**Options.**

1. **Keep the default instant.** Free. A port that relied on the default
   cross-fade snaps until it adds `.contentTransition(.opacity)`.
2. **Dissolve by default, in `Text` and `Image`.** Each keeps its last
   drawing and dissolves to a changed one under an animated transaction, as
   the modifier does for a subtree. The price is in the hottest view there
   is: every `Text` drawn under an animation compares its lines with the last
   frame's and, while a change dissolves, draws twice; and every `Text` keeps
   one drawing in state storage. A day, plus the A/B on `Stress` that a change
   to `Text` needs.

**Recommendation:** 1, until a port shows the default being relied on.

**Your answer of 2026-10-04:** inclined to option 2, unless it costs when
nothing is animating. **Agreed on 2026-10-05:** to dissolve from old to new,
each `Text` needs its previous drawing kept from before the change, which is a
cost on every frame of every app, not only while animating; so the option is
A/B'd first, and option 2 is adopted if that costs under about 1%. The A/B is
owed on the quiet machine. The recommendation above predates both.

**Measured on 2026-10-15: kept instant, as agreed.** A prototype (session notes
`A40/`) kept each `Text`'s last drawing in state storage, at an identity of its
own, and dissolved from it when its glyphs changed under an animation (a change
of colour alone left to the colour's animation). It passed the suite and cost,
warm, with nothing animating: `fanout` +500%, `anyview` +100%, `modifiers`
+97%, `textwall` +69%, `scrollfollow` +53%, `dashboard` +40%, `menus` +13.5%;
`table` +0.2%. The price is the record every drawn text writes — a boxed value
in the tracked-value table, a live mark, and the pass's sweep over them — and
any design that dissolves from the last drawing has to keep that drawing
somewhere for every text, since nothing else keeps it. So a port that relies
on the default cross-fade still snaps until it writes `.contentTransition(.opacity)`.

### B52. A custom transition's body is drawn at each frame's point between its phases

*`Transition` (`body(content:phase:)`, `Content`, `properties`,
`animation(_:)`, `combined(with:)`, `apply(content:phase:)`),
`TransitionPhase`, `TransitionProperties`, `PlaceholderContentView`,
`AnyTransition.init(_:)`, `AnyTransition.modifier(active:identity:)`,
`View.transition(_:)` for a `Transition`*

**How SwiftUI does it.** A transition's body is evaluated at three discrete
phases. On insertion it is shown at `.willAppear` and then "immediately moved
to the `identity` phase" under the change's animation; on removal it goes from
`.identity` to `.didDisappear`. Nothing about the body is continuous: what
moves are the animatable modifiers inside it, each interpolated between the
value it had at one phase and the value it has at the other. "If no animatable
change is applied, then the transition will be a no-op."

**How TUI had it.** A transition was a value — `AnyTransition`'s closed set
of effects — applied to the view's rendered buffer as a function of one number,
how present the view is (0 absent, 1 there, above 1 while a spring overshoots).
An insertion reads that number from the animation store as the view arrives; a
removal leaves a closure behind every frame, "here is what I look like part-way
gone", which whatever holds its slot plays out over the picture the view last
drew (`DepartureStore`). All of that stays exactly as it was.

**What shipped: a custom body is drawn by scrubbing it.** For a presence `p`
on any frame of an arrival or a departure, the body is rendered twice:

1. **Record**, at the end phase (`.willAppear` arriving, `.didDisappear`
   leaving), with the content standing in as an empty box of its own size.
   Every animatable value the body produces — an `Animatable` view or
   modifier's data, and the colours `.foregroundStyle`, `.background` and
   `.border` resolve — is noted, keyed as the animation store keys it (place
   in the tree, owning type, slot), and nothing is drawn.
2. **Draw**, at `.identity`, with the real content, and each of those values
   replaced by `end.interpolated(towards: identity, amount: p)`.

That is the same arithmetic the animation store performs when a value animates
(`from.interpolated(towards: to, amount: curve(t))`), with `p` already being
`curve(t)`, so the picture is the one SwiftUI's per-modifier interpolation
gives. Both passes go through one hook at the top of the store's lookup, so a
scrubbed value never reaches, or disturbs, the store's own records. A value
built FROM one drawn part-way — inside the body of an animatable modifier,
evaluated at its interpolated data — is drawn as built, not interpolated a
second time; what a placeholder draws (the view a modifier is applied to) is
not built from the modifier, and is scrubbed on its own account.

Everything else is reused rather than rebuilt: the arrival phase and its
explicit animation, the departure slot and its timing, a removal starting
mid-insertion from where the arrival had got to, a spring's overshoot (`p`
above 1 extrapolates, so an `.offset` in a body bounces past its slot and an
`.opacity` stops at opaque, both as the built-ins do), and the rule that only
an animated change transitions.

**The content is live while the view is present.** The placeholder draws the
real view, at the transition's own identity (so its `@State` is where it would
be without the transition), under the environment the body gives it — a body's
`.foregroundStyle` or `.disabled` reaches it, as in SwiftUI. While the body is
being recorded the placeholder draws nothing, so the content's side effects
(focus, hit regions, `onAppear`) happen once a frame, as they always have.
At rest the body is drawn at `.identity` every frame: SwiftUI applies it for as
long as the view is visible, and a body is allowed to leave something there.

**Where TUI cannot follow SwiftUI, and why.**

- **A departing view's content is a picture.** A removed view does not exist
  any more — that is what `DepartureStore` is for — so while it leaves, the
  body is drawn around the cells the content drew on its last frame. The
  body's own modifiers still move: its opacity, offset, colours. What the body
  would have changed *inside* the content (an environment value that differs
  between `.identity` and `.didDisappear`) does not change any more once the
  view has gone.
- **The slot is the size of the `.identity` body.** A body that changes the
  view's size between phases (`.frame(height: phase.isIdentity ? nil : 0)`,
  a collapse) is drawn inside the size it has at rest, rather than re-laying
  out its siblings on every frame. TUI's transitions have never moved
  their neighbours (see `AnyTransition`); this is the same rule applied to a
  custom body. (Since 2026-10-18 the neighbours glide with the change of
  layout itself, as SwiftUI's do — decisions FB16; a transition still never
  changes the size of the view it plays on.)
- **A body that changes its structure between phases does not animate the
  difference.** A value is interpolated only where both renders produced it
  at the same place; a modifier present at one phase and not the other is
  drawn as the `.identity` render has it. SwiftUI asks for the same
  ("Transitions should not use any identity-affecting changes like `.id`,
  `if`, and `switch`").

**The built-in transition types** (`OpacityTransition`, `MoveTransition`,
`OffsetTransition`, `ScaleTransition`, `SlideTransition`, `PushTransition`,
`IdentityTransition`, `AsymmetricTransition`) have real bodies, built from one
animatable modifier that applies TUI's own effect at the body's presence —
so `OpacityTransition().apply(content: v, phase: phase)` inside an app's own
transition fades exactly as `.opacity` does. Erased to `AnyTransition` (which
is what `View.transition(_:)` does with any `Transition`), they keep the
buffer fast path; only a transition with a body of the app's own takes the
two-pass route.

**What it costs.** Two body renders a frame while a custom transition plays
(the first draws no content); one at rest, which is what any `ViewModifier`
body costs. The built-ins cost what they did.

**The fuller version.** Animate the layout too: measure the body at the
interpolated values each frame, so a collapsing transition closes its gap as
it goes. That is a re-layout of the transition's container per frame — the
cost the buffer-based design exists to avoid — and needs the measure walk to
scrub as well, which the memoised measure path makes delicate. About two days.
I would wait for a port that needs it.

**Measured and put to you again (2026-10-19, lane TRANSITIONS2):** since
FB16 the neighbours of a collapsing transition glide with the change, which
closes its gap as SwiftUI's does in every container that glides (measured,
`Tools/SwiftUIProbes/Transitions/tr1.out` T7); the container is already laid
out again on every frame a transition is on screen. What is left, and its
price, is decisions
[A-TRANSITIONS2-1](#a-transitions2-1-b52-a-custom-transition-that-changes-its-views-size--lay-the-body-out-at-each-frames-size).

### B54. A scale transition uncovers from its anchor, and a scale above 1 draws the view whole

*`ScaleTransition` (`init(_:anchor:)`, `scale`, `anchor`),
`Transition.scale`, `Transition.scale(_:anchor:)`,
`AnyTransition.scale(scale:anchor:)`*

TUI's `.scale` already reveals the view from its anchor a whole cell at a
time, there being no sub-cell rendering to shrink. The scale factor is now
where that reveal starts: `.scale(0.5)` shows half the view at once and
uncovers the rest. `.scale` itself is `ScaleTransition(1e-5)`, SwiftUI's own
value (measured) — nothing, in whole cells.

A factor above 1 asks for the view to start larger than its slot. A cell grid
cannot draw that: the reveal is clamped at the whole view, so the transition
draws the view whole from the first frame. `opacity` above 1 is clamped the
same way in SwiftUI itself.

TUI's own spelling, `AnyTransition.scale(anchor:)`, was not SwiftUI's and is
gone; `scale(scale: 0, anchor:)` is the same transition.

**The fuller version** would draw an oversized start by cropping the view to
its middle and widening the crop as it settles — a zoom-out rather than a
grow. Nothing in TUI crops from the middle today; half a day, and I would
wait for someone to ask.

### B61. A content transition dissolves each text and image

*`ContentTransition` (`.identity`, `.opacity`, `.interpolate`,
`.numericText(countsDown:)`, `.numericText(value:)`), `View.contentTransition(_:)`,
`EnvironmentValues.contentTransition`,
`EnvironmentValues.contentTransitionAddsDrawingGroup`*

The Wave 17 review (W4) found the refusal ("a cell holds one glyph with no
alpha") overtaken by opacity compositing. **Shipped:** where the modifier is
written, a change to what its content draws, made under an animation, draws
the new content over the old at the animation's progress through the opacity
compositor: colours blend and each cell's glyph changes half way, so a cell
whose character is the same keeps it and moves only its colours. That is
`.interpolate` here (SwiftUI's "matching glyph pairs" interpolate, and the
rest use its documented opacity fallback); `.opacity` and both
`.numericText` forms draw the same dissolve (SwiftUI's rolling digits are
promised only "in certain environments"); `.identity` draws the change at
once. A change in mid-dissolve dissolves from the last drawing, so a burst
of changes is followed one change behind. The dissolve counts as an
animation for completions.

**Per leaf, as SwiftUI's** (owner ruling of 2026-10-23, option 2; lane
VISUALS, 2026-10-24). Each `Text` and each raster `Image` reads the value as
it draws and dissolves its own change; a symbol image is a `Text` and
dissolves there. So an inner `.contentTransition(.identity)` exempts its
part, and `.environment(\.contentTransition, …)` works as the modifier does.
The modifier only sets the environment value. What is not a text or an
image (a shape, a colour, a control's chrome) changes as it would without
the modifier, an animatable one animating, as in SwiftUI. Until then the
modifier dissolved its whole subtree's drawing, and an inner `.identity`
exempted nothing (deviations A4 as it was).

The price is A40's, confined: a leaf keeps its last drawing only where a
transition that dissolves is in force, in a record at an identity of its
own (`ContentDissolve`, TUIFoundation); everywhere else each `Text` and
raster `Image` pays one environment read a draw (a `Bool`,
`contentDissolves`, written by `\.contentTransition`'s setter, since the
leaves cannot see `ContentTransition`'s module). The ruling lands it if the
A/B on text-heavy scenarios is within a few percent; see the lane file
`Shapes, effects and animation/Visual effects rulings (VISUALS).md`.

**Where it still differs.** The leaf dissolves where SwiftUI interpolates
glyph shapes or rolls digits, and takes its new size at once (a shrinking
drawing loses its edges immediately). `contentTransitionAddsDrawingGroup` is
a rendering hint with no visible contract (a drawing group changes how
SwiftUI composites, not what it shows) and is kept for whoever reads it. The
symbol-effect content transitions shipped with A35 on 2026-10-05 (on macOS:
a fade of the symbol).

**A40's default dissolve** (every text, with nothing written) stays off: it
is this record kept for every text everywhere, measured at up to +500%.

### A34. `BlurReplaceTransition` is its scale and a fade

*`BlurReplaceTransition` (`Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`; ruling: option 2.*

**What SwiftUI does** (measured on macOS 15.8, macOS 26.2 SDK,
[`Tools/SwiftUIProbes/Transitions/tr4.swift`](../../../Tools/SwiftUIProbes/Transitions/tr4.swift),
a 200×100 view under a 2 s linear animation): besides the blur, the view
scales about its centre between **0.9** and its full size and fades linearly
between 0 and 1. `.downUp` arrives from 180×90 and leaves to it; `.upUp`
arrives from 180×90 and leaves to 220×110. `properties.hasMotion` is `true`
(`Animation curves, springs and keyframes/p1.swift`).

**What TUI draws.** The blur is drawn as the fade: at a cell's resolution a
blurred view reads as a faded one, and the opacity compositor already
dissolves its colours toward what is behind it. The scale is the `.scale`
reveal (B54) from 0.9 of the view at its centre. So `.downUp` erases to
`.scale(scale: 0.9, anchor: .center).combined(with: .opacity)` both ways, and
`.upUp` to that on insertion and `.opacity` alone on removal: a reveal cannot
draw a view larger than its slot. Under reduce motion it is a fade, as every
transition with motion is.

**Option 3**, a cell blur, was not built. The follow-up answer in the owner
decisions file prices it and ties it to O5-FROSTED's neighbour sampling.

### B61. Each text and image dissolves its own change

*`View.contentTransition(_:)`, `EnvironmentValues.contentTransition`; ruling:
option 2, landing if the A/B on text-heavy scenarios is within a few percent.*

**Shipped on the lane, waiting on the A/B.** The modifier only sets
`\.contentTransition`. Its setter also writes a package `Bool`,
`contentDissolves`, which TUIFoundation's leaves can read without seeing
TUIEffects' type. `Text.renderToBuffer` and the raster image host end in
`ContentDissolve.drawn(_:context:)`, which reads that `Bool` (after the
measure check) and returns the drawing unless a dissolving transition is in
force. Where one is, the leaf keeps its last drawing, the outgoing one and
the animation in a tracked value at a child identity of its own, as the
modifier kept them for its subtree, and draws the dissolve at a second one.
A symbol image is a `Text` and dissolves there. A text that draws another in
its place (relocalized, or a live text) asks that one for its undissolved
drawing, so the record is kept once.

**What it costs where nothing is written,** counted, not timed: one
environment read per `Text` and raster `Image` draw, a dictionary lookup of
an `ObjectIdentifier` in the environment's storage, and nothing kept. A40's
prototype kept a record for every text and cost up to +500%; this keeps one
only under a written transition. Under one, the cost per leaf per frame is
A40's: a child identity, a tracked value read and written, a live mark.
Where the modifier used to wrap a subtree in one record, a subtree of N
texts now keeps N.

**Judgement calls.** What is not a `Text` or an `Image` no longer dissolves
under the modifier: a shape or a colour animates its own change, as
SwiftUI's leaves do, and a view of an app's own that draws cells itself
(`Renderable`) changes at once. A table's cells dissolve only where they are
drawn through `Text`.

**For the A/B:** `textwall`, `fanout`, `menus` (the ruling's), and `anyview`,
`modifiers`, `dashboard` and `scrollfollow`, the scenarios most sensitive to
a per-`Text` cost in A40's measurement. None writes a content transition, so
they measure the environment read alone.

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

**Built 2026-10-28** (the owner's A-TRANSITIONS2-1, "all"): a grid's cells
are one flat list at the grid's identity, each with its own resolved
identity, so the eager stacks' glide takes them whole — every cell, its
picture and its place in the grid — and draws them where each has got to.
Still open: a departure slot in a row keeps its room (the lattice is grouped
by the rows' marks, which a slot taken out would disturb). `GridGlideTests`.

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
removal should draw on top. TUI draws it so: beneath the present children
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

### A-TRANSITIONS2-1. B52: a custom transition that changes its view's size — lay the body out at each frame's size?

*`Transition` with a body of the app's own, B52; owner rulings 2026-10-04
("measure the per-frame re-layout cost first") and 2026-10-18 (FB16 (a′))*

**What SwiftUI does** (`tr1.out` T7, T7b, a `Transition` whose body sets
`.frame(height: phase.isIdentity ? nil : 0)` on a 60-point view between two
10-point ones, under an 8 s change): the view's frame grows and shrinks, and
the view below moves with it in step — 70 → 63 → 55 → … → 10 as it folds
away, 10 → 17 → 25 → … → 70 as it opens.

**What TUI does now.** The body is drawn by scrubbing between its phases
(B52) inside the size it has at rest, and since FB16 the layout changes at
once and every child whose place changed glides there with the change: the
row below goes 70 → 10 as the view folds, in step with it when the
transition runs under the change's animation, which is SwiftUI's picture in
an eager `VStack`, `HStack`, `ZStack` or `Layout`. The folding view's own
picture shrinks inside its slot as the body is scrubbed. Stress's
`session/glides` now plays such a transition (`GlidesFold`), under the memo
verifiers and as a benchmark (`--bench --scenario session/glides`, which
`ab_bench.py` can A/B), so the transition no longer lacks a scenario.

**What the per-frame re-layout costs — measured by construction.** A view
with a transition declares a render side effect on every frame it renders,
at rest as well as while it plays (`_TransitionView`: its departure is
re-declared each frame, which no memo may skip), so the container it is in is
laid out again on every frame already, whether or not anything plays, and
FB16's glides lay out every container a change animates again on each frame
of the change. What B52's fuller version adds is one measure of the body at
each frame's phase, scrubbed, while it plays — about the cost of one of the
two scrubbed renders it already makes — and a slot whose size follows it.

**The options:**

1. **Leave it** (shipped). Free. Differs from SwiftUI where the view's
   neighbours do not glide — a lazy stack, a `Grid`, a `List`, a `Table`,
   and a removal's room in a `Layout` (B-FB16-2 to B-FB16-5), where the room
   goes at once after the removal has played; where the transition's own
   animation differs from the change's, so the neighbours glide on the
   change's clock and the body on its own; and in the size of the container
   round it, which changes at once (A-FB16-1).
2. **Lay the body out at each frame's phase** in the containers that glide:
   the slot takes the scrubbed body's size each frame, and the neighbours
   follow it rather than gliding. About two days (the measure walk has to
   scrub too, and the measure memo must not keep a scrubbed size); one
   scrubbed measure of the body per playing frame. Fixes the second
   difference above only.
3. **SwiftUI's whole model** — every frame of every view glides, sizes
   included — is A-FB16-1's option 3, not priced.

**Recommendation:** 1. The case B52 was opened for — a collapsing transition
whose gap does not close — closes now, through FB16, in every container that
glides; what option 2 would add is visible only where a transition names an
animation different from its change's.

### B-TRANSITIONS2-1. A branch, a case and a row fade in where a container remembers its children

*`ChildFade`, `PlacementStore.Record`, `View.transition(_:)`*

**Since 2026-10-19 they fade in only, and go at once** (decisions
[B-TR2PERF-1](#b-tr2perf-1-a-branch-a-case-and-a-row-fade-in-and-go-at-once)).
The fade-out this lane shipped kept the picture of every child of every eager
container from one frame to the next. The A/B priced that with nothing
animating at up to +7.2% a frame (`tables-scroll`), +2–3.5% across a dozen
scenarios, and `deep`'s footprint 17.1 → 32.6 MB. The middle way below,
prototyped, still kept the rows and branches that `churn` and `deep` are made
of, so the owner's fallback of 2026-10-14, fade-in only, was taken. What
follows is this lane's work as it stands now.

SwiftUI fades a view in and out with no `.transition` written — an `if`/`else`
whose branch flips, a `switch`'s case, a `ForEach`'s row alike (`tr1.out`
T1–T3): the view leaving fades where it was, drawn beneath its siblings, the
new one where it lands, while the views below glide. An `if` already did
(2026-10-14), by a record of its own, since it renders both ways. A branch, a
case and a row cannot report themselves: the branch not taken is not
rendered, and a row that has gone has no element left to render.

**What shipped:** the container that places them does it. An eager `VStack`,
`HStack` or `ZStack` and a `Layout` already remember where each child was
(lane FB16's `PlacementStore`). On a change under an animation, a child they
are handed for the first time fades in where it lands. A child's presence is
an animated value under the container, as its glide is, so a `withAnimation`
completion waits for it, and reduce motion, which holds motion still
(A-D3M-1), lets it play: a fade is not motion. One they no longer are handed
goes at once (it faded out where it was, beneath the others, from a picture
of its last frame the container kept, until lane TR2PERF).

The same memory plays a transition of the view's own: a branch or a row
carrying one plays its removal where it was, from what it left in the
`DepartureStore`, where nothing could before (the branch an `if`/`else` left
was replaced at once). A view the container held behind something that draws
round its transition (`X.transition(t).padding()`) goes at once; such a view
in an `if` fades its whole picture instead, padding and all, from the `if`'s
record (it snapped).

A conditional drawn whole — a view's whole `body`, a modifier's content,
not taken apart by a stack — fades the branch it takes in, and plays the
own transition of the branch it leaves, from the record of the branch it
took, which it already wrote every frame (`ConditionalRecord`,
`BranchTransition`; B-TRANSITIONS2-2).

**What it costs.** A settled eager container writes nothing, as before; an
empty one looks its record up, so that a row arriving in it fades in. A
conditional drawn whole writes a record of eight bytes in one in-place access
where it wrote a `Bool` in a lookup and a store. A change under an animation
works out the identities of what came and went. TR2PERF's profiles and the
A/B owed for this are in B-TR2PERF-1.

**A middle way, measured and not taken:** keep the pictures only of children
that can go — a `ForEach`'s rows, a branch, a case, an `if`'s views — and not
of a tuple's plain members, which cannot leave while their container stays.
TR2PERF prototyped it: `churn`'s column still kept 300 rows drawn afresh each
frame, and every level of `deep` still kept its branch's picture (footprint
37.3 MB). Rows and branches are exactly what it keeps.

**The fuller version:** the fade-in in the containers that keep no memory of
their children yet — a lazy stack, a `Grid`, a `List`'s and a `Table`'s rows,
where a branch, a case and a row still change at once (deviations, Slated).
Each needs the placement memory first, priced with it in decisions FB16
(B-FB16-2, B-FB16-3, B-FB16-5): about two days for the lazy stacks, half a
day for `Grid`, and the list's row work for `List` and `Table`. Fading out
as well is B as this lane shipped it; its price is above.

### B-TRANSITIONS2-2. A conditional drawn whole draws the branch it leaves over the one it takes

*`BranchTransition`, deviations A6*

SwiftUI draws a view's two branches overlapping at its origin while they
cross-fade, the one leaving beneath (`tr1.out` T8). A conditional drawn whole
has no canvas of its own to draw beneath on: its layout is the new branch's,
at once, and only a container composites a fade against what is beneath it
(`FrameBuffer.layered`, in `TUIFoundation`; the conditional is in
`TUIView`, below it). So the branch leaving is drawn past the conditional's
frame, as content drawn past a view's region is (`FrameBuffer.drawnPastSlot`),
which lands it over the new branch. For two fades crossing, over and beneath
are the same blend with the weights swapped: half-way, each is half there.
What it covers past the new branch's frame is covered over, not under, as an
overflow is. It takes no clicks. Since 2026-10-19 only a branch leaving by a
transition of its own is drawn so: one with none goes at once
(B-TR2PERF-1).

**The fuller version:** move the layering compositor (`FrameBuffer.layered`
and the claims it resolves, `FrameBuffer+ClaimsOverNothing.swift`, with the
wake its runs ask for) down into `TUIView`, so a conditional can draw the
leaving branch beneath. About a day, most of it the module move and its
checks (`Tools/ModuleMap`); nothing a user would see but the order of two
fades.

### B-TRANSITIONS2-3. `.transitionSpace(.held)` holds an `if`'s room, not a branch's or a row's

*`View.transitionSpace(_:)`*

The opt-out holds the room of a view an `if` takes out, whose `nil` keeps a
slot the stack can lay out at the view's size. A branch, a case and a row
that have gone are not children any more: the stack lays out what it is
handed, and fades the one that went where it was, while the rest close up
over it. **The fuller version** would give the stack a slot of the view's
size for each child that went, laid out until it has played — the slot an
`if` keeps, made by the stack. About half a day; it would change the
indices every container's layout sees for the length of a removal, which is
what B-FB16-4 found costly in a `Layout`.

### B-TRANSITIONS2-4. A combined transition plays under one animation for each half

*`AnyTransition.combined(with:)`, deviations A3*

Each half of an `asymmetric` transition now keeps its own animation, and an
animation written outside a transition leaves a half that has its own alone,
`nil` included, as SwiftUI's do (`tr1.out` T4, T5; `tr2.out` T9–T11, T13). A
`combined` pair is one effect with one presence, so each half runs under one
animation: the first part's own, or else the second's. SwiftUI runs each part
under its own (`tr2.out` T12: two fades of two and eight seconds multiply).
**The fuller version** keeps an animation per part of a combined effect and a
presence per animation — an arrival phase per animation in the store, and a
departure that plays several clocks. About a day, for a transition whose
parts disagree about their timing, which is rare.

### B-TR2PERF-1. A branch, a case and a row fade in, and go at once

*`ChildFade`, `BranchTransition`, `PlacementStore.Record`, `ConditionalRecord`;
Deliberate deviations A10*

**What B cost with nothing animating.** The coordinator's release A/B of
`Stress`, W1B against W1B + TRANSITIONS2 (2026-10-19; 32/32 frame checksums
the same; box at load 11). Almost none of its scenarios animate, so this is
B's price with nothing animating: `tables-scroll` +7.2% (CI +2.1..+10.6), `churn`
+3.5%, `menus` +3.4%, `kitchensink` +2.9%, `table-churn` +2.9%, `deep` +2.7%
with its footprint 17.1 → 32.6 MB, `fanout` +2.6% (+3.7 MB), `textwall`
+2.0%, `tables-vstack` +2.0%, `keyrows` +1.9%, `framedcolumns` +1.3%, and 16
indistinguishable.

**Where the time went** (Time Profiler, 10 s a scenario,
`perf/profile1017.sh`; release builds inline differently, so these are the
frames TRANSITIONS2 added or grew, as inclusive shares of each trace):

| Scenario | W1B | TRANSITIONS2 | What it is |
|---|---|---|---|
| `tables-scroll` | `glidingPlacements` 0.4% | 2.5%; malloc 12.3 → 14.1% | the root column freeing last frame's pictures, mostly the scroll view's viewport; buffers living a frame longer |
| `churn` | `glidingPlacements` 2.8% | `glidingStackBuffer` 5.9% | 300 rows of four, each row's stack keeping its members' pictures; freeing `FrameBuffer`s 1.4 → 2.5% |
| `menus` | 0.4% | 1.7% | the stacks' stored pictures |
| `deep` | `recordConditionalBranch` 1.3% | `ConditionalView.present` 2.7%, `glidingStackBuffer` 2.6% | every level's conditional and column keeping what the levels below drew |
| `kitchensink` | 0.2% | 0.9% | the stacks' stored pictures |

The pictures, then, and not only the stored array. Kept from one frame to the
next, they cost a release each frame, frees that happen a frame late, a
heap that holds two frames of buffers instead of one, and the footprint
(`Stress --bench`, `footprint-peak`: `deep` 16.7 → 45.7 MB, `fanout` 26.4 →
32.4 MB at 120×40).

**The middle way, measured.** B-TRANSITIONS2-1 priced a middle way at about
half a day: keep pictures only for the children that can go, which are a
`ForEach`'s rows, a branch, a case and an `if`'s views, and not for a tuple's
plain members. A prototype did that (a child kept its picture if it had a key,
a resolved identity, a default transition or a departing slot; a container
none of whose children could go stored nothing). It was not committed. Its
profile against the two above:

| Scenario | Middle way | Still kept |
|---|---|---|
| `tables-scroll` | `glidingStackBuffer` 1.5% | the rows of the column inside the scroll view |
| `churn` | 4.8% | the column's 300 rows, drawn afresh each frame |
| `menus` | 1.0% | the menus' rows |
| `deep` | `ConditionalView.present` 2.5% | every level's branch: a nested page is branches |
| `kitchensink` | 0.5% | |

Footprint: `deep` 37.3 MB, `fanout` 32.1 MB. What the middle way keeps is by
definition what can go, and in these scenarios that is rows and branches, so
it couldn't get `churn` or `deep` to about 1%. The owner's fallback applies.

**What shipped: C, fade-in only.** A branch, a case or a row that a change
puts in under an animation fades in where it lands, as before. One the change
takes out goes at once, as before TRANSITIONS2, unless it carries a
transition of its own: that removal still plays where it was, from what the
view left in the `DepartureStore` (TRANSITIONS2's own-removal, under the
change's animation or one the transition names). A conditional drawn whole
does the same at its origin. Nothing keeps a picture any more:
`PlacementStore.Record` has no `pictures`, and `ConditionalRecord` is eight
bytes, a pass and four flags, where it held a `FrameBuffer` and a leaving
branch's (`ConditionalRecordTests`).

A settled container does what it did before TRANSITIONS2: it looks its record
up, as FB16's glides need, and writes nothing. An empty eager stack or
`Layout` still looks its record up each frame. That keeps the record alive
for a row arriving in it to fade in, and lets a last row with a transition of
its own play its removal; it is one dictionary probe per empty container, and
it was not hot in any profile.

Kept from TRANSITIONS2: each half of an asymmetric transition's own animation,
`.animation(nil)`, a transition's own removal played by the stack, B-O4-1 (a
matched view leaving is carried with the one arriving, for a removal that
plays: an `if`'s view, or one with a transition of its own), B-O4-2, and the
stale-record fix.

What changes for an app: the branch an `if`/`else` leaves, a `switch`'s case,
a `ForEach`'s row and the views of an `if` holding several now vanish on the
frame of an animated change, where SwiftUI's fade out. The views around them
glide into the room as before. A hero written as `if`/`else` with
`matchedGeometryEffect` draws the arriving view carried from where the one
leaving was, but not the one leaving, unless that one is given
`.transition(.opacity)`, which is SwiftUI's default written out.

**Measured on C** (the same profiles; footprints from `Stress --bench` at
120×40, warm at 300 frames, the ranges over three runs on a busy box):

| Scenario | W1B | TRANSITIONS2 | C |
|---|---|---|---|
| `tables-scroll` | 0.4% | 2.5%, malloc 14.1% | 0.9%, malloc 12.6% |
| `churn` | 2.8% | 5.9% | 3.9% |
| `menus` | 0.4% | 1.7% | 0.7% |
| `deep`, the conditional | 1.3% | 2.7% | 1.0% |
| `deep`, the columns | 0.4% | 2.6% | 0.4% |
| `kitchensink` | 0.2% | 0.9% | 0.4% |
| `deep` warm, footprint-peak | 16.7 MB | 46.3 MB | 16.7 MB |
| `deep` warm, rss-peak | 24.7 MB | 57.8 MB | 24.8 MB |
| `fanout` warm, footprint-peak | 24.9–27.2 MB | 33.5–34.0 MB | 29.8–30.8 MB |

The cold footprints the A/B reported growing (`kitchensink` 72.8 → 124.5 MB,
`deep`, `dashboard`) varied by more between runs of one binary than between
the three binaries here: `kitchensink`'s cold rss-peak was 104–136 MB for
each. `churn`'s column check is still about a point above W1B's, in copies
of each child's `FrameBuffer` and `ChildView` that W1B's build had inlined
away. Frame checksums: the same as TRANSITIONS2's in all 33
scenarios, `session/glides` and `animating` included.

**The A/B owed:** this branch against W1B and TRANSITIONS2 on `tables-scroll`,
`churn`, `menus`, `kitchensink`, `deep` and `fanout`, cold and warm, with the
footprint beside the time.

**The fuller version: B, fade both ways.** That's TRANSITIONS2 as shipped,
whose price is above. A design that fades out with no memory kept from frame
to frame would need the picture from somewhere else: the render cache already
holds a memoised row's last buffer, so a row the cache served could fade out
from that at no cost to frames where nothing changes, while a row drawn
afresh, or a branch, would still go at once. That's untried; I'd guess about
a day, and it covers memoised rows only.

### B-TR2PERF-2. An `if`'s view keeps its fade-out

*`DefaultTransition`, `OptionalPresence`; Deliberate deviations A10*

Fade-in only (B-TR2PERF-1) applies to what lane TRANSITIONS2 added: a branch,
a case, a row, and a conditional drawn whole. An `if`'s view fades out as well
as in, as it has since 2026-10-14. That was B for the `if`, finished after its
own A/B (2026-10-14, "B2": warm `keyrows` +1.7%, `menus` +1.2%; cold `menus`
+3.4%; the rest indistinguishable), and fade-in only was found no cheaper
there: an `if` needs a record either way, to tell an arrival from a first
sight. Its `if` keeps what the view drew on its last frame, one picture per
`if`, in the record it writes every frame anyway, now in one access (lane
TRANSITIONS2). That cost is in both binaries of the A/B in B-TR2PERF-1, so
that A/B doesn't price it.

So `if a { X }` fades `X` out, and `if a { X } else { Y }` lets `X` go at once.
In a stack, an `if` whose content is several views, a `Group` (with a modifier
on it or not) or an `if`/`else` of its own lets them go at once too: those are
the stack's children, not the `if`'s. So does the view of an `if` with `.id`
written on it. Each fades in, as a row does; TRANSITIONS2's stack faded each
out from the picture it kept (`BranchAndRowFadeTests`, the handed-over
shapes; `TransitionRemovalAddressTests`). Rendered directly, as a view's whole
`body` or a modifier's content, an `if` holds whatever it holds and fades it
out.

**The fuller version:** one rule for every default. Fading in only here too
would drop the `if`'s picture, and an `if`'s view with no transition would go
at once: about half a day, with the tests of the `if`'s fade-out
(`DefaultTransitionTests`, `TransitionTests`, the Example's
`AnimationPageShowHideTests`) changing, and an A/B to say what the picture per
`if` costs. Not done: one picture per `if` is a cost of a different order from
one per child of every container, it passed its own A/B, and the fade-out of
an `if`'s view is the one people see most.
