# What the shapes unblocked: decisions from lane W1B

*Lane W1B, 2026-10-19: the work lanes W1 (shapes) and O6 (shadows) left owed
once both had landed — `ShapeStyle.shadow(_:)` (B-O6-3), and what
[Shapes (W1).md](<Shapes (W1).md>) lists under Owed. SwiftUI's side was
measured on macOS 15.8 by probes that read back pixels
([`Tools/SwiftUIProbes/Shadowed shape styles/`](<../../../Tools/SwiftUIProbes/Shadowed shape styles/>)).
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
