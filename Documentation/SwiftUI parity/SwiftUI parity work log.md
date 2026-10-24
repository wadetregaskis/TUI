# SwiftUI parity work log

*A running record of what I am doing, what I decided and why, and what I would
like a second opinion on. Newest at the bottom. Questions are marked **Q** —
none of them block me; each says what I did in the meantime.*

## 2026-08-19 — animation

### Done

| | |
|---|---|
| `withAnimation`, `Animation`, `Animatable`, `VectorArithmetic`, `Transaction` | shipped |
| `.animation(_:value:)`, `.transaction(_:)`, `Binding.animation(_:)` | shipped |
| `Animatable`: `.opacity`, `.offset`, `.padding`, fixed `.frame`, `EdgeInsets`, `UnitPoint`, `CellSize`, `CellRect`, any app `ViewModifier` | shipped |
| Colour fades on `.foregroundStyle` / `.background` / `.border` | shipped |
| `.transition(_:)` with the seven built-in effects | shipped |
| `repeatForever` on `.opacity` served by pre-rendered runs (no render passes) | shipped |
| Example page, Stress scenario, DocC article, parity re-baseline | shipped |

### Decisions worth a second look

**1. Colours do not go through `Animatable`.** A semantic `Color` is not
components until it meets a palette, and `animatableData` has no palette. So
the painting modifiers ask a helper at render time instead. SwiftUI solves the
same problem the same way (an internal resolved-colour type). App-facing API is
unchanged.

**Q1.** `Text.foregroundStyle(_:) -> Text` still does not fade — that overload
carries the colour in the view *value*, so no modifier is left to ask. Making it
fade means a store lookup per `Text`, which is the most-rendered view there is.
*Meanwhile:* documented on the modifier and pinned by a test. I think the cost
is not worth it, but you may disagree.

**2. Removal transitions need a surviving slot.** An `if` inside a stack had
none: a stack asks children to flatten and a `nil` optional flattened to *no
children*. Such a view animated in and jumped out.

**Q2 — answered, and done (2026-08-20).** You called the jump wrong, and it was.
The fix is narrower than I had feared: a `nil` keeps a slot only while the store
confirms something is still leaving from that exact address (parent identity +
the wrapped view's type), so a `nil` in an app that animates nothing costs one
`isEmpty` check and contributes no child — identities and stack spacing under
every existing `if` are untouched. The slot borrows `Wrapped`'s identity, which
is the address the present view rendered at, so it finds the picture that view
left behind.

**3. `PhaseAnimator` / `KeyframeAnimator` are recorded as not-implemented**,
with the reason: pre-rendering a subtree once per phase runs its render *side
effects* once per phase too. That is the same thing that killed the general
diffing engine in `Animating your own view efficiently.md` §5.3.

### Performance

Everything is A/B'd against the commit before the animation work
(`ab_bench.py`, 41 reps, paired, order randomised).

| stage | `table` | `deep` | `kitchensink` | `megalist` |
|---|---|---|---|---|
| first cut | +0.8% | +1.0% | +1.0% | ~0 |
| after three rounds | +0.7% | +0.6% | +0.7% | ~0 |
| after `.padding`/`.frame` became animatable | +1.4% | **+14.0%** | +1.8% | +1.0% |
| after the generic witness | +0.7% | +7.6% | +1.0% | +1.4% |
| after the store stopped rebuilding its tables | ~0 | **+7.5%** | ~0 | ~0 |

The +14% is the lesson of the batch: `view as? any Animatable` **boxes**, and
with layout modifiers animatable that is a heap allocation per layout node per
walk — on a tree whose whole shape is nested layout, measured O(depth²) times.
Replaced with a static `View._animated` witness where `Self` is concrete, so
nothing is boxed and nothing is cast back. A second round stopped
`endRenderPass` rebuilding a whole dictionary per pass and stopped
`beginRenderPass` sweeping every record to clear a flag almost none of them set.

`table`, `kitchensink` and `megalist` — the three that look like real app
shapes — are now **indistinguishable** from before any of this existed.

**Q3.** `deep` stays at **+7.5%**, and I have stopped chasing it. It is the
deliberately pathological scenario: nested layout modifiers, re-measured once
per enclosing level (O(depth²)), so every animatable `.padding` / `.frame` pays
a store probe that many times. The only remaining fix is a per-frame "could
anything animate at all?" gate that skips the probe — and it is not sound as
designed, because a record has to exist BEFORE a change in order to know what
the value was before it. Every gate I tried either drops the first animated
change or is open permanently once an app animates anything once.
*Meanwhile:* accepted and recorded. My read is that a 7.5% on the deep-nesting
stress case is a fair price for `.padding`/`.frame` animating at all, given the
realistic shapes measure clean — but it is a judgement call and it is yours.

**Q3, measured again (2026-10-24, owner ruling WL-Q3 (b): measure first,
then A/B).** Counted, not timed, with temporary counters in
`animatedValue(of:owner:context:isMeasuring:)` over five warm frames of the
`deep` tree through `RenderLoopHarness` (counters removed after). Every
probe a frame makes is a padding's — `deep` writes no `.frame`; its
`.padding(1)` and its `.border()`'s inner padding are the two owners:

| depth | probes a frame | measure walk | render walk | answered by the settled fast path |
|---|---|---|---|---|
| 10 | 160 | 140 | 20 | 160 |
| 20 | 506 | 466 | 40 | 506 |
| 40 (the scenario) | 1,786 | 1,706 | 80 | 1,786 |

So the render walk asks twice per level, and the measure walks ask the rest,
growing as about depth^1.8 (O(depth²), as the entry says). Every probe ends at
`AnimationStore.isSettled`: one key built (the identity and the owner), one
dictionary lookup, and two `Any`-to-`EdgeInsets.AnimatableData` casts of the
record's target and origin; no environment read, nothing allocated, no
volatile read. What that costs in time is the A/B's to say: main against the
branch `wlq3-animatable-layout-off` (533b7b0ab, from main b8acc3898), where
`.padding` and `.frame` keep their conformances but answer the walks as types
that are not animatable — `Stress --bench --scenario deep` on the quiet
machine, and `kitchensink` and `table` as controls. Close the item if `deep` is
within a few percent, as the ruling says.

**Q3, the A/B (2026-10-24).** The owner's, release, warm, 15 reps:

    deep        −28.5% [−29.1, −28.1] faster without animatable padding/frame  (≈ +40% for it)
    kitchensink  +0.0% indistinguishable
    table        −1.3% [−2.0, −1.0] faster

Not within a few percent, so the item stays open. The cost did not grow
fivefold since August: the August numbers above were taken on a bench that
called `renderToBuffer` in a loop with no per-pass lifecycle, so the measure
memo was never emptied and served each frame's measures from the frames
before. Counted on the August commit (da01c6842) with temporary counters: 84
memo hits and 1 miss a frame, and 80 store probes a frame, all on the render
walk; no measure walk reached a padding. Since 87f260029 (2026-09-05) the
bench runs the app's lifecycle (it moved `deep` from 2,186 to 10,547 µs a
frame), and now: 9,366 measure lookups a frame at 9.2% hits, and 1,800 probes,
1,720 of them measuring. Each probe that finds its record compares the key's
identity node by node to the root, because a record keeps the nodes of the
frame that first saw it and each frame builds new ones: seven nodes per
nesting level, 187 on average; identity comparisons visit about 363,000 nodes
a frame, nearly all in these lookups, a retain and a release each. In the profile of main's release build that is
`animatedValue` 25.8% inclusive, `Dictionary.index(forKey:)` 22.5%,
`IdentityNode.structurallyEqual` 21.3%. Details in the VISUALS decisions file.


## 2026-08-19 — parity, continued

Working down the gap list, picking the ones a character grid can honour
*exactly* rather than approximately.

### Done

- **Seven colour effects**: `.brightness`, `.contrast`, `.saturation`,
  `.grayscale`, `.hueRotation`, `.colorInvert`, `.colorMultiply`. These sound
  graphical and are not — each is a function from colour to colour, and a
  terminal names its colours explicitly in escapes it has already emitted.
  `.opacity`'s SGR walk turned out to be the general case and became one
  (`SGRColorRewrite`). All animatable, all size-neutral.
- **`Angle`**, which comes with `.hueRotation` and is the one place a geometric
  type earns its keep here: a hue *is* an angle, so this rotates colours exactly
  while nothing about the cells moves.
- **`.position(x:y:)` / `.position(_:)`** — the absolute counterpart to
  `.offset`, including SwiftUI's rule that a positioned view fills the space it
  is offered.
- **`Binding.animation(_:)`**.

A/B after the colour effects: `table`, `megalist`, `kitchensink`
indistinguishable. (`deep` unchanged at its known +7.7% — see Q3.)

### Pulled before shipping

**Q4.** `.background(alignment:content:)` — I wrote it and then took it out,
because "draw this *behind* that" has no honest meaning when every cell is
opaque. SwiftUI's background shows through wherever the content is transparent;
here the content's spaces are cells like any other, so a background under
`Text("Total")` is simply covered by the word. The options are (a) treat a
space in the content as transparent, which is a real and defensible rule but a
new one, (b) ship it as "visible only where the content is shorter", which
would be surprising, or (c) leave it out. I left it out.
*Meanwhile:* `.overlay(alignment:content:)` already exists and is unambiguous,
and `.background(_ color:)` covers the common case.

*Reversed, 2026-10-03.* The premise went twelve days later, with 590e71a4f
("A glyph and the colour behind it are two statements"): a cell that names no
background now keeps the field under it. That gives "behind" an exact meaning
— the content composited over the background — and it is what SwiftUI's
picture comes to in a grid: every cell the content does not colour shows the
background's colour, translucent ones included, and a background *glyph* is
covered under any cell the content draws, which is `ZStack`'s rule already. So
`.background(alignment:content:)` ships, on the composite `.overlay` uses with
the layers swapped. None of (a)–(c) was needed.

### Not attempted, and why

- **`deleteDisabled(_:)` / `moveDisabled(_:)`** — these belong on the ROWS of a
  `ForEach`, read by the enclosing `List`'s delete/reorder machinery. TUIkit has
  `onDelete` / `onMove` on `ForEach` itself, so wiring a per-row veto means
  threading an environment value through the reorder host. Worth doing; wants
  more room than the end of a batch.
- **`labelsHidden()` / `labelsVisibility(_:)`** — cheap to add, but only
  meaningful once `Toggle`, `Slider`, `Stepper`, `Picker` and `DatePicker` all
  honour it. Adding the modifier without that is the "silently does nothing"
  shape I have been avoiding all session.
