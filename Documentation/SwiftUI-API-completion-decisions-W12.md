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
