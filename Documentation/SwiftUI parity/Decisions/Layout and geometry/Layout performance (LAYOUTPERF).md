# Layout performance — what lane LAYOUT cost, won back (LAYOUTPERF)

*Lane LAYOUTPERF, 2026-10-19, took the regressions the coordinator's A/B of
lane LAYOUT found (`customlayout` +9.0%, `framedcolumns` +6.1%, `megalist`
+4.4%, `kitchensink` +3.2%, `geometry` +3.0%; perf/results/layout/ab.txt)
towards the base, keeping every behaviour LAYOUT shipped: 32 of 32 scenario
checksums are the same before and after, and so are the memos' counts per
frame but `customlayout`'s, which go back to main's. Each change was found and
priced with Time Profiler traces of release `Stress` binaries
(perf/profile1017.sh's recipe, 10–15 s attached); each commit quotes its
shares. The A/B is the coordinator's. Numbered as the main decisions document
is: A = owner decision, B = basic shipped, C = declined.*

## B. Shipped the safe option

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

### B-LAYOUTPERF-2. A frame, a padding, a position and a `ZStack` say by type whether they may state a spacing

*`.frame`, `.padding`, `.position`, `ZStack`, `HStack(spacing: nil)`;
decisions B-BITEMS1-3*

Shipped: each answers `mayStateSpacing(_:along:)` from its type
(`SpacingReaching`) — a frame and a padding their content's answer, a
position never, a `ZStack` any non-spacer layer's — where the generic
reading said "may" for every view that states a preference itself. A row of
framed columns (`framedcolumns`) asked each column its spacing on every
pass, evaluating its body to find the default: `StackGaps.init` 4.1% of the
frame, now 0.1%.

**The fuller version:** an answer per instance, so a frame that sets a width
is known to state nothing on its leading and trailing edges whatever its
content holds (a framed custom `Layout` beside a row's other views is still
asked). It needs the child to carry a value-level answer beside its type's;
not wanted by any scenario measured. About half a day.

### B-LAYOUTPERF-3. Overflow is cut under the lines it reaches; three environment writes are skipped where they change nothing

*`.offset`, `.position` (LAYOUT's L6), `FrameBuffer`'s combining operations;
`VStack`, `HStack`, the bordered containers, `.disabled(_:)`*

Shipped: since L6 an offset view's cells overflow, and the cut under a later
view read every line of it — in `geometry`, the whole scroll view under a
one-row offset view, every frame (3.3%; now none). The cut now reads only the
lines an overflow reaches, giving the same layers (`OverflowCoverReachTests`).

Three writers of the environment wrote a value already in force, each write
copying the whole environment dictionary: a stack publishing the container
relationship it was given (a column in a column or in a box), a box clearing
a focus indicator that is not there, and `.disabled(false)` in an enabled
subtree. Not costs LAYOUT added — taken because `deep` and `kitchensink` are
the scenarios B19's 1% rule names: `deep`'s environment copies went from
1.9% of its frame to none, and `framedcolumns`' `isEnabled` writes from 0.7%
to none.

**The fuller version:** every framework writer of the environment skips a
write that changes nothing. `kitchensink` still spends about 0.9% copying
environments, across a dozen writers of 0.1–0.2% each
(`containerRelativeSize`, `drawsListSectionChrome`, a row's container
relationship, …). A helper that writes an `Equatable` value only where it
differs, adopted writer by writer: about half a day, plus an A/B.

## Measured, nothing to take back

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
[the main decisions file](<../SwiftUI API completion decisions.md#b19-a-guide-travels-out-of-a-view-type-of-the-apps-own>).
The base (3a331fd3b) against the head was not run on its own. Scenarios:
`customlayout`, `framedcolumns`, `geometry`, `megalist`, `kitchensink`, `deep`,
`table`, `stateful`, `churn`, `anyview`, `fanout`.
