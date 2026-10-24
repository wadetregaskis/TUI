# Completing the SwiftUI API: decisions from lane CHURN

*Lane CHURN, 2026-10-18: the scrollbar's first round asks an eager column only
WHETHER it is taller than the viewport, and the column stops measuring a line
past it (`RenderContext.asksOverflow`, `StackOverflowProbe.swift`). It changed
no public API and no frame. This file holds the judgement calls the work
reached, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-CHURN-n — needs your decision.** Nothing has shipped for these.
- **B-CHURN-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-CHURN-n — declined.** With the reason.

## A. Your decisions

### A-CHURN-1. Presume last frame's scrollbar (hysteresis)

*`ScrollView` with `.automatic` indicators — performance, and what a frame shows*

The first round has to be exact because a bar takes a column: wrapping
content can fit at the full width W and overflow at W−1, so whether it gets a
bar depends on asking at W. Hysteresis would skip that question while the
view had a bar last frame, keeping it as long as the content still overflows
at W−1 (which round 2 measures anyway), and drop it only when the content
fits there.

- **As now (recommended):** round 1 is asked every frame the content
  overflowed last; for an eager column it now costs a screenful of rows, not
  the whole column.
- **Hysteresis:** round 1 costs nothing on those frames. Price: a frame then
  depends on the view's history as well as its state — content that fits at
  W but not at W−1 keeps a bar it would not get drawn fresh, and a resize
  across that width shows a bar or not depending on which way it came. The
  memo verifiers and the selfcheck compare a frame against a fresh render, so
  they would need an exemption for it.

### A-CHURN-2. Overlay scrollbars that take no column

**Re-checked 2026-10-18 (evening):** this would reverse two standing rules. Deliberate deviations R5 says a bar is a column of the viewport (kept on 10-12 under B24), and R4 says `ScrollGeometry` leaves the bars out (owner: keep, 10-12). It isn't needed for performance now, since with the early stop round 1 is a screenful. Suggested: keep R4 and R5 and decline this, unless you want macOS's overlay look for its own sake.

*`ScrollView` — a design change*

A bar drawn over the content's last column (as macOS's overlay scrollers sit
over content) would make the two rounds one: the content is laid out at W
whether or not it overflows, so the overflow answer and the scroll range come
from one measure. Price: the bar covers a column of content (or the content
leaves that column blank on every scroll view, overflowing or not), which is
a visual choice and a parity question this lane does not decide. Not needed
for performance now: with the early stop round 1 is a screenful.

## B. Shipped

### B-CHURN-1. Only a `VStack`, or the app's own views over one, is asked with the mark

*The scroll view's first round — performance only*

A stopped column's height is exact (the budget, which is what the whole
column reports there), but its width and flexibility are only its measured
rows'. Anything between the probe and the column that reads those could turn
them into a wrong answer: `fixedSize` proposes the column its ideal width
back, a row hands its children the width the others leave, `ViewThatFits`
picks by width — and a narrower width can pick a layout that is TALLER, a
yes for content that fits. A view of the app's own measures as its body
does and nothing else, so the mark goes to content whose TYPE is a `VStack`
or such views over one (`measuresAsEagerColumn`), and nowhere else.

**The fuller version:** also through the single-child modifiers whose height
reads only the child's height (`.padding`, `.background`, `.border`, the
environment modifiers). Price: each needs an audit and a marker conformance,
and a later change that makes one re-measure at its child's width would turn
a stopped width into a wrong yes with nothing to catch it but the agreement
tests; or the mark cleared centrally in `measureResolved` for every
`Layoutable` not on a list, a branch on the path every measured view takes
(a guard on that path measured +1.5% on `modifiers` once). The Stress
scenarios with an eager column in a scroll view are all the bare shape.

### B-CHURN-2. A column nested in the column is measured whole

*The scroll view's first round — performance only*

The column clears the mark for its rows, so `VStack { header; VStack { rows } }`
measures the inner column whole (the outer one then stops after it).

**The fuller version:** a row that is itself an eager column, by its type,
asked with the mark at the SAME budget as the outer one. Exact, since a
column measures each row at one proposal whatever the others answer, and a
stopped inner column reports the budget, which stops the outer one too. Not
the REMAINING budget: the rows of a column under the mark are owed the
ladder's first rung for the height asked about, derived from the budget, and
a smaller budget would change what they are asked. Price: `ChildView` holds
its view as `any View` and would have to expose its type for the walk; one
dynamic cast per row of a marked column.

### B-CHURN-3. Content seen walking a nested lazy stack is asked as before

`oneLinePast` asks the rows of such content one line past the viewport on
purpose, so each nested lazy stack stops a screenful in. Under the mark the
column asks its rows the ladder's first rung, which would undo that; such
content keeps its unmarked ask.

### B-CHURN-4. The overflow mark takes bit 6 of the measure generation

*Every measure — the measure memos' keys*

The mark has to be in both measure keys, and `RenderContext.measureGeneration`
is the one field already in both; the context's 104-byte stride has no
padding left for a byte of its own. So a generation is six bits now, not
seven. What that costs, all of it stale serves of a class that was there
before (a keyed bump of key 0 already steps by one, and lands where a
menu's plain bump does):

- a wrap after 64 plain bumps on one path rather than 128 — nothing nests
  near either;
- the keyed bump (a text-style pager's content-margins probe, keyed by its
  height) has 63 generations rather than 64, so two heights 63 apart share
  one;
- a keyed step of 64 − n with n plain bumps beneath it (a menu's, in the
  pager's content) comes back round to the generation it started from —
  probe heights of 62 modulo 63 with one bump, 61 with two — and so does a
  keyed bump nested in another whose keys sum to 62 modulo 63. At seven bits
  neither happened short of 64 plain bumps, or two keys of 63 modulo 64. It
  takes a pager probed at such a height, in a window some sixty lines tall
  or more, with a menu in its content.

**The fuller version:** the seventh bit back, from a second byte:
`measureGeneration` widened to sixteen bits, with room made by narrowing
`environmentApplicationDepth`, a public `Int`, to 32 bits, and both keys'
generation widened to match (`SizeKey` has the padding; `MeasureKey` folds
it into its hash). Price: a public field's type changes, every place that
stores or compares a generation changes with it, the layout pins move, and
every context copy's code changes, so it is owed an A/B on `anyview` and
`modifiers` (an `Int` field cost those +2.4% and +1.4% once). **Or** keyed
steps kept short of the top — the key modulo 63 − k — so that no k plain
bumps beneath one wrap, for k fewer keyed generations.

## C. Declined

### C-CHURN-1. Reusing round 1's walk for round 2 when no row's height depends on the width

Round 2 measures at W−1, round 1 at W; for rows whose height does not depend
on the width the two walks give the same heights. Declined: not provable in
general — a `Text` exactly W wide wraps at W−1, and knowing that a row's
height ignores its width takes either a second measure (what it would save)
or a new claim on every view's `sizeThatFits`, which any app `Layout` could
get wrong. With the early stop round 1 is a screenful, which is all the reuse
could still save. No API is involved, so there is no parity-map entry.

### C-CHURN-2. An `HStack` mirror for a horizontal probe

There is no horizontal overflow probe to answer: a view that scrolls
horizontally skips round 1's shortcut, because its horizontal bar reads the
round's measured WIDTH (`resolveScrollbars`). Nothing to build.
