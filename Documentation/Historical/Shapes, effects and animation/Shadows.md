# Shadows

*How a terminal casts a shadow: from the cells a view paints, falling off by
whole rings, drawn past the view as overflow, and as a style's shadow. Ids: O6
(refusal review), B-O6-1 to 3, B-W1B-1.*

## In short

`View.shadow(color:radius:x:y:)` casts from the cells a view paints, falling
off by whole rings (the owner's O6 (b), 2026-10-12: cells as they are,
documented). Past its view a drop shadow is overflow, cut where later views
paint. A style's shadow (`ShapeStyle.shadow(_:)`) is cast by whatever draws
with it, from the cells it drew (lane W1B, 2026-10-19).

## The record

### B-O6-1. A shadow is cast by the cells a view paints, and falls off by whole rings

*`View.shadow(color:radius:x:y:)`, `ShadowStyle.drop(color:radius:x:y:)`,
`ShadowStyle.inner(color:radius:x:y:)`*

SwiftUI blurs, tints and offsets a view's per-pixel alpha. The ruling settled
the units (cells, as `.padding(8)`'s are); it left open what the alpha is and
what the blur is, at a cell's resolution.

- **What casts:** every cell the view paints — a glyph, or a blank with a field,
  reverse video or a line of its own (`String.columnsShowingNothing(width:)`,
  inverted) — at full strength. A label with no background casts the shape of
  its letters, a whole cell a letter; a filled card casts its rectangle; a
  bordered box with no fill casts its border and its text, as a stroked shape's
  shadow in SwiftUI is the stroke's.
- **The falloff:** the shadow is at the colour's alpha on the moved footprint,
  and `1 / (radius + 1)` of it less a ring beyond, a cell's ring being its
  Euclidean distance from the footprint rounded to whole cells
  (`ShadowField.ring(of:radius:)`). Rounded rather than truncated, the cell off
  a corner (1.4 cells out) is in the first ring, so a one-cell shadow keeps
  square corners — the classic terminal drop shadow — and wider ones round off.
  `radius + 1` alphas at most, so the claims they make coalesce into a few
  rectangles a row.
- **An inner shadow** darkens the painted cells by the same falloff measured
  from the nearest cell the view does not paint, everything outside it
  included, with that outside moved by the offset: deepest on the edges the
  offset points away from.
- **The cost** is the shadow's area, twice: at every render a two-pass
  distance transform (`ShadowField.squaredDistances`, linear in the cells
  whatever the radius) and the claims cut from it, and at every frame the
  screen root blending each cell past the view's frame over what is behind
  it, which a memo hit on the view does not skip (B-O6-2). A view with no
  shadow pays nothing: the modifier is the only thing that runs any of it.
  The area grows with the square of the radius, so the radius drawn is held
  to 32 cells (`ShadowField.radiusLimit`), more than most terminals are rows
  tall: a larger one is drawn as 32, its alpha still falling to nothing at the
  edge, so a ported `radius: 100` is a soft shadow 32 cells wide. Measured on
  a debug build, an 8 × 3 card rendered in 3 ms at a radius of 16, 8 ms at
  32, 29 ms at 64 and 0.32 s at 256, where an earlier limit of 256 cells let
  it go, its alpha stepping at the radius's own rate and stopping at a hard
  edge. An offset moves a shadow at most 2^20 cells, which no screen shows.
  A release A/B of a shadowed page is owed.

**The fuller version**, in parts that can ship apart:
1. **Coverage below a whole cell.** A glyph inks perhaps a fifth of its cell,
   so SwiftUI's shadow of a letter is fainter than its shadow of a filled
   rectangle. A constant table of how much of a cell each common glyph inks
   (the material frost's `FrameBuffer.frostCoverage(of:)` is one) would scale a
   letter's shadow down. About a day with the table; it changes every text
   shadow's look, so an owner's look first.
2. **A translucent caster.** A view drawn with a translucent field (a
   material, a `Color.opacity`) casts at full strength; scaling its cells by the
   alpha its claims state would cast a fainter shadow, as SwiftUI's does. About
   half a day.
3. **A caster that floats.** `.offset(x:y:)` draws its content as a floating
   layer and leaves a blank footprint, so `.offset(x: 2).shadow(radius: 1)`
   casts nothing (`.shadow(radius: 1).offset(x: 2)` is the spelling that works).
   Casting from the content's own displaced layers too: about half a day.
4. **A Gaussian falloff** instead of a linear one, as SwiftUI's blur is: a
   lookup per ring, an hour; the linear ramp is what the ruling describes.

### B-O6-2. Past its view, a drop shadow is drawn like a guide's overflow: the views after it cut it where they paint

*`View.shadow(color:radius:x:y:)`*

A drop shadow reaches past the view, and nothing in TUI composited a layer
beneath a view's cells before. The shadow is a layer of blank cells in the
colour's opaque spelling, each claiming its field at the shadow's alpha
there, laid under the view by `.background { … }`'s own compositor
(`compositeDrawnLayer(_:at:under:context:modifierType:)`, split out of
`compositeLayer(_:under:…)` for it): inside the frame it is the field of every
cell the view leaves clear, and it resolves against whatever is behind the
view where that is known; past the frame it is overflow
(`FrameBuffer.splitPlacing`, decisions
[B-GUIDE-3](<../Layout and geometry/Drawing past a region.md#b-guide-3-one-child-whose-guide-would-put-it-outside-its-region-is-held-inside-it>)),
drawn at the screen root over the views before the shadowed one, cut under the
views after it, and clipped by a scroll view, a list, a table cell or a surface
as SwiftUI clips a shadow at a scroll view's edge.

The layer is the shadow's whole rectangle. A cell of it that the shadow misses
— a corner past the last ring, the gap in a label's shadow under "a b" — is
claimed with its whole layer at 0, which leaves what is behind it untouched:
compositing replaces every cell a line spans, and an unclaimed blank there
would erase the glyph behind it. Laid row by row from each row's first shadowed
cell, as it first was, the overflow was cut into a layer for every row round
the corners, since overflow is cut into one layer per run of rows that start
at the same column (`OverlayLayer.drawnParts()`): sixteen for a radius of ten,
every one a draw at the screen root, and sixteen such cards spent the root's
whole budget of draws (measured from a probe on a debug build: 16 cards of
`.shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)`, 260 layers,
235 ms a root composite; as rectangles, 100 layers and 141 ms, the rest being
the cards after each shadow cutting it where they paint). A rectangle is at
most four, one a side of the view, whatever the radius. The price is the
corners: a run beneath one (a control's breath) is held to the frame drawn at
the last render, as a run beneath the shadow itself already was, and beneath
any translucent layer drawn at the root (`Opacity as composition.md` §109,
"what it does not cover yet").

What that shares with every overflow: a view after the shadowed one cuts the
shadow under every cell it PAINTS, a glyph's cell included, where SwiftUI would
show the shadow around the glyph's strokes. So a shadow running under a label
that comes later stops at the label's letters rather than darkening the field
behind them.

**The fuller version:** overflow that a later view composites over, as a
translucent layer, rather than cuts: the later view's cells that leave their
field clear would take the shadow under them. It is the general fix for every
kind of overflow, not a shadow's alone — about a day, and an A/B of the pages
that draw past a region, since every combining operation would then carry
translucent claims for the overflow it covers.

### B-O6-3. `ShapeStyle.shadow(_:)` waits on shapes, and `.inner` is drawn but has no public route yet

*`ShapeStyle.shadow(_:)` (instance and static), `ShadowStyle.inner(color:radius:x:y:)`*

`ShadowStyle` has exactly one consumer in SwiftUI, `ShapeStyle.shadow(_:)`:
`Rectangle().fill(.red.shadow(.drop(radius: 2, y: 3)))`,
`Circle().fill(.shadow(.inner(radius: 1, y: 1)))`. Shapes are W1's, another
lane's, and are not on this lane's base, so it stays a baseline gap.

It is not shipped for the styles that exist already, `.background(_:)` and
`.foregroundStyle(_:)` among them, because a shadowed style is a `ShapeStyle`
and goes everywhere one goes: every consumer that did not draw the shadow — a
border, a tint, a list row's fill, a control's ink — would drop it without a
word, which is rule 2's silent no-op. So it ships when every consumer can draw
it, not before.

The drawing is done: `ShadowModifier` draws either kind
(`FrameBuffer.castingDropShadow`, `FrameBuffer.castingInnerShadow`), and the
inner one is tested through it (`ShadowTests`), so `.inner` is reachable from
inside the module only. `ShadowStyle.inner` compiles, as SwiftUI's does, and
using one fails to compile until `ShapeStyle.shadow(_:)` exists.

**The fuller version:** after W1, carry a `ShadowStyle` on the `Paint` a style
resolves to, and have each consumer cast it from the cells it painted with that
style — a shape's fill and stroke, `.background(_:)`'s fill (a drop shadow
under the fill, an inner one over the fill and under the content), `Text`'s
ink, a border's lines — through the two functions above. About two days, most
of it going through the consumers; the drawing itself is shared.

**Shipped** by lane W1B (2026-10-19), as this fuller version describes it:
[B-W1B-1](#b-w1b-1-a-styles-shadow-is-cast-by-whatever-draws-with-it-from-the-cells-it-drew).

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
