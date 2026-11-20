# Framework controls beside a live timeline

*A design and its first half, written 2026-11-19 against `main` at 2876f4f51, in answer to tuiarcade's
`TUI-FEEDBACK.md`, M2 item 3: while any `TimelineView` runs in the window, a `List` row's or a `Button`
label's content is "drawn again at every frame". Commit d4808499d fixed the app's own views beside and
above a timeline (`FrameBodyKeep`) and left this, with the diagnosis that framework controls have no memo
of their own and that a focused `List` registers focus in a way the memo cannot replay. Ids:
B-TLCTRL-1 (decided and built here), A-TLCTRL-1 (the owner ruled F0, 2026-11-19); B-TLCTRL-2 to B-TLCTRL-6, added below.*

## In short

What runs again at each entry is not the row's or the label's content, which is served from its own memo,
but the control around it: the `List` lists, measures and lays out its rows, gathers its selection,
registers its focus and draws its chrome; the `Button` resolves its style, registers its focus and
draws its label's frame. Each is drawn because the walk reaches it at every entry (no buffer above a live
timeline can be stored) and nothing at the control's own identity keeps its picture: the plain memo
leaves the framework's composites out, and `FrameBodyKeep` does too.

Two cases, two answers:

- **A control that does not hold the focus** (built, B-TLCTRL-1). `List` and `Button` are memoized at
  their own identity as an app's view is, while a timeline is live and only then
  (`_PlainMemoizedBesideTimelines`). It is the memo the app's view above the control already stores the
  same subtree in, so it is no less safe; outside a live timeline nothing changes.
- **A control that holds the focus** (not built; the owner ruled F0, A-TLCTRL-1). Its registration still declines every memo
  around it, so a focused `List` beside a timeline is still drawn at each entry. Making it replayable
  changes what a served frame may skip for a focused control, with an audit behind it, priced below.

Measured (B-TLCTRL-1, against the same tree with `TUI_KEEP_TIMELINE_ANCESTORS=0`, which turns it off):

| Over one second of a 60 Hz timeline beside the controls (`TimelineBesideControlsTests`) | Before | After |
|---|---|---|
| Row boxes an unfocused `List` of two rows made | 122 | 0 |
| Bodies each unfocused `Button`'s style made | 122 | 0 |

`Stress --check-counts`, `timeline-beside` (a launcher at rest: a 60 Hz timeline behind a board, a `List` of
six previews and a `Button` with a canvas label beside it), 60 frames: `listed` 360 → 0, `served` 650 → 346
(the list's rows are no longer asked for one by one), `bodies` 1232 → 1044, `misses` 3080 → 2864; `built`
25 → 30 and, as the page opens, 60 → 64: the controls' own memos missing on their first frames, and one
that cannot store trying again as its cooldown ends (`PlainMemo.isCoolingDown`). A/B (`Tools/Profiling/ab_bench.py`, release, CPU per frame, 10 paired
reps): `app-shapes/timeline-beside` 1156.2 → 915.0 µs, −20.4% (95% CI −21.5% to −18.6%);
`session/case:timeline-beside` 1532.4 → 1376.8 µs, −9.8% (−11.1% to −7.1%); `app-shapes/game-loop` and
`app-shapes/timeline-rows`, which hold no `List` or `Button` beside their timelines, indistinguishable.
The default sweep (36 scenarios, none with a live timeline beside a control): 35 indistinguishable,
`gradients` −2.8% faster; the widest, `customlayout` +10.3% on 7.4 µs a frame, has its interval reaching
0.0% and runs no timeline, where the change costs one `Bool` test a composite type.

## What re-runs at each entry

Time Profiler, `Stress --bench --scenario app-shapes --variant timeline-beside` (release, `-g`), 8 s
attached, ranked by `Tools/Profiling/analyze_timeprofile.py`, inclusive:

| Frame | Before | After |
|---|---|---|
| `_ListCore.renderToBuffer` (of which `renderFrame` 9.1%, `buildPopulatedContent` 4.9%, `composeRowLines` 1.6%) | 9.8% | not in the top 400 |
| `_ButtonCore.sizeThatFits` (the style's measure, which draws a `@ViewBuilder` label to size it) | 6.4% | not in the top 400 |
| `_ButtonCore.renderToBuffer` | 4.9% | not in the top 400 |
| `_ButtonStyleBody.drawStandardRow` (in both of the above) | 9.5% | not in the top 400 |
| `BackgroundLayerModifier.renderToBuffer` | 67.3% | 85.8% |

So the `List` and the `Button` cost about a fifth of each frame of that page, every bit of it their own
work around content that was served: the list lists, measures and lays out its rows and composes their
lines; the button's style measures its label by drawing it and then draws it again. The rest of the frame
is the board's `.background { TimelineView }` composite, 58% (`FrameBuffer.prepared`) before and 74%
after, a cost of the layer modifier above the timeline and not of any control: a separate fix, not this
one (B-TLCTRL-2, below).

## Why the framework's composites had no memo

`FrameworkModules` keeps the framework's composites out of the plain memo: their bodies only forward,
and "the memo at the app's view above decides for the whole". Above a live timeline that memo cannot
decide anything, since the timeline's wake declines its store, and the walk reaches every control on the
page at every entry. The canvas beside a timeline was the first framework view let back in
(`_PlainMemoizedFrameworkView`, unconditionally, because its renderer is the app's work); the controls are
the second, conditionally, because outside a live timeline the app's memo above serves them and their own
would only cost a key.

Why a control's own memo is as safe as the app's memo above it: the app's memo stores the same subtree,
control included, whenever nothing beside the control declines, keyed by fewer things (the app view's
fields, its environment). At the control's identity the key is the control's own value (its closures
passed over, as an app view's are, in a frame in which nothing above wrote, and compared strictly below a
parent's write) and the environment it is drawn under by stamp. Everything else a control draws from is
already an invalidation the app's memo relies on: its `@State` (a hover box, a pressed flag), its
handler's drawn state moved by input that does not focus it (`HandlerDrawing`), a focus move at either end
(`FocusManager.focusedID`'s `didSet`), a `Binding` or style body read in its core (observed under the
kept render, `observingKeptResult`), a per-frame registration (journalled and replayed, or declining).

## The focused control

A focused control declines (`FocusRegistration.declareRegistration`, "a control that holds the focus"),
and everything containing it with it. The focus move itself would not make a stored picture stale: both
ends are dropped. What would is everything a focused control does that an unfocused one does not, and
that has never been journalled because a focused control was never served:

- its handler's state, moved by the keys and the pointer it receives while focused (a `List`'s cursor
  row, its anchor, its type-select prefix, its scroll position from the keyboard), with no invalidation:
  `HandlerDrawing` covers only the inputs that reach a control without focusing it, and says so;
- the per-frame claims only the focused control makes, emptied each frame: the status bar's Return label
  (`publishActivationLabel`, `StatusBarState.activationLabelOverride`), the keyboard tooltip candidate
  (`publishHelpText`), a scroll view's `.overContent` indicators placed beside rows while focused, and,
  in other controls, the terminal cursor a text field places;
- its timers (a button's auto-repeat, a list's type-select timeout).

The options, cheapest first:

| | What | Cost | Risk |
|---|---|---|---|
| F0 | Leave it: a focused control beside a live timeline draws at each entry. Document it (here, `RenderCycle.md`), and tell an app that keeps a 60 Hz timeline beside a focused list to give the timeline the slowest schedule it can (`.animation(minimumInterval:)`, `.periodic`). | None | The launcher's shape, a focused `List` of previews beside its loop, keeps most of its cost (the measured split is above). |
| F1 | A focused control's registration replayable at **its own** memo only, and only while a timeline is live: the registration names the control it was made at, the memo at that identity leaves it out of its store gate and journals it, every other memo still declines. Every input event the run loop dispatches drops the focused control's buffers (the focus manager knows where it last drew: `focusIdentities`), so nothing the keys or the pointer move in its handler is served stale; the focused-only claims above become journal entries (`publishActivationLabel`, `publishHelpText`); opt-in per control, `List` and `Button` first. | About 1.5 to 2 lane-days: the gate, the per-event drop, two journal kinds, a storm test per control asserting on the registries (the status bar's Return label, the tooltip candidate, the ring's order, the cursor) after served frames, since the memo verifier compares pictures and is blind to a missing claim. | Medium. It changes what a served frame may skip for a focused control, the recurring bug class (a per-frame write nobody journalled). Bounded by the opt-in, by the timeline gate, and by the store being at the control alone. |
| F2 | F1 for every focusable control and every memo. | Several lane-days: an audit of every control's focused path (text fields place the terminal cursor, pickers open, steppers repeat). | High, and the reach is every app, timeline or not. |
| F3 | Make a focused `List`'s own draw cheaper whatever the memo does: keep its extracted rows and its layout across frames, keyed by its content's value, its environment and a generation its handler bumps on every change. | About 2 lane-days. | Medium: the same audit as F1, of `ItemListHandler`'s state, and the gain is the `List`'s alone. |

## Recommendation

B-TLCTRL-1 as built, and F0 now, with F1 put to the owner (A-TLCTRL-1). F1 is the change that would serve a
focused `List` beside a timeline, which is the launcher's case and the one the feedback measured; it is
contained, but it widens what a served frame skips for a focused control, the class of change this
repository has paid for before (`memo-verifier-blind-to-side-effects`: two live stale-frame bugs under a
clean verifier run), so it should be the owner's call, with the storm tests written first.

## The composite of a layer modifier around a timeline (B-TLCTRL-2)

*Added 2026-11-19, against aa3becdd6 (the above built).* With the controls served, three quarters of each frame of
`timeline-beside` was the board's `.background { TimelineView(.animation) { … Color.clear … } }`, and none of it the
timeline's own work. Time Profiler, `Stress --bench --scenario app-shapes --variant timeline-beside` (release, `-g`),
8 s attached, `analyze_timeprofile.py --thread main`, inclusive:

| Frame | Before | After |
|---|---|---|
| `BackgroundLayerModifier.renderToBuffer` | 86.5% | 11.9% |
| `compositeLayer(_:under:…)` | 86.3% | 10.8% |
| `FrameBuffer.prepared(_:at:in:)` (of which `resolvingOpacity`'s `rebuildCovered` 52.0%, `settlingClaims` 36.3%) | 75.0% | not in the top 400 |
| `placeLayer` (the layer drawn: the timeline and its content) | 1.2% | 9.4% |
| `_TimelineViewCore.renderToBuffer` (both of the page's timelines) | 1.5% | 10.8% |

(The second column is a share of a much cheaper frame, so the same work is a larger part of it.)

**What re-ran at each entry.** Not the board, which is an `.equatable()` canvas served from its memo, and not its
measure: the layer modifier's base renders at the modifier's identity, which the entry's clear does not reach
(d4808499d). What ran was the composite of the two layers. The walk reaches the `BackgroundLayerModifier` at every
entry, since no memo above a live timeline can store, and it is a framework modifier with no memo of its own; so it
drew its layer (the timeline, whose content is a `Color.clear`) and composited the base over it, again. A
`Color.clear` is a field claim at alpha 0 over every cell (the claim is what routes the cells through the blend, so a
clear fill leaves what is behind it: see `ColorAsView.swift`), and under the base that claim is settled cell by cell:
the board's 300 cells, each of a named colour, split into cells, resolved against the claim, and rebuilt into lines,
for the picture the entry before made. A timeline that draws something under the base would pay the same.

**What changed.** A layer composite is a function of what it composites: the two buffers, the layer's offset, which
way it goes, and the environment's say about spending claims (the palette, linear light, the image store). The
process-wide inputs it reads besides (the colour depth, the terminal's reported colours, the graphics protocols)
clear the render cache when they move. So, while a timeline is live, `compositeDrawnLayer` (the half of `.overlay`,
`.background`, a shadow and a glass composite that follows the layer's placement) keeps each composite with all of
its inputs (`LayerCompositeKeep`, owned by the plain memo beside `FrameBodyKeep`) and serves it when every input
compares equal: the buffers as `FrameBuffer`'s `==` compares them, and the layout hints a composite takes a path by
besides. A served base buffer is the stored one, so its compare is an identity check; the redrawn layer is compared
line by line. No invalidation has to find a kept composite, and none could make it stale: anything that moved either
layer (a write, a hover, a focus move, an entry whose content draws differently) moved an input.

**What a serve skips, and why that is safe.** The composite has two side effects, and a composite that made either is
not kept: a wake asked for a run of one layer that shows through the other (asked again whenever the composite is
made), and a registration in the image store (a frosting claim's backdrop, or a faded copy of a picture under a
claim, when there is a store). Every registration the two layers make (focus, hit regions' handlers, the status
bar's claims, a tooltip candidate) is made, or replayed, by the layers' own walks, which still run: the keep sits
after both are drawn. So nothing a focused or interactive view does is skipped: a control in either layer is drawn,
or served by its own memo, exactly as before, and only the cell arithmetic of putting the two pictures together is
not done again. `TUI_VERIFY_RENDER_MEMO` makes a composite that would be served again and compares the two.

**Where it applies.** Only while a timeline asked for a wake this pass or the last (`FrameBodyKeep.timelinesLive`),
and only on a draw: a page with no live timeline composites as it did, beyond a load and a branch, and
`TUI_KEEP_TIMELINE_ANCESTORS=0` turns it off with the rest. Off a timeline the same keep would serve a layer modifier
the walk reaches for a sibling's change; it is left off there, where nothing measured asks for it.

**The timeline as the base.** A timeline used as the base of a layer modifier was said to clear the views in its
background at each entry. It does not, in this tree: the timeline's core draws at its body's identity, a child of
the modifier's, and its entry clears that and what is below it, of which the layer, at the modifier's other child,
is not part. `TimelineLayerCompositeTests` pins it (a board in the background of a timeline renders once over a
second of entries, and is composited once).

**What an entry still costs.** The timelines' own content, and the layout and drawing of the composites and stacks
between the root and the timeline: their bodies are kept (`FrameBodyKeep`) but no buffer above a live timeline can
be stored, so each is measured and laid out and its children's pictures stacked again (the `_HStackCore` and
`_VStackCore` draws and measures are most of the frame now). That is the next cost, and a structural one: a stack
above a timeline would have to keep its layout and splice the timeline's region into its last picture.

Measured (`Tools/Profiling/ab_bench.py`, release, CPU per frame, 10 paired reps, against aa3becdd6):
`app-shapes/timeline-beside` 940.0 → 109.3 µs, −88.3% (95% CI −88.6% to −88.1%); `app-shapes/game-loop`, a board with
its loop in its `.background` too, 668.2 → 87.9 µs, −86.7% (−86.8% to −86.6%); `session/case:timeline-beside` 1414.8 →
553.8 µs, −61.3% (−63.5% to −59.3%); `app-shapes/timeline-rows`, whose timelines are in rows and not in a layer
modifier, indistinguishable (+0.9%, −0.5% to +1.7%). The default sweep (36 scenarios, none with a live timeline):
33 indistinguishable, `texteffects` −0.8% faster, `scrollfollow` +1.0% (+0.3% to +2.2%) and `table-churn-wrapped`
+0.2% (+0.0% to +1.0%) slower on a busy box (load 3), where the change is a load and a branch per layer composite.
`Stress --check-counts`: no count moved, since the keep touches none of the counters the cases read; bytes
unchanged (92 of 92 sessions' `TUI_HEADLESS_STREAM` identical).

## What the ancestors of a live timeline cost at each entry (B-TLCTRL-3)

*Added 2026-11-19, against 77894861f (the above built).* What was left: no buffer above a live timeline can be stored,
so at each entry every view between the root and the timeline is walked, measured and laid out again, even though
only the timeline's subtree changed and its siblings are served from their own memos. Measured on the shape that asked
(tuiarcade's launcher, Stress's new `timeline-tiles`: two focusable bordered tiles in a row, each a `Canvas` preview in
a `.frame(width: 34, height: 8)`, the preview a `ZStack` of the picture and its own
`TimelineView(.animation(minimumInterval:))`), the frame was not mostly drawing. Time Profiler,
`Stress --bench --scenario session/case:timeline-tiles` (release, `-g`), 8 s attached,
`analyze_timeprofile.py --thread main`, inclusive:

| Frame | Before | After |
|---|---|---|
| `ChildView.measure` (every measure a stack asks of a child) | 35.9% | 6.0% |
| `_HStackCore.resolvedLayout` (the row of tiles measuring its tiles) | 30.5% | 3.0% |
| `FocusableModifier.sizeThatFits` (a tile's measure, below its focus modifiers) | 25.4% | 1.4% |
| `_BorderRings.sizeThatFits` | 18.1% | 1.0% |
| `FlexibleFrameView.measureAnalytically` (the preview's frame measuring the preview) | 15.4% | not in the top 400 |
| `_CanvasCore.renderToBuffer` (the preview whose demo moved, drawn) | 7.4% | 8.8% |

**What re-ran.** A measure of a live timeline declares the clock it reads (`recordClockedRead(movingAt:)`): its size is
its current entry's, and the clock moves the entry. Every measure memo containing it then declines, so each tile, the
row above it and the column above that measured their whole subtrees again at each entry, through the focus
modifiers, the border's rings, the container, the column, down to the preview's frame and through it to the timeline,
whose measure was the cause. But the preview's frame is pinned on both axes, and a frame pinned on both axes is its
pins whatever it holds: `measureAnalytically`'s arithmetic for two pinned axes (`FlexibleFrameAxis.extent`,
`extentOfferedNothing`, `isFlexible`) reads nothing the content reports. Nothing above the frame could have moved.

**What changed.** A frame pinned on both axes (`.frame(width:height:)`, or `minWidth`, `idealWidth` and `maxWidth` one
number, and the same of the heights) answers its measure from its pins, held to what it is offered, without measuring
its content (`FlexibleFrameView.pinnedSize`). Its render still draws the content, and measures it there as the content
needs. Under a `scrollTo` search's measure (`ScrollKeyLocate`), which measures to find a view, it still measures the
content. A pure function of the frame's own fields and the offer, so nothing to invalidate and nothing to go stale; no
registration moves, since a measure registers nothing. With the timeline's clocked read sealed below the frame, the
measures above it are kept by the memos that keep any other measure.

**Where it applies.** Every frame pinned on both axes, timeline or not: elsewhere it saves the content's measure, which
a memo at or below the frame often served anyway, for the cost of reading the frame's six fields. A timeline's size
change still propagates where it can: a timeline outside a pinned frame is measured at each entry as before, and one
inside a pinned frame is drawn inside the pins, as it always was (`TimelinePinnedFrameMeasureTests` pins both, and that
a frame pinned on one axis still measures its content).

Measured (`Tools/Profiling/ab_bench.py`, release, CPU per frame, 10 paired reps, against 75e461955):
`app-shapes/timeline-tiles` 647.2 → 374.6 µs, −40.3% (95% CI −44.2% to −39.4%); `session/case:timeline-tiles` 1404.6 →
1074.5 µs, −22.8% (−23.4% to −17.1%); `app-shapes/game-loop`, whose board is in a pinned frame, 92.7 → 82.6 µs, −5.5%
(−10.9% to −0.1%), and its case −3.2% (−6.6% to −2.6%); `app-shapes/timeline-beside` −2.2% (−2.9% to −0.8%);
`timeline-rows` and `session/case:timeline-beside` indistinguishable. The default sweep (36 scenarios, none with a live
timeline, on a busy box, load 4.8): 32 indistinguishable, `table-churn` −8.2% faster; `scrolleager` +3.2%, `table-tail`
+1.5% and `texteffects` +1.0% read slower, and again at 20 reps +0.7% (−0.9% to +1.3%), +1.0% (−0.5% to +2.8%) and −1.6%
(−2.9% to −0.2%): two indistinguishable and one faster. `Stress --check-counts`: `bodies` and `misses` fell, and nothing
else moved, in the cases with a frame pinned on both axes (`timeline-tiles` over its second, `bodies` 4538 → 1997 and
`misses` 12253 → 3056; `game-loop`, `timeline-beside` and four form cases by less); bytes unchanged (95 of 95 sessions'
`TUI_HEADLESS_STREAM` identical).

**What an entry still costs.** The walk itself. Each ancestor of a live timeline is still drawn at each entry: its
body kept (`FrameBodyKeep`, whose keys and environment stamps were 12% of a frame of `timeline-tiles` after this
change), its children's buffers fetched or drawn and stacked again. The re-assembly is small by now (`assembleColumn`
0.8%, padding 1.4%), with one exception: the preview's `ZStack`, which composites its two layers again at each entry
(`FrameBuffer.layered`, 7.4%; B-TLCTRL-4, below).

## The composite of a ZStack beside a live timeline (B-TLCTRL-4)

*Added 2026-11-19, with B-TLCTRL-3 built.* A launcher's preview is a `ZStack` of the picture and the timeline that
moves it, the timeline beside the picture rather than behind it (tuiarcade's `AttractPreview`). The walk reaches the
stack at every frame, since it is an ancestor of a live timeline, and `FrameBuffer.layered` composited its layers onto
a blank canvas again, cell by cell (`composedRow`, `insertOverlay`), though at a frame of `timeline-tiles` one
preview's picture at most had moved and the other layer is a zero-size `Color.clear`.

**What changed.** The same keep as a layer modifier's (B-TLCTRL-2): a stack's composite is a function of its layers,
each where it lands, the canvas's size, whether a layer past the canvas is drawn past it, and what the environment
says about blending. While a timeline is live, `_ZStackCore` keeps its composite in `LayerCompositeKeep` with all of
those (`Direction.stacked(width:height:splitsOverhang:)`, the layers in drawing order) and serves it while every one
compares equal. Not kept: a composite one of whose layers carries animated runs, which may ask for a wake (a later
layer showing an earlier one's field asks for the run's steps), and one that may have drawn into the image store. The
layers are drawn, or served by their own memos, before the keep is asked, so everything they register is registered
as before; a served composite skips only the cell arithmetic. `TUI_VERIFY_RENDER_MEMO` makes a composite that would be
served again and compares the two; `TUI_KEEP_TIMELINE_ANCESTORS=0` turns it off with the rest.

Time Profiler, `Stress --bench --scenario session/case:timeline-tiles` (release, `-g`), 8 s attached,
`analyze_timeprofile.py --thread main`, inclusive:

| Frame | Before (B-TLCTRL-3 built) | After |
|---|---|---|
| `FrameBuffer.layered` (the previews' `ZStack`s composited) | 7.4% | 1.0% |
| `composedRow` in `FrameBuffer.composited` (within it) | 3.6% | 0.6% |
| `_CanvasCore.renderToBuffer` (the moved preview drawn) | 8.8% | 10.5% |
| `EnvironmentStamps.stamp(of:)` (the bodies' keys above the timelines) | 12.2% | 13.7% |

Measured (`Tools/Profiling/ab_bench.py`, release, CPU per frame, 10 paired reps, against B-TLCTRL-3 built):
`app-shapes/timeline-tiles` 376.3 → 298.2 µs, −20.4% (95% CI −22.9% to −19.3%); `session/case:timeline-tiles` 1087.0 →
1003.1 µs, −7.6% (−9.0% to −6.7%); `timeline-beside`, `game-loop` and `timeline-rows`, which hold no `ZStack` beside a
timeline, indistinguishable but for `session/case:game-loop`, −0.6% (−3.5% to −0.2%). The quick sweep (7 scenarios, none
with a live timeline): 6 indistinguishable, `modifiers` +0.7% (+0.0% to +1.3%), where the change is a load and a branch
per `ZStack` drawn. `Stress --check-counts`: no count moved, as for B-TLCTRL-2; bytes unchanged (95 of 95 sessions'
`TUI_HEADLESS_STREAM` identical). With B-TLCTRL-3, a frame of `timeline-tiles` went from 647.2 to 298.2 µs (−54%) and a
step of its perf case from 1404.6 to 1003.1 µs (−29%).

**What is left.** The walk through the ancestors itself, which none of these memos can skip without serving a picture
that holds the timeline: each is drawn at each entry, its body kept (`FrameBodyKeep`, whose keys and their environment
stamps are now the largest single cost, 13.7%), its context copied and its children fetched. Under the owner's ruling
A-TLCTRL-1 = F0 the focused tile is drawn at each entry in any case. The stamps are a separate question: an environment
no derivation reaches is stamped flat, its keys hashed and sorted, at each pass.

## The environment stamp built at each pass (B-TLCTRL-5)

*Added 2026-11-19, with B-TLCTRL-4 built.* A kept body's key holds the stamp of the environment it was built under
(`frameBodyKey`), and each ancestor of a live timeline asks for one at each entry. Time Profiler,
`Stress --bench --scenario session/case:timeline-tiles` (release, `-g`), 8 s attached, `analyze_timeprofile.py --thread
main`, inclusive:

| Frame | Before | After |
|---|---|---|
| `EnvironmentStamps.stamp(of:)` | 13.7% | 7.9% |
| `EnvironmentStamps.build(_:)` (the flat stamp) | 7.3% | 2.2% |
| its `sort(by:)` | 5.8% | not in the top 600 |
| `EnvironmentStamps.derive(_:)` (the others, against it) | 2.3% | 3.9% |

(The second column is a share of a cheaper frame.)

**Why a stamp is made again at each pass, not reused.** A stamp is memoized per pass by its environment's storage, and
no storage outlives a frame: the run loop builds the root environment afresh and installs a new volatile-read tracker
in it at every frame, and every environment below is a copy of it with a key or two set. So the first environment
stamped in a pass, the anchor, is stamped flat, every key read, classified, hashed and sorted, and the others are
derived from it (counted in a debug build: 326 of the case's 380 passes built one flat stamp and derived three). A flat
stamp is interned, so an environment equal to last frame's is last frame's stamp and keys compare by identity. Here
none ever was: the anchor is a tile's environment, below its `.focused(_:equals:)`, and that modifier puts a new
`AssignedFocusID` object, the focus id it offers, into the environment at every render. A stamp compares a class by
identity, so the anchor never equals last frame's, nor does any stamp derived from it, and every kept body's key is
compared with last frame's flat, entry by entry. Keeping the anchor into the next pass, to derive the next frame's
first environment from it, was weighed and not done: the anchor keeps the environment it was made from, which holds
the render cache and the state storage, so it would be the cycle `EnvironmentStamps.endPass` exists to break; and its
cheap comparisons (an object's address, equal bytes) are sound only while that environment keeps every object it
holds alive. Comparing the offer by its id instead was measured as an experiment and not built: with the
offer compared by its id, and a claim of it made a render side effect so that no memo keeps a picture whose claim it
cannot make again, `app-shapes/timeline-tiles` was 5.2% faster (95% CI −6.3% to −4.6%) and its perf case 1.2%
(−1.7% to −0.3%), the flat stamp still built at each pass. It changes what may be served below every `.focused`, for
a small gain here, so it is left for a lane that measures it where `.focused` wraps more.

**What was slow was the sort.** `build` sorted its entries by key, and an entry holds an existential and a closure, so
each step of the sort copied two entries through the runtime's generic tuple witnesses, a retain and a release each
(594 of the 745 ms `build` took). It now sorts each key with its hash and its place, three words, and gathers the
entries in that order once. The stamp is the same: the same entries in the same order, the same shallow hash
(`EnvironmentStampTests`' key-order test pins both).

Measured (`Tools/Profiling/ab_bench.py`, release, CPU per frame, 12 paired reps, against B-TLCTRL-4 built):
`session/case:timeline-tiles` 1012.3 → 946.2 µs, −6.6% (95% CI −7.5% to −3.3%); `session/case:timeline-beside`
−11.0% (−11.5% to −10.6%); `session/case:game-loop` −14.5% (−15.3% to −14.1%). The perf cases run under the app's run
loop, whose root environment holds 62 keys; the bench scenarios' hosts hold far fewer, and `app-shapes/timeline-tiles`,
`timeline-beside` and `timeline-rows` were indistinguishable, `game-loop` +0.9% (+0.1% to +3.5%), and at 20 reps
+1.4% (−1.5% to +3.1%), indistinguishable. The sweep is under B-TLCTRL-6, with which it was run. `Stress
--check-counts`: no count moved; bytes unchanged (95 of 95 sessions' `TUI_HEADLESS_STREAM` identical).

## The process environment read at each frame (B-TLCTRL-6)

*Added 2026-11-19, with B-TLCTRL-5 built.* `RenderLoop.buildEnvironment`, which makes each frame's root environment,
wrote the terminal's line styles from `TerminalHost.lineStyles`, which names the terminal from the process environment
(`TerminalHost.program`), and `ProcessInfo.environment` copies the whole of it into a new dictionary at each read:
5.9% of a frame of `session/case:timeline-tiles` (`static TerminalHost.program.getter` 601 ms of 10,172, all of it
under `buildEnvironment`, 7.7%).

Nothing it reads changes under a running loop. The one write TUI makes, `TUI_TERM_PROGRAM` seeded from the terminal's
answer when nothing named it (`TerminalHost.seedDiscoveredHost`), is made before the loop is made (`identifyHost`),
for the same reason: the loop's `FrameDiffWriter` and its hairline layer read the host once, at construction, and the
`TerminalHost` detectors are `static let`s. And the variable is documented as read once (*Environment variables*). So
the loop reads the line styles once, when it is made (`RenderLoop.lineStyleSupport`), and writes that at every frame.
Under tmux the answer was already fixed for the run (`.tmux`; tmux re-spells line styles for each client itself).

Time Profiler, `Stress --bench --scenario session/case:timeline-tiles` (release, `-g`), 8 s attached,
`analyze_timeprofile.py --thread main`, inclusive, B-TLCTRL-5 built: `RenderLoop.buildEnvironment()` 7.3% → 1.1%,
`_ProcessInfo.environment.getter` 4.7% → not in the top 600. Measured (`Tools/Profiling/ab_bench.py`, release, CPU per
frame, 12 paired reps, against B-TLCTRL-5 built): `session/case:timeline-tiles` 942.4 → 869.9 µs, −8.0% (95% CI −8.7%
to −7.4%); `session/case:timeline-beside` −10.5% (−11.4% to −9.9%); `session/case:game-loop` −15.5% (−17.8% to
−14.8%); the bench scenarios, which draw without a run loop, indistinguishable. With B-TLCTRL-5, a step of
`timeline-tiles`' perf case went from 1012.3 to 869.9 µs (−14%). The default sweep, B-TLCTRL-4 built against both (36
scenarios, 10 reps): 7 faster, 27 indistinguishable, `table-churn` +0.9% (+0.5% to +1.5%) and `table-tail` +0.5% (+0.3%
to +1.9%) slower, and at 20 reps −0.2% (−10.4% to +6.1%) and +0.6% (−0.6% to +1.3%), both indistinguishable.
`Stress --check-counts`: no count moved; bytes unchanged (95 of 95 sessions' `TUI_HEADLESS_STREAM` identical).

## Decisions

### A-TLCTRL-1. A focused control beside a live timeline: replayable, or drawn?

*Put to the owner, who ruled below.* Whether to build F1 (a focused `List`'s and `Button`'s registration replayable at their own
memo while a timeline is live, every input dropping the focused control's buffers, its focused-only claims
journalled), or to stay at F0. What a SwiftUI program would change: nothing either way; under F0 a launcher
whose list holds the focus pays for the list's draw at each of its loop's entries.

**Ruled 2026-11-19: F0, (a).** Measured first on tuiarcade's launcher at 7e050123a (release, 100×30, 10 s):
the launcher itself has no `List` any more (focusable tiles, about 4% of a core idling); a `List` with the
previews beside it and a `Button` to Tab to costs 3.8–4.1% focused against 3.7% unfocused, so F1 would save
at most about 0.25% of a core; a `List` whose rows hold the previews changes under its focused row's tint at
every entry, so a kept picture would be stale and F1 could serve nothing. The owner chose F0, as F1's benefit
is insignificant. What that `List`-of-previews shape does cost is each visible row drawn twice a frame
(`rowsOverflow`, then `composeRowLines`), a separate fix.

### B-TLCTRL-1. List and Button are memoized at their own identity while a timeline is live

*Decided here, 2026-11-19, and built.* `List` and `Button` conform to `_PlainMemoizedBesideTimelines`, which
`PlainMemo.comparison(forRoot:)` honours only while `FrameBodyKeep.timelinesLive` (a timeline asked for a wake
this pass or the last) and `FrameBodyKeep.isOn`, so `TUI_KEEP_TIMELINE_ANCESTORS=0` turns it off with the body
keep it complements. A `Button` holds its `@ViewBuilder` label in an `AnyView`, an existential no comparison
reads, so `Button` compares itself (`_ValueComparing`): its fields, and its label by the view the `AnyView`
erases (`AnyView.valuesEqual`), which is not a conformance of `AnyView`'s, since that would make every view of
an app's holding one comparable at once. Two controls, not every framework control: the two the feedback
measured, and the two whose own draw is dear. Another joins by the conformance, once its unfocused draw is
known to read nothing the key and the invalidations above miss.

Known limit, as for an app's view: an environment holding a value that is not `Equatable` (a custom
`ButtonStyle` that is not, say) has no stamp, and nothing drawn under it is memoized.

### B-TLCTRL-2. A layer composite is kept across frames while a timeline is live

*Decided here, 2026-11-19, and built.* `compositeDrawnLayer` keeps each composite with everything it was made from
(`LayerCompositeKeep`) and serves it while a timeline is live when every input compares equal; a composite that asked
for a wake or may have drawn into the image store is not kept. A pure function's memo, so no question for the owner:
it changes nothing a frame shows or registers. Not extended to frames with no live timeline, where it would cost a
compare and the buffers' retention at every layer modifier the walk reaches, for a gain not measured.

### B-TLCTRL-3. A frame pinned on both axes does not measure its content

*Decided here, 2026-11-19, and built.* `FlexibleFrameView`'s measure of a frame pinned on both axes is its pins held to
the offer, without the content's measure, which its arithmetic does not read; except under a `scrollTo` search's
measure. Everywhere, not only beside a live timeline: the answer is the same, and the content's measure was only cost.
Above a live timeline it is what lets the measures above a pinned frame be kept across entries.

### B-TLCTRL-4. A ZStack's composite is kept across frames while a timeline is live

*Decided here, 2026-11-19, and built.* `_ZStackCore` keeps its `FrameBuffer.layered` composite in `LayerCompositeKeep`
with its layers, their places, the canvas and the environment's blending inputs, and serves it while a timeline is
live and all compare equal; one whose layers carry animated runs or may draw into the image store is not kept. A pure
function's memo, as B-TLCTRL-2's. The other users of `FrameBuffer.layered` (a stack's glide, a windowed stack's z
order, a pulled `ZStack`'s band) are left as they were: none was measured beside a live timeline.

### B-TLCTRL-5. A flat environment stamp sorts its keys, not its entries

*Decided here, 2026-11-19, and built.* `EnvironmentStamps.build` sorts each key with its hash and its place and then
gathers the entries in key order, rather than sorting the entries themselves. A refactor of how the stamp is made:
every stamp is what it was. A stamp is still made flat once per pass, not kept across passes: what that would keep
alive, and the comparisons it would make unsound, are above.

### B-TLCTRL-6. The render loop reads the terminal's line styles once

*Decided here, 2026-11-19, and built.* `RenderLoop` reads `TerminalHost.lineStyles` when it is made and writes that
value as each frame's `lineStyleSupport`, rather than reading the process environment at every frame. No behaviour
changes: what it reads is settled before the loop is made, as for the loop's diff writer.
