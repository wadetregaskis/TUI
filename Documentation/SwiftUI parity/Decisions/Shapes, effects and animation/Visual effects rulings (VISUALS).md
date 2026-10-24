# Visual effects rulings: decisions from lane VISUALS

*Lane VISUALS, 2026-10-24, building the owner's rulings of 2026-10-23 on six
visual questions in `Documentation/Open owner decisions.md`: A34 (option 2),
B61 (2, landing if the A/B is within a few percent), B95 (2), O5-FROSTED (b),
P5 (c) and WL-Q3 (b, measuring first). Each section says what shipped, what
was measured, and any judgement call the ruling did not settle.*

## A34. `BlurReplaceTransition` is its scale and a fade

*`BlurReplaceTransition` (`Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`; ruling: option 2.*

**What SwiftUI does** (measured on macOS 15.8, macOS 26.2 SDK,
[`Tools/SwiftUIProbes/Transitions/tr4.swift`](<../../../../Tools/SwiftUIProbes/Transitions/tr4.swift>),
a 200×100 view under a 2 s linear animation): besides the blur, the view
scales about its centre between **0.9** and its full size and fades linearly
between 0 and 1. `.downUp` arrives from 180×90 and leaves to it; `.upUp`
arrives from 180×90 and leaves to 220×110. `properties.hasMotion` is `true`
(`Animation curves, springs and keyframes/p1.swift`).

**What TUIkit draws.** The blur is drawn as the fade: at a cell's resolution a
blurred view reads as a faded one, and the opacity compositor already
dissolves its colours toward what is behind it. The scale is the `.scale`
reveal (B54) from 0.9 of the view at its centre. So `.downUp` erases to
`.scale(scale: 0.9, anchor: .center).combined(with: .opacity)` both ways, and
`.upUp` to that on insertion and `.opacity` alone on removal: a reveal cannot
draw a view larger than its slot. Under reduce motion it is a fade, as every
transition with motion is.

**Option 3**, a cell blur, was not built. The follow-up answer in the owner
decisions file prices it and ties it to O5-FROSTED's neighbour sampling.

## B61. Each text and image dissolves its own change

*`View.contentTransition(_:)`, `EnvironmentValues.contentTransition`; ruling:
option 2, landing if the A/B on text-heavy scenarios is within a few percent.*

**Shipped on the lane, waiting on the A/B.** The modifier only sets
`\.contentTransition`. Its setter also writes a package `Bool`,
`contentDissolves`, which TUIkitFoundation's leaves can read without seeing
TUIkitEffects' type. `Text.renderToBuffer` and the raster image host end in
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
