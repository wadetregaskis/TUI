# Visual effects rulings: decisions from lane VISUALS

*Lane VISUALS, 2026-10-24, building the owner's rulings of 2026-10-23 on six
visual questions in `Documentation/Open owner decisions.md`: A34 (option 2),
B61 (2, landing if the A/B is within a few percent), B95 (2), O5-FROSTED (b),
or (c) if (b) costs significantly (shipped as (c)), P5 (c) and WL-Q3 (b,
measuring first). Each section says what shipped, what was measured, and any
judgement call the ruling did not settle.*

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

## B95. A ramp's blank cells are two samples where Block Elements fill the line

*Gradient views, `.background(gradient)`, rectangle-family gradient fills,
`MeshGradient`; ruling: option 2. The follow-up's ▌, quadrant and diagonal
glyphs were answered and not built.*

**Shipped.** One rule, the rasterized shapes' (`ShapeHalfBlocks.cell(upper:
lower:)`, shared by a prepared refactor), and one half-row sampler
(`RampSampler(halfRowsOf:…)`), now used by three paths:

- **A box-drawn fill** (`RoundedRectangle`, `Capsule`, an inset `Rectangle`,
  the container shapes): a cell the shape covers whole is its two halves; a
  corner keeps its quadrant glyph in one sample, since a quadrant has one ink.
- **A `.background` ramp** (which is also how `Rectangle().fill`, `Color`'s
  and the gradients' own view bodies draw): `GradientHalfRows` draws each
  bare cell of the content — a space with no SGR in force — as the two
  halves, and the content's other cells on the one sample they had. A row
  holding an escape that is not SGR (a hyperlink) keeps one sample whole.
  A content run is closed with a reset before half cells follow, so its
  styling cannot reach them.
- **A rasterized shape** already drew this way on every terminal.

**Where it applies:** a ramp that changes down a column (a horizontal ramp's
halves agree, so it is untouched and pays one flag test), opaque throughout,
with no blend mode, on a terminal with colour whose Block Elements fill the
line. Apple Terminal keeps one sample, as its button faces keep whole cells
(Terminal compatibility survey). A terminal that takes pictures still draws
an opaque ramp behind blank cells as a picture; the halves are what it draws
behind content.

**Judgement calls.** A translucent ramp keeps one sample: the halves' ink
would owe a claim per half, and the background's claims are field claims
only. A blended ramp keeps one, as it is never a picture either. Under a
layer — `.background { LinearGradient(…) }`, a `ZStack` — a cell the
content draws, a space included, covers the `▄` and shows the top half's
colour where it showed the centre's: a quarter of a row's shift in that
cell's sample. The fill under a fade inside an opaque ramp
(`resolvingOpacity`'s backdrop) is the one-sample row, as before.

**Cost.** Counted, not timed: a ramp that qualifies samples each blank cell
twice and spells each distinct pair of half entries once per fill (a
dictionary, as the background's one-sample escapes are an array); a row
with content is scanned once for bare cells (`String.bareCells(width:)`) and
cut at the runs. Bytes: a run of halves states a foreground and a
background where a run of one sample stated a background, and a vertical
linear ramp, which was one fill per row, is now one run of `▄` per row. A
ramp that does not qualify pays one `Bool` and a flag test per fill. For an
A/B if wanted: `gradients` (its geometry and mesh bands are gradient views)
and `app-shapes`.

## O5-FROSTED. A material frosts what is behind it

*`Material` (every thickness, `.bar`), `Glass`, `glassEffect(_:in:)`;
ruling: (b), watching performance, (c) if the cost is significant.*

**Shipped:** option (c). Under a material's translucent field, what is
behind loses its glyphs; its fields are tinted by the material as before,
each cell its own colour, nothing averaged. Glass is a material's surface,
and frosts too. The mechanics are `Opacity as composition.md` §111: a
`Paint.frosted` paint, a `frosts` flag on the painter's claim, carried to
the cell's alpha, and the cell behind blanked in the blend.

**Why (c), not (b).** (b) was built first: the glyphs dropped and each
cell the average of the effective colours of its 5 × 3 neighbourhood, a
glyph's ink counted at a constant share of its cell. The owner's A/B of it
(the frost commit against the one before, release Stress, warm, 15 reps):

| Scenario | Cost of (b) |
|---|---|
| `translucent` | +0.8%, indistinguishable |
| `translucent --variant material` | **+66.4%** [+62.5, +68.6] |
| `alpharamp`, `kitchensink` | indistinguishable |

Nothing is paid where no material is drawn, but +66% where one is is
significant, so by the ruling's own terms (c) ships. The averaging needed
a second parse of every row a material's neighbourhood touched, fifteen
colours summed per covered cell and the destination's rows re-spliced
before the blend; (c) needs none of that. The glyph is dropped inside the
blend that already reads both cells: one flag test per covered cell, no
extra parse and no neighbour sampled.

**Judgement calls.** A cell behind keeps the field it shows exactly as it
spells it (a reversed cell's, the terminal's own), its ink and attributes
dropped with the glyph. A material that does not appear active is opaque
and is not marked. A material over nothing but the page is its tint,
unchanged. **A/B scenarios** for the (c) build if wanted: the same four,
`translucent --variant material` the one that draws a material.

## P5. Reduce transparency, differentiate without colour and increase contrast are read as reduce motion is

*`EnvironmentValues.accessibilityReduceTransparency`,
`.accessibilityDifferentiateWithoutColor`, `.colorSchemeContrast` and their
underscored setters; ruling: (c), option (b) plus the host read.*

**Shipped.** The reduce-motion plumbing carries a set
(`AccessibilityPreferences`, a prepared refactor): the user's variables
(`TUIKIT_REDUCE_TRANSPARENCY=1`, `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR=1`,
`TUIKIT_INCREASE_CONTRAST=1`, beside `TUIKIT_REDUCE_MOTION=1`) and the
host's settings, read by `HostAccessibilityRefresher` at launch and when the
terminal regains the focus, counted only where `SessionLocality.isLocal()`
holds. On macOS the host is `com.apple.universalaccess`'s `reduceMotion`,
`reduceTransparency`, `differentiateWithoutColor` and `increaseContrast`
(the four names are in macOS 15.8's shared cache; the three new ones were
not toggled and read here). On GNOME, `org.gnome.desktop.a11y.interface
high-contrast` is increased contrast; GNOME has no setting for the other
two. The root writes all four. TUIkit honours reduce transparency: every
material, and glass, is opaque, as an inactive one is, and so unfrosted.

**Judgement calls.** The three are read-only, as SwiftUI's are, with
SwiftUI's own underscored setters (`_accessibilityReduceTransparency`,
`_accessibilityDifferentiateWithoutColor`, `_colorSchemeContrast`) to write
them: that is how `.environment` reaches them in SwiftUI. No `Scene`
modifier was added for them (the ruling's option (b) names variables and
`.environment`). TUIkit's drawing does not change for increased contrast
(the palettes keep their floors either way) or differentiate without colour
(its own cues wait on a design, as the entry recommends): both are reported
for the app's views. `\.accessibilityVoiceOverEnabled` stays refused.

**Cost:** three more environment writes at the root a frame, and, on
macOS, three more preference reads per host reading (launch, focus in); on
GNOME one more `gsettings` run per reading.
