# Completing the SwiftUI API: lane GUIDE's new judgement calls

*The lane that fixed two alignment-guide parity bugs measured on 2026-10-11:
a guide outside its own view was clamped to that view's size, and a trailing or
centred run that a child overhung was shifted so its guides no longer met.
Where the work met a judgement call the brief did not settle, the safe option
shipped and is written up here, in the three parts the other lanes use: A needs
a decision, B shipped the safe option (with the fuller version and its price),
C declined with a parity-map reason. SwiftUI's behaviour was measured with
SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in the
session notes, `GUIDE/probe/` and `GUIDE/probe2/`).*

## A. Needs a decision

### A-GUIDE-1. SwiftUI's lazy stacks ignore an explicit alignment guide; TUIkit's honour it

*`LazyVStack(alignment:spacing:pinnedViews:content:)`,
`LazyHStack(alignment:spacing:pinnedViews:content:)`,
`.alignmentGuide(_:computeValue:)`*

Measured (GUIDE/probe2, `guide3.out`, `guide4.out`): in a `LazyVStack` 400
points wide, a 1-wide view with leading guide 5 above a 6-wide view leaves both
at 0; with `.trailing` and a 3-wide view whose trailing guide is 0, the views
are at 397 and 394 — each at the alignment's default, the guide unread. The
same inside a `ScrollView`, with `.fixedSize()` (the stack then takes its first
row's width, and the 6-wide view sits at -3), with `Text` rows, with a guide
that lies inside the view (`d.width`), with the row inside a `ForEach`, and for
`LazyHStack(alignment: .top)`. An eager `VStack` with the same rows honours the
guide.

TUIkit's lazy stacks honour it, by design: `AlignmentGuideModifierTests`
"A guide on a lazy stack's row is not silently inert" pins it, and the placed
and windowed runs share the eager stacks' `AlignmentGuideRun` (this lane checked
them against the eager rule: a placed lazy column sizes to its run, and a
window moves the run as a whole, its guides still on one line —
`AlignmentGuideContainerParityTests`). The comment on `assembleWindow` says the
realized rows are "the same limit SwiftUI has", which the measurement does not
bear out.

**Options.**
1. *Match SwiftUI* (parity): a lazy stack places each row by its alignment's
   default and asks no row for a guide. Removes the guide runs from four lazy
   paths and their measure twins (`placedGuideRun`, `slotGuideRun`, the
   windowed measures — less code), and turns the "not silently inert" test
   around. Price: an app that relied on a guide in a lazy stack sees it stop
   working, as it would in SwiftUI.
2. *Keep honouring it* and record it as a deviation in the compatibility doc.
   Price: a SwiftUI app moved to TUIkit lays out differently in a lazy stack
   that carries a guide (rare: SwiftUI ignores it, so such code does nothing
   there).

Recommended: 1, by the parity rule; nothing has shipped either way in this
lane.

### A-GUIDE-2. SwiftUI does not report a built-in guide out of a stack of several views

*`VStack`, `HStack`, `ZStack` reporting their children's guides
(`StackGuidePropagation.swift`, `_HStackCore`/`_ZStackCore.explicitGuide`)*

Measured (GUIDE/probe2, `guide3.out`, `guide4.out`, `guide6.out`), an inner
stack inside `VStack(alignment: .leading)` beside a 6-wide view C:

| inner stack | C's x |
|---|---|
| `VStack(alignment: .leading) { G (w 1, leading 5) }` — one view | 5 (reported) |
| `VStack(alignment: .leading) { G (w 1, leading 5); S (w 6) }` | 0 |
| `VStack(alignment: .leading) { G (w 6, leading 2); S (w 6) }` | 0 |
| `VStack(alignment: .center) { G (w 1, leading 5); S (w 6) }` | 0 |
| `VStack(alignment: .center) { G (leading 5); S (leading 1) }`, both explicit | 0 |
| `HStack { G (w 1, leading 5); S (w 6) }` | 0 |
| `HStack { S (w 6); G (w 1, leading 0) }` | 0 |
| `ZStack(alignment: .leading)` and `.center`, the same two views | 0 |
| `HStack(alignment: .top) { G (h 1, top 5); S (h 6) }` in `HStack(alignment: .top)` | 0 (C's y) |

With a custom `AlignmentID` (`.mark`, default `d[.leading]`) the guide IS
reported out of a two-view `VStack(alignment: .center)` and a two-view `HStack`
(C at 7.25 and 5): the decimal-point pattern works. W05's probe `r`, which the
propagation was built on, used one view per inner stack, where a built-in
guide is reported too. So the rule appears to be: a stack reports a built-in
guide (`.leading`, `.top`) only when it has one view, and a custom guide from
several (hypothesis: the built-in guides' `_combineExplicit` differs;
unmeasured beyond these rows, and the text baselines not at all). TUIkit reports both, merged by the mean
(`combineExplicit`), so its layout differs from SwiftUI's in the rows above.

**Options.**
1. *Match SwiftUI*: measure the rule fully first (`.trailing`, `.bottom`, the
   baselines, three views, a stack with spacers), then answer `nil` from a
   multi-view stack for the built-in guides it does not report. Price: a probe
   lane and a change to `combineExplicit`'s callers; layouts that relied on
   TUIkit's merge move.
2. *Keep* and record the deviation.

Recommended: 1, in a lane of its own (it is not a guide-value question, so it
was left out of this one).

## B. Shipped the safe option

### B-GUIDE-1. A region smaller than the run keeps the run's leading edge on its own

*`AlignmentGuideRun.resolve`: a `.frame` or `.overlay` narrower than its
content, a column a flexible child fills, a lazy column's window*

SwiftUI's rule, measured, is that each view sits at `max(guides) - its guide`
and the stack is as big as that needs. TUIkit now places a run so, and when the
region is bigger than the run, moves the run as a whole toward the region's own
guide only as far as all of it still fits: `anchor = min(max(M, regionGuide(E)),
M + room)`, where `room = max(0, E - contentExtent)`.

The brief wrote the room without the `max(0, …)`. That differs only for a
region SMALLER than the run, where it would move the run back so its far edge
met the region's — a leading-aligned column then lost the alignment of every
row whose base is less than the overhang, where today it loses only the rows
that overhang. With the `max`, a run in a region too small for it keeps its
leading edge on the region's, as a `.leading` run always did, and the per-child
clamp pulls back only the views that would fall outside, as before.

**The fuller version** is SwiftUI's: the stack reports the size the run needs,
past its proposal, and the parent places and clips it. Measured: in a 400-point
host, `VStack(alignment: .trailing)` holding a 3-wide view with trailing guide
0, a 6-wide view and a view with `maxWidth: .infinity` is 403 wide, the
flexible view at 0 and the 3-wide one at 400. **Price:** every TUIkit container
holds its report to its proposal ("never advertise a size larger than the
constraint", `_VStackCore.sizeThatFits`), and the parent's buffer is the size
it reported, so this is a change to every container's contract, not to the
guide run.

### B-GUIDE-2. One guide pushes a view at most 4,096 cells, whatever the container's extent

*`AlignmentGuideRun.maximumPush`, `.alignmentGuide(_:computeValue:)`*

A finite guide is now used as given, as SwiftUI's is; what is bounded is how
far one guide falling short of another pushes a view along the run, because a
content-sized run pads a buffer to its extent and a runaway guide (`1e300`)
would otherwise ask for one `Int.max` cells wide (117c0533e, b2182b996). A
non-finite guide is still the view's own origin.

The brief suggested the bound be the container's available extent plus the
views' sizes, with a hard cap for unbounded proposals. The bound shipped is the
hard cap alone, 4,096 cells — the natural-extent ladder's first rung, half of
which TUIkit already takes as more than any real bound offers
(`isNaturalExtentBudget`) — floored at the region's own extent and its widest
view, which are drawn already. A view pushed that far is past any terminal's
edge with either bound, so nothing visible differs; the constant reads no
budget, which a bound on the available extent would: a row reports its height
without reading the vertical budget (`_HStackCore.clipSizeThatFits`), and the
measure and the render would each bound the run by their own budget.

**The fuller version** would hold no bound at all on a guide that lies within
`Int`, so a view could be pushed past 4,096 cells into a scroll view's canvas.
**Price:** a buffer as wide as the guide asks, per row, and a stack asked its
ideal width under a runaway guide climbing the ladder toward `Int.max` instead
of stopping at its second rung. And a view pushed past the bound that reports
its guide up through its stack reports it from where it was placed, not from
where SwiftUI would place it — visible only through two explicit guides more
than 4,096 cells apart.

### B-GUIDE-3. One child whose guide would put it outside its region is held inside it

*`.frame(width:height:alignment:)`, `.overlay(alignment:content:)`,
`.background(alignment:content:)` — `horizontalGuidePlacement`,
`verticalGuidePlacement`*

Measured (GUIDE/probe2, `guide2.out`, `guide5.out`): SwiftUI places a single
child so its guide meets the region's, wherever that puts it. In
`.frame(width: 20, alignment: .leading)` a 6-wide view with leading guide 5 is
at -5, with guide 25 at -25; with `.trailing` and guide 0 it is at 20, past the
frame's far edge; an `.overlay` or `.background` on a 20-wide view does the
same, and `.frame(height:alignment: .top)` likewise down the column. SwiftUI
does not clip a frame, so the child draws outside it.

TUIkit places the child at the nearest position to SwiftUI's that keeps all of
it inside the region — `min(max(0, x), extent - size)` — as it places a child
wider than its region (`childOffset(childWidth:in:)`), so the six-cell view is
drawn whole. Before this lane's two fixes the guide was first held to the
view's own size, so a trailing guide of 25 put the view at 8 instead of 0;
every other measured placement is unchanged
(`AlignmentGuideContainerParityTests`).

**The fuller version** draws the child where SwiftUI puts it: the part inside
the region, clipped, or all of it as an overflow layer outside the frame's
buffer (`OffsetView` draws one). **Price:** a region would stop containing its
content, which every TUIkit container assumes of a buffer (its size is its
extent), or a child past the edge would be cut — showing six cells' worth of a
view as one or none, where today it is whole.
