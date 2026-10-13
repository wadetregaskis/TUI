# The scroll anchoring default: decisions from lane SCROLLANCHOR

*Lane SCROLLANCHOR, 2026-10-12, shipped decisions B30's two owed items: the
reader that was missing (a windowed lazy stack's held row ignored "no
adjustment") and the default — with no anchor declared, rows inserted above
the top row keep the reader's place, as SwiftUI's do, configurable either way
(the owner's ruling of 2026-10-12). SwiftUI was measured on macOS 15.8 with an
offscreen `NSHostingView` (`Tools/SwiftUIProbes/Scroll anchoring/hold.swift`,
its output beside it). The design is `Documentation/Layout and
scrolling/Scroll anchoring.md` §5. The format is that of the main decisions
file:*

- **A-SCROLLANCHOR-n — needs your decision.**
- **B-SCROLLANCHOR-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-SCROLLANCHOR-n — declined.** With the reason.

## A. Needs your decision

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

## B. Shipped the safe option

### B-SCROLLANCHOR-1. A removal above, and a row above growing, are held as an insertion is

*`ScrollWindowHold.topRow`*

SwiftUI's lazy stack holds only insertions: rows removed above the top row
leave its origin where it was, and the rows on screen move up (measured,
`hold.out` case 2); a row it has not laid out growing moves nothing, since it
does not know (case 3 says only that the origin stayed).

**Shipped:** TUIkit holds the top row whichever way the content above it
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
with the top name edited — keeps the offset in SwiftUI, and in TUIkit: the
rows either side of it are still where they were, so nothing above moved
(measured, `Tools/SwiftUIProbes/Scroll anchoring/beside.out` case 1). In the
same change as five rows inserted above it, SwiftUI holds nothing — the row
it would hold is gone — and the five new rows push the rows on screen down
(case 2).

**Shipped:** TUIkit holds the place: the rows before and after it are still
either side of one place, so the row in it changed and the rows above it
arrived, and the arrivals are held as any are — the renamed row stays at the
top. It is the two changes held as each is held alone, the reader's place
kept whichever way the rows above changed, as for a removal above (R14).

**The fuller version** is SwiftUI's: hold nothing once the top row's id is
gone with the rows above changed. Minutes — drop the row before from the
gone-row rule — and the cost is the jump.

## C. Declined

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
