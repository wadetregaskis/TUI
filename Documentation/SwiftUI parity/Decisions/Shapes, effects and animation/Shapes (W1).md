# Shapes: decisions from lane W1

*Lane W1, 2026-10-18: SwiftUI's shapes, after the refusal review's W1 and the
owner's ruling on O0 (2026-10-12: square units — x in columns, y in rows ×
`\.imageCellAspect`). SwiftUI's geometry was measured on macOS 15.8 by probes
that print SwiftUI's own path descriptions (`Tools/SwiftUIProbes/Shape paths (W1)/`); the
macOS 26 declarations were read from the Xcode SDK's `SwiftUICore`
interface. The format is that of the main decisions file:*

- **A-W1-n — needs your decision.**
- **B-W1-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-W1-n — declined.** With the reason, and a parity-map entry.

## A. Needs your decision

### A-W1-1. Should `import TUIkit` bring Foundation's geometry with it?

*`CGRect`, `CGPoint`, `CGSize`, `CGFloat` in a shape of the app's own*

A shape of an app's own is written against `path(in rect: CGRect)`, and
`CGRect` is Foundation's (on Apple platforms, CoreGraphics'). SwiftUI
re-exports Foundation, so a SwiftUI file that imports only SwiftUI compiles; a
TUIkit file that imports only TUIkit does not — `cannot find type 'CGRect' in
scope` (measured with a probe against the built modules). The same is already
true of `Date`, `URL` and `SortDescriptor` (the compile corpus imports
Foundation for them), so this lane changed nothing; it is where the friction is
sharpest, because every custom shape meets it.

**Options.**

1. **Leave it** (shipped): a ported shape adds `import Foundation`. The
   compatibility guide's §2.12 says so. Free.
2. **Re-export Foundation from the umbrella** — `@_exported import Foundation`
   in `Sources/TUIkit/Exports.swift`, as SwiftUI does. An app that imports
   TUIkit then sees all of Foundation, as a SwiftUI app does. An hour, and a
   look at whether any TUIkit name collides with a Foundation one in a client
   (none known).
3. **Re-export the geometry alone** — CoreGraphics on Apple platforms, where
   the types live; on Linux and Windows they are in Foundation, which cannot
   be split, so this is option 2 there.

**Recommendation:** 2. It is what a ported file expects, and the cost of
Foundation in scope is one SwiftUI apps already pay.

## B. Shipped the safe option

### B-W1-1. Shapes live in TUIkitFoundation, rasterizer and all

*`Path`, `Shape`, `ShapeCoverage`, `ShapeStroker`, `ShapeHalfBlocks`,
`ShapeBoxCells`*

The lane brief put the rasterizer in TUIkitImage, the module the refusal
review called "pure math". It cannot be there: TUIkitFoundation does not
depend on TUIkitImage, deliberately (module split step B5c: an app that shows
no image links neither TUIkitImage nor its decoder, CSTBImage), and a
rasterizer below TUIkitFoundation could not see `Path`. So the shapes, the
rasterizer and the cell emitter are all TUIkitFoundation's, beside
`GradientRaster` and `MeshRaster`, which are there for the same reason. They are
pure arithmetic and import nothing POSIX, so the Windows port loses nothing.

The refusal review also said to hand the coverage to `ASCIIConverter`'s
half-block renderer. That renderer is TUIkitImage's too; the half-block table
it follows (`Opacity as composition.md` §42.2) is re-stated in
`ShapeHalfBlocks`, about forty lines.

**The fuller version:** one half-block cell emitter shared by images and
shapes, in TUIkitStyling, below both. Half a day, and an A/B of the image glyph
path, whose inner loop counts retains.

### B-W1-2. A rectangle-family stroke is a box of light lines, whatever the appearance

*`Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`,
`ContainerRelativeShape`: `stroke`, `strokeBorder`, `stroke(lineWidth:)`*

A stroke no wider than a column and undashed, round a shape of the rectangle
family, is a box in the outermost cells: `┌─┐` where a corner's radius is zero
and `╭─╮` where it is not, decided per corner (the refusal review's reading).
One row tall it ends in `(` `)` where rounded and `[` `]` where not, as a lines
button does; one column runs `╷ │ ╵`; one cell is `○` or `□`. `stroke` and
`strokeBorder` draw the same box: lines in the outermost cells are already
inside the frame. A wider or dashed stroke is rasterized.

The box is light lines in every `Appearance`: a shape is geometry the caller
drew, not chrome the theme owns. Its glyphs are the light `BorderStyle`s', drawn
by the shapes' own cell emitter (`ShapeCells`) rather than by `BorderRenderer`,
whose functions take one colour: a stroke in a gradient paints each cell its
own colour, and a translucent one claims its alpha as every shape cell does.

**The fuller version:** follow the appearance's family as a button face does
— heavy and double lines, a Braille outline, a block ring — and draw a stroke
between one and two columns wide in heavy lines rather than rasterizing it
(heavy lines have no rounded corners, so a rounded one would rasterize). Half
a day.

### B-W1-3. A rectangle-family fill cuts its rounded corners in quadrants

*the same shapes: `fill`, and as a view*

`Rectangle().fill(s)` is `.background(s)` over a blank block — exactly what a
`Color` or a gradient used as a view is, including the gradient picture on a
terminal that takes one. The other rectangle-family shapes fill their cells,
each rounded corner cut at quadrant resolution where the shape's own path
leaves a quadrant less than half covered, and by at least the outermost
quadrant however small the radius (`▟`), so a corner the caller rounded looks
rounded. One row tall, a rounded end is the half-block cap, `▐ … ▌`, TUIkit's
capsule since its first text field. Where Apple Terminal draws Block Elements
short of the line a corner is a whole cell, drawn where at least half covered,
as a solid button face's is there; the one-row caps are kept, as a button's
are.

**The fuller version:** draw the corner cells at their coverage as alpha, as
the rasterizer does, instead of in quadrants. It would make a radius-1 corner a
faint cell rather than a notch; the quadrants were chosen to match the solid
button faces. An hour either way.

### B-W1-4. The rasterizer draws half blocks at their coverage, and no shape is a picture

*`Circle`, `Ellipse`, `Path`, custom shapes, `trim`, `rotation`, `scale`,
`offset`, `transform`, `size`, wide and dashed strokes*

Each cell is two pixels, a column across and half a row down (square at the
usual aspect), each sampled at 4 × 4 points; its coverage is drawn as alpha by
§42.2's table, so an edge blends into whatever is behind it at composite time.
A cell the shape does not reach is claimed at field 0, so a glyph beneath it
survives (a `ZStack` of text under a circle keeps the text round the circle).
The stroke is the union of convex pieces filled by the non-zero rule, which
draws joins, caps, the miter limit and dashes exactly.

On a terminal that takes pictures a shape is still cells. Its picture would
always have transparent pixels, and the terminal composites those against the
cell it is placed in, not against what TUIkit knows is behind — the reason
`BackgroundModifier.pictured` declines a translucent gradient. A picture would
also hide any glyph under the shape's bounding box.

**The fuller version:** send the picture where everything under the shape's
bounding box is known to be one opaque field (a shape on a filled card), with
that field composited into the picture. A day, and a terminal-graphics A/B.

### B-W1-5. A shape draws within its frame

*`stroke` past the frame, `offset`/`rotation`/`scale` past the frame*

A view's buffer is the size it reports (deviation L5), so a stroke's outer half
on the frame's edge, and any of a moved shape that leaves the frame, are not
drawn. SwiftUI draws both. `strokeBorder` draws the whole line inside.

**The fuller version:** what leaves the frame as a floating layer, as
`.offset` already floats displaced drawing (L6). A day, for a case
`strokeBorder` covers.

### B-W1-6. A shape sizes itself in TUIkit's layout terms

*`Shape.sizeThatFits(_:)`*

SwiftUI's takes a `ProposedViewSize` and answers a `CGSize`. TUIkit's layout
asks for cells and for whether each axis fills (`ViewSize`), as a custom
`Layout` already answers, so a shape's `sizeThatFits` takes a `ProposedSize`
and answers a `ViewSize`. The default fills both axes from nothing, as a
`Color` does — SwiftUI's default, the proposal, read in TUIkit's terms. A
ported override fails to compile (`ProposedViewSize` is `renamed` in the
parity map) rather than being ignored.

**The fuller version:** none needed; a shape that keeps an aspect writes it in
cells, as a `Layout` does.

### B-W1-7. A continuous corner that does not fit is drawn circular

*`RoundedCornerStyle.continuous`, `Capsule`'s default*

Apple's continuous corner reaches 1.53 radii along each edge (measured). Where
two such corners do not fit along a side, SwiftUI blends toward a circular
corner by an amount the probe printed but did not explain; TUIkit draws that
corner circular. The difference is below a sub-cell at any size a cell grid
shows, and the box tier never sees it.

**The fuller version:** fit SwiftUI's blend from more probe points. Half a
day, for path descriptions alone.

### B-W1-8. `stroke(lineWidth:)` as a shape is drawn as the stroke; its path is the stroke's pieces

*`Shape.stroke(lineWidth:)`, `Shape.stroke(style:)`*

`Circle().stroke(lineWidth: 2)` — no style named — is the stroke as a shape,
filled. It is drawn as the stroke it is (so a rectangle's is the box of lines),
and when its path is asked for it is the union of the stroke's convex pieces,
filled by the non-zero rule: what the stroke covers, not an outline of it. That
is why `Path.strokedPath(_:)`, which promises an outline, stays absent (C-W1-1).

**The fuller version:** an exact outline, by offsetting curves and clipping the
pieces — the computational geometry C-W1-1 declines.

### B-W1-9. `AnyShape` does not animate the shape it holds

*`AnyShape.AnimatableData`*

Erased, a shape's animatable data has no type a property could name, so
`AnyShape`'s is `EmptyAnimatableData`: a corner radius changed inside an
`AnyShape` inside `withAnimation` jumps. The concrete shapes, their adapters and
the views drawing them all forward their data.

**The fuller version:** a type-erased `VectorArithmetic` box, as SwiftUI's
`AnyShape` has. Half a day.

### B-W1-10. `contentShape` takes a rectangle alone

*`View.contentShape(_:eoFill:)`; `View.contentShape(_:_:eoFill:)` waits*

A view's hit area is already its frame — a click on a spacer or the padding
inside a tappable stack reaches it — so `.contentShape(Rectangle())`, the form
nearly every port writes, asks for what is already so, and returns the view
(refusal review P3: measured, it changes no pixel on macOS either). A hit area
cut to another shape would need the pointer dispatch to take a region per row
from the enclosing gesture, which it does not, so the parameter is a
`Rectangle` and `.contentShape(Circle())` fails to compile rather than claiming
the whole frame. The `ContentShapeKinds` form waits on P3.

**The fuller version:** a hit mask carried by the buffer to the gesture, hover
and context-menu modifiers outside it, cut from the shape's cells as a clip is.
A day, and a field on every buffer that has to stay free for views without one.

**Shipped** by lane W1B (2026-10-19), with no field on any buffer: the mask
rides as geometry markers
([B-W1B-3](<What the shapes unblocked (W1B).md#b-w1b-3-a-content-shape-is-carried-to-the-modifiers-around-it-as-geometry-markers>)).

### B-W1-11. A clip keeps a cell at half coverage, and leaves the hit area alone

*`View.clipShape(_:style:)`*

A cell of the view is kept where the shape covers at least half of it and
cleared — a space claimed at a field of 0, so what is behind shows — otherwise;
the view's claims and animated runs over a cleared cell are cut with it. A
`Rectangle` keeps the frame. The view is clipped to its frame first, as
`clipped()` clips, so its floating layers are cut too. The hit area is not
clipped, for B-W1-10's reason.

**The fuller version:** an antialiased clip — a kept cell at the edge drawn at
its coverage as alpha. Half a day; the ½ rule is what every other glyph decision
here takes.

### B-W1-12. A container-relative shape is inset by the nearest side

*`View.containerShape(_:)`, `ContainerRelativeShape`*

A `containerShape(_:)` publishes its shape, its size (its content measured as a
frame offered what the modifier is offered) and its place, a carried geometry
origin started there (`RenderContext.geometryOriginX`, which stacks, frames,
paddings and offsets move onto each child). A `ContainerRelativeShape` inside is
drawn as the container's shape inset by how far inside the container it lies —
the nearest of its four sides, a row counting the cell aspect — and drawn in its
frame grown by that distance, so its outline sits on its frame with every radius
shrunk by the distance: concentric. In box glyphs a corner is `╭` while the
container's radius outlasts the distance and `┌` once it is used up. Its border
(`strokeBorder`) borders the container's shape. SwiftUI's inset rule for a view
nearer one side than another is not measured; the nearest side keeps the shape
inside the container.

**The fuller version:** an inset per side, so a view hugging one edge keeps that
edge's corners and rounds the far ones less. An hour, once SwiftUI's rule is
measured on a macOS 26 machine.

### B-W1-13. macOS 26's corner vocabulary, from the SDK's declarations

*`ConcentricRectangle` (its nine initialisers and the eight `.rect(…)`
spellings), `RoundedRectangularShape`, `RoundedRectangularShapeCorners`,
`Edge.Corner` with `Set` and `Style`, `RectangleCornerRadii[corner]`, the
rounded shapes' `corners(in:)`, `containerShape(_:)` for a rounded rectangular
shape*

Declared as the Xcode SDK's `SwiftUICore` interface declares them; this Mac runs
macOS 15, so SwiftUI's behaviour is not measured and the doc comments are not in
the symbol graphs. What each does here: a `Style` is a fixed radius (a number
literal is one) or concentric with the container's corner on its side, no
smaller than its minimum; a `ConcentricRectangle` resolves its corners against the
container as B-W1-12 places it, and without a container a concentric corner is
its minimum; `isUniform` makes every corner the smallest of the four; a circle's
and a capsule's `corners(in:)` are half the shorter side, and `nil` without a
size. Animatable data is each type's radii.

**The fuller version:** measure each on a macOS 26 machine and match it — in
particular `isUniform`, and what a concentric minimum that is itself concentric
means. Half a day with the machine.

### B-W1-14. A sheet's corner radius is its box's corners (decisions A24)

*`View.presentationCornerRadius(_:)`*

A24, decided with O0 and O15: a radius has a cell reading now, the one a shape's
lines take — zero is `┌`, any other radius `╭`, `nil` the appearance's. A terminal
sheet has no card of its own; its content's outermost box (a `Dialog`, a
`Panel`, a `.border()`) is the sheet. So the modifier is a presentation trait,
read by the presenter as a detent is, which hands the radius to that box through
the environment (`sheetCornerRadius`, beside `sheetDetentHeight`), and the box
consumes it, so a box inside keeps its own corners. Only light lines have both
corners: a heavy, double, dotted or block box keeps its own. A popover and a
full-screen cover have no box to round.

**The fuller version:** rounded heavy and double corners do not exist in
Unicode; a block box could cut its corners in quadrants as a filled rounded
rectangle does. An hour, if wanted.

## C. Declined

### C-W1-1. `Path`'s boolean operations and its stroke outline

*`union`, `intersection`, `subtracting`, `symmetricDifference`,
`lineIntersection`, `lineSubtraction` (on `Path` and `Shape`),
`Path.normalized(eoFill:)`, `Path.strokedPath(_:)`*

Out of the lane's cut, as briefed: each needs exact geometric clipping of one
outline by another, or offsetting a curve by half a line width. Absent, so a
call fails to compile; one parity-map family names them. A mask-level union or
intersection for fills — coverage combined, no outline made — is possible later.

### C-W1-2. `layoutDirectionBehavior` on every shape

*`Shape.layoutDirectionBehavior` and each shape's*

It waits on decisions A3 (deferred with right-to-left support): SwiftUI's
`.mirrors(in: .leftToRight)` really mirrors, so the property cannot be a
constant that compiles and means nothing. A parity-map family names it.

## Owed

What the shapes unblock and this lane did not reach. None is a decision; each is
work. Lane W1B (2026-10-19) took the first three and `ImagePaint`; what it left,
and why, is in its decisions,
[What the shapes unblocked (W1B).md](<What the shapes unblocked (W1B).md#owed>).

- **`contentShape(_:_:eoFill:)` and `ContentShapeKinds`** (refusal review P3), and
  `contentShape` for shapes other than a rectangle (B-W1-10's fuller version).
  *Shipped by W1B (B-W1B-3).*
- **`ShapeStyle.shadow(_:)`** with lane O6's `ShadowStyle`, **`glassEffect(_:in:)`**
  and `DefaultGlassEffectShape` with lane GLASS, and the zoom transition's
  `MatchedTransitionSourceConfiguration.clipShape(_:)` with lane O4: each takes a
  `Shape`, which is here now. *`ShapeStyle.shadow(_:)` and the zoom's clip shape
  shipped by W1B (B-W1B-1, B-W1B-2); the glass effect's shape is lane GLASS's.*
- **`mask(alignment:_:)`** (decisions A27): the cell-coverage rule a clip shape
  keeps by (B-W1-11) is the natural one, but A27's choice is the owner's.
- **`Canvas` and `GraphicsContext`** (the refusal review's D3): a drawing context
  of paths, filled and stroked through this lane's rasterizer.
- **`ImagePaint`** (W9): a shape filled with an image, which the rasterizer's
  per-pixel paint is ready for. *Shipped by W1B (B-W1B-4).*
- **A picture for a shape on a terminal that takes one** (B-W1-4's fuller
  version), and the half-block emitter shared with images (B-W1-1's).
- **An A/B** of the box path (`ContainerViewCore` reads one more environment value
  for a sheet's corner radius, B-W1-14) on the `deep`, `kitchensink` and
  `dashboard` Stress scenarios; nothing else here touches a path that existed
  before.

