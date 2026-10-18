# Completing the SwiftUI API: lane O6's judgement calls

*Lane O6, 2026-10-18, shipped the owner's ruling on refusal review
[O6](<../Refusals re-examined, wave 17 (2026-10-03).md#o6-shadowstyle--w16-shadow-w13-shapestyleshadow--m>)
(2026-10-12: option (b), cells as-is, documented): `View.shadow(color:radius:x:y:)`
and `ShadowStyle`. Where the work met a judgement call the ruling did not
settle, the safe option shipped and is written up here, in the three parts the
other lanes use: A needs a decision, B shipped the safe option (with the fuller
version and its price), C declined with a parity-map reason. SwiftUI's side is
its declarations and Apple's documentation; nothing here was measured.*

## B. Shipped the safe option

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
- **The cost** is the shadow's area: a two-pass distance transform
  (`ShadowField.squaredDistances`, linear in the cells whatever the radius),
  one layer of cells, and the compositor a translucent `.background` already
  goes through. A view with no shadow pays nothing: the modifier is the only
  thing that runs any of it. So that a ported `radius: 1000` does not cost a
  square two thousand cells on a side, a shadow is drawn at most 256 cells
  from what casts it (`ShadowField.reachLimit`), its alpha still stepping at
  the radius's own rate, and an offset moves it at most 2^20 cells; neither
  bound is anywhere a screen can show.

**The fuller version**, in parts that can ship apart:
1. **Coverage below a whole cell.** A glyph inks perhaps a fifth of its cell,
   so SwiftUI's shadow of a letter is fainter than its shadow of a filled
   rectangle. A constant table of how much of a cell each common glyph inks
   (the frosted-material add-on of O5 needs the same table) would scale a
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

A drop shadow reaches past the view, and nothing in TUIkit composited a layer
beneath a view's cells before. The shadow is a layer of blank cells in the
colour's opaque spelling, each claiming its field at the shadow's alpha
there, laid under the view by `.background { … }`'s own compositor
(`compositeDrawnLayer(_:at:under:context:modifierType:)`, split out of
`compositeLayer(_:under:…)` for it): inside the frame it is the field of every
cell the view leaves clear, and it resolves against whatever is behind the
view where that is known; past the frame it is overflow
(`FrameBuffer.splitPlacing`, decisions
[B-GUIDE-3](<Alignment guides outside their view (GUIDE).md#b-guide-3-one-child-whose-guide-would-put-it-outside-its-region-is-held-inside-it>)),
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
