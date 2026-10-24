# Completing the SwiftUI API: lane GUIDE's new judgement calls

*The lane that fixed two alignment-guide parity bugs measured on 2026-10-11:
a guide outside its own view was clamped to that view's size, and a trailing or
centred run that a child overhung was shifted so its guides no longer met.
Where the work met a judgement call the brief did not settle, the safe option
shipped and is written up here, in the three parts the other lanes use: A needs
a decision, B shipped the safe option (with the fuller version and its price),
C declined with a parity-map reason. SwiftUI's behaviour was measured with
SwiftUI 6.5.4 on macOS 15.8.1 with offscreen `NSHostingView`s (probes in
[`Tools/SwiftUIProbes/Alignment guides/`](<../../../../Tools/SwiftUIProbes/Alignment guides>)).*

## A. Needs a decision

### A-GUIDE-1. SwiftUI's lazy stacks ignore an explicit alignment guide; TUIkit's honour it — decided: keep honouring it

*`LazyVStack(alignment:spacing:pinnedViews:content:)`,
`LazyHStack(alignment:spacing:pinnedViews:content:)`,
`.alignmentGuide(_:computeValue:)`*

Measured (`Tools/SwiftUIProbes/Alignment guides/guide3.out`, `guide4.out`): in a `LazyVStack` 400
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
`AlignmentGuideContainerParityTests`). The comment on `assembleWindow` said the
realized rows were "the same limit SwiftUI has", which the measurement does not
bear out; it, and LayoutSystem.md, now say what was measured.

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

**Owner (2026-10-12): keep honouring guides in lazy stacks** (option 2);
SwiftUI's ignoring them looks like a bug. Measured since (session notes
`GUIDE2/notes.md` §1): SwiftUI's lazy stacks never ask a row for its guide,
and report none to their parent either, not even a custom one. Its
documentation says nothing about it (the macOS 26.2 SDK's doc comments,
searched); it may be a side effect of laziness, since the eager rule needs
every row's guide and a lazy stack does not build the rows off screen. Either
way SwiftUI code with a guide in a lazy stack does nothing, so no code relies
on it, and copying it would only take a working feature away. Recorded as a
deliberate deviation in the compatibility guide.

**The cost, which only an app with a guide on a lazy row pays** (gated by the
static witness): when a lazy row's type carries a guide, two fast paths step
aside, the uniform window at any row count and the anchored window over 256
rows, and the exact slot walk measures every row on every frame. That is what
keeps the alignment column still while rows scroll in. Its cost on a big list
is unmeasured. A lazy stack outside a scroll view resolves its guides over the
rows it placed, so a guide on a row past the cut does nothing until that row
fits.

### A-GUIDE-2. SwiftUI does not report a built-in guide out of a stack of several views

**Owner, 2026-10-12 (second message):** follow SwiftUI, option (a): an edge or centre guide stays inside a container of several
views, and baselines and custom guides travel, as SwiftUI's do. "Requiring extra code (that SwiftUI doesn't) to
suppress some guides, or otherwise disambiguate them, is not a good idea" — which rules out (b), whose way to keep a
guide local is an extra modifier SwiftUI code never has. The averaging of edge guides (`VStack(.center) { G (leading 5);
S (leading 1) }` centring the row at 4) goes. Lane owed, after B19's A/B.

*`VStack`, `HStack`, `ZStack` reporting their children's guides
(`StackGuidePropagation.swift`, `_HStackCore`/`_ZStackCore.explicitGuide`)*

Measured (`Tools/SwiftUIProbes/Alignment guides/guide3.out`, `guide4.out`, `guide6.out`), an inner
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

**2026-10-12: awaiting your choice between (a) and (b) below.** You asked for
no special exceptions: uniform behaviour. Measured since (session notes
`GUIDE2/notes.md` §2), SwiftUI's rule depends on the guide's **kind**, so no
rule here is free of exceptions:

- **Edge and centre guides** (`.leading`, `.center`, `.trailing`, `.top`,
  vertical `.center`, `.bottom`) never leave a container that arranges several
  views: `VStack`, `HStack`, `ZStack`, `AnyLayout`, a custom `Layout`, a
  `ForEach` of one row and a false `if`, with three views, beside a `Spacer`,
  with two children setting the guide, and with the stack aligned on the same
  guide.
- **Custom guides and text baselines do leave**: custom guides measured out of
  `VStack`, `HStack`, `ZStack`, `VStackLayout`, `AnyLayout` and a custom
  `Layout`, merged by their mean; baselines out of `VStack`, merged by the
  minimum (`firstTextBaseline`) and the maximum (`lastTextBaseline`), as
  `combineExplicit` already merges them.
- **Lazy stacks and a `ScrollView`** report nothing, not even a custom guide.
- **Single-child modifiers and an app's view type** pass every guide.
- **One oddity:** a container whose content is statically one view lets an edge
  guide through (`VStack { G }`), but not through a `ForEach` of one, an `if`
  or `AnyLayout`. It looks like an implementation shortcut (hypothesis).

TUIkit today reports edge guides out of eager stacks of several views, merged
by the mean, which gives odd results: `VStack(alignment: .center) { G (leading
5); S (leading 1) }` puts the outer row's guide at column 4, where no child
aligned (SwiftUI: 0). Its `Layout`s count the baselines as built-in guides, so
they drop a baseline SwiftUI's `VStack` reports. Custom guides already match
SwiftUI in every container measured.

- **(a) SwiftUI's rule, by kind.** A container places its own children by an
  edge or centre guide and reports none; baselines and custom guides travel.
  To align across containers by an edge, a developer declares a custom
  `AlignmentID` (about five lines). SwiftUI code keeps its layout.
- **(b) Uniform.** Every eager container reports every explicit guide, merged
  as today. To keep one local, a developer adds
  `.alignmentGuide(.leading) { _ in 0 }` on the inner container, which answers
  its own key before asking its content. SwiftUI code written for local guides
  lays out differently, with no error.

Under both, lazy stacks and scroll views keep reporting nothing, and only
explicit values change. Either is about three days, after B19's fuller version
and its A/B, which must pass first. **Recommended: (a)**: SwiftUI code keeps
its layout, and a guide stays local unless the developer asks. (b) is the
literal reading of "no exceptions".

**Shipped 2026-10-18 (lane LAYOUT): (a).** A `VStack`, `HStack` or `ZStack`
of several views, and a layout's default
`explicitAlignment(of:in:proposal:subviews:cache:)`, answer no edge or centre
guide (`AlignmentGuideQuery.staysInside(contentOf:)`, `isEdgeOrCentre` on both
alignment types, which replaces `isBuiltIn`); a text baseline and a custom
guide still travel, merged by `combineExplicit`. A layout's default and
`GridLayout`'s now merge the baselines too, where they dropped them as
built-in (measured since: SwiftUI's custom `Layout`, `VStackLayout`,
`HStackLayout`, `AnyLayout`, `HStack`, `ZStack` and `Grid` all report an
explicit baseline). The static one-view case is SwiftUI's own count of the
views a type puts where it is written (`staticViewListCount`, not
`staticMemberCount`, which counts an `if`/`else` whose arms agree as one so a
loop of them stays lazy): measured, `VStack { G }`, `VStack { G;
EmptyView().padding() }`, `Group { G }`, `G.padding(0)`, `G.onAppear {}` and
a view of the app's own whose body is `G` report `G`'s leading guide, and so
do `VStackLayout`, `HStackLayout` and `ZStackLayout` around `G`
(`PassesEveryGuideOfOneView`); an `if`, an `if`/`else` (even of one view in
each arm), a view of the app's own whose body is one of those, an `AnyView`,
a custom layout around `G` and a `Grid` report none
(`Tools/SwiftUIProbes/Alignment guides/layout1.swift`). The averaging of
edge guides is gone with it: `VStack(alignment: .center) { G (leading 5); S
(leading 1) }` reports nothing, so the row beside it stays at 0, as
SwiftUI's does. The lazy stacks and scroll views still report nothing.
Deviation L4 is closed. The A/B is B19's (ran 2026-10-19, see B19 in the main decisions file): what changed here only
removes work, an edge guide's query on a container of several views
answering before it resolves the children.

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

**2026-10-12, answered: keep the safe option for now.** The case arises only
when an explicit guide pushes a view past the widest child and the region
cannot grow (a child that fills it, a fixed `.frame`, or the screen). Measured:
`GGG` sits three cells left of where its guide puts it. Changing what
containers report would take 1.5 to 2.5 weeks (estimate) and risk every
layout; drawn as an overflow layer, B-GUIDE-3's mechanism, it is about a day
more than that mechanism.

**Shipped (2026-10-12, lane GUIDE3): the overflow-layer version.** A run of
explicit guides larger than a region that cannot grow — a column a flexible
child fills, a lazy column's window, the space a `VStack`, `HStack`, `ZStack`
or lazy stack was given — keeps every guide on one line (`AlignmentGuideRun.resolve`
with `holdsChildrenInside: false`), and what hangs past the region's edge is
drawn past it through B-GUIDE-3's mechanism
(`FrameBuffer.placedHorizontallyDrawingOverhang`, its vertical twin, and the
`ZStack`'s split): under the views after the stack, cut by a scroll view
around it, off the screen where the edge is the screen's. Measured above,
`GGG` now sits at 20 with its guide on the line, drawn past a 20-wide column
(`PlacementOverflowTests`). What the stack reports is unchanged — the
proposal, not SwiftUI's 403 — so a sibling after it is placed where it always
was and draws over the overhang. A measure pass places nothing past the
region, and a stack reporting a guide out of itself reports it from where it
is drawn. Each child is padded to the region, never to the run, on a measure
pass too, so a push under the 2^20 bound does not build a line (or a column of
blank rows) that long every frame (review of the lane, 2026-10-12).

### B-GUIDE-2. One guide pushes a view at most 4,096 cells, whatever the container's extent — decided: 2^20, and a push past it reported

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
view, which are drawn already. This said a view pushed that far is past any
terminal's edge with either bound, so nothing visible differs. That is wrong
(measured 2026-10-12, below): a scroll view's canvas goes past any terminal's
edge. The constant reads no
budget, which a bound on the available extent would: a row reports its height
without reading the vertical budget (`_HStackCore.clipSizeThatFits`), and the
measure and the render would each bound the run by their own budget.

**Owner (2026-10-12): 4,096 is too low, and a cap must not hide logic
errors. Decided: raise the bound to 2^20 (1,048,576 cells) and report a push
past it as a logic error; lane owed.** The owner added (second message): an environment variable overrides the
2^20 default, as a safety net. Measured since (session notes
`GUIDE2/notes.md` §4):

- **4,096 hides real layouts.** A `ZStack(alignment: .topLeading)` that places
  items by `.alignmentGuide(.top) { _ in -row }` in a vertical `ScrollView` (a
  day or timeline view) puts every item past row 4,096 on row 4,096, and the
  content is 4,097 rows tall instead of 10,001; SwiftUI honours 10,000 and
  100,000 rows. A horizontal `ScrollView` stops a view at column 4,096 the same
  way.
- **A guide of 1e300 or NaN is always a bug.** SwiftUI places 1e300 without a
  word, losing the view's width to rounding, and crashes on +∞ and NaN ("view
  origin is invalid") in every placement tried.
- **No cap is worse than a cap.** Without one, a 1e300 guide traps on
  arithmetic overflow while the render sizes a line (measured, and Swift
  checks overflow in release too), and a push of 1e7 to 1e12 builds a line of
  that many spaces per pushed row every frame. Neither names the guide.

**The lane:** the bound becomes 2^20, 256 times today's (about twelve times a
seconds-per-row day; a legitimate push of a million takes four measures on the
ladder instead of one). A push past it, and a non-finite guide on a view
whose width and height are both non-zero, on a render pass, is reported
through `SoftTrap` (an assertion in debug, reported once in release, with a
reporter tests can replace), and the view is placed at its own origin, not at
the bound, so a release build never builds a million-cell buffer on a bug
path. A zero-sized view keeps its silent fallback, because a small terminal
can squeeze a row to zero and make a `d.width / d.height` guide infinite.
Four tests in `AlignmentGuideTests` change with it.

**The fuller version** would hold no bound at all on a guide that lies within
`Int`, so a view could be pushed past 4,096 cells into a scroll view's canvas.
**Price:** a buffer as wide as the guide asks, per row, and a stack asked its
ideal width under a runaway guide climbing the ladder toward `Int.max` instead
of stopping at its second rung. And a view pushed past the bound that reports
its guide up through its stack reports it from where it was placed, not from
where SwiftUI would place it — visible only through two explicit guides more
than 4,096 cells apart.

**Shipped (2026-10-12, lane GUIDE3), as decided.** `AlignmentGuideRun.maximumPush`
is 2^20 (1,048,576) cells, read once from `TUIKIT_MAX_ALIGNMENT_PUSH` when that
holds a whole number of cells, held to 2^30 so a pushed run's extent still fits
a 32-bit `Int` (WebAssembly). A push is how far one guide falls short of the
largest, so the furthest push is the spread of the run's guides; past the
bound, the guide furthest from its own view's origin is taken as the runaway
(`1e300` beside a `0`, `-1e300` beside a canvas row's `-3`), reported, and
taken as that origin, one guide at a time until the spread fits — so a
legitimate row beside a runaway keeps its place. A guide that is not a number
is reported where its view's width and height are both non-zero, on a render
pass only (`checkedGuide`): a measure pass proposes sizes SwiftUI never does,
and works out the same placement silently. Both reports go through `SoftTrap`
by way of `AlignmentGuideRun.reportGuideError`, whose task-local
`guideErrorReporter` is the injectable reporter a render-path test binds. The
canvas measured above now measures 10,001 rows and draws its item on row
10,000 (`AlignmentGuideTests` "A push under the bound is honoured…"). Without
the old per-child cap, a runaway guide's view is no longer placed at the bound,
so the reported guide question in the fuller version above does not arise.

### B-GUIDE-3. One child whose guide would put it outside its region is held inside it

**Owner, 2026-10-12 (second message):** "Try to support it. If you run into significant issues, let me know and we'll discuss."
Lane owed: generalise `scrollClipDisabled`'s overflow layers so a single child, a guide placement, fixed-size content
and a move/offset bounce can draw past their region in SwiftUI's stacking order, while lists, tables, menus, sheets and
scroll views keep clipping (session notes `GUIDE2/notes.md` §5).

*`.frame(width:height:alignment:)`, `.overlay(alignment:content:)`,
`.background(alignment:content:)` — `horizontalGuidePlacement`,
`verticalGuidePlacement`*

Measured (`Tools/SwiftUIProbes/Alignment guides/guide2.out`, `guide5.out`): SwiftUI places a single
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

**Asked 2026-10-12: build the overflow layers?** You dislike forced clipping
(a bouncing scale-in, say), and asked to explore SwiftUI's unclipped
placement. SwiftUI does not clip a view to its frame by default (measured for
frame, overlay, background, offset and scale; scroll views and the clipping
modifiers do clip). TUIkit clips every view to the space it was given, as a
safety net, but `scrollClipDisabled`'s overflow layers already draw past a
region in SwiftUI's stacking order, painting only the cells they draw, with
their hit regions travelling with them. Generalised to the placement sites,
they would fix this entry, B-GUIDE-1's overhang, a badge on a corner
overwriting its label, fixed-size content larger than its frame, and `.move`
and `.offset` bounces drawing over every sibling instead of in order. A cell
has no transparency, so overflow hides what is under it completely: lists,
tables, menus, sheets and scroll views keep clipping. The bouncing scale-in
is a different limit: `.scale` uncovers a view a cell at a time, and past 100%
there is nothing more to show. About three to four days.

**Shipped (2026-10-12, lane GUIDE3).** `scrollClipDisabled`'s overflow layers
are now the one mechanism for content drawn past its region
(`FrameBuffer.splitPlacing(at:inWidth:height:)`, `OverlayLayer.isOverflow`).
A single child that its guide places outside its `.frame`, `.overlay` or
`.background` sits where SwiftUI puts it (`AlignmentGuideRun.place`, bounded
as a run's push is): the part the region holds is drawn in it, the rest past
it, over the views before it and under the views after it, clicked where it
is drawn. The badge measured above draws `3` a row above `Inbox` and a column
right of it; a 4-wide view in a 4-wide frame whose leading guide is 3 sits 3
cells left of the frame, over the view before it (`PlacementOverflowTests`,
and `AlignmentGuideContainerParityTests` now expects SwiftUI's positions, past
the region, for every row). A `.move` or `.offset` transition's overshoot is
drawn the same way, so it no longer bounces over the views after it, and its
hit regions travel with it (`TransitionOvershootTests`). A view that fits its
region pays one static check and four comparisons; a measure pass draws
nothing past the region and sizes as before. A scroll view, `.clipped()`, a
`List`, a `Table`'s cell and a surface (a menu, a sheet) cut these layers at
their box (decisions-GUIDE3 B-GUIDE3-3). Not shipped: content larger than its
frame or base (B-GUIDE3-1: `.fixedSize()` does not make a `Text` rigid
here), and `.offset`/`.position`, which still float over every sibling
(B-GUIDE3-4).
