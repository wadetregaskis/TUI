# Completing the SwiftUI API: decisions from lane D5G

*Lane D5G implemented the owner's decisions A2 (coordinate spaces,
`GeometryProxy.frame(in:)`, anchors, `scrollTransition`) and A7
(`onScrollVisibilityChange`), by the design study
[`SwiftUI-API-completion-design-A2-geometry.md`](SwiftUI-API-completion-design-A2-geometry.md)
and the owner's answers to its §9. This file holds the judgement calls the
work reached that those answers did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

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

### B-D5G-2. A view inside a `Table` cell is not located

*`GeometryReader` asking any space but its own, `onScrollVisibilityChange`,
`onGeometryChange` with a non-local space, anchors — inside a `TableColumn`'s
cell view*

A `Table` composes each row's cells as text (`rowCells(for:columnWidths:context:)`
returns strings), which drops every hit-test region a cell view drew — buttons
as well as the geometry markers these read. So a view in a cell is answered as
though no owner found it: a reader with what was last found for it, which is
the origin `(0, 0)` until something does; an `onGeometryChange` asking another
space likewise, still called once the frame is done (its first report
included); a scroll visibility observer never measured, nor reported (a
registration whose marker reached no owner and not the frame counts as none).
`List` rows, eager and lazy stacks, grids, custom layouts, `.offset`, scroll
views and presentations all carry markers (`GeometryMarkerTests`).

**Fuller version:** carry each cell's markers (and its regions) through the row
composition at the cell's column — a `[HitTestRegion]` beside the row's claims
in `renderRowUncached`. About half a day, on `Table`'s hot path, so with the
`table`/`tables-scroll` A/Bs.

### B-D5G-3. A reader inside a presented surface asking `.global` is told the right answer from the next frame

*`GeometryProxy.frame(in: .global)` (and any name nothing declared) inside a
sheet, popover, menu or alert*

A presentation's surface is placed by the compositor — centred, flipped above
its anchor, clamped on screen — after the scene has rendered and the root has
corrected its readers. Its readers are answered from the composited frame, and
when one was told something else the render loop asks for another frame
(`RenderLoop.render`, `resolveRemaining` after the composite), so the surface's
first frame, or the frame it moves, draws its readers from where they were.
Named spaces declared inside the surface are exact in the same frame; a name
declared on the page does not reach into a presentation (nor does SwiftUI's).

**Fuller version:** place each layer as the compositor will before the root's
correction, so the correction covers them; that is the compositor's placement
run twice per frame with readers inside a surface. About a day.

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
`CoordinateSpaceTests.correctedSubtreeSideEffects`). It is the app header's
correction's known issue (`RenderPassScopeTests`), scoped to the subtree, and
made only as often as a reader's answer moves — which the prediction rungs
(design study §10 steps 5–7) exist to make rarely.

**Fuller version:** stage a walk's side effects and adopt only the last
drawing's — the design the header correction is waiting on too. Days, across
every side-effecting modifier.

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
no owner found the view in (its marker dropped on the way up: the app header's
content, a `Table` cell), for a hover or mouse handler as for a gesture.

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
where SwiftUI's list is itself the scroll view. A `Table`'s cells are not
located at all (B-D5G-2).

**Fuller version:** the list places each drawn row at `contentTop + (line −
drawn offset)` in its window, as `attachRowPayloads` already does for the
rows' regions, and owns `.scrollView` for its rows as the scroll view does —
a day, on the list's hot path, so with the `table`, `tables-scroll` and
`session/inbox` A/Bs.

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

