# Shapes

*How SwiftUI's shapes came to a cell grid: square units, a rasterizer of half
blocks, strokes as light lines, rounded corners, clips and content shapes, and
what was declined. Ids: O0 (square units), W1 (refusal review), A-W1-1,
B-W1-1 to 14, C-W1-1, C-W1-2, B-W1B-3, B-W1B-4, C-W1B-1.*

## In short

Shapes use square units (x in columns, y in rows × `\.imageCellAspect`), live
in TUIFoundation with their rasterizer, and draw half blocks at their
coverage; a rectangle-family stroke is a box of light lines. A shape draws
within its frame; a clip keeps a cell at half coverage; `contentShape` takes a
rectangle, carried to the modifiers around it as geometry markers. `Path`'s
boolean operations and stroke outlines are declined.

## How it unfolded

1. **2026-10-12, O0:** square units. **2026-10-18, lane W1** built shapes on
   them, measuring SwiftUI's geometry on macOS 15.8.
2. **2026-10-19, lane W1B** built what W1 and O6 left owed.
3. **A-W1-1** (should `import TUI` bring Foundation's geometry) was listed for
   the owner on 2026-10-18 and never answered (recommended: yes, re-export).

## The record

### A-W1-1. Should `import TUI` bring Foundation's geometry with it?

*`CGRect`, `CGPoint`, `CGSize`, `CGFloat` in a shape of the app's own*

A shape of an app's own is written against `path(in rect: CGRect)`, and
`CGRect` is Foundation's (on Apple platforms, CoreGraphics'). SwiftUI
re-exports Foundation, so a SwiftUI file that imports only SwiftUI compiles; a
TUI file that imports only TUI does not — `cannot find type 'CGRect' in
scope` (measured with a probe against the built modules). The same is already
true of `Date`, `URL` and `SortDescriptor` (the compile corpus imports
Foundation for them), so this lane changed nothing; it is where the friction is
sharpest, because every custom shape meets it.

**Options.**

1. **Leave it** (shipped): a ported shape adds `import Foundation`. The
   compatibility guide's §2.12 says so. Free.
2. **Re-export Foundation from the umbrella** — `@_exported import Foundation`
   in `Sources/TUI/Exports.swift`, as SwiftUI does. An app that imports
   TUI then sees all of Foundation, as a SwiftUI app does. An hour, and a
   look at whether any TUI name collides with a Foundation one in a client
   (none known).
3. **Re-export the geometry alone** — CoreGraphics on Apple platforms, where
   the types live; on Linux and Windows they are in Foundation, which cannot
   be split, so this is option 2 there.

**Recommendation:** 2. It is what a ported file expects, and the cost of
Foundation in scope is one SwiftUI apps already pay.

### B-W1-1. Shapes live in TUIFoundation, rasterizer and all

*`Path`, `Shape`, `ShapeCoverage`, `ShapeStroker`, `ShapeHalfBlocks`,
`ShapeBoxCells`*

The lane brief put the rasterizer in TUIImage, the module the refusal
review called "pure math". It cannot be there: TUIFoundation does not
depend on TUIImage, deliberately (module split step B5c: an app that shows
no image links neither TUIImage nor its decoder, CSTBImage), and a
rasterizer below TUIFoundation could not see `Path`. So the shapes, the
rasterizer and the cell emitter are all TUIFoundation's, beside
`GradientRaster` and `MeshRaster`, which are there for the same reason. They are
pure arithmetic and import nothing POSIX, so the Windows port loses nothing.

The refusal review also said to hand the coverage to `ASCIIConverter`'s
half-block renderer. That renderer is TUIImage's too; the half-block table
it follows (`Opacity as composition.md` §42.2) is re-stated in
`ShapeHalfBlocks`, about forty lines.

**The fuller version:** one half-block cell emitter shared by images and
shapes, in TUIStyling, below both. Half a day, and an A/B of the image glyph
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
rounded. One row tall, a rounded end is the half-block cap, `▐ … ▌`, TUI's
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
cell it is placed in, not against what TUI knows is behind — the reason
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

### B-W1-6. A shape sizes itself in TUI's layout terms

*`Shape.sizeThatFits(_:)`*

SwiftUI's takes a `ProposedViewSize` and answers a `CGSize`. TUI's layout
asks for cells and for whether each axis fills (`ViewSize`), as a custom
`Layout` already answers, so a shape's `sizeThatFits` takes a `ProposedSize`
and answers a `ViewSize`. The default fills both axes from nothing, as a
`Color` does — SwiftUI's default, the proposal, read in TUI's terms. A
ported override fails to compile (`ProposedViewSize` is `renamed` in the
parity map) rather than being ignored.

**The fuller version:** none needed; a shape that keeps an aspect writes it in
cells, as a `Layout` does.

### B-W1-7. A continuous corner that does not fit is drawn circular

*`RoundedCornerStyle.continuous`, `Capsule`'s default*

Apple's continuous corner reaches 1.53 radii along each edge (measured). Where
two such corners do not fit along a side, SwiftUI blends toward a circular
corner by an amount the probe printed but did not explain; TUI draws that
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
([B-W1B-3](#b-w1b-3-a-content-shape-is-carried-to-the-modifiers-around-it-as-geometry-markers)).

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

### B-W1B-3. A content shape is carried to the modifiers around it as geometry markers

*`View.contentShape(_:eoFill:)`, `View.contentShape(_:_:eoFill:)`, `ContentShapeKinds`*

A content shape is the cells its shape covers at least half of — the rule a
clip keeps a cell by (B-W1-11). For `.interaction` the view takes the pointer
only there: the hit regions its content registered are cut to them, and so is
the region a gesture, hover, context-menu, `.help`, drag, drop, spring-loading
or text-selection modifier registers over the view, so a click outside the
shape reaches what is behind the view. For `.dragPreview` the preview a
`.draggable` view carries is cut to them, and where a drag starts is left
alone, as SwiftUI documents.

The cells travel in the buffer as zero-area geometry markers, beside the hit
regions — the frame's two corners, then each run's two ends — as a picture's
corners do; a modifier registering over the view asks for its cut
(`FrameBuffer.frameHitRegions(handlerID:focusID:width:height:)`), which is the
whole frame where no shape covers it. So no buffer carries anything for a view
with no content shape, a memo serves the shape with the buffer, and the pointer
dispatch needed no change: a region cut into pieces is several regions with
one handler, and each records what was cut above and before it, so a handler
is still handed points from the frame's origin. Registering nothing itself, the
shape goes round each member of a `Group` or a `ForEach`, as
`.allowsHitTesting(_:)` does, and a container reaches past it to the members,
their tags, z-indices, priorities and guides — as it did when
`.contentShape(Rectangle())` returned the view itself.

Where the measurement did not reach:

- **A shape reaches the modifiers whose frame is its own.** SwiftUI hit-tests
  each view against its content shape, so a `.padding` between the shape and a
  gesture leaves the gesture the shape (its padding takes no hits there). Here
  a view's hit area is its frame (refusal review P3), so the gesture takes its
  whole padded frame.
- **A click on a cut corner of a hovered view** leaves it as moving off it does;
  moving from one piece to another inside the shape is staying on it.

**The fuller version:** hit-testing per view against its shape, the padding
included — a change to how every hit area is found, which TUI's
frame-as-hit-area rule does not ask for. No price until a port needs it.

### B-W1B-4. An image paint is sampled cell by cell, and paints nothing until its picture is there

*`ImagePaint`, `ShapeStyle.image(_:sourceRect:scale:)`*

What was measured, and is drawn so (`Tools/SwiftUIProbes/Image paint/`): the
tile is the source rectangle's share of the image's size in points, times the
scale, repeated from the top-leading corner of the frame filled — a shape's, a
background's, a text's — or from the origin `in(_:)` names, whose size changes
nothing. A tile is its size in points over the terminal cell's
width in points columns across, a row being the cell aspect of them down, so a
shape's half-block rasterizer samples the same picture at twice the rows; each
cell is the mean of four samples, weighted by their alpha, the alpha a claim,
as a translucent ramp's is.

Where the measurement left a call:

- **The cell's size not known** (under tmux, over ssh to Ghostty), one tile
  spans what is filled, across, at the scale — as an `Image` that is not
  resizable fits the space it is offered there.
- **A picture that loads** — a file, a URL — paints nothing until it has,
  as an `Image` shows its placeholder. It loads as an image does, its state at
  a child identity of whatever draws with the paint (a foreground style once,
  for everything under it), keyed by that drawer's type, so a style and the
  backgrounds drawn at one view each keep a load of their own; it is
  converted once. SwiftUI's images are never late.
- **Once a member.** A style on a `Group` or a `ForEach` goes round each of
  its members, as every style does, and each copy loads the paint at its own
  member: three members of a file's paint decode the file three times, hold
  three copies of its pixels, and each paints on the frame its own load
  lands — as three `Image`s of the file would. A cost, not a wrong picture.
- **A symbol**, `Image(systemName:)`, is a character here with no pixels, and
  paints nothing.
- **Cells, never a picture.** On a terminal that takes pictures a gradient
  behind blank cells is one; an image paint is not, being sampled already — a
  picture of it would sample the image again at the terminal's pixels.
- **A new picture shows at once** under `withAnimation`.

**The fuller version:** an image paint behind blank cells sent as a picture —
the tile drawn at the terminal's pixel resolution, half a day with
`GradientRaster`'s picture path; a symbol's paint drawn as the glyph repeated, a
day, since a paint names colours, not glyphs; one load and one set of pixels
for every paint of one source — a store of decoded pictures on the app's
context, keyed by the source and released with the last paint holding it, which
the `Image`s of one file would share too — half a day.

### C-W1B-1. `ContentShapeKinds.focusEffect` and `.accessibility`

*as the refusal review's P3 ruled*

`.focusEffect` shapes the focus ring macOS draws round a focused view, and
TUI draws none a shape could outline: focus is the control's own drawing
breathing. `.accessibility` shapes a view's accessibility frame, and a screen
reader reads a terminal from its text. Both are omitted, so a ported
`.contentShape(.focusEffect, …)` fails to compile; parity-map entries say why.
`.contextMenuPreview` and `.hoverEffect` are unavailable on macOS and declined
with the effects they shape (O8); they are not in the macOS symbol graphs the
parity check reads.
