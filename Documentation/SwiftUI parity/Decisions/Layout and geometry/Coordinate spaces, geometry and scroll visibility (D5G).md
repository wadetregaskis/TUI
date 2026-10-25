# Completing the SwiftUI API: decisions from lane D5G

*Lane D5G implemented the owner's decisions A2 (coordinate spaces,
`GeometryProxy.frame(in:)`, anchors, `scrollTransition`) and A7
(`onScrollVisibilityChange`), by the design study
[the A2 design study](<../../../Historical/Geometry design study, A2 and A7 (2026-10-04).md>)
and the owner's answers to its §9. This file holds the judgement calls the
work reached that those answers did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-D5G-n — needs your decision.** Nothing has shipped for these.
- **B-D5G-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-D5G-n — declined.** With the `parity-map.json` reason.

Measurements are SwiftUI on macOS 15 (probes in
`Tools/SwiftUIProbes/Coordinate spaces and scroll visibility (D5G)/`).

## B. Shipped the safe option

### B-D5G-1. Scroll visibility: a removed view is not reported; a row windowed out of a lazy stack is

*`View.onScrollVisibilityChange(threshold:_:)`*

Measured: every observed view reports once when it first appears, shown or
not, then at each crossing of its threshold (a fraction AT the threshold is
shown, so `threshold: 0` reports every view shown); a view in no scroll view
is reported shown wherever it is laid out; and a view removed from the tree
reports nothing. SwiftUI's lazy stacks destroy a row that scrolls out of their
window, and it reports nothing until it is made again.

What ships follows all of that except the last: a row a TUIkit lazy stack stops
drawing is still in the tree (its state is kept), and is reported hidden if it
was shown — option 1 of A7 ("fires `false` for a marker that has vanished").
A removed view is told nothing, as in SwiftUI; the two are told apart by
whether a windowing container still retains the identity
(`StateStorage.retainedSubtrees()`).

**Fuller version:** none wanted; the alternative would be to stay silent for a
windowed-out row as SwiftUI's destroyed one does, which leaves an app that
stopped a player on `false` playing it off screen. Nothing to price.

### B-D5G-2. A view whose marker reaches no owner is not located; a `Table` cell's now does

*`GeometryReader` asking any space but its own, `onScrollVisibilityChange`,
`onGeometryChange` with a non-local space, anchors — under a container that
drops its content's hit-test regions; inside a `TableColumn`'s cell view
until 2026-10-06*

**A `Table` cell (changed 2026-10-06, the tables lane's follow-up).** A
`Table` composes each row's cells as text, and carries a view cell's regions
up with the row (`_TableRowPayload`, B46) — its geometry markers among them
now, which it used to leave behind. So a view in a cell is found where its row
draws it: a reader there is answered exactly, and an `onGeometryChange`
reports that place, its first report included (`CoordinateSpaceTests`). A
cell still carries no geometry origin (`Table.cellContext`), so a reader's
own prediction there is the origin: the frame it first shows costs the root a
second walk of the scene, after which it reads what was found (one correction
on its first frame, none after, in the test's static table; a frame its row
moves on, unmeasured, would cost another). Before, nothing found the cell, and
a reader there was told the origin on every frame. A space declared inside a
cell starts an origin of its own and is answered exactly, as before. A
`ScrollView` inside a cell has no origin carried to it either, so it does not
predict for its own `.scrollView` readers: they are corrected — the scroll
view's subtree drawn a second time — on every frame they move. An open menu's
content in a cell (a layer, not a region) still leaves its markers behind: it
is found where the menu is drawn, not the cell.

**Elsewhere:** a marker reaches an owner only through the buffers its
ancestors draw, so a view is not located under any container that redraws its
content's lines into a new buffer without the hit-test regions in them, which
carry the markers (a bare `FrameBuffer(lines:)`, in an app's own `Renderable`
as in the framework; `ContainerPayloadAudit` guards the framework's
containers for regions). Such content carries an origin down as any content
does, so a reader there is told where the containers above it would place it,
and nothing checks it; a reporter is told the origin, and a pointer converts
in the global space (B-D5G-7). A window bar's content is located: the bars are
rows of the frame the scene root reads (A28), so a reader in a `.toolbar` item
is found and corrected as a reader on the page is (`GeometryWindowChromeTests`).

**Fuller version, for a cell:** carry each cell's origin down to it (the
row's line and the column's start), so a reader there predicts exactly and
the first frame needs no second walk. About half a day, on `Table`'s hot path,
so with the `table`/`tables-scroll` A/Bs.

### B-D5G-3. A reader inside a presented surface asking `.global` costs the scene a second walk on the frame the surface shows or moves

*`GeometryProxy.frame(in: .global)` (and any name nothing declared) inside a
sheet, popover, menu or alert*

A presentation's surface is placed by the compositor — centred, flipped above
its anchor, clamped on screen — which the window runs inside the scene's walk
(A28's chrome host composites the content's layers between its bars), so the
frame the scene root reads has every surface in place. A reader in one is
found with the page's readers and corrected the same way: the prediction does
not follow the compositor's placement, so the surface's first frame, or the
frame it moves, walks the scene again (`RenderLoop.renderContent`) — and draws
its readers from where they are (`GeometryWindowChromeTests`). Named spaces
declared inside the surface are exact in the same frame without it; a name
declared on the page does not reach into a presentation (nor does SwiftUI's).

(Before the window's chrome moved into the scene, the composite ran after the
root's correction, and such a reader was right only from the frame after.)

**Fuller version:** carry the compositor's placement down as an origin, so a
reader in a surface is predicted and the scene is not walked again; the
compositor's placement run before the surface's content draws. About a day.

### B-D5G-4. Side effects inside a corrected subtree run for the kept drawing alone

*every owner's correction: `coordinateSpace(_:)`, a scroll view, a list, an
anchor layer, the root*

**Fuller version shipped (lane EFFECTS, 2026-10-24; the owner's ruling (2)).**
A correction draws the owner's subtree once more in the same walk. The
registrations the first drawing made are put back first
(`RenderWalkCheckpoint`: mouse and marker ids, `onChange` indices, key
handlers, preferences, what a memo recording around the owner kept of them,
and the render cache below the owner), so the second drawing takes the same
ids and indices and nothing is registered twice. A scroll view that draws its
band again at the offset the frame settled on puts the same things back but
the cache. The registries that take a second registration of the same thing
as one — the focus ring, keyboard shortcuts, status-bar items, drop targets
— are not put back: a view only the first drawing drew (a row of a band the
scroll view replaced) stays registered for that frame.

What the first drawing would have DONE is now held back instead
(`EffectStage`, `ProvisionalEffects`). Every drawing that may be made again —
a checkpoint's, and the scene root's walk (`RenderLoop.renderContent`, and the
headless and test drivers that mirror it) — is opened on the app's effect
stage. While one is open a view does not act: it hands its action to the
stage and notes how to put back what it remembered in deciding to. A
discarded drawing drops its actions and runs its undos, last first, so the
drawing made in its place decides from what the frame began with; a kept one
joins the drawing around it, and the outermost — the scene's walk — runs its
actions once the walk is done, in SwiftUI's order (B-D5G-11). Held back, with
what is put back:

| Effect | Remembered state put back |
|---|---|
| `onChange` (views and scenes) | the compared value (`setChangedTrackedValue`) |
| `onPreferenceChange` | the reduction last heard |
| `onGeometryChange` | the last report (reported at the frame's end, with the walk's drawing still open, it joins the walk's effects) |
| `onModifierKeysChanged(initial: true)` | that the view has appeared |
| `onInteractiveResizeChange` | the last answer |
| `onAppear`, `.task`, and every task a view starts on appearing (`Image`/`AsyncImage` loads, a notification host's expiry, gradient graphics) | that the token appeared, and that it is present this pass |
| `onDisappear` | its callback, where the drawing registered it first |
| `onScrollGeometryChange`, `onScrollTargetVisibilityChange`, `onScrollPhaseChange` | the last value the scroll view told each |
| a bound `ScrollPosition` told the row shown | the row last reported |

So a reader's first frame inside a corrected subtree fires no `onChange`, as
SwiftUI fires none (`CoordinateSpaceTests.correctedSubtreeSideEffects`), a move
fires one, old answer to new, and a view only the discarded drawing drew —
a branch the guess chose — neither appears, starts a task, nor later
disappears (`CorrectedSubtreeEffectsTests`, including the root's walk and owners
nested in owners).

**How it was armed, until B-D5G-11.** Holding every effect back from the
start of every drawing was tried first, without walking the frame again: a
view drawn after an `onAppear` or `onChange` then no longer saw what the
action wrote in the same frame — a keyframe animator restarted one frame late
(`AnimatorViewTests.keyframesInterrupted`), and a page that loads in
`onAppear` would draw one frame empty. So a drawing held back only once
*armed*, by a reader inside it being told an answer that could be wrong, and
everything before that acted at once. B-D5G-11 walks the frame again for
what the effects wrote, which takes that frame off the screen, and every
drawing now holds back from its start; the arming (`GeometryAsk` finding the
owner's depth on the stage) is gone.

**Not held back, and why:**

- nothing an owner draws again is now left out: a scroll view's band redrawn
  at the offset the frame settled on, a glass container whose pieces joined
  otherwise than it last found, and a matched geometry effect drawn again at
  its matched frame's size discard their first drawing's effects too (the
  band's and glass's were not held while a drawing held back only once a
  reader armed it). A row
  only the discarded band drew may still stay registered for that frame.
- the framework's own memory written while drawing (a scroll view's offset, a
  `.task(id:)` generation, an animation's start, a keyframe animator's
  playback): the second drawing reads what the first wrote and comes to the
  same answer, so it is written once.
- `onRenderPass`, instrumentation that reports every pass a view takes part
  in: a discarded drawing is one.

**Price.** A drawing's opening and keeping is a depth count, and a view
tests one flag on the frames it acts; the one closure an action needs is
made only when it acts. Profiled before B-D5G-11 (release Stress, 8 s Time Profiler,
2026-10-24): `RenderWalkCheckpoint.init`, which now opens the drawing, is at
most 12 ms of 24 s in `kitchensink`; in `geometry`, whose scroll transitions
are readers told an answer every frame, arming is 1 ms of 7.9 s, once it
reuses the owner the prediction found (it was 0.7% while it walked the owner
chain a second time); nothing of the stage shows in `scrollfollow` or
`preferences`. A/B timings are owed.

### B-D5G-5. `CellRect` gains `minX`, `minY`, `origin` and `size` — and still no `midX`/`midY`

*`CellRect`, the cell form of `CGRect`*

`proxy.frame(in: .named("scroll")).minY` is how SwiftUI code tracks a scroll
offset, and it did not compile: `CellRect` had `x`, `y`, `maxX`, `maxY`. The
four added are `CGRect`'s names for values `CellRect` already has. The
midpoints stay out, for the reason recorded on `AlignmentID` (a midpoint
floored before it is subtracted from another moves one in four centrings by a
cell).

### B-D5G-6. `CoordinateSpace` and `NamedCoordinateSpace` are not `Sendable`, and `hasGlobalPosition` is gone

*`CoordinateSpace`, `NamedCoordinateSpace`, `GeometryProxy.hasGlobalPosition`*

`CoordinateSpace.named(AnyHashable)` holds any `Hashable`, and nothing says the
value inside is safe to share; SwiftUI's two types are not `Sendable` either
(their symbol graph lists `Equatable` and `Hashable`). TUIkit's
`CoordinateSpace` was `Sendable` while it had only `.local` and `.global`;
nothing in TUIkit relied on it.

`hasGlobalPosition` existed to say when `frame(in: .global)` had fallen back to
the local frame. `.global` is exact now, so the property answered nothing, and
pre-1.0 it is removed rather than kept true.

### B-D5G-7. A pointer location in a named space converts with the frame the event arrives over

*`DragGesture(coordinateSpace: .named(…))`, `SpatialTapGesture`,
`onTapGesture(count:coordinateSpace:perform:)`,
`onContinuousHover(coordinateSpace:perform:)`*

The view's place in the named space is found by the space's owner when the
frame is drawn, and an event between two frames is converted with it — the
frame the user was looking at. A view handling the pointer in a named space
stamps a marker each frame and so declines the memos above it (its conversion
is made per frame); in `.local` and `.global` nothing changes. A name nothing
declares converts in the global space, as SwiftUI's does — and so does a name
no owner found the view in (its marker dropped on the way up: a `Table` cell),
for a hover or mouse handler as for a gesture.

### B-D5G-8. Scroll transitions: the default threshold is taken as `.visible`, unmeasured

*`View.scrollTransition(_:axis:transition:)`,
`scrollTransition(topLeading:bottomTrailing:axis:transition:)`,
`ScrollTransitionConfiguration` (`.interactive`, `.animated`)*

What ships: a view's phase follows where it is in its scroll view's viewport
— the edge it is nearer (`.topLeading` above the middle, `.bottomTrailing`
below) until it is in as far as the configuration's threshold, then
`.identity`. `.interactive` interpolates the EFFECT between the edge phase's
and the identity phase's by how far in the view is (measured: SwiftUI calls
the closure for all three phases and does the same), paced by the curve;
`.animated` switches at the threshold and animates with its animation;
`.identity` never changes. Thresholds are depths into the viewport in cells
(`.visible(a)` is `a` of the view, `.centered` is the view's middle at the
viewport's, `inset(by:)` moves one towards the middle). The position is the
owner's answer 5: predicted, and corrected by the scroll view when wrong.

Not measured: the threshold SwiftUI uses when none is set. A pixel probe of
an offscreen `NSHostingView` (`Tools/SwiftUIProbes/Coordinate spaces and scroll visibility (D5G)/st2.swift`) did not
agree with itself — the band it found partly faded did not move with the
scroll offset it was given — so the default is taken as `.visible`, the point
the documentation of `threshold(_:)` calls "fully visible".

**Fuller version:** a probe that reads the effect without pixels — an effect
whose `animatableData` is observable — to settle the default; an hour, and a
one-line change if it differs.

**Done 2026-10-19 (lane SCROLL).** SwiftUI's configurations carry their
threshold as data, and a `dump` of them reads it: `.interactive` and
`.interactive(timingCurve:)` start at `.visible` (1.0), but `.animated` and
`.animated(_:)` start at `.visible(0.5)`, half the view, and `animation(_:)`
keeps it. Driven through the scroll view, each default behaves exactly as the
threshold it holds and unlike the other, at four offsets
(`Tools/SwiftUIProbes/Scroll transitions/`). So an animated transition now
switches with half the view in, which only a view taller than one line can
show; the interactive default was right.

### B-D5G-9. A `List`'s rows are not placed by the prediction, and a `List` does not own `.scrollView`

*`GeometryReader` (or `scrollTransition`) in a `List` row asking `.scrollView`,
a named space, or `.global`*

The prediction rungs convert the stacks, grids, layouts and the scroll view
(design study A2, rungs 1 and 2). A `List` renders its rows on demand into a
window under its chrome, and its rows are told the list's own origin: what
the window and the chrome add is carried by each reader's residual, so a
static list costs a correction on a reader's first frame, and scrolling a
list with readers in its rows costs its owner one more drawing per frame —
G1's rate, never a wrong answer. `.scrollView` inside a `List` row is
answered by the nearest `ScrollView` around the list (or the global space),
where SwiftUI's list is itself the scroll view. A `Table`'s cells are
located, from their first frame's correction on (B-D5G-2).

**Fuller version:** the list places each drawn row at `contentTop + (line −
drawn offset)` in its window, as `attachRowPayloads` already does for the
rows' regions, and owns `.scrollView` for its rows as the scroll view does —
a day, on the list's hot path, so with the `table`, `tables-scroll` and
`session/inbox` A/Bs.

**The ownership half: built (2026-10-19, lane LISTS2).** A `List` draws its
frame as the owner of `.scrollView` and `.scrollView(axis: .vertical)`
(`RenderContext.drawingAsVerticalScroller`), as a `coordinateSpace(_:)`
declaration owns its name: a reader in a row is answered in the list's
content window, inside the border and below a borderless title, and where one
drew from an answer that turned out wrong the walk is put back and the frame
drawn once more. A list with nothing asking pays the walk's checkpoint and a
test of the waiting count, every frame — A/B owed on `table`,
`tables-scroll` and `session/inbox`. **The placement half is not built:** the
rows are still told the list's origin, so a scrolled list with a reader in
its rows draws once more a frame (G1's rate); placing each row before it is
drawn needs its line in the window before the window walk has settled it,
which the walk renders rows to find — about a day more, with the same A/Bs.

### B-D5G-10. The prediction's third rung converts seven composers; the root's centring and five more containers are left to the residual

*Where a reader inside them is told it is before it draws (the correction
rate only — never the answer)*

Converted (design study A2 §10 step 7, the owner's answer 6): `.padding`, a
bordered or titled box (`.border()`, `ContainerView` and what is built on
it), `.frame`'s alignment, `.overlay`/`.background` and the preference
layers, `ZStack`, `.offset` and `.position` — each places its content before
drawing it, measuring the content where it aligns by size (memo hits: the
same measures its own `sizeThatFits` took). The ones that align by size also
move a `.gradientExtent(.subtree)` ramp, which they did not before; `.offset`
and `.position` move only the geometry origin, keeping the colour where the
layout put the view (the extent is TUIkit's own, so SwiftUI has no answer
to measure; this keeps today's colours under an offset).

Left to the residual: the scene root's centring of content smaller than the
screen, `safeAreaInset`, content margins, `TabView`, `NavigationSplitView`
and `SplitView`, a `List`'s rows (B-D5G-9). Each adds an offset that is the
same frame after frame for a given layout, so a reader under it costs one
correction on its first frame and none after, until that container's own
layout changes.

**Fuller version:** the root, by measuring the scene before drawing it on
frames with readers — a measure of the whole tree per frame, which on the
deep and fanout shapes is a cost a reader somewhere should not impose on
everything; the other five as the List is priced (a day, with their own
A/Bs), when the Stress counter shows a shape paying for them.

### B-D5G-11. Effects run after the walk, in SwiftUI's order, and a frame they changed is walked again before it is written

*every `onAppear`, `onChange`, `onPreferenceChange`, `onGeometryChange`,
`.task` start, scroll observer and bound `ScrollPosition`; the architecture
study's option (a), approved by the owner on 2026-10-24*

**Built (2026-10-24).** The architecture study ([SwiftUI's update model beside
TUIkit's](<../../../Investigations/SwiftUI's update model beside TUIkit's (2026-10-24).md>),
§5 option (a)) found that the frames TUIkit showed and SwiftUI does not — a
page that loads in `onAppear` drawn empty for a frame, or torn (the views
before the loader old, the ones after new), a value an `onChange` derives a
frame behind its source, the flow-layout idiom laid out once from empty
sizes — all came from writing the first walk, and that SwiftUI avoids them by
updating again before it draws ([the probe](<../../../Investigations/SwiftUI's update and effect ordering, measured (2026-10-24).md>)).
So, as SwiftUI does:

1. **Every effect waits for the walk.** The scene root's drawing is opened
   on the effect stage (`FrameSettling`, in `RenderLoop`, the Stress
   bench's headless frame and the test harness alike), so every view in the
   walk hands its effects over (B-D5G-4's mechanism), and they run once the
   walk — and the root's geometry correction, and the geometry reports made
   at the frame's end — is done. A corrected drawing's effects are dropped and
   their memories put back, as before.
2. **In SwiftUI's order where it was measured** (`EffectStage.Kind`):
   geometry (`onGeometryChange`, and a scroll view's reports of what it
   shows), then `onPreferenceChange`, then `onAppear` and the start of a
   task, then `onChange` and the other value observers. The probe measured
   geometry → preference → `onAppear` on one view, and a parent's `onAppear`
   before its child's; within a kind the walk's order stands, which gives the
   parent first. **Not measured:** where `onChange` falls among the others in
   one round (it is last here), and the order among siblings (the walk's, top
   to bottom). `onScrollVisibilityChange` is reported as the frame's geometry
   is settled, before the held effects. `onDisappear` still runs after the
   frame is written, and a task's operation still runs once the main actor is
   free, after it: both as before, and `.task`'s as measured.
3. **A frame the effects changed is walked again before it is written, at
   most twice.** If an effect wrote state — anything that reaches the render
   cache's invalidation queue: a `@State`, an `@Observable` a body read — the
   walk is out of date, so the frame is walked again against what it wrote
   (what it invalidated dropped, the pass's measure memos emptied), its
   effects run, and so on, up to two walks more, as SwiftUI updates twice
   inside its layout pass. Then the frame is written. A longer chain is
   written as it stands and carries on one walk a frame, as every chain did
   before, so a chain that does not end never holds the main thread
   (SwiftUI runs a chain of different actions to its end inside one turn of
   the run loop — 100 steps, measured). A write made *during* a walk (a body
   that writes) does not walk again: it asks for the next frame, as before.
   The frame request the effects' writes made is let go before the walk made
   again, since that walk is the frame they asked for.
4. **What carries over between the walks of one frame.** Lifecycle: a
   view's appearance stays (its `onAppear` ran), its presence is the last
   walk's, so a view only an earlier walk drew disappears with the frame and
   its `onDisappear` runs. Animation: the stores take a walk made again as a
   pass of their own, so a value the walk before drew and an effect changed
   under `withAnimation` animates from there — `onAppear { withAnimation {
   shown = true } }` slides or fades in, as in SwiftUI. The completions of
   changes the effects made join the frame's. The bars' rows are the frame's:
   every walk is laid out against the rows the first was (toolbars are still
   adopted a frame late, W1).

5. **Per-action cut-offs, as measured.** An `onChange` or `onPreferenceChange`
   action runs at most twice in one written frame; a third run is refused
   and its change dropped, not deferred — the value is already tracked as
   seen, so the next frame does not fire it either; a later change runs it
   again — with SwiftUI's words, once (`SoftTrap.warn`, which reports as a
   soft trap does but never stops a debug build): "onChange(of: Int) action
   tried to update multiple times per frame." and "Bound preference IntKey
   tried to update multiple times per frame." Counted per action as it runs,
   so a discarded drawing's count nothing. SwiftUI's limit reads as twice per
   *draw*; TUIkit's draw is the written frame, whose walks a chain may end
   partway through, so a self-feeding action can run twice in each of two
   frames before a third run in one is refused — four runs where SwiftUI
   made three (`EffectSettlingTests.selfTriggeringOnChangeIsCutOff`). An
   `onGeometryChange` has no count but SwiftUI's duplicate-cycle rule: a
   report going back, within one frame, to the value before last (`A → B →
   A`) is refused and taken as seen, with "Geometry action is cycling between
   duplicate values." A value a view takes again on a later frame is
   reported as usual.

**What changes for an app.** The first frame written shows what an `onAppear`
loaded, everywhere it is shown; an `onChange`'s derived value is drawn in the
frame that shows its source; a size a preference or `onGeometryChange` feeds
into the layout is in the first frame. A view drawn after an effect no longer
sees what it wrote *in the same walk*: it sees it in the walk made again,
before anything is shown. A phase animator with no trigger takes its first
step as it appears, so its first frame shows the second phase's content, its
animated values starting from the first phase (`AnimatorViewTests.cycles`);
whether SwiftUI's first frame shows the first phase's content was not
measured.

**How often a frame is walked again** (counted 2026-10-24, debug build; the
Stress bench prints `effects:`, each session report too, and
`TUIKIT_DIAGNOSE_BODY_MUTATION=1` writes a line for each frame whose effects
wrote):

- Every Stress `--bench` scenario (37, 60 frames each after the warm-up):
  none.
- Stress sessions (401 frames each, the opening frame included): `log`,
  `log-observable` and `log-captures` 146 (88 once, 58 twice) — the bound
  `scrollPosition(id:)` reporting the top line as lines arrive, which the
  status line above the scroll view shows; `editor` 36 once — its
  `onChange(of: document.line) { proxy.scrollTo(line) }`; the other 19 none.
  No frame was left still writing.
- The Example, every page opened with ⌃T in a headless app (140 × 42, ten
  frames a page, then Down ×3, Up and Tab ×2 with two frames each): 8 of 841
  frames, each once, each a page's first frame (`layout`, `tables`,
  `scrollView`, `imageFile`, `imageURL`, `lifecycle`, `preferences`,
  `animation`); none on a key.

**Price.** A frame whose effects write nothing is walked once, and pays one
count compare of the invalidation queue and, for every view, the hand-over of
the effects it makes (a closure each, made only when it acts, and a token per
lifecycle view first seen in the pass). A frame whose effects write pays a
walk more, which the render cache serves except for what the write
invalidated.

Profiled (release Stress, 8 s Time Profiler, `analyze_timeprofile.py
--process Stress`, 2026-10-24; under the profiler, so not an A/B):

- `--scenario kitchensink`, which walks nothing again: of 2,305 ms,
  `RenderWalkCheckpoint.init` 5 ms (0.2%), `EffectStage.open` and `close`
  1 ms each; `FrameSettling.settle` is the walk (89.0%) and adds nothing
  that shows.
- `--scenario session/log`, the shape that walks again most (1,211 of 4,001
  frames, 327 of them twice: 1.38 walks a frame): the walks are 82.4% of the
  frame inclusive (`RenderLoop.walkScene`), against 76.7% at `main`
  (`renderContent`); the bench's own per-frame figure while profiled was
  3,364 µs against 2,817 µs at `main` (+19%). A walk made again costs about
  what the first did (≈2.0 ms), because the write it is made for — the
  top line, in an `@Observable` the page's body reads — clears the page
  above the scroll view, so the memo serves little of it (the class Option
  C addresses). The settling itself is small: `RenderCache.beginRewalk`
  13 ms (0.5%), `EffectStage.close` 2 ms. That frame used to be written showing the old
  top line in the status bar; it is now written once, settled.

Tests (`EffectSettlingTests`, all reading the frame written): the first frame
of a page that loads in `onAppear` shows the rows and the count above and
below them; a derived value is drawn beside its source on both sides of the
`onChange`; the flow-layout idiom's first frame is laid out from its sizes;
a sibling before an `onGeometryChange` draws the width it reports; a chain
of four is walked again twice and finishes in the next frame; an `onAppear`
`withAnimation` slides from the first walk's place; a frame whose effects
write nothing is walked once; a self-triggering `onChange` and a self-feeding
preference stop, and a geometry action that flips its own view's width
settles in the first frame, each with SwiftUI's warning.
`AnimatorViewTests.keyframesInterrupted` — a
keyframe animator restarting a frame late when effects were first held
without a walk made again — passes.
