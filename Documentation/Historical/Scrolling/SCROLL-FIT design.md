# SCROLL-FIT: content-sized views in scroll content, built on the pull

*The design for steps 2 and 3 of the owner's SCROLL-FIT ruling of 2026-11-11: how a scroll view
draws only the rows it shows wherever they sit in its content, and what changes when
content-sized views stop filling or capping at the visible area. First written 2026-11-11
against `main` at 59c9207dc around a relay of the scroll window (commit b5481ecf2), from step
1's measurements (`ScrollFitBaselineTests`, commit 1d8296c66; findings in
`Documentation/Working notes/plan/SCROLL-FIT-baseline.md`). Revised the same day around the
pull (design C, NESTED-LAZY-PULL) after the owner's A-SCROLLFIT-3. Ids: A-SCROLLFIT-1 to 3
(answered), A-SCROLLFIT-4 and 5 (for the owner), B-SCROLLFIT-1 to 18 (decided here; 1 and 4
superseded by the pull, 2 renamed).*

## In short

The scroll view keeps its position as an **anchor**: the identity of a row in its content,
plus how many lines of that row are hidden above the viewport. To draw, it asks its content to
fill the viewport outward from the anchor. Each container routes the request to the child the
identity chain names, which costs O(1) a level and builds nothing. It lets that child fill
first, then places its other children outward, up and then down, until the viewport is full.
Each container answers only for its own children, so a lazy stack's total height, a footer
below a million rows, or a section off screen is never measured.

Containers implement one package protocol, `ScrollPlacing`, which refines the `LayoutPlacing`
that ships. Single-child wrappers and an app's own views forward the request for free. Eager
containers (`VStack`, `HStack`, `Grid`) build every child and paint only the rows the fill
reaches. A view that does not conform is a leaf drawn whole, and the anchor inside it is a line
offset.

The SwiftUI APIs that speak in absolute lines (`ScrollPosition(y:)`, `onScrollGeometryChange`,
the scrollbar thumb, "N more") read a derived offset. That offset is exact for fixed-pitch and
eager content, and an estimate elsewhere, carried by dead reckoning so that it stays steady.
Every other movement (the wheel, keys, Page Down, `scrollTo`, a focus jump) is exact, at a cost
of O(visible).

The relay version's other parts carry over:

- build only the visible rows in `List`, `Table`, `TextEditor`, the lazy stacks, and the
  non-lazy containers A-SCROLLFIT-1 names;
- content-sized defaults behind one switch;
- a tall table's header and horizontal bar pinned to the visible area;
- keyboard reveal through the outer scroll view;
- `.fixedSize` on the measure ladder;
- A-SCROLLFIT-2's horizontal case.

Nine lanes take about 24½ lane-days (20 to 32), about five weeks of one landing stream.
`NavigationSplitView`'s height (L0) runs separately and is left out. Two questions for the
owner remain: how far a `scrollTo` searches for an id nested in rows never built, and how
`FlowLayout` finds its line breaks.

## The problem

**The ruling (SCROLL-FIT, in [the owner's decisions of 2026-11-08](<../SwiftUI parity process/The owner's decisions of 2026-11-08.md>)).**
Along an axis its parent leaves unbounded, a view whose size depends on its content takes its
content's size by default. That axis is a `ScrollView`'s scroll axis, under `.fixedSize`, or in a
popover that sizes to its content. Space-fillers take their minimum. `.frame(height:)`,
`.frame(maxHeight:)` and `.containerRelativeFrame(.vertical)` stay available as opt-outs. Until
this ships, TABLE-TALL's (a) holds (5cec75080: a table is capped at the visible height).

**The answers that followed (same file).**

- **A-SCROLLFIT-1, narrowed (a).** A container stays eager (builds every row, as SwiftUI's
  does) only where SwiftUI has a lazy counterpart and is itself eager: `VStack`/`HStack` and
  `Grid`. `GroupBox`, `DisclosureGroup`, `FlowLayout`, a `.columns` `Form` and a `Section`'s
  content outside a `List` build only their visible rows past a threshold, accepting that an
  off-screen row's `onAppear`/`.task` runs when it scrolls in.
- **A-SCROLLFIT-2 (b).** `ScrollView(.horizontal)` proposes its own height. Tables and lists fit
  it and scroll themselves; content still taller keeps today's vertical scrolling.
- **A-SCROLLFIT-3 (c).** Build the pull, not the relay.

**What step 1 measured** (60 × 24, debug; the table in the baseline report):

1. Most content-sized views are not content-sized.
   - `List`, all three kinds, and `GeometryReader` take 4,096 lines in any scroll view. That is
     the first rung of the measure ladder (`naturalExtentStartingBudget`), and it leaves thousands
     of blank lines.
   - `TextEditor`, a nested `ScrollView`, the grouped `Form` and the split views are
     max(content, viewport) up to 4,096 lines, and two of them stacked split the viewport 12/12.
   - `Table` is capped at the viewport (`scrollViewportCap`, TABLE-IN-SCROLL-HEIGHT).
2. **The containers that already fit their content build every row on every frame.** These are
   `GroupBox`, `DisclosureGroup`, `Grid`, `FlowLayout`, `TabView`, `NavigationStack` and the
   `.columns` `Form`. At 10,000 rows a case takes 1.5 to 14 s in debug.
3. **Windowing exists only at the content's origin.**
   - `LazyVStack` windows itself only when it is the scroll view's direct content (or sits under a
     `Section` or `.padding`), and even there its first frame builds every row twice.
   - `LazyHStack` never windows.
   - `Table` and `List` window only against their own viewport, so drawn whole they would build
     every row. That is why TABLE-IN-SCROLL-HEIGHT capped the table: drawn whole, a 10,000-row
     table's scroll step took 144 ms, against 4.0 ms capped.
4. **`.fixedSize` takes one measure at `max(offered × 64, 4096)`** (`_FixedSizeView.idealExtent`).
   It reads "filled the budget" as "greedy", so every view at 10,000 rows falls back to the space
   it is offered (23 lines), after building 4,153 table rows to show 20.
5. **`NavigationSplitView` reports a height of one line**, flexible
   (`_NavigationSplitViewCore.sizeThatFits`). L0 fixes it separately.
6. **`ScrollView(.horizontal)` also scrolls vertically.** `resolveScrollbars` and the render
   never check `axes.contains(.vertical)`, so its vertical axis is unbounded too.
7. **The focus reveal at launch scrolls a title away** above a focused table or list as tall as
   the viewport. `FrameBuffer.revealTarget` reveals the whole control on arrival.

**A nested lazy stack today** is design D: it is drawn whole, its measure walking every row its
budget reaches (`anchoredSizeThatFits`, told it is nested by `RenderContext.scrollContentOriginDepth`
and `leaveScrollOrigin()`). That is correct, and its price was measured when it landed (series
total, 49cbee2b3 to 8c3bc1e62, paired A/B, release, 2026-09-27): `grouped-feed` +706.8%, 17.0 →
137.2 ms a frame and RSS 20.1 → 84.2 MB; `grouped-feed-uniform` +427.4%; `headed-log` +52.9%. The
owner accepted it as the price of a correct drawing and ruled the pull as its follow-up ("land D
first … then pursue C"). The story is
[Measuring a scroll view's content](<Measuring a scroll view's content - the overflow check, wide rows and nested lazy stacks.md>);
the design is [Locating things without drawing them](<../../Layout and scrolling/Locating things without drawing them.md>)
§3 (anchors), §5b (one traversal, seekable), §6b (the scroll view pulls, the stacks answer) and §8
(costs).

## Superseded: the relay

The first version of this document (b5481ecf2) passed the scroll view's window, a range of the
content's lines, down through every container that places a child. Each container moved the
window into the child's coordinates by the child's measured y (B-SCROLLFIT-1) and handed a
still window to a child wholly off screen so its memo held (B-SCROLLFIT-2). A `scrollTo` named
its holder so the relays built it (B-SCROLLFIT-4). It estimated about 9½ lane-days.

The owner was told the pull is technically superior and more effort, and answered "If that's
accurate, then do Pull" (A-SCROLLFIT-3, (c)). What the relay could not do, and the pull does:

- **No total is needed to draw.** The relay placed a child by its y, which is the sum of every
  sibling's height above it. So every consumer had to report a total, an estimate for variable
  rows, and content *below* a variable list moved as that estimate settled. Under the pull, a
  container visits only the children the fill reaches, and a total is asked for only by the
  scrollbar and the absolute-offset readings.
- **A far `scrollTo` or focus jump is exact at about constant cost.** The target becomes the
  anchor, and the frame is filled around it. The relay had to turn the target into a content
  offset through every level's estimated heights, then window back down to it.
- **One engine.** The relay needed a band assembler and a still-window rule in every relaying
  container. The pull has one outward walk, shared by every container, which answers only how
  its own children are laid out.
- **It is the design already ruled for** on 2026-09-26, and the anchored lazy stack, the anchor
  ladder and the top-row hold that ship are its pieces.

The caveats were stated and accepted. The scrollbar thumb and "N more" stay estimates for rows
of varying height either way. A list inside an app's own `Layout` needs a placement protocol
(B-SCROLLFIT-13).

Kept from the relay, under the pull: the arithmetic of `ScrollWindowRelay` (it becomes the
forward shape), the still window for subtrees off screen (now the off-band request), fixed pitch
as arithmetic and variable pitch as an estimate (B-SCROLLFIT-3), and everything in step 3
(B-SCROLLFIT-5 to 10).

## 1. The pull (step 2)

### 1a. What exists, and what each piece becomes

| Piece | Where | What it does today | Under the pull |
|---|---|---|---|
| `LayoutPlacing` | `TUIView/Rendering/LayoutPlacing.swift` | §5b's seekable shape: `placementCount`, `placement(at:)`, `ordinal(of:)`, `uniformExtent`. One conformer, `_VStackCore` (`StackLayoutPlacing.swift`). | Refined by `ScrollPlacing` (1c). `placement(at:)`'s y is a prefix from child 0, so the pull never asks it of a child it does not visit. |
| `ViewIdentity.childStep(below:)` | `TUICore/Rendering/ViewIdentity.swift` | Reads, without building anything, which child of a container leads to an identity: an index or a key. | How every level routes the anchor, a focus target and a located seek (1b). |
| The anchored window | `StackAnchoredWindow.swift`, `StackAnchoredMeasure.swift`, `StackWindowState` | Variable rows past 256: the anchor (`anchorOrdinal`, `anchorKey`, `anchorOffsetWithin`), outward fill, rows never built estimated at the running pitch. Takes the scroll view's absolute offset and walks the *difference* in row space (`advanceAnchor(to:)`, `lastDerivedOffset`). | Lifted into the scroll view and generalised to any depth (1b, P1). The column shape of the engine *is* this walk. P1 moved the anchor to `ScrollViewHandler.contentAnchor` and the walk to `ScrollColumnFill.swift`. |
| The anchor ladder | `StackWindowState`, §5f | A deleted anchor falls to its nearest surviving neighbour; a replaced list falls back to the remembered index. | Kept per level: the anchor remembers each placing level's key and ordinal. |
| The uniform window | `StackUniformWindow.swift` | A common row height as a hypothesis, refuted for good on the first row that differs. | The column shape's fixed-pitch path, for `List` and `Table` too (1d). |
| The top-row hold | `StackTopRowHold.swift`, `TopRowHold`, `ScrollWindowHold` | Moves the absolute offset by however far the content above moved the row at the top. | Intrinsic: the anchor *is* the held row. `ScrollWindowHold.offset` re-derives the anchor from the derived offset instead (2a, B-SCROLLFIT-16). |
| `ScrollContentWindow`, `ScrollContentReply` | `ScrollContentWindow.swift` | The window down (offset, viewport, addressee, `linesAbove`/`linesBelow`, seek, read-back sampling, hold); the slice back (`sliceOriginY`, totals, `drawnLines`, `seekResolvedOffset`, `measureWentStale`). | Become the pull request and its reply (1b). The addressee and `isAtOrigin` go: every placing container reads the request. |
| `ScrollWindowRelay` | `ScrollWindowRelay.swift` | For a view that draws N lines above its content and M below (`Section`, `.padding`, the margins), moves the window in and the reply out. | The forward shape, for every single-child view that draws lines around its content (1c). |
| `consumableScrollWindow`, `scrollContentOriginDepth`, `leaveScrollOrigin()`, `anchoredSizeThatFits` | `VStack.swift`, `StackLayoutPlacing.swift`, `RenderContext`, `StackAnchoredMeasure.swift` | Window only the content's origin; mark the origin so a nested stack knows to measure every row it reaches (design D). | As P2 built it: no origin is special. Each column re-addresses the request to the child it hands it to (`contentIdentity`), so "at the origin" means "reached by single-child steps from the view the request was handed to". The mark stays, with the depth kept below the origin (`belowScrollContentOriginFlag`), for a stack to read whether columns lead to it (`isPulledWhereItStands`); design D's walk stays only for a stack below a container that does not pull yet (B-SCROLLFIT-13), and the scroll view's hint for it (`contentWalksNestedStacks`, `oneLinePast`) is deleted. |
| Off-band rows | `StackOffBandRows.swift`, `StackFocusReach.swift` | Builds the focused row, its neighbours and a pending target outside the band; the 64-row continuation probe (`focusRingContinuations`). | The engine's off-band routes, at every level (1e). |
| `ChildViewCollection` | `TUIView/Rendering/ChildViewCollection.swift` | O(1) `count`, `key(at:)`/`anyID(at:)` with no row built, a row built on subscript. | The children of every column, as it is. |
| `RowSource`, `ScrollRowWindow`, `ScrollExtentEstimator` | `TUILists` | `List`'s O(1) count and lazy ids; which rows to build from an offset; its sample estimate. `Table` uses the resolver with one-line rows. | `List`'s and `Table`'s children and estimators under `ScrollPlacing` (P3, P4). |
| Pinned chrome | `ScrollPinnedChrome.swift`, `OverlayLayer.ScrollPin`, `PinnedChromeCover` | A section's header or footer rides as a layer to the nearest scroll view, pinned while its section is under the viewport edge. | A table's header and horizontal bar (2c), unchanged. |
| `WindowedRowFade`, `WindowedRowRecord` | `TUIView/Animation/WindowedRowFade.swift` | A row fades in only if it was not drawn last frame *and* was not in the data. | Unchanged for lazy containers; extended to the containers A-SCROLLFIT-1 windows (1g). |
| `ScrollToRegistry` | `ScrollViewReader.swift` | Parks a request on every live scroll view; each resolves against its content (`locate(key:)`, `firstOrdinal(forKey:)`, `index(ofScrollKey:)`). | Each scroll view locates the key by routing (1f). |

### 1b. The anchor, and the frame filled from it

**B-SCROLLFIT-11. The scroll view holds its position as an anchor; the absolute offset is a
reading derived from it.**

```swift
/// ScrollViewHandler's position under the pull (P1). Package-internal:
/// `ScrollPosition` and `ScrollAnchor<ID>` are already spent on SwiftUI's
/// and TUI's public shapes (Locating §9).
struct ScrollContentAnchor: Equatable {
    /// The row the viewport is anchored on: the deepest placed child the
    /// fill reached at the viewport's top (or bottom, under `edge`).
    var row: ViewIdentity
    /// A line-source leaf's own row below `row` (a `TextEditor`'s logical
    /// line); `nil` elsewhere.
    var subRow: Int?
    /// Lines of the row hidden above the viewport's top (below its bottom
    /// for `.bottom`).
    var within: Int
    /// Top is the default; bottom is follow mode (§5c's edge affinity).
    var edge: VerticalEdge
    /// Each placing level's key and ordinal on the way to `row`: the
    /// ladder a deleted row or a replaced collection falls back on (§5f).
    var route: [AnchorStep]
}
```

**As P1 built it** (`ScrollContentAnchor.swift`): a class, not this struct, because the request
carries it down by reference and the column writes it in place, as `ScrollContentReply` travels
back. `ScrollViewHandler.contentAnchor` holds it and `ScrollContentWindow.anchor` hands it down.
It holds the row as its column's identity (`column`, the route's head) with the row's `ordinal`
and `key`, the signed `within`, and the dead reckoning that was the stack's: `derivedOffset`
(was `lastDerivedOffset`) and `reportedTotal` (was `lastReportedTotal`). A column claims it each
frame (`claimed(byColumn:state:)`) and finds it afresh when it is another column, or the same
column drawn anew after its window state was pruned, which is exactly when its own anchor used to
start afresh, so the move changed no output. `subRow` (P4's `TextEditor`), `edge` (follow mode,
still the scroll view's declared anchor and tail glue) and the multi-level `route` (P2's router)
arrive with their first readers; with content at the origin only, the route is one level.

`ScrollViewHandler.scrollOffset` stays, as the derived reading. Input keeps speaking in lines,
as it does today. The wheel, the arrows, Page Down, a glide step and a short scrollbar drag each
change the offset by a delta, and the delta is walked in row space from the anchor: one line up
looks at one row. That is the trick the anchored stack already plays
(`advanceAnchor(to:)`, `lastDerivedOffset`), lifted from one stack into the scroll view. A move
of more than four screens (a long drag, `scrollTo(y:)`, End on unknown content) lands by
estimate (2b). A `scrollTo`, a focus jump or a `.scrollPosition(id:)` names a row, and that row
simply becomes the anchor.

**The fill.** To draw, the scroll view hands its content a **pull request**:

- the anchor's route;
- the lines to fill above the anchor line and below it, which is the viewport's height split at
  the anchor;
- the off-band routes: the focused control, a pending seek or focus target, and the margin rows
  either side of the band.

The request travels the way `ScrollContentWindow` does today: in the render context, with a
reply back in the same call. Each placing container then does the same four steps:

1. **Route.** It reads which child leads to the anchor (`childStep(below:)`, then `ordinal(of:)`,
   with no row built), and asks that child to fill with the rest of the route.
2. **Fill outward.** From the child's reply (lines filled above and below the anchor line, and
   whether it reached its own top or bottom), it fills upward with the children above, each from
   its bottom edge, and downward with the children below, each from its top edge. It adds its
   spacing and chrome between them, until both needs are met or it runs out of children.
3. **Off band.** It draws the children that hold an off-band route and lie outside the band.
   They are drawn for their regions and focus places (`graftOffBandRow`), without adding lines,
   and every other child gets an off-band request that does not change while it stays off screen
   (B-SCROLLFIT-2, kept). So its memo holds, and a consumer inside it draws only its own off-band
   rows.
4. **Reply.** It answers with its band, the lines it still owes above and below (so its parent
   continues outward), whether it reached its top or bottom, and its *estimates* of its lines
   above and below the band (1d).

This is §6b's example made general. In `ScrollView { VStack { header; LazyVStack(1M); footer } }`
anchored at row 517,203, the column routes to the lazy stack. The stack fills from row 517,203,
and the header and the footer are never touched unless the fill reaches them.

**B-SCROLLFIT-12. One fill engine; a container answers only for its own children.** The outward
walk is written once (P1), as the anchored window is today. A container supplies only its
children, their extents, the lines around them, and a **shape**:

| Shape | Who | What the engine does |
|---|---|---|
| **column** | `VStack`, `LazyVStack`, `List` rows, `Table` rows, `Form`, `GroupBox`/`DisclosureGroup`/`Section` content, `LazyVGrid` lines, `Grid` rows, `VSplitView` panes | the outward walk above |
| **parallel** | `HStack`, `ZStack`, `.background`/`.overlay`, a `GridRow`, `LazyHStack` across the vertical axis, `HSplitView`, `NavigationSplitView` columns | Routes to the anchored child; every sibling is filled with the same need, moved by its alignment offset. Top alignment needs no height; centre and bottom need each sibling's extent, which is O(1) for a consumer and estimated for a lazy one. The band is the union. A secondary (`.background`) is drawn at the band's size and offset, not the content's height. |
| **forward** | an app's view (`body`), every modifier, `AnyView`, `EquatableView`, `_MemoizedRow`, `if`/`else` branches, `ViewThatFits`' chosen variant, `.padding`, `.border`, `.frame`, the content margins, `TabView` (its selected tab, below the bar), `NavigationStack` (its top view, below the title bar), a `Section` outside a `List` (header and footer around its content), a content-sized nested `ScrollView` (2a) | Moves the request past the lines the view draws above its content and the reply back by them, which is `ScrollWindowRelay`'s arithmetic. A body step costs nothing, because it adds no lines. |
| **lines** | `TextEditor`, and any leaf with rows of its own | A column whose children are not views: the anchor's `subRow` is the leaf's row |
| **leaf** | `Text`, `Image`, controls, and every view that conforms to nothing | Measured and drawn whole, then clipped to the band; the anchor in it is a line (`within`). Cost: its own size, as today. |

**What a container implements** (sketch; P1 settles the spellings):

```swift
@MainActor
package protocol ScrollPlacing: LayoutPlacing {
    /// How the engine walks this container's children along the scroll axis.
    func pullShape(context: RenderContext) -> PullShape
    /// The child at `ordinal`'s extent at `width`: exact once built and
    /// measured this pass, else this container's own estimate (fixed pitch,
    /// running pitch, or a sample). Never builds a row to answer.
    func extent(at ordinal: Int, width: Int, context: RenderContext) -> PullExtent
    /// Lines drawn before child `ordinal` (spacing; chrome above, for 0),
    /// and after the last child.
    func lines(before ordinal: Int, context: RenderContext) -> Int
    func linesAfterLast(context: RenderContext) -> Int
    /// `.eager`: every child exists every frame (built, `onAppear` at mount,
    /// focus registered). `.windowed(threshold:)`: past `threshold` children,
    /// only pulled children exist.
    var existence: PullExistence { get }
}
```

**As P1 built it.** The engine is written against the rows a column hands it,
`ScrollFillColumn` (`ScrollColumnFill.swift`): `rowCount`, `pitch(of:)`, `key(at:)`,
`firstOrdinal(forKey:)`, the `ladder` of rows drawn last frame, the `estimatedPitch`, and the
`anchor` it moves. The walk (`rebindAnchor`, `advanceAnchor`, `tailAnchor`, `fill`) is the
anchored stack's, moved unchanged; the stack's per-frame measurer is the one conformer, and
`List` and `Table` conform in P3/P4. `ScrollPlacing`, the container-level protocol above, has no
caller while content is pulled at its origin only, so it arrives with its first router in P2
rather than as an unused protocol. The uniform window stays its own arithmetic until P3 needs
fixed pitch for `List` and `Table`: it keeps no anchor, so P1 had nothing to move in it.

**As P2 built it** (`StackPulledColumn.swift`, 2026-11-12). The route is held level by level,
not as one array at the scroll view. A column that holds a pulled child (`VStack`,
`LazyVStack`, at any row count) is a *pulled column*: it keeps its own anchor (the scroll view's
`contentAnchor` at the content's origin, its window state's `ownAnchor` below it), walks the
scroll delta through its children with the column engine (`advanceAnchor`), and fills outward
from the anchored child. A pulled child is handed a request of its own, a `ScrollContentWindow`
addressed to it (`contentIdentity`, so every level re-addresses as it hands on) and marked
`isPulled`, whose `edge` says what its offset counts from:

- `.position`, the child's own dead-reckoned position, when the anchor stayed in it: the
  column hands back the position the child last answered (`ScrollContentReply.pulledPosition`),
  moved by the delta, so the child walks the same delta in its own lines;
- `.top`, its first row's top, when the fill reaches it from the row above or the anchor enters
  it from above or by a jump;
- `.end`, its last row's bottom, when the fill reaches it from below or the anchor enters it from
  below; the child places its last rows from its end exactly (`enter(edgeOf:)`).

The column places each child by what it drew (the band's origin, and whether it holds the
child's first and last rows), not by a measured height: rows below a pulled child start where
its band ends, rows above end where it starts. A pulled child's pitch for the walk across it is
the end it last reported (`StackWindowState.pulledAnchorRow`), exact by the time the viewport
nears it, because the band then holds its last row.

Which children are pulled is filed by their own measures (`PullConsumers`, on the render cache):
a lazy stack past the windowing threshold, or a column holding one. A column asks it of each
child by one lookup (`ViewIdentity.singleChildRoot`). A stack is pulled only where every
container between it and the scroll view that holds it among siblings is a column
(`isPulledWhereItStands`, read from the identity chain, so a measure knows before any request
arrives); below anything else it is still drawn whole and measured over the rows its budget
reaches (design D's walk, kept as B-SCROLLFIT-13's fallback, now reached only there).

`ScrollPlacing` is the marker those containers conform to: in P2, `_VStackCore` only.

What P2 left to P3 (each recorded under 4):

- **Parallel and forward shapes past `Section` and padding.** `HStack`, `ZStack`,
  `.background`/`.overlay`, the bordered container (`GroupBox`, `.border()`), `TabView`,
  `NavigationStack` and `Grid` do not pull yet; a lazy stack below one is drawn whole as before.
  Bodies, modifiers and the views that already relayed the window (`Section`, `.padding`, the
  content margins) forward it.
- **Locate by route (B-SCROLLFIT-15, A-SCROLLFIT-4's (b)).** A pulled column answers a `scrollTo`
  of its own rows (by the running pitch); a key inside a pulled child is not searched, as under
  design D.
- **The focus reveal as an anchor (1e).** Reveal still moves the offset; the walk carries it.
  A pulled column draws its children as it fills, anchored row first, so a focusable child above
  its anchor registers after the rows below it.
- **What the outermost stack did that a pulled column does not yet:** a row held by
  `.anchorPosition(.row(id))`, the top-row hold, `scrollTargetLayout` and the visibility
  observers' rows, and the eager stack's departing-row transitions. A pulled column takes over
  only from a column that holds a pulled child, which before P2 drew that child whole.

Forwarders do not conform: the engine sees a single-child step and forwards. That is the common
case, and an app's own views are always that case. The counts are Locating §8's, updated. About
a dozen multi-child cores conform:

- `_VStackCore` and `_HStackCore`, which share an implementation;
- `_ZStackCore`, `_ListCore`, `_SectionCore`, the table core, `_GridCore`, the lazy grids, the
  `Form` styles;
- `ContainerView` (`GroupBox`, `DisclosureGroup`) and the split views;
- `_LayoutCore`, by an adapter (B-SCROLLFIT-13).

About seven single-content cores forward with chrome lines: `_TabViewCore`,
`_NavigationStackCore`, `_ContainerViewCore`, and the padding, border, frame and margins.

**The identity chain is seekable through:**

| On the chain | Step | Routing cost |
|---|---|---|
| an app's view, a modifier, `Group`, `AnyView`, a branch | typed single-child, or `branch` | none: forward |
| `ForEach` | keyed (`child(erasedType:key:)`), flattened into its parent's children | `ChildViewCollection.key(at:)` near the remembered ordinal (±64), then the data scan (Locating §12's identity tax), with an O(1) rung for `ForEach` over a `Range<Int>` keyed by `\.self` |
| `VStack`, `HStack`, `LazyVStack`, `Grid`, `GroupBox`, `DisclosureGroup`, `Form`, `Section` | indexed or keyed | `ordinal(of:)`: O(1) by index, as for `ForEach` by key |
| `List`, `Table` | the row's key in `RowSource` / the table's data | `index(ofScrollKey:)` / `firstIndex`, near the remembered index first |
| `TabView`, `NavigationStack` | the selected tab / the top destination | forward. A route into an unselected tab or a popped view is not on screen and is dropped, as the ladder drops a deleted row. |
| `TextEditor` | `subRow` | the logical line, then the wrapped line within it |

**B-SCROLLFIT-13. A view that does not conform is drawn whole; an app's own `Layout` is
adapted.** A multi-child core that does not conform is a leaf: it is measured, drawn whole and
clipped, and a consumer inside it is drawn whole (today's cost). A debug counter records each
such consumer, `ScrollPull.unplacedConsumers`, and tests assert it is zero for every framework
container. Locating §8's "fail loudly" becomes a test failure, not a crash, by the owner's
never-crash rule.

An app's `Layout` runs through `_LayoutCore`. Its `placeSubviews` places every subview, which
SwiftUI also does eagerly, so the adapter runs it once per frame per width, keeps the
placements, and serves them as a parallel-or-column shape by their rects. A `List` inside an app
`Layout` is then pulled like one in a `VStack`. Cost: the `placeSubviews` the render already
pays. Price: about 1½ days (P9). `FlowLayout` is a `Layout` too, but A-SCROLLFIT-1 asks it to
build only visible items, which an adapter cannot do; its own conformance is A-SCROLLFIT-5.

**B-SCROLLFIT-14. Eager containers build every child and paint the band.** Under
A-SCROLLFIT-1, a `VStack`, `HStack` or `Grid` keeps SwiftUI's existence: every child is built
and measured, its `onAppear` runs at mount, and its focusables register. In TUI, `onAppear` and
focus registration happen when a view renders (Locating §1 and §5g). So every child is rendered.
Children outside the band are rendered with the off-band request, which does not change as the
page scrolls, so they are memo hits. Only their lines are left out of the assembled band.

This is today's cost for eager content, and no more. Decoupling registration and lifecycle from
rendering, so that eager rows off screen are not even rendered, is Locating §5g's paint
windowing. It would change no observable behaviour, but needs its own design, and is left for a
future reader.

### 1c. Containers with no lazy counterpart (A-SCROLLFIT-1)

`GroupBox`, `DisclosureGroup`, a `.columns` `Form`, and a `Section`'s content outside a `List`
take `existence: .windowed(threshold: 256)`. That is the lazy stack's `anchoredWindowThreshold`,
so a small page behaves exactly as today. Past it they are columns whose children exist only
while pulled, with the running-pitch estimate and the per-level ladder.

`FlowLayout`'s rows are wrapped lines, and a line's first item depends on every item before it.
How it finds them is A-SCROLLFIT-5.

`TabView`, `NavigationStack` and `NavigationSplitView` only forward or run in parallel. Their
content's own containers decide what is built.

### 1d. Heights of rows not yet built

**B-SCROLLFIT-3 (kept). Fixed pitch is arithmetic; variable pitch is an estimate, through the
one engine.**

- **Fixed one-line rows: exact, O(1).**
  - A single-line `Table` already measures without building a row (`measuredSizeThatFits`).
  - A `List` whose rows are one line takes the uniform hypothesis as a lazy stack does. It is
    seeded from row 0, checked against every row the band builds, and refuted the first time a
    row differs, once in the view's life (`ScrollContentReply.measureWentStale` replans the
    frame).
  - A section's row count comes from its own `ForEach`, so a sectioned list's total is
    O(sections).
- **Variable rows: an estimate.**
  - Covers `List` rows of several lines, a multi-line `Table`, `TextEditor` lines that wrap, a
    grouped `Form`'s rows, and the containers of 1c.
  - Rows the fill builds are measured exactly; every other row is priced at its container's
    running pitch (`ScrollExtentEstimator` for `List` and `Table`, the anchored window's own
    for the stacks).
  - `.scrollExtentPrecision(.exact)` still makes a container measure every row, for an app that
    wants exact readings and accepts Ω(rows) per change.
- **Where an estimate is used.** Under the pull it never places anything on screen: the fill
  places only from the anchor, by rows it has built. An estimate feeds only the readings in 2b:
  the derived offset, the total, the thumb, "N more", and a far jump's landing row. That is the
  difference from the relay, where an estimate above a list moved the content below it.
- **`LazyVStack`'s first frame builds every row twice** (20,075 at 10,000). The likely cause is
  in Locating §6b: on a first render no content height has been recorded, so the scrollbar's
  first round climbs the ladder at the other width. Under the pull, the scroll view learns
  whether the content overflows from the fill itself (did it reach the content's end before the
  viewport was full?), so the first frame needs no total. P2 pins the count at under 100 at
  10,000 rows (moved from P1, which changes no count the baseline pins: section 4).

  *Corrected in P2 (2026-11-12): the cause was not the scrollbar's round.* An app's first frame
  begins with a throwaway measuring walk of the whole page, for the chrome its content declares
  (`RenderLoop.prepareWindowChrome`). Under a measure a windowed stack takes no window, so it
  drew every row its measure had priced into the canvas the scroll view gave it, twice. A
  scroll view's measuring render now gives its content only the lines down to the viewport's
  bottom, and answers with the height its measure found
  (`_ScrollViewCore.renderedContent`'s `drawsPrefixOnly`). The baseline's count is 124 at
  10,000 rows alone and 119 under a title, the sixteen-row samples of the measure ladder's
  rungs included, so the pin is under 150; a 10,000-row `List` under a title, which the same
  walk drew to its 4,095-line canvas, builds 12,300 rows on its first frame rather than 16,000+.

### 1e. Focus: an unbuilt row stays reachable

- **The focused control is an off-band route.** Every placing container on its chain draws the
  child that leads to it, outside the band if need be, as the windowed stack draws its focused
  row today. Shift+Tab order is kept: a child above the band is drawn before the band
  (`drawOffBandRow`'s rule).
- **`List` and `Table` register one focusable**, the container, and their cursor is an index
  (`ItemListHandler.focusedIndex`). Off the band they draw only the cursor row's marker, at its
  place, with no lines. A container whose band is empty still registers.
- **Tab out of the band.** The container that holds the focus answers "next focusable after
  ordinal k" by building rows outward, within the existing 64-row continuation probe
  (`focusRingContinuations`), and escapes to its parent at its ends (Locating §5d). Eager
  children are rendered and registered anyway (B-SCROLLFIT-14).
- **Focus at launch.** The first focusable in ring order is the first registered, and with
  eager children rendered and every consumer registering, that does not change. 2e covers what
  the reveal then does.
- **Reveal.** When focus moves to a control that is not wholly visible, the control becomes the
  anchor, with minimal movement, as `scrollTo(_:anchor: nil)` does. When it is visible, nothing
  moves (Locating §5c). This is Locating's Stage 2 (the locate visitor), which never shipped; the
  route makes it O(depth).

### 1f. `scrollTo` and focus jumps to a row never built

**B-SCROLLFIT-15. A seek is located by routing, then becomes the anchor.**

1. `ScrollToRegistry.scrollTo` parks the request on every live scroll view, as today.
2. The scroll view asks its content to locate the key. Each placing container checks its own
   children's keys, by the data scan with the near-first search and the range rung (1b's
   table), and descends into the children it already holds built (eager children, and pulled
   ones). Nothing new is built. How far it goes into rows never built is A-SCROLLFIT-4.
3. A hit returns the route. The scroll view sets the anchor to the target, with the request's
   `UnitPoint` choosing the line (Locating §5c's alignment: `.top` puts the row's top at the
   viewport's top, `.bottom` its bottom at the viewport's bottom, `nil` the minimal move), and
   fills. The target lands exactly where asked, on the frame that carries the request, at
   O(visible) plus the key scan.
4. A miss falls back to today's paths. An unknown key does nothing, as in SwiftUI.

A framed table, which still scrolls itself, resolves into its own offset as now, and the outer
view reveals the cursor marker that results. A content-sized nested `ScrollView`'s
`ScrollViewReader` seeks through the outer one (2a).

### 1g. Animations and transitions of windowed rows

`WindowedRowFade` separates "entered the band by scrolling" (no fade) from "inserted into the
data" (fade), using `WindowedRowRecord`'s last-drawn set and the `isRow` question about the data.
For `List`, `Table` and the lazy stacks nothing changes, provided `isRow` stays a data question.

The containers A-SCROLLFIT-1 windows are new to this. Their children's identities are already
resolved, so the record is keyed by those, and a child present in the data last frame appears
without a fade when it is first pulled in. Eager containers render every child (B-SCROLLFIT-14),
so their transitions run as today. A row removed while off-band plays no removal, since nothing
would see it, which matches the stack and `List` today.

## 2. The SwiftUI APIs, and switching the defaults (step 3)

### 2a. Per view, from the baseline table

| View | Today (alone / under title / 2 stacked, 60 rows) | After |
|---|---|---|
| `Table` | capped at the viewport (24, scrolls itself) | its content: 63 at 60 rows, 10,003 at 10,000. Header and horizontal bar pinned (2c). The outer view reveals the cursor (2d). `scrollViewportCap` is deleted. |
| `List` (plain, sectioned, outline) | 4,096 (the rung) | its content (≈62 at 60). Plain one-line rows are arithmetic; sections are O(sections); outline rows take the variable path, which also fixes "a wheel step rebuilds every drawn row" (4,094 at 10,000), because only the band is drawn |
| `Form .grouped` | max(content, viewport), up to 4,096, then scrolls itself | its content (5 at 3 rows) |
| `Form .columns`, `GroupBox`, `DisclosureGroup`, `FlowLayout` | already its content; builds every row | unchanged in size; build only pulled rows past 256 (1c, P8) |
| `TabView`, `NavigationStack`, `Grid`, `LazyVStack` | already its content | unchanged in size. Forwarded or pulled; `Grid` stays eager (B-SCROLLFIT-14); a `LazyVStack` anywhere is pulled (P2) |
| `TextEditor` | max(content, viewport) up to 4,096, scrolls itself past that | its wrapped content (3 / 60 / 10,000). No bar of its own. It stamps a caret-line marker like the list's cursor marker, so the outer view follows the caret. A lines-shaped leaf. |
| `ScrollView`, same axis | max(content, viewport) up to 4,096, its own bar | its content, no bar, forward-shaped: its own offset stays 0, and a `ScrollViewReader` inside it seeks through the outer view |
| `ScrollView`, cross axis | as above | its content height; it still scrolls across |
| `HSplitView` | max(content, viewport) up to 4,096; rows past that unreachable | the tallest pane's content; parallel-shaped |
| `VSplitView` | panes split, top pane cut even at 60 | the panes' content heights summed. When no pane is flexible and the height offered covers the sum, each pane gets its natural height. The likely cause is `resolvedSizes`' even split when `flexibleIndices.isEmpty`, still to be reproduced. A pane the user resized keeps its size and scrolls itself. |
| `Image.resizable()` | fills the viewport alone, 15 when stacked | its ideal: 15, its pixels at the width |
| `Spacer`, `Color`, shapes, `GeometryReader`, `Text.frame(maxHeight: .infinity)` | fill or split the viewport; `GeometryReader` 4,096 | their minimum (B-SCROLLFIT-7) |
| `Divider`, `scaledToFit` images | unchanged | unchanged |
| `LazyHStack` | 1 line high; never windowed across | unchanged vertically (parallel-shaped). Windowing across is outside this ruling. |

**The scroll view's canvas.** The content is drawn at its measured height, not at
`max(viewport, content)`, so flexible children no longer stretch to the viewport.
`containerRelativeFrame(.vertical)` still reads the viewport, so a table framed that way is as
tall as the visible area and scrolls itself, which is TABLE-TALL's behaviour as an opt-in.
`.frame(maxHeight: h)` hands a table a height of min(content, h), and the table scrolls itself
inside it. P7 tests that the frame makes the height explicit (`hasExplicitHeight`).

**A-SCROLLFIT-2, as ruled (b).** `ScrollView(.horizontal)` proposes its own height to its
content, so a `Table` or `List` in it is framed to that height and scrolls itself, as in
SwiftUI. Content still taller (eager content) keeps today's vertical scrolling, through the same
anchor engine on the vertical axis, so nothing becomes unreachable. Column (v) of the baseline
then reads `Table` 24 (its own bar), `List` 24 (its own bar), eager containers as now. One
sentence in the deviations records it as an extension that no SwiftUI program can trip over.

### 2b. The APIs that speak in absolute offsets, mapped onto anchors

**B-SCROLLFIT-16. Moves are exact; absolute readings are exact where every extent is known and
estimates elsewhere, carried by dead reckoning.**

"Known" means: fixed pitch, eager content (measured anyway), or `.scrollExtentPrecision(.exact)`.
"Estimated" means a variable-height lazy or windowed container lies above or below the viewport.

| API | Under the pull | Exact? |
|---|---|---|
| `ScrollViewProxy.scrollTo(_:anchor:)`, `ScrollPosition.scrollTo(id:anchor:)`, `.scrollPosition(id:)` written | Located by route (1f); the target becomes the anchor at the asked alignment | **exact placement**, O(visible) plus the key scan |
| `.scrollPosition(id:)` read back, `ScrollPosition.viewID` | The row the fill drew at the sample line (`sampleY`, unchanged) | **exact** |
| `ScrollPosition.scrollTo(edge:)`, Home, End, `defaultScrollAnchor(.bottom)`, following the tail | Anchor = first row at the top, or last row with bottom affinity; filled outward, no total needed (Locating §6c) | **exact** |
| The wheel, arrows, glide, Page Up/Down, `scrollTargetBehavior(.paging)` | A delta in lines, walked from the anchor | **exact** |
| `scrollTargetBehavior(.viewAligned)` | Snaps to a drawn row's top | **exact** |
| A focus jump, `focus(id:)`, Tab | Reveal: the control becomes the anchor if not visible (1e) | **exact** |
| `ScrollPosition.scrollTo(y:)`, `scrollTo(x:y:)`, `scrollTo(point:)`, a long scrollbar drag, a track click | A line y from the content's top: each level turns it into (child, y′) by its children's extents, down the route. Under four screens from the current offset it is a walked delta, which is exact. | **exact** where extents are known; **estimated** landing row elsewhere |
| `ScrollPosition.x`/`y`/`point` read | The request, kept until the user scrolls, as in SwiftUI | as asked |
| `onScrollGeometryChange` `contentOffset.y` | The derived offset | **exact** where known; **estimated** elsewhere |
| `onScrollGeometryChange` `contentSize.height` | The derived total: the lines above the band plus the band plus the lines below, each level's estimate summed | **exact** where known; **estimated** elsewhere |
| `onScrollGeometryChange` `visibleRect`, `containerSize`, `contentInsets` | From the viewport | **exact** |
| `GeometryReader` `frame(in: .scrollView)`, `onScrollVisibilityChange`, `scrollTransition` | A drawn view's place relative to the viewport, from the fill | **exact** |
| `frame(in: .named(…))` of a space at the content's top | The derived offset plus the view's band y | **exact** where known; **estimated** elsewhere |
| The scrollbar thumb | Derived offset over derived total | **exact** where known; **estimated** elsewhere |
| "N more above/below" | Lines above / below the viewport | **exact** where known, or when the fill reached that end (0 below: no indicator); else **"~N"**, as `contentHeightIsEstimate` marks it today |
| `ScrollWindowHold.offset` (TUI-specific) | The offset in lines is kept and the anchor re-derived from it: a delta walk, exact, unless rows above were never built | **exact** where known; **estimated** elsewhere |

**How estimates stay steady** (the existing top-row hold, generalised):

1. **Content on screen never moves for an estimate.** The fill places only from the anchor.
2. **The derived offset moves only with the user's moves.** It is carried by dead reckoning: a
   walked delta adds exactly the lines walked. It is re-derived from estimates only on a far
   jump, and corrected at the edges: when the fill reaches the content's top, the offset is
   exactly the lines it walked above the anchor. So an estimate that refines off screen changes
   the *total* (the thumb's length and "~N more below"), not the offset, and
   `onScrollGeometryChange` sees a `contentSize` change, not a `contentOffset` jump. This is the
   anchored window's `lastDerivedOffset`, at the scroll view.
3. **A drag holds its mapping** (P2: `ScrollbarDragExtentHolding.scrollbarDragExtent`, set at the
   grab and at a jump-click's implicit grab, read by every drag event, cleared at release). At
   the grab (`scrollbarDragGrab`), the total in use is frozen
   for the drag's duration, so the thumb follows the pointer and the row under it does not
   oscillate as estimates refine. At release the thumb is re-derived once.
4. **Totals are sticky.** A level's estimate changes only when it measures a row it had not
   measured, never because the band moved, so scrolling back and forth over measured rows reads
   the same numbers. That is `ScrollExtentEstimator`'s sample rule, applied at every level.

### 2c. A tall table's header and horizontal bar, pinned to the visible area

**B-SCROLLFIT-9 (kept).** A content-sized `Table` emits a copy of its header (the header line, its
rule, and the side borders on those lines) as a top-pinned `OverlayLayer.ScrollPin` layer, and
its horizontal bar (`TableHorizontalWindow`, `drawHorizontalScrollbar`) as a bottom-pinned one.
`PinnedChromeViewport.pinnedRow` places them while any of the table's rows are under the
viewport edge. The next table's header pushes the first away, which is SwiftUI's section-header
rule, and `PinnedChromeCover` keeps a focused row out from under either. The layers are emitted
whenever any of the table's band is drawn, with `offsetY` at their natural place, possibly
outside the band. That is how a section header above a lazy stack's band reaches the scroll view
today. The table keeps its own horizontal scrolling by whole columns.

### 2d. Keyboard in a tall `List` or `Table`

- **Arrows, Home and End, type-select (`r45`)** move the cursor index. The cursor row is drawn
  (in band or off-band, 1e) and stamped with the cursor marker, and `snapViewportToFocusedControl`
  reveals it through the outer view. Under the pull that reveal is the anchor rule in 1e.
- **Type-select** scans `typeSelectText` (`resolvePendingTypeSelect`); P3 checks that it builds
  no row. If it does, that is per key press and capped at a scan, but it is to be measured.
- **B-SCROLLFIT-5 (kept). Page Up and Page Down move by the outer viewport.** `ItemListHandler`
  pages by the request's viewport less the pinned header's lines, not by its own height (which
  for a content-sized list would make Page Down act as End). With no request, a framed or
  free-standing list pages as today.
- **Selection** is data: indexes and ids (`index(of:near:)`, ±64 first). Unchanged.
- **The wheel** over a content-sized table or list goes to the outer view, which walks the
  delta from its anchor.

### 2e. Focus at launch does not scroll a title away

**B-SCROLLFIT-6 (kept). On arrival, the reveal of a control taller than the viewport reveals its
cursor line, and does nothing if that line is already on screen.** If the union of its regions
fits in the viewport, the union is revealed (unchanged). Otherwise the smallest region (the
cursor marker) is revealed, and only if it is not visible. At launch the first row sits under
the title, on screen, so nothing moves.

### 2f. Greedy views declare it; `.fixedSize` climbs the ladder

**B-SCROLLFIT-8 (kept).** "Filled the budget" no longer means greedy.

- **Fillers declare it.** Under a nil proposal, a filler answers its minimum (0, or a `Spacer`'s
  `minLength`) and is flexible (`ViewSize.isHeightFlexible`, `.flexibleHeight`).
  `_GeometryReaderCore` and `.frame(maxHeight: .infinity)` change to match.
- **Content-sized views answer content** from 1d, flagged as a natural size so that the per-pass
  memo serves every rung of the ladder. They are flexible only where a height was given.
- **`.fixedSize` uses the scroll view's ladder** (`naturalExtent(_:along:proposal:context:startingBudget:)`)
  instead of one measure, and stops at a rung the extent comes in under, or at a declared filler.
- **Outside a scroll view there is no viewport to pull against.** A variable-row consumer under
  `.fixedSize` there must answer its exact height, which is Ω(rows) per change. That is correct:
  it is drawn whole. Inside a scroll view, `.fixedSize` content is pulled like any other, so a
  10,000-row table under it is 10,003 lines and builds the rows on screen, instead of 23 lines
  after building 4,153.

**B-SCROLLFIT-7 (kept).** A filler's ideal along an unbounded axis is its minimum: 0 for `Color`,
shapes and `GeometryReader`. This is the height counterpart of the ideal-width ask's 0 (SwiftUI
answers 10 points, less than a line). One constant if the owner prefers a line.

## 3. Performance budget

**What must be O(visible) per frame**, independent of the row count. Rows *built* means a row
builder called, as `ScrollFitProbe.built` counts them.

- The rows built for: a first frame, an idle redraw, a wheel step, a cursor step, a Page Down,
  a `scrollTo` to a row never built, and a focus jump.
- A placing container's work: O(the children the fill visits) plus its off-band routes.
- Eager children (B-SCROLLFIT-14): built and rendered as today, as memo hits off band.

The bound is the band plus the off-band rows: the viewport's rows, a margin row each way, the
focused row ±1, any pending focus or seek target, and at most the 64-row continuation probe each
way (the existing cap, rarely spent).

**Allowed to be O(N), not per frame:**

- data scans that build no row, at the user action that needs them (a key's ordinal, a
  selection set from outside, type-select);
- `.scrollExtentPrecision(.exact)`;
- the two-axis view's whole-content width, which keeps its four rungs (Locating §12);
- an eager container's existence.

**Each lane's gate:**

1. **Counts, deterministic.** For each new shape, `builtFirst`, `builtStep` and `builtSeek` at
   1,000, 10,000 and 100,000 rows must be **equal** across the three sizes, which proves
   O(visible). They are pinned in tests next to `ScrollFitBaselineTests`.
2. **Time and memory.** `Stress --bench`, quiet box, `Tools/Profiling/ab_bench.py` paired
   against the lane's base, CPU per frame and peak RSS. The owner's tolerance applies: a few
   percent is fine, around 10% means optimise first. The scenarios that cross these paths must
   not regress:
   - `app-shapes` (`headed-log`, `sidebar`, `file-browser`, `code-editor`,
     `code-editor-tailing`);
   - the table scenarios (`TableGroups`, `WideTable`, `MultiLineTable`, `ChurningTable`);
   - `MegaList`, `ScrollEager` and `ScrollFollow`;
   - the small eager pages (`Dashboard`, `session/editor`, `session/chat`): the pull sits under
     every scroll view, and these are where its overhead would show.
3. **`Stress --selfcheck` and the render-memo verifier** stay clean. A band is a function of state
   (anchor, focus, request) and must equal a fresh render's.
4. **P1 only: byte-identical frames.** P1 moves the anchor into the scroll view and changes no
   output. Every scroll test passes unchanged, and a parity harness renders the scroll suites'
   scenes on the base and on the lane and compares every frame: `Tools/Profiling/frame_parity.py`
   over `Stress --bench --frame-checksums`, every scenario, variant and session.

**The cost that must go: design D's.** `grouped-feed` was +706.8% (17.0 → 137.2 ms a frame) and
+64 MB (RSS 20.1 → 84.2 MB) when D landed. Its rows built a write frame went from 4,093 to
27,932. After P2:

- rows built a write frame O(visible), the same at 40 and 320 sections;
- RSS back within 10% of D's base, about 20 MB;
- the time A/B against `main` showing the cost gone, expected well past −80%.

If it does not, P2 does not land.

**Stress scenarios to add** (variants of a new `scroll-fit` scenario in `Sources/Stress/Scenarios/`,
the page moving every tick unless noted; each lane adds the variants its code reaches and A/Bs
them):

| Variant | Shape | Lane |
|---|---|---|
| `lazy-million-seek` | `ScrollView { VStack { Text(header); LazyVStack { ForEach(0..<1_000_000) } } }`, a `scrollTo` alternating between rows near either end every tick (the range rung: O(1) locate) | P3 (moved with locate by route) |
| `lazy-million-seek-keyed` | the same over a million `Identifiable` structs (the locate is the data scan, once per call; the frame is O(visible)) | P2 |
| `nested-seek` | an outer `LazyVStack` of 10,000 groups, each a heading over its own `LazyVStack` of 20 rows, a `scrollTo` of a row in a far group every tick (A-SCROLLFIT-4's search) | P3 (moved with locate by route) |
| `boxed-lazy` | `GroupBox { LazyVStack { ForEach(10k) } }` under a title (forward through chrome) | P3 (moved with the bordered container) |
| `app-shapes/titled-lazy`, `app-shapes/two-stacked-lazy` | a title over a `LazyVStack` of 100,000 one- and two-line entries, and two headed stacks of 50,000, scrolled three lines a tick through a `ScrollPosition` | P2, as built: variants of `app-shapes` beside `grouped-feed` rather than a new scenario, whose title and blurb would need translating into seven languages for a development tool's listing |
| `two-tables` | `ScrollView { VStack { Text; Table(10k, 4 columns); Text; Table(10k) } }`, wheel steps through both | P3 |
| `two-tables-keys` | the same, Down and Page Down in the second table every tick (cursor reveal through the outer view) | P3 |
| `titled-list` | a title over a `List` of 10,000 one-line rows | P3 |
| `titled-list-variable` | the same with rows of 1 to 3 lines (the estimate, dead reckoning) | P4 |
| `grouped-form` | `Form { … }.formStyle(.grouped)`, 40 sections of 250 rows | P4 |
| `tall-editor` | a title over a `TextEditor` of 10,000 wrapped lines, typing in the middle | P4 |
| `fixed-size-table` | `VStack { Text; Table(10k) }.fixedSize(horizontal: false, vertical: true)` in a scroll view (the ladder) | P5 |
| `boxed-eager` | `GroupBox { ForEach(10k) { Text } }` and `DisclosureGroup` of the same (windowed past 256) | P8 |
| `flow-10k` | `FlowLayout` of 10,000 tags under a title | P8 |
| `layout-list` | a `List` of 10,000 rows inside an app's own two-column `Layout` | P9 |

## 4. Sequencing

Each lane lands alone with the suite green. L0 (`NavigationSplitView`'s natural height) is
already running separately.

- **B-SCROLLFIT-10 (kept): P3 to P6 build behind one internal switch**, `scrollFitsContent`, a
  package-level environment value, false by default and set by the lanes' tests. P7 flips it and
  deletes it, so no compatibility spelling survives.
- **B-SCROLLFIT-17. P1 is a pure move.** It lifts the anchored walk into the scroll view, with
  input still in lines and output byte-identical (gate 4). That is the riskiest change: it is on
  the path of every scroll view, through seek, reveal, hold, follow, glide, overscroll, the
  position read-back, the designated anchor and the two-axis column seek. It lands first and
  alone, as its own commit series, so that everything after it is additive.
- **B-SCROLLFIT-18. A fast path only if the A/B asks for one.** If P1's or P2's A/B shows more
  than about 10% on a page with nothing windowed below its origin, such content draws as today
  (whole, then clipped), told apart by a "holds a windowing consumer" bit its measure raises.
  That costs one bit in the measure answer, and is not built unless measured to be needed.
- **The docs go in the commit whose behaviour they describe.** The step-4 rewrite (deviation
  L19, the `Table`/`List`/`Form` articles, the compatibility guide) is P7's. Locating §6b's
  "What ships" and §11 are updated by P2.
- **Each lane changes `ScrollFitBaselineTable.swift`** and the 10,000-row tests on purpose, row
  by row, as the table says.

| Lane | What | Days | `ScrollFitBaselineTable.swift` and the 10,000-row tests |
|---|---|---|---|
| **P1** | `ScrollContentAnchor` in `ScrollViewHandler` (B-SCROLLFIT-11); the fill engine (B-SCROLLFIT-12), with `_VStackCore`'s anchored window as the column shape; the derived offset by dead reckoning, held with the anchor. Content at the origin only, which is today's coverage. Byte-identical; parity harness (`frame_parity.py`); A/B. *Moved out on the way in (2026-11-11):* `ScrollPlacing` and the uniform window as fixed pitch (to P2 and P3, their first users, see 1b); drags holding their mapping (2b) and the first frame without a total (1d) to P2, since each changes what P1 must not: a drag over estimated rows draws other rows, and the first frame's rows built are a count `ScrollFitBaselineTests` pins | 6 | None. Sizes and built counts unchanged |
| **P2** | Drags hold their mapping (2b) and the first frame without a total (1d), from P1. Every placing container reads the request: the column through `VStack`; parallel through `HStack`/`ZStack`/`.background`/`.overlay`; forward through every wrapper, chrome, `TabView`, `NavigationStack`, `Section`; the off-band request; locate by route (B-SCROLLFIT-15); the focus reveal as an anchor (1e). Deletes design D's walk, `consumableScrollWindow`'s origin test and the origin mark. `scroll-fit` scenario; `grouped-feed` gate; A/B | 4 | No size changes. `tallLazyStackAlone`'s first frame 20,075 → < 100 rows built (from P1). `tallLazyStackUnderTitle` drawn whole → pulled (< 100 rows built). `lazyVStack underTitle`/`twoStacked` built 54k/104k → < 100/< 200. The `groupBox`, `tabView` and `navigationStack` rows wrap an eager `VStack` and are unchanged |
| **P2 as built** (2026-11-12) | The column through `VStack` and `LazyVStack` at any count (`StackPulledColumn.swift`); forward through bodies, modifiers, `Section`, `.padding` and the content margins (which relayed already); the off-band request; drags holding their mapping; the first frame without a total; `ScrollPlacing` (the marker the pulled column conforms to, read from the identity chain); design D's walk kept only below containers that do not pull. Moved to P3: the parallel shape (`HStack`, `ZStack`, `.background`/`.overlay`), forwarding through the bordered container (`GroupBox`, `.border()`), `TabView` and `NavigationStack`; locate by route (B-SCROLLFIT-15, A-SCROLLFIT-4); the focus reveal as an anchor (1e); and in a pulled column, a held row, the top-row hold, target layout and departing-row transitions. See "As P2 built it" under 1b | 4 | `tallLazyStackAlone` 20,075 → 124 rows built on the first frame (< 150 pinned: the measure ladder's samples count); `tallLazyStackUnderTitle` 9 × 10,000 drawn whole → 59 × 26 pulled, 119 built; `tallListUnderTitle` 16,000+ → 12,300 (the first frame's measuring walk); 3- and 60-row rows unchanged |
| **P3** | `List` and `Table` as column-shaped consumers, fixed pitch; off-band cursor row and registration; Page Up/Down by the outer viewport (B-SCROLLFIT-5); type-select checked. Behind the switch. From P2: the parallel and remaining forward shapes, locate by route, the focus reveal as an anchor, and a pulled column's held row, top-row hold and target layout | 2½ + about 3 from P2 | None with the switch off. New tests with it on |
| **P4** | Variable rows on the engine: `List`, multi-line `Table`, `TextEditor` as a lines leaf with its caret marker, grouped `Form`. Behind the switch | 3 | None with the switch off |
| **P5** | Nil-proposal answers; fillers declare (B-SCROLLFIT-7, 8); `.fixedSize` on the ladder (2f) | 1 | In the 10,000-row tests: `fixedSize` `Table` 23 → 10,003 and `tallTableFixedSize` 4,153 → < 100 rows built; already content-sized views under `fixedSize` at 10,000 go 23 → their content. The table's 3/60-row `fixedSize` rows unchanged |
| **P6** | The table's pinned header and bar (2c); the arrival reveal (2e) | 1½ | The keys test: the title stays on screen at launch. Pinned-chrome tests with the switch on |
| **P7** | The switch: defaults flipped, switch and `scrollViewportCap` deleted; `TextEditor`, nested `ScrollView`, grouped `Form`, split views content-sized; fillers' minimum; A-SCROLLFIT-2's horizontal view. Rewrites `TableInScrollViewHeightTests` and `FramedTableFillsTests`. Docs: L19, the articles, CHANGELOG, compatibility guide | 2 | Every row in the "Under SCROLL-FIT" column, e.g. `table underTitle 60` 59x24 → 59x63, `listPlain alone 60` 59x4096 → 59x62, `color alone 3` 24 → 0. Column (v) per A-SCROLLFIT-2. `ownBar` → `n` for every content-sized view |
| **P8** | A-SCROLLFIT-1's windowed containers (1c): `GroupBox`, `DisclosureGroup`, `.columns` `Form`, `Section` content outside `List`, `FlowLayout` per A-SCROLLFIT-5; the transition record for them (1g) | 3 | Sizes unchanged. Built counts of `formColumns` and `flowLayout` at 10,000 drop (`formColumns` < 100 a frame; `flowLayout` per A-SCROLLFIT-5). The baseline's `groupBox` and `disclosureGroup` wrap an eager `VStack` and stay as they are; new tests pin a `GroupBox` and a `DisclosureGroup` directly around a `ForEach` |
| **P9** | The app-`Layout` adapter (B-SCROLLFIT-13) | 1½ | None (no app `Layout` in the baseline); a new `layout-list` test |

**Total: 24½ lane-days** (P1–P9), honestly 20 to 32. P1, P2, P4 and P8 each owe an A/B.

The SCROLL-FIT defaults switch at P7, about 20 lane-days in. P8 and P9 only change what
already-content-sized containers cost, so they follow the switch rather than hold it. P1 is the
risk: if its parity harness finds the anchor cannot reproduce some path byte for byte, that path
is the lane's to fix, not to fork. The earlier estimate for design C, "multi-week", stands.

## 5. Questions for the owner

### A-SCROLLFIT-1. Eager containers' rows off screen

**Answered 2026-11-11: (a), narrowed.** A container stays eager (builds every row, as SwiftUI's
does) only where SwiftUI has a lazy counterpart and is itself eager: `VStack`/`HStack` and
`Grid`. `GroupBox`, `DisclosureGroup`, `FlowLayout`, a `.columns` `Form` and a `Section`'s
content outside a `List` build only their visible rows past a threshold, as the lazy stack does.
The owner: "(a), _only_ for types that have Lazy versions (e.g. VStack & HStack) and where
SwiftUI behaves this way." Built as B-SCROLLFIT-14 and 1c (P8).

### A-SCROLLFIT-2. The vertical axis of `ScrollView(.horizontal)`

**Answered 2026-11-11: (b).** The view proposes its own height to its content, so tables and
lists fit it and scroll themselves; content still taller keeps today's vertical scrolling. The
alternatives were (a) parity, cutting tall content off on a short terminal, and (c) unbounded,
making a two-axis view of anything tall. Built in P7 (2a).

### A-SCROLLFIT-3. Does the relay replace design C (NESTED-LAZY-PULL)?

**Answered 2026-11-11: (c), build the pull instead of the relay.** The owner, told the pull is
technically superior and more effort: "If that's accurate, then do Pull." This revision is the
result; "Superseded: the relay" says what changed and why.

### A-SCROLLFIT-4. How far a `scrollTo` looks for an id inside rows never built

*`proxy.scrollTo(messageID)` where messages sit in each day's `LazyVStack`, inside an outer
`LazyVStack` of days, or behind an app view's `body` in a lazy row nobody has drawn.*

A key a container's own `ForEach` names is found without building anything (1f). An id one
lazy level deeper is behind rows that were never built, and only building them can show it.

- **(a) Reach only what is named without building.** The keys of every placing container's own
  children, through eager children and pulled rows. **Price:** 0 extra days, and today's reach
  (when design D landed, a `scrollTo` into a nested stack did nothing either: `resolveEagerSeek`
  matches only a stack's own children, 49cbee2b3). A nested id does nothing, silently.
- **(b) ★ Search into unbuilt rows, outward from the anchor.** Build each lazy row's view value
  and, where its content is behind a `body`, evaluate it for measuring only (no `onAppear`, no
  focus registration), until the id is found. **Price:** about 1 day, in P2. A miss costs one
  body evaluation per outer row, once per call: 40 days of messages is at most 40 evaluations, and
  10,000 is 10,000, its time to be measured by the `nested-seek` scenario. Found ids land exactly.

★ (b), because an id that silently does nothing looks like a bug to an app, and the cost is
paid once per call, never per frame. A SwiftUI probe of the same shape is run first; if SwiftUI
does not reach nested ids either, (b) is still an extension no SwiftUI program can trip over.

### A-SCROLLFIT-5. Where `FlowLayout` breaks its lines

*A `FlowLayout` of thousands of tags in scroll content, which A-SCROLLFIT-1 asks to build only
the visible items.*

Each line's first item depends on the widths of every item before it.

- **(a) ★ Measure every item's width once per data change; build only the visible lines.** The
  line starts are kept, as the two-axis view keeps its widest row. **Price:** about 1 day in P8.
  A change of the data or the width measures every item (Ω(items), building each one's view to
  measure it, with no `onAppear`); scrolling builds only the visible lines. Lines are always the
  ones a top-down wrap makes.
- **(b) Wrap outward from the anchor; estimate the line starts it has not walked.** **Price:**
  about 2 days. O(visible) even on a change. But after a far jump, the lines above are made by
  wrapping backward, and can differ from a top-down wrap: scrolled back to the top, the first
  line may come out short, and the lines move once the walk meets the kept starts.

★ (a): correctness before performance, and a flow of thousands of items is rare. The change's
cost is one measure per item, not per frame.

## For a future reader

- **Paint windowing for eager rows** (Locating §5g) is not done. Eager children off band are
  rendered as memo hits so that `onAppear` and focus registration keep SwiftUI's timing
  (B-SCROLLFIT-14). Separating those from rendering would let them be skipped, with no
  observable change.
- **`LazyHStack` never windows across.** It rebuilt 9,990 items per wheel step in the baseline.
  The engine is axis-agnostic in shape (`columnSeek`/`columnReport` already travel across), so
  the mirror is a lane of its own of about 2 days, outside this ruling.
- **The off-band request (B-SCROLLFIT-2) is what keeps the memo's hit rate.** A later change
  that hands a moving request to children off screen would show as an idle-redraw regression on
  pages that do not scroll.
- **`isRow` must stay a data question** (1g). Answered from drawing, every row scrolled into a
  band would fade in.
- **The switch (B-SCROLLFIT-10) lives only from P3 to P7.** If P7 is delayed, the switch is not
  to become public API. It is deleted, not deprecated.
- **Dead reckoning is the rule that keeps the readings steady** (2b). A change that re-derives
  the offset from estimates every frame would make `onScrollGeometryChange` report motion nobody
  made.
- **Locating a key in opaque data stays Ω(N)** (Locating §12's identity tax), mitigated by the
  near-first search and the range rung. An app-supplied index is the escape hatch if it ever
  matters.

## The record

### B-SCROLLFIT-1. The window is relayed, addressed child by child

**Superseded by B-SCROLLFIT-11 and 12 (A-SCROLLFIT-3, (c)).** The relay moved the window into each
child's coordinates by the child's measured y. That y is a prefix of every sibling's height, so
every consumer had to report a total, and an estimate above moved the content below. The
arithmetic it reused (`ScrollContentWindow.beneath`, `ScrollWindowRelay.answer`) survives as the
forward shape. Full text in b5481ecf2.

### B-SCROLLFIT-2. A subtree entirely off screen is handed a still window

Kept, renamed: the **off-band request**. A child the fill does not reach gets a request that does
not change while it stays off screen, so its memo holds, and a consumer inside it draws only its
off-band rows. Handing it no request would make such a consumer fall back to being drawn whole.

### B-SCROLLFIT-3. Fixed pitch is arithmetic; variable pitch is an estimate held at the top row

Kept (1d), with one change: under the pull an estimate never places anything on screen, only
the readings in 2b. One engine, shared by the lazy stack, `List`, `Table`, `TextEditor` and the
windowed containers.

### B-SCROLLFIT-4. A pending seek names its holder

**Superseded by B-SCROLLFIT-15.** The holder was needed so that relays would build a row a band
did not reach. Under the pull the located target becomes the anchor, and the fill builds it
because it is there.

### B-SCROLLFIT-5. Page Up and Page Down move by the outer viewport

See 2d. By the list's own height, a content-sized list's Page Down would act as End.

### B-SCROLLFIT-6. On arrival, a control taller than the viewport reveals its cursor line

See 2e. Revealing the union aligned the control's top and scrolled away the title above it.

### B-SCROLLFIT-7. A filler's ideal along an unbounded axis is its minimum

See 2f. 0 for `Color`, shapes and `GeometryReader`, and a `Spacer`'s `minLength`. SwiftUI's 10
points (less than a line) was not rounded up to one line.

### B-SCROLLFIT-8. Greedy views declare it; `.fixedSize` climbs the ladder

See 2f. A filler says so with its flexibility at its minimum, and `.fixedSize` measures with the
ladder the scroll view uses.

### B-SCROLLFIT-9. A tall table's header and horizontal bar are pinned as a section's header and footer

See 2c. Reuses `OverlayLayer.ScrollPin`, `PinnedChromeViewport.pinnedRow` and `PinnedChromeCover`.

### B-SCROLLFIT-10. Built behind an internal switch, flipped and deleted in one lane

See 4. P3 to P6 land with the baseline unchanged; P7 flips and deletes the switch.

### B-SCROLLFIT-11. The scroll view holds an anchor; the absolute offset is derived

See 1b. The anchor is the row's identity, a line-source leaf's row, the lines hidden, the edge
affinity, and a per-level ladder. Input stays in lines and is walked as a delta, which is the
anchored stack's `advanceAnchor(to:)` lifted to the scroll view, so the many paths that move an
offset today keep working.

### B-SCROLLFIT-12. One fill engine; containers answer for their own children

See 1b. Five shapes (column, parallel, forward, lines, leaf) and one package protocol,
`ScrollPlacing`, which refines `LayoutPlacing`. Chosen over per-container walks because four
hand-written anchor walks would drift apart, which the code-reuse rule forbids.

### B-SCROLLFIT-13. A non-conforming view is drawn whole; an app's `Layout` is adapted

See 1b. Framework containers are tested to conform (`ScrollPull.unplacedConsumers` is zero). An
app's `Layout` is served from its own `placeSubviews` (P9, about 1½ days), because it is eager
in SwiftUI too and its placements are already paid for.

### B-SCROLLFIT-14. Eager containers build and render every child; only the band is painted

See 1b. SwiftUI's existence for `VStack`, `HStack` and `Grid` (A-SCROLLFIT-1), with off-band
children rendered as memo hits so `onAppear` and focus registration keep their timing.

### B-SCROLLFIT-15. A seek is located by routing and becomes the anchor

See 1f. Keys are found by the data scan with no row built, near the remembered ordinal first,
with an O(1) rung for integer ranges. How deep it searches is A-SCROLLFIT-4.

### B-SCROLLFIT-16. Moves are exact; absolute readings are estimates only where extents are unknown

See 2b. Readings are carried by dead reckoning, corrected at the edges, and held through a drag.
`.scrollExtentPrecision(.exact)` remains the opt-in to exact readings everywhere.

### B-SCROLLFIT-17. P1 moves the anchor into the scroll view with byte-identical output

See 4. The riskiest change lands alone and changes nothing visible, gated by a frame-by-frame
parity harness, so that every later lane is additive.

### B-SCROLLFIT-18. A fast path for content with nothing windowed, only if measured to be needed

See 4. One bit in the measure answer. Not built unless an A/B shows more than about 10% on pages
the pull gains nothing on.
