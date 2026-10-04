# Completing the SwiftUI API: Wave 17m decisions (mesh gradients)

*Wave 17m's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. Wave 17m acts on the
`MeshGradient` half of the refusal review's P11, which found the refusal wrong:
a mesh is a function from a position to a colour, as the four gradients are,
and a cell has a position. SwiftUI's behaviour was measured on macOS 15.8
(built against the macOS 26.2 SDK) by probes that render meshes through
`ImageRenderer` and read every pixel back — meshes painted with colours that
encode each pixel's place in the mesh, so the picture gives the patches' shape
directly — and one that hosts a mesh in a window and captures it mid-animation.
The probe sources and the fitting scripts are in the session notes
(`w17m/probe/`), not in the repository.*

Nothing here needs the owner: every symbol shipped. The one entry is the shape
of what shipped and what a fuller version would cost.

---

## B. Shipped the safe option

### B-W17m-1. A mesh is one sample a cell on a glyph terminal, and a picture where the terminal takes one

*`MeshGradient` (its five initialisers, `width`, `height`, `locations`,
`colors`, `background`, `smoothsColors`, `colorSpace`, `resolve(in:)`, `Body`,
`Resolved`), `MeshGradient.BezierPoint` (its initialiser and five points),
`MeshGradient.Locations` (`.points`, `.bezierPoints`),
`MeshGradient.Colors` (`.colors`, `.resolvedColors`); `Paint.mesh` and
`MeshPaint`, TUIkit's own*

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

- **One sample a cell.** A cell is the mesh at its centre, so a smooth mesh is
  a staircase on a glyph terminal; the picture path removes the staircase
  where the terminal draws pictures. This is the same rule every gradient
  follows.
- **Exact evaluation, not SwiftUI's tessellation.** TUIkit evaluates the
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

**The fuller version: two samples a cell on a glyph terminal.** A gradient
used as a view — any of the five, behind blank cells — could draw each cell as
an upper half block (`▀`) whose foreground is the sample a quarter of the way
down the cell and whose background the sample three quarters down, doubling
the vertical resolution where there is no picture. `Image` already draws this
way. About half a day with the self-check, and a look in Apple Terminal and
Warp, which take no pictures and are where it would show. It changes how every
gradient view looks on those terminals, and copying such a region yields `▀`
rather than spaces, which is why it is not done here.

---

## D. Deferred to other waves or lanes

- **An A/B of the `gradients` Stress scenario on a quiet machine.** The ramp
  sampler's mapping gained a case with a class payload, and its `ramp` became
  computed (a mesh's grows as cells are asked about). Every gradient goes
  through both; no machine in this lane was quiet enough to measure the
  difference, and `PaintRenderer.band` and `.background` each gained a bounds
  check per run as well. The scenario also draws two meshes now, at the top, so
  the A/B wants the scenario's own previous version run with the new band
  removed.
- **An Example page demo** of a mesh, with its strings in the seven languages.
- **A DocC build** from a clean clone: the new links are all to public
  symbols, and none was checked against the archive.
- **The track and indeterminate styles** take a `Gradient`, a ramp along the
  track, so a mesh cannot be given to them, here or in SwiftUI (whose `tint`
  takes a style; TUIkit's takes a `Color`, which is that modifier's own
  question).
