# Wave 12 (animation and transitions): decisions for review

*Written by the worktree that implemented Wave 12, to be folded into
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Same three parts: **A** needs your decision, **B** shipped the safe option,
**C** declined without asking. SwiftUI's behaviour quoted here is from its own
doc comments in the SDK's symbol graph unless an entry says it was measured;
measurements are from probes compiled against the macOS 26.2 SDK and run on
macOS 15.*

---

## A. Needs your decision

### A-W12-1 `BlurReplaceTransition`: a fade in place of the blur, or wait for W16?

*`BlurReplaceTransition` (and `Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`*

SwiftUI documents it as "combining blurring and scaling effects": `.downUp`
scales the view down while removing it and up while inserting it, `.upUp`
scales up both ways. The scale half is TUIkit's `.scale` reveal. The blur half
is the per-pixel filter the map declines (`VisualEffect.blur*`, confirmed by
the Wave 17 review, P14), and Wave 16 owns blur as a whole.

**Options.**

1. **Leave it out until Wave 16 decides blur.** Free. Code using it fails to
   compile, which is the rule for anything not honoured.
2. **Ship it as a scale and a fade.** A blurred-out view reads, at a cell's
   resolution, as one that has faded: there is no sub-cell detail to soften,
   and the opacity compositor already dissolves a cell's colours toward what
   is behind it. `.downUp` becomes the reveal from the centre plus the fade;
   `.upUp` the same on insertion and a fade alone on removal (a reveal cannot
   grow past the slot). An hour with tests, and the doc comment says
   the blur is drawn as a fade.
3. **Option 2, plus a cell "blur"**: soften the glyphs on the way out (shade
   blocks `▓▒░`, or the dim attribute) as well as the colours. A day, and a
   drawing that has no precedent in TUIkit.

**Recommendation:** 2, if Wave 16 does not give blur a cell reading of its
own; 1 until then. Nothing ships.

### A-W12-2 Symbol effects: declare TUIkit's own `SymbolEffect` types?

*`View.symbolEffect(_:options:isActive:)`, `View.symbolEffect(_:options:value:)`,
`View.symbolEffectsRemoved(_:)`, `Transition.symbolEffect`,
`Transition.symbolEffect(_:options:)`, `WiggleSymbolEffect.custom(angle:)`*

Every one of these takes a value from Apple's **Symbols** framework
(`SymbolEffect`, `IndefiniteSymbolEffect`, `DiscreteSymbolEffect`,
`TransitionSymbolEffect`, `SymbolEffectOptions`, `PulseSymbolEffect`, …), not
from SwiftUI. Symbols does not exist on Linux or Windows. The Wave 17 review
(P4) found the effects a single glyph can show — appear, disappear, replace
(cross-fade through the opacity compositor), pulse and breathe (an
`AnimatedCellRun` on the glyph's cell) — and the ones it cannot, which need
glyph geometry or layers: bounce, scale, wiggle, rotate, variable colour.

**Options.**

1. **Decline the family.** The modifiers fail to compile; an SF Symbol stays a
   still glyph.
2. **Declare TUIkit's own Symbols vocabulary** under Apple's names, for the
   five effects a glyph can show: the protocols, `SymbolEffectOptions`
   (`.repeating`, `.nonRepeating`, `.repeat(_:)`, `.speed(_:)`), and the
   effect structs with their builder members. Bounce, scale, wiggle, rotate
   and variable colour are left out, so asking for one fails to compile —
   which is also why `WiggleSymbolEffect.custom(angle:)` stays absent under
   either option. Two to three days with tests. It is the same policy question
   as A18 (declaring API that belongs to another Apple framework): a file that
   imports both TUIkit and Symbols would see two `PulseSymbolEffect`s.
3. **Option 2 with only the transition half** (`Transition.symbolEffect`,
   appear/disappear/replace), which is the part an ordinary port most often
   carries. About a day.

**Recommendation:** 2, after A18 is answered; until then 1.

### A-W12-3 `matchedGeometryEffect` waits on O4

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

`@Namespace` shipped in Wave 9, so the identifier half exists. The effect
itself — carrying a view from the source's frame to its own — and its
`MatchedGeometryProperties` are O4 of the refusal review, with options from
position-only (whole cells, size snaps) to a full re-layout per frame.
Nothing ships until O4 is answered.

### A-W12-4 `phaseAnimator(_:trigger:content:animation:)` waits on O2

*`View.phaseAnimator(_:trigger:content:animation:)`*

The animator views are O2 of the refusal review. If O2 goes (b), this is the
trigger form of that live phase animator, and its completion advance would use the
animation completions this wave adds.

### A-W12-5 `Animation.shouldMerge` and `Animation.velocity` wait on O3

*`Animation.shouldMerge(previous:value:time:context:)`,
`Animation.velocity(value:time:context:)`*

Both take an `AnimationContext`, which belongs to the `CustomAnimation`
family that O3 of the refusal review reopens. They are the merge and velocity
half of a custom animation's contract; with O3 (b) they would answer `false`
and the closed-form velocity respectively.

### A-W12-6 `Transaction.dismissBehavior` waits on O9

*`Transaction.dismissBehavior`*

It qualifies `dismissWindow`, the window family O9 reopens; A-W09-4 holds
`DismissBehavior` itself on the same question.

### A-W12-7 The geometric visual effects wait on Wave 16

*`VisualEffect.rotationEffect(_:anchor:)`,
`VisualEffect.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`VisualEffect.scaleEffect(_:anchor:)`, `VisualEffect.scaleEffect(x:y:anchor:)`,
`VisualEffect.transformEffect(_:)`*

The `View` modifiers of the same names are Wave 16's (sub-cell geometry, an
owner decision). The visual-effect spellings are the same requests made from a
geometry proxy, and should be answered with them; `VisualEffect` itself and the
effects with a cell reading are this wave's.

---

## B. Shipped the safe option

### B-W12-1 A custom transition's body is drawn at each frame's point between its phases

*`Transition` (`body(content:phase:)`, `Content`, `properties`,
`animation(_:)`, `combined(with:)`, `apply(content:phase:)`),
`TransitionPhase`, `TransitionProperties`, `PlaceholderContentView`,
`AnyTransition.init(_:)`, `View.transition(_:)` for a `Transition`*

**How SwiftUI does it.** A transition's body is evaluated at three discrete
phases. On insertion it is shown at `.willAppear` and then "immediately moved
to the `identity` phase" under the change's animation; on removal it goes from
`.identity` to `.didDisappear`. Nothing about the body is continuous: what
moves are the animatable modifiers inside it, each interpolated between the
value it had at one phase and the value it has at the other. "If no animatable
change is applied, then the transition will be a no-op."

**How TUIkit had it.** A transition was a value — `AnyTransition`'s closed set
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
scrubbed value never reaches, or disturbs, the store's own records.

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

**Where TUIkit cannot follow SwiftUI, and why.**

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
  out its siblings on every frame. TUIkit's transitions have never moved
  their neighbours (see `AnyTransition`); this is the same rule applied to a
  custom body.
- **A body that changes its structure between phases does not animate the
  difference.** A value is interpolated only where both renders produced it
  at the same place; a modifier present at one phase and not the other is
  drawn as the `.identity` render has it. SwiftUI asks for the same
  ("Transitions should not use any identity-affecting changes like `.id`,
  `if`, and `switch`").

**The built-in transition types** (`OpacityTransition`, `MoveTransition`,
`OffsetTransition`, `ScaleTransition`, `SlideTransition`, `PushTransition`,
`IdentityTransition`, `AsymmetricTransition`) have real bodies, built from one
animatable modifier that applies TUIkit's own effect at the body's presence —
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

### B-W12-2 `TransitionProperties.hasMotion` is recorded, and nothing reads it yet

*`TransitionProperties`, `TransitionProperties.hasMotion`,
`TransitionProperties.init(hasMotion:)`, `Transition.properties`*

SwiftUI: "When this behavior is included in a transition, that transition will
be replaced by opacity when Reduce Motion is enabled." TUIkit reads no
reduce-motion setting (O1 of the refusal review), so Reduce Motion is never on
and the replacement never happens — which is what SwiftUI does on a Mac with
the setting off. The built-ins report the values measured on SwiftUI: opacity
and identity have no motion, everything else has, and a combined or asymmetric
pair has motion if either half does.

**The fuller version** comes with O1 (b): when the host's reduce-motion
setting (or `TUIKIT_REDUCE_MOTION`) is on, `View.transition(_:)` swaps a
transition with motion for `.opacity`. A few lines once the setting exists.

### B-W12-3 A scale transition uncovers from its anchor, and a scale above 1 draws the view whole

*`ScaleTransition` (`init(_:anchor:)`, `scale`, `anchor`),
`Transition.scale`, `Transition.scale(_:anchor:)`,
`AnyTransition.scale(scale:anchor:)`*

TUIkit's `.scale` already reveals the view from its anchor a whole cell at a
time, there being no sub-cell rendering to shrink. The scale factor is now
where that reveal starts: `.scale(0.5)` shows half the view at once and
uncovers the rest. `.scale` itself is `ScaleTransition(1e-5)`, SwiftUI's own
value (measured) — nothing, in whole cells.

A factor above 1 asks for the view to start larger than its slot. A cell grid
cannot draw that: the reveal is clamped at the whole view, so the transition
draws the view whole from the first frame. `opacity` above 1 is clamped the
same way in SwiftUI itself.

TUIkit's own spelling, `AnyTransition.scale(anchor:)`, was not SwiftUI's and is
gone; `scale(scale: 0, anchor:)` is the same transition.

**The fuller version** would draw an oversized start by cropping the view to
its middle and widening the crop as it settles — a zoom-out rather than a
grow. Nothing in TUIkit crops from the middle today; half a day, and I would
wait for someone to ask.

### B-W12-4 `tracksVelocity` is recorded, and no velocity is carried; `isContinuous` is set by TUIkit's own continuous controls

*`Transaction.tracksVelocity`, `Transaction.isContinuous`*

**`tracksVelocity`.** SwiftUI accumulates the velocity of values changed under
such a transaction, so a later animation can start moving at that speed.
TUIkit's animations are closed-form functions of elapsed time that start at
rest — a spring retargeted mid-flight already restarts from where its picture
is, without its speed — so there is nothing to track, and the flag is a value
the transaction carries for whoever reads it. This is the one place the
"retargets at rest" deviation of every TUIkit spring shows up as a property;
the Wave 17 review (W6) asked for it to be documented in one place rather than
used to refuse spellings, and `Animation.interpolatingSpring` will point here
too.

**`isContinuous`.** SwiftUI sets it when "a continuous action created the
transaction" — dragging a slider, holding a stepper. TUIkit now sets it on the
writes its own controls make that way: a press and drag on a `Slider`'s track,
and the repeats of a held arrow (`Slider`, `Stepper`) or a repeating
`Button` (the first action of the press is a click, and is not continuous).
A key the terminal repeats arrives as separate presses with nothing to say
they are one hold, so a held arrow KEY is not continuous. Setting the flag
makes the write an explicit transaction, which — like any `withTransaction` —
takes over from an animated change made earlier in the same frame.

**The fuller version** of `tracksVelocity` is O3's: velocity-preserving
retargeting needs integrated animations, the `CustomAnimation` question.

### B-W12-5 When a completion fires: the pass that shows the change decides, and a spring logically completes at its pace

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

Two transactions in one frame render under the last one (the rule TUIkit
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

### B-W12-6 `UnitCurve` follows its documentation where SwiftUI's measured answers do not

*`UnitCurve` (`value(at:)`, `velocity(at:)`, `inverse`, `bezier(startControlPoint:endControlPoint:)`,
the eight named curves), `Animation.timingCurve(_:duration:)`*

The Bézier curves share the solver an `Animation`'s timing curve uses (the
Wave 17 review asked for one formula, not two), and match SwiftUI's values and
velocities to the sixth place (measured, `w12/probe/p3.swift`). Two readings
differ from what SwiftUI answers, both in the documentation's favour:

- **Out-of-range input is clamped**, as `value(at:)` and `velocity(at:)`
  document. SwiftUI clamps its Bézier curves, but not `.linear` (1.5 gives
  1.5) or the circular ones (1.5 gives NaN, -0.5 a mirrored value).
- **`circularEaseInOut.inverse` is the curve with x and y swapped**, as
  `inverse` documents: level in the middle, steep at the ends. SwiftUI
  answers `circularEaseInOut` itself, whose values are not an inverse at all.

Where a curve is vertical — `circularEaseIn` at its end, the circular in-out
at its middle — the velocity is infinite, as in SwiftUI. Where a Bézier's
control point sits on its end point, the tangent vanishes and the velocity is
the limit the curve approaches (SwiftUI's answers there, 0 and 1, come from
dividing two rounding errors).

A circular curve is a new case of the animation curve, so
`Animation.timingCurve(.circularEaseIn, duration:)` moves along the circle;
a Bézier or `.linear` builds the animation `timingCurve(_:_:_:_:duration:)` and
`linear(duration:)` already build, and compares equal to it.

### B-W12-7 `Spring` is SwiftUI's numbers, two quirks kept and one not; a spring animation keeps no velocity across a retarget

*`Spring` (its four initialisers, `duration`, `bounce`, `response`,
`dampingRatio`, `mass`, `stiffness`, `damping`, `settlingDuration`, `value`,
`velocity`, `force`, `update`, `settlingDuration(…)`, `.smooth`/`.snappy`/
`.bouncy` and their tunable forms), `Animation.spring(_:blendDuration:)`,
`spring(duration:bounce:blendDuration:)`, `spring(response:dampingFraction:blendDuration:)`,
`interactiveSpring` (all three), `interpolatingSpring` (all four)*

The Wave 17 review (W6) found the refusal of all of these to be a judgement,
not a limit: TUIkit already drew springs in closed form. `Spring` is that
closed form made public — one implementation (`SpringMotion`) behind both the
type's arithmetic and the curve a spring animation is drawn with — and every
number was checked against SwiftUI's `Spring` on a probe
(`w12/probe/p4.swift`, `p5.swift`): values, velocities with and without a
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
more than the derivative of its own `value(…)` (1 at rest at t = 0). TUIkit
answers the derivative.

**Bounce at or below −1** is NaN in SwiftUI; here it stops at −0.999, a spring
too sluggish to visibly arrive, rather than a NaN on its way to a cell.

**Retargeting.** SwiftUI's `spring` hands its velocity to the next spring on
the same value, blending the durations over `blendDuration`; its
`interpolatingSpring` adds overlapping animations so velocity is preserved.
TUIkit's animations are functions of elapsed time from a start at rest: a
change that retargets a running spring starts the new one from where the
picture is, without the speed it had. So `blendDuration` has nothing to blend,
and `interpolatingSpring`'s `initialVelocity` is honoured for the change it
is given to — it moves the start of the curve and lengthens the settling the
loop waits for — but not inherited by the next. This is the deviation every
TUIkit spring already had (B-W12-4 records `tracksVelocity` against it); the
`interactiveSpring` presets are, accordingly, the quick springs their numbers
describe.

**The fuller version** is velocity-preserving retargeting: store the
velocity at retarget and start the next closed form with it
(`SpringMotion` already takes one). For springs alone that is a day — the
store records where the picture is; it would also record how fast — but a
curve retargeting into a spring, or a spring into a curve, has no velocity
model, which is O3's question.
