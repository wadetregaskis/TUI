# Pixel effects: transforms, masks, drawingGroup, blend modes and meshes

*Which of SwiftUI's pixel effects a cell grid can honour: the six view
transforms (declined), masks, `drawingGroup`, the geometric visual effects,
blend modes, the faint content levels at low colour depths, and meshes. Ids:
A27, A39, W5, A-EFFECTS-1, B95.*

## In short

The six view transforms are declined, and the geometric visual effects follow
them (A39). `mask(alignment:_:)` keeps a view's cells where another draws;
`drawingGroup` composites in linear light where asked. Blend modes are
honoured per cell, as the colour effects are (W5). A mesh is one sample a
cell, or a picture where the terminal takes one; a ramp's blank cells are two
samples where Block Elements fill the line (B95). At 16 colours the faint
content levels vanish (A-EFFECTS-1, never answered).

## How it unfolded

1. **Wave 16, A27.** The owner took the recommended set (2), built on
   2026-10-26: transforms declined, mask at cell coverage, `drawingGroup` with
   linear-light blending.
2. **2026-10-19, W5:** blend modes, built after the review showed they could be
   honoured per cell.
3. **2026-10-23 to 24, B95:** option 2 (built by VISUALS).

## The record

### A27. Pixel effects: transforms, masks and `drawingGroup` (Wave 16)

*`View.scaleEffect(_:anchor:)`, `View.scaleEffect(x:y:anchor:)`,
`View.rotationEffect(_:anchor:)`, `View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`View.projectionEffect(_:)`, `View.transformEffect(_:)`, `View.mask(alignment:_:)`,
`View.drawingGroup(opaque:colorMode:)`; and, waiting on refusal-review items
already, `View.clipShape(_:style:)` and `View.contentShape(_:eoFill:)`/`(_:_:eoFill:)`
(O0), `View.shadow(color:radius:x:y:)` (O6)*

Wave 16 shipped what a cell grid keeps honestly: `clipped(antialiased:)` (the
cut `ScrollView` and `List` already made) and `compositingGroup()` (a guarantee
the compositor keeps). `View.shadow(color:radius:x:y:)` followed with O6 (2026-10-18). Blur, luminance to alpha and the background
extension effect joined the map's per-pixel shading family; blend modes did too, until W5
shipped them per cell (2026-10-19). The rest is yours.

**Transforms.** A glyph cannot be scaled or turned, and an affine transform
of a cell grid is not a cell grid.

1. **Decline all six.** `scaleEffect(isPressed ? 0.95 : 1)` in ported code then
   fails to compile, and the developer removes it. Free.
2. **`scaleEffect` as the `.scale` transition draws it**, a reveal from the
   anchor, with `rotationEffect` and the rest declined. A scale of 0.95 then
   draws as 1 (nothing to reveal), which is the silent no-op rule 2 forbids, so
   this only makes sense with a threshold. Half a day.
3. **Raster content only:** a scaled or quarter-turned `Image` is resampled.
   The receiver is any view, so the type system cannot keep this to images.
   Text would draw unchanged. That is a no-op again. A day.

**`mask(alignment:_:)`.** Masking by another view's alpha can be honoured at
cell granularity: a cell where the mask draws (a glyph or a background) keeps
the content, at the mask colour's alpha through an opacity region, and the
rest is cleared to what is behind. Choosing that coverage rule is the decision
("a space with no background masks out" is the one that would surprise). Half
a day.

**`drawingGroup(opaque:colorMode:)`.** In SwiftUI it flattens the view into an
offscreen image before display. Here every view already composites as one
picture, as for `compositingGroup()`. `opaque` is a promise by the caller.
`colorMode: .linear` asks for linear-light blending, which TUI's encoded-sRGB
blend does not do.

1. **Ship it as `compositingGroup()`**, honouring `.nonLinear`, the default,
   and documenting `.linear` and `.extendedLinear` as blended non-linearly.
2. **Decline it.**

**Recommendation:** transforms (1); mask, the cell-coverage rule; drawingGroup
(1), since nearly every use is the argument-free performance hint.

**Ruled 2026-10-26: option 2.** The six transforms are declined (the API
parity map's family, with A39's spellings); `mask(alignment:_:)` ships at
cell coverage, a shape mask by `clipShape`'s half-cell rule; `drawingGroup`
ships as `compositingGroup()`, with linear-light blending inside it for
`.linear` and `.extendedLinear`.

**`mask` shipped 2026-10-26** (`MaskModifier.swift`), with one rule beyond
coverage: a glyph's alpha is its letter's shape, so where the mask draws a
glyph with no field over a cell the view only fills, the cell is the mask's
glyph inked in the view's colour. Without it `gradient.mask { Text(…) }`,
SwiftUI's gradient-text idiom, drew solid blocks where the letters are. Where
the view draws a glyph of its own it keeps it.

**`drawingGroup` shipped 2026-10-26** (`DrawingGroupModifier.swift`, with
`ColorRenderingMode`): the blends spent at a composite inside a linear group
mix in linear light, and what leaves the group unspent mixes where it lands,
as SwiftUI composites the group's image into the window (`Opacity as
composition.md` §113).

**You asked (2026-10-04)** whether linear and extended-linear blending could be
supported. Yes (answer of 2026-10-05): blending happens in one place, in
encoded sRGB by design today, and linear blending is decode, blend and
re-encode through lookup tables, which is cheap. Extended-linear is the same on
an SDR terminal, clamped at the end. Not yet decided.

*Wave 8a's remaining entries (C10; A30, A31 and B44–B47 shipped 2026-10-06, A29 on 2026-10-07): SwiftUI's behaviour was measured on macOS 15.8, built against the macOS 26.2 SDK, with an offscreen `NSHostingView`; the probes are in `Tools/SwiftUIProbes/Table questions, compile and runtime (wave 8a)/`.*

*Wave 11a's entries (A32–A33, B48–B51): every string was measured on SwiftUI, macOS 15, by rendering with `ImageRenderer` and reading the picture back with Vision; the probes are in `Tools/SwiftUIProbes/Live text formats read back (wave 11a)/`. A pass on macOS 26 is owed.*

*Wave 12's entries (A34–A40, B52–B61; its `Transaction.dismissBehavior` joined A22): SwiftUI's behaviour is from its doc comments unless an entry says it was measured; measurements are from probes built against the macOS 26.2 SDK and run on macOS 15, kept in [`Tools/SwiftUIProbes/Animation curves, springs and keyframes`](<../../../Tools/SwiftUIProbes/Animation curves, springs and keyframes>).*

### A39. The geometric visual effects wait on Wave 16 (A27)

*`VisualEffect.rotationEffect(_:anchor:)`,
`VisualEffect.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`VisualEffect.scaleEffect(_:anchor:)`, `VisualEffect.scaleEffect(x:y:anchor:)`,
`VisualEffect.transformEffect(_:)`*

The `View` modifiers of the same names are Wave 16's (sub-cell geometry, an
owner decision: A27, declined on 2026-10-26, and these with them). The
visual-effect spellings are the same requests made from a geometry proxy, and
are answered with them; `VisualEffect` itself and the
effects with a cell reading are this wave's.

### What shipped

- **W5, blend modes.** `BlendMode`, `View.blendMode(_:)`, `VisualEffect.blendMode(_:)`
  and `ShapeStyle.blendMode(_:)`, composited cell by cell as `.opacity` is,
  against macOS's arithmetic, measured first (`Tools/SwiftUIProbes/Blend modes`;
  `Opacity as composition.md` §110).
- **B-D3M-3.** A tiled image repeats at its natural size, and cap insets are
  points, where the terminal's cell size in points is known.
- **B-D3M-4.** A PDF is read again on Apple platforms, through Core Graphics, and
  the `CGColor` and `CGImage` bridges are TUI's own.
- **B22, the look owed.** The faint content levels were rendered at 16 and 256
  colours over every shipped palette; the result is in B22, and the levels
  that vanish are A-EFFECTS-1.

### A-EFFECTS-1. The faint content levels vanish at 16 colours, and the faintest at 256

*`HierarchicalShapeStyle` `.secondary` … `.quinary` under a `foregroundStyle`
(decisions B22)*

Under a `foregroundStyle`, `.secondary` to `.quinary` are that style at 0.5,
0.26, 0.1 and 0.05, composited at the cell. Rendered over each shipped
palette's page with the colour depth forced, and the ink read back out of the
emitted SGR (`FaintLevelsAuditTests`, 2026-10-19):

- **16 colours, all sixteen palettes:** `.secondary` is drawn in exactly
  `.primary`'s colour, and `.tertiary`, `.quaternary` and `.quinary` in the
  page's own colour — invisible. The nearest of sixteen colours to a faint ink
  is the page.
- **256 colours:** most levels stay apart, but `.quinary` is the page on Green,
  Red, Violet, Ocean and Solid Colors, and `.quaternary` too on Grass,
  Homebrew and Novel (eleven cells in all). Several neighbours collapse into
  one colour (`.tertiary` and `.quaternary` on Green, Red, Blue and Ocean).

The rendered contrast floor does not reach these: it floors a control's label
on its fill, not content text.

Options:

1. **Leave them.** The arithmetic is honest, and at 16 colours there is no
   colour between the ink and the page. *Price:* text an app styled
   `.tertiary` or fainter is invisible on a 16-colour terminal, and the
   faintest is on some 256-colour palettes.
2. **Floor the levels at the depth.** A level whose quantised ink is the
   page's steps toward the primary to the nearest colour that is not, at 256
   colours (a cube or grey entry); at 16, `.tertiary` and below take the
   primary's colour. *Price:* a small check per faint glyph at those depths;
   at 16 colours every level below the first is one colour, so the ordering is
   lost but nothing vanishes.
3. **At 16 colours, draw the faint levels dim (SGR 2) in the primary's
   colour**, and floor them at 256 as in 2. Every terminal TUI supports
   draws SGR 2 as a fainter ink, and TUI already uses it for a faint row
   (`Opacity as composition.md` §102). *Price:* as 2, and `.secondary` becomes
   distinct from `.primary` at 16 colours too, which it is not today.

**Recommendation:** 3. It keeps the levels visible and ordered as far as 16
colours can, with the attribute terminals already provide for exactly this,
and changes nothing at 24-bit colour.

### B95. A mesh is one sample a cell on a glyph terminal, and a picture where the terminal takes one

*`MeshGradient` (its five initialisers, `width`, `height`, `locations`,
`colors`, `background`, `smoothsColors`, `colorSpace`, `resolve(in:)`, `Body`,
`Resolved`), `MeshGradient.BezierPoint` (its initialiser and five points),
`MeshGradient.Locations` (`.points`, `.bezierPoints`),
`MeshGradient.Colors` (`.colors`, `.resolvedColors`); `Paint.mesh` and
`MeshPaint`, TUI's own*

**Shipped:** all of SwiftUI's surface, a style and a view. Each cell takes
the mesh's colour at the cell's centre; an opaque mesh used as a view, or
behind blank cells, is a picture on a graphics terminal; inside
`withAnimation` its vertices slide and its colours fade. Measured on macOS
15.8, and pinned at SwiftUI's own pixels in `MeshGradientTests`:

- **A patch is a Coons patch.** The interior control points fitted from
  SwiftUI's picture match PDF's type 6 formula to the probe's noise.
- **An implied control point** (the `points:` form) lies a third of the way to
  its neighbour, along the line bisecting the vertex's two edges in that
  direction; an edge vertex aims straight at its one neighbour. Residual on
  four warped meshes: 0.7–0.9 px on a 201 px picture, against 2–4 px for
  straight thirds or Catmull–Rom tangents.
- **`smoothsColors`** is a bicubic Hermite patch per channel, with no twist,
  whose slope at a vertex is half the difference of its neighbours — zero at
  the mesh's edges (not one-sided), zero at a peak or a trough, and capped at
  three times the smaller difference. 1 level in 255 against SwiftUI, which is
  its own tessellation; bilinear blending matches to the byte.
- **`.perceptual`** makes those slope decisions per channel of OKLab's
  cube-root cone space, the stage before OKLab's last matrix: 1.4 levels
  against SwiftUI, where deciding them in OKLab itself missed by 12. (For a
  bilinear blend the two spaces give the same answer.)
- **Translucent colours blend premultiplied**; `background` fills what no
  patch covers (`.clear` by default); a mesh with fewer than two vertices in a
  direction, or a point count other than `width × height`, draws its
  background alone; a missing colour is `.clear`.
- **Inside `withAnimation`** SwiftUI moved a mesh's column at even steps and
  stepped its colours exactly as a `LinearGradient`'s stops beside it.

Where it differs, or rests on less than a measurement:

- **One sample a cell, or two.** A cell is the mesh at its centre, so a smooth
  mesh is a staircase on a glyph terminal; the picture path removes the
  staircase where the terminal draws pictures. Since 2026-10-24 (the fuller
  version below) a blank cell is two samples where the terminal's Block
  Elements fill the line. This is the same rule every gradient follows.
- **Exact evaluation, not SwiftUI's tessellation.** TUI evaluates the
  Hermite patch at each sample; SwiftUI interpolates linearly between the
  vertices of its tessellation. The two differ by a level or two where a colour
  curves.
- **The slope cap is spelled as a box, not a circle.** "At most three times the
  smaller difference" and Fritsch–Carlson's α² + β² ≤ 9 both fit every probe:
  with Catmull–Rom slopes they part only once one difference is about five
  times the other, and then by under 2 % of the slope. Telling them apart
  needs one more probe aimed at that band, an hour; the colour it could move is
  under a level.
- **A folded mesh draws its patches in reading order**, a later one over an
  earlier. SwiftUI's order where patches overlap was not measured.
- **Whether a mesh is opaque throughout is decided conservatively.** A mesh
  whose outline lies on its box's edges covers the box, and is opaque if its
  colours are; one that covers the box some other way (points past its edges)
  is treated as letting a `.clear` background through. It draws the same,
  through the translucency path, which costs more and leaves an `.opacity`
  inside it carried up rather than spent against the mesh.
- **A colour with no RGB** — `.default`, an unreported terminal slot — cannot
  be blended: a patch with one takes whichever corner weighs most at the point,
  whole. This is `Color.lerp`'s rule for a gradient stop; SwiftUI has no such
  colour.
- **At 256 colours each cell is quantised on its own.** A ramp's quantiser
  repairs monotonicity along the ramp; a mesh has no order to repair along.

**The cost**, debug build, one mesh over 80 × 24 cells: 0.9 ms for a grid
mesh (each cell finds its patch by two divisions) and 3.4 ms for a warped one
(each patch split by de Casteljau until a piece is within a twentieth of a
cell of its corners' bilinear map). A picture of the same box at 640 × 408
pixels fills in 104 ms and 170 ms, once per picture: the store asks for the
bytes only when the terminal does not already hold them, which is new for
every gradient picture (before, each render of a ramp behind blank cells
filled its whole picture first). A `Table`'s ramp runs over every row of its
data, so a mesh there is worked out a band of eight rows at a time, only for
the rows asked about.

**Two samples a cell where Block Elements fill the line** (owner ruling of
2026-10-23, option 2; lane VISUALS, 2026-10-24). A ramp or mesh that changes
down a column draws each blank cell it fills by the rasterized shapes' rule
(`ShapeHalfBlocks.cell(upper:lower:)`): `▄` in the colour a quarter of the
way up from the cell's bottom over the colour a quarter of the way down from
its top, or a space where the two agree. That is a gradient view, a
`.background(gradient)` behind the content's bare cells (a space with nothing
in force), and a rectangle-family shape's whole cells (its corners keep their
quadrant in one sample), so a gradient `Rectangle`, `RoundedRectangle` and
`Circle` agree. Apple Terminal (`blockElementsFillTheLine` false) keeps one
sample, as do a cell with a glyph, a translucent or blended ramp, a
horizontal ramp (whose halves agree) and a terminal with no colour; a
terminal that takes pictures still draws an opaque ramp behind blank cells
as one. Copying such a region gives `▄` rather than spaces. The `▀`/`▌`
choice, quadrants and diagonals were not built (the ruling's follow-up
answer). Where a layer is drawn under content — `.background { gradient }`,
a `ZStack` — a cell the content draws, a space included, covers the `▄` and
shows the top half's colour. See the lane file `Shapes, effects and
animation/Visual effects rulings (VISUALS).md`.

### B95. A ramp's blank cells are two samples where Block Elements fill the line

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
