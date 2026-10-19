# Transition follow-ups: decisions from lane TRANSITIONS2

*Lane TRANSITIONS2, 2026-10-19, built on lane FB16's insertion and removal
model (owner ruling FB16 (a′), 2026-10-18): the default transition for what is
not an `if` (owner ruling 2026-10-14, "prototype B (fade both ways) + A/B,
fall back to C (fade-in only) if significant cost esp. with no animation"),
each half of an `asymmetric` transition's own animation, `.animation(nil)`,
and the one-access presence record of an `if`. Where the work met a judgement
call the rulings did not settle, the safe option shipped and is written up
here in the main decisions file's format:*

- **A-TRANSITIONS2-n — needs your decision.**
- **B-TRANSITIONS2-n — shipped the safe option.** Says what the fuller
  version would be, and its price.
- **C-TRANSITIONS2-n — declined.** With a parity-map entry.

*SwiftUI's behaviour is the one measured on this Mac (macOS 15.8, Xcode 26's
SDK, 2026-10-19) by two offscreen `NSHostingView` probes,
[`Tools/SwiftUIProbes/Transitions/`](<../../../Tools/SwiftUIProbes/Transitions/>)
(`tr1.swift`, `tr2.swift`, each with what it printed), which read the
presentation frames and opacities of the layer tree every half second under a
linear animation.*

## A. Needs your decision

### A-TRANSITIONS2-1. B52: a custom transition that changes its view's size — lay the body out at each frame's size?

*`Transition` with a body of the app's own, B52; owner rulings 2026-10-04
("measure the per-frame re-layout cost first") and 2026-10-18 (FB16 (a′))*

**What SwiftUI does** (`tr1.out` T7, T7b, a `Transition` whose body sets
`.frame(height: phase.isIdentity ? nil : 0)` on a 60-point view between two
10-point ones, under an 8 s change): the view's frame grows and shrinks, and
the view below moves with it in step — 70 → 63 → 55 → … → 10 as it folds
away, 10 → 17 → 25 → … → 70 as it opens.

**What TUIkit does now.** The body is drawn by scrubbing between its phases
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

## B. Shipped the safe option

### B-TRANSITIONS2-1. A branch, a case and a row fade where a container remembers its children

*`ChildFade`, `PlacementStore.Record.pictures`, `View.transition(_:)`*

SwiftUI fades a view in and out with no `.transition` written — an `if`/`else`
whose branch flips, a `switch`'s case, a `ForEach`'s row alike (`tr1.out`
T1–T3): the view leaving fades where it was, drawn beneath its siblings, the
new one where it lands, while the views below glide. An `if` already did
(2026-10-14), by a record of its own, since it renders both ways. A branch, a
case and a row cannot report themselves: the branch not taken is not
rendered, and a row that has gone has no element left to render.

**What shipped:** the container that places them does it. An eager `VStack`,
`HStack` or `ZStack` and a `Layout` already remember where each child was
(lane FB16's `PlacementStore`); they now also keep what each child drew on
the frame before (`Record.pictures`, the array they already hold, stored once
a frame). On a change under an animation, a child they are handed for the
first time fades in where it lands, and one they no longer are fades out
where it was, beneath the others, from its last picture. A child's presence
is an animated value under the container, as its glide is, so one that comes
back while it leaves turns round from where it is, a `withAnimation`
completion waits for it, and reduce motion — which holds motion still, A-D3M-1
— lets it play: a fade is not motion.

The same memory plays a transition of the view's own: a branch or a row
carrying one plays its removal where it was, from what it left in the
`DepartureStore`, where nothing could before (the branch an `if`/`else` left
was replaced at once). A view the container held behind something that draws
round its transition (`X.transition(t).padding()`) fades its whole picture
instead, padding and all; so does such a view in an `if`, whose record now
keeps the picture for that (it snapped).

A conditional drawn whole — a view's whole `body`, a modifier's content,
not taken apart by a stack — keeps its branch's picture in the record of the
branch it took, which it already wrote every frame (`ConditionalRecord`,
`BranchTransition`), and fades the two the same way (B-TRANSITIONS2-2).

**What it costs, and the A/B owed.** A settled eager container stores one
array a frame; an empty one now looks its record up, so that its last rows
can fade. A conditional drawn whole stores its picture in the access it
already made, which is now one in-place access where it was a lookup and a
store. A change under an animation works out the identities of what came and
went. The owner's criterion was "C (fade-in only) if significant cost esp.
with no animation": C would save only the stored array, since fading in needs
the record already kept. The A/B on `deep`, `fanout`, `dashboard`,
`kitchensink`, `menus` and `churn`, cold and warm, is owed.

**The fuller version:** the same in the containers that keep no memory of
their children yet — a lazy stack, a `Grid`, a `List`'s and a `Table`'s
rows, where a branch, a case and a row still change at once (deviations,
Slated). Each needs the placement memory first, priced with it in decisions
FB16 (B-FB16-2, B-FB16-3, B-FB16-5): about two days for the lazy stacks, half
a day for `Grid`, and the list's row work for `List` and `Table`.

### B-TRANSITIONS2-2. A conditional drawn whole draws the branch it leaves over the one it takes

*`BranchTransition`, deviations A6*

SwiftUI draws a view's two branches overlapping at its origin while they
cross-fade, the one leaving beneath (`tr1.out` T8). A conditional drawn whole
has no canvas of its own to draw beneath on: its layout is the new branch's,
at once, and only a container composites a fade against what is beneath it
(`FrameBuffer.layered`, in `TUIkitFoundation`; the conditional is in
`TUIkitView`, below it). So the branch leaving is drawn past the conditional's
frame, as content drawn past a view's region is (`FrameBuffer.drawnPastSlot`),
which lands it over the new branch. For two fades crossing, over and beneath
are the same blend with the weights swapped: half-way, each is half there.
What it covers past the new branch's frame is covered over, not under, as an
overflow is. It takes no clicks.

**The fuller version:** move the layering compositor (`FrameBuffer.layered`
and the claims it resolves, `FrameBuffer+ClaimsOverNothing.swift`, with the
wake its runs ask for) down into `TUIkitView`, so a conditional can draw the
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
