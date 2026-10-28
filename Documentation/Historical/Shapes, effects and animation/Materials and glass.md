# Materials and glass

*How SwiftUI's materials and glass came to a terminal: a material's surface
over a frosted copy of what is behind, glass as a material with a rim, and,
in October 2026, frost over the terminal's own pictures. Ids: O5 (refusal
review), O5-FROSTED, B-GLASS-1 to 7, the inactive-glass ruling of 2026-10-26.
The current design is in [Opacity as composition](<../../Colour and styling/Opacity as composition.md>)
and, for pictures, [Terminal graphics protocols](<../../Images and terminal graphics/Terminal graphics protocols.md>) §14.*

## In short

A material is a translucent surface laid over a frost of what is behind it:
the glyphs dropped and each cell the average of a box around it, the box set
by thickness or `.materialFrost(_:)`. Glass is a material's surface with a
highlighted rim drawn in the appearance's family; interactive glass lifts its
rim under the pointer; a container draws nearby glass as one shape. Over the
terminal's own pictures the frost is one blurred picture of everything behind
the glass, at `.materialFrostResolution(_:)`, laid under the text on Ghostty.
In an inactive window glass stays frosted, half way to opaque.

## How it unfolded

1. **2026-10-12, O5:** option (b) for Material and Glass. Lane GLASS built
   glass on 2026-10-18.
2. **2026-10-23 to 24, O5-FROSTED:** the frosted add-on, option (b), watching
   its cost (+22% on material frames, accepted on 2026-10-25 with a note to
   revisit; later passes took more than that back).
3. **2026-10-26, a day of glass over pictures:** frost over Kitty pictures,
   one backdrop blurred across them, pictures under text on Ghostty, the
   whole glass as one placement, a resolution in the terminal's pixels, and
   inactive glass kept frosty (the owner: "the effect shouldn't disappear
   completely - that just looks like a bug").

## For a future reader

- **Revisit the frost's remaining cost** (the owner's note of 2026-10-25).
- **The border gap under glass** was answered (GLASS-BORDER-GAP (a), 2026-10-27): a background the bordered view ends in fills the border's inset, `BackgroundBeneathBorderInset.swift`; `.backgroundStopsAtContent()` keeps it clear.

## The record

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
Example. **Shipped 2026-10-24** (owner ruling O5-FROSTED (b)): glass frosts
as a material one thickness thinner than the one whose surface it takes does
(decisions [VISUALS](#o5-frosted-a-material-frosts-what-is-behind-it)).

### B-GLASS-2. The rim is drawn in the appearance's family

*the rim of `View.glassEffect(_:in:)`*

A shape's own stroke is light lines whatever the appearance (decisions B-W1-2):
a shape is geometry the caller drew. Glass is the opposite case — the system's
material, chrome the theme owns — so its rim follows the appearance as a box's
border does (`ButtonFaceFamily(rimOf:)`), and glass and boxes are of a piece.
(Until 2026-10-24 a bordered button's face followed the appearance too; it now
follows the `ControlStyle`, filled by default — owner #19, 2026-10-23 — and
plain glass stays with the border.)

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
  kinds never joins: one shape has one surface; nor does glass still arriving
  (B-GLASS-6). `spacing` is cells, an `Int?`,
  as every interface measurement is (compatibility guide §2.1).
- **What is drawn:** the smallest rectangle round the members, in the first
  member's shape and glass; its rim lifts where the pointer is over any
  member. Each member draws its own part of it, where its own glass would be
  and behind its own content, so whatever lies between a member and the
  container — a background, a colour effect, an environment of its own —
  acts on its part as on glass alone; the container draws what lies between
  the members in the first member's environment, and as in front of what is
  behind them, as their parts are: over a background inside the container,
  under anything drawn there (a glyph, and the field it is drawn on). (The container first drew the whole shape
  behind its content, past all of that: an opaque background inside the
  container covered the joined glass from the second pass on — found in
  review.)
- **How:** each glass draws itself and tells the container where it is (a
  geometry marker it finds in what the content drew, `GlassEffectGathering`).
  The container keeps the part each glass it found joined draws, and those
  draw it. Where a drawing of the content draws them otherwise than it finds
  them — the pass a group forms, a glass joins one, leaves, moves or changes
  size — the container puts the walk back (`RenderWalkCheckpoint`) and draws
  its content again, knowing each part, as a coordinate space draws its
  readers again. Glass changes no layout, so the second drawing finds what
  the first did: every pass shows the glass joined as it stands. The second
  walk is paid only on a pass that changes how the glass is joined, and is
  the coordinate spaces' second walk, with its known cost: what a drawing
  does rather than registers — an `onChange` that fires, a task that starts
  — happens on both.
- **What it costs:** glass in a container declares a render side effect, as
  a view with a `.transition` does: the container learns of its glass only
  from glass that draws, and an arriving glass's record lasts only while it
  is asked for. So no memo keeps the container's subtree, nor any view above
  it up to the root, and every frame something draws — the focus breathing,
  any animation — draws that chain again, the container's content and its
  glass with it (found in review; not measured — an A/B is owed on a page
  with a container while the focus breathes). The remedy: the container's
  markers numbered by the dispatcher, which keeps a view's marker across
  passes, rather than by the drawing's count; a glass's telling and its
  arrival's asking recorded in the effect journal, so a served subtree makes
  them again and declares no side effect. A part a served glass drew stale is
  already settled by the container's second drawing. About half a day.
- **Where it stops:** a glass in a `ScrollView`, a `.clipped()` or
  `.clipShape(_:)`, a `.hidden()` view or an `.opacity(_:)` below 1 inside
  the container draws itself and joins nothing: a joined shape reaches past
  each member, and what the container draws between them would not be
  clipped, hidden or faded with it — the other members' parts would draw a
  shape open towards a glass not there (found in review: a hidden member's
  rim was drawn, and a faded one's glass at full strength). A faded glass is
  also a surface of its own, and one shape has one. A `List` does not stop
  it; a glass in a list row inside a container joins as though the list were
  not clipping it. Nothing else in TUI draws glass in lists.

**Alternatives.**

1. **No joining:** the container is its content. Free; a container would be
   a no-op, which rule 2 forbids.
2. **Join a pass late**, from who the last pass found joined, with no second
   walk: what the lane first shipped. Every change of who is joined showed one
   frame drawn as it was before — a group forming drawn apart, and a group a
   glass joined drawn apart for that frame, its members each alone (found in
   review). Free; a flicker on every join.
3. **The container draws the whole joined shape** behind its content, the
   members drawing no glass: what the lane first shipped. It skipped
   everything between a member and the container, so an opaque background
   inside the container covered the joined glass. Told what each member's
   content covers, it could draw over a background and under the content —
   an hour — but a member's colour effect or environment would still be
   skipped. Its one advantage: a member leaving under an animation took no
   part of the shape with it, its glass gone at once. Members drawing their
   parts cost a rasterizing of the joined shape per member, not one for the
   group.

**The fuller version:** the union of the members' own shapes rather than a
rectangle round them — each member's coverage, joined by a bridge across the
gaps closer than the spacing, its rim traced round the union's outline with
the box glyphs' junctions — closer to SwiftUI's blended shape, at cell
resolution. About a day and a half; and a list's rows stopping the container
as a scroll view does, an hour.

### B-GLASS-6. Glass arriving in a container fades in; an id keeps a glass that moves

*`View.glassEffectTransition(_:)`, `GlassEffectTransition` (`.matchedGeometry`,
`.materialize`, `.identity`), `View.glassEffectID(_:in:)`*

SwiftUI animates glass in a container as it comes and goes: `.materialize`
fades the glass in and out, `.matchedGeometry` grows a new glass out of a
nearby one's geometry (and shrinks a leaving one into it), and an id lets a
glass that moves from one view to another be animated from its old shape to
its new.

- **Arriving:** in a container, glass arriving under an animation — a view
  inserted in `withAnimation`, or `.identity` glass becoming glass — fades
  in with the animation (the animation store's arrival phase): its surface at
  that fraction of its opacity, and its rim's lines from half-way, since a
  glyph is drawn or not. `.matchedGeometry` (SwiftUI's default, taken as the
  default here too, unmeasured) arrives as `.materialize` does; `.identity`
  appears at once. Beside glass it would join, it fades in by itself and
  joins once it has arrived: a joined shape is drawn at one strength, and
  drawn at the arriving glass's it would fade out the glass already there, at
  the most present's it popped the new glass in a frame after it came (found
  in review).
- **Leaving:** with its view, whose own removal transition plays out what it
  last drew: alone, its glass; joined, its part of the joined shape, open
  where it joined. The glass that stays closes at once.
- **An id:** the arrival is kept by the id in its namespace rather than by
  the view, so a glass that moves to another view under an animation does
  not arrive again; without one it materializes in its new place.
- **Outside a container,** where SwiftUI's documentation does not use these,
  glass comes with its view: tracking an arrival there would keep every glass
  out of the render memo, which glass in a container already is.

**The fuller version:** the geometry — a new glass grown out of the nearest
glass within the container's spacing, a leaving one shrunk into it, and an
identified glass that moves drawn sliding from its old frame to its new — all
drawn by the container from the frames it kept, over the animation, with the
leaving glass kept until it has gone. About a day and a half; matched geometry
of views generally (refusal review O4) is its own lane.

### B-GLASS-7. A glass button is the bordered button on glass, its lines the rim

*`GlassButtonStyle` (`init()`, `init(_:)`), `GlassProminentButtonStyle`,
`PrimitiveButtonStyle.glass`, `.glass(_:)`, `.glassProminent`*

SwiftUI's glass buttons are "glass border artwork based on the button's
context". Here the button's context is the family table a bordered button is
drawn by (the family, `ButtonBorderShape`, `ControlSize`), so a glass
button is the bordered button of that table — its caps, its box at the larger
sizes, its focus breath and hover — on `glassEffect(_:in: .buttonBorder)`.
Its family is the control style where `.controlStyle(_:)` names one, and under
`.automatic`, the default, the glass's own rim family, from the appearance:
where every other control is filled by default (owner #19, 2026-10-23), a
filled glass button would cover the glass it is made of, and `.glass` would
draw the bordered button (decided 2026-10-24).

- **Lines faces** (the default appearances): the lines are drawn in the
  glass's rim ink (`_ButtonAppearance.glassRim`), lifted again under the
  pointer, and the label sits on the glass's surface, so what is behind the
  button shows through it tinted.
- **`.glassProminent`:** glass tinted the accent, its label bold in the
  palette's foreground — floored against the tinted surface, which tinted
  glass hands its content — as `.borderedProminent` is the prominent member
  of the bordered family. Focused, its lines breathe and its label keeps its
  colour: the accent a label breathes to is the tint it sits on.
- **Solid faces** (`.block`, or `.controlStyle(.block)`): the bordered
  button's own face, which covers the glass.

Each is a primitive style whose body is `Button(configuration)` with that
appearance, on glass: it focuses, presses and is triggered as a button is,
and is one focus stop. `Equatable`, unlike SwiftUI's, so the memo can compare
it.

**The fuller version:** a solid face made of the glass — its field the glass's
translucent surface and its caps the rim — which means a translucent face in
the procedural button body, whose caps' focus cycle spends its alpha against
the surface (`ButtonCapCycle`). Half a day.

### O5-FROSTED. A material frosts what is behind it

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

**Judgement calls.** The average is of encoded sRGB bytes, as every TUI
blend is; past the end of a line a cell is the surface, and a wide glyph's
later columns are the glyph's. A box reaches only what is behind the
material where it is composited (in the Example's and Stress's one-row
`ZStack`s, that row alone). Two claims with different boxes over one cell:
the larger frosts it. A material that does not appear active is opaque and
is not marked. A material over nothing but the page is its tint, unchanged.
