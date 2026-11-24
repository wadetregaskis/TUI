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

**Status: complete** (2026-11-14). P1–P9, P5b/P6b, the P8 leftovers and P7 are built, and P7
turned SCROLL-FIT on and deleted its switch; "As P7 built it" under 2a says what that changed
and what is left.

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
of more than four screens and more than 256 lines (a long drag, `scrollTo(y:)`, End on unknown
content) lands by estimate (2b). *Corrected after P2 (2026-11-12):* the threshold was four
screens alone, so twenty wheel ticks read in one frame on a twelve-line screen (sixty lines) were
landed by the running pitch, and a pulled stack, which walks its column's delta in its own lines,
landed rows away from where the same ticks one at a time land (`scrollWalkableDelta`,
`PulledColumnTests`' many-ticks twin). A `scrollTo`, a focus jump or a `.scrollPosition(id:)` names a row, and that row
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

*Corrected in P2's second lane (2026-11-12): `ScrollPlacing` refines nothing and asks for
nothing.* The sketch above has it refine `LayoutPlacing` and answer the engine's questions; no
caller reads a container through it, since each shape reads and answers the request in its own
render, so it is a package marker (`ScrollPlacing.swift`), read by type from the identity chain,
and a container that pulls need not be one a placement query can walk. The second lane added:

- **The forward shape through a box** (`ContainerViewCore+Pulled.swift`): `_ContainerViewCore`
  (`GroupBox`, `.border()`, every titled or footed box) files itself pulled when its body holds a
  pulled view, hands the body the request below its top line through `ScrollWindowRelay`,
  re-addressed to the body (`addressing:`, since the body is a child among two), and keeps of
  its own lines only those the band reaches (`FrameBuffer.lines(in:)`): the top line with the
  body's first row, the footer and the bottom line with its last. Its width is the body's
  measured width, not the band's, so it does not change as the page scrolls.
- **The parallel shape** (`ScrollParallelFill.swift`): `_HStackCore` (both overflows, since a
  type cannot say which it is) and `_ZStackCore` hand each pulled child the request moved by its
  place in the container — from the container's top or end by the child's, or each child's own
  position moved by the container's delta — draw every other child whole, and keep of each only
  the band. The container's lines are its tallest pulled child's (the lead's), moved to the
  lead's place; the band is the lead's, reaching the container's top or end when the lead's
  holds its first or last row. Each child stands where the eager container puts it — by the
  alignment or the explicit guides' run, across by the row's widths or the z-stack's frame — and
  the pieces are drawn through the eager container's z-order and glide (`zOrderedStackBuffer`,
  `glidingStackBuffer`), each at its place in the band as it drew, its blank lines above and
  below no cover over a sibling. `PulledContainersTests` compares every pulled shape, a guided
  row, a z-indexed one, a guided z-stack and a row whose child glides out with its eager twin,
  frame by frame. The twin is a `VStack` given `.frame(maxWidth: .infinity, alignment:
  .leading)`: a `LazyVStack` fills its width, an eager one hugs its widest row, so a box or a
  badge around the two differed by that alone. The scrollbar's column is left out of the
  comparison: the lazy stack's thumb reads its estimated height, the eager one's its exact one.
- **A pulled column entered at an edge places its anchor afresh.** A column inside a pulled
  column (a `GroupBox` is one, `VStack { label; Box { content } }`) handed a request counted from
  its top or end kept treating its anchored row as one the anchor had stayed in, whenever the
  entry landed on the row it remembered, and handed that row the position it had frames before:
  in `VStack { first; GroupBox { LazyVStack }; second; LazyVStack }`, scrolled up from the end,
  the heading `second` was stepped over. P2's own bug, which the box's pull exposed: before it the
  box was drawn whole.
- **Two relay fixes the shapes needed.** A request counted from a view's end is counted from its
  content's end, `linesBelow` further up (`ScrollContentWindow.beneath`, which subtracted
  `linesAbove` whatever the edge), and a pulled content's position is answered back through the
  relay in the view's lines (`pulledPosition`), so a column places the band by it.

Measured (2026-11-12, `ab_bench.py`, release, cpu per frame, 10 reps, base 1391cf863, busy box,
load 3.5): `app-shapes/boxed-lazy` (a title over a `GroupBox` around 100,000 entries) 687.2 →
0.59 ms a frame (−99.9%) and RSS 1,010 → 14.7 MB; every other scroll scenario within the noise
(`grouped-feed`, `headed-log`, `titled-lazy`, `two-stacked-lazy`, `sidebar`, `file-browser`,
`scrollfollow`, `glide`, `megalist`, `scrolleager`, `dashboard`, `session/log`), `session/editor`
+1.4% and `session/chat` +0.3%. Re-run with the nested-column fix and the parallel shape's
guides, z-order and glides (a27df296a, load 3.1): `boxed-lazy` 701.3 → 0.59 ms, the rest within
the noise or under 1.1% (`session/editor` +0.7%, `session/log` +1.1%). `frame_parity.py`: 154 of 156 cases draw alike; `boxed-lazy`
differs (now pulled) and `timeline-rows` differs between runs of one binary.

Still to do after the second lane:

- ~~**`TabView`, a pushed `NavigationStack` screen**~~ **and `Grid`.** The first two built in the fifth lane, below; `Grid` tried there and not landed. A tab view's content is reached by single-child steps, so a lazy stack in it is
  already pulled, but the request is not moved below the strip (the strip's lines and the
  tallest tab's padding are not relayed): its rows are misplaced by the strip, and End does not
  reach its last row (`PulledContainersTests`). A pushed screen sits below the bar as an indexed
  child. A relay below the strip alone (tried in the second lane) drew End right but not the rest:
  the tab view sizes its panel by every tab's measure, so its rows built still grew with the row
  count and its width and centring differed from the eager twin's. `NavigationStack` at its root,
  `.background` and `.overlay` already pull. *Fixed in the fourth lane:* a layer that is a view
  placed at an edge (`.overlay(alignment: .bottomTrailing) { badge }`) was laid out against the
  band, so it stood at the foot of every screen of the stack; it is laid out against the whole
  content now, as SwiftUI lays it out against the whole stack — offered the content's width and
  estimated height, placed there by its alignment, and drawn only where the band holds it
  (`pulledLayerPlacement`). A layer as tall as the content (a colour, a shape) is drawn the
  band's height: a fill draws the same over any band of it. `PulledContainersTests`' twins
  `overlayView` and `backgroundView` compare it with the eager stack's at the top, paged and at
  the end.
- ~~**Locate by route (B-SCROLLFIT-15, A-SCROLLFIT-4's (b)).**~~ Built in the third lane, below.
- ~~**The focus reveal as an anchor (1e).**~~ Built in the fourth lane: a focus move to a
  control the content holds only off its band is a seek by the focus's route. Reveal used to move
  the offset by the drawn region (`snapViewportToFocusedControl`), and for a control off the band
  — grafted at an estimate by the stack that draws it for its place in the focus ring — that
  region was the estimate: the offset landed there, the walk crossed the jump by the running
  pitch, and a pursuit closed in over the frames after. Now the scroll view, seeing the focus
  just moved to a control whose region lies outside the band (`offBandRevealSeek`), draws its
  content again with a `ScrollToRequest` whose `focusID` names the control; each container finds
  the child the id's path leads to (`seekOrdinal`, `pulledChild(holding:)`,
  `PulledParallel.holder`) instead of a key, hands the seek to it when it is pulled, and places
  it as a minimal-movement `scrollTo` places a row when it is drawn whole or is a row of its own.
  The snap then shows the control from the drawing that holds it, exactly. A control on the band
  is revealed by its region as before: its place is drawn, not estimated.
  *Fixed in the fourth lane, a regression of the pull:* the edge rows of a pulled child next to the
  focus. Shift-Tab from a control below a pulled stack whose last rows are off screen (a button
  under a 300-row stack, focused, then Home) went to the band's last row, where the stack drawn
  whole (as at 98447fc67, before the pull) went to its own last row, which a pulled stack never
  registered; Tab from the control above, the page at its end, to the band's first. A pulled
  column now tells the children beside the one the focus lies in which of their edges it stands
  past (`ScrollContentWindow.focusBeyond`, `pulledFocusNeighbours`), and the column's own first
  or last child when the column above told it; a lazy column draws such a child off its band if
  the band misses it. A stack told so draws its focusable nearest that edge off its band, as it
  draws the focused row's continuation (`focusRingStops`), and a box or a parallel container
  hands the request on as it is. `PulledFocusTests` walks it for every shape against the eager
  twin.
  *Built in the third lane:* the order of what does register. A pulled column draws its anchored
  row, then the rows below, then the rows above, nearest first, then its children off the band;
  so the controls above the anchor were filed in the focus ring after the ones below, and Tab
  from the band's last row went back up to a row above it. Those above are now filed at the
  place the column's first row would take (`FocusManager.registering(at:_:)`,
  `FocusSection.registrationPlace`), each ahead of the one drawn before, so the ring is in the
  rows' order (`PulledFocusTests`). And a scroll view that draws its content a second time in a
  frame (the reveal moved it) takes back the first drawing's registrations
  (`RenderWalkCheckpoint.rewind`, `FocusManager.rewindRegistrations(to:)`), as it takes back its
  handler ids and key handlers: kept, the row the second drawing brought on screen above the rest
  was filed after them all, and Tab from the control just revealed skipped it.
- **What the outermost stack did that a pulled column does not yet** (built in the fifth lane,
  below, but the departing-row transitions and a row held outside the anchored child): a row held by
  `.anchorPosition(.row(id))`, the top-row hold, `scrollTargetLayout` and the visibility
  observers' rows, and the eager stack's departing-row transitions. A pulled column takes over
  only from a column that holds a pulled child, which before P2 drew that child whole.

  *Still not built after the fourth lane,* which took the regressions, the reveal as an anchor
  and the layer views over a band: these, the write frame's rows, and `TabView`, a pushed
  `NavigationStack` screen and `Grid`. What it found on the way: a pulled column hands its
  children requests that do not carry `reportsTargetLayout` or `reportsTargetVisibility`, so a
  `scrollTargetLayout()` stack inside one reports no rows for a behaviour to settle on; the
  rows would also have to be moved from the child's lines into the column's. Nor do they carry
  `topRowHold`, and a stack handed one rebinds its anchor by ordinal, not key
  (`rebindingAnchor`, `rebindAnchor(holdsRow: false)`), so rows inserted above a pulled
  stack's anchor would, by a reading of the code (not tested), move its rows on screen where
  the outermost stack holds them; a pulled column's own children are rebound by key. The write
  frame over sections (506 rows built at 40, 986 at 320, `PulledColumnTests`) was not traced: the
  natural-extent ladder steps past an answer above its rung in one step (`naturalExtent`'s
  informed step), so the extra rung the second lane named needs an answer that grows between
  two measures, which a sample measured at a taller rung could give; unmeasured, it is a
  write frame's cost growing by about 480 rows per eightfold height, not per row.

  *Built in the fifth lane (2026-11-12), which closes P2:*

  - **Target layout and the visibility observers.** A pulled column hands its pulled children
    `reportsTargetLayout` when the scroll view has a behaviour and the column is not marked
    itself, and answers up the rows of the marked stack a child is (the anchored child's, or the
    first drawn that has some), moved by the column line the child's line 0 falls on. Marked
    itself, it reports its own children as the fill placed them, and takes the mark off theirs.
    For the visibility observers it reports its own children, as the eager column it took over
    from did. `PulledTargetLayoutTests` twins `.viewAligned` and `.paging` over a stack under a
    title against the same lines as one top-level stack (its first row the title, keyed alike,
    so it too draws by the anchored window): every tick and page lands alike.
  - **The top-row hold.** The anchored child, handed `.position`, is handed the scroll view's
    `topRowHold`; it rebinds its top row by key as the outermost stack does, and the column moves
    its offset, and every piece, by the lines the change put above that row
    (`holdingRow`), reporting the offset as the hold's. Not the key rebind the fourth lane
    suspected: a stack handed a hold does rebind by key (`rebindingAnchor`'s held-row branch);
    it was the hold that never reached it.
  - **A held row.** The scroll view's `.anchorPosition` binding is handed with the request to the
    anchored child (`ScrollContentWindow.holdsDesignatedRow`), which holds the row as the
    outermost stack does; the column follows its offset as for the hold. *Not built:* a row held
    in a child other than the one the viewport's top lies in (a title at the top, the held row in
    the stack below it) is not held. The column would have to find the child that holds the key
    (a nested search, once per designation) and move its anchor there at the row's place.
  - **The write frame.** Traced rung by rung (a temporary print in `naturalExtent` and of each
    row built, over `PulledColumnTests`' sections paged once and written): at 40 sections the
    ladder measured 4,096 → 4,096 (480 rows) and 32,768 → 12,040
    (240), at 320 a third rung, 262,144 → 96,320 (240 more). The outer stack's estimate was capped
    at each rung, and a cap says nothing past it, so the ladder climbed by eight. On the ladder's
    budgets (`isNaturalExtentBudget`, no proposed height) a pulled column's anchored estimate is
    now answered whole (`sampledRows`' `answersWhole`, for a stack that `pullsItsRows`; any other
    keeps the cap, as an eager stack does under a budget, `LazyStackSemanticsTests`), and the
    ladder's informed step clears it in one rung: two rungs whatever the height, 746 rows in that
    trace at 40 sections and at 320. `PulledColumnTests` bounds the count at 746 for 40, 320 and
    2,560 sections rather than pinning it: a full run gave 506 at 40 and 746 at 320, one rung's
    sample served by a pass's memo or not by what ran before in the process.
  - **A lazy stack in an `if` among a column's views** (found by the P9 lane in an app's `Layout`)
    was not pulled where it stood: an `if` holds its view as its child at index 0, a sibling step,
    under an `Optional` (no `else`) or the branch an `if`/`else` took, and neither is
    `ScrollPlacing`. Its measure walked every row on the first frame (33,165 rows built at 10,000);
    the request reached it all the same, since the view is laid out among the column's children,
    so later frames drew a band. `isPulledWhereItStands` passes an `if`'s identity through
    (`holdsItsChildrenForAContainer`). *Found on the way, not fixed:* twenty wheel ticks in one
    frame up from the end of two stacked lazy stacks (`PulledColumnTests`' `twoStacked`, with or
    without the `if`) land about two dozen lines short of where the same rows drawn eager land;
    a tick at a time they match. Not traced.
  - **`TabView` and a pushed `NavigationStack` screen** forward through `PulledChromeRelay`, the box's
    relay made package-wide (the box uses it too): each files itself pulled once its measure has
    measured the child (`notePulledContainer`, after the measure — filed before it, on the first
    measure nothing below had filed yet, and the memo kept the measure from running again), hands
    the child the request below its strip or bar, addressed to it, and keeps of its own lines only
    those the band reaches. The tab view tells its tab's request the panel's filler below it (the
    tallest tab's height less the selected one's) and pads a band only by that, not to the panel's
    whole height, and centres the band as the whole tab, by its natural width. The pushed screen
    pads a band to the screen's width only. `_NavigationStackCore` is `ScrollPlacing`, its screen
    being a child among the others it keeps. In `PulledContainersTests` both tab styles and the
    pushed screen draw what their eager twins draw at the top, paged and at the end. The tab views'
    twin hugs its widest row: a tab view sizes its panel by its tab's measure, and a `LazyVStack`'s
    measure is its widest row's, so a lazy stack in a tab is as wide as its rows, not the panel (as
    before the pull; SwiftUI's lazy stack is flexible across, a parity question for P7's widths).
    Their rows built are bounded alike at 1,000, 10,000 and 100,000 rows rather than equal: the tab
    view measures its tab at two heights (the panel's and the drawn), so where the measuring ladder
    lands against the stack's estimate moves a sample between steps. A pushed screen is a focus
    section of its own, which takes the keys from a scroll view around its stack, so its tests
    scroll by the wheel.
  - **`Grid` — tried, not landed.** A lazy stack in a `GridRow` cell is still drawn whole (a
    probe: 63,081 rows built for the first frame at 10,000 rows, 7,008 at 1,000). The lane drew a
    filed-pulled grid as a band of its lattice's lines, its cells eager, a pulled cell handed a
    request from its top when the band reached that, from its end when the band reached that, and
    otherwise its own position from the frame before moved by the grid's scroll (kept at the
    grid's identity). Its twin matched at the top, over three pages and at End, but Page Down
    stalled near row 215 of 300: the cell's place in its own lines and the lattice's estimate for
    it disagree mid-scroll — most likely the stack clamping a handed position at its own estimated
    end, shorter than the lattice's (not traced). What is left is to place a pulled cell's row by
    what the cell drew, as a column places a pulled child, rather than by the lattice's estimate:
    about a day. The attempt is not in the history.

**As the fourth lane measured it** (2026-11-12, `ab_bench.py`, release, cpu per frame, base
b52006fe7 against the lane's tip 7647fbbaa, a busy box, load 7.5): `app-shapes` +0.1%,
`grouped-feed` +0.2%, `two-stacked-lazy` +0.5%, `headed-log` +0.3%, `megalist` −0.9%,
`scrolleager` −0.9%, `glide` +0.3%, `dashboard` +1.5%, `session/editor` −0.5%, `session/chat`
+0.9%, `session/log` −0.2%: indistinguishable; `boxed-lazy` +0.4% [+0.1, +3.0], `titled-lazy`
+1.9% [+1.2, +3.0] and `scrollfollow` +0.7% [+0.1, +1.4] slower, under the owner's few-percent
line (a pulled column's search for the child the focus lies in, each frame a focus exists, is
the likeliest cost; not profiled). RSS within 0.6 MB everywhere. `frame_parity.py`: 155 of 156
cases draw alike, `app-shapes/timeline-rows` the one that differs between runs of one binary.

**As the fifth lane measured it** (2026-11-12, `ab_bench.py`, release, cpu per frame, base
ceeec40be against the lane's tip before its rebase onto P9, a701fa1a7, load 2.9): `app-shapes`
−0.4%, `grouped-feed` +0.5%, `titled-lazy` −0.3%, `two-stacked-lazy` +0.8%, `headed-log` +0.2%,
`megalist` +0.9%, `scrolleager` +0.3%, `scrollfollow` +0.5%, `glide` −0.8%, `dashboard` −0.6%,
`session/editor` −0.2%, `session/log` +0.1%: indistinguishable; `boxed-lazy` +0.5% [+0.2,
+2.2] slower and `session/chat` −0.2% faster, both inside the owner's few-percent line. RSS within
1 MB everywhere. `frame_parity.py`: 155 of 156 cases draw alike, `app-shapes/timeline-rows` the
one that differs between runs of one binary. *The fourth lane's `titled-lazy` +1.9%:* profiled
(Time Profiler, all processes, `--process Stress`, 8 s of `Stress --bench --scenario app-shapes
--variant titled-lazy --cols 120 --rows 40` at ceeec40be, `analyze_timeprofile.py`): the pulled
column is 24.3% of the frame inclusive (1,853 of 7,626 ms), and of it the search for the child the
focus lies in, `pulledFocusNeighbours`, is 1 ms (0.0%) and `drawOffBand` 8 ms (0.1%). The
suspected cost is not there, so there is no cheap remedy to make: nothing changed, and the lane's
own A/B finds `titled-lazy` where the base has it.

**As the third lane built it (2026-11-12): locate by route** (`StackNestedSeek.swift`,
`StackPulledSeek.swift`, `ScrollKeyLocate.swift`). A seek whose key no row of the resolving
container carries is searched for below its rows, level by level:

- **The search measures, never draws.** The container measures each row in a context with no
  render cache (no memo read or kept, nothing filed as pulled), measuring (no `onAppear`, no
  focus registration) and a `ScrollKeyLocate` in the environment. A `_VStackCore` measured so
  looks for the key among its own rows by the data's keys, building none, and while the search
  may go deeper measures its rows in turn; a nested `ScrollView` stops it, its own content
  being its own seek's. Each round goes a level deeper, until the key is found or no stack the
  round reached had rows left to look below (at most eight levels). A key one level down costs a
  measure of each row before its own, twice; a miss costs a measure of every row on every level
  there is, once per call, A-SCROLLFIT-4 (b)'s price.
- **A pulled row is handed the seek.** The column anchors on it, at the viewport's place in it
  (clamped to a screen off its near edge when it is far: a stack given an offset tens of
  thousands of lines away placed no band), hands it the request with `linesAbove`/`linesBelow`
  the column's estimates around it (what the row's clamp and indicator headroom read), and moves
  its own offset, and every piece it placed, by where the row's answer put the viewport's top
  (`pulledPosition`). So each level resolves the seek among its own rows; a box relays it as it
  relays any request, and the parallel shape hands it to its lead and re-hands its other pulled
  children their place below the container's new top. *Built in the fourth lane:* the seek goes
  to the child below which the search finds the key (`PulledParallel.holder(of:)`): handed to
  it when it is pulled, the container's lines then moving by where it put the viewport's top;
  aimed at the key's place in it when it is drawn whole (a stack of 256 rows or fewer), the
  container's position worked out from that place (`aimedOffset`); either way every other pulled
  child, the lead among them, is handed its place below the container's new top. With no child
  holding it, the lead is handed it, as before. So a key in the shorter of two lazy stacks side
  by side is found. At 98447fc67 neither the lazy nor the eager page found it: not a regression.
  Two `LazyVStack`s side by side split the row's width otherwise than two filling `VStack`s
  (as at 98447fc67 too), so their twin is compared by the line the key lands on.
- **A row drawn whole is aimed into.** The row is drawn once for the key's place alone, measuring
  and with no cache: the child the key names stamps two geometry markers on its drawing
  (`seekTargetTop`, `seekTargetEnd`), which every container moves with what it draws, so the
  row's drawing says where the key's view is in it and how tall, whatever lies between. The seek
  then aims at that line of the row, in the pulled column, the anchored and the uniform windows,
  and the eager stack alike. *Corrected:* 1f's "nothing new is built" is A-SCROLLFIT-4 (b)'s
  search now, and a row drawn whole is a leaf (B-SCROLLFIT-13) whose inside the pull does not
  see, so the key's line in it is read from the row's own drawing. That is not the disqualifier's
  case: the row is drawn whole whenever any of it is on screen, and is drawn here once per call,
  off screen, for its own size.
- **Minimal movement** reads where the target is from the anchor: on screen, nothing moves (the
  pulled column's own-row seek used to move it to an edge regardless); off it, to the edge it is
  past. A pulled column's own row is placed from the rows above it summed where its walk measures
  across a jump, rather than at the running pitch, which in a column of a title over a stack of
  800 rows put the stack's top hundreds of lines low.
- `ChildViewCollection.seekOrdinal(forKey:)` matches a `.id(_:)` on a column's own child too, as
  the eager seek does, which a pulled column's seek did not.

`PulledLocateTests` lands a row at `.top`, `.center`, `.bottom` and by minimal movement under a
title, in the second of two stacks, in a box, beside a gutter and in the rows of an outer lazy
stack (pulled, and of twenty rows drawn whole), each against the same rows drawn eagerly, and
pins the rows a seek's frame builds under a title as the same at 1,000 and 10,000 rows.

Measured (2026-11-12, `ab_bench.py`, release, cpu per frame, base 09da5c3cd against the third
lane's locate and focus-ring commits, load 3 to 10): `app-shapes` −0.3%, `megalist`, `scrollfollow`,
`glide`, `dashboard` and `session/editor` indistinguishable, `scrolleager` +1.7% [+0.5, +2.0],
`session/chat` +0.4%, `session/log` −1.2%; the pulled variants `grouped-feed` +0.5% [+0.1, +2.3],
`boxed-lazy` and `headed-log` indistinguishable, `titled-lazy` −0.9%, `two-stacked-lazy` −0.7%.
RSS within 1 MB everywhere. What a frame with no seek pays is a render-cache test in
`ChildView.render` and in `_VStackCore`'s measure and render, and a focus mark per pulled column
and per scroll view drawn: under the owner's few-percent line. `frame_parity.py`: 155 of 156 cases
draw alike, `app-shapes/timeline-rows` the one that differs between runs of one binary; `Stress
--selfcheck` clean.

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

**As P9 built it** (`LayoutCore+Pulled.swift`, 2026-11-12). Not a column-or-parallel choice
but both at once, by the rects. The render already runs `sizeThatFits` and `placeSubviews`; a
layout filed as holding a pulled view hands the placements to the parallel shape
(`PulledParallel.fill`, `ScrollParallelFill.swift`): each pulled subview is handed the request at
its placed y, every other one is drawn whole at its own and cut to the band, and the whole is
drawn through the eager path's glide and z-order (`composited`, `LayoutCore+Composite.swift`).
A subview placed wholly below the tallest pulled one (the lead) *follows* it
(`PulledParallelChild.follows`): it is moved by how far the lead's drawing ends from where its
estimate put it, since the layout placed it from that estimate. So a top-to-bottom flow is
served as a column for what comes after the stack, and a two-column layout as a parallel row.
What the rects cannot serve is drawn whole: pulled subviews not beside the lead (two lazy
stacks one below the other, whose places hang on each other's drawing) or a pulled subview
placed twice. The measure decides it, so the first frame is right: a layout whose measure
files it as holding a pulled view runs `placeSubviews` there too, and when the rects fail it
files itself as drawn whole (`PullConsumers.noteLayout(_:places: false)`), drops its subtree's
measures and measures again, its stacks now not pulled where they stand (design D's walk, as
before P9).

- **The layout has no identity of its own.** `_LayoutCore` is drawn at the identity of what holds
  it (a branch, an `AnyView`, an app's `body`), so its type is often not on its subviews'
  identity chain, which is how `isPulledWhereItStands` knows a `_VStackCore` row. Each layout in
  scroll content files the identity it is drawn at before it measures its subviews
  (`noteLayout(_:places: true)`), and that filing answers for the step before any type does.
  `_LayoutCore: ScrollPlacing` answers where it has a node of its own. The registry is cleared
  with the rest of `PullConsumers` past its capacity.
- **A measuring render.** The first frame's measuring walk gives the scroll content only the
  lines down to the viewport's bottom, and a lazy stack under a measure takes no request; the
  eager layout drew each subview at its placed height regardless, so it built every row of the
  stack's estimate. A layout holding a pulled view draws a pulled subview under a measure only
  down to the lines it was given (`measuringHeight`), as an `HStack` clamps to its offer.
- **Seeks and focus** go through the parallel shape's (`holder`, `place`); a seek aimed at a
  subview drawn whole that follows the lead lands by the layout's estimated place for it.
- ~~**Not pulled:** a lazy stack in an `if` among the subviews.~~ Its node is a sibling step under the
  branch's, which no container files or conforms for — the same rule for every container, not
  the layout's; found by a trace of the reach test, left to the lane that owns the column's
  internals. *Pulled since the fifth P2 lane* (`isPulledWhereItStands` passes an `if`'s identity
  through, after a layout's filing, since a layout is drawn at its holder's identity, which may be
  an `if`'s: `PulledLayoutTests`' `flowIf`). Not `List` or `Table`, which nothing pulls before P3; when they file themselves as
  consumers, a layout hands them the request as it hands a stack.

`PulledLayoutTests` twins a flow, a two-column layout and a flow spaced by a `LayoutValueKey` and
the subviews' spacing (each around 300 rows of one and two lines) against the same layouts
around an eager `VStack`, at the top, paged, wheeled, at the end, wheeled back and at Home, and a
flow of two lazy stacks, drawn whole, the same way; pins the rows built a frame under 100 and
equal at 1,000 and 10,000 rows (first frame, five pages, two wheel steps; End under 100), End at
10,000 rows, and the wheel through all 10,000. `PulledLayoutReachTests` lands a `scrollTo` of row
6,000 of 10,000 at the top building under 100 rows, runs Tab against the eager twin, and
Shift-Tab from the footer to the last row. Before P9, the 10,000-row first frame built 43,081
rows (flow) and 63,081 (two columns), and the seek 118,194.

Measured (2026-11-12, `ab_bench.py`, release, cpu per frame, 10 reps, base 8eda5ac70, which is
ceeec40be with the new variant, load 9 falling to 2.6): `app-shapes/layout-list` 167.8 → 0.79 ms
a frame (−99.5%) and RSS 144.5 → 14.8 MB; `scrolleager` −0.7% [−2.4, −0.0]; `titled-lazy`,
`boxed-lazy`, `grouped-feed`, `headed-log`, `two-stacked-lazy`, `sidebar`, `customlayout`,
`megalist`, `scrollfollow`, `dashboard`, `grids` and the sessions `editor`, `chat` and `log`
indistinguishable. `frame_parity.py`: 155 of 157 cases draw alike; `layout-list` differs (now
pulled; not compared frame by frame beyond the twins, which leave out the scrollbar's column)
and `timeline-rows` differs between runs of one binary.

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

**As P8 built it** (2026-11-12, `ImplicitColumnWindowing.swift`, `FlowLayoutWindowing.swift`).
No `existence` protocol: each of these containers draws its content as an implicit column, a
`ForEach` with nothing to lay it out (`renderStackedVertically`), and that column is what windows.

- **`GroupBox`, `DisclosureGroup`, a `Section` drawn as one view.** Each marks its content on the
  identity chain: `windowingItsRows()` draws it one step down, typed with the marker view, and
  `_SectionCore` is that step for its own; both conform to `WindowsItsImplicitColumn`. (First built
  as a depth written into the environment, which cost `boxed-lazy` +4.9%: a copy of the
  environment's dictionary on every measure and draw of a box's body.) A `ForEach` reached from
  there by single-child steps, in scroll content, with
  more than 256 elements (`anchoredWindowThreshold`) is drawn as a `LazyVStack` at its own identity
  (`ForEach.windowedColumn`), so each row keeps the identity it has drawn whole and the box's
  forward shape pulls it as it pulls a lazy stack. A `ForEach` inside a row, or one a stack in the
  box lays out, is not the container's column and is built as before. The column fills the width
  it is offered, as a lazy stack's band does (`windowedColumnSize`): a column drawn whole hugs its
  widest row, which only every row measured can say, a sample's widest would cut a wider row
  further down, and the widest drawn so far would widen the box as the page scrolls. So past 256
  rows a box is as wide as its parent offers. Rows built (`WindowedContainersTests`, 30 × 12): a
  page 12 to 30 in a box, 18 in a section, 76 to 94 in a disclosure group, the same at 2,000 and
  10,000 rows; a first frame 96, 114 and 144. The disclosure group's extra is the focus
  continuation probe (`focusRingStops`): its button holds the focus at launch, and the column
  below it looks through up to 64 rows for the focusable nearest its top each frame.
- **A bare `OutlineGroup`** (2026-11-17). Drawn on its own, as a scroll view's whole content (the
  shape its doc example uses) or a container's column, it had no drawing at all: `body` is `Never`
  and it was not `Renderable`, so the renderer fell through to an empty buffer and
  `ScrollView { OutlineGroup(…) }` drew a blank screen. Its `body` is now a private
  `_OutlineGroupCore` (`OutlineGroup+Drawn.swift`), so modifiers and the environment reach its rows
  as CLAUDE.md asks of a public control, while a stack, `List` or `Section` still takes the outline
  apart by its own conformances before asking for the body. The core stacks the rows as a `ForEach`
  drawn on its own does, and past 256 open rows in scroll content draws them
  as a lazy stack at its own identity, by the same helper a windowing container's loop uses
  (`_VStackCore.implicitColumn`). Unlike a `ForEach`, it windows wherever it is drawn on its own,
  not only as a windowing container's column: an outline is itself the container, and has no lazy
  counterpart. Its rows come from the kept visible nodes (`OutlineVisibleNodes`) as a lazy child
  collection, so a lazy stack of it, `LazyVStack { OutlineGroup }`, builds only the rows it draws
  as well. Perf case `outline-scroll`.
- **Not windowed:** a container's content of several views (`GroupBox { header; ForEach }`), whose
  `TupleView` resolves its children eagerly, building every row to count them; the `.columns`
  `Form`, whose label pillar and content width are read from every row on every frame, from an
  extraction that builds each row (`extractFormElements`), so a band would save the drawing and
  none of the building. Windowing it needs those two widths kept per data change, which the
  extraction has no signal for: about a day.
- **`FlowLayout`, A-SCROLLFIT-5 (a).** Past 256 items in scroll content, `_LayoutCore` breaks the
  flow's lines from the top, as `placeSubviews` does, and draws them as the rows of a lazy stack
  (`windowedFlow`, `_FlowLine`), each item at its identity under the flow, not its line, so a line
  break that moves leaves its state and focus where they were. The items are measured for their
  lines at one height whatever the pass (`flowItemMeasureHeight`), and the flow retains its
  subtree's kept measures (`RenderCache.retainSubtree`; without it `removeInactive` pruned the
  measures of the items off screen, and past about 2,000 items every step measured them all twice),
  so a loop over equatable data keeps each item's measure from frame to frame and only a change of
  the data or the width measures them again. A non-equatable loop builds every item each frame to
  measure it, as before. A line on screen draws its items afresh each frame (about 150 a wheel step
  at 60 × 24), where a lazy stack's rows come from the memo: not traced.
- **Transitions (1g).** The windowed column and the flow's lines are a lazy stack's rows, so they
  take its record (`WindowedRowFade`): a row scrolled in comes without a fade, a row an animated
  change inserts fades in (`WindowedRowFadeTests`' boxed rows).
- **Measured** (2026-11-12, `ab_bench.py`, release, cpu per frame, 10 reps, base 320320509, which
  is c9f7d884b with the two new variants, tip 87c8504c5, load 5 after builds at 12 to 17):
  `app-shapes/boxed-eager` (a title over a `GroupBox` directly around 10,000 entries) 88.7 → 0.55 ms
  a frame (−99.4%) and RSS 94.8 → 14.6 MB; `app-shapes/flow-10k` (a title over a `FlowLayout` of
  10,000 tags) 202.7 → 28.5 ms (−85.9%) and RSS 104.4 → 88.3 MB, the rest its measure of every item
  through the memo each frame and its lines on screen drawn afresh; `grouped-feed` −0.5% and
  `headed-log` −0.4% faster; `app-shapes`, `titled-lazy`, `layout-list`, `megalist`,
  `scrolleager`, `scrollfollow`, `glide`, `dashboard`, `grids`, `customlayout` and the sessions
  `editor`, `chat` and `log` indistinguishable; `boxed-lazy` +4.7% [+3.6, +5.7], fixed by the
  marker on the identity chain (tip 99ccb7697, load 3.5: +1.2% [−0.3, +2.2], indistinguishable).
  `frame_parity.py`: 157 of 159 cases draw alike, `flow-10k` among them; `boxed-eager` differs (now
  windowed, and as wide as the page) and `timeline-rows` differs between runs of one binary.
- **`Grid`: drawn whole.** A grid stays eager. A lazy stack in a cell, and a grid among a pulled
  column's children, are drawn as their eager twins draw them at the top, paged, wheeled and at
  the end (`PulledGridTests`); the stack in a cell is drawn whole, every row built (design D's
  walk), as before. The fifth P2 lane's plan, placing a pulled cell's row by what the cell drew,
  stays the next step (about a day): this lane spent its time on the containers above. (Built
  otherwise in P8's leftovers, below.)

**P8 leftovers as built** (2026-11-14). What P8 left, each pinned by a twin (the same rows drawn
whole, `drawsContainerRowsWhole`) with the switch off and on, and by a count of rows built that
failed before:

- **A container's content of several views, a long loop among them** (`GroupBox { header;
  ForEach(rows) }`, the same in a `DisclosureGroup`; `ImplicitColumnWindowing.swift`). The cause:
  the content's `TupleView` drew its views stacked whole, and its loop, a sibling step under it,
  was not the container's column, so every row was built every frame (240,000 rows on the first
  frame at 10,000, then 10,000 a page). Now, in scroll content and when one of the views is a loop
  past 256 elements (written bare or in an `if`), the content is drawn as a column of its views
  at a step of its own (`_ImplicitColumnOfSeveral`, a `ScrollPlacing` marker), the loop one child
  of it (`ForEach.staysWhole(in:)`) drawn as the lazy stack it is drawn as alone. So the column
  pulls the header whole and the loop's band: a page builds the same rows at 2,000 and 10,000
  (`WindowedContainersTests`' `headedGroupBox` and `headedDisclosureGroup`). The views' identities
  are the column's, not those of the views stacked whole, so a loop that grows past the threshold
  starts its rows' state afresh, once. A `Section` drawn as one view with several views in its
  content still draws them whole.
- **A lazy stack in a `Grid` cell** (`GridCore+Pulled.swift`). The cause: a cell's identity is a
  sibling step under its `GridRow`, and neither the row nor the grid was a container that pulls,
  so the stack was drawn whole, design D's walk building 64,119 rows on the first frame at 10,000.
  Not the fifth lane's band of the lattice: the grid is now served as an app's `Layout` is (P9,
  `LayoutPull`, the adapter's reading of placements by rects made package-wide for it), each cell
  at the place the lattice gives it, the cells beside the pulled one in the parallel shape and the
  rows wholly below it following where its drawing ends, so no estimate of the lattice places
  anything after it. `GridRow` is `ScrollPlacing` (its cells are laid out by whatever lays the row
  out, as an `if`'s view is), and `_GridCore` files itself as placing before its cells are
  measured; a grid whose places cannot be served (two pulled cells one above the other) is filed
  as drawn whole and measured again, as a layout is. `PulledGridTests`: the twin matches at the
  top, paged, wheeled and at End; a first frame builds 171 rows and a page 20 to 30, the same at
  2,000 and 10,000.
- **A `.columns` `Form` of a long loop** (`FormColumnsWindowing.swift`). The cause, as P8 found
  it: the form extracts every row each frame to classify it, and reads its label column and its
  rows' width from all of them, then lays out every row in an eager column (50,000 rows built a
  page at 10,000). Now a form whose content is a loop of more than 256 elements over comparable
  data (`listRowsSignature`), in scroll content, keeps those widths at its identity, read once
  from every row at each width it is laid out at (eight at most) and again only when the data or
  the labels' visibility changes, and draws its rows as a lazy stack framed to the width the whole
  column hugs, each row extracted only when drawn. The signal the extraction lacked is the
  loop's data: a row whose label changes with something other than the data keeps the old column
  until the data changes, as a `List`'s hugged width does (`_ListCore.widestRowWidth`). A loop over
  data that cannot be compared, a grouped form and a form of several views among which a loop
  stands still extract every row. `WindowedFormColumnsTests`: the twin matches with the switch
  off and on, the column follows a change of the data, and a page builds 26 rows at 2,000 and
  10,000 (the first frame 20,177 at 10,000, every row read at two widths).
- **The nested-stack pages' +1.6–3.0%** (P3's A/B: `titled-lazy`, `two-stacked-lazy`,
  `boxed-lazy` against P2's tip c9f7d884b). Not the pull. Bisected with `ab_bench.py` (release,
  cpu per frame, 10 reps, `slot.py --exclusive`): c9f7d884b → ba1ea499b (`.focusable(false)`'s
  bullet) −0.3% and −1.2%, → cbce33b63 (the walkable delta) −1.0% and +0.4%, → c1e6beb77 (the
  pull test as a `RenderContext` function) −1.0% and +0.1%, all indistinguishable or faster; then
  c1e6beb77 → 353baee99 +2.5% [+1.3, +3.7], +1.8% [+0.7, +4.5] and +1.2% [+0.3, +2.6], a range
  whose only change on these pages' path is the Stress page itself: P3 added the `titled-list` and
  `titled-table` cases to `PulledPageApp`'s `switch`, and a view builder nests a switch's
  conditionals deeper as cases are added, so every row of every variant sat one conditional
  deeper. The profile agrees (Time Profiler, 8 s of `two-stacked-lazy` at 9db53e79a,
  `analyze_timeprofile.py --process Stress`): `ConditionalView.renderToBuffer` 66.5% inclusive,
  `IdentityNode.structurallyEqual` 1.5% self. The remedy is the benchmark's: the page's content is
  an `AnyView` built by a plain `switch`, every shape at one depth (`structurallyEqual` 1.1% self,
  no `ConditionalView` on the stack), so a shape added to the catalogue no longer taxes the rest.
  Against 9db53e79a: `two-stacked-lazy` −2.5% [−3.6, −0.4], `boxed-lazy` −3.0% [−3.7, −0.3],
  `titled-list` −3.6% [−5.1, −2.2], `titled-lazy` −3.8% (indistinguishable on a busy box, load
  5.2). Not a framework change, so nothing on an app's path moved: deep conditionals cost an
  app what they cost the page. On the way: 9db53e79a draws `titled-lazy` at 787 µs a frame
  against P3's 269 µs, most likely because P3's page did not move: the harness composed no rows a
  frame there and 32 at 9db53e79a, and 989c60504 since made a `ScrollPosition` bound with a new
  value scroll (not traced).
- **Measured** (2026-11-14, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py
  --exclusive`, base 9db53e79a with the flattened page against the lane's tip, load 6.3):
  `boxed-eager` +0.9%, `flow-10k` −0.2%, `titled-lazy` −0.1%, `two-stacked-lazy` +0.7%,
  `boxed-lazy` −2.2%, `layout-list` −2.0%, `grouped-feed` 0.0%, `headed-log` −0.1%,
  `settings-form` −0.7%, `grids` +1.0%, `customlayout` 0.0%, `dashboard` −0.9%, `megalist` −0.5%,
  `session/editor` −0.8%: indistinguishable, RSS within 0.6 MB but `flow-10k`'s 6.8 MB less. That
  tip still drew a loop a stack in a box lays out as one lazy child (13a0e81cc fixed it); at the
  fixed tip (load 2.7) `boxed-eager` −0.1%, `boxed-lazy` −0.4%, `titled-lazy` +0.2%,
  `two-stacked-lazy` −0.1%, `layout-list` −0.2%: indistinguishable. `Stress --selfcheck` clean
  (139 cases, 26 sessions); the full suite passes (`parallel_test.py`, 15,714 tests); `api_baseline.py` records `ForEach.staysWhole(in:)`, the
  witness of `ChildViewProvider`'s requirement the column of several needs. Not run:
  `frame_parity.py`. Left: a `Section` drawn as one view with several views in its content; a
  columns form of several views, of data that cannot be compared, or grouped; `LazyVStack {
  header; ForEach(10k) }` itself still builds every row on its first frame (50,009 at 10,000, a
  `TupleView` resolving its loop eagerly), though not on the frames after.

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

**As P3 built it** (2026-11-12, `PulledBand.swift`, `_ListCore+Pulled.swift`, `Table.swift`'s
"SCROLL-FIT's pull"). Behind the switch, `EnvironmentValues.scrollFitsContent` (package-internal,
off by default, B-SCROLLFIT-10): with it off nothing reads any of this, and every frame is as
before. With it on, a `List` or `Table` in scroll content, given no height, that a column pulls
where it stands (`RenderContext.isPulledWhereItStands`, P2's reach test moved onto the context so
a view outside the stacks' module can ask it) and whose rows are one line each, is a *band
consumer*, filed `.bandsRows` as a windowed lazy stack is:

- **Its height is arithmetic.** The chrome above the rows (a border, a borderless title, a
  table's header), a line a row, the chrome below: the measure answers that total, held, and no
  row is built. A list counts its rows from its `RowSource` (O(1) for a `ForEach`) and asks its
  container what it keeps of a tall height for the chrome; a table's are its border and header
  lines. Fixed pitch only: a table on its multi-line layout (lines above one, or sections), a
  list whose rows are not all content (sections), an empty one, a custom table style or columns
  that scroll sideways are drawn as before (P4's). A list's one-line rows are B-SCROLLFIT-3's
  uniform hypothesis: taken until a band draws fewer rows than its lines (a row of two lines),
  then refuted for good (`ListPulledPitch`, state index -83) and the scroll view told to measure
  again (`measureWentStale`).
- **The band is the view framed to its rows.** `PulledBandRequest` reads the request (its edge,
  and a seek or a focus reveal placed by the rule every seek shares) as a band of the view's
  lines; the view draws itself as it would framed to the rows that band holds — its own window
  walk, cursor, selection, clicks and regions — from the band's first row, with no indicators of
  its own and its own scrolling handed to the scroll view (`isScrollEnabled` off, so the wheel
  chains out; `scrollTo` not registered with the reader), cuts the drawing to the band's lines
  (`FrameBuffer.lines(in:)`, now package), and answers the band, the total, its ends and the
  position. With no request — the first frame's measuring walk — it draws its top, no further than
  the walk's lines or a viewport.
- **Focus (1e).** The list or table registers its one focus stop whenever it is drawn, and a
  column draws an eager column's children off the band, so Tab reaches it. Its whole-control
  region reaches, for a reveal, every line outside the band (`revealOutsetTop`/`Bottom`), so
  tabbing to it shows it as tabbing to it drawn whole does; its cursor row off the band is a
  one-line region at its place (`FrameBuffer.markPulledControl`), so an arrow, Page Down, End or
  type-select moving the cursor past the band has the scroll view reveal it.
- **Page Up and Page Down (B-SCROLLFIT-5)** move the cursor by the request's viewport: the
  handler's `viewportHeight` is set to it after the band is drawn. There is no pinned header yet
  (P6), so nothing is taken off it.
- **`scrollTo` (1f).** Measured for a key search (`ScrollKeyLocate`), a list or table says whether
  a row carries the key (a scan of the keys, no row built); the column hands it the seek, and it
  places the row's line by the request's anchor.
- **Type-select** (`resolvePendingTypeSelect`) reads each row's `typeSelectText` from its content,
  which builds the rows it scans from the cursor to its match: per key press, never per frame, as
  2d allowed (`PulledListTests`: typing `r5000` over 10,000 rows builds about the 5,000 it scans).

`PulledListTests` and `PulledTableTests` twin a list and a table of 300 rows under a title and a
button against the same view drawn whole, framed to its full height with the switch off: at the
top, five wheel steps and a burst, Tab onto it, fourteen cursor steps past the screen, End and
Home draw alike. At 10,000 rows they pin the rows built a frame (first frame, three wheel steps,
a `scrollTo`, two pages, End) under 100 and equal to 1,000's, and reach every row by the wheel and
by Page Down (a page a screen: 834 pages), row 0, 517, 5,000 and 9,999 by `scrollTo`, and the
button below and back by Tab.

Measured (2026-11-12, `ab_bench.py`, release, cpu per frame, 10 reps). The new variants, base
7afe15716 (the variants with the switch, before the pull) against the P3 tip: `app-shapes/titled-list`
33.8 ms → 0.48 ms a frame (−98.6%), RSS 61.2 → 15.4 MB; `app-shapes/titled-table` 327 → 365 µs
(+12.2%), a different workload rather than a slowdown: at the base the table was capped at the
viewport, so the page under its title could not scroll and its frames held still, where at the tip
it scrolls through all 10,000 rows. Against c9f7d884b (P2's tip, switch off throughout):
`grouped-feed`, `headed-log`, `megalist`, `scrolleager`, `scrollfollow`, `dashboard`, `table`,
`table-multiline`, `table-churn`, `tables-vstack` and the sessions `editor`, `chat` and `log`
indistinguishable, `tables-scroll` +0.4% [+0.0, +0.5]; the pulled lazy pages, re-run once the
scenario wrote the switch only on its list and table pages (load 4.1), `titled-lazy` +1.9%
[+1.1, +3.9], `two-stacked-lazy` +3.0% [+2.1, +3.8], `boxed-lazy` +1.6% [+0.8, +3.0]: under the
owner's few-percent line, not profiled. RSS within 1 MB everywhere. `frame_parity.py` (switch off):
156 of 157 cases draw alike, `app-shapes/timeline-rows` the one that differs between runs of one
binary; its first run caught the walked-move change sending End from between four screens and 256
lines off to the estimated total's offset (`session/log*`, fixed in cbcf91160).

**As P4 built it** (2026-11-12, `PulledRowBand.swift`, `_ListCore+Pulled.swift`, `Table.swift`'s
"SCROLL-FIT's pull", `TextEditor+Pulled.swift`, `FormScroller.swift`). Behind the same switch, and
with it off nothing reads any of it:

- **Rows of varying height walk the engine.** A view whose rows are not all a line hands the
  column engine (`ScrollFillColumn`, P1's walk) its rows through `PulledRowColumn`: their count,
  each one's pitch measured when the walk first reaches it, their keys. It keeps `PulledRows`
  in its state: its own `ScrollContentAnchor` (in the rows' lines, its chrome not counted), a
  bounded sample of the pitches measured (the running estimate, taken afresh when the width or
  the row count changes) and the rows it drew last (the ladder). A request counted from the
  view's top or end places the anchor there (`enter(edgeOf:)`); one counted from its own
  position walks the delta (`advanceAnchor`). A seek makes its row the anchor, placed by the rule
  every seek shares, the target's line read from the anchor by exact pitches within four screens
  and priced past that. The fill goes from the anchor down to the viewport's bottom and no
  further (P3's band is the viewport's lines, not the stack's margin rows), and the view draws
  itself framed to those rows from the first, its top line clipped (`scrollTopClipLines`), cut to
  the band. Where the band holds the first row the view's lines are re-based so its top is line
  0, the position moving with them (`pulledPosition`, or a hold reported to a scroll view whose
  content the view is); where it holds the last, the total is exact; elsewhere it is the walk's
  lines plus the rest at the running pitch (`sliceTotalIsEstimate`). The cursor row off the band
  is marked at its line read the same way: exact near the band, so an arrow past it is revealed
  exactly; priced far off it, so a reveal there lands by the pursuit. Page Up and Page Down step
  the cursor by the rows the viewport shows (`rowsOnScreen`), as a list drawn whole steps by the
  rows it shows: by the viewport's lines, as P3's one-line rows do, a page of two-line rows
  stepped over half of them.
- **`List`.** Rows found taller than a line (B-SCROLLFIT-3's hypothesis refuted, as in P3) or not
  all content (sections, whose headers and footers are rows) are walked; an outline's rows are one
  line and stay counted. The rows' pitches are the heights the list draws them at: the band is
  placed inside the list's frame once its rows are extracted at their width
  (`ListPulledVariable`), and the frame is then framed to the band's rows. The measure is the
  last band's total, or before any band a line a row, building none. A section header is
  not pinned over a pulled list's rows: its window's top is the band's, and a header pinned to
  the scroll view is pinned chrome's (P6). An empty list is its placeholder's height, drawn
  whole.
- **`Table`** of multi-line rows (a column's `lineLimit` above one, or sections): the same walk,
  each row's pitch its wrapped cells and the section headers it carries
  (`entryHeight`), at the columns the table lays out with no bar (`pulledColumns`); its measure
  no longer sums every row (`analyticMultiLineSize`) when pulled.
- **`TextEditor`** is a lines leaf: its rows are its own and laid out already (the layout keeps
  them at each width), so its height is exact and its band is P3's arithmetic. It draws from the
  band's first row (`pulledTop`) with no bar of its own, takes no wheel tick, follows the caret
  across but not down, and marks the caret's row: the scroll view keeps the caret in sight as it
  moves and as text is typed. A design `subRow` was not needed: the editor's rows are its anchor's
  rows, one line each. The editor sits inside its editing menu, a `ContextMenuModifier`, whose
  content is a child at index 0, a sibling step: the modifier now forwards (`PulledChromeRelay`
  with no lines of its own, `ScrollPlacing`), and a pulled editor it measures by drawing answers a
  footprint of its rows' height.
- **A grouped `Form`** in a vertical scroll view's content is no scroll view of its own
  (`fitsVerticalScrollContent`, written by the scroll view for its content with the switch on):
  its sections' height, eager content the scroll view scrolls and reveals into. The scroll
  modifiers written on such a form have no scroll view of its own to answer them.
- **Type-select** still builds the rows it scans. A row's type-select text is its stated
  equivalent or its first line of text, both read from its view; the data does not hold it, so
  there is nothing to search without building the row. Per key press, never per frame.

`PulledVariableListTests` twins rows of one to three lines, sections and an outline,
`PulledMultiLineTableTests` a table of one- to three-line rows, `PulledTextEditorTests` an editor
wrapped and not, and `PulledFormTests` a grouped form, each against the same view drawn whole
framed to its full height (top, wheel steps and a burst, wheel up, Tab, cursor steps, End, Home);
at 10,000 rows the rows (or cells) built a frame are under 100 and equal to 1,000's, and every row
is reached by the wheel, Page Down, `scrollTo` and Tab.

Measured (2026-11-14, `ab_bench.py`, release, cpu per frame, base af107bd7a — main with the new
variants — against the P4 tip 2827579fe): `app-shapes/titled-list-variable` 23.8 ms → 0.39 ms a
frame (−98.4%) and RSS 53.6 → 15.4 MB; `app-shapes/titled-editor` 37.7 ms → 0.53 ms (−98.6%), RSS
68.2 → 73.2 MB; `app-shapes/grouped-form` indistinguishable (its rows are eager either way:
336 ms a frame for 1,000 rows, the form's own scroll view or the page's). `app-shapes/code-editor`
−0.7% [−1.9, −0.0]; `titled-list`, `titled-table`, `titled-lazy`, `boxed-lazy`, `headed-log`,
`sidebar`, `grouped-feed`, `megalist`, `scrolleager`, `scrollfollow`, `dashboard`, `table`,
`table-multiline`, `tables-scroll` and the sessions `editor`, `chat` and `log` indistinguishable.
`frame_parity.py`: 160 of 162 cases draw alike, `titled-list-variable` and `titled-editor` among
them (the pulled band draws what the view drawn whole drew); `app-shapes/grouped-form` differs in
one frame of 120, and `app-shapes/timeline-rows` differs between runs of one binary.

Traced afterwards (2026-11-14), with every frame of both builds dumped:

- **The grouped-form frame is a flake both builds draw.** Now and then one frame draws each
  section's card at its ideal width (30 columns) rather than the page's; which frame, if any,
  changes from run to run of one binary (five runs each: the base drew one such frame, the tip
  two; frames 9, 24, 28, 35, 59, 76 and 119 seen). It is not the new path's: the base draws it
  with the form's own scroll view, and the form drawn without one draws it too. Not root-caused:
  it happens with `TUI_VERIFY_MEASURE_MEMO` set as well.
- **The page's form was not pulled.** The scroll view marked its content for the form only under
  its own switch, and the Stress pages turn the switch on inside the content, so the form stayed a
  scroll view of the viewport's height. Fixed: the mark is written whatever the scroll view's
  switch and the form reads the switch where it stands (`PulledFormTests` "The switch written on
  the scroll view's content…"). `grouped-form` against P4's tip: −14.1% cpu a frame
  [−15.1, −13.8] (343 → 296 ms), RSS 105 → 79 MB; `titled-lazy`, `boxed-lazy`, `titled-list`,
  `megalist`, `dashboard`, `tables-scroll` indistinguishable, `scrolleager` +0.9% [+0.2, +2.0].
  Parity against the P4 base after the fix: still 160 of 162 (the flake, and `timeline-rows`).
- **The pulled pages do not scroll in `--bench`.** Every frame of `titled-list-variable`,
  `titled-lazy` and `grouped-form` (the three dumped) is the page's top:
  `.scrollPosition(.constant(ScrollPosition(y: line)))` builds a fresh position each frame, each
  with the same request token (1), and the scroll view applies a request only when the token
  changes, so after the first frame it never moves. The A/B numbers above for these pages measure
  the top frame redrawn, not three lines a tick. Fixed in the library (461d13e84): SwiftUI
  scrolls to each new value bound that way (measured, `Tools/SwiftUIProbes/Scroll position bound
  to a changing value`), so the scroll view now compares the bound request by value. Stress now
  fails a scrolling variant whose frames do not move, in `--selfcheck` and `--bench` (0c5031afc).

**Corrected measurements** (2026-11-14, `ab_bench.py`, release, cpu per frame, 10 reps, the pages
scrolling three lines a tick). Every A/B recorded above for the pulled pages — P2's, P3's, P4's,
P8's and P9's, the headline numbers and the "indistinguishable" checks alike, and every earlier
`geometry` number — timed a page that stood still: the tip's side was its top frame redrawn,
which the memos serve. The base's side drew every row whatever the offset, so the bases' numbers
hold roughly; the tips' were too low by up to 4.6 times.

Against the code before P2 (98447fc67, with today's pulled pages, the switch lines dropped since
the switch did not exist, and the fix; tip 0c5031afc; load 3.9):

| Page | Recorded (idle tip) | Corrected base → tip | RSS |
|---|---|---|---|
| `titled-lazy` | 0.27 ms (idle at a58bb6549; P2 to P4 checked it only for change) | 2,513 ms → 0.81 ms (−100.0%) | 1,063 → 14.9 MB |
| `two-stacked-lazy` | 0.45 ms (idle at a58bb6549; likewise) | 2,749 ms → 0.90 ms (−100.0%) | 1,101 → 15.0 MB |
| `boxed-lazy` | 687.2 → 0.59 ms (P2, base 1391cf863) | 2,577 ms → 1.19 ms (−100.0%) | 1,103 → 15.5 MB |
| `boxed-eager` | 88.7 → 0.55 ms (P8) | 273.9 ms → 1.03 ms (−99.6%) | 99.3 → 15.4 MB |
| `flow-10k` | 202.7 → 28.5 ms (P8) | 354.0 → 27.8 ms (−92.2%) | 118.8 → 84.8 MB |
| `layout-list` | 167.8 → 0.79 ms (P9) | 227.9 ms → 1.40 ms (−99.4%) | 165.4 → 15.6 MB |
| `titled-list` | 33.8 → 0.48 ms (P3) | 45.9 ms → 0.61 ms (−98.7%) | 62.4 → 15.6 MB |
| `titled-table` | 327 → 365 µs, +12.2% (P3) | 317 → 377 µs, +18.4% [+17.2, +19.6] | 17.9 → 18.5 MB |
| `titled-list-variable` | 23.8 → 0.39 ms (P4) | 65.3 ms → 1.79 ms (−97.3%) | 53.5 → 16.7 MB |
| `grouped-form` | 343 → 296 ms, −14.1% (P4 fix) | 344 → 296 ms, −13.7% [−14.4, −13.3] | 101.8 → 72.8 MB |
| `titled-editor` | 37.7 → 0.53 ms (P4) | 39.1 ms → 0.53 ms (−98.6%) | 69.4 → 67.9 MB |

(RSS here is after the A/B's 50 to 117 frames a run; see below for longer runs.) The pull's
verdicts stand: every page but `titled-table`, whose base could not scroll (the table capped at
the viewport, as P3 noted), is 92 to 100% faster. What changes is the tip's cost, which is what the
lanes' few-percent checks were guarding.

The same code standing still and scrolling (a58bb6549, the tip as recorded, against 0c5031afc;
load 2.4), which is what each recorded tip number left out: `titled-lazy` 271 → 807 µs (+198%),
`two-stacked-lazy` 451 → 844 µs (+87%), `boxed-lazy` 552 → 1,156 µs (+110%), `boxed-eager` 489 →
977 µs (+99%), `layout-list` 741 → 1,363 µs (+85%), `titled-list` 448 → 561 µs (+26%),
`titled-list-variable` 379 → 840 µs (+121%), `titled-table` +3.3%, `flow-10k` −10.1%;
`grouped-form` and `titled-editor` indistinguishable (the form's rows are eager either way; the
editor costs the same at rest). `geometry`, whose page binds the same constant position and so
never scrolled either, 3.61 → 5.34 ms (+47%), and its scroll-view geometry corrections, which its
acceptance metric wants at zero past a reader's first frame, rise from 0.20 to 0.54 a frame once
it scrolls (300 frames; "still wrong after one" stays 0).

Two things the corrected runs show that the idle ones could not, neither looked into yet:

- **A pulled page's memory grows with the rows it has scrolled past.** `titled-lazy` at the tip,
  `--bench` of 2,000, 8,000 and 16,000 frames (6,000 to 48,000 lines scrolled): RSS peak 28.2,
  57.9 and 98.8 MB, about 1.7 KB a line, and cpu a frame 742, 801 and 894 µs. The render cache's
  prune is flat (about 30 entries a frame), so what grows is held elsewhere. In the A/B's long
  runs `two-stacked-lazy` reached 61 MB, `boxed-lazy` 66 MB, `layout-list` 31 MB.
- **`geometry`'s scroll view corrects a frame in two** while it scrolls (above).

**Looked into (2026-11-14, the lane after).**

- **The memory was the `if` records of the rows scrolled past.** `Stress --bench --cache-sizes N`
  (new) named the one table that grew, `state.optionalPresence`, by about 2.25 records a frame —
  one per row passed, each row of the pulled pages holding an `if` for its second line — and
  `heap` on a running bench named what they held: 500,516 `IdentityNode`s, 40 MB of a 60 MB heap
  after 20 seconds. A record keeps what its `if` last drew and where, and a windowed-out row's
  were kept with its state (`retainSubtree`), the picture and the identity of every view down to
  the `if` with them. Only one of a record's jobs survives a pass unseen — dropping the held
  view's state when the row comes back empty; an arrival or a departure is never played from a
  frame nobody saw (`wasOnScreenLastPass`) — so the sweep, which already ran when the table
  doubled, now drops a windowed-out row's record unless its `if` holds a view with state below it
  (found by climbing each stored value's identity once), and keeps that one without its picture.
  Dropping only the pictures was tried first: 98 → 92 MB, the identities being the bulk.
  `titled-lazy`, RSS peak at 2,000, 8,000 and 16,000 frames: 26.5, 55.5, 96.1 → 20.1, 21.6,
  22.8 MB (records 4,494, 17,983, 36,061 → 74, 43, 78; what still grows, 0.08 KB a line, not
  found); cpu a frame flat at 755 to 766 µs, where the base's rose under load in the earlier run.
  At 8,000 frames: `two-stacked-lazy` 56.5 → 21.1 MB, `boxed-lazy` 63.7 → 23.1, `layout-list`
  31.6 → 21.9, `titled-list-variable` 31.2 → 22.4. A/B (load 3.2): the five pulled pages
  indistinguishable in cpu, their A/B RSS 49.4 → 21.0, 40.3 → 21.8, 42.0 → 22.2, 30.1 → 21.4,
  30.1 → 22.6 MB; frames identical on 12 scenarios. That A/B also had `menus` +7.9% [+6.4, +9.6]
  (twice on its own, +6.3 and +9.1%) and `dashboard` +2.1%, neither of which runs this code
  (`menus` holds 18 records every frame, under the sweep's floor of 64). It was the tip binary, an
  incremental release build in the lane's worktree: the same commits built clean
  (`perf/build_v.sh`) put `menus` at +0.9% and −2.4% before this commit and +0.5% and +1.3% across
  it, all indistinguishable.
- **`geometry`'s corrections were a bug, and not the scroll's.** Traced reader by reader over
  300 frames (a debug print of each reader the scroll view found misled, now removed): 161 of
  the 164 corrections were readers told the right ORIGIN — the carried-origin prediction (design
  study A2, G4) was exact — and the wrong SPACE SIZE: every row's `anchorPreference(.bounds)` asks
  `bounds(of:)`, which uses the size, and a reader with an answer kept from last frame was told
  last frame's viewport (`GeometryAsk.predictedAnswer` took the kept observation's size), so the
  frame narrowing every fifth tick (`.frame(width: 100 - (tick / 5) % 10)`) drew the content
  twice to correct them. At rest that was those frames, 0.20 a frame (one in five); scrolling
  made it 0.54 (more readers holding an answer from an earlier width — not traced further, as
  the fix removes them all). The residual corrects the origin only now; under a scroll view the
  size is the viewport it opens the frame with, exact, as a first-sight prediction's already was
  (a named space opens with the size it is offered, not the one it takes, so there the size found
  last frame stays the better guess — the first version took the owner's everywhere and failed
  `CoordinateSpaceTests`' probe M1 case). 0.54 → 0.01
  corrections a frame (the three left: the first scrolled frame, whose residual is from a
  frame drawn at offset 0, and the frame the page wraps back to its top); 5,066 → 3,771 µs a
  frame, −26.1% [−27.0, −23.8], frames identical (`frame_parity.py`, 120 frames). The rungs'
  "zero corrections past a reader's first frame" holds again for this page.
- **A starting `ScrollPosition` did not apply.** SwiftUI places a scroll view at its binding's
  first value as it appears — an offset, `scrollTo(y:)`, an edge, an offset past the end landing
  on the last (`Tools/SwiftUIProbes/Scroll position bound to a changing value/starting.swift`);
  its macOS `List` follows no bound position at all. Two causes here. A `ScrollView` clamped the
  offset against the extent the last frame measured, 0 on a view drawn with no layout pass ahead
  of it (a test, a `--bench` context), and spent the request at the top; on its opening frame the
  offset is now placed as asked and the render clamps it. In an app the scroll view had its
  height from the first frame's layout and was right; a `List` was not: it placed the row, and
  the focus arriving after the first frame revealed the cursor, still on row 0
  (`ItemListHandler.onFocusReceived`). A list an app's request placed now stays there when the
  focus arrives, until the cursor or the user's scroll moves it — the rule a `scrollTo` already
  kept for the cursor (`scroll(toRow:anchor:)` moves neither the focus nor the selection). The
  pulled pages start at 0, so their frames do not change.


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

**As P7 built it** (2026-11-14). The switch is on and deleted; SCROLL-FIT is complete. Six commits, the
first five behind the switch, so the flip itself changed only what the switch gated:

- **The canvas** (`canvasHeight`, `ScrollView+Content.swift`). A vertical scroll view draws its content at the
  content's natural height, not `max(viewport, natural)`: a `Color`, a shape, a `GeometryReader` or
  `.frame(maxHeight: .infinity)` under a title takes no lines (was the 23 left), a `Spacer` between two lines its
  stack's minimum, a resizable image alone its ideal (15, was 24). `.containerRelativeFrame(.vertical)` still reads
  the viewport (`ScrollCanvasFitsContentTests`).
- **Offered no height, content-sized.** Asked how tall it would be with nothing to stop it (no height proposed, a
  natural-extent budget offered, none given: `.fixedSize`, or scroll content where nothing pulls it), each of these
  answered the height it was offered, flexibly, which P5 left for P7: a `List` (its chrome and rows as a pulled list
  reads them, none built, `naturalHeight`), a `TextEditor` (`answersNaturalHeight`), a `ScrollView` (its content's
  ideal height), the split views (the tallest pane's beside, the panes' and dividers' one above another). A
  vertical split now lays each pane out at its own height every frame until a divider moves; split evenly, its top
  pane was cut even at 60 rows, and the sizes the first frame's measuring walk left, scaled up, cut it too. Under
  `.fixedSize` at a window's root P5b's band draws them: a 10,000-row list 60x10002, 84 rows built on its first frame
  (was 60x23). `ContentSizedOfferedNoneTests`.
- **A nested vertical `ScrollView` forwards** (`ScrollView+Nested.swift`, the forward shape): in a vertical scroll
  view's content, given no height, not the framework's own, it draws its content in its place at its child
  identity, as wide as it is offered with the content at the leading edge, with no handler, bar or focus stop; the
  outer request passes through a single-child step, so a lazy stack in it is pulled, building the same rows as the
  stack written in its place, equal at 1,000 and 10,000 rows (`NestedScrollViewForwardTests`; before, 90,000 row
  builds on the first frame at 10,000). A key search goes on into it. *Not built:* a `ScrollViewReader` *inside*
  the nested view reaches no scroll view (none registers under it); the design's "seeks through the outer view"
  needs the reader's registry to reach the outer one.
- **A grouped `Form` the scroll view scrolls is as wide as it is offered**, its sections at the leading edge, as
  the scroll view it otherwise is lays them out (it hugged its widest row and stood centred under a wider title).
- **A-SCROLLFIT-2.** A horizontal-only scroll view draws content that fills the measuring ladder's budget at its
  viewport's height (`canvasHeight`, from `naturalExtent`'s `fillsBudget`): a 10,000-row `Table`, `List` or
  `TextEditor` is 24 lines and scrolls its own rows (was 4,096, the rows past them out of reach), a wheel step 21
  rows built. *Left:* a table whose rows come in under the first rung (60 rows) says its height rather than filling,
  so it is drawn whole at 63 lines and the view scrolls it down, not "Table 24 (its own bar)" as 2a has it; and its
  first frame still builds its rows down the rung (4,156 at 10,000), most likely for the width ask made at that
  height (not traced). `HorizontalScrollViewHeightTests`.
- **The flip.** `EnvironmentValues.scrollFitsContent` is deleted, as B-SCROLLFIT-10 and "For a future reader" rule
  ("deleted, not deprecated"): no escape hatch, since nothing needs one — a frame gives any of these views a height
  and it scrolls itself, as before. Every read of it goes (P3 to P6's and this lane's), with `.fixedSize`'s
  measure-once vertical path; `_TableCore.scrollViewportCap` and its two uses go with TABLE-IN-SCROLL-HEIGHT. The
  pull's fallbacks stay: design D's walk for a stack below a container that does not pull, and a `List` or `Table`
  drawn whole there (now at its content's height). The Stress pages lose their switch lines.
- **What the full suite found with it on everywhere.** The framework's own scroll views
  (`asChrome()`: a dialog's body, a menu's column) neither forward a nested scroll view nor answer
  their content's height offered none: nested in a `Dialog`'s chrome scroller, an app's `.visible`
  text-style `ScrollView` forwarded and lost its "N more" lines. A `VSplitView` lays its panes out
  at their own heights when it is given exactly their total, as scroll content and `.fixedSize`
  give it, rather than wherever no height was given (a split drawn directly, with none, kept its
  even split). Tests that pinned the old canvas now frame their content to the container
  (`ScrollViewReservedIndicatorCanvasTests`, `ScrollViewRenderTests`' middle spacer), and two of
  the first under an `.automatic` horizontal bar went: framed to its container a filler fills the
  container, which is the viewport less the pair whether such a bar comes or not (decisions
  SCROLL B-SCROLL-2), so the case they guarded cannot arise. `ListRowSelectionValueCostTests`'
  hugging lists are fixed across only (`.fixedSize(horizontal: true, vertical: false)`): fixed down
  too, a list now answers its rows' height, an extraction of its rows that read a few tags (53
  tag builds against a bound of 49 for 300 rows; how it grows with the row count is not
  measured).

*Not built:* split views do not pull (they are not `ScrollPlacing`): a `List` in a pane is its content's height
and drawn whole, every row built each frame, where 2a's table calls `HSplitView` parallel-shaped; it would serve
through `LayoutPull` as `Grid` does (about half a day). A grouped `Form`'s rows are still eager (P4).

**P7's follow-ups** (2026-11-15), one commit each:

- **A `ScrollViewReader` in a scroll view's content scrolls it** (`ScrollViewReader.swift`). A proxy reached only
  the scroll views that registered with its reader's registry, which are those in the reader's content, so a reader
  *inside* a scroll view — `ScrollView { ScrollViewReader { proxy in … } }`, a shape SwiftUI's examples take — reached
  none, and `scrollTo` did nothing; inside a nested vertical view that P7 forwards (the *not built* above) it was the
  same, since the nested view registers nowhere. Each scroll view that scrolls now keeps a registry of its own in its
  state, holding itself, and publishes it to its content (`enclosingScrollToRegistry`); a reader records the one it
  stands in, and its requests go on there as well as to the scroll views in its content. The forwarded view publishes
  none (its content does not pass through `contentContext`), so a reader in it reaches the outer view, which seeks
  the key through the forwarded content as for any key of its own. An outer view's search stops at a scroll view
  inside the reader that holds the key, so no row is scrolled to twice. `NestedScrollViewReaderTests` (both shapes
  failed before: the page did not move).
- **Page Up on a pulled list's first row and Page Down on its last page the scroll view on** (`ItemListHandler+Keys.swift`).
  The list took the key though its cursor could not move, so non-focusable text after a table (or before it) in the
  same scroll view was out of the keys' reach. A list or table whose scroll view scrolls it (`isScrollEnabled` off,
  as its pull pins it) now leaves a page key that moves no cursor to `FocusManager.scrollActiveSection(for:)`, as a
  focused button does. Its own scroll offset is no test of movement there: the pull re-pins it to the band every
  frame, and a first try that also compared it left a table's second Page Down on its last row moving nothing (most
  likely taken as a move, not traced). A list that scrolls itself takes the key as before. `PulledListPageOnTests`.
- **A table or text editor in a horizontal scroll view is the view's height whatever its row count**
  (`Table.swift`, `TextEditor.swift`). A-SCROLLFIT-2's ruling (b) says a horizontal view proposes its own height, so
  a `Table` there is 24 with its own bar (2a's column (v)); the 63 lines at 60 rows were the bug, not the ruling. The
  cause: given a height and asked how tall it would be with nothing to stop it (the ladder's rung, no height
  proposed), a table answered its rows' height up to the rung, flexibly, so under the rung it read as content of
  that height and was drawn whole; and it was measured at the rung, its columns read from every row the rung reached,
  for the width ask the horizontal view makes first (`naturalContentWidth`) and the height after it (4,156 rows built
  at 10,000). Now, where `asksWholeContentWidth` says a horizontal view's canvas, it answers the rung, flexibly, as a
  `List` already did, and is measured at the viewport's height, which it is drawn at (the viewport read is volatile,
  and made only there). A `TextEditor` answered the same way and drew 60 lines whole; it answers the rung too. Built
  at 10,000 rows: the first frame 4,156 → 84 (four times the band's 21, not traced further), a wheel step 21; at 60
  rows 59x63 → 60x24 with its own bar, every row reached. The baseline's `table horizontal 60` and `textEditor
  horizontal 60` rows move to 60x24.
- **`LazyVStack { header; ForEach(rows) }` builds only what shows from its first frame** (`ImplicitColumnWindowing.swift`,
  `VStack.swift`). The tuple resolved its loop eagerly, every row a child of the stack, so each measure of the stack
  on the first frame built every row (30,035 at 10,000 rows in a 30 × 12 window, each row three times); on later
  frames the row memo served them, so none was built, but every row was still resolved as a child. Past the lazy stack's threshold, in
  scroll content and pinning no sections, such a stack is now drawn as P8's column of several
  (`_ImplicitColumnOfSeveral`): the header whole, the loop a lazy stack of its own at the stack's alignment and
  spacing (`implicitColumnRowLayout`, cleared below it), a pulled child of the column. First frame 30,035 → 52 rows,
  26 a page, the same at 1,000 rows; it draws what the same content in an eager `VStack` as wide draws, line for line,
  at the top, three pages down and at the end (`HeadedLazyStackFirstFrameTests`). As with a `GroupBox`, the rows'
  identities are the column's, so a loop growing past the threshold starts its rows' state afresh, once.

Measured for the four (2026-11-15, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py --exclusive`, main
d9a562b30 against the follow-ups' tip cfdb1a218, load 3.9 → 2.6): `app-shapes/headed-log` +3.3% [+2.4, +11.7],
`scrollfollow` +1.3% [+0.4, +2.0], `churn` +1.1% [+0.1, +2.9], `app-shapes/boxed-eager` +0.9% [+0.2, +2.3] and
`session/editor` +0.8% [+0.3, +2.5] slower, inside the owner's few-percent line and not profiled (each scroll view's
content now carries its registry, a state lookup and an environment write a measure, and each lazy stack in scroll
content asks whether its content is a tuple); `tables-scroll`, `dashboard`, `grids`, `megalist`, `scrolleager`,
`glide`, `table`, `app-shapes/titled-lazy`, `titled-table`, `titled-list`, `grouped-feed` and `session/log`
indistinguishable; RSS within 1.4 MB. `ab_counters.py` (every scenario and session): no bench checksum differs, so
every scenario draws as before; 36 of 62 moved no count past 1%, and of the rest the moves are memo traffic, not
traced: `session/log` composes half the memoized rows (1,526 → 765) and `dashboard` and `grids` store about 16% fewer
value memos, while `tables-scroll` stores 25 → 38 over its run (0.9 → 1.2 rows composed a frame). `Stress --selfcheck`
clean (139 cases, 38 scenarios, 26 sessions); the full suite passes (`parallel_test.py`, 15,763 tests; one clipboard
test, `SystemClipboardTests/largeReadSucceeds`, failed under load 79 and passes alone); `api_baseline.py --check`
matches (9,578 declarations) once `ScrollViewReader.body` is a `@ViewBuilder` again (0cfb3cdd1).

**The follow-ups' follow-ups** (2026-11-15), one commit each:

- **Home and End on a list the page has gone past bring its row back** (`ScrollViewReveal.swift`). Paged past a
  pulled `List` or `Table` (Page Down on its last row, since the follow-up above) or scrolled past it by the wheel,
  Home showed the text below the list, not row 1. The list is then off the band, drawn by the column only for its
  place in the focus ring (`drawOffBandChild`, a still request whose band is its first line) and placed at an
  estimate: a child above the band at the column's running pitch, a line for a list of forty. Home moved the cursor
  and the key's snap read the cursor's region at that estimate. Off-band focus was revealed by a seek only when the
  focus had just moved; now also when the focused control has just taken a key, and the test is what the control
  drew, not its reveal outsets, which `markPulledControl` stretches over every line of a pulled control, the band's
  included. A seek routes to the list, which answers with its cursor's row. The same failure on main d9a562b30,
  where the wheel was the only way past (the page key change only made it reachable by keys; the reveal path is
  untouched by it). `PulledListPageOnTests` (paged and wheeled, a table and a list; both failed before).
- **A pinning `LazyVStack { header; ForEach }` pulls as one pinning nothing does** (`ImplicitColumnWindowing.swift`).
  The previous follow-up drew such a stack as a column of several only where it pinned no sections, so
  `LazyVStack(pinnedViews: .sectionHeaders) { title; ForEach(groups) { Section … } }` still resolved its loop whole: a
  title and 300 sections of 30 rows built 63,300 rows on the first frame, a title and 10,000 rows 30,035. The loop's
  lazy stack now takes the stack's pins with its alignment and spacing (`ImplicitColumnRowLayout.pinnedViews`), so the
  sections the loop makes pin there: a section pins within its own lines, the same lines in either drawing. Not where
  a view beside the loop may be a section (`mayHandOver(.section, _:)`): the column is an eager stack and would not
  pin it, so that stack draws as before. Now 52 rows on the first frame for the title and 10,000 rows, and for the
  sections exactly what the same stack pinning nothing builds (2,700, then 210 a page), the header or footer of the
  section under the edge pinned there (`HeadedLazyStackFirstFrameTests`; both failed before). *Left:* that 2,700 is a
  lazy stack of sections building each section it samples whole, pinned or not (1,800 with no title); and a lazy
  stack of a few sections, or of fewer loop elements than its threshold (256) whatever their rows, is drawn whole: one
  `Section` of 10,000 rows unpinned 30,035 (pinned, 68), two such sections 30,035 unpinned and 55,000 pinned, a
  `ForEach` of 100 sections of 100 rows 31,200 either way. Not traced.
- **Why a horizontal view's 10,000-row table builds its band four times on its first frame** (traced, not changed).
  Not measures: every one of the 84 builds is a drawing of the table, through `_ScrollViewCore.renderToBuffer`'s
  first drawing, once a pass, 21 rows each. The four passes are `TestApp`'s launch, and a vertical scroll view's
  table under a title does the same (84): the first frame's measuring walk, which draws the content to measure it
  (no bar yet, `isMeasuring`); the launch frame; a second frame, asked by
  `RenderContext.settleScrollIndicatorPlacement(focusID:)` as the table takes the focus and its bar moves beside its
  rows; and a third, asked by the focus manager's `onFocusChange` during the second. Each frame builds the band
  again because a table whose columns compute their values draws its rows on screen every frame (left in P5b/P6b).
  So there is nothing for the table or the measure protocol to drop: what would cut it is serving a table's unchanged
  rows across frames, and a launch that settles the focus in fewer frames, both general and not the horizontal
  view's.
- **`tables-scroll`'s memo stores, 25 → 38 in the A/B above, are the machine's load, not the follow-ups** (traced,
  not changed). Release builds of d9a562b30 and of 1caeed378 (the follow-ups, rebased, with the same code as
  cfdb1a218 but for `ScrollViewReader.body`'s builder) each stored 25 at a quiet start and, run six times at load 8.6,
  25, 39 or 43 (d9a562b30) and 25, 38 or 46 (1caeed378), with the checksum the same in every run, and lookups rising
  with the stores (197 → 226); the fixed frame clock (`--frame-checksums`) still gave 42 once in ten. The plain memo
  marks a view type heavy after three of its timed measures inside a value memo run over `heavySubtree` (100 µs in
  release, `PlainViewMemo.noteMeasured`), and from then on asks the memo for it: on a loaded machine the stress table
  crosses the line and stores. `ab_counters.py`'s doc now says so.

Measured for these four (2026-11-15, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py --exclusive`,
1caeed378 against 778064287, load 4.0): `scrolleager` +0.3% [+0.2, +1.2] slower and `app-shapes/fixed-size-table`
-0.4% [-1.0, -0.1] faster; `megalist`, `scrollfollow`, `glide`, `tables-scroll`, `table` and `app-shapes/` `titled-lazy`,
`titled-table`, `titled-list`, `headed-log`, `boxed-eager`, `grouped-feed` and `two-stacked-lazy` indistinguishable;
RSS within 0.3 MB. `ab_counters.py` on the same fourteen: no checksum differs; 12 moved no count past 1%, and the two
that did (`two-stacked-lazy`'s value-memo stores -11.5%, `titled-table`'s measure lookups +1.2%) move as much between
three runs of either binary (2,242–2,434 against 2,274–2,594 stores; 1,934–1,952 against 1,886–1,940 lookups), the
learner above. The full suite passes (`parallel_test.py`, 15,767 tests), `Stress --selfcheck` is clean (139 cases, 38
scenarios, 26 sessions), and `api_baseline.py --check` matches (9,578 declarations).

**The sections' follow-ups** (2026-11-15, S8 and S7 of the follow-ups' follow-ups' *Left*), one commit each:

- **A lazy stack of a few long sections builds only what shows** (`SectionCore+PulledParts.swift`). The cause, two
  ways round: unpinned, a section written in the stack's content is its parts there (B16), so the loop in it resolved
  as the stack's children, every row built for each measure on the first frame (one `Section` of 10,000 rows 30,035,
  two 60,035, a title and one 30,032); pinned, the stack keeps its own sections whole and each laid its parts out whole
  (`renderStacked`), every row measured and drawn (two 110,000, a title and one 60,000). One of a lazy stack's own
  sections whose content is a loop past 256 elements in scroll content (`sectionContentLoopWindows`) is now drawn as a
  column of its parts at P8's step (`_ImplicitColumnOfSeveral`), the loop a lazy stack of its own at the stack's
  alignment and spacing, pulled, as `LazyVStack { header; ForEach }` is; unpinned, such a section is kept whole for it
  (`Section.staysWhole(in:)` under `SectionWholeness.loopRows`), so it lays its parts out as the stack would, with
  B-D1S-1's deviations. Pinned, the column's header and footer are copied as pins at their places in the band
  (`renderPulledParts`): the header at the section's line 0, the footer at its end, both read from the band's
  `sliceOriginY` and `sliceTotalHeight`; one the band leaves out is drawn for its pin as a measure draws it, so a
  control in it joins the focus ring once, through the column's off-band drawing. And a stack's whole content is its
  own section (`PinnedSectionScope.owns`, no sibling step as well as one): `LazyVStack(pinnedViews: .sectionHeaders) {
  Section … }` did not pin its header. First frame now 52 (one, either way), 100 (two) and 49 (a title and one) rows,
  26 a page, the same at 1,000 rows; the drawing matches an eager `VStack`'s at the top, 30 pages down (across the two
  sections' boundary at spacing 0), at the end and paged up from it, at leading and trailing alignment and spacing 0 and 1, and
  pinned, the header of the section under the top edge on the first line, a pinned footer on the last
  (`SectionedLazyStackFirstFrameTests`). The parts' identities are the column's, so a loop growing past the threshold
  starts its rows' state afresh, once. *Found, not fixed:* a lazy stack of two pulled children with spacing pages up
  from its end 140 rows too far (two sections of 280 rows at spacing 1, and as much for two `VStack { header;
  LazyVStack(spacing: 1) }`, so not the sections'); an eager `VStack` of the same pages right; the twin marks it a known
  issue. *Left:* a pinned stack whose own section holds an explicit `LazyVStack` of 10,000 rows builds 44,110 rows on
  its first frame (98,749 before, then 18,218 a page, now none): the section lays its parts out whole, and the column
  path takes only a loop.
- **A lazy stack of a loop of sections whose rows together pass the threshold builds only what it samples and shows**
  (`PinnedSectionScope.windowsSectionLoops`, `SectionLoopRowsCounting`). `ForEach(0..<100) { Section { ForEach(0..<100)
  } }` is 10,100 rows, but neither loop passes 256, so the stack measured every section exactly and each section every
  row: 31,200 rows on the first frame, pinned or not. A lazy stack of no more than 256 children now counts its sections'
  rows without building one (each element's `Section` value built, its loop counted, stopping past 256) and, past the
  threshold, prices its rows by a sample (`estimatesRows(count:context:)`, at the three places that read the
  threshold and the uniform seek's seed); each of its own sections then draws its loop as a lazy stack whatever its
  count (`ImplicitColumnRowLayout.windowsAnyCount`, `_VStackCore.estimatesWhateverItsCount`), so the section is a
  pulled column as above and its loop is estimated from sixteen rows. A title over such a loop takes P8's column of
  several (`TupleView.columnOfSeveral(…sectionLoops:…)`), the loop a lazy stack that estimates whatever its count. And
  the lazy stack a loop is drawn as (`ForEach.windowedColumn`) files itself as placing its rows
  (`ForEach.fileWindowedColumn`, as a layout files, `PullConsumers.noteLayout`): its rows are siblings at the loop's
  identity, whose type is no pulling container's, so a lazy stack in one of them was not pulled where it stood. First
  frame now 820 to 2,017 rows (the stack's sample of sixteen sections, each sampling sixteen rows, over the first
  frame's measures; the same order at 200 sections or 200 rows), 26 a page; the drawing matches an eager `VStack`'s
  at the top, twelve pages down, at the end and paged up from it, with and without a title, pinned or not
  (`SectionedLoopFirstFrameTests`). At spacing 1 the page up from the end lands at the last section's top: the found
  issue above, marked known there.
- **S7, a lazy stack of more sections than the threshold samples each section it measures whole: kept.** 300 sections
  of 30 rows build 1,800 rows on the first frame (a title above, 2,700), 30 a section in the stack's sample of sixteen,
  over the frame's measures. Drawing the sampled sections as the pulled columns above (built in this lane, then taken
  out) cut it to 1,060 (1,918 with the title), the two-level sample of sixteen by sixteen, and cost exactness: the
  stack becomes a pulled column of estimated sections, so a jump of more than four screens is placed at the running
  pitch, where the anchored window measured each section whole and placed it exactly — `CompositeMembersLazyTests`'
  `.scrollPosition(y: 50)` over 300 sections of one to three rows drew a line off. A section's height is its rows'
  heights, so an exact measure of a sampled section builds its rows; a stack of that many sections already windows
  by its count, and a section of fewer than 256 rows builds no more than those. So a loop of more sections than the
  threshold leaves its sections' loops alone (`ForEach.sectionLoopRows` answers `nil`). *Left:* a title over such a
  loop draws each section in the band whole, 210 rows a page.

Measured for these (2026-11-15, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py --exclusive`, base 0dd60a98d
with the lane's two Stress pages added against the lane's tip aa44cc526, load 9.6 at the start): the two pages the
lane adds, `app-shapes/one-section` (one pinned `Section` of 10,000 one- and two-line entries) 3,417.6 → 849.6 µs a
frame (−75.1% [−75.4, −74.8], RSS 25.2 → 20.1 MB) and `app-shapes/section-loop` (100 pinned sections of 100 entries)
193,018 → 2,418 µs (−98.8% [−98.8, −98.7], RSS 147.1 → 17.2 MB); `app-shapes/boxed-lazy` +0.7% [+0.1, +1.2] slower,
inside the owner's few-percent line and not profiled; `titled-lazy`, `two-stacked-lazy`, `boxed-eager`, `headed-log`,
`grouped-feed`, `outline`, `titled-list`, `titled-table`, `flow-10k`, `layout-list`, `megalist`, `scrollfollow`,
`scrolleager`, `glide`, `tables-scroll`, `table`, `churn`, `dashboard` and `grids` indistinguishable; RSS within 1.1
MB but the two pages'. `ab_counters.py` on the same 22: 16 moved no count past 1%; `section-loop`'s value-memo stores
2,362,040 → 5,454 and measure lookups 5,926,860 → 54,507, `one-section`'s measure hits 4,746 → 2,916, and
`two-stacked-lazy`, `boxed-lazy`, `outline` and `titled-table` moved memo counts by 1 to 8.5%, as much as the
follow-ups' follow-ups found between runs of one binary (not traced here).
The checksums of every page but the two new ones are the same; those two draw
differently from base (`frame_parity.py`, 0 of 2 alike from the first frame), most likely the scroll bar's thumb,
which an estimate of the height below the band now sizes, and `one-section`'s header, which now pins: an eager
`VStack` of the same mixed-height content draws the same lines as the lane's tip at six pages for both shapes, the
thumb a cell off on some of them (a probe, not kept). `Stress --selfcheck` clean (141 cases, 38 scenarios, 26
sessions); the full suite passes (`parallel_test.py`, 15,798 tests with 70 known issues, the lane's probe suite among
them); no public declaration changed, so `api_baseline.py` was not run.

**S10, the sections' found issue: a column entered from its end prices the rows the walk did not reach after the walk**
(2026-11-15, `ScrollColumnFill.swift`'s `enter(edgeOf:)`). End sends a pulled child it reaches from below a request
counted from its end, and the child walks up from its last row by exact pitches and puts its own end at its last
reported end or, on its first draw, at an estimate. The callers worked that estimate out *before* the walk: a lazy
stack that had never measured a row priced each at the one-line floor, its spacing left out, so 280 rows at spacing 1
ended at 278 lines where they take 559. On the next frame the uniform hypothesis was seeded and the stack drew by
arithmetic in exact lines, reading the position the walk had answered in the short ones: Page Up from the end landed
140 rows up (187 at spacing 2), the column above taking the stack's short end as its height. Not the sections': the
lazy stack of two `VStack { header; LazyVStack(spacing:) }` does it as well, and only a *lazy* outer stack, which never
draws its second child until End reaches it (an eager column draws every child off the band each frame, so the inner
stack's hypothesis was seeded long before). Now the estimate is read after the walk, from it: the lines it covered,
plus the rows above them, each measured in a column of a few rows (`walksJumps`, a header over a long stack, whose
average describes neither) and priced at the running pitch, which the walk has just measured, in any other. Reading the
callers' `count × pitch` after the walk instead was tried and was worse: a column of a one-line header over an
838-line stack ended at 1,676, and Home then landed at the first stack's end. And the running pitch now counts the last
row with the gap it does not draw (`AnchoredWindowFrame.pitch`), as it prices rows that have one: a walk up from the end
over three one-line rows at spacing 6 averaged 5, not 7, and the end lost 2 lines a row. `PulledSpacedChildrenTests`
(a lazy and an eager outer column, spacing 0, 1, 2 and 6, Page Down, End, Page Up, Home, End and Home again, and the
wheel) failed at Page Up from the end and at Home after a second End at spacing 1 and 2 before, and at spacing 6 with
the estimate read after the walk but the last row counted without its gap; spacing 0, the eager outer column and the
wheel passed before and after. The twins' known issues (`SectionedLazyStackFirstFrameTests`,
`SectionedLoopFirstFrameTests`) are gone.

**The baseline** (`ScrollFitBaselineTests`). The table's 240 rows stay as the pins of the behaviour; 80 moved, every
one to what 2a's "After" column asks: `table` at 60 rows 59x24 (own bar) → 59x63, the three `List`s 59x4096 →
their rows (5, 7, 62, 64), `formGrouped`, `textEditor`, both nested scroll views and the split and navigation-split
views at 3 rows the viewport → their content, `vSplitView` at 60 now reached (`n` → `Y`, the horizontal row too), the fillers 0
(`color`, `rectangle`, `spacer`, `geometryReader`), `maxHeightText` 1, `imageResizable` 15, `lazyVStack` alone 59x25
→ 59x60 (`onGeometryChange` reads the pulled height, P5b), the horizontal `List`s 59x4096 → 60x24 with their own bar.
Rows that did not move stay where switch-off had them (the eager containers, `Divider`, `scaledToFit`,
`LazyHStack`). The 10,000-row tests were converted where the old behaviour was the bug: the table under a title
59x24 capped → 59x10003, under 150 rows built and no bar of its own; under `.fixedSize` 4,153 rows built → under 150;
horizontal 4,096 lines → 24 with its own bar; the list 4,095 lines and 12,000 rows → 59x10002 and under 150; the
editor 4,095 → 10,000; the lazy stack's reported size its band → its whole height. The keys tests now pin P6's: the
title stays on line 0 at launch, the table's header pinned over the page as its cursor moves the page, and the list's
last row followed by the line after it rather than four thousand blank lines. Deleted: `PulledListTests`' "With the
switch off the list is drawn as before" and `PulledFormTests`' "The switch written on the scroll view's content",
which pinned the switch itself; the `fitsContent` twins of `WindowedContainersTests`, `WindowedFormColumnsTests` and
`PulledGridTests` collapse to one side. `ScrollingTablesScreens`' known issue (a `List` filling 4,096 rows "until
SCROLL-FIT's P7") is gone.

**Frames** (`frame_parity.py`, 120 × 40, every scenario, variant and session, release builds). The base 72033451f
against the last commit before the flip (1789b806c): 165 of 165 alike, as they should be, the five commits before it
changing only what the switch gated (the Stress pages that turn it on in their content kept their scroll view's
canvas, which reads the scroll view's own). The base, and the pre-flip commit, against the flip (ba9c88718; the tree
built was 2bd3acff9's, the same tree under a message the lane amended): 164 of 165 alike. `table-api/in-scrollview`,
a 500-row table alone in a `ScrollView`, differs from its first frame, where the old drawing was the cap: the table
the viewport's height, its own scroll bar and bottom border on screen, scrolling its own rows; it is now its rows'
height, pulled, under the outer scroll view's bar (L19). The tip against itself: 165 of 165 (`timeline-rows`, which
differed between runs of one binary in earlier lanes, drew alike in all four runs here). No page with a filler under
short content is among the Stress pages, so the canvas changed none of them.

**Measured** (2026-11-15, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py --exclusive`, base 72033451f
against the flip's tree 2bd3acff9; the sweep at load 4.1, the variants at 3.4 → 2.9):

| Scenario | Base µs | Tip µs | Change | 95% CI | RSS MB |
|---|---|---|---|---|---|
| `tables-scroll` | 2,786.2 | 20.9 | −99.2% | [−99.3, −99.2] | 18.5 → 15.9 |
| `alpharamp` | 7,768.5 | 5,454.0 | −29.8% | [−30.3, −29.3] | 53.5 → 26.1 |
| `churn` | 8,624.9 | 8,511.8 | −2.0% | [−2.2, −0.3] | 21.0 → 20.8 |
| `app-shapes` | 10,491.2 | 10,377.5 | −0.9% | [−1.5, −0.7] | 36.0 → 35.2 |
| `table-churn` | 401.0 | 404.0 | +0.5% | [+0.0, +1.1] | 17.2 → 17.4 |
| `table-churn-wrapped` | 957.6 | 968.6 | +1.2% | [+0.4, +1.9] | 17.3 → 17.4 |
| `app-shapes/grouped-form` | 310,754 | 300,221 | −3.2% | [−9.7, −2.3] | 78.8 → 78.5 |
| `app-shapes/fixed-size-table` | 488.6 | 477.9 | −2.7% | [−3.0, −1.0] | 18.4 → 18.8 |
| `app-shapes/titled-table` | 400.8 | 392.2 | −2.5% | [−2.8, −1.8] | 19.0 → 18.8 |
| `app-shapes/titled-list` | 588.7 | 578.5 | −2.4% | [−2.6, −1.2] | 20.4 → 20.8 |
| `app-shapes/titled-editor` | 553.2 | 543.3 | −1.7% | [−2.8, −1.4] | 71.3 → 74.2 |
| `app-shapes/titled-list-variable` | 895.0 | 883.7 | −1.5% | [−1.6, −0.9] | 22.0 → 22.4 |

Indistinguishable: `megalist`, `scrollfollow`, `scrolleager`, `glide`, `table`, `table-multiline`, `truncate`,
`table-tail`, `table-api`, `tables-vstack`, `deep`, `fanout`, `modifiers`, `preferences`, `geometry`, `customlayout`,
`textwall`, `texteffects`, `anyview`, `dashboard`, `framedcolumns`, `gradients`, `menus`, `keyrows`, `sheetrows`,
`controls`, `grids`, `pickers`, `stateful`, `kitchensink`, and of `app-shapes` `titled-lazy`, `two-stacked-lazy`,
`boxed-lazy`, `boxed-eager`, `flow-10k`, `layout-list`, `grouped-feed`, `headed-log`, `sidebar`, `settings-form`,
`code-editor`, `text-editor`. RSS within 1.3 MB everywhere but the two large gains and `titled-editor` (+2.9 MB)
and `text-editor` (−4.8 MB). The two table-churn pages, 1.2% at most, are inside the owner's few-percent line; not
profiled. `tables-scroll` and `alpharamp` draw the same frames as before (above) and compose fewer rows a frame
(`tables-scroll` 8 → 0, its cell values 1,001 → 0; `alpharamp` 185 → 151, 70 → 2): their tables, in scroll
content, read the scroll view's viewport for the cap, and that getter tells the memos above not to keep what read it
(the deleted `scrollViewportCap`'s own note), so the page was drawn again every frame; without the cap the memos
hold. That is the likeliest reading of the counts, not a profile. The pulled pages' 1.5–3.2% gains are not traced
either (the switch's reads and the cap's test gone from every measure is a guess).

`Stress --selfcheck` clean (139 cases, 38 scenarios, 26 sessions); the full suite passes (`parallel_test.py`, 15,749
tests); `api_baseline.py --check` matches (9,578 declarations: the switch was package-internal, nothing public moved);
DocC `--strict` found one diagnostic, a public symbol's link to a package type from the P8 leftovers (30e520232),
fixed in its own commit (820d8fb86), and is clean after it.

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

**As P6 built them** (2026-11-14, `Table.swift`'s "SCROLL-FIT's pull", `ScrollPinnedChrome.swift`,
`ScrollViewReveal.swift`). Behind the switch; with it off nothing reads any of this:

- **The header and the bar are pinned.** A pulled table (one-line rows or multi-line) adds to its
  band a copy of its header lines with the side borders on them (`pinnedChrome`), at the header's
  place in the band's lines, above the band when the band leaves it out, as a top
  `OverlayLayer.ScrollPin` free to travel the rows' height; and where its columns do not fit
  across, a copy of its horizontal bar's line as a bottom pin, travelling up to its first row.
  `OverlayLayer.scrollPinned`, which a pinned section's header and footer were built by
  (`_SectionCore.pinnedLayer`), is shared. The scroll view places them as it places a section's
  (`PinnedChromeViewport.pinnedRow`), so the next table's header takes the edge over, and
  `PinnedChromeCover` keeps a revealed row clear of both. The copies carry their own regions: a
  click on the pinned header reaches the header, not the row under it, and the pinned bar's
  arrows scroll the columns. The top border is not pinned (the design's "header line, its rule
  and the side borders"; the table draws no rule under its header).
- **Columns that scroll sideways are pulled now** (P3 drew them as before). Their band is framed
  with the bar's line under the rows (`PulledTableLines.bar`, counted in the chrome below), the
  window of columns draws no vertical bar of its own when pulled (`horizontallyWindowed`), and
  the measure answers the pulled height and files the table again as a view that bands its rows:
  the window's measure, itself not pulled, had withdrawn it, so no column handed it a request and
  it drew its first screen at the viewport's height. A multi-line table whose columns do not fit
  is still drawn as before.
- **A row sought is kept clear of the pinned chrome.** A `scrollTo` or a focus seek places the
  row with the header's lines above it and the bar's below (`seekChrome` on the variable path),
  as SwiftUI's table, whose header sits outside the rows it scrolls, shows a row sought to the
  top. A lazy stack's section header still covers a row sought under it, as SwiftUI's does.
- **Page Up and Page Down** move by the viewport less the header and bar lines (B-SCROLLFIT-5).
  A multi-line table pages by the rows on screen, as P4 built it, the rows only under the pinned
  lines not counted (P6b, `PulledRowsBand.rowsOnScreen(clearOf:)`).
- **The arrival reveal (2e)** is the scroll view's, read from the switch where the scroll view
  stands: on arrival, a control whose regions' union is taller than the viewport is revealed by
  its smallest region, the cursor's row, so not at all when that row shows
  (`_ScrollViewCore.revealTarget`). The keys test: a 60-row table under a title, focused at launch,
  leaves the title on line 0; tabbing to a tall table below the fold brings its first row up to
  the last line rather than its top to the first.

`PulledTableChromeTests` twins the pulled table, with columns that fit and with columns that
scroll sideways, against the same table drawn whole, framed to its full height: wheeled a tick at
a time from the top to past the end, each screen is its twin's with the header over the top line
exactly when that line is one of the table's rows and the bar over the last on the same condition
(`PulledTableTwin`). It also pins the keys test, the pinned chrome's clicks and two tables'
headers handing over; `PulledArrivalRevealTests` the arrival at launch, below the fold, and of a
table that fits. `PulledTableTests`, `PulledMultiLineTableTests` and `PulledFixedSizeTests` now
compare against `PulledTableTwin` too, their twins framed with the switch on (the switch leaves a
framed table as it was, and the arrival rule is then the same on both sides); a row a key reveals
upward lands a line lower than the twin's, under the header.

**As P6b built them** (2026-11-14, `_ListCore+Pulled.swift`'s `PulledListHeader`). Behind the switch:

- **A pulled `List` pins its section headers.** SwiftUI's rule is the list's own (decisions A45,
  measured with `Tools/SwiftUIProbes/List pinned headers and row stripes/pin.swift`:
  `NSTableView.floatsGroupRows` under every style but `.sidebar`), so the header of the section the
  viewport's top lies in stays at the top while its rows are under it, its section's last row pushes
  it off, and no footer pins. A pulled list draws a window from the band's first row, and its own pin
  (over the window's top) would be the band's, so it is the scroll view's: the band's walk names the
  header (`RowSource.pinnedHeader(over:)`), the list draws it above the band's rows covering none of
  them (`PinnedHeaderCover`'s `coversRows`, `WindowOrigin.headerAbove`), and a copy of its lines is a
  top scroll pin built as the table's header is (`OverlayLayer.scrollPinned`, opaque, as the header a
  list scrolling itself pins is drawn in its rows' place), at the header's place in the band's lines,
  free to travel its section's rows (to the next header or footer, `RowSource.sectionEnd(after:)`,
  their lines read off the walk: exact near the band, priced at the running pitch past it). A header
  the band opens in, its top lines scrolled off, is drawn where it is. The copy carries the header's
  regions, so a click on it selects nothing under it; a revealed row is kept clear of it
  (`PinnedChromeCover`), so Tab onto the list, which reveals its top, leaves it a line lower than the
  same list drawn whole, which pins nothing — as a pulled table's row revealed upward is.
- **A page leaves out the rows under the pinned header**, of a list as of a multi-line table
  (`PulledRowsBand.rowsOnScreen(clearOf:)`).
- **The pinned header costs less.** The Time Profiler on `app-shapes/titled-table` (attached to
  `Stress --bench`, 8 s, at P6) put what pinning added in the composite of the opaque copy over the
  row under it: `resolvingScrollPins` 3.5% inclusive, `move(pinned:)` 3.4%, of which
  `composite(with:at:)` 3.0%, nearly all of it the split of the row around the copy
  (`ansiOverlaySplit`, the stripped lengths, the scalar widths) — not the header's drawing, which the
  table draws in every band anyway, nor its copy (`scrollPinned` 0.2%). A painted overlay as wide
  as the canvas from its first column covers its rows whole, so the in-place composite now writes
  each row as the overlay between two resets where the row ends plain (a reset last, no link), and
  splits only the rest: `resolvingScrollPins` 0.7%, `move(pinned:)` 0.4%. The bytes differ from the
  split's (which keeps the row's escapes before its first cell and after its last), the cells do
  not (`PaintedRowOverlayTests`, against the copying composite); `frame_parity.py` reports the two
  pulled-table pages different for that, every other case alike.

Found on the way: a pinned copy drawn over a cursor row reversed on the terminal's own ink (the
focused row, `\e[7m`) lost its letters. A transparent overlay cell takes the field under it, and
that field is the terminal's foreground, the ink the letters are drawn in, so they are drawn as
blanks (`String.paintedOver(fieldsReversing:)`, as designed for transparent overlays). A table's
pinned chrome is opaque (`OverlayLayer.isOpaque`, composited painted), as SwiftUI's table header
is; a section's stays transparent.

Measured (2026-11-14, `ab_bench.py`, release, cpu per frame, 10 reps, base d3548ddf5 — main with
P5 — against the lane). As first built (3866a5bb9), `app-shapes/titled-table` 370.6 → 439.9 µs
(+19.2% [+16.8, +20.0]) and `app-shapes/fixed-size-table` 436.9 → 516.5 µs (+18.1%): the Time
Profiler put it in the pinning (`resolvingScrollPins` 8.9% inclusive, `move(pinned:)` drawing the
opaque copy through the copying composite, which measures every line of the content), the header's
copy cut by `lines(in:)` (3.2%) and `pulledBarLines` laying the columns out at every rung of the
measuring ladder (2.2%). The lane's last commit composites in place (`overlayIsPainted` on the
in-place composite), copies only the lines and what rides on them (`FrameBuffer.copying(lines:)`),
and only where the scroll view could pin them, and leaves the bar's line to the measure's own
overflow path: against the first build −9.8% and −11.7%, against the base `titled-table` 366.5 →
383.9 µs (+4.6% [+4.3, +6.9]) and `fixed-size-table` 448.9 → 464.9 µs (+4.7% [+0.1, +8.7]), the
header drawn again at the top of every frame that scrolls past it, under the owner's
few-percent line. `titled-list`, `titled-list-variable`, `titled-lazy`, `boxed-lazy`,
`headed-log`, `grouped-feed`, `titled-editor`, `grouped-form`, `megalist`, `scrolleager`,
`scrollfollow`, `dashboard`, `table`, `table-multiline`, `table-churn`, `tables-scroll`,
`tables-vstack`, `geometry` and the sessions `editor`, `chat` and `log` indistinguishable (load
2.5 to 5.4). RSS within 1 MB everywhere. `frame_parity.py` against the base: 161 of 165 cases
draw alike; `titled-table` and `fixed-size-table` differ from frame 0, as they should (the title
stays at launch, the header is pinned), and `grouped-form` and `timeline-rows` differ between runs
of one binary. Between the two builds of the lane, 163 of 165 alike, the two table pages among
them. `Stress --selfcheck` clean.

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

**As P5 built it** (2026-11-14, `FixedSizeModifier.swift`, `GeometryReader.swift`). Behind the
switch; with it off nothing reads any of it (`ScrollFitBaselineTests` unchanged).

- **`.fixedSize` climbs the ladder down, not across.** Its vertical ideal is `naturalExtent` from
  the first rung it measured at before (64 times what it is offered, at least 4,096 lines); it
  stops under a rung, or at one the content fills while flexible, which has no ideal height and
  keeps what it is offered, as before. A flexible minimum is an ideal there (B-SCROLLFIT-7), so a
  lone `Color` fixed down is 0. Across it still measures once: the horizontal hazard its comment
  records (a row that takes any width without calling itself flexible climbs to the edge of
  `Int`) is unchanged.
- **The content is given no height.** In a window the root says it has one (`hasExplicitHeight`),
  and a `Table` given a height is flexible: it filled the rung and had no ideal to climb to. Fixed
  down, the content is told it has none, as a vertical scroll view's content is.
- **A scroll view's measuring walk is not undone.** The walk gives its content only the lines down
  to the viewport's bottom (`drawsPrefixOnly`, 1d); `.fixedSize` laid its content out at its
  ideal height, so a pulled table with no request drew every row: 10,039 of 10,000 built on the
  first frame against 47 for the same page without `.fixedSize`. While measuring in scroll
  content its content is drawn no taller than the walk's lines. Before P5 the walk's small offer
  made `.fixedSize` give up on content past its rung, which hid this.
- **"Nil-proposal answers" took one view.** `GeometryReader` asked how tall it would be with
  nothing to stop it (no height proposed, a natural-extent budget offered) answers 0, flexible,
  as `Color` and the shapes already did. `.frame(maxHeight: .infinity)` already answered its
  content's height offered none (4x1 under `.fixedSize`), and `Spacer` its `minLength`. The
  content-sized views that answer the height they are offered, flexibly — `TextEditor` outside
  the pull, a nested `ScrollView`, a grouped `Form`, the split views, `List` drawn as before —
  still do: making them answer content is P7's row, and here they keep the height offered.

The done-criteria read the baseline's `fixedSize` situation, which is outside a scroll view
(`VStack { title; view }.fixedSize(...)` as the window's root). There 2f's own rule holds: there
is no viewport to pull against and the content is drawn whole, so `tallTableFixedSize`'s table is
60x10003 (was 60x23) and builds 24,093 rows on its first frame (was 4,153) and 10,000 a wheel step
(was 20). The "< 100 rows built" is met where 2f puts it, in scroll content: there the table was
already pulled before P5 (`.fixedSize` offered a scroll view's rung measured at 262,144 lines),
and P5 adds content past that rung — a 300,000-row table is 300,005 lines of content rather than
the 4,096 it was offered, and End reaches its last row building under 100. Already content-sized
views at 10,000 rows outside a scroll view go 23 → their content: `lazyVStack` 9x10000, `groupBox`
13x10003, `disclosureGroup` 13x10001, `grid` 14x10000, `tabView` 9x10001, `navigationStack`
9x10000, `formColumns` 9x10000, `flowLayout` 60x1641. The 3- and 60-row tables are unchanged.

Measured (2026-11-14, `ab_bench.py`, release, cpu per frame, 10 reps, base 01f471736 — main
43c8a6a89, with the pages scrolling, plus the new `app-shapes/fixed-size-table` — against the P5 tip
e58286bce; load 10.9 at the start, 2.8 at the end): `fixed-size-table` 445.2 → 445.8 µs,
indistinguishable, and it draws alike (the table was pulled at the base already, 1d's walk not
undone at the tip). `titled-table`, `titled-list`, `titled-lazy`, `boxed-lazy`, `headed-log`,
`grouped-feed`, `titled-editor`, `grouped-form`, `megalist`, `scrolleager`, `scrollfollow`,
`dashboard`, `tables-scroll` and the sessions `editor`, `chat` and `log` indistinguishable; `table`
+1.2% [+1.2, +3.0] (8.3 µs a frame) and `geometry` +0.7% [+0.1, +1.5], under the owner's
few-percent line. RSS within 1.2 MB everywhere. `frame_parity.py`: 163 of 165 cases draw alike,
`app-shapes/grouped-form`'s flake (4 frames of 120) and `app-shapes/timeline-rows` the two that
differ, as at P4. `Stress --selfcheck` clean (139 cases, 26 sessions).

**As P5b built it** (2026-11-14). Behind the switch; with it off nothing reads any of it
(`ScrollFitBaselineTests` unchanged).

- **Outside a scroll view, `.fixedSize` content taller than its offer draws only what shows**
  (`FixedSizeModifier.swift`). Every line of a drawn view past the height it is offered is cut by the
  clamp every buffer goes through (`renderResolved`), so its content's lines past that offer cannot
  show. Where the content's ideal height is more than that, `.fixedSize` draws it as a scroll view
  draws its own at the top: marked as scroll content's origin, measured there first, under a measure
  generation of its own (so a view that bands its rows is filed as one, and the ideal-size ask, made
  with no origin, is never served it nor serves it), handed a window over the offered lines at offset
  0, and the drawing cut to them. Its size is still its content's. `tallTableFixedSize`'s table, the
  window's root, is 60x10003 and builds 84 rows on its first frame (was 24,093) and 21 on a wheel
  step (was 10,000): the rows on screen, drawn again as every frame of a table whose columns compute
  their values draws them, in a scroll view too (rows are kept across frames only where every column
  names a property). Not 0: that would take the table's own memo serving a frame nothing changed.
- **What a frame draws past it is still drawn whole.** A frame, an overlay or a background that draws
  `.fixedSize` content past its edges offers it its whole size and places it by its alignment, so any
  of its lines may show. `TestApp`'s window is such a frame (`.frame(maxWidth: .infinity, maxHeight:
  .infinity, alignment: .topLeading)`): a test whose root is statically `.fixedSize` sees it drawn
  whole. An app's window, and a root behind `AnyView`, offer the window's height.
- **A table's handler made by a measure kept that measure's height as its viewport** until a frame
  drew (`resolveHandler`), and a measuring walk drew that many rows: the ladder's first rung's 4,093.
  A pulled band caps it at the band's rows.
- **A lazy stack pulled from there reports the width its band is drawn at** (60), not its rows' (9),
  as a pulled lazy stack does in a scroll view (59x26 in the baseline): `PulledFixedSizeTests` says so.
- **A pulled view's geometry is all of it** (`OnGeometryChangeModifier.swift`). `onGeometryChange` read
  the size off the drawing, so a pulled table or lazy stack reported the band on screen (59x24 for a
  60-row table under a title); under the switch it reads the height the band's reply says
  (`sliceTotalHeight`), as SwiftUI reports the frame of a view part of which is scrolled off: 59x63.
  The width is still the drawing's. With the switch off the baseline's band sizes stand
  (`tallLazyStackAlone` 59x26).

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

**As P2 measured it** (2026-11-12, `ab_bench.py`, release, cpu per frame, 10 reps, base 98447fc67
against the pull's commit, on a busy box). `grouped-feed` 37.5 → 1.55 ms a frame (−95.9%) and
RSS 80.3 → 17.6 MB, under D's base; `grouped-feed-uniform` −96.1% (73.0 → 17.4 MB);
`headed-log` −97.7% (50.5 → 14.9 MB). Rows built a write frame (`PulledColumnTests`, 30 × 12):
506 at 40 sections, against 27,932 under D; at 320 sections 986, not the same: the scroll view's
natural-extent ladder climbs one rung more for the taller estimate and samples there again, a
step per eightfold height rather than a row per row, as for a stack at the origin. Pages with
nothing pulled: `megalist`, `scrolleager`, `dashboard`, the sessions `editor`, `chat` and `log`,
and the app shapes `sidebar`, `file-browser`, `code-editor` and `code-editor-tailing` within
the noise; `scrollfollow` +1.2% and `glide` +1.5%, under the owner's few-percent line.
`frame_parity.py` over every scenario, variant and session: 151 of 153 draw alike, the pulled
`grouped-feed`, `grouped-feed-uniform` and `headed-log` among them; `app-shapes/timeline-rows`
differs between two runs of one binary too (its timelines read the clock), and
`session/inbox-commands` only in the menu bar's first item, the binary's name.

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
| `titled-list-variable` | the same with rows of 1 to 3 lines (the estimate, dead reckoning) | P4, as built: one- and two-line rows, a variant of `app-shapes` |
| `grouped-form` | `Form { … }.formStyle(.grouped)`, 40 sections of 250 rows | P4, as built: 40 sections of 25 rows, a variant of `app-shapes` (its rows are eager, every one built each frame either way) |
| `tall-editor` | a title over a `TextEditor` of 10,000 wrapped lines, typing in the middle | P4, as built: `app-shapes/titled-editor`, scrolled rather than typed in |
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
| **P2, fifth lane** (2026-11-12) | In a pulled column: target layout, the visibility observers' rows, the top-row hold and a held row in the anchored child; the write frame's ladder answered whole; a lazy stack in an `if` among a column's views; forward through `TabView` and a pushed `NavigationStack` screen (`PulledChromeRelay`). Left: a lazy stack in a `Grid` (tried, a band of the lattice drifts from what the cell draws: about a day), departing-row transitions in a pulled column, a held row outside the anchored child. See "Built in the fifth lane" under 1b | — | Rows built a write frame equal at 40 and 320 sections |
| **P3** | `List` and `Table` as column-shaped consumers, fixed pitch; off-band cursor row and registration; Page Up/Down by the outer viewport (B-SCROLLFIT-5); type-select checked. Behind the switch. From P2: the parallel and remaining forward shapes, locate by route, the focus reveal as an anchor, and a pulled column's held row, top-row hold and target layout | 2½ + about 3 from P2 | None with the switch off. New tests with it on |
| **P3 as built** (2026-11-12) | `List` and single-line `Table` as band consumers at a fixed pitch behind the switch: content-sized, a band of the view framed to its rows, the cursor row marked off the band, the whole-control reveal reaching every line, Page Up/Down by the outer viewport, `scrollTo` by a key search, type-select measured (see "As P3 built it" under 1d). Not taken from P2's list: a held row outside the anchored child and departing-row transitions in a pulled column, and a lazy stack in a `Grid` | — | None with the switch off (`ScrollFitBaselineTests` unchanged); `PulledListTests`, `PulledTableTests` with it on |
| **P4** | Variable rows on the engine: `List`, multi-line `Table`, `TextEditor` as a lines leaf with its caret marker, grouped `Form`. Behind the switch | 3 | None with the switch off |
| **P4 as built** (2026-11-12) | `List` of rows of varying height (several lines, sections) and a multi-line `Table` walked by the engine (`PulledRowBand.swift`), the rows not yet built priced at the running pitch; an empty list its placeholder's height; `TextEditor` a lines leaf marking its caret's row; a grouped `Form` in scroll content no scroll view of its own (see "As P4 built it" under 1d). Not done: type-select without building rows (a row's text is its view's), a section header pinned over a pulled list (P6) | — | None with the switch off (`ScrollFitBaselineTests` unchanged); `PulledVariableListTests`, `PulledMultiLineTableTests`, `PulledTextEditorTests`, `PulledFormTests` with it on |
| **P5** | Nil-proposal answers; fillers declare (B-SCROLLFIT-7, 8); `.fixedSize` on the ladder (2f) | 1 | In the 10,000-row tests: `fixedSize` `Table` 23 → 10,003 and `tallTableFixedSize` 4,153 → < 100 rows built; already content-sized views under `fixedSize` at 10,000 go 23 → their content. The table's 3/60-row `fixedSize` rows unchanged |
| **P5 as built** (2026-11-14) | `.fixedSize` down the ladder, its content given no height and, in a scroll view's measuring walk, no more lines than the walk's; `GeometryReader` its minimum offered no height. The content-sized views that answer their offer flexibly stay P7's (see "As P5 built it" under 2f). Outside a scroll view the content is drawn whole, as 2f rules: the "< 100 rows built" holds in scroll content, where the table was already pulled below the first rung | — | None with the switch off (`ScrollFitBaselineTests` unchanged); `PulledFixedSizeTests` with it on: outside a scroll view the 10,000-row table 60x23 → 60x10003, 4,153 → 24,093 rows built (drawn whole); in scroll content 10,005 lines of content, under 100 built a frame and equal to 1,000's, 300,000 rows past the first rung reached; content-sized views 23 → their content; `GeometryReader` as tall as a `Color` in every situation |
| **P6** | The table's pinned header and bar (2c); the arrival reveal (2e) | 1½ | The keys test: the title stays on screen at launch. Pinned-chrome tests with the switch on |
| **P6 as built** (2026-11-14) | A pulled table's header and horizontal bar as opaque scroll pins; columns that scroll sideways pulled; a row sought placed clear of them; pages less the pinned lines; the arrival reveal by the cursor's row for a control taller than the viewport (see "As P6 built them" under 2e). Not done: a section header pinned over a pulled `List` (P4 left it here; it is a list's own pinned header, A45, not the table's, and needs its section's extent read off the walk), the pinned lines taken off a multi-line table's page | — | None with the switch off (`ScrollFitBaselineTests` unchanged); `PulledTableChromeTests` and `PulledArrivalRevealTests` with it on |
| **P5b/P6b as built** (2026-11-14) | `.fixedSize` at the window's root draws only the lines its offer holds, as a scroll view's content at its top; `onGeometryChange` reports a pulled view's whole height; a pulled `List` pins its section headers as scroll pins; a multi-line table's or a list's page leaves out the rows under the pinned header; the pinned header's composite writes its rows whole (see "As P5b built it" under 2f and "As P6b built them" under 2e). Measured (`ab_bench.py`, release, cpu per frame, 10 reps, base d3548ddf5, load 2.7): `titled-table` 377.7 → 387.3 µs (+2.4% [+0.5, +3.7]) and `fixed-size-table` 448.7 → 463.1 µs (+3.0%, indistinguishable), down from P6's +4.6% and +4.7%; the guarded build again, `titled-table` +1.9% (indistinguishable), `fixed-size-table` +2.9% [+2.3, +4.0]; `titled-list`, `titled-list-variable`, `titled-lazy`, `boxed-lazy`, `headed-log`, `grouped-feed`, `titled-editor`, `megalist`, `scrolleager`, `scrollfollow`, `dashboard`, `table`, `table-multiline`, `table-churn`, `tables-scroll`, `tables-vstack`, `geometry` and the sessions indistinguishable or faster. `frame_parity.py` against main: 162 of 165 alike, the two pulled-table pages differing as P6's do and in the composite's bytes (not its cells), `timeline-rows` between runs of one binary. Left: a `.fixedSize` root a frame draws past (`TestApp`'s window) is still drawn whole; a frame of a table whose columns compute their values draws its rows on screen again, a wheel step that moves nothing included (21 rows, as in a scroll view); a lazy stack pulled under `.fixedSize` reports its band's width | — | None with the switch off (`ScrollFitBaselineTests` unchanged); `PulledFixedSizeTests` with it on: outside a scroll view the 10,000-row table 24,093 → 84 rows built on the first frame and 10,000 → 21 a wheel step, still 60x10003; `PulledTableTests`' geometry, `PulledVariableListTests`' pinned sections, `PulledMultiLineTableTests`' page, `PaintedRowOverlayTests` |
| **P7** | The switch: defaults flipped, switch and `scrollViewportCap` deleted; `TextEditor`, nested `ScrollView`, grouped `Form`, split views content-sized; fillers' minimum; A-SCROLLFIT-2's horizontal view. Rewrites `TableInScrollViewHeightTests` and `FramedTableFillsTests`. Docs: L19, the articles, CHANGELOG, compatibility guide | 2 | Every row in the "Under SCROLL-FIT" column, e.g. `table underTitle 60` 59x24 → 59x63, `listPlain alone 60` 59x4096 → 59x62, `color alone 3` 24 → 0. Column (v) per A-SCROLLFIT-2. `ownBar` → `n` for every content-sized view |
| **P7 as built** (2026-11-14) | The canvas at the content's height; `List`, `TextEditor`, `ScrollView` and the split views their content's height asked for none; a nested vertical `ScrollView` forwarded; a grouped `Form` as wide as offered; A-SCROLLFIT-2's horizontal view; the switch and `scrollViewportCap` deleted (see "As P7 built it" under 2a). Not built: split views pulled, a `ScrollViewReader` inside a forwarded scroll view, a horizontal view framing a table shorter than the ladder's rung | — | 80 of the 240 rows moved, each to 2a's "After" column; the 10,000-row and keys tests converted (see "The baseline" under 2a) |
| **P7 follow-ups as built** (2026-11-15) | A `ScrollViewReader` in a scroll view's content, a forwarded one's included, scrolls the nearest scroll view that scrolls; Page Up and Page Down a pulled list's cursor cannot move page its scroll view on; a table or text editor in a horizontal view is its height at any row count, measured at it; `LazyVStack { header; ForEach }` drawn as a column of several (see "P7's follow-ups" under 2a). Not built: split views pulled | ½ | `table horizontal 60` and `textEditor horizontal 60` 59x63 / 59x60 → 60x24; the horizontal 10,000-row table's first frame 4,156 → 84 rows built |
| **P8** | A-SCROLLFIT-1's windowed containers (1c): `GroupBox`, `DisclosureGroup`, `.columns` `Form`, `Section` content outside `List`, `FlowLayout` per A-SCROLLFIT-5; the transition record for them (1g) | 3 | Sizes unchanged. Built counts of `formColumns` and `flowLayout` at 10,000 drop (`formColumns` < 100 a frame; `flowLayout` per A-SCROLLFIT-5). The baseline's `groupBox` and `disclosureGroup` wrap an eager `VStack` and stay as they are; new tests pin a `GroupBox` and a `DisclosureGroup` directly around a `ForEach` |
| **P8 as built** (2026-11-12) | `GroupBox`, `DisclosureGroup` and a `Section` drawn as one view directly around a `ForEach` (the implicit column, windowed past 256 elements as a lazy stack at the loop's identity); `FlowLayout` per A-SCROLLFIT-5 (a) as a lazy stack of its lines; the transition record by the lazy stack's. Not built: the `.columns` `Form` (its pillar and widths read every row each frame), a container's content of several views, a pulled `Grid` (drawn whole, twins pass). See "As P8 built it" under 1c | ½ + flow ½ | None of the table's rows (each P8 container there is under the threshold or wraps an eager `VStack`); new `WindowedContainersTests` (a page under 100 rows built, equal at 2,000 and 10,000) and `tallFlowLayoutUnderTitle` |
| **P8 leftovers as built** (2026-11-14) | A container's content of several views with a long loop among them drawn as a column that pulls them (`_ImplicitColumnOfSeveral`); a lazy stack in a `Grid` cell pulled through the grid's places (`LayoutPull`, shared with P9's adapter); a long `.columns` `Form` over comparable data keeping its label column and rows' width per data and width, its rows a lazy stack; Stress's pulled pages each at one depth, which is where P3's nested-stack +1.6–3.0% was (see "P8 leftovers as built" under 1c) | ½ | None of the table's rows (`ScrollFitBaselineTests` unchanged); new counts in `WindowedContainersTests` (headed shapes), `PulledGridTests` and `WindowedFormColumnsTests`, a page's rows equal at 2,000 and 10,000. A probe at 30 × 12 and 10,000 rows, before → after: a headed `GroupBox` 240,000 → 62 rows on the first frame and 10,000 → 26 a page; a lazy stack in a grid cell 64,119 → 126 on the first frame; a columns form 50,000 a page (26 in `WindowedFormColumnsTests` after) |
| **P9** | The app-`Layout` adapter (B-SCROLLFIT-13) | 1½ | None (no app `Layout` in the baseline); a new `layout-list` test |
| **P9 as built** (2026-11-12) | The adapter, by rects: pulled subviews beside the lead in the parallel shape, subviews below it following its drawn end, everything else drawn whole (see "As P9 built it" under 1b); `app-shapes/layout-list` in Stress | ½ | None; `PulledLayoutTests` pins under 100 rows a frame at 10,000 rows in a layout (43,081 and 63,081 on the first frame before) |

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
- **The switch (B-SCROLLFIT-10) lived only from P3 to P7.** P7 deleted it (2026-11-14); it never
  became public API. A view that must scroll itself takes a frame, as in SwiftUI.
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

### B-SCROLLFIT-19. The column of several is taken whatever the loop's count (O-14 (c), 2026-11-21)

The column of several (`_ImplicitColumnOfSeveral`, P8 and the follow-ups above) was taken only while the loop had
more than 256 elements, and its step changed the identity of every view beside the loop and of every row. "Once" held
for a loop that only grows; a filtered loop that crosses 256 both ways reset row state and a filter field's focus at
each crossing (hunt H-71, SCROLL-3). The owner chose (c), always take the step in scroll content, over keeping it and
over hysteresis. Now, in scroll content, content of several views with a loop among them (by its type:
`CountedLoop.mayBeLoop`) is drawn as the column whatever the count, the loop always one child of it, its rows its
own (`ForEach.staysWhole(in:)`): a lazy stack's loop drawn as a lazy stack of its own at any count, a `GroupBox`'s or
`DisclosureGroup`'s stacked whole below 256. One reset when an app first runs on this, none after
(`ColumnOfSeveralCrossingTests`), and the same drawing for a small loop as before (its twin against
`drawsContainerRowsWhole`). The stack drawn at the loop's own identity notes it (`implicitColumnDrawnAt`), so its
rows are not mistaken for the loop standing whole among the column's views.

Kept at the threshold, and so still reset at it: content that pins its sections or may hold a section beside the
loop (below 256 a section there pins and is read as one only among the stack's own rows), a stack marked
`scrollTargetLayout()` or in a scroll view that reads its rows back (`.scrollPosition`, `onScrollTargetVisibilityChange`;
`contentRowsAreReadBack`: below 256 each row is a target and an id, where the column would offer the header and the
loop's stack, as it does past 256), and a lazy stack's own `Section` around a loop (`SectionCore+PulledParts.swift`,
taken apart below 256: making it whole at every count changes how a stack of many small sections windows, which the
ruling did not settle).

Measured: see the commit that made it (H-71).

**The exceptions, finished (H-71b, 2026-11-24).** The column now reports its loop's rows one by one
(`StackPulledColumn+LoopRows.swift`): a pulled column of several asks each loop among its views for its rows, as a
visibility observer asks a stack, and reports them in its own lines beside its other views — to `.scrollPosition`,
`onScrollTargetVisibilityChange` and a behaviour over a stack marked `scrollTargetLayout()` — with the ordinals its
report names them by (a uniform loop's rows kept as arithmetic, `TargetLayoutSpans.Uniform.firstOrdinal`). Below 256
the loop's lazy stack draws every row and is not pulled, so the column draws as an eager stack: it lays the loop's rows
out to report them (`ColumnLoopRowsLaying`) and finds a row a request names among them (`resolveEagerSeek`). Under H-71
alone a request for a row of a small loop beside a heading — `ScrollViewReader.scrollTo`, a `.scrollPosition` id —
found none. What the scroll view reads back is the flat stack's, below 256 and past it (`ColumnOfSeveralReadBackTests`,
against the twin); past 256 it read the heading and the loop's stack before. Past 256 a behaviour knows the loop's rows
in its band only, as for any windowed lazy stack, where the flat twin drew every row: a jump of three screens settles
differently. So the read-back and the mark no longer keep the threshold (`contentRowsAreReadBack` is gone).

Nor does a stack that pins: the loop's lazy stack pins the sections the loop makes, in the same lines. A section beside
the loop is taken apart by the column as by the stack, so it takes the step too, unpinned, unless such a section may hold
a loop of its own that the stack keeps whole by its count (`SectionLoopRowsCounting.mayCountSectionLoops`): there the
column keeps the threshold and still resets at it. Pinned, a section beside the loop never takes the column, at any
count, so it never reset. `TupleView.columnOfSeveral` finds the loop by its type alone and decides on what stands
beside it.

And a lazy stack's own `Section` written out in its content (`PinnedSectionScope.writesOut(sectionAt:)`: no keyed step
between them) is the column of its parts whatever its loop's count, unpinned (`Section.staysWhole(in:)`) and pinned
(`_SectionCore.pulledPartsColumn`). A section a loop makes keeps the threshold: whole at every count, a stack of many
small sections would be a pulled column of estimated sections, S7's lost exactness; written out, a stack holds only as
many as are written. Still reset at 256: sections a loop makes, whose rows together cross it, and an unpinned section
beside the loop holding a loop of its own.

H-71's A/B of `app-shapes/headed-lazy-short` and `headed-box-short` measured the flat stack on both sides: their
scroll views are bound to a `ScrollPosition`, which kept them at the threshold. Taking the step there, they are 10.1%
and 54.3% faster (the commit that made it).

**Sections a loop makes (H71-SECTIONS (b), 2026-11-24).** `LazyVStack { ForEach(groups) { group in
Section(group.name) { ForEach(group.rows) { … } } } }`, pinned or not, a title above or not: each of the stack's own
sections laid its parts out whole (`renderStacked`) while the sections' rows together were 256 or fewer, and drew them
as the column of its parts (`pulledPartsColumn`, `_ImplicitColumnOfSeveral`'s step) past that, so at each crossing,
either way, every row's `@State` started afresh and the focus left its row (`SectionLoopCrossingTests`: all eight
shapes, spacing 0 and 1, failed on 4cfb53cd4 growing 250 → 260 and shrinking 260 → 250). The owner chose (b), the
step at every count, so rows keep their state as in SwiftUI. Now one of a lazy stack's own sections whose content is a
loop is the column of its parts whatever the count, written out or made by a loop (`pulledPartsColumn`,
`whateverItsCount: true`; `OwningStack.writtenOut` is gone).

What the step does not take: the sample. The column's loop is a lazy stack at any count, but it prices its rows by
sixteen only where the stack's sections' loops together pass the threshold (`windowsAnyCount`, from
`windowsSectionLoops`, as before); at or below it the loop's lazy stack draws every row, so the section measures and
places as laid out whole. So a small stack of such sections keeps its exact placement: the cost the ruling accepted —
an absolute jump more than four screens away in a small stack landing a line off, the estimate's — is not paid, and
no test's expectation changed. The drawing is the twin's (`drawsContainerRowsWhole`) at 0, 1, 6 and 25 sections of 0
to 9 uneven rows with headers and footers, in all eight shapes, at the top, paged, wheeled, at the end, paged up from
it and home (`smallSectionsDrawAsBefore`). S7 is kept: a loop of more sections than the threshold still leaves its
sections' loops unsampled (`ForEach.sectionLoopRows` answers `nil`), so a stack of many small sections places each
exactly. The step at every count makes S7's crossing moot for identity: the sections themselves crossing 256 (250 →
260 sections of a row each) keep the rows' state and focus too, since the section is the column on both sides.

What a small stack pays (2026-11-24, `ab_bench.py`, release, cpu per frame, 10 reps, `slot.py --exclusive`,
f773c5d24 — 4cfb53cd4 with the four pages below — against this change, load 2.3): `app-shapes/small-sections` (20
sections of 5) +21.0% [+19.8, +22.1], `small-sections-pinned` +23.1% [+21.0, +24.6], `many-small-sections` (50 of 4)
+13.2% [+5.2, +15.1], `many-small-sections-pinned` +14.5% [+12.6, +14.9], all slower; `section-loop`, `one-section`,
`outline`, `megalist` and `kitchensink` indistinguishable. Past the owner's few-percent line, so optimised before
landing (the next paragraph).

*Taken back.* The profile (`analyze_timeprofile.py`, `small-sections`, release, 12 s under Stress's autopilot, main
thread) put half the step's time in the section's loop drawn as a lazy stack that walks every row:
`_VStackCore.sizeAsImplicitColumn` 49.2% inclusive, `naturalRowSlots` 64.6% (62.2% on f773c5d24, where
`_SectionCore.stackedSize` measured the rows in one walk). What kept the state was the rows' identity, under the
loop's step below the column's, not the lazy stack: the column takes the loop apart when it would draw every row —
at or below the threshold, the sections' loops together within it too (`ImplicitColumnRowLayout.takesFewApart`,
consulted by `ForEach.staysWhole(in:)`) — and resolves its rows as its own children through the section's content
part, `sectionPartChildren`, which pins them to the loop's step, so they keep the identities the lazy stack gives
them. After: `sizeAsImplicitColumn` gone from the profile, `naturalRowSlots` 54.2%. A/B (same method, load 7.0, base
f773c5d24): `small-sections` −18.5% [−19.4, −18.1], `small-sections-pinned` −15.8% [−16.8, −15.1],
`many-small-sections` −20.8% [−26.5, −18.9], `many-small-sections-pinned` −19.3% [−23.9, −17.9], all faster than
before the step; `section-loop`, `one-section`, `outline`, `megalist`, `kitchensink` indistinguishable.
`frame_parity.py` draws alike on the four pages, `section-loop`, `one-section` and `outline` (120 frames each, 120×40);
the plant and the drawing twins pass. A section written out (H-71b) takes the same path, its small loop no longer a
lazy stack either.

*Found* (on 4cfb53cd4 too, so not the step's): 260 sections of a row cut to 250 under a title at spacing 1, pinned or
not, drew the sections' headers and none of their rows until the next change — the frame on which the sections' loops
together pass the threshold again after one past it. Marked a known issue in `SectionLoopCrossingTests`
(`changedCountDrawsAfresh`, and the sections' crossing's row check).

**H-71d, that found issue: a sample of every row took the last gap off twice** (2026-11-24,
`StackAnchoredMeasure.swift`'s `sampledRows`). Past the threshold again, each section's loop is a lazy stack that
estimates its rows whatever their count (`windowsAnyCount`), and one that has drawn no row yet answers its measure
from its sample: the first sixteen rows measured, the pitch averaged over them, the total `count × pitch` less the
last gap. The sample counted each row with the gap below it but the last, which has none to draw — and the total took
that gap off again. Past sixteen rows the last row is never in the sample, so only a loop of sixteen rows or fewer
lost it, the stack's spacing short: one one-line row at spacing 1 averaged 1 and measured `1 × 1 − 1`, no lines, so
each section drew its header, its gap and nothing, until a render had measured a row and the running pitch, which
counts the last row's gap too (S10, `AnchoredWindowFrame.pitch`), took over. At 260 (S7) the loops are taken apart,
so on the cut's frame their lazy stacks are new, with no running pitch. The same convention S10 set for the running
pitch, at a site it left: now the sample counts every row with its gap. Not the 140-rows issue itself, which S10 fixed
(2ec624395) in `enter(edgeOf:)` and the running pitch; the same arithmetic, in the measure. `PulledColumnFrame.height(of:)`
still records a pulled column's last row without its gap; counting it was tried and changed nothing measured here, so
it is left.

`SectionLoopCrossingTests`' known issues are gone; `changedCountScrolledDrawsAfresh` (new) cuts 260 → 250 and 300 → 100
and grows 250 → 260, sections of a row, in all eight shapes, scrolled to the top, five pages down and the end, against
the new count scrolled there afresh, then End and Home on both, and checks that every header drawn has its row below.
Before the fix it failed in the four shapes at spacing 1 cut 260 → 250: under a title, headers and no rows; without
one, the fresh stack's Home after End landed mid-list (section 122 of 250).
