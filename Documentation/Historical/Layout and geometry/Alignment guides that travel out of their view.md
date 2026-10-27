# Alignment guides that travel out of their view

*How an `.alignmentGuide` set deep inside a view reaches the stack that aligns
on it: through containers, modifiers, an app's own view types, lazy stacks,
`AnyView` and `Grid`, and how far one guide may push a view. Ids: B19,
A-GUIDE-1, A-GUIDE-2, B-GUIDE-2, B-GUIDE3-2, B-LAYOUT-1 to 4,
B-LAYOUTPERF-1, B-D1S-7; deviations L3, L4 (closed), L11, L13; SA-L11.*

## In short

A guide travels as SwiftUI's does: through stacks, padding, frames, offsets,
overlays and every size-neutral wrapper, out of an app's own view types (B19),
and out of a container of several views only if it is a text baseline or a
custom guide, never an edge or centre guide (A-GUIDE-2, SwiftUI's rule by
kind). Where TUI goes further than SwiftUI, deliberately: lazy stacks honour a
guide on their rows (A-GUIDE-1, L3), and a border moves a guide by its ring
(L11). A guide may push a view up to 2^20 cells; a push past that, or a guide
that is not a number, is reported as a logic error (L13).

## The problem

TUI's first guides stopped at the first boundary: a guide inside `struct
Row: View` did not reach the column of rows, so the decimal-point alignment
that SwiftUI code writes as a matter of course did nothing. A guide outside its
own view was clamped to that view's size, edge guides out of a stack of
several views were averaged into a position no child had, and one runaway guide
(`1e300`) asked for a line `Int.max` cells wide.

## How it unfolded

1. **2026-10-11 to 12, lane GUIDE.** Two parity bugs fixed (a guide clamped to
   its own view; a trailing run shifted off its guides), and SwiftUI measured
   at length with offscreen `NSHostingView`s (`Tools/SwiftUIProbes/Alignment
   guides/`). The surprises: SwiftUI's lazy stacks ignore guides altogether,
   and its stacks report a built-in guide out of a stack of several views only
   in special cases.
2. **2026-10-12, the owner.** Keep honouring guides in lazy stacks — "SwiftUI's
   ignoring them looks like a bug" (A-GUIDE-1). Follow SwiftUI's rule by kind
   for guides out of containers, because "requiring extra code (that SwiftUI
   doesn't) to suppress some guides … is not a good idea" (A-GUIDE-2). Raise
   the push bound from 4,096 to 2^20 and report a push past it, with an
   environment variable as a safety net (B-GUIDE-2). Explore the cost of B19's
   fuller version (guides out of an app's view types).
3. **2026-10-12, lane GUIDE3** built the bound and its reporting (B-GUIDE-2,
   B-GUIDE3-2).
4. **2026-10-18, lane LAYOUT** shipped B19's fuller version, A-GUIDE-2's rule
   by kind, guides through every single-child wrapper, and the costs and
   remaining differences B-LAYOUT-1 to 4 record.
5. **2026-10-19.** B19's A/B met the owner's 1% rule (`deep` −3.9%,
   `kitchensink` −1.5%); lane LAYOUTPERF won back what LAYOUT had cost
   elsewhere (B-LAYOUTPERF-1).

## Where it stands

Shipped. What differs from SwiftUI is deliberate and recorded: lazy stacks
honour guides (L3); a border moves a guide by its ring, and a `.toolbar`, a
list row's insets or background, and an app's own `BufferModifier` stop one
(L11); an `AnyView` passes none out of itself, and a `Grid` reports none
(B-LAYOUT-2, B-LAYOUT-4).

## For a future reader

- **A guide on a lazy stack's row costs the stack its window**: every row is
  built and measured each frame, unmeasured on a big list (A-GUIDE-1). Only
  an app that puts one there pays.
- **SwiftUI's lazy stacks may start honouring guides** in a later release; if
  they do, L3 stops being a deviation and nothing needs changing.
- **The fuller versions are each small and unasked for**: a `Grid` answering
  guides from its lattice (two hours), an `AnyView` opened dynamically (half a
  day plus an A/B), a memoised loop row still answering its guide (half a
  day), `BufferModifier` stating its insets (half a day), a cached "no member
  carries a guide" for loops over subviews (half a day).
- **An A/B is owed** for B-LAYOUT-8's witness reads alongside B19's arms; B19's
  three-arm plan ran as two.

## The record

### B19. A guide travels out of a view type of the app's own

*`View.alignmentGuide(_:computeValue:)`, `Layout.explicitAlignment(of:in:proposal:subviews:cache:)`*

SwiftUI resolves a guide recursively through everything between it and the
container aligning on it. TUI now does the same through `VStack`,
`HStack`, `ZStack`, `.padding` (each moving the guide by where it put its
content) and a custom `Layout` (`explicitAlignment`), which closes the gap the
compatibility notes recorded: `.alignmentGuide(.decimalPoint)` on a `Text`
inside each row of a column aligns the rows on the point.

It stops at a view type of the app's own: a guide inside
`struct Row: View`'s `body` does not travel out of `Row`. A container decides
whether to ask a child about guides from a static witness
(`View._providesAlignmentGuide`), which the framework's containers now
forward from their content; an app's view states none, so it is not asked. It
also stops at any modifier that does not translate guides (`.border()`,
`.frame`, `.offset`): there a wrong position is the alternative.

**The fuller version** makes every composite view forward its `body`'s
witness by default (`Body._providesAlignmentGuide`, `false` for a `Never`
body), so the question reaches into every body type. The cost is where the
witness is read: `ChildView` construction, per child per walk, would recurse
through the child's whole static body type, not only the framework containers
in it. That is O(static subtree) per construction, which the per-pass measure
memo keeps to roughly O(nodes × depth) witness calls a frame — small on paper,
and exactly the kind of thing that has measured as a percent on `fanout` and
`deep` before. Half a day, plus an A/B on `deep`, `kitchensink`, `megalist`
and `table` on a quiet machine before it ships.

**For the first version, which shipped before the fuller one (the A/B below
prices the fuller one against the batch before it).** The witness then forwarded through `TupleView`,
`Group`, `ForEach`, `ConditionalView`, `Optional`, the three eager stacks and
padding, so constructing a `ChildView` for a container child ORs its
framework subtree's witnesses instead of reading one constant. A tree with no
guide still pays one stored `Bool` per child at layout time, as before; the
added cost is in the construction, and it was not measured separately (no benchmarks on
a shared machine). `deep` and `kitchensink`, the structure-heavy scenarios,
are the ones to A/B. One more: an app's own `Layout` cannot be known not to
override `explicitAlignment`, so inside a stack it is laid out once more per
walk to answer the stack's guide question (the framework's layouts state
`_definesExplicitAlignment = false` and are asked only when a subview may
hold a guide). Stress's `customlayout` scenario is the one to A/B for that.

**Decided 2026-10-12: explore the cost**, of the current version against the
fuller one at least. (You asked for my recommendation on 2026-10-04; on
2026-10-05 I recommended the fuller version, gated on an A/B, because a guide
inside an app's own row view, decimal alignment say, is how SwiftUI code is
commonly written; if `deep` or `kitchensink` cost more than about 1%, it comes
back to you before landing.) **Lane owed** (shipped 2026-10-18, below), about a day (estimate, more than
the half day above): the witness defaults to `Body._providesAlignmentGuide`
with `false` for `Never`, and stops where a body holds its own type, since
`Optional` and the conditional view forward and a recursive body would
recurse (an if/else in both arms would be 2ⁿ); `_handsOverChildren` already
defaults to its body's this way. Tests for recursive and if/else bodies. The
A/B can price all three versions on today's tree: a forwarding-off arm, where
the containers' witnesses return `false` and the modifier's stays `true`,
stands in for the original, which is 1,357 commits back. Scenarios: `deep`,
`kitchensink`, `table`, `customlayout`, `fanout`, `anyview`, and `megalist`
only where its verdict reproduces at more than one path layout. A-GUIDE-2
needs the fuller version whichever way it is answered.

**Shipped 2026-10-18 (lane LAYOUT): the fuller version.** The witness's
default is the body's answer (`false` for a `Never` body or a view drawn
procedurally), so a guide inside `struct Row: View`'s body travels out of
`Row` as SwiftUI's does, and through an `if`, an `if`/`else` or a `switch`
there (`ConditionalView` and `Optional` answer the guide query with their
live view). The question cannot be left to the type system, since the
providers forward it and a body that holds its own type would ask itself for
ever: `BodyWitnessMemo` asks each type's body once, cuts the question where it
comes back round (a type met again while its own body is asked adds nothing
to an OR), keeps an answer only where it is exact (Tarjan's rule: a `false`
worked out under a type still open further out is asked again on its own),
and serves the kept answer from a direct-mapped table of 512 entries indexed
by the type's metadata address, with a dictionary behind it. So building a
child of a composite type costs one shift, mask and comparison per witness
read where it cost a constant, and the walk of a body's type is made once
per process, not per child per walk. Tests: `AppViewGuideTests` (a view whose
body holds its own type with and without a guide, one with itself in both
arms of an `if`/`else`, asked once, and two types whose bodies hold each
other, asked in the order that would keep a wrong `false`).

Two costs fall only on apps with a guide inside a view type of their own: a
`ForEach` whose row type holds one forfeits its row memo (`ForEach.makeChild`,
as for a row that sets a guide itself), and a stack around such a view asks
it for its guide, evaluating its body in a measure.

**A/B, 2026-10-19** (the batch before this commit against it, 15 reps, a busy
box with a load of 26, so indicative; the checksums were identical). `deep`
−3.9% warm and −4.7% cold, `kitchensink` −1.5% warm and +0.7% cold, so the rule
above (about 1% on either) was met and it landed. Slower elsewhere, within
tolerance: `stateful` +3.6% warm, `customlayout` +2.6% warm and +2.0% cold,
`alpharamp` +1.3%, `fanout` +0.8%, cold `menus` +1.2%, `churn` +1.0%. The plan
had three arms (the containers' witnesses off, the batch, this commit); only
the last two ran.

### A-GUIDE-1. SwiftUI's lazy stacks ignore an explicit alignment guide; TUI's honour it — decided: keep honouring it

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

TUI's lazy stacks honour it, by design: `AlignmentGuideModifierTests`
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
   Price: a SwiftUI app moved to TUI lays out differently in a lazy stack
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
unmeasured beyond these rows, and the text baselines not at all). TUI reports both, merged by the mean
(`combineExplicit`), so its layout differs from SwiftUI's in the rows above.

**Options.**
1. *Match SwiftUI*: measure the rule fully first (`.trailing`, `.bottom`, the
   baselines, three views, a stack with spacers), then answer `nil` from a
   multi-view stack for the built-in guides it does not report. Price: a probe
   lane and a change to `combineExplicit`'s callers; layouts that relied on
   TUI's merge move.
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

TUI today reports edge guides out of eager stacks of several views, merged
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
which TUI already takes as more than any real bound offers
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

### B-GUIDE3-2. Which guide a push past the bound blames, and how far the variable may raise the bound

*`AlignmentGuideRun.maximumPush`, `TUIKIT_MAX_ALIGNMENT_PUSH`*

A push is the gap between two guides, so a push past 2^20 does not say which
of the two is wrong. The owner's ruling places "such a view at its own
origin". The lane takes the guide furthest from its own view's origin as the
runaway and takes it as that origin, one guide at a time until the run's
spread fits: `1e300` beside a `0`, and `-1e300` beside a canvas row at `-3`,
which keeps its place (`AlignmentGuideTests` "A push past the bound is
reported…"). The run is reported once, and its guides are sorted once rather
than rescanned for each runaway, which cost a canvas of 20,000 rows with a
unit mix-up about 10^9 comparisons a resolve ("A run with many runaways…").
A single child in a frame, overlay or background is bounded
the same way against the region's guide; a region guide that is itself a
runaway (a custom `AlignmentID`) is held to the bound.

The environment variable takes a whole number of cells from 1 up and is held
to 2^30: a pushed run is drawn as lines that long, and its extent plus a
view's size has to fit an `Int` where `Int` is 32 bits (WebAssembly). Anything
else (0, a negative number, text, `1e9`) leaves 2^20.

**The fuller version** would name the guide in the report (which view, which
key). The report has no view to name: a guide is a closure, and the run sees
only its values. Recording the call site of each `.alignmentGuide` (a
`#fileID`/`#line` default argument, as `SoftTrap.report` takes) would do it,
at the cost of two stored words in every guide wrapper. About half a day
(estimate); not done, since the debug build's assertion already stops in the
stack that placed the run.

### B-LAYOUT-1. A row type of the app's own that holds a guide forfeits a loop's row memo

*`View.alignmentGuide(_:computeValue:)`, `ForEach`, decisions B19*

Since B19 a view of the app's own answers `_providesAlignmentGuide` with its
body's answer, so a guide anywhere in `struct Row: View`'s body is a guide of
`Row`. Two places read that answer as a reason to do more work, and both now
do it for such a row type where they did not before:

- **A `ForEach` keeps no row memo for a row type that may hold a guide**
  (`ForEach.makeChild`): the memo wrapper is opaque, and a guide inside it
  would not reach the stack. Before B19 that was only a row that set a guide
  itself; now it is any row type whose body holds one, even one that a stack
  inside the row keeps to itself (an edge guide of a stack of several views,
  A-GUIDE-2), because the static question cannot tell the guide's kind.
- **A lazy stack gives up its window over such rows** (`StackUniformWindow`,
  `StackAnchoredWindow`): placing a row by its guide needs the whole run, so
  every row is built and measured on every walk, as it was before B19 for a
  row that set a guide itself. Only a row type that may report a guide of
  the kind the stack aligns on does: a stack of several views keeps its edge
  and centre guides (A-GUIDE-2), and the type says whether one can leave it
  (`mayReportEdgeOrCentreGuide(_:)`, kept per type). This entry recorded only
  the memo until the review, which found a row type holding an edge guide
  inside an `HStack` of two views costing a `LazyVStack` of 3,000 rows
  18,011 body evaluations to draw ten; it keeps its window again.
- **A stack around such a view asks it for its guide**, evaluating its body in
  a measure, where it answered nothing before — for an edge or centre guide
  only where the type says one can leave it, so a view whose guides all sit
  inside a stack of several views is not evaluated to ask.

Apps with no guide inside a view type of their own pay one table read per
child of a composite type (`BodyWitnessMemo`), where they read a constant.

**The fuller version** keeps the memo: `_MemoizedRow` forwards the guide
witness and answers the guide query by building its row, so a memoised row
is still asked for its guide (only on a stack that aligns on one, and only
rows whose type may hold one). About half a day, plus the A/B below, since it
puts a query on the memo's hit path for such rows.

**A/B (B19's three arms; ran 2026-10-19 as two, the base before B19 and B19):**
the off arm (the patch in the lane's notes, `LAYOUT/b19-off-arm.patch`) was not
run. `deep` and `kitchensink` were within the rule (over about 1% on either it
goes back to the owner); the numbers are under B19 in
[the main decisions file](#b19-a-guide-travels-out-of-a-view-type-of-the-apps-own).

### B-LAYOUT-2. An `AnyView` passes no guide out of itself

*`AnyView`, `View.alignmentGuide(_:computeValue:)`*

Measured: SwiftUI's `AnyView(G)`, as a stack's child, reports `G`'s leading
guide (C at 5), and `VStack { AnyView(G) }` reports none, an `AnyView`'s
count being unknown from its type (A-GUIDE-2). TUI's `AnyView` reports
none in either case: its static witness cannot say what it erases, and
answering "may" for every `AnyView` would put every loop of erased rows off
its row memo and every stack holding one on the guide path. The second case
matches; the first does not.

**The fuller version:** a container building a child that is an `AnyView`
asks the erased view's witness dynamically (one existential open per
`AnyView` child per walk), and an `AnyView` answers the guide query by
opening its view. That reaches a guide in an `AnyView` that is a stack's own
child; one further in (an `AnyView` inside a `VStack` inside the stack)
still needs the static "may", with the costs above. About half a day for the
first part, plus an A/B on `anyview` and `kitchensink`.

### B-LAYOUT-3. A border moves a guide by its ring, and a few wrappers stop one

*`.border(_:style:width:)`, `.toolbar`, `listRowInsets`,
`listRowBackground`, `BufferModifier`; deviations L11*

A guide now passes every single-child modifier written after it, as SwiftUI's
does: `.padding`, `.frame` and `.position` move it by where they put their
content, `.offset` passes it from the layout's place, `.overlay` and
`.background` pass their base's (measured, `layout1.out` case B), and the
wrappers that keep their content where it is pass it unmoved. That last set
is decided by a witness for size-neutrality,
`SingleContentWrapper._keepsContentGeometry` (with `BufferModifier`'s twin),
which every `DrawsContentUnchanged` wrapper meets a fortiori; the paint
wrappers (`.opacity`, `.hidden()`, the colour effects, `.dimmed()`), drag and
spring-loading regions, `.help`, `.fixedSize()` and a transition state it
themselves. Such a wrapper's content is asked for its guide in the context the
wrapper lays it out in (`SingleContentWrapper.wrappedContentContext(_:)`, the
one its measure hands its content), and a wrapper that has not said what that
is stops the guide. Asked in the wrapper's own context, the content answered
from a layout that is never drawn wherever the wrapper's environment changes
what it lays out: `HStack { Text("ßß"); Text("x").alignmentGuide(.mark) {
$0[.leading] } }.textCase(.uppercase)` placed the guide two cells in, where
the drawn row is `SSSSX` (found in review).

Two differences remain:

- **`.border()` moves the guide in by its ring**, a line and a blank cell
  across and a line down per ring, where SwiftUI's border strokes inside the
  view and moves nothing (measured: 5 under `.border(_:width: 2)`). A terminal
  border takes cells round its content, so the content's guide is where the
  content is.
- **A `.toolbar`, a list row's insets, colour or background, and a
  `BufferModifier` of the app's own** stop a guide: each moves or resizes its
  content without saying by how much (a list row's colour fills the row's
  width, wider than its content), and a guide passed through unmoved would
  report the wrong position. A `.badge` passes it, as SwiftUI's does
  (measured, `Tools/SwiftUIProbes/Alignment guides/badge.out`): it publishes
  its value and lays its content out where it is, in that environment
  (`AlignmentGuideWrapperTests`). This entry listed it among the stops until
  the review found the code passing it.

**The fuller version:** a requirement on `BufferModifier` that states where
the modifier puts its content (its insets), so an app's own modifier
translates a guide as padding does, and the same for the list row styles. About
half a day for the requirement; the others an hour each, with a probe each.

### B-LAYOUT-4. A `Grid` reports no guide out of itself

*`Grid(alignment:horizontalSpacing:verticalSpacing:content:)`, `GridRow`*

Measured: SwiftUI's `Grid` reports a custom guide and a text baseline set in
a cell, and no edge guide, even from a grid of one cell (`layout1.out` case
C). TUI's `Grid` forwards the static witness but answers no guide query,
so it reports none of any kind; `GridLayout`, the same grid as a `Layout`,
reports custom guides and baselines through the layout's default.

**The fuller version:** the grid answers the query from its lattice: each
cell's guide moved by where the grid placed the cell, merged by the guide's
rule, edge guides never. About two hours with tests.

### B-LAYOUTPERF-1. A layout's default guide answer is learnt from its first query

*`Layout.explicitAlignment(of:in:proposal:subviews:cache:)`,
`Layout._definesExplicitAlignment`, `AnyLayout`; decisions B-LAYOUT-3*

Shipped: the default `explicitAlignment` records the type it runs for, per
axis (`LayoutDefaultGuides`), and a layout of that type is asked as one that
defines no guide of its own from then on, so a stack aligning on an edge or
the centre answers it `nil` without the layout pass. Since a guide passes a
border, `customlayout` (`VStack(alignment: .leading) { …; AnyLayout(Flow())
{ … }.border() }`) laid its `Flow` out twice a frame for that answer: 6.3% of
the frame, now 0.1%, and its measure-memo lookups are main's again (127 a
frame, from 207).

What is left is the walk down to the record: the stack asks the bordered
child, which builds a context and two identities through its ring to reach
the layout — 0.6% of `customlayout`. The first query of each layout type
still makes the pass, since Swift cannot tell whether a conformance
implements a requirement.

**The fuller version:** an instance-level "may this report an edge guide?"
for the views on that path (the border's ring, `ContainerView`, `AnyView`,
`_LayoutCore`), asked before any context is built. About half a day, plus an
A/B on `customlayout` and `anyview`, since it adds a cast to every guide
query that reaches a view of those kinds.

### B-D1S-7. A stack around a loop over subviews asks it for guides it may not have

*`ForEach(subviews:content:)`, `Group(subviews:transform:)`, `Subview`,
`HStack`, `VStack`, `ZStack`, `Layout`*

A proxy lays out as its member (B17), and a member may carry an alignment
guide; `Subview` is one type for every member, so its static witness
(`_providesAlignmentGuide`) says it MAY, and every container type holding a
proxy says so too, up the tree. A `ChildView` built for a proxy asks the
instance and is exact, so the container placing the proxies pays nothing; the
containers AROUND it cannot ask without resolving it. So an aligning stack
with such a container among its children — `HStack { VStack {
ForEach(subviews: content) { $0 } }; Text("x") }` — asks it for its guide on
each of its passes (its measure and its render, and each enclosing stack asks
its own child the same way, up the chain). What that costs, when no member
carries a guide:

- **A stack** (`VStack`, `HStack`, `ZStack`) resolves its children to answer
  and stops there: the loop's members — the content they come from resolved
  again, a proxy built for each — then `nil`. A walk over the members per
  question, not a layout.
- **A built-in `Layout`** (`HStackLayout`, `VStackLayout`, `ZStackLayout`,
  the lazy grids, `GridLayout`) did a whole layout pass per question; it now
  resolves its subviews and answers `nil` when none carries a guide, as a
  stack does.
- **A `Layout` of the app's own** does the pass whatever its subviews hold,
  as it always has: whether its `explicitAlignment` is the default cannot be
  told from its type (`_definesExplicitAlignment` is `true` for it).

**The fuller version.** The answer cached per pass where the members are
resolved — "no member of this loop carries a guide", kept by the loop's
identity in the render cache's per-pass store — and consulted by a container's
guide question before it resolves anything, so the question costs a lookup.
Half a day, with an A/B on `deep` and `kitchensink` shaped with such loops.

### Measured, nothing to take back

- **`megalist`:** re-profiled with 15 s traces of both binaries, no symbol of
  LAYOUT's above 0.1%; `evaluateCompositeBody` is 1.4% in both (the 0 → 1.7%
  in the first trace pair came from a main trace of 931 ms of samples). Its
  memo counts are the same.
- **`kitchensink`:** no single symbol stands out, before or after; the
  witness getters (`_providesAlignmentGuide` through `BodyWitnessMemo`) cost
  about 0.1–0.2% more than main's constant. B-LAYOUTPERF-3's writes are what
  this lane took from it.

**A/B** (the coordinator's, owed on a quiet machine): main against the head ran
on 2026-10-19 with LAYOUT's, a busy machine (load 26), indicative; see B19 in
[the main decisions file](#b19-a-guide-travels-out-of-a-view-type-of-the-apps-own).
The base (3a331fd3b) against the head was not run on its own. Scenarios:
`customlayout`, `framedcolumns`, `geometry`, `megalist`, `kitchensink`, `deep`,
`table`, `stateful`, `churn`, `anyview`, `fanout`.
