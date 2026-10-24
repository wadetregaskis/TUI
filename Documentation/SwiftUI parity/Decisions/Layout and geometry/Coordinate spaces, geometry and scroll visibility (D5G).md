# Completing the SwiftUI API: decisions from lane D5G

*Lane D5G implemented the owner's decisions A2 (coordinate spaces,
`GeometryProxy.frame(in:)`, anchors, `scrollTransition`) and A7
(`onScrollVisibilityChange`), by the design study
[the A2 design study](<../../../Historical/Geometry design study, A2 and A7 (2026-10-04).md>)
and the owner's answers to its §9. This file holds the judgement calls the
work reached that those answers did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-D5G-n — needs your decision.** Nothing has shipped for these.
- **B-D5G-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-D5G-n — declined.** With the `parity-map.json` reason.

Measurements are SwiftUI on macOS 15 (probes in the session notes,
`D5G/probe`).

## B. Shipped the safe option

### B-D5G-1. Scroll visibility: a removed view is not reported; a row windowed out of a lazy stack is

*`View.onScrollVisibilityChange(threshold:_:)`*

Measured: every observed view reports once when it first appears, shown or
not, then at each crossing of its threshold (a fraction AT the threshold is
shown, so `threshold: 0` reports every view shown); a view in no scroll view
is reported shown wherever it is laid out; and a view removed from the tree
reports nothing. SwiftUI's lazy stacks destroy a row that scrolls out of their
window, and it reports nothing until it is made again.

What ships follows all of that except the last: a row a TUIkit lazy stack stops
drawing is still in the tree (its state is kept), and is reported hidden if it
was shown — option 1 of A7 ("fires `false` for a marker that has vanished").
A removed view is told nothing, as in SwiftUI; the two are told apart by
whether a windowing container still retains the identity
(`StateStorage.retainedSubtrees()`).

**Fuller version:** none wanted; the alternative would be to stay silent for a
windowed-out row as SwiftUI's destroyed one does, which leaves an app that
stopped a player on `false` playing it off screen. Nothing to price.

### B-D5G-2. A view whose marker reaches no owner is not located; a `Table` cell's now does

*`GeometryReader` asking any space but its own, `onScrollVisibilityChange`,
`onGeometryChange` with a non-local space, anchors — under a container that
drops its content's hit-test regions; inside a `TableColumn`'s cell view
until 2026-10-06*

**A `Table` cell (changed 2026-10-06, the tables lane's follow-up).** A
`Table` composes each row's cells as text, and carries a view cell's regions
up with the row (`_TableRowPayload`, B46) — its geometry markers among them
now, which it used to leave behind. So a view in a cell is found where its row
draws it: a reader there is answered exactly, and an `onGeometryChange`
reports that place, its first report included (`CoordinateSpaceTests`). A
cell still carries no geometry origin (`Table.cellContext`), so a reader's
own prediction there is the origin: the frame it first shows costs the root a
second walk of the scene, after which it reads what was found (one correction
on its first frame, none after, in the test's static table; a frame its row
moves on, unmeasured, would cost another). Before, nothing found the cell, and
a reader there was told the origin on every frame. A space declared inside a
cell starts an origin of its own and is answered exactly, as before. A
`ScrollView` inside a cell has no origin carried to it either, so it does not
predict for its own `.scrollView` readers: they are corrected — the scroll
view's subtree drawn a second time — on every frame they move. An open menu's
content in a cell (a layer, not a region) still leaves its markers behind: it
is found where the menu is drawn, not the cell.

**Elsewhere:** a marker reaches an owner only through the buffers its
ancestors draw, so a view is not located under any container that redraws its
content's lines into a new buffer without the hit-test regions in them, which
carry the markers (a bare `FrameBuffer(lines:)`, in an app's own `Renderable`
as in the framework; `ContainerPayloadAudit` guards the framework's
containers for regions). Such content carries an origin down as any content
does, so a reader there is told where the containers above it would place it,
and nothing checks it; a reporter is told the origin, and a pointer converts
in the global space (B-D5G-7). A window bar's content is located: the bars are
rows of the frame the scene root reads (A28), so a reader in a `.toolbar` item
is found and corrected as a reader on the page is (`GeometryWindowChromeTests`).

**Fuller version, for a cell:** carry each cell's origin down to it (the
row's line and the column's start), so a reader there predicts exactly and
the first frame needs no second walk. About half a day, on `Table`'s hot path,
so with the `table`/`tables-scroll` A/Bs.

### B-D5G-3. A reader inside a presented surface asking `.global` costs the scene a second walk on the frame the surface shows or moves

*`GeometryProxy.frame(in: .global)` (and any name nothing declared) inside a
sheet, popover, menu or alert*

A presentation's surface is placed by the compositor — centred, flipped above
its anchor, clamped on screen — which the window runs inside the scene's walk
(A28's chrome host composites the content's layers between its bars), so the
frame the scene root reads has every surface in place. A reader in one is
found with the page's readers and corrected the same way: the prediction does
not follow the compositor's placement, so the surface's first frame, or the
frame it moves, walks the scene again (`RenderLoop.renderContent`) — and draws
its readers from where they are (`GeometryWindowChromeTests`). Named spaces
declared inside the surface are exact in the same frame without it; a name
declared on the page does not reach into a presentation (nor does SwiftUI's).

(Before the window's chrome moved into the scene, the composite ran after the
root's correction, and such a reader was right only from the frame after.)

**Fuller version:** carry the compositor's placement down as an origin, so a
reader in a surface is predicted and the scene is not walked again; the
compositor's placement run before the surface's content draws. About a day.

### B-D5G-4. Side effects inside a corrected subtree run for both drawings

*every owner's correction: `coordinateSpace(_:)`, a scroll view, the root*

A correction draws the owner's subtree once more in the same walk. The
registrations the first drawing made are put back first
(`RenderWalkCheckpoint`: mouse and marker ids, `onChange` indices, key
handlers, preferences, what a memo recording around the owner kept of them,
and the render cache below the owner), so the second drawing takes the same
ids and indices and nothing is registered twice. A scroll view that draws its
band again at the offset the frame settled on puts the same things back but
the cache. The registries that take a second registration of the same thing
as one — the focus ring, keyboard shortcuts, status-bar items, drop targets
— are not put back: a view only the first drawing drew (a row of a band the
scroll view replaced) stays registered for that frame. What
the first drawing DID cannot be put back: an `onChange` that fired runs again
against the first drawing's value — on a reader's first frame, an
`.onChange(of: proxy.frame(in: …).minY)` fires once from the guess to the
answer, where SwiftUI fires nothing (pinned as a known issue,
`CoordinateSpaceTests.correctedSubtreeSideEffects`). It is the known issue the
app header's correction re-render had (`RenderPassScopeTests`) until the
window's chrome was adopted a frame late, scoped to the subtree, and made only
as often as a reader's answer moves — which the prediction rungs (design study
§10 steps 5–7) exist to make rarely. The scene root's correction is not scoped:
it walks the whole scene again (`RenderLoop.renderContent`, the per-walk
registries reset as for any walk, the window's bars laid out against the rows
the first walk was), so on a frame a `.global` reader's prediction misses,
every effect in the scene runs for both walks — the one walk of the scene a
frame after the first ever repeats.

**Fuller version:** stage a walk's side effects and adopt only the last
drawing's. Days, across every side-effecting modifier.

### B-D5G-5. `CellRect` gains `minX`, `minY`, `origin` and `size` — and still no `midX`/`midY`

*`CellRect`, the cell form of `CGRect`*

`proxy.frame(in: .named("scroll")).minY` is how SwiftUI code tracks a scroll
offset, and it did not compile: `CellRect` had `x`, `y`, `maxX`, `maxY`. The
four added are `CGRect`'s names for values `CellRect` already has. The
midpoints stay out, for the reason recorded on `AlignmentID` (a midpoint
floored before it is subtracted from another moves one in four centrings by a
cell).

### B-D5G-6. `CoordinateSpace` and `NamedCoordinateSpace` are not `Sendable`, and `hasGlobalPosition` is gone

*`CoordinateSpace`, `NamedCoordinateSpace`, `GeometryProxy.hasGlobalPosition`*

`CoordinateSpace.named(AnyHashable)` holds any `Hashable`, and nothing says the
value inside is safe to share; SwiftUI's two types are not `Sendable` either
(their symbol graph lists `Equatable` and `Hashable`). TUIkit's
`CoordinateSpace` was `Sendable` while it had only `.local` and `.global`;
nothing in TUIkit relied on it.

`hasGlobalPosition` existed to say when `frame(in: .global)` had fallen back to
the local frame. `.global` is exact now, so the property answered nothing, and
pre-1.0 it is removed rather than kept true.

### B-D5G-7. A pointer location in a named space converts with the frame the event arrives over

*`DragGesture(coordinateSpace: .named(…))`, `SpatialTapGesture`,
`onTapGesture(count:coordinateSpace:perform:)`,
`onContinuousHover(coordinateSpace:perform:)`*

The view's place in the named space is found by the space's owner when the
frame is drawn, and an event between two frames is converted with it — the
frame the user was looking at. A view handling the pointer in a named space
stamps a marker each frame and so declines the memos above it (its conversion
is made per frame); in `.local` and `.global` nothing changes. A name nothing
declares converts in the global space, as SwiftUI's does — and so does a name
no owner found the view in (its marker dropped on the way up: a `Table` cell),
for a hover or mouse handler as for a gesture.

### B-D5G-8. Scroll transitions: the default threshold is taken as `.visible`, unmeasured

*`View.scrollTransition(_:axis:transition:)`,
`scrollTransition(topLeading:bottomTrailing:axis:transition:)`,
`ScrollTransitionConfiguration` (`.interactive`, `.animated`)*

What ships: a view's phase follows where it is in its scroll view's viewport
— the edge it is nearer (`.topLeading` above the middle, `.bottomTrailing`
below) until it is in as far as the configuration's threshold, then
`.identity`. `.interactive` interpolates the EFFECT between the edge phase's
and the identity phase's by how far in the view is (measured: SwiftUI calls
the closure for all three phases and does the same), paced by the curve;
`.animated` switches at the threshold and animates with its animation;
`.identity` never changes. Thresholds are depths into the viewport in cells
(`.visible(a)` is `a` of the view, `.centered` is the view's middle at the
viewport's, `inset(by:)` moves one towards the middle). The position is the
owner's answer 5: predicted, and corrected by the scroll view when wrong.

Not measured: the threshold SwiftUI uses when none is set. A pixel probe of
an offscreen `NSHostingView` (session notes, `D5G/probe/st2.swift`) did not
agree with itself — the band it found partly faded did not move with the
scroll offset it was given — so the default is taken as `.visible`, the point
the documentation of `threshold(_:)` calls "fully visible".

**Fuller version:** a probe that reads the effect without pixels — an effect
whose `animatableData` is observable — to settle the default; an hour, and a
one-line change if it differs.

**Done 2026-10-19 (lane SCROLL).** SwiftUI's configurations carry their
threshold as data, and a `dump` of them reads it: `.interactive` and
`.interactive(timingCurve:)` start at `.visible` (1.0), but `.animated` and
`.animated(_:)` start at `.visible(0.5)`, half the view, and `animation(_:)`
keeps it. Driven through the scroll view, each default behaves exactly as the
threshold it holds and unlike the other, at four offsets
(`Tools/SwiftUIProbes/Scroll transitions/`). So an animated transition now
switches with half the view in, which only a view taller than one line can
show; the interactive default was right.

### B-D5G-9. A `List`'s rows are not placed by the prediction, and a `List` does not own `.scrollView`

*`GeometryReader` (or `scrollTransition`) in a `List` row asking `.scrollView`,
a named space, or `.global`*

The prediction rungs convert the stacks, grids, layouts and the scroll view
(design study A2, rungs 1 and 2). A `List` renders its rows on demand into a
window under its chrome, and its rows are told the list's own origin: what
the window and the chrome add is carried by each reader's residual, so a
static list costs a correction on a reader's first frame, and scrolling a
list with readers in its rows costs its owner one more drawing per frame —
G1's rate, never a wrong answer. `.scrollView` inside a `List` row is
answered by the nearest `ScrollView` around the list (or the global space),
where SwiftUI's list is itself the scroll view. A `Table`'s cells are
located, from their first frame's correction on (B-D5G-2).

**Fuller version:** the list places each drawn row at `contentTop + (line −
drawn offset)` in its window, as `attachRowPayloads` already does for the
rows' regions, and owns `.scrollView` for its rows as the scroll view does —
a day, on the list's hot path, so with the `table`, `tables-scroll` and
`session/inbox` A/Bs.

**The ownership half: built (2026-10-19, lane LISTS2).** A `List` draws its
frame as the owner of `.scrollView` and `.scrollView(axis: .vertical)`
(`RenderContext.drawingAsVerticalScroller`), as a `coordinateSpace(_:)`
declaration owns its name: a reader in a row is answered in the list's
content window, inside the border and below a borderless title, and where one
drew from an answer that turned out wrong the walk is put back and the frame
drawn once more. A list with nothing asking pays the walk's checkpoint and a
test of the waiting count, every frame — A/B owed on `table`,
`tables-scroll` and `session/inbox`. **The placement half is not built:** the
rows are still told the list's origin, so a scrolled list with a reader in
its rows draws once more a frame (G1's rate); placing each row before it is
drawn needs its line in the window before the window walk has settled it,
which the walk renders rows to find — about a day more, with the same A/Bs.

### B-D5G-10. The prediction's third rung converts seven composers; the root's centring and five more containers are left to the residual

*Where a reader inside them is told it is before it draws (the correction
rate only — never the answer)*

Converted (design study A2 §10 step 7, the owner's answer 6): `.padding`, a
bordered or titled box (`.border()`, `ContainerView` and what is built on
it), `.frame`'s alignment, `.overlay`/`.background` and the preference
layers, `ZStack`, `.offset` and `.position` — each places its content before
drawing it, measuring the content where it aligns by size (memo hits: the
same measures its own `sizeThatFits` took). The ones that align by size also
move a `.gradientExtent(.subtree)` ramp, which they did not before; `.offset`
and `.position` move only the geometry origin, keeping the colour where the
layout put the view (the extent is TUIkit's own, so SwiftUI has no answer
to measure; this keeps today's colours under an offset).

Left to the residual: the scene root's centring of content smaller than the
screen, `safeAreaInset`, content margins, `TabView`, `NavigationSplitView`
and `SplitView`, a `List`'s rows (B-D5G-9). Each adds an offset that is the
same frame after frame for a given layout, so a reader under it costs one
correction on its first frame and none after, until that container's own
layout changes.

**Fuller version:** the root, by measuring the scene before drawing it on
frames with readers — a measure of the whole tree per frame, which on the
deep and fanout shapes is a cost a reader somewhere should not impose on
everything; the other five as the List is priced (a day, with their own
A/Bs), when the Stress counter shows a shape paying for them.

