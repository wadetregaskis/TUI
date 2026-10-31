# Animation timing: curves, springs, keyframes and completions

*How TUI's animations came to keep SwiftUI's time: `UnitCurve`, `Spring`,
keyframe timelines, when a completion fires, velocity tracking, animatable
geometry, and the cost of animatable `.padding` and `.frame`. Ids: B55 to
B58, B60, C1, C2, WL-Q3, O2-KEYFRAMES.*

## In short

Curves, springs and keyframe timelines are SwiftUI's arithmetic, measured,
except where its answers contradict its own documentation (B57) and two
spring quirks kept and one not (B58). A completion fires on the pass that
shows the change; a spring logically completes at its pace. Frames are 1/60 s
multiples. Under reduce motion a `KeyframeAnimator` keeps moving, as SwiftUI's
does (O2-KEYFRAMES, settled 2026-10-18).

## How it unfolded

The B items shipped with the animation waves. **WL-Q3:** in August animatable
`.padding` and `.frame` were measured at +7.5% on `deep`; re-measured on
2026-10-24 it was about +40%, its cause found (the measure walk asked the
animation store while nothing moved) and fixed (`deep` −25.2% warm).

## The record

### B55. `tracksVelocity` is recorded and read by nothing; `isContinuous` is set by TUI's own continuous controls

**Since 2026-10-18** a retarget hands the velocity on (O3's merging, with A38): a merging
spring starts the next at the speed the value was moving. What follows is the entry as written
before that, when no velocity was carried; `tracksVelocity` is still recorded and read by nothing.

*`Transaction.tracksVelocity`, `Transaction.isContinuous`*

**`tracksVelocity`.** SwiftUI accumulates the velocity of values changed under
such a transaction, so a later animation can start moving at that speed.
TUI's animations are closed-form functions of elapsed time that start at
rest — a spring retargeted mid-flight already restarts from where its picture
is, without its speed — so there is nothing to track, and the flag is a value
the transaction carries for whoever reads it. This is the one place the
"retargets at rest" deviation of every TUI spring shows up as a property;
the Wave 17 review (W6) asked for it to be documented in one place rather than
used to refuse spellings, and B58 (the spring animations) points here
too.

**`isContinuous`.** SwiftUI sets it when "a continuous action created the
transaction" — dragging a slider, holding a stepper. TUI now sets it on the
writes its own controls make that way: a press and drag on a `Slider`'s track,
and the repeats of a held arrow (`Slider`, `Stepper`) or a repeating
`Button` (the first action of the press is a click, and is not continuous).
A key the terminal repeats arrives as separate presses with nothing to say
they are one hold, so a held arrow KEY is not continuous. Setting the flag
makes the write an explicit transaction, which — like any `withTransaction` —
takes over from an animated change made earlier in the same frame.

**The fuller version** of `tracksVelocity` is O3's: velocity-preserving
retargeting needs integrated animations, the `CustomAnimation` question.

### B56. When a completion fires: the pass that shows the change decides, and a spring logically completes at its pace

*`AnimationCompletionCriteria` (`.logicallyComplete`, `.removed`),
`Transaction.addAnimationCompletion(criteria:_:)`,
`withAnimation(_:completionCriteria:_:completion:)`,
`Animation.logicallyComplete(after:)`*

SwiftUI fires a completion "when the animations created with this
transaction are all complete", exactly once, and "immediately after `body`"
if the changes created none.

**Shipped.** A completion rides the transaction onto the state change made
under it; the frame that renders the change starts its animations, and the
stores report each one they start (an animated value, an arriving transition,
a departing one) for that pass only. Then:

- **Nothing changed** in `body` (no state change claimed the completion): it
  runs as `withTransaction` returns.
- **Something changed but nothing animated:** it runs when that frame's pass
  ends.
- **`.logicallyComplete`:** when the latest logical completion among the
  started animations has passed. A curve completes at its end. A spring
  completes at the end of its pace — the `duration:` it was made with — and
  settles after that; SwiftUI calls that "the long tail". `.logicallyComplete
  (after:)` brings the point forward (it scales with `speed`, as the delay
  does), never past the end. A later change does not move it.
- **`.removed`:** when the latest end has passed and none of the values the
  pass started is still animating, so a retarget makes it wait for the new
  animation too.
- **A value whose view has left** is removed, so its completion fires
  whatever the deadlines say; a `repeatForever` animation still on screen
  never completes, as in SwiftUI.

Two transactions in one frame render under the last one (the rule TUI
already had), but each keeps its completion: the pending completions are
collected separately from the pending transaction.

**Readings, not measurements.** That a spring logically completes at its
perceptual duration is from SwiftUI's description of a spring's `duration`
("the perceptual duration, which defines the pace of the spring"); a
completion's timing could not be measured with an offscreen hosting view.
"The animations created with this transaction" is read as every animation the
change's frame starts — an unrelated `.animation(_:value:)` whose value moved
in the same frame is included.

**Not honoured:** a completion added by a view's `transaction(_:)` modifier
while rendering. No change was made under that transaction, so nothing claims
the completion and nothing runs it. SwiftUI documents no such use either.

### B57. `UnitCurve` is SwiftUI's arithmetic, except where its answers contradict its documentation

*`UnitCurve` (`value(at:)`, `velocity(at:)`, `inverse`, `bezier(startControlPoint:endControlPoint:)`,
the eight named curves), `Animation.timingCurve(_:duration:)`*

The Bézier curves share the solver an `Animation`'s timing curve uses (the
Wave 17 review asked for one formula, not two), and match SwiftUI's values and
velocities to the sixth place (measured, [`p3.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p3.swift>)). Two readings
differ from what SwiftUI answers, in the documentation's favour:

- **Out-of-range input is clamped**, as `value(at:)` and `velocity(at:)`
  document. SwiftUI clamps its Bézier curves, but not `.linear` (1.5 gives
  1.5) or the circular ones (1.5 gives NaN, -0.5 a mirrored value).
- **`circularEaseInOut.inverse` is the curve with x and y swapped**, as
  `inverse` documents: level in the middle, steep at the ends. SwiftUI
  answers `circularEaseInOut` itself, whose values are not an inverse at all.

Where a curve is vertical — `circularEaseIn` at its end, the circular in-out
at its middle — the velocity is infinite, as in SwiftUI. Where a Bézier's
control point sits on its end point the tangent vanishes, and SwiftUI answers
1 (`easeOut` at 0) or 0 (`easeIn` at 1, the quotient of two rounding errors)
rather than the limit the curve approaches (1.72 for both). TUI answers
the same, by the same arithmetic: a keyframe track carries a linear
keyframe's end velocity into the cubic keyframe after it, and the two
frameworks' tracks agree only if these do.

A circular curve is a new case of the animation curve, so
`Animation.timingCurve(.circularEaseIn, duration:)` moves along the circle;
a Bézier or `.linear` builds the animation `timingCurve(_:_:_:_:duration:)` and
`linear(duration:)` already build, and compares equal to it.

### B58. `Spring` is SwiftUI's numbers, two quirks kept and one not

**Since 2026-10-18** a spring keeps its velocity across a retarget: the fuller version below
shipped with O3's merging (and A38). The rest of the entry stands.

*`Spring` (its four initialisers, `duration`, `bounce`, `response`,
`dampingRatio`, `mass`, `stiffness`, `damping`, `settlingDuration`, `value`,
`velocity`, `force`, `update`, `settlingDuration(…)`, `.smooth`/`.snappy`/
`.bouncy` and their tunable forms), `Animation.spring(_:blendDuration:)`,
`spring(duration:bounce:blendDuration:)`, `spring(response:dampingFraction:blendDuration:)`,
`interactiveSpring` (all three), `interpolatingSpring` (all four)*

The Wave 17 review (W6) found the refusal of all of these to be a judgement,
not a limit: TUI already drew springs in closed form. `Spring` is that
closed form made public — one implementation (`SpringMotion`) behind both the
type's arithmetic and the curve a spring animation is drawn with — and every
number was checked against SwiftUI's `Spring` on a probe
([`p4.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p4.swift>), [`p5.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p5.swift>)): values, velocities with and without a
starting velocity in all three damping regimes, force, `update`, the
settling durations, the conversions, the presets.

**Quirks kept, because ported arithmetic reads them:**

- An overdamped spring's `stiffness` reads `(2ζ² − 1)` times the stiffness it
  moves with, and `force` uses it.
- A critically or overdamped spring's settling duration is found in steps of
  a tenth of a second (0.8 s for the default spring); an underdamped one's is
  the bound `ln((|y₀| + |v₀ + ζω·y₀|)/ε)/(ζω)`.
- `init(settlingDuration:dampingRatio:epsilon:)` solves a different relation
  from the one `settlingDuration` answers by, so the spring it makes reports
  a longer settling duration than it was asked for (1 s asks, 1.25 s
  reported, at ζ = 0.8), and a ratio above 1 is treated as 1.

**A quirk not kept:** SwiftUI's overdamped `velocity(…)` reads exactly one
more than the derivative of its own `value(…)` (1 at rest at t = 0). TUI
answers the derivative.

**Bounce at or below −1** is NaN in SwiftUI; here it stops at −0.999, a spring
too sluggish to visibly arrive, rather than a NaN on its way to a cell.

**Retargeting.** SwiftUI's `spring` hands its velocity to the next spring on
the same value, blending the durations over `blendDuration`; its
`interpolatingSpring` adds overlapping animations so velocity is preserved.
TUI's animations are functions of elapsed time from a start at rest: a
change that retargets a running spring starts the new one from where the
picture is, without the speed it had. So `blendDuration` has nothing to blend,
and `interpolatingSpring`'s `initialVelocity` is honoured for the change it
is given to — it moves the start of the curve and lengthens the settling the
loop waits for — but not inherited by the next. This is the deviation every
TUI spring already had (B55 records `tracksVelocity` against it); the
`interactiveSpring` presets are, accordingly, the quick springs their numbers
describe.

**The fuller version** is velocity-preserving retargeting: store the
velocity at retarget and start the next closed form with it
(`SpringMotion` already takes one). For springs alone that is a day — the
store records where the picture is; it would also record how fast — but a
curve retargeting into a spring, or a spring into a curve, has no velocity
model, which is O3's question.

### B60. Keyframe timelines follow SwiftUI's curves, measured

The animator views this entry left with O2 shipped with it on 2026-10-14.

*`KeyframeTimeline` (`init(initialValue:content:)`, `duration`, `value(time:)`,
`value(progress:)`), `Keyframes`, `KeyframeTrack`, `KeyframeTrackContent`,
`KeyframesBuilder`, `KeyframeTrackContentBuilder` (and `Conditional`),
`LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`,
`Never: Keyframes`*

The Wave 17 review (P13) found the timeline side of the keyframe family
wrongly refused: these are pure functions of time with no rendering at all,
and `KeyframeTimeline` cannot be written without them. `KeyframeAnimator` and
`keyframeAnimator` — the views that play a timeline — stay with O2.

**Shipped,** with every curve rule taken from SwiftUI's own timelines
([`p6.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p6.swift>), [`p7.swift`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes/p7.swift>)) and pinned by tests to six places:
adjacent cubic keyframes form a Catmull–Rom spline at rest at both ends; a
cubic keyframe starts at the velocity the keyframe of another kind before it
ended at, and ends at the next one's starting velocity; a named velocity
wins on its own side of a junction only; a spring keyframe without a
duration runs until it is within 0.0001 of its target (an absolute
threshold, so a larger change takes longer), and one cut short hands on the
value and velocity it reached; a move leaves the value at rest; tracks run
together from the initial value and the last to write a property wins.

**Where it differs.**

- **Main-actor isolated.** The protocols, builders and the timeline's
  initialiser and samplers are, because TUI's `Animatable` is (its values
  are read and written through `animatableData`). SwiftUI's are
  nonisolated. Code that builds a timeline in a view, a body or a `.task`
  compiles unchanged; one built off the main actor does not.
- **A time before the start is the start.** SwiftUI clamps its linear and
  cubic segments there, but evaluates a spring backwards (−58.5 at −0.5 s for
  a bouncy spring to 1).
- **A zero-length linear or cubic keyframe arrives at once**, where SwiftUI
  divides by its zero length and answers NaN.

### C1. `CGPoint`, `CGSize` and `CGRect` as `Animatable`

*`CGPoint.AnimatableData`, `CGSize.AnimatableData`, `CGRect.AnimatableData`*

This is a compiler wall, not a judgement. On Apple platforms, SwiftUICore's
own extensions of the CoreGraphics types are visible to any module that
imports Foundation, through a cross-import overlay. That is the same overlay
`Collection+Offsets.swift` already works around. SwiftUICore's
`AnimatableData` typealias on each type is found before any witness TUI
could give, so `extension CGPoint: Animatable` does not compile on macOS. I
tried with and without an explicit typealias.

`CGFloat` *is* conformed, because there the wall has a door. An app's ported
`Animatable` type with `CGFloat` data compiles and animates, and so does
`AnimatablePair<CGFloat, CGFloat>`. What stays ambiguous on macOS is calling
the extension methods directly on a concrete value (`x.interpolated(…)`).
That call never linked before either.

### C2. `CGPoint.applying(_:)`, `EdgeInsets.inset(by:edges:)`, `EdgeInsets.init(_:)`

- The first two take types that were already declined: `ProjectionTransform`
  and `RectangleCornerInsets`.
- The third converts AppKit's `NSDirectionalEdgeInsets`, whose values are
  points. The conversion would need an invented point-to-cell scale.

### WL-Q3. Animatable `.padding` and `.frame` on `deep`: measured, and the A/B built

*`.padding`, `.frame` (their `Animatable` conformances); ruling: (b), measure
the current impact first.*

**Measured** (counted, not timed; the numbers are in the work log's Q3):
`deep` at its depth of 40 makes 1,786 animation-store probes a frame, 1,706
of them on measure walks, all from paddings (`deep` has no `.frame`), and
every one answered by `isSettled`'s fast path: a key, a lookup, two casts,
nothing allocated, no environment read. They grow as about depth^1.8.

**Built:** the A/B's other side, on the branch `wlq3-animatable-layout-off`
(533b7b0ab, from main b8acc3898), never to land: padding and frame keep their
conformances and answer the walks' witnesses as non-animatable types. Its
padding and frame animation tests fail there, as they must. **A/B:** main
against that branch, `deep`, with `kitchensink` and `table` as controls.
Close the item if `deep` is within a few percent.

**The A/B** (the owner's, main b8acc3898 against 533b7b0ab, release,
warm, 15 reps): `deep` −28.5% [−29.1, −28.1] without the animatable path,
so about +40% for having it; `kitchensink` +0.0%, indistinguishable;
`table` −1.3% [−2.0, −1.0]. Not within a few percent: the item stays open.

**Why it is not the August +7.5%.** It did not grow; August did not see it.
The August A/B ran on a Stress bench that called `renderToBuffer` in a loop
and nothing else, so the per-pass measure memo was never emptied and every
frame's measures were served from the frames before (counted on that
commit, da01c6842, with temporary counters: 84 memo hits and 1 miss a
frame, and 80 store probes a frame, all on the render walk). The bench has
run the app's per-pass lifecycle since 87f260029 (2026-09-05), which moved
`deep` from 2,186 to 10,547 µs a frame because the app never had that warm
memo. Measured the same way now: 9,366 measure-memo lookups a frame (9.2%
hits), and 1,800 store probes, 1,720 of them on measure walks.

**Where the cost is** (Time Profiler, main's release build, 8 s of
`deep`): `animatedValue` 25.8% inclusive, of which the store's
`Dictionary.index(forKey:)` 22.5% and `IdentityNode.structurallyEqual`
21.3%; `swift_retain` / `swift_release` 11.1% / 13.0% self. A probe that
finds its record compares the key's identity node by node up to the root:
a record keeps the identity nodes of the frame that first saw it, every
frame builds new ones, so nothing is shared to stop the walk early. Each
nesting level of `deep` adds seven nodes, the probes' identities average
187 nodes, and identity comparisons visit about 363,000 nodes a frame,
nearly all in these lookups, each visit a retain and a release. The lookup was always this; the bench
now counts the measure walk that pays it 1,720 times a frame.

**A fix, for an A/B.** The measure walk skips the store where nothing in it
moves and no animation is in force (`animatedValue`,
`AnimationStore.presentsEveryTarget`). A measure writes nothing, so all it
did there was look up a record to learn the answer is the target: with no
record running or settled away from its target, no transition scrub
installed, and no animation in the transaction, every branch of
`value(for:…)` answers the target. The store keeps a count of its unsettled
records to say so in a load and a compare; the gate reads the transaction
(one environment read) in place of the lookup. The render walk still asks
every time, so the record a first animated change starts from is still made
at first sight, and on the frame such a change lands the transaction carries
its animation, so the measure asks and measures the old value
(`AnimatableModifierTests`). An arrival over is now retired as a value's
animation is, at what it presented, so a view that arrived under an
animation does not keep the gate shut while it stays. Profiled (`deep`,
release, 8 s, against the commit before it): `animatedValue` 25.5% → 1.8%
inclusive, `IdentityNode.structurallyEqual` 21.4% → 2.2%, the store's
`index(forKey:)` 22.1% → 0.2%, `swift_release` / `swift_retain` self
12.6% / 10.6% → 5.8% / 4.3%; the bench's checksums are unchanged on `deep`,
`kitchensink`, `animating` and `table`. **A/B:** `deep`, with `modifiers`
(many shallow paddings, where an environment read and a short lookup are
close), `kitchensink`, `animating` and `table`.
