# Visual effects rulings: decisions from lane VISUALS

*Lane VISUALS, 2026-10-24, building the owner's rulings of 2026-10-23 on six
visual questions in `Documentation/Open owner decisions.md`: A34 (option 2),
B61 (2, landing if the A/B is within a few percent), B95 (2), O5-FROSTED (b),
or (c) if (b) costs significantly (shipped as (c), then as (b) once the owner
had seen both), P5 (c) and WL-Q3 (b, measuring first). Each section says what shipped, what was measured, and any
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
ruling: (b), watching performance, (c) if the cost is significant; then,
2026-10-24, after seeing (a), (b) and (c) rendered: "Let's do the 'full
frost' approach. But also, it seems like it would be nice to be able to
control the degree of frosting."*

**Shipped:** option (b), the full frost. Under a material's translucent
field, what is behind loses its glyphs and each cell takes the average of
the effective colours of a box of cells around it (a glyph's ink counted at
a constant share of its cell), and the material's surface is composited over
that as before. Glass is a material's surface, and frosts too. The mechanics
are `Opacity as composition.md` §111: a `Paint.frosted` paint carrying its
box, a `frost` on the painter's claim, the averages made once per
resolution where the destination is known, and the cell behind replaced in
the blend.

**History.** (b) was built first and cost +66.4% on `translucent --variant
material` in the owner's A/B (release Stress, warm, 15 reps; `translucent`
+0.8%, `alpharamp` and `kitchensink` indistinguishable), so (c) shipped:
the glyphs dropped, the fields tinted as before, nothing averaged. The owner
then chose (b) on its look. This build is (b) made cheaper:

| Release Stress, `translucent --variant material`, Time Profiler | (c) | first (b) | this (b) |
|---|---|---|---|
| `resolvingOpacity`, inclusive | 42.1% | 63.2% | 51.9% |
| the frost's own pass | — | 18.4% (`frosted(under:…)`) | 6.9% (`frostFields`) |
| row parsing (`cells(in:)`) | 10.0% | 17.1% | 11.1% |
| splicing | 3.2% | 8.5% | 2.9% |
| frame, against (c), the rest held fixed | — | ≈ +57% (A/B: +66.4%) | ≈ +20% |

The first build frosted the destination as strings before the blend: a
second parse of every row, fifteen `Color`s summed per cell, the rows
re-spliced and parsed again by the blend. This one parses each row once
into a summed-area table of bytes (four lookups a channel per cell,
whatever the box) and hands the blend each cell's average on its alpha.
Of the ≈ +20% left, about two fifths is the averaging and the rest is
spelling a picture whose every cell is its own colour, which is what a
blur is. Sharing the frost's parse with the blend measured no better and
was not kept. An A/B is owed: `translucent --variant material` (the one
that draws a material), `translucent`, `alpharamp`, `kitchensink`.

**The degree follows the thickness.** SwiftUI's only control of a
material's blur is its thickness, a thicker one blurring more and letting
less through. Each step of thickness here reaches one more column either
side of a cell, and half as many rows as columns, rounded down, because a
cell is about twice as tall as it is wide:

| Material | Opacity | Box (columns × rows) |
|---|---|---|
| `.ultraThin` | 0.35 | 3 × 1 |
| `.thin` | 0.5 | 5 × 3 (the box the owner saw rendered) |
| `.regular` | 0.65 | 7 × 3 |
| `.thick`, `.bar` | 0.8 | 9 × 5 |
| `.ultraThick` | 0.92 | 11 × 5 |

Each box is about as tall as it is wide on screen (7 × 3 cells is 7 × 6
cell-widths) but the thinnest, which blurs along its row alone: a row above
and below would already be a box twice as tall as it is wide. `.bar` has been
drawn at a thick material's opacity since materials shipped (SwiftUI's
documentation says only that it matches system toolbars), so it takes
thick's box too: one thickness, one look. Glass takes the box of the material one step thinner than
the one whose surface it takes — thin's for `.regular`, ultra-thin's for
`.clear` — because SwiftUI's glass lenses what is behind it more than it
blurs it, and what shows through glass stays plainer than through a
material as see-through.

**The explicit control** the owner asked about is TUI-specific, so a
modifier (the CLAUDE.md rule): `.materialFrost(_:)`, an environment value,
`MaterialFrost` — `.automatic` (each thickness's box), `.none` ((c)'s look:
the glyphs dropped, the colours each their own; nothing averaged, the cheap
path), and `.radius(columns:rows:)`, one box for every thickness, in cells
either side of a cell. Named degrees were weighed and left out: a box in
cells says exactly what it does, and `.automatic` already names the five the
thicknesses give. It reaches materials and glass alike, and an opaque
material frosts nothing whatever it says.

**Judgement calls.** The average is of encoded sRGB bytes, as every TUIkit
blend is; past the end of a line a cell is the surface, and a wide glyph's
later columns are the glyph's. A box reaches only what is behind the
material where it is composited (in the Example's and Stress's one-row
`ZStack`s, that row alone). Two claims with different boxes over one cell:
the larger frosts it. A material that does not appear active is opaque and
is not marked. A material over nothing but the page is its tint, unchanged.

## P5. Reduce transparency, differentiate without colour and increase contrast are read as reduce motion is

*`EnvironmentValues.accessibilityReduceTransparency`,
`.accessibilityDifferentiateWithoutColor`, `.colorSchemeContrast` and their
underscored setters; ruling: (c), option (b) plus the host read.*

**Shipped.** The reduce-motion plumbing carries a set
(`AccessibilityPreferences`, a prepared refactor): the user's variables
(`TUIKIT_REDUCE_TRANSPARENCY=1`, `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR=1`,
`TUIKIT_INCREASE_CONTRAST=1`, beside `TUIKIT_REDUCE_MOTION=1`) and the
host's settings, read by `HostSettingsRefresher` at launch and when the
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

## WL-Q3. Animatable `.padding` and `.frame` on `deep`: measured, and the A/B built

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
