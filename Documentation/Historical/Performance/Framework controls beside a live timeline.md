# Framework controls beside a live timeline

*A design and its first half, written 2026-11-19 against `main` at 2876f4f51, in answer to tuiarcade's
`TUI-FEEDBACK.md`, M2 item 3: while any `TimelineView` runs in the window, a `List` row's or a `Button`
label's content is "drawn again at every frame". Commit d4808499d fixed the app's own views beside and
above a timeline (`FrameBodyKeep`) and left this, with the diagnosis that framework controls have no memo
of their own and that a focused `List` registers focus in a way the memo cannot replay. Ids:
B-TLCTRL-1 (decided and built here), A-TLCTRL-1 (for the owner).*

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
- **A control that holds the focus** (not built, A-TLCTRL-1). Its registration still declines every memo
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
one.

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

## Decisions

### A-TLCTRL-1. A focused control beside a live timeline: replayable, or drawn?

*For the owner.* Whether to build F1 (a focused `List`'s and `Button`'s registration replayable at their own
memo while a timeline is live, every input dropping the focused control's buffers, its focused-only claims
journalled), or to stay at F0. What a SwiftUI program would change: nothing either way; under F0 a launcher
whose list holds the focus pays for the list's draw at each of its loop's entries.

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
