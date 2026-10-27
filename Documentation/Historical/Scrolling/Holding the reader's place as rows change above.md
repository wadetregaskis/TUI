# Holding the reader's place as rows change above

*The story of what a scroll view does with its offset when rows are inserted,
removed or resized above the row at the top of its viewport. Ids: B30,
A-SCROLLANCHOR-1, B-SCROLLANCHOR-1 to 6, C-SCROLLANCHOR-1 and 2; deviations
R11 to R14. The design itself is live, in
[Scroll anchoring.md](<../../Layout and scrolling/Scroll anchoring.md>) §5.*

## In short

With no anchor declared, a scroll view keeps the row at the top of its
viewport where it is as rows change above it: inserted, removed, or resized.
That is SwiftUI's lazy stack's behaviour, extended to removals and resizes,
and to `List` and `Table`, which on macOS keep their offset instead. The old
behaviour, the offset kept in lines, is one TUI-specific modifier away:
`.scrollWindowHold(.offset)`. Shipped 2026-10-12, refined 2026-10-13; it
costs nothing measurable (no A/B scenario past +0.8%).

## The problem

TUI's anchoring design of 2026-07-17 (`Scroll anchoring.md`) gave a scroll
view four modes. In the default, Window, the offset was kept in line
coordinates, so rows inserted above the screen pushed the rows on screen down:
a "load earlier messages" list, or a log growing above what the reader was
looking at, jumped. Nobody had asked for that; it was simply what an offset in
lines does.

The question surfaced sideways, on 2026-10-12, while shipping SwiftUI's
`Transaction` scroll members (B30, below). Measuring how SwiftUI treats
`scrollContentOffsetAdjustmentBehavior = .disabled` showed what it adjusts by
default: a lazy stack holds its top row when rows arrive above it (the offset
moves 200 → 300 for one insertion). That made TUI's default the larger gap.

## How it unfolded

1. **2026-10-12, B30.** The transaction members shipped. Asked whether to keep
   the Window default (and record a deviation) or hold the top row as SwiftUI
   does, the owner chose SwiftUI's behaviour, configurable either way, with
   licence to redesign the anchoring API where that made it cleaner (pre-1.0,
   no compatibility spellings).
2. **2026-10-12, lane SCROLLANCHOR.** SwiftUI was measured on macOS 15.8 with
   an offscreen `NSHostingView` (`Tools/SwiftUIProbes/Scroll anchoring/`):
   insertions, removals, resizes, reorders, renames, and what each
   `defaultScrollAnchor` role changes (nothing, for this). The hold shipped
   for a lazy stack on all three of its paths and for `List` and `Table`,
   with the TUI-specific opt-out (B-SCROLLANCHOR-2). Where SwiftUI holds only
   insertions, TUI holds removals and resizes too (B-SCROLLANCHOR-1, R14).
3. **2026-10-13, A-SCROLLANCHOR-1.** macOS's `List` turned out not to hold at
   all. The owner kept the hold for `List` and `Table`: "I feel like they
   should be consistent, unless there's some apparent reason why not? And
   keeping the place (not the offset) seems like a better default." (R13.)
4. **2026-10-13, lane SCROLLB and two review rounds.** Reorders, renames, a
   move applied a frame late, and the cursor of a `List` each needed a rule;
   the entries below record each fix and what it still cannot tell apart.

## Where it stands

Shipped and stable. The hold is one memory shared by the lazy stack's three
paths (exact walk, uniform window, anchored window) and by `List` and
`Table`, so a stack behaves the same either side of the 256-row threshold.
It governs only what nothing else holds: Window mode, and an edge mode away
from its edge; following the tail, a seek, a designated row and "no
adjustment" keep their own rules.

## For a future reader

- **The cases the hold still gets wrong**, each rare and each recorded below:
  a change that inserts above and also changes the rows on both sides of the
  top row (B-SCROLLANCHOR-5); the top row and the row above it renamed in the
  same update as rows arrive above (held a row too far); the top row removed
  with the row above it, in an update whose insertions above leave the row
  count unchanged (B-SCROLLANCHOR-6); an `onMove` that takes longer than 150
  ms or three frames to apply (B-SCROLLANCHOR-4).
- **An eager `VStack` never holds** (C-SCROLLANCHOR-1), as SwiftUI's does not;
  the advice is a `LazyVStack`. Revisit only if an app needs the hold on an
  eager column and will pay for it on the hottest stack there is.
- **Above 256 rows of differing heights the offset is approximate** after an
  insertion above (B-SCROLLANCHOR-3): the rows on screen are exact, the
  scrollbar and "N more above" near the truth.
- **macOS measurements only.** iOS's `List` was never measured; if a port
  wants iOS's behaviour, measure it first.
- **SwiftUI's `ScrollPosition.scrollTo(id:anchor:)` ignored its own anchor**
  when measured (R11). If a later SwiftUI fixes that, the deviation can go.

## The record

How each part was asked, decided and shipped, in the words of the day.

### B30. The `Transaction` scroll members: what "no adjustment" suspends

*`Transaction.scrollTargetAnchor`, `Transaction.scrollContentOffsetAdjustmentBehavior`
(and `ScrollContentOffsetAdjustmentBehavior`, whose `differentShape` map entry
goes), `Transaction.scrollPositionUpdatePreservesVelocity`*

The run loop already publishes the transaction a change was made under for the
frame that renders it, so a scroll view can read all three where it decides.

- **`scrollTargetAnchor`**: preferred to a `.scrollPosition(id:anchor:)`
  modifier's anchor (SwiftUI's documentation says so); for a `ScrollPosition`
  request or a `ScrollViewProxy.scrollTo` that names an anchor of its own, the
  call's wins, and one that names none takes the transaction's. SwiftUI does
  not say which wins there; the call is the more specific statement.
- **`scrollContentOffsetAdjustmentBehavior = .disabled`** suspends a declared
  anchor's adjustments for the change: a `ScrollView`, `List` or `Table`
  following its tail does not follow, which leaves it short of the new tail
  and so releases the follow, exactly as a user scroll does (engagement is
  positional); a `List`, a `Table` or a windowed lazy stack holding a row
  (`.anchorPosition(.row)`) lets it go and holds it again from the line the
  change left it on. The opening placement is not an adjustment and is kept;
  an app's own write to a bound `.anchorPosition` still jumps.
- **`scrollPositionUpdatePreservesVelocity`** is recorded and met by the
  medium: no scroll here has momentum, so nothing is moving for a
  programmatic change to stop or spare.

`Transaction` lives below `UnitPoint`, and every `Binding` carries one
inline, so the anchor is stored in two bytes — hundredths of the viewport,
finer than any terminal's row — and the switches share one byte with
`disablesAnimations`. A binding grows by two bytes and gains no padding (a
titled `Toggle`: 195 → 197, `ControlLayoutPaddingTests`); stored as two
`Double`s and three `Bool`s it grew by twenty-four and left five undefined.

**You asked (2026-10-12) what the gap is, and what I recommend.** Measured on
macOS 15.8 (a 300×200 window, rows 20 high; `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/anchor/`
and `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/disabled/`):

- **`ScrollViewProxy.scrollTo`:** the call's anchor wins over the
  transaction's, and with none the transaction's applies. That is TUI's
  rule exactly.
- **`ScrollPosition.scrollTo(id:anchor:)`:** SwiftUI ignored the call's anchor
  (`.top` and `.center` both landed at the minimal position) and applied the
  transaction's even over a `.bottom` call. TUI honours the call's anchor
  first. That looks like a SwiftUI defect, so TUI's rule stays, recorded as
  a deliberate deviation
  ([Deliberate deviations from SwiftUI.md R11](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md#r11-scrollpositionscrolltoidanchor-honours-its-own-anchor>)).
- **`.disabled`** stops SwiftUI's lazy-stack bottom follow and its hold of the
  top row on an insertion above, as it stops TUI's follows. SwiftUI ignores
  it for an eager `VStack`, which follows anyway; TUI treats eager and lazy
  alike. Kept, and recorded
  ([Deliberate deviations from SwiftUI.md R12](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md#r12-no-adjustment-suspends-an-eager-stacks-follow-too>)).
- **The larger gap is the default.** With no `scrollPosition` at all, SwiftUI
  keeps the top row in place when rows are inserted above it (a lazy stack,
  one insertion: the offset moves 200 → 300). TUI's Window default, from
  your 2026-07-17 anchoring spec, leaves the offset in line coordinates, so the
  rows shift and a "load earlier messages" list jumps.

**Shipped 2026-10-12 (SCROLLANCHOR):** the reader that was missing inside
TUI — a windowed `LazyVStack`'s `.anchorPosition(.row)` hold ignored "no
adjustment". All three of the stack's paths now let the row go, and adopt it
on the change's own frame where the change left it. `List` and `Table` adopt
it there too: they adopted it a frame later, where the NEXT change left it,
so a second change, made without the transaction, went unheld as well.

**Asked 2026-10-12:** keep TUI's Window default and record it as a
deviation, or hold the top row by default as SwiftUI does? The second reverses
part of `Scroll anchoring.md`'s first slice for views that declare no anchor,
at a cost not measured.

**Owner, 2026-10-12 (later):** follow SwiftUI. With no anchor declared, rows
inserted above the top row keep the reader's place. Make it configurable
either way, and redesign TUI's existing anchoring API where that makes it
cleaner (pre-1.0, no compatibility spellings). **Lane owed** (SCROLLANCHOR),
together with the missing reader above; the cost is measured in that lane.

**Shipped 2026-10-12 (SCROLLANCHOR):** with nothing else holding it, a scroll
view keeps the row at the top of its viewport where it is as rows are
inserted, removed or resized above it — a lazy stack on all three of its paths,
`List` and `Table` — and holds nothing at the top, while following the tail,
for a seek, or for a change made under "no adjustment".
`.scrollWindowHold(.offset)` (TUI-specific: no SwiftUI spelling expresses it,
measured) keeps the offset in lines, the old default. Design in `Scroll
anchoring.md` §5; the lane's own entries are below, among them
[A-SCROLLANCHOR-1](#a-scrollanchor-1-list-and-table-hold-their-top-row-where-macoss-list-does-not): `List` and `Table` hold as the stacks do, though macOS's
`List` keeps its offset (measured); you kept that on 2026-10-13, for one rule
across scrollables. Cost: neutral in the A/B (no scenario past +0.8%,
2026-10-13).

### A-SCROLLANCHOR-1. `List` and `Table` hold their top row, where macOS's `List` does not

*`List`, `Table`, `ScrollWindowHold`*

Your ruling asks for two things that part here: follow SwiftUI, and keep the
reader's place when rows arrive above. SwiftUI's lazy stack does both. Its
`List` on macOS does neither: scrolled 200 points down, five rows inserted
above leave its origin where it was and the rows move down (measured,
`hold.out` cases 13–15; iOS is not measured).

**Shipped:** `List` and `Table` hold their top row, as the lazy stacks do —
the reading of "keep the reader's place" that does not depend on which kind of
scrollable it is, and the one the lane was briefed with. An app that wants
macOS's `List` writes `.scrollWindowHold(.offset)` on it. Recorded as
deliberate deviation R13.

**The alternative:** follow macOS — `List` and `Table` keep their offset by
default and hold under `.scrollWindowHold(.topRow)`. One line: a per-view
default where the list reads the environment (`syncFrameInputs`), which then
needs the environment value to be optional (`nil` = "the view's own default").
About an hour with the tests. **Recommendation:** keep what shipped; a
terminal list that jumps when a log above it grows is the case the ruling was
about, and the switch is one modifier either way.

**Owner, 2026-10-13: keep what shipped.** "I feel like they should be
consistent, unless there's some apparent reason why not? And keeping the place
(not the offset) seems like a better default." `List` and `Table` hold their
top row as the lazy stacks do.

### B-SCROLLANCHOR-1. A removal above, and a row above growing, are held as an insertion is

*`ScrollWindowHold.topRow`*

SwiftUI's lazy stack holds only insertions: rows removed above the top row
leave its origin where it was, and the rows on screen move up (measured,
`hold.out` case 2); a row it has not laid out growing moves nothing, since it
does not know (case 3 says only that the origin stayed).

**Shipped:** TUI holds the top row whichever way the content above it
changed — inserted, removed, or resized where the scroll position counts lines
and the rows above are measured (a lazy stack's exact walk; `List` and `Table`
count rows, so a row above growing never moved theirs). "The reader's place"
does not depend on the direction of the change, and one rule is simpler to rely
on. When the top row itself is removed, the row after it takes its
place — which is also what SwiftUI shows when nothing above it changed (case 8).
Recorded as deliberate deviation R14.

**The fuller version** — insertions only, as SwiftUI — would need the hold to
tell an insertion from a removal, which it does not track: it compares where
one remembered row is now. A count of the rows before it, kept frame to frame,
would do it, and so would break on a change that does both. Not recommended.

### B-SCROLLANCHOR-2. The opt-out is a TUI-specific modifier, `.scrollWindowHold(.offset)`

*`ScrollWindowHold`, `View.scrollWindowHold(_:)`, `EnvironmentValues.scrollWindowHold`*

No SwiftUI spelling switches the hold off: `defaultScrollAnchor(_:for:
.sizeChanges)`, the role SwiftUI documents as "how a scroll view should adjust
its content offset when the scroll view's content or container size changes",
changes nothing about it at `.top`, `.center` or `.bottom` (measured, `hold.out`
cases 16–23: every anchor holds the row alike), and
`Transaction.scrollContentOffsetAdjustmentBehavior` is per change, not per view.

**Shipped:** `ScrollWindowHold` (`.topRow`, the default; `.offset`), set with
`.scrollWindowHold(_:)` or `\.scrollWindowHold`, kept apart from SwiftUI's API
as TUI-specific additions are. It governs only what nothing else holds — Window
mode, and an edge mode away from its edge; the edges, a designated row and "no
adjustment" keep their own rules — so it composes with `.defaultScrollAnchor`
and `.anchorPosition` rather than competing with them. `ScrollAnchor.window`
keeps its name: the released state it names now holds the top row, and "the
window stays where it is" reads either way.

**The fuller version** would fold the choice into `ScrollAnchor`/`.anchorPosition`
(say, a fifth case for line coordinates). A user scroll writes `.window` into a
bound anchor, so a mode written there would be lost on the first wheel tick;
the setting has to be standing, which is what an environment value is. Not
recommended.

### B-SCROLLANCHOR-3. The anchored walk's offset follows the held row by the running pitch

*`LazyVStack` over more than 256 rows of different heights*

The anchored walk holds the row structurally — the top row, found by its key,
becomes its anchor — so the rows on screen are exact. Its offset is not: the
rows inserted above are never measured (that is the walk's point), so the
offset moves by their count times the running pitch, keeping the scrollbar and
"N more above" near the truth; when the held row is the first, the offset is
exact. Left where it was, a "load earlier" of hundreds of rows would leave
"N more above" short by all of them.

**The fuller version** measures the inserted rows: exact, and O(inserted) per
change — the price the walk exists not to pay. Not recommended.

### B-SCROLLANCHOR-4. A `List`'s focus cursor moves with the rows the hold keeps in place

*`List`, `Table`*

The cursor is a row index. Left where it was when the hold moves the offset, it
points at another row — drawn elsewhere, or off screen, where the next arrow
key's reveal scrolls back to it and undoes the hold. **Shipped:** when the hold
moves the offset by some rows, a cursor on the top row or below it moves by as
many. A cursor above the top row is left alone: the change may have been on
either side of it. **The fuller version** tracks the cursor's row by id every
frame — one more id read a frame, which can be a build of the row (`id(at:)`)
— and is exact for a change between the top row and the cursor too. Two hours.
A move the list makes itself (a move chord, a drop) is not held at all: it puts
the cursor on the row it moved, and shifting it as well put it a row off.

**2026-10-13 (lane SCROLLB, the review's S4):** an `onMove` that applies the
move later — `onMove { s, d in Task { await store.move(s, d) } }` — drew the
key's frame with the rows unchanged, which spent the "not held" mark, and the
moved rows a frame later were held: the cursor landed on the old top row
again. The mark now waits through up to three frames whose top row is where
it was, and is spent by the first that finds it moved. The price: a change
made above the top row in those frames, by anything else, is not held either.
An `onMove` that takes longer than three frames to apply is still held.

**And bounded in time (the lane's own review, round 1):** only frames that
find the top row in place spent the wait, and a move below the top row — the
common move chord — leaves it there. A list that drew nothing more after the
move stood waiting for good, and an insertion or removal above the top row
seconds later was taken for the move and not held: the rows jumped, and the
cursor named another row. The wait now also ends 150 ms of frame clock (three
frames' time) after the first frame that follows the move; the clock is read
only while a move is awaited. An `onMove` that takes longer than that to apply
is held, as one slower than three frames was.

### B-SCROLLANCHOR-5. A reorder is told from rows inserted or removed above by the row after the top row

*`ScrollWindowHold.topRow`*

The hold finds where the top row went, so a sort, which moves it far away,
would scroll the view after it. SwiftUI holds nothing through a reorder:
reversing the rows, moving the top row to the end, swapping it with the next,
moving a row from below to the start — the origin stays every time (measured,
`Tools/SwiftUIProbes/Scroll anchoring/reorder.out`).

**Shipped:** the top row is followed only when the row that followed it is
still the same distance after it, or the row before it the same distance before
it (the row before since 2026-10-13) — rows inserted, removed or moved above
move all three alike, and a row inserted or removed beside the top row in the
same change moves one of its neighbours only; a sort parts it from both, and
the offset stays, as SwiftUI's does. SwiftUI holds the row through the change
beside it (measured, `Tools/SwiftUIProbes/Scroll anchoring/beside.out` cases
3–5), which the row after it alone took for a sort. Up to two key (or id)
reads more, on a frame whose top row moved; none otherwise. A designated row
is followed through a reorder as before: it names a row. The cost of the
rule: a change that inserts above and changes the rows on both sides of the
top row is not held.

**The fuller version** would hold only insertions of new rows, as SwiftUI
does — which needs the previous frame's set of ids to tell a new row from a
moved one: O(rows) a change. Not recommended (B-SCROLLANCHOR-1).

### B-SCROLLANCHOR-6. A top row whose id changes as rows arrive above keeps its place

*`ScrollWindowHold.topRow`*

A top row whose id changes where it stands — `ForEach(names, id: \.self)`
with the top name edited — keeps the offset in SwiftUI, and in TUI: the
rows either side of it are still where they were, so nothing above moved
(measured, `Tools/SwiftUIProbes/Scroll anchoring/beside.out` case 1). In the
same change as five rows inserted above it, SwiftUI holds nothing — the row
it would hold is gone — and the five new rows push the rows on screen down
(case 2).

**Shipped:** TUI holds the place: the rows before and after it are still
either side of one place, so the row in it changed and the rows above it
arrived, and the arrivals are held as any are — the renamed row stays at the
top. It is the two changes held as each is held alone, the reader's place
kept whichever way the rows above changed, as for a removal above (R14).

**The fuller version** is SwiftUI's: hold nothing once the top row's id is
gone with the rows above changed. Minutes — drop the row before from the
gone-row rule — and the cost is the jump.

**Fixed 2026-10-13 (lane SCROLLB, the SCROLLANCHOR review's S3):** the rule
read neighbours remembered on the last frame that found the top row
somewhere new. A frame that found it in place re-read nothing, so a row
inserted just after it there left the row after it stale, and a rename in a
later frame put the row two after it on top — and a `List`'s cursor two rows
on; with rows inserted above as well, the view moved k + 2. The neighbours
are now read again on a frame that finds the top row in place when the row
count has changed since they were read (one comparison on every other frame,
and two reads on a frame that inserted or removed rows anyway). And the place
is judged kept by the row before it alone where there is one: "still where the
place was" took a top row removed with exactly one row inserted above for a
rename and put the row from above the screen on top, where two inserted put
the row after it there, as this entry says. A change that both inserts beside
the top row and removes a row elsewhere, in one update that leaves the count
alone, still leaves the row after it stale.

**And again (the lane's own review, round 1):** asked of the row before it
alone, the top row renamed with the row above it in one update — a bulk edit
of two selected rows — judged the place gone: the row after it was put on top,
the view moved a row, and a `List`'s cursor a row on. The place is now kept
when one row still stands between the rows either side of it — the row before
it right before the place, or the row after it as far after it as it was —
and not when the row before it is right before the row after it, the top row
gone from between them, which is what a removal with a row inserted above
looks like. One id read more, on a frame whose top row is gone. The two renamed
together in the same update as rows arrive above are still held a row too
far, as before either fix: neither neighbour is left to tell the place by.
And one case remembered rows cannot tell from those two renamed in place: the
top row removed with the row above it removed or renamed, in an update whose
insertions above leave the count where it was (ids 9 and 10 removed and two
rows inserted at the start, the view at 10). The place is kept, and the row
that was above the screen (8) is drawn on top, where the rule before the
first fix put the row after (11) there.

### C-SCROLLANCHOR-2. The anchored walk's top-row hold has no ladder

*`LazyVStack` over more than 256 rows, `ScrollWindowHold.topRow`*

The anchored walk used to hold its anchor itself, and its ladder handed a
deleted anchor to the nearest surviving row. Since the hold became one memory
shared by the three paths (2026-10-12), the anchored walk finds the top row as
the other two do — the row, or the row after it where it was — and a change
that removes the top row and the row after it together with a change above
holds nothing (the review of 2026-10-13, S4). Restoring the ladder there
would make the anchored walk hold where the uniform and exact paths, and
`List` and `Table`, do not, so a stack would behave differently either side of
256 rows, which the shared memory exists to stop. A designated row keeps its
ladder: it names a row. Declined; the fuller version would give all five a
ladder of the rows after the top one, at a read a rung on the frames that
need it.

### C-SCROLLANCHOR-1. An eager `VStack` does not hold

An eager `VStack` in a `ScrollView` is measured and drawn whole, and the scroll
view clips it; there is no window, and so no row at the top that the stack
knows of, and a child of an eager stack need not have an identity to hold (a
positional child has none). SwiftUI's eager stack does not hold either
(measured, `hold.out` cases 10–12), so this is parity. Holding there would mean
giving the scroll view each eager child's key and place every frame — a cost on
the hottest stack there is, for every app, to go beyond SwiftUI. As with a
designated row (`Scroll anchoring.md` §3.4), the windowed `LazyVStack` is the
stack that anchors.
