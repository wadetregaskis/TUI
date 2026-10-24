# Animated scrolling: a design and a price (B27, option 3)

*Written 2026-10-24 for the owner's answer to
[B27-ANIMATING](<../../../Open owner decisions.md#b27-animating>) (option 3,
2026-10-23). Nothing here is built. Line references are to `main` at
`83d6292fd`.*

The ruling covers three things. Programmatic scrolls made inside an animation
(`ScrollViewProxy.scrollTo`, `ScrollPosition` writes, anchor changes) move in
whole-line steps at 60 Hz along the animation's curve. While they move, the
view reports `ScrollPhase.animating`: idle → animating → idle, as SwiftUI does
(measured, [B27](<../SwiftUI API completion decisions.md#b27-scroll-phases-interacting-until-a-quarter-of-a-second-of-quiet-and-no-velocity>)).
Under reduce motion they jump. On top of that, Page Up/Down and Home/End can
glide, through a TUI-only opt-in modifier.

**Price: about 6 days (estimate), in 8 commits.** Idle cost is one nil test per
scrollable per frame. A glide frame costs what a one-line wheel step costs now,
and is drawn only on ticks where the line changes.

## 1. Where the animated offset lives, who moves it, and how a frame reads it

**Today.** A scroll view's offset is `ScrollViewHandler.scrollOffset`
(`Sources/TUIkitFoundation/Focus/ScrollViewHandler.swift:106`). It is in whole
lines and is the one value that both event-time code (keys, wheel) and the
render read. Programmatic placements go through `jumpProgrammatically(to:)`
(`ScrollViewHandler.swift:423-426`):

- a seek resolved by drawing the content at the request
  (`Sources/TUIkitFoundation/Views/ScrollView.swift:635-670`);
- a bound position's edge or offset (`ScrollView+ScrollPosition.swift:44-65`).

`scrollTo` parks a request on every registered scroll view and asks for a frame
(`ScrollViewReader.swift:154-162`). That request goes through
`AppState.setNeedsRender()`, which stamps the ambient transaction
(`Sources/TUIkitView/State/State.swift:63-66, 100`). The loop publishes that
transaction for exactly one pass (`Sources/TUIkitApp/App/RenderLoop+Animation.swift:70`).
So the frame that consumes the request already sees the `withAnimation`
transaction, which is how B30 reads `scrollTargetAnchor`
(`ScrollView+ScrollPosition.swift:27`).

**Proposal: `scrollOffset` stays the drawn offset, and a glide is a distance.**
A new `ScrollGlide` value sits beside `overscrollState` as a requirement of
`ScrollableOffsetState` (`ScrollableOffsetState.swift:123`). Both
`ScrollViewHandler` and the lists' `ItemListHandler` therefore carry it, and
the horizontal axis's conformer does too. It holds:

- `distance` (signed, in the scrollable's `scrollFine` unit);
- `covered` (how much has been stepped so far);
- the `Animation`;
- `startNanos` (frame clock);
- what to re-apply on landing (the request, or an edge).

Each frame steps the offset by `round(distance × fraction) − covered` through
`scrollFine(by:)`. That step costs O(step), and it is a line step for a list
too (`Sources/TUIkitLists/Focus/ItemListHandler+Keys.swift:551`). The fraction
comes from `Animation.fraction(at:)` and the end from `isFinished(at:)`
(`Sources/TUIkitCore/Animation/Animation.swift:559, 592`). A spring's overshoot
shows inside the content and is clamped at its ends. A repeating animation
glides on its first pass only.

**Why not `AnimationStore`?** It is the shared "where has the picture got to"
store (`Sources/TUIkitView/Animation/AnimationStore.swift:195`), and
`ChildGlide` uses it (`ChildGlide.swift:259-261`). It does not fit here for
three reasons:

1. Keys and the wheel move the offset at event time, with no context.
2. The store treats every new target as a fresh change, and with no animation
   in force it jumps there (`AnimationStore.swift:256-263`). So the anchor
   adjustments in §2 would abandon a glide.
3. Its live records hold the 30 Hz lattice open (`RenderLoop+Animation.swift:89-95`;
   `AnimationRequest.viewAnimations` is 2 ticks, `AnimationRequest.swift:48`).
   A glide wants 60 Hz frames, and only some of them.

What we lose is the store's velocity-preserving retarget
(`AnimationStore.swift:564-596`). See §2.

**Who advances it.** The render advances it. One shared call,
`settleGlide(context:)`, follows the precedent of `settleOverscroll`, the
spring-back that already steps a scroll a line a frame on wakes it asks for
(`ScrollOverscroll.swift:131-150, 166-177`). On a render pass with a glide:

1. Step the offset to this frame's place before the content draws, where
   `applyPositionOffset` runs (`ScrollView.swift:606`).
2. Declare the frame volatile and ask for one wake, with
   `context.requestWake(token:atNanos:)` (`RenderContext+Animation.swift:93-101`).
   That call also records the render side effect, so no memo above keeps a
   mid-glide frame. The wake is set at the first 1/60 s tick at which the
   rounded position changes. To find that tick, sample the curve forward a
   tick at a time; that is a few curve evaluations per frame.

So a 5-line glide draws 5 frames, not the 21 that 0.35 s holds. The default
spring (`Animation.swift:131-137`) makes its last visible change at about
0.84 s, so no glide draws more than about 50 frames. The landing frame clears
the glide.

**The request frame.** A seek finds its target by drawing the content at it
(`ScrollView.swift:665-670`), and the frame must then show the starting offset.
So it draws again at the start, as `coverSnappedViewport` already does for a
reveal (`ScrollViewReveal.swift:397-418`). That costs one extra O(window)
render per animated request. An edge or offset request knows its target from
arithmetic and needs no second drawing.

**The animation in force** is `canAnimate ? transaction.effectiveAnimation : nil`,
dropped under reduce motion. That is `ChildGlide`'s rule
(`ChildGlide.swift:251-253`).

**Completions.** The glide reports `noteStarted(_:at:key: nil)` to the pass's
completion tracker (`AnimationCompletionTracker.swift:75`). So
`withAnimation(…, completion:)` fires at the animation's deadline, as a
departure's does.

**`.animating`.** `reportScrollPhase` (`ScrollPhase.swift:179-197`) runs only
when there is an observer, so the phase costs nothing without one. It sets
`.animating` on the request frame and `.idle` on the landing frame, with
velocity (0, 0) as everywhere (R1). `settlePhase` (`ScrollPhase.swift:202-216`)
keeps handling `.interacting`. The `.animating` comment
(`ScrollPhase.swift:45-47`) changes to say when it is produced.

## 2. Interactions, each with its rule

- **Scroll anchoring while content changes mid-glide.** The top-row hold
  (`ScrollView+Anchor.swift:204-260`) shifts the offset when rows arrive above
  the top row. The glide is a distance, so the rest of it is unchanged: the
  destination moves with the rows, which is right for an insertion above both.
  An insertion between the viewport and the destination would land the glide
  off by the inserted lines. To correct that, the landing frame re-applies the
  original request without animation (a re-seek, or the edge). That costs one
  seek, and the jump is usually zero lines. A view in the middle of a glide is
  not glued to its tail (`isGluedToBottom`, `ScrollView+Anchor.swift:128`). A
  bottom-edge glide lands through the End path's tail seek
  (`ScrollViewHandler.swift:409-412`), so rows that arrive during it are
  followed from the landing on. `.scrollContentOffsetAdjustmentBehavior(.disabled)`
  needs no rule of its own: it stops the hold, and the glide carries on.
- **`scrollTargetBehavior`.** Programmatic scrolls are not gestures, here as in
  SwiftUI (compatibility guide, Scrolling row, `SwiftUI compatibility guide.md:130`).
  So a `scrollTo` glides to its own target, unsnapped, as it jumps there today.
  A paging key is a gesture. Its landing is the behaviour's target
  (`userScrollStep`, `ScrollableOffsetState.swift:256`, applied in
  `userScrollFine`, `:652-653`), which is snapped first and then glided to.
  Intermediate frames are not landings and do not consult the behaviour. A
  resize in the middle of a glide lands it at its target before
  `settleTargetAfterResize` runs (`ScrollViewReveal.swift:371-389`).
- **Scroll transitions** are worked out from where each view sits at the frame's
  offset (compatibility guide, Scrolling row). Every glide frame is a frame, so
  `.interactive` transitions follow each intermediate line. `.animated` ones
  switch at their threshold and run their own animation there. Under reduce
  motion they already hold their offsets still (A-D3M-1, FU3). No rule is
  needed.
- **User input mid-glide.** A wheel tick, a scrollbar press, a drag's
  auto-scroll, a focus move, or a key during a programmatic glide each stops the
  glide where it stands. The input then acts from there, and the phase becomes
  `.interacting` (`noteUserScroll`, `ScrollViewHandler.swift:374-378`). This
  matches SwiftUI, where a gesture interrupts an animated scroll (not measured
  here). During a key glide, a gliding key retargets from the glide's target,
  not from where it stands, so that N presses move exactly N pages. A
  non-gliding key (an arrow) lands the glide at its target first and then steps.
- **A second `scrollTo` mid-glide** starts a new glide from the drawn offset
  under the new transaction's animation, starting at rest. An unanimated one
  cancels the glide and jumps. Carrying the velocity over would reuse
  `AnimationStore`'s velocity estimate (`AnimationStore.swift:597-616`); that is
  half a day, and only if a port asks.
- **List and Table do not share ScrollView's path.** They resolve `scrollTo` and
  `.scrollPosition` themselves (`_ListCore.swift:1869-1874`,
  `Table.swift:2934-2941`) through `ItemListHandler.scroll(toRow:anchor:)`
  (`ItemListHandler+ScrollTo.swift:23-43`). Because the glide state is on
  `ScrollableOffsetState`, they share the glide but not the seek. The glide
  moves the viewport only; the focus cursor and the selection stay put, as
  `scroll(toRow:)` promises. **A gap found while writing this:** neither reports
  any scroll phase today. No `onScrollPhaseChange` observer is read in
  `TUIkitLists` or `TUIkitTables`, where SwiftUI's `List` is a scroll view and
  reports them. `.animating` on a list needs that reporting first (piece 6).
- **Nested scroll views.** A request is parked on every registered view, and
  each resolves it against its own content (`ScrollViewReader.swift:144-162`).
  So each view that holds the key glides on its own handler, just as each jumps
  today. A wheel in the middle of a glide is spent on the gliding view: it is
  not at an edge, so nothing chains to the enclosing scroller
  (`ScrollableOffsetState.swift:633-690`).
- **Lazy stacks** draw the band at each frame's offset, so each frame is
  O(window) even at millions of rows. Rows the glide passes between two frames
  are never built. Rows a frame shows are built, appear, and report visibility
  (`onScrollVisibilityChange` reports from what each frame draws). The
  intermediate offsets can land on estimated heights (`contentHeightIsEstimate`,
  `ScrollViewHandler.swift:310`); the landing re-seek corrects the end.
- **A bound `.scrollPosition(id:)`** is written back only on landing, not at
  each intermediate row. Written every frame, it would make the app's body
  render again on every glide frame (`ScrollView+ScrollPosition.swift:67-74`).
  SwiftUI's behaviour here is not measured. If a probe shows it reports along
  the way, this becomes a recorded deviation.

## 3. Reduce motion

Under reduce motion every glide is a jump, the scrollTo and the keyboard ones
alike. This is A-D3M-1 (scroll offsets are spatial motion,
`D3M.md:147-160`), applied through `ChildGlide`'s rule
(`ChildGlide.swift:251-253`). Without a scheduler (`canAnimate` false, a
one-off render) it jumps too. A jump changes no phase, as an unanimated
`scrollTo` changes none (measured, B27). D3M's line "Scrolling is never
animated in TUIkit" (`D3M.md:166`) is rewritten when this ships.

## 4. The TUI-only keyboard opt-in

```swift
extension View {
    /// The animation a scrollable's Page Up/Down and Home/End glide with,
    /// or `nil` (the default) to jump. TUI-specific.
    public func scrollKeyboardAnimation(_ animation: Animation? = .default) -> some View
}
```

It is an environment modifier, as `scrollChainingDelay(_:)` is
(`ScrollableOffsetState.swift:922-924`). It is read once a frame where the
handler is captured, beside `scrollChainingDelay`
(`ScrollView.swift:405-406`), because event time has no environment. It
animates `.pageUp`/`.pageDown`/`.home`/`.end` in `handleKeyEvent`
(`ScrollViewHandler.swift:460-506`):

1. The key computes the landing as now, with the behaviour, edge anchors and
   the tail seek all applied.
2. It puts the offset back.
3. It records the distance.
4. The next render starts the glide.

These do not glide:

- Arrows, Shift-arrows: one line, or five, is already a step.
- Wheel ticks.
- A push into overscroll: a line or two, shown at once.

The phase stays `.interacting`, since B27 defines keys as interaction. Its
250 ms quiet is counted from the landing, so a held Page Down is one
interacting span and does not flip back and forth with `.animating`. List and
Table paging moves their cursor (R1), so it joins later, as piece 7.

## 5. Cost

- **Per glide frame.** The cost equals a one-line wheel step's frame today. No
  scenario measures that on static content (`scrollfollow` and `scrolleager`
  change content every tick, `Sources/Stress/README.md:88-89`), so piece 8 adds
  one. What stays cheap:
  - Rows are drawn with the scroll window cleared (`VStack.swift:860`,
    `StackTargetLayout.swift:70`), so a row's memo does not depend on the
    offset. Rows on screen at consecutive offsets are served from it wherever
    that row memoises.
  - The scroll view and its windowed stack composite again every frame. The
    window, offset included, is part of the environment their memos key on
    (`ScrollContentWindow.swift:13-47`).
  - The scrollbar memo misses whenever the thumb moves
    (`ScrollViewHandler.swift:65-76`).
  - The bytes are the changed viewport lines. Nothing is scrolled in hardware
    yet (`Terminal compatibility survey.md:6787`, O2).
  - The `onScrollGeometryChange` observers run every frame, as they would for
    a wheel.
- **Idle.** One `glide == nil` test per scrollable per render. There are no
  wakes, no volatile reads, and no environment reads beyond the keyboard
  modifier's one lookup per scroll view. That lookup is the one cost to watch:
  `tables-scroll` showed 0.3 µs per scroll view as +4.2% (`Performance pass
  after the SwiftUI API batch (2026-10).md:231-234`). If it shows there, fold it
  into a value already read.

**Price, in landing order (estimates; one commit each):**

| # | Piece | Days |
|---|-------|------|
| 1 | `ScrollGlide` on `ScrollableOffsetState`, `settleGlide`, line-crossing wakes, reduce motion, completions; `ScrollView` vertical `scrollTo` and `ScrollPosition` row requests, including the start-offset redraw | 1.5 |
| 2 | `.animating` reporting in `ScrollView` | 0.25 |
| 3 | Interruptions and retargets, the landing re-seek, the resize landing, edge glides through the tail seek | 1.0 |
| 4 | Horizontal axis: `ScrollPosition` x and column `scrollTo` | 0.5 |
| 5 | `scrollKeyboardAnimation(_:)` for `ScrollView` | 0.75 |
| 6 | `List` and `Table`: animated `scroll(toRow:)` and position requests, plus `onScrollPhaseChange` reporting, which they lack | 1.0 |
| 7 | `List`/`Table` keyboard paging under the modifier (the cursor's page move glides the viewport) | 0.5 |
| 8 | Stress `glide` scenario, profile, docs (R1 rewritten, B27, guide row, D3M:166, `ScrollPhase.swift:18` and `:45-47`, `AccessibilityReduceMotion.swift:39`) | 0.5 |

**Total: about 6 days.** Pieces 1–3 deliver the SwiftUI parity on their own
(about 2.75 days). 4–5 complete the ruling for `ScrollView`, and 6–7 extend it
to the lists.

**Risks.**

- The request frame draws twice.
- The landing re-seek can show a final jump under heavy churn.
- A heavy page pays a full frame for every line step for up to about 0.84 s.
- The scrollTo transaction lasts one frame. A scroll view that does not draw on
  that frame, such as one in a hidden tab, jumps when it next draws.
- The memo verifier cannot see side effects, so test the volatile declaration
  directly.

## 6. Tests that would pin it

Clocks are pinned as the existing tests pin them: `frameNowNanos` on the
context (`Tests/TUIkitEffectsTests/StackGlideTests.swift:125`) and
`handler.phaseNow` (`Tests/TUIkitAppTests/OnScrollPhaseChangeTests.swift:45`).

1. An animated `scrollTo` draws the start on its first frame, then whole-line
   offsets that never move backwards under an ease, then the target. An
   unanimated one still jumps.
2. Frames are asked only at ticks where the line changes: an n-line glide asks
   for at most n wakes, all on 1/60 s ticks.
3. Phases: idle → animating → idle, velocity (0, 0) at each. A wheel in the
   middle gives animating → interacting, with no idle in between.
4. Under reduce motion, and with `canAnimate` false, it jumps and reports no
   phase.
5. `withAnimation(…, completion:)` fires once, at the animation's end.
6. An insertion above mid-glide still lands on the row. An insertion between the
   viewport and the row lands on it through the landing re-seek.
7. A second `scrollTo` retargets from the drawn offset. A wheel stops the glide
   where it stands.
8. A `.paging` view's Page Down glides to a page boundary. Three presses
   mid-glide land exactly three pages down. Down mid-glide lands the page and
   then steps.
9. A `.interactive` scroll transition's phase changes on intermediate frames.
10. A lazy stack at 10⁶ rows glides with O(window) rows built per frame.
11. A bound `.scrollPosition(id:)` is written once, on landing.
12. `List` and `Table` glide without moving the cursor or the selection, and
    report the phases.
13. Idle: a settled scroll view requests no wake and serves from its memo.
    Gliding, it declares the frame volatile.
14. Without `scrollKeyboardAnimation`, every key jumps as today (the existing
    key tests are unchanged).
