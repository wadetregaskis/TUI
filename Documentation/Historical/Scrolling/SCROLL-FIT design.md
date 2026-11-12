# SCROLL-FIT: content-sized views in scroll content, and the window that makes them cheap

*The design for steps 2 and 3 of the owner's SCROLL-FIT ruling of 2026-11-11: how a scroll view
lets content at any depth build only the rows it shows, and what changes when content-sized
views stop filling or capping at the visible area. Written 2026-11-11 against `main` at
59c9207dc, from step 1's measurements (`ScrollFitBaselineTests`, commit 1d8296c66; findings in
`Documentation/Working notes/plan/SCROLL-FIT-baseline.md`). Ids: A-SCROLLFIT-1 to 3 (for the
owner), B-SCROLLFIT-1 to 10 (decided here).*

## In short

The scroll view already tells the content at its origin which lines are visible
(`ScrollContentWindow`), and `Section`, `.padding` and the content margins relay that window to
content they draw at their own identity (`ScrollWindowRelay`). This design passes the window on
through every container that knows where it places a child: `VStack` and `HStack`, the bordered
chrome, the wrappers, and a content-sized nested `ScrollView`. Each hands its child the window in
the child's own coordinates and builds its own *band* (the visible slice of its lines) from what
the children send back. `List`, `Table`, `TextEditor`, the lazy stacks and the grouped `Form` then
build only the rows the window covers, plus the focused row and any pending targets, which are
built outside the band.

Rows that have not been built have heights that are either arithmetic (fixed pitch) or an
estimate at the running pitch. The scroll view's existing top-row hold keeps the row on screen
still while an estimate settles. So measuring is O(1) per container, and a frame costs
O(visible) wherever the content sits.

Step 3 then switches the defaults behind one flag:

- content-sized views take their content's height;
- fillers take their minimum;
- `.fixedSize` climbs the measure ladder;
- a tall table's header and horizontal bar are pinned like a section's header and footer;
- the outer scroll view reveals a table's cursor, as it already does a list's.

Seven lanes take about 9½ lane-days. Three questions for the owner remain: eager
containers' off-screen rows, the vertical axis of a horizontal scroll view, and whether this
replaces design C (the pull).

## The problem

**The ruling (SCROLL-FIT, in [the owner's decisions of 2026-11-08](<../SwiftUI parity process/The owner's decisions of 2026-11-08.md>)).**
Along an axis its parent leaves unbounded, a view whose size depends on its content takes its
content's size by default. That axis is a `ScrollView`'s scroll axis, under `.fixedSize`, or in a
popover that sizes to its content. Space-fillers take their minimum. `.frame(height:)`,
`.frame(maxHeight:)` and `.containerRelativeFrame(.vertical)` stay available as opt-outs. Until
this ships, TABLE-TALL's (a) holds (5cec75080: a table is capped at the visible height).

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
   (`_NavigationSplitViewCore.sizeThatFits`). So in a scroll view it is the viewport's height, and
   under `.fixedSize` it is one line. That is a bug in its own right.
6. **`ScrollView(.horizontal)` also scrolls vertically.** `resolveScrollbars` and the render
   never check `axes.contains(.vertical)`, so its vertical axis is unbounded too.
7. **The focus reveal at launch scrolls a title away** above a focused table or list as tall as
   the viewport. `FrameBuffer.revealTarget` reveals the whole control on arrival.

Design C was the owner's answer to the same cost for lazy stacks nested in content. It is
NESTED-LAZY-PULL, ruled for on 2026-09-26 ("land D first … then pursue C"), described in
[Locating things without drawing them](<../../Layout and scrolling/Locating things without drawing them.md>) §5b and §6b,
and it never started. That story is
[Measuring a scroll view's content](<Measuring a scroll view's content - the overflow check, wide rows and nested lazy stacks.md>).
This design delivers the same O(visible) by a different route. A-SCROLLFIT-3 asks whether it
replaces design C.

## 1. Windowing anywhere in scroll content (step 2)

### 1a. What exists, and what each piece already does

| Piece | Where | What it does today | Reused for |
|---|---|---|---|
| `ScrollContentWindow` | `TUIFoundation/Views/ScrollContentWindow.swift` | Carries the visible slice down: offset, viewport height, the addressee (`contentIdentity`), the lines drawn above and below the consumer (`linesAbove`/`linesBelow`), the pending seek, read-back sampling and the top-row hold. | The window, unchanged in kind. Its addressee becomes "the child this container handed it to". |
| `ScrollContentReply` | same file | Sends the answer back up: the slice (`sliceOriginY`, `sliceTotalHeight`, `sliceTotalIsEstimate`, `sliceHoldsFirstRow`/`LastRow`), `drawnLines`, `seekResolvedOffset`, `measureWentStale`, target layouts and ids. | Every relaying container's answer. |
| `ScrollWindowRelay` | `ScrollWindowRelay.swift` | For a view that draws N lines above its content and M below (`Section`, `.padding`, the margins), moves the window into the content's coordinates and moves the reply back (`beneath(linesAbove:linesBelow:reply:)`, `answer(contentBuffer:linesBelow:)`). | The single-child relay, as it is. The multi-child relay is new (1b). |
| The uniform window | `StackUniformWindow.swift` | Treats a common row height as a hypothesis, seeded from row 0, checked against every row it measures, and dropped for good on the first row that differs. Placement is then arithmetic. | Fixed-pitch rows in `List` and `Table` (1c). |
| The anchored window | `StackAnchoredWindow.swift`, `StackAnchoredMeasure.swift` | Variable rows past 256: the position is a persisted anchor (row plus lines hidden), the band fills outward from it, and the extents of rows never built are estimated at the running pitch. | Variable rows in `List`, `Table` and `TextEditor`, through one shared engine (1c). |
| The top-row hold | `StackTopRowHold.swift`, `TopRowHold` | Moves the offset by however far the content above moved the row at the viewport's top. | Absorbing an estimate as it settles, at any depth (1c). |
| Off-band rows | `StackOffBandRows.swift`, `StackFocusReach.swift` | Builds the focused row, its neighbours and a pending focus target outside the band, for their regions and ring places. Probes up to 64 rows for the next focusable row past rows that cannot take focus. Grafts regions without adding lines. | Focus through unbuilt rows at every level (1e). |
| `targetOrdinal` / `ordinal(of:)` | `StackFocusReach.swift`, `StackLayoutPlacing.swift` | Finds which child holds a focus id or an identity, from the identity path, without building rows. | Finding the child that holds a focus or seek target (1e, 1f). |
| `ChildViewCollection` | `TUIView/Rendering/ChildViewCollection.swift` | Gives O(1) `count`, plus `key(at:)`/`anyID(at:)` with no row built, and builds a row on subscript. `.varying` `ForEach` rows build every member to count them. | The lazy stacks' row source, as it is. |
| `RowSource`, `ScrollRowWindow.resolve` | `TUILists/Views/_ListCore.swift`, `ScrollRowWindow.swift` | `List`'s O(1) count and lazy ids. Picks which rows to build from an offset, a height and a per-row height closure. `Table` calls the same resolver with `{ _ in 1 }` for single-line rows. | Unchanged. Fed the outer window instead of the view's own offset (1c). |
| Pinned chrome | `ScrollPinnedChrome.swift`, `OverlayLayer.ScrollPin`, `PinnedChromeCover` | A section's header or footer copy rides as a layer to the nearest scroll view, which pins it to the viewport edge while the section is under it. Reveal keeps a focused row out from under it. | A table's header and horizontal bar (2c). |
| The cursor marker | `_ListCore` and `Table` stamp a one-row `HitTestRegion` at the cursor's drawn line; `snapViewportToFocusedControl` reveals it | How the outer scroll view follows a list's cursor today. | Both containers' cursor reveal through the outer view (2d). |
| `WindowedRowFade`, `WindowedRowRecord` | `TUIView/Animation/WindowedRowFade.swift` | Fades a new row in only if it was not drawn last frame *and* was not in the data. Rows reached by scrolling appear without a fade. | Unchanged, provided `isRow` stays a data question (1g). |

The new parts are four:

- the multi-child relay (1b);
- the still window for subtrees off screen (1b);
- one anchored-row engine shared by every row container, where today only `_VStackCore` has it
  (1c);
- the seek holder (1f).

### 1b. The relay: every container that places a child hands it the window

**B-SCROLLFIT-1. The window is relayed and addressed child by child; it is not pulled.**

Today a stack takes the window only when its identity is a single-child descent from the
addressee (`ScrollContentWindow.isAtOrigin`, `consumableScrollWindow`). On the measure side, the
matching test is `RenderContext.scrollContentOriginDepth` with `leaveScrollOrigin()`. A stack
below a title is one child among several, not at the origin, so it is drawn whole.

The relay changes what "the origin" means. The window is **re-addressed** by every container that
knows a child's position:

1. The container measures its children, as it already does to place them. Every window consumer
   answers O(1) (1d), so this costs what measuring a column of plain views costs.
2. To each child it hands the window **moved into the child's coordinates** and **addressed to
   the child's identity**. This is `beneath(linesAbove: childY, linesBelow: containerHeight −
   childY − childHeight, reply: childReply)` with `contentIdentity` set to the child, and on the
   measure side the origin depth is set to the child's. The arithmetic is the relay's; what is new
   is that there are several children, and that the addressee changes.
3. It **assembles a band of its own**: the lines of its height that the window meets, plus one
   line either side for the "N more" indicators. A child that answered with a slice (a consumer)
   is placed by its `sliceOriginY`. A child that answered with a whole buffer (an eager view) is
   clipped to the band. Regions outside the band are grafted at their places without adding lines,
   using the off-band graft (`graftOffBandRow`). The container answers its own reply with
   `sliceOriginY` (the band's top), `sliceTotalHeight` (its height, flagged as an estimate if any
   child's was), `sliceHoldsFirstRow`/`LastRow`, and the relayed seek, hold, read-back and target
   fields, as `ScrollWindowRelay.answer` already moves them.

Shifting the window this way is the part design C's §5b said a push could not state. That
argument assumed a parent had to know its children's heights *before* it could hand down a
window. Here the parent knows them, because it has just measured its children, and the measures
of the children that matter are O(1). Where a height is only an estimate, the top-row hold (1c)
gives what the pull gave: content on screen never moves when an estimate refines off screen.

**Which containers relay** (each is a small conformance; anything not on the list keeps today's
behaviour, and its children leave the origin and are drawn whole, which is correct and costs what
it costs today):

| Container | Lines around its children | Lane |
|---|---|---|
| `VStack` (the eager column, `_VStackCore` `.clip`) | each child at its laid-out y | L1 |
| `HStack` | each child at its alignment's y; the band is the union | L1 |
| `ContainerView` chrome (`GroupBox`, bordered and titled boxes, `Table`'s border) | title and border above, border below | L1 |
| `DisclosureGroup` (expanded), `TabView` (tab bar), `NavigationStack` (title bar) | their label or bar lines above | L1 |
| `.background`, `.overlay` | none, at the content's origin; the secondary is drawn at the *band's* size and offset, not the content's whole height | L1 |
| `.border`, `.frame` with an alignment inside a taller frame | the border line, or the alignment offset | L1 |
| a content-sized nested same-axis `ScrollView` | none: it is transparent along that axis (2a) | L6 |
| `Section`, `.padding`, content margins | already relay | done |

**B-SCROLLFIT-2. A subtree entirely off screen is handed a still window.**

`ScrollContentWindow`'s equality includes the offset, so a child handed a moved window misses the
render memo on every scroll step. That is fine for children on screen, which redraw anyway. A
title or a whole table off screen should not pay it. So a child the window does not meet gets a
canonical window, "entirely above" or "entirely below" (offset pinned to the child's height, or to
the viewport height negated). That window does not change while the child stays off screen. A
consumer handed one draws only its off-band rows (1e), which costs O(1), and an eager child keeps
its memo.

Handing such a child *no* window would not do: a 10,000-row table below the viewport would fall
back to being drawn whole.

**The band and the scroll view.** The scroll view already handles a sliced answer from its direct
content (Stage 6: `sliceOriginY`, `coverSnappedViewport` from `drawnLines`). A relaying column at
the origin gives that same answer, so nothing changes in `_ScrollViewCore` beyond what the
`linesAbove`/`linesBelow` handling already does for a section.

The one subtle path is an offset moved *after* the render: the bottom re-glue, a focus snap, or a
hold. A band drawn for the old offset does not cover the new one. That case is
`ScrollContentReply.drawnLines` plus `coverSnappedViewport`, which re-draws the content at the
settled offset. A relaying column reports its band as `drawnLines` in the same way.

### 1c. Heights of rows not yet built

**B-SCROLLFIT-3. Fixed pitch is arithmetic; variable pitch is an estimate plus the hold, through
one shared anchored-row engine.**

- **Fixed one-line rows: exact, O(1).**
  - A single-line `Table` already measures without building a row (`measuredSizeThatFits`: header
    and column arithmetic, a stand-in content block of exactly `data.count` lines, and the real
    chrome).
  - A `List` whose rows are one line (plain `ForEach` of `Text`, the common case and the
    baseline's) takes the uniform hypothesis as a lazy stack does. It is seeded from row 0,
    checked against every row the band builds, and refuted the first time a row differs, once in
    the view's life. Its total is then `count × pitch` plus section headers. A section's row count
    comes from its own `ForEach`'s count, so the total is O(sections).
  - Refuting the hypothesis drops the pass's measures and replans the frame
    (`ScrollContentReply.measureWentStale`), as the stack's refuted hypothesis already does.
- **Variable rows: an estimate.**
  - Covers `List` rows of several lines, a multi-line `Table`, `TextEditor` lines that wrap, and a
    grouped `Form`'s rows.
  - Rows the band has built are measured exactly. Every row it has not built is estimated at the
    running pitch (`ScrollExtentEstimator` is `List`'s today; the anchored window keeps its own).
  - The total is flagged `sliceTotalIsEstimate`, so the indicators say "~N more below".
  - Below it, the content's y is an estimate. Above the viewport, a refined estimate would move
    the rows on screen, which is what the top-row hold is for. The consumer reports the row at the
    viewport's top, and the next frame's hold moves the offset by however far that row moved.
    That is exactly what the anchored lazy stack does, now reported through the relays, which
    already carry `seekResolvedOffset` and `resolvedOffsetIsHold` up.
- **One engine.** Today the anchored walk is `_VStackCore`'s alone (`AnchoredWindowFrame`,
  `StackWindowState`). L3 extracts it behind a small row-source protocol: `count`,
  `key(at:)`/`anyID(at:)`, `pitch(at:)` (measuring the row), and `draw(at:)`. The lazy stack,
  `List` (over `RowSource`), `Table` (over its data and `layoutOf`) and `TextEditor` (over its
  wrapped lines) each provide one. This follows the code-reuse rule; four hand-written anchor walks
  would drift apart.
- **`LazyVStack`'s first frame builds every row twice** (20,075 at 10,000). The cause has not been
  traced. The likely one is in the Locating doc's §6b: on a view's first render no content height
  has been recorded, so the scrollbar's first round climbs the ladder at the other width.
  - L1 traces it and fixes it in a commit of its own.
  - The rule after the fix is that a first frame builds O(visible) rows. The ladder's rungs are
    served by the memo, because a windowed answer "claims a natural size" (the per-pass memo
    serves it to every later ask at that width).

### 1d. Measuring without building every row

Under SCROLL-FIT a scroll view proposes no height along its axis, and the content answers its
content height. Today's views answer `proposal.height ?? context.availableHeight`, which fills
whatever rung they are offered. That pattern is what made the `List` 4,096 lines tall. The
conversion (L4 and L6) is:

- **A consumer answers a nil proposal from 1c** (O(1) or O(sections)), not from
  `availableHeight`, and flags the answer as a natural size so the per-pass memo serves every rung
  of the ladder.
- **The overflow probe** (`RenderContext.asksOverflow`) is answered from the same number. The
  column's early stop (`overflowProbeSizeThatFits`) then works unchanged above a table.
- **A container's measure** sums its children's measures, as now. With every consumer at O(1),
  `VStack { title; Table(10k); title; Table(10k) }` measures in O(children).
- **What stays O(N), and is allowed to.** These are scans of the data that build no row, once per
  user action and not per frame:
  - `RowSource.index(ofScrollKey:)` (by `typeAt`) and `Table`'s `firstIndex` for a `scrollTo`;
  - `index(of:near:)` for a selection set from outside (±64 rows first);
  - type-select's scan (`resolvePendingTypeSelect`).

  L2 checks that type-select reads `typeSelectText` without building a row. If it does build one,
  that is per key press and capped at a scan, but it is to be measured.

### 1e. Focus: an unbuilt row stays reachable

A `List` or `Table` registers *one* focusable, the container, and its cursor is an index
(`ItemListHandler.focusedIndex`). So keyboard reach inside it never depends on which rows are
built. What does depend on drawing:

- **The container must register even when the window misses it.** A consumer handed a still
  window (1b) still draws its off-band rows. For `List` and `Table` that means the cursor row: it
  registers the container, stamps the cursor marker at the row's place outside the band, and draws
  no lines. A container whose band is empty still registers.
- **A relaying container treats a child holding the focus as off-band**, as the windowed stack
  treats its focused row. It finds the child from the focus id's identity path (`targetOrdinal`,
  `ordinal(of:)`: no row built) and hands it the window. That child, in turn, draws its focused row
  off-band. Shift+Tab order is kept: a child above the band is drawn before the band
  (`drawOffBandRow`'s rule).
- **Tab out of the band.** Under A-SCROLLFIT-1's recommended answer, eager children are drawn
  whole and register as they do today. Only consumers draw a band, and each one's off-band rows
  plus the 64-row continuation probe (`focusRingContinuations`) already find the next focusable
  row.
- **Focus at launch.** The first focusable row in ring order is the first one registered. With
  every eager child drawn and every consumer registering, that does not change. See 2e for what
  the reveal then does.

### 1f. `scrollTo` of a row never built

**B-SCROLLFIT-4. A pending seek names its holder, so the relays build it.**

Today `ScrollToRegistry.scrollTo` parks the request on every live `ScrollToTarget`. An
`ItemListHandler` resolves it into its *own* offset (`resolveScrollRequests`, `scroll(toRow:)`).
The outer scroll view resolves keys only through stacks (`StackAnchoredWindow.locate(key:)`,
`ChildViewCollection.firstOrdinal(forKey:)`). A content-sized list has no offset of its own to
move, and its row may lie in a part of the tree no band reaches.

So:

1. At `scrollTo` time the registry asks each target whether it holds the key. That is the
   existing data scan, with no rows built. The one that does stamps the request with its identity
   (`ScrollToRequest.holder`).
2. The scroll view's window carries the request, as `seek` does today. Every relaying container
   draws the child that is an ancestor of the holder, off-band if need be, exactly as it draws the
   child holding a pending focus target.
3. The holder computes its row's y: exact for fixed pitch, from the anchor and pitch otherwise. It
   answers `seekResolvedOffset` through `ScrollContentWindow.offset(realising:…)`, which already
   respects the content's headroom and clamp. The relays add each level's y on the way up.
4. A key that no live target holds falls back to today's path, the stacks' keys.
5. An unknown key does nothing, as in SwiftUI.

The holder's row lands with the request's anchor in the *outer* viewport. A framed table, which
still scrolls itself, resolves into its own offset as now, and its outer scroll view reveals the
cursor marker that results.

### 1g. Animations and transitions of windowed rows

`WindowedRowFade` already separates "entered the band by scrolling" (no fade) from "inserted into
the data" (fade). It does this with `WindowedRowRecord`'s last-drawn set and the `isRow` question
about the data. Under the outer window a `List`'s or `Table`'s drawn set is its band, so nothing
changes there, provided `isRow` stays a data question and is never "was it drawn".

Two new cases:

- **A relaying container's eager children** come in and out of its band, but under A-SCROLLFIT-1's
  answer they are drawn whole every frame, so their insert and remove transitions run as now.
- If the owner chooses (c) instead, an eager row drawn for the first time as it scrolls in would
  look like an insertion. It would need the same record, keyed by the container's children (their
  identities are already resolved), so that a child present last frame appears without a fade.

A row removed while off-band plays no removal, since nothing would see it. That matches the stack
and `List` today.

## 2. Switching the defaults (step 3)

### 2a. Per view, from the baseline table

| View | Today (alone / under title / 2 stacked, 60 rows) | After |
|---|---|---|
| `Table` | capped at the viewport (24, scrolls itself) | its content: 63 at 60 rows, 10,003 at 10,000. Header and horizontal bar pinned (2c). The outer view reveals the cursor (2d). `scrollViewportCap` is deleted. |
| `List` (plain, sectioned, outline) | 4,096 (the rung) | its content (≈62 at 60). Plain one-line rows are arithmetic; sections are O(sections); outline rows take the variable path, which also fixes "a wheel step rebuilds every drawn row" (4,094 at 10,000) because only the band is drawn |
| `Form .grouped` | max(content, viewport), up to 4,096, then scrolls itself | its content (5 at 3 rows) |
| `Form .columns`, `GroupBox`, `DisclosureGroup`, `TabView`, `NavigationStack`, `Grid`, `FlowLayout`, `LazyVStack` | already its content | unchanged in size. Consumers inside them window through the relay (L1). Eager rows per A-SCROLLFIT-1 |
| `TextEditor` | max(content, viewport) up to 4,096, scrolls itself past that | its wrapped content (3 / 60 / 10,000). No bar of its own. It stamps a caret-line marker like the list's cursor marker, so the outer view follows the caret. Lines are windowed by the outer window |
| `ScrollView`, same axis | max(content, viewport) up to 4,096, its own bar | its content, no bar, transparent: it relays the window and forwards seeks to the outer view. Its own offset stays 0. A `ScrollViewReader` inside it seeks through the outer view |
| `ScrollView`, cross axis | as above | its content height; it still scrolls across |
| `NavigationSplitView` | the viewport's height; 1 line under `.fixedSize` | the tallest column's content. Fixed first as a bug (L0) |
| `HSplitView` | max(content, viewport) up to 4,096; rows past that unreachable | the tallest pane's content |
| `VSplitView` | panes split, top pane cut even at 60 | the panes' content heights summed. When no pane is flexible and the height offered covers the sum, each pane gets its natural height. The likely cause is `resolvedSizes`' even split when `flexibleIndices.isEmpty`, inferred from the code and still to be reproduced. A pane the user resized keeps its size and scrolls itself |
| `Image.resizable()` | fills the viewport alone, 15 when stacked | its ideal: 15, its pixels at the width |
| `Spacer`, `Color`, shapes, `GeometryReader`, `Text.frame(maxHeight: .infinity)` | fill or split the viewport; `GeometryReader` 4,096 | their minimum (B-SCROLLFIT-7): a `Spacer` its `minLength`, the others 0, a framed `Text` its text's height |
| `Divider`, `scaledToFit` images | unchanged | unchanged |
| `LazyHStack` | 1 line high; never windowed across | unchanged vertically. Windowing across is not part of this ruling (see "For a future reader") |

**The scroll view's canvas.** The content is drawn at its measured height, not at
`max(viewport, content)`. The canvas below short content is padded with blank lines, so
flexible children no longer stretch to the viewport. `containerRelativeFrame(.vertical)` still
reads the viewport (`containerSize(viewport:context:)`), so a table framed that way is as tall as
the visible area and scrolls itself, which is TABLE-TALL's behaviour as an opt-in.

`.frame(maxHeight: h)` hands a table a height of min(content, h), and the table scrolls itself
inside it. L6 tests that the frame makes the table's height explicit (`hasExplicitHeight`),
because the table's flexibility follows from that.

### 2b. Greedy views declare it; `.fixedSize` climbs the ladder

**B-SCROLLFIT-8.** Today a view is "greedy" on an axis when it reports at least the budget it was
offered. `_FixedSizeView.idealExtent` reads `extent >= budget` that way after a single measure at
`max(offered × 64, 4096)`, and the scroll view's ladder stops at its first rung on the same
evidence (`guard extent >= budget, !fills` in `naturalExtent`). That confuses "fills what it is
given" with "has more content than the budget".

- **Fillers declare it.** Under a nil proposal on an axis, a filler answers its minimum (0, or a
  `Spacer`'s `minLength`) and is flexible on that axis. `Color`, shapes and `Spacer` already
  answer 0×0 flexible. `GeometryReader` (`_GeometryReaderCore`: `proposal.height ??
  availableHeight`) and a `.frame(maxHeight: .infinity)` without a proposal change to match.
  "Flexible with an extent of 0 or its minimum" is the declaration. No new type is needed:
  `ViewSize.isHeightFlexible` already carries it, and `.flexibleHeight` builds it.
- **Content-sized views answer content**, as 1d describes, and are flexible only where a height
  was given (TABLE-IN-SCROLL-HEIGHT's rule, which every consumer takes).
- **`.fixedSize` uses the ladder** (`naturalExtent(_:along:proposal:context:startingBudget:)`), as
  the scroll view does, instead of its single measure. It stops when the extent comes in under the
  rung, or when the view declared itself a filler, which keeps the offer exactly where it keeps it
  today for fillers. With consumers at O(1), and their answers memoized as natural sizes, the rungs
  cost nothing. A 10,000-row table under `.fixedSize` is then 10,003 lines and builds the rows on
  screen, instead of 23 lines after building 4,153.
- **What still climbs the ladder for real**: views not yet converted, an app's own `Layout`, and
  views that measure by rendering. Their behaviour is unchanged. The ladder stays as the safety
  net, and `isNaturalExtentBudget` stays for pictures.

**B-SCROLLFIT-7. A filler's ideal along an unbounded axis is its minimum, 0 for `Color`, shapes
and `GeometryReader`.**

This is the height counterpart of the ideal-width ask, under which a filler already answers 0
(`fillingWidth`). SwiftUI answers 10 points (`replacingUnspecifiedDimensions`, measured
2026-09-23), less than a line. One line was considered and declined because it would be the one
place a filler invents a size, and an app that wants a `GeometryReader` in scroll content frames
it in SwiftUI too. If the owner prefers a line, the change is one constant.

### 2c. A tall table's header and horizontal bar, pinned to the visible area

**B-SCROLLFIT-9.** Pinned section chrome (`ScrollPinnedChrome.swift`) already does what this
needs. A header layer carrying `OverlayLayer.ScrollPin` rides every combining operation to the
nearest scroll view along its axis. That view places it at the viewport's top while the section's
content is under it, and the content's end pushes it away. A footer stays at the bottom edge and
never rises above its section's first row. The reveal keeps a focused row out from under either
(`PinnedChromeCover`).

- **The header.** A content-sized `Table` emits a copy of its header as a top-pinned layer. That
  is the header line, its rule line, and the table's side borders on those lines, so the box
  reads as closed. The table's top border is not pinned, just as a section's pinned header is
  only the header. A second table's header pushes the first away. That is SwiftUI's
  section-header rule, and it is what "two tables stacked" should look like.
- **The horizontal bar** (`TableHorizontalWindow`, `drawHorizontalScrollbar`) becomes a
  bottom-pinned layer, under the same rule. Regions on pinned layers are already placed where they
  are drawn, so dragging the bar keeps working.
- **The table's band**, not its whole height, is what it draws. The pinned layers are emitted
  whenever any of its band is drawn, with `offsetY` at their natural place, possibly outside the
  band. That is how a section header above a lazy stack's band reaches the scroll view today.

The table keeps its own horizontal scrolling by whole columns (Left and Right), because the outer
scroll view is vertical.

### 2d. Keyboard in a tall `List` or `Table`

- **Arrows, Home and End, type-select (`r45`)** move the cursor index. The cursor row is drawn
  (in band or off-band, 1e) and stamped with the cursor marker, and `snapViewportToFocusedControl`
  reveals it through the outer view. `List` does this today; `Table` does too, on a table that has
  stopped scrolling itself. The baseline's "Table doesn't" most likely came from the cap (the table
  scrolled its own rows and the page never moved), not from a missing marker (`Table.swift` stamps
  it from `drawnBands`); L2 confirms it with the switch on.
- **B-SCROLLFIT-5. Page Up and Page Down move by the outer viewport.**
  - `ItemListHandler` pages by its own `viewportHeight`, which for a content-sized list is its
    whole height, so Page Down would act as End. It pages instead by the window's
    `viewportHeight`, less the pinned header's lines.
  - When no window is handed, the list's own height is used, so a framed or free-standing list is
    unchanged.
  - The row landed on is revealed at the viewport's bottom (Page Down) or top (Page Up), as a list
    scrolling itself places it.
- **The wheel** over a content-sized table or list goes to the outer view. The inner one has
  nothing to scroll, so edge-chaining never comes into it.

### 2e. Focus at launch does not scroll a title away

**B-SCROLLFIT-6. On arrival, the reveal of a control taller than the viewport reveals its cursor
line, and does nothing if that line is already on screen.**

`FrameBuffer.revealTarget(focusID:wholeControl:)` reveals the union of the control's regions when
focus arrives, and its smallest region when focus moves within it. For a control taller than the
viewport the union cannot be revealed, and aligning its top moved the page past the title (by
one line in the baseline). The rule becomes:

- if the union fits in the viewport, reveal the union (unchanged);
- otherwise, reveal the smallest region (the cursor marker), and only if it is not already
  visible.

That is the Locating doc's §5c rule, "reveal only when needed", applied to arrival. At launch the
first row sits under the title, on screen, so nothing moves.

### 2f. `NavigationSplitView` and the split views

These are fixed as part of the switch (2a), except `NavigationSplitView`'s one line under
`.fixedSize`. That is a bug today, with or without the ruling, and L0 fixes it first, with a
failing test:

- under a nil proposal, `_NavigationSplitViewCore.sizeThatFits` answers the tallest column's
  measure (sidebar, content, detail, each under a nil proposal) and stays flexible;
- `combineColumns` pads to that height, not to `availableHeight`.

### 2g. The horizontal scroll view's vertical axis

The ruling names "a `ScrollView`'s scroll axis". `ScrollView(.horizontal)` here also scrolls
vertically when its content is taller (finding 6). No comment or deviation entry calls that
deliberate (C-SCROLL-1 describes SwiftUI, where a horizontal view cannot scroll down). This is a
real choice for the owner: A-SCROLLFIT-2.

## 3. Performance budget

**What must be O(visible) per frame**, independent of the row count (rows *built*, meaning a row
builder called, counted as `ScrollFitProbe.built` counts them):

- the rows built for a first frame, an idle redraw, a wheel step, a cursor step, a Page Down, and
  a `scrollTo` to a row never built;
- every content-sized consumer's measure: O(1) for fixed pitch, O(sections) for sectioned lists,
  O(rows built so far) in memory for the variable estimate's record and O(1) per frame;
- a relaying container's measure and band: O(its children). Its eager children are drawn whole,
  as today, under A-SCROLLFIT-1's (a).

The bound is "the band plus the off-band rows": the viewport's rows, one margin row each way, the
focused row ±1, any pending focus or seek holder, and at most the 64-row focus continuation probe
each way. The probe is the existing cap and is rarely spent.

**Allowed to be O(N), not per frame:** data scans that build no row, at the user action that
needs them (1d).

**Each lane's gate:**

1. **Counts, deterministic.** For each new shape, `builtFirst` and `builtStep` at 1,000, 10,000
   and 100,000 rows must be **equal** across the three sizes, which proves O(visible). They are
   pinned in tests next to `ScrollFitBaselineTests`, and the 10,000-row tests there are updated on
   purpose.
2. **Time and memory.** `Stress --bench`, quiet box, A/B against the lane's base:
   - first-frame ms, idle-redraw ms, scroll-step ms and peak RSS at 10,000 and 100,000;
   - target: the content-sized table's scroll step and idle redraw within 2× of the capped table
     TABLE-IN-SCROLL-HEIGHT measured (1.1 ms idle, 4.0 ms step at 10,000, debug, `TestApp` 60 ×
     30), and flat from 10,000 to 100,000.
3. **No regression** on the existing scenarios that cross these paths: `app-shapes` variants
   `grouped-feed`, `grouped-feed-uniform`, `headed-log`, `sidebar` and `file-browser`; the table
   scenarios (`TableGroups`, `WideTable`, `MultiLineTable`, `ChurningTable`); `MegaList`,
   `ScrollEager` and `ScrollFollow`. The owner's tolerance applies: a few percent is fine, around
   10% means optimise first.
4. **`Stress --selfcheck` and the render-memo verifier** stay clean. A band is a function of state
   (offset, anchor, focus) and must equal a fresh render's.

**Stress scenarios to add** (variants of a new `scroll-fit` scenario in `Sources/Stress/Scenarios/`,
each with the page moving every tick unless noted):

| Variant | Shape |
|---|---|
| `two-tables` | `ScrollView { VStack { Text; Table(10k, 4 columns); Text; Table(10k) } }`, wheel steps through both |
| `two-tables-keys` | the same, Down and Page Down driven in the second table every tick (cursor reveal through the outer view) |
| `titled-list` | a title over a `List` of 10,000 one-line rows |
| `titled-list-variable` | the same with rows of 1 to 3 lines (the estimate and the hold) |
| `grouped-form` | `Form { … }.formStyle(.grouped)`, 40 sections of 250 rows |
| `boxed-lazy` | `GroupBox { LazyVStack { ForEach(10k) } }` under a title (relay through chrome) |
| `fixed-size-table` | `VStack { Text; Table(10k) }.fixedSize(horizontal: false, vertical: true)` in a scroll view (the ladder) |
| `tall-editor` | a title over a `TextEditor` of 10,000 wrapped lines, typing in the middle |

L1 adds the scenario with whatever variants its code reaches, and each later lane adds its own.
The `grouped-feed` variants are the ones design D's cost (+707%) was measured on. The relay
windows the nested stacks there too: each outer row in the band hands its nested stack the window.
Its numbers are this design's first proof against design C's aim.

## 4. Sequencing

Each lane lands alone with the suite green.

- **L2 to L5 build behind one internal switch** (B-SCROLLFIT-10): a package-level environment
  value, `scrollFitsContent`, false by default and set by the lanes' tests. L6 flips it and
  deletes it, so no compatibility spelling survives (the "no compat shims" rule).
- **The docs go in the commit whose behaviour they describe** ("docs as you go"). The step-4
  rewrite of deviation L19, the `Table`/`List`/`Form` articles and the compatibility guide is
  L6's.
- **Each lane changes `ScrollFitBaselineTable.swift`**, the 10,000-row tests and the keys test, row
  by row on purpose, as the table below says.

| Lane | What | Days | `ScrollFitBaselineTable.swift` and the 10,000-row tests |
|---|---|---|---|
| **L0** | `NavigationSplitView`'s natural height (2f), a bug fix | ½ | `navigationSplit fixedSize` rows go from 1 line to its columns' content height |
| **L1** | The relay (1b) through `VStack`, `HStack`, the chrome, wrappers, `.background`/`.overlay`/`.border`/`.frame`. The still window. Bands from relaying containers. The lazy stack's first frame built once (1c, its own commit). The `scroll-fit` Stress scenario. A/B gated (every eager column in scroll content takes the new path) | 2 | No size changes. `tallLazyStackUnderTitle` goes from drawn whole to windowed (< 100 rows built). `tallLazyStackAlone`'s first frame goes from 20,075 to < 100. The `lazyVStack` and boxed rows' built counts drop |
| **L2** | `List` and `Table`, fixed pitch, consume the window (1c, `ScrollRowWindow` fed the outer window); off-band cursor row and still-window registration (1e); Page Up/Down by the outer viewport (2d); seek holders (1f). Behind the switch | 1½ | None with the switch off. New tests with it on |
| **L3** | The shared anchored-row engine (1c) extracted from `_VStackCore`; variable `List` rows, multi-line `Table`, `TextEditor` lines (with its caret marker), the grouped `Form`. Behind the switch. A/B gated (the lazy stack's anchored path moves into the shared engine) | 2 | None with the switch off |
| **L4** | Nil-proposal answers (1d); fillers declare it (B-SCROLLFIT-7/8); `.fixedSize` on the ladder (2b) | 1 | `fixedSize` rows at 10,000 for views already content-sized: `Table` 23 → 10,003, `LazyVStack`/`Grid`/`GroupBox`/`DisclosureGroup`/`TabView`/`NavigationStack`/`.columns` `Form` 23 → their content. `tallTableFixedSize` goes from 4,153 rows built to < 100. Fillers' `fixedSize` rows unchanged (0) |
| **L5** | The table's pinned header and bar (2c); the arrival reveal (2e) | 1 | The keys test: the title stays on screen at launch. Pinned-chrome tests with the switch on |
| **L6** | The switch: defaults flipped, the switch deleted, `scrollViewportCap` deleted, `TextEditor`/nested `ScrollView`/grouped `Form`/split views content-sized, fillers' minimum, the horizontal view per A-SCROLLFIT-2. Rewrites `TableInScrollViewHeightTests` and `FramedTableFillsTests`. Docs: deviation L19, the articles, CHANGELOG, compatibility guide | 1½ | Every row in the "Under SCROLL-FIT" column, e.g. `table underTitle 60` 59x24 → 59x63, `listPlain alone 60` 59x4096 → 59x62, `color alone` 24 → 0. Column (v) per A-SCROLLFIT-2. The `ownBar` column goes to `n` for every content-sized view |
| *(L7)* | *Only if A-SCROLLFIT-1 is (c): eager containers window their rows past 256* | *2* | *built counts of `Grid`, `FlowLayout`, `.columns` `Form`* |

**Total: 9½ lane-days** (L0–L6). L1 and L3 each owe an A/B. L1 is the riskiest: it is on the path
of every eager column in scroll content, and its still-window and band logic has to keep the
render memo's hit rate on pages that are not tall. If L1's A/B shows more than about 10% on the
existing scenarios, the fallback is to relay only through columns that hold a consumer, where
"holds a consumer" is a flag a consumer's measure raises. That costs one more bit in the measure
answer.

## 5. Questions for the owner

### A-SCROLLFIT-1. Eager containers' rows off screen

*`VStack`, `Grid`, `FlowLayout`, a `.columns` `Form`, and a `GroupBox` or `DisclosureGroup` around
a `ForEach`, at thousands of rows in scroll content.*

SwiftUI's eager containers build every row: that is why `LazyVStack`, `LazyVGrid`, `List` and
`Form` exist. Today TUI does the same, at 3 to 9 builds a row a frame (10,000 rows: `Grid` 6 to
14 s a case, `GroupBox` 60,000 builds; debug).

- **(a) ★ Stay eager.** Every eager row is drawn every frame, as SwiftUI's are, with `onAppear`,
  `.task` and transitions as today. A consumer *inside* an eager container (a `List` in a
  `GroupBox`) still windows through the relay. **Price:** 0 days, but an eager container of
  thousands of rows keeps today's cost, and the app's remedy is SwiftUI's: the lazy type. It is
  also the simplest band, because eager children register their focusables and transitions as they
  do today.
- **(b) Measure every eager row, draw only the band.** **Price:** about 1 day. An off-screen
  eager row's `onAppear`/`.task` runs when it scrolls in, a deviation from SwiftUI. The saving is
  only the drawing; every row is still built to be measured, so expect at most a few-fold cut, to
  be measured. The off-band focus probe and a presence record (1g) are needed for eager rows.
- **(c) Window eager containers past 256 rows, as the lazy stack does** (L7). **Price:** about 2
  days. O(visible) everywhere, but the same `onAppear` deviation, and an eager stack's height
  becomes an estimate ("~N more") with the hold absorbing it.

### A-SCROLLFIT-2. The vertical axis of `ScrollView(.horizontal)`

TUI's horizontal scroll view also scrolls vertically, which SwiftUI's does not. Under the ruling
its vertical axis is either bounded or not.

- **(a) Parity.** It stops scrolling vertically and proposes its own height. A content-sized view
  takes that height and scrolls itself (a 10,000-row table in a horizontal scroll view is the
  view's height, with its own bar). **Price:** ½ day. Eager content taller than the view is cut
  off and cannot be reached, as in SwiftUI. That is a loss on a short terminal.
- **(b) ★ Bounded for sizing, scrollable when it overflows.** Content is proposed the view's
  height, so content-sized views fit it and scroll themselves, as in SwiftUI. Eager content that
  is still taller keeps today's vertical scrolling, so nothing becomes unreachable. **Price:** ½
  day, and one sentence in the deviations (an extension SwiftUI lacks, which no SwiftUI program
  can trip over). Column (v) of the baseline then reads: `Table` 24 (its own bar), `List` 24 (its
  own bar), eager containers as now.
- **(c) Unbounded, like a vertical scroll view.** Content-sized views take their full height and
  the horizontal view scrolls them vertically. **Price:** 0 extra days, but `.horizontal` then
  makes a two-axis view of any tall content. A wide table gets its rows scrolled by an outer view
  the app declared horizontal, with the header pinned by a view it never asked to scroll that way.

### A-SCROLLFIT-3. Does the relay replace design C (NESTED-LAZY-PULL)?

The owner ruled for design C on 2026-09-26 (the scroll view pulls placements outward from an
anchor, and every container answers for its own children). It was estimated at several weeks and
never started. The relay here reaches O(visible) for the same shapes, nested lazy stacks and
`grouped-feed` included, in about 4 of its 9½ days (L1 plus L3).

- **(a) ★ The relay is design C's implementation.** The full pull is not built, and the
  NESTED-LAZY-PULL item closes when L1's `grouped-feed` numbers show design D's cost gone.
  **Price:** every consumer reports a total height. For variable rows that total is an estimate,
  so the thumb and the "N more" counts are approximate ("~"), and content *below* a variable list
  moves as its estimate settles (never content on screen, which the hold keeps still). An app's
  own `Layout` does not relay (it measures and places by its own rules), so a consumer inside one
  is drawn whole, as today.
- **(b) Build the relay now and the pull later.** **Price:** the pull's weeks again, for exact
  positions without any total ever computed (the Locating doc's §6b footer is "never touched"),
  and relaying through app `Layout`s via an outward placement protocol.
- **(c) Build the pull instead of the relay.** **Price:** weeks rather than days, before any
  SCROLL-FIT default can switch. TABLE-TALL's cap holds until then.

## For a future reader

- **`LazyHStack` never windows across.** It rebuilt 9,990 items per wheel step in the baseline.
  The relay is axis-agnostic in shape (`columnSeek`/`columnReport` already travel across), so the
  mirror is a lane of its own of about 2 days, outside this ruling.
- **App `Layout`s do not relay.** A consumer inside one is drawn whole. If that becomes common, the
  fix is a protocol that lets a `Layout` say where it placed each child, after `placeSubviews`, so
  the relay can read the offsets. Until then it is the cost of today.
- **The still window (B-SCROLLFIT-2) is what keeps the memo's hit rate.** A later change that
  hands a moving window to children off screen would show as an idle-redraw regression on pages
  that do not scroll.
- **`isRow` must stay a data question** (1g). Answered from drawing, every row scrolled into a
  band would fade in.
- **The switch (B-SCROLLFIT-10) lives only from L2 to L6.** If L6 is delayed, the switch is not to
  become public API. It is deleted, not deprecated.

## The record

### B-SCROLLFIT-1. The window is relayed, addressed child by child

See 1b. Chosen over the pull (A-SCROLLFIT-3 asks whether it replaces it) because each relaying
container already measures its children to place them, and with consumers measured in O(1) that
measure gives every child's y. The arithmetic is `ScrollContentWindow.beneath` and
`ScrollWindowRelay.answer`, which ship.

### B-SCROLLFIT-2. A subtree entirely off screen is handed a still window

See 1b. A canonical "above" or "below" window that does not move while the child stays off
screen, so its memo holds. No window at all would make an off-screen consumer fall back to being
drawn whole.

### B-SCROLLFIT-3. Fixed pitch is arithmetic; variable pitch is an estimate held at the top row

See 1c. One anchored-row engine, extracted from `_VStackCore` and shared by the lazy stack,
`List`, `Table` and `TextEditor`, rather than four.

### B-SCROLLFIT-4. A pending seek names its holder

See 1f. The registry already asks every live target; the one holding the key stamps its identity
on the request, and the relays draw that child as they draw a pending focus target.

### B-SCROLLFIT-5. Page Up and Page Down move by the outer viewport

See 2d. By the list's own height, a content-sized list's Page Down would act as End.

### B-SCROLLFIT-6. On arrival, a control taller than the viewport reveals its cursor line

See 2e. Revealing the union aligned the control's top and scrolled away the title above it.

### B-SCROLLFIT-7. A filler's ideal along an unbounded axis is its minimum

See 2b. 0 for `Color`, shapes and `GeometryReader`, and a `Spacer`'s `minLength`: the height
counterpart of the ideal-width ask's 0. SwiftUI's 10 points (less than a line) was not rounded up
to one line.

### B-SCROLLFIT-8. Greedy views declare it; `.fixedSize` climbs the ladder

See 2b. "Filled the budget" no longer means greedy. A filler says so with its flexibility at its
minimum, and `.fixedSize` measures with the same ladder the scroll view uses.

### B-SCROLLFIT-9. A tall table's header and horizontal bar are pinned as a section's header and footer

See 2c. Reuses `OverlayLayer.ScrollPin`, `PinnedChromeViewport.pinnedRow` and
`PinnedChromeCover`. The header with its rule line and side borders is pinned; the table's top
border is not.

### B-SCROLLFIT-10. Built behind an internal switch, flipped and deleted in one lane

See 4. Lets L2 to L5 land alone with the suite green and the baseline unchanged. It is not public
and does not outlive L6.
