# Completing the SwiftUI API: lane GLASS's judgement calls

*Lane GLASS, 2026-10-18, shipped the owner's ruling on refusal review
[O5](<../Refusals re-examined, wave 17 (2026-10-03).md#o5-materials-and-glass-materialactiveappearance-plus-differentshape-material-w13s-material-backgroundmaterial-p14s-glass>)
(2026-10-12: option (b) for Material and for Glass) for glass: `Glass`,
`View.glassEffect(_:in:)` and `DefaultGlassEffectShape`. The materials shipped
first (`Material.swift`, Deliberate deviations C5); glass is the same
translucent surface, with the rim option (c) of the review describes. Where the
work met a judgement call the ruling did not settle, the safe option shipped and
is written up here, in the three parts the other lanes use: A needs a decision,
B shipped the safe option (with the fuller version and its price), C declined
with a parity-map reason. SwiftUI's side is the macOS 26.2 SDK's declarations
and Apple's documentation, read from the SDK's symbol graphs (the session's
SwiftUI graphs come from the macOS 15.5 SDK and have no glass); this Mac runs
macOS 15.8, so nothing here was measured.*

## B. Shipped the safe option

### B-GLASS-1. Glass is a material's surface with a highlighted rim, behind the view

*`Glass` (`.regular`, `.clear`, `.identity`, `tint(_:)`, `interactive(_:)`),
`View.glassEffect(_:in:)`, `DefaultGlassEffectShape`*

SwiftUI's glass refracts and blurs what is behind it and lays foreground
effects over the view. The ruling settled the surface (a material's: a palette
surface at a fraction of its opacity, no blur); it left open what makes glass
look like glass rather than a material, and where that goes.

- **The surface:** `.regular` is the regular material's (0.65 of the page's
  surface), `.clear` the ultra-thin one's (0.35) — the two ends SwiftUI's
  documentation describes, one that keeps content legible by itself and one
  that wants a dimming layer — so there is one table of opacities, not two. A
  `tint(_:)` makes the surface that colour at the same opacity. Glass that does
  not appear active is opaque, as a material is (`MaterialActiveAppearance`).
  `.identity` draws nothing.
- **The rim:** the shape's outline, in the border's ink lifted once
  (`Palette.hoveredForeground`, the step a hovered line takes, so it shows on
  every palette and depth) — a highlighted border, glass's edge. Tinted, the
  tint lifted.
- **Where:** behind the view, filling its frame, as SwiftUI anchors the glass
  to the view's bounds; layout is untouched. The rim's glyphs, and the
  surface's quadrant corners, show through the view's blank cells
  (`FrameBuffer.claimsShowingGlyphs(of:)`, the rule `background(_:in:)` already
  keeps for a shape's corners), so `.padding().glassEffect()` — SwiftUI's own
  example — puts the rim in the padding.

**Alternatives.**

1. **No rim** (option (b) read strictly): glass would be a material with
   another name. Free; it was the rim that made the review offer (c).
2. **A rim that takes cells of its own**, the view grown by one each side:
   the rim always shows, but every glass changes its view's size, which
   SwiftUI's never does. An hour.
3. **A rim over the view**: always shows, and hides the view's outermost
   glyphs. An hour.

**The fuller version:** the frosted add-on the O5 ruling offers for materials —
drop the glyphs beneath, give each cell the average of its neighbours'
effective colours and tint that — applies to glass unchanged, as one more
surface treatment. About two days, offered once the owner has seen this in the
Example.

### B-GLASS-2. The rim is drawn in the appearance's family

*the rim of `View.glassEffect(_:in:)`*

A shape's own stroke is light lines whatever the appearance (decisions B-W1-2):
a shape is geometry the caller drew. Glass is the opposite case — the system's
material, chrome the theme owns — so its rim follows the appearance as a
bordered button's face does (`ButtonFaceFamily`), and glass and buttons are of a
piece:

| family | the rectangle family | any other shape |
|---|---|---|
| lines (`.rounded`, `.line`, `.heavy`, `.doubleLine`) | a box of the style's lines; a light style's corners `╭` where the shape is rounded and `┌` where not, a heavy or double one its own; one row, the ends `( … )` or `[ … ]` | its border rasterized, a column wide (`strokeBorder(lineWidth: 1)`) |
| Braille | a dotted outline of the shape, as thick as the appearance says | the same |
| solid (`.block`) | a band: the surface's outermost cells in the rim's colour; one row, its ends | its border rasterized |
| blank | none: the surface alone | none |

One row tall the rim is its ends and not `(─Flag─)`: the row between them is
the view's, and a line under its blank cells would strike it through.

**Alternatives.** Light lines always, as a shape's stroke (B-W1-2): consistent
with shapes, out of step with the boxes and buttons beside the glass. Free.

**The fuller version:** none needed. A heavy or double rim round a rounded
shape keeps that style's square corners, because neither glyph set has rounded
ones; a band's corners are the surface's own quadrants already.

### B-GLASS-3. Interactive glass lifts its rim under the pointer

*`Glass.interactive(_:)`*

SwiftUI's interactive glass reacts to touches and the pointer — it scales,
bounces and shimmers. Here interactive glass lifts its rim a step further
while the pointer is over it, and back when it leaves. It listens as a hover
observer (`MouseEventDispatcher.registerHoverObserver(in:_:)`), so a control
inside keeps its own hover, and it takes no click and no focus: it is a look,
so nothing becomes reachable only with a mouse. In a disabled subtree it does
not react, as `.onHover` does not. Whether the pointer is over it is kept at a
child identity of the glass's own, so marking it live keeps no other view's
`@State` alive (decisions A40's finding).

**The fuller version:** react to a press as well (a flash of the surface, a
frame or two), and light the rim while a control inside holds the focus — a
"focus within" answer the focus system does not publish today. Half a day.

### B-GLASS-4. Tinted glass is the ground of what is on it

*`Glass.tint(_:)` under `View.glassEffect(_:in:)`*

A control that floors its ink's contrast does it against the surface it lands
on (`EnvironmentValues.enclosingSurface`), and a text field steps its well off
it. On tinted glass that surface is the tint, so the glass hands its content
the tinted surface, composited over the surface the glass is drawn on, noted
with the render cache like any applied environment value. Untinted glass is the
page's own colour and leaves the ground as it was.

**The fuller version:** untinted glass over something that is not the page —
what is behind is not known where the glass draws, so the page is the best
estimate it has, and the default already. Nothing owed.

### B-GLASS-5. A container draws glass that comes near as one shape, round all of it

*`GlassEffectContainer(spacing:content:)`, `View.glassEffectUnion(id:namespace:)`*

SwiftUI's container renders the glass inside it together: shapes blend into
one another as they approach — sooner the larger the spacing — and a union
is one shape round all of its members. A cell is joined or not, so here:

- **Who joins:** two glasses of the same kind (variant, tint and
  interactivity) when they touch or overlap, or come fewer than `spacing`
  cells apart — at the spacing itself, the gap an `HStack` of the same spacing
  leaves, they stay apart, as SwiftUI's at rest do — and every glass of one
  union, wherever it is, when they also share a kind of shape. Glass of two
  kinds never joins: one shape has one surface. `spacing` is cells, an `Int?`,
  as every interface measurement is (compatibility guide §2.1).
- **What is drawn:** the smallest rectangle round the members, in the first
  member's shape and glass, behind the container's content; its rim lifts
  where the pointer is over any member.
- **How:** each glass draws itself and tells the container where it is (a
  geometry marker it finds in what the content drew, `GlassEffectGathering`).
  The container keeps who was in a joined group; next pass they leave their
  glass to it. So a group forms one pass after its members come together —
  the change of who is joined is a state write, which draws that next pass —
  and a member that leaves is drawn apart at once. Glass in a container
  declares a render side effect, so no memo keeps a subtree with one.
- **Where it stops:** a glass in a `ScrollView` inside the container draws
  itself, since what the container draws is not clipped to the viewport. A
  `List` does not stop it; a glass in a list row inside a container joins as
  though the list were not clipping it. Nothing else in TUIkit draws glass in
  lists.

**Alternatives.**

1. **No joining:** the container is its content. Free; a container would be
   a no-op, which rule 2 forbids.
2. **Join in the same pass**, drawing the content twice when who is joined
   changes: no frame with the members apart, at the price of a second walk of
   the container's content on each change — and a second walk re-registers
   every handler and marker in it (`RenderWalkCheckpoint`). Half a day.

**The fuller version:** the union of the members' own shapes rather than a
rectangle round them — each member's coverage, joined by a bridge across the
gaps closer than the spacing, its rim traced round the union's outline with
the box glyphs' junctions — closer to SwiftUI's blended shape, at cell
resolution. About a day and a half; and a list's rows stopping the container
as a scroll view does, an hour.
