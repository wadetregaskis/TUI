# What the shapes unblocked: decisions from lane W1B

*Lane W1B, 2026-10-19: the work lanes W1 (shapes) and O6 (shadows) left owed
once both had landed — `ShapeStyle.shadow(_:)` (B-O6-3), and what
[Shapes (W1).md](<Shapes (W1).md>) lists under Owed. SwiftUI's side was
measured on macOS 15.8 by probes that read back pixels
([`Tools/SwiftUIProbes/Shadowed shape styles/`](<../../../../Tools/SwiftUIProbes/Shadowed shape styles>)).
The format is that of the main decisions file:*

- **A-W1B-n — needs your decision.**
- **B-W1B-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-W1B-n — declined.** With the reason, and a parity-map entry.

## B. Shipped the safe option

### B-W1B-1. A style's shadow is cast by whatever draws with it, from the cells it drew

*`ShapeStyle.shadow(_:)`, the static `.shadow(_:)`*

What was measured, and is drawn so: the static form's style is the foreground,
and inside `backgroundStyle(_:)` the background style above; `.secondary` of a
shadowed foreground keeps the shadow at half; a fade on either side of the
shadow halves it; a background's inner shadow darkens its fill and not the
content in front of it; two shadows on one style are each cast from the
style's drawing, not one from the other.

The shadow travels in the resolved paint (`Paint.shadowed`), so it rides the
foreground slot and every style that changes another — `opacity(_:)`, `in(_:)`,
the content levels, `AnyShapeStyle` — with nothing more to do; each consumer
that draws splits it off, draws the paint, and casts the shadows from the cells
it drew (`FrameBuffer.castingShadows(of:context:owner:)`, O6's two casters).
The consumers that draw: a shape's fill and stroke; `background(_:)`'s fill —
and so `background()`, `background(_:in:)`, `containerBackground(_:for:)` and
`presentationBackground(_:)` — on a layer of its own, its inner shadows over it
and the content laid over both; and under a `foregroundStyle`, a `Text`'s
letters, a `Divider`'s rule, a spinner, a template or mono image's picture, a
symbol's breath, and a `Table`'s rows. A control that draws an inherited
foreground in a colour of its own — a hovered or disabled toggle's label, a
radio button's, a segment's — keeps the shadow on it. What only derives a
colour from a paint — a contrast floor, a mono picture's paper — reads through
the shadow as it reads through a ramp.

Where the measurement left a call:

- **A ramp casts at its representative colour's alpha.** SwiftUI's shadow of a
  ramp fading along its length fades with it, pixel by pixel (`stacked.swift`,
  Q15); a terminal cell's shadow field is cast from whether the cell paints.
- **A table casts once, from its rows' glyphs.** It paints its text cells
  itself, so the rows cast together, a view cell's glyphs among them (its own
  views are drawn without the shadow, so nothing is cast twice); a row's own
  fill — a stripe, the focused row — hides the shadow where it paints, as any
  field of a view's own does.
- **A shadow changed inside `withAnimation` jumps.** The paint under it moves
  as before.
- **A text's run with a colour of its own still casts** with the rest of the
  text, which casts as one block.

**The fuller version:** a ramp's shadow scaled per cell by the ramp's alpha
there — half a day, the shadow field taking a strength per cell; the shadow
animated through `PaintAnimation`'s slots, its colour, radius and offset — a
few hours.

### B-W1B-2. A zoom source's clip shape and shadow shrink to nothing as the rectangle grows

*`MatchedTransitionSourceConfiguration.clipShape(_:)`,
`MatchedTransitionSourceConfiguration.shadow(color:radius:x:y:)`*

The zoom (B-O4-5) is a rectangle growing from the source's frame to the stack's.
The source's clip shape cuts the rectangle's corners — a cell kept where the
shape covers at least half of it, the rule `clipShape(_:)` keeps
(B-W1-11) — and the screen it grows over shows in the corners cut away; its
shadow is cast from the rectangle, or from the clip shape where there is one,
onto that screen, in cells as every shadow here is (C10), and is cut at the
stack's edge. SwiftUI interpolates a source's configuration into the
destination's (Apple's documentation; the zoom is iOS-only, so not measured);
a pushed screen has neither, so the radius shrinks with what is left of the
zoom and the shadow's alpha fades with it, the source's at the start and
nothing once the rectangle is the stack's.

While a corner is cut, a click there reaches the screen being uncovered, not
the one showing through: the hit regions are the screen's whole rectangle, as
they were before the clip.

**The fuller version:** the screen's hit regions cut with its corners — an
hour, with the mask a `contentShape` uses (B-W1B-3).

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

## C. Declined

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

## Owed

What [Shapes (W1).md](<Shapes (W1).md#owed>) owes that this lane did not do, and
why. None is a decision.

- **`mask(alignment:_:)`** — decisions A27, the owner's: excluded from this lane
  by its brief. The cell-coverage rule a clip and a content shape keep by is
  the natural one (B-W1-11, B-W1B-3).
- **`Canvas` and `GraphicsContext`** — the refusal review's D3, which needs a
  design of its own: excluded by the brief.
- **`glassEffect(_:in:)` and `DefaultGlassEffectShape`** — lane GLASS's work,
  which is not on this lane's base; whatever of it takes a `Shape` lands there.
- **A picture for a shape on a terminal that takes one** (B-W1-4's fuller
  version) — a day, and a terminal-graphics A/B: more than the brief's S or M.
- **One half-block emitter shared by images and shapes** (B-W1-1's fuller
  version) — half a day, but it moves the image glyph path's inner loop, whose
  retains are counted, across a module boundary: it wants an A/B before it
  lands, which a lane cannot run. Left for a pass that can measure it.
- **The A/B of the box path** W1 owed (a sheet's corner radius read in
  `ContainerViewCore`), and this lane's own: `textwall`, `fanout` and
  `gradients` for the one enum test a text, a background and a shape pay for a
  paint without a shadow (B-W1B-1); `menus` and `dashboard` for the marker scan
  each region a modifier registers over a view's frame now makes (B-W1B-3).

