# Measuring a scroll view's content: the overflow check, wide rows and nested lazy stacks

*What a scroll view measures of its content each frame, and three places
where that cost or its correctness was in question: deciding whether a
scrollbar is needed, a row that grew wider while off screen, and a lazy stack
that is not the content's top. Ids: A-CHURN-1, A-CHURN-2, B-CHURN-1 to 4,
C-CHURN-1 and 2, B-SCROLL-4, B-SCROLL-5, NESTED-LAZY-PULL (design C); the
owner's Q1 ruling of 2026-09-23.*

## In short

A scroll view with `.automatic` indicators asks its content, in a first
round, only *whether* it is taller than the viewport, and an eager column
stops measuring a line past it: a screenful of rows rather than the whole
column. A row that widens while off screen is caught as it enters the drawn
band, and the frame is measured and drawn once more. A lazy stack inside
`.padding` is windowed; one below other content in a `VStack` is still drawn
whole, which is what the owner's design C, the "pull" design, would fix.

## The problem

A scrollbar takes a column, and wrapping content can fit at the full width
and overflow one column narrower, so whether a bar is needed depends on
measuring at the full width first (round 1), then laying out at the narrower
width (round 2). For an eager column that meant measuring every row twice a
frame. Separately, a lazy stack measures only the rows it draws, so a width
record can go stale, and a lazy stack nested below other content is never at
the content's origin, so it cannot window itself.

## How it unfolded

1. **2026-09-23, Q1.** The owner ruled that an extent may be an estimate but
   a drawn row is never cut (option 3: detect, stop and replan). A 14-commit
   plan was written; its core shipped later (B-SCROLL-5).
2. **2026-09-26, nested lazy stacks.** Design D (a lazy stack below other
   content drawn whole, correctly) landed, at a measured cost (grouped-feed
   +707%, +64 MB). The owner ruled: "land D first … then pursue C (the pull
   design; multi-week)". A lane brief for C was written on 2026-10-18
   (NESTEDLAZY) but the lane was never launched.
3. **2026-10-18, lane CHURN.** The early-stopping overflow probe shipped
   (`RenderContext.asksOverflow`, `StackOverflowProbe.swift`), with the
   choices B-CHURN-1 to 4, and two questions for the owner: hysteresis
   (A-CHURN-1) and overlay scrollbars (A-CHURN-2).
4. **2026-10-19, lane SCROLL.** `.padding` relays the scroll window
   (B-SCROLL-4), and rows entering a band are checked against the width record
   (B-SCROLL-5), closing the one case Q1's re-run still found cutting a row.

## Where it stands

The overflow probe, the padding relay and the band check are shipped. **Open:**
A-CHURN-1 and A-CHURN-2 were listed for the owner on 2026-10-18 and never
answered (back on the open-decisions page since 2026-10-26; the defaults —
no hysteresis, bars keep their column — hold). **Owed:** design C, which the
owner ruled for on 2026-09-26 and which never started.

## For a future reader

- **Owed, multi-week: NESTED-LAZY-PULL (design C)**, where the scroll view
  pulls only the rows it needs. It would replace B-SCROLL-4's fuller version
  (a column cutting a band of its own) and remove D's cost.
- **The measure generation is six bits now** (B-CHURN-4). The stale-serve
  cases listed there need a pager probed at a particular height, in a window
  some sixty lines tall, with a menu in its content. If such a bug is ever
  seen, the fuller version (a sixteen-bit generation) is the fix, with an A/B.
- **The overflow mark reaches only a `VStack`, or the app's own views over
  one** (B-CHURN-1). A later change that makes a view between them
  re-measure at its child's width would turn a stopped width into a wrong
  answer, with only the agreement tests to catch it.
- **An A/B is owed on two-axis scenarios** for B-SCROLL-5's band check.
- **Q1's remaining cases** (a lazy stack nested in the content, one inside a
  `.frame(width:)`, the classic paths, bars re-resolved on the replan) were
  not seen to cut a row; each is about a day if one is.

## The record

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

### B-SCROLL-4. `.padding` relays the scroll window; a lazy stack below other content is still drawn whole

*`LazyVStack` in a `ScrollView`, inside `.padding` or below a heading in a
`VStack` (the 2026-10-18 inventory's LAZY-NESTED-WINDOWING)*

**Shipped:** `.padding` around the content relays the scroll window below its
top lines and above its bottom ones (`ScrollWindowRelay`), as a `Section`'s
header and the content margins do — set up as the modifier adjusts its
content's context, answered once the content has drawn, the two passes
sharing the scroll view's reply (`ScrollContentReply.pendingRelay`). A lazy
stack under `.padding(.vertical)` used to take the window as if it were all
the content: the scroll view took the stack's height for the content's, and
End stopped short of the last row and the padding below it. Now it bands
itself, seeks and reports its row, and End reaches the end. The check is the
context's, so a padding anywhere else reads nothing more.

**The fuller version:** a lazy stack below other content — `VStack { Text("Feed");
LazyVStack { … } }` — is not at the content's origin, and is measured and
drawn over every row, as a `VStack` is. Windowing it needs the column around
it to hand it the window moved down by the rows above it, and to answer the
scroll view for a canvas that is drawn whole above and below the stack but
only as a band inside it: the reply's drawn lines (one range today) would
have to say "all of it but this stretch", or the column would have to cut a
band of its own, so that a snap or a re-glue that moves the offset after the
render draws the rows it lands on. About two days with the relay's seek,
read-back and hold paths, and a hot path (every eager column in a scroll
view asks), so an A/B with it. Lane NESTEDLAZY's design C, where the scroll
view pulls only the rows it needs, is the owner-ruled answer to the same cost
and would replace it; this lane leaves that shape to it.

### B-SCROLL-5. A row widened off screen is drawn whole when it scrolls in: rows entering the band are checked (Q1)

*A two-axis `ScrollView` over a `LazyVStack` past the full walk's threshold
(the owner's Q1 ruling of 2026-09-23: an extent may be an estimate, a drawn
row is never cut; option 3, detect, stop and replan)*

**Re-run on 2026-10-19 first.** A row widened through its data is caught now
by the width record's challenge, and the full walk under 256 rows measures
every row's slot each frame. What still cut a row: one that reads an
`@Observable` no drawn row read, widened while off screen. The write clears
nothing, the record keeps its old widest row, and scrolled in (End) the row
was drawn on the old canvas with an ellipsis — and stayed so, since nothing
asked again (`WidenedRowDrawnWholeTests`).

**Shipped:** the uniform and anchored windows measure the rows that ENTER
their band against the record as they record the band
(`_VStackCore.recordDrawnBand`), their sizes forgotten first, as the
challenge measures the widest row. One wider than the record raises it; one
past the width the record was measured at falls it, for a walk. Then the
pass's measures are dropped and the scroll view measures and draws once more,
that frame (`ScrollContentReply.measureWentStale`, the replan the uniform
window's refuted hypothesis already uses), on which no row enters. A
screenful of row measures when the band jumps, a row or three when it
scrolls, nothing when it rests, and nothing in a view that does not scroll
across, which keeps no record: an A/B is owed on two-axis scenarios.

**The fuller version** (the 14-commit plan of 2026-09-23, about 1,900 lines of
source): the same check for a lazy stack nested in the content (risers that
carry the need out through the stacks around it), for a stack inside a
`.frame(width:)` that fixes its canvas, and for the classic paths; the scroll
bars re-resolved on the replan, where today a bar the wider row brings
appears on the next frame; and a bounded replan loop for a replan that
reveals another. None of these was seen to cut a row on the base; each is
about a day.
