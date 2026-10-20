# Completing the SwiftUI API: decisions from lane SCROLL

*Lane SCROLL, 2026-10-19: scrolling fixes and parity — scroll target
behaviours inside content margins (B-D2S-7), the animated scroll transition's
threshold (B-D5G-8), and the other scrolling items of the 2026-10-18
inventory. This file holds the judgement calls the work reached, in the format
of [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-SCROLL-n — needs your decision.** Nothing has shipped for these.
- **B-SCROLL-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SCROLL-n — declined.** With the reason.

## B. Shipped

### B-SCROLL-1. `.paging` under a top or leading margin steps the container, not SwiftUI's half-margin longer page

*`PagingScrollTargetBehavior` in a `ScrollView` with `.contentMargins`
(B-D2S-7, which you settled as "probe, then follow SwiftUI")*

The probe (`Tools/SwiftUIProbes/Scroll target behaviours/`) confirmed
SwiftUI's documented reading of a behaviour's context: the container is the
bounds less the margins, the content its size without them, the target the
area inside them. `.viewAligned` follows it: a row (or a carousel's card)
lands at the top (leading) margin, the one before it showing in the margin.
That shipped, and so did `.paging` stepping the container — every page lands
inside the margins, and a page sized with `containerRelativeFrame` is the page
a step moves.

SwiftUI's own `.paging` does not quite: its page is the container plus HALF
the top margin (vertically) or the leading margin (horizontally), at every
size measured (top 20, 30, 40, 60; with bottom 0, 10, 20; leading 20 and 40),
and the container exactly when only the bottom or trailing margin is set.
So under a top margin of 40 SwiftUI steps 90 points through a 70-point
window: no container-sized page lines up with any stop, and each stop shows
20 points more of the page before. Nothing in its documentation describes
that, and it looks like an arithmetic slip, so it is recorded as deviation
R15 rather than copied.

**The other version:** copy it — `paged(…)`'s page lengthened by half the
top or leading margin, rounded down to whole cells. Ten minutes and a test;
but it would undo the one thing a paging view under margins is for, and an
app sizing its pages to the container would see them drift.

### B-SCROLL-2. Only a pager decides its `.automatic` horizontal bar before its container

*`containerRelativeFrame` in a `ScrollView` that scrolls across, with the
default `.automatic` horizontal indicator (B-FU2-2)*

**Shipped:** a view under a scroll target behaviour decides an `.automatic`
horizontal bar by a measure of its content's width before it publishes the
container, so the bar's row comes off a container-sized page and the page is
the step (FU2's fuller version). A view under no behaviour decides the bar as
before, by the rounds that measure the content in its container, and its
container keeps the bar's row. In a two-axis view that is a page one line
taller than the window, which scrolls to that line like any other; in a
`ScrollView(.horizontal)` with no behaviour, whose content cannot scroll
down, a card sized to the container's height has its last line under the bar.

**The other version:** every view that scrolls across with an `.automatic`
bar decides it first. Price: one more measure of the content's width on every
frame of every such view (a wide table in a horizontal scroll view, every
two-axis view), in a generation of its own, so it cannot warm the render's
memo either, where today only pagers pay it. Without a behaviour the drift is
not a defect, only the horizontal-only card's last line is, and
`.scrollIndicators(.visible, axes: .horizontal)` or a card a line shorter
avoids it.

### B-SCROLL-3. `onScrollTargetVisibilityChange` measures the stack's views along its axis, from what the stack reports

*`View.onScrollTargetVisibilityChange(idType:threshold:_:)` (A7, the reader
left unbuilt when `onScrollVisibilityChange` shipped)*

**Shipped:** the scroll view the observer is stated above asks its content's
stack for its views' extents and how to name each — the extents a scroll
target behaviour settles on (`TargetLayoutSpans`), now with each view's
ordinal, and the per-child ids `.scrollPosition` reads back
(`StackRowIDs`) — and, once the frame's offset is final, lists the ids of
those that show at least the threshold of themselves along the stack's axis,
and at least a cell. Reported on the first frame and whenever the list
changes. Every stack path reports them: eager, the full walk, the uniform
window (by arithmetic) and the anchored window (its band, which holds every
row on screen), and a horizontal stack's columns, eager or lazy, through a
section's header and the content margins. A scroll view with no such
observer asks for nothing.

Where it differs from SwiftUI, recorded in the guide: rows are reported
whether or not the stack is marked with `scrollTargetLayout()` (as
`.scrollPosition` reads them, deviation R6); the fraction is along the
stack's axis only, so a row a two-axis view has scrolled out sideways still
counts; and a threshold of 0 counts a view once a cell of it shows, where
`onScrollVisibilityChange` reports every view shown at 0, as SwiftUI's does —
for this one that would list every row of a lazy stack's data.

**The fuller version:** G1's markers on each view of the target layout (what
`onScrollVisibilityChange` measures): a view's true drawn rect, so both axes
count and a view inside a nested container is measured where it is drawn.
Price: a marker and a registration per row drawn in each of the stack's six
paths, on the render's hot path whenever an observer is stated, about a day;
and nothing seen needs it yet.

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

### B-SCROLL-6. A bound scroll position is the first scrollable's; one nested in its content takes none of it

*A `List`, a `Table` or a `ScrollView` in the content of a `ScrollView` that
`.scrollPosition` is bound to (lane SCROLL's review, 2026-10-19)*

**Measured** (`Tools/SwiftUIProbes/Nested scroll position/nested.swift`): in
SwiftUI a nested `ScrollView` or `List` does not follow the outer view's
write-backs, and its own scroll writes nothing into the binding. An id the app
writes is sought by the outer view where its content holds it; one that only
the nested scrollable holds is sought there.

**Shipped:** a scroll view takes the binding out of its content's
environment, as it takes its scroll observers and content margins. Until then
a nested scrollable read it too, and since a `List` and a `Table` came to read
it (SA-44) every one did. Each took the other's write-back for a request: a
request for row 48 sent a list in the content to its own row 48, which its
last rows kept below its top; the list wrote back the row at its top, and the
outer view sought that one. A framework scroller passes the binding on, as it
passes on the other settings.

**The fuller version:** an id the app writes that only a nested scrollable
holds is not sought here. To seek it, the outer view would hand a request it
could not find, and nothing else, to the scrollables in its content on the
next frame, and they would neither report nor take its write-backs. About
half a day, with tests for the shared and the nested-only ids.

## C. Declined

### C-SCROLL-1. `scrollTo` a row of a vertical stack inside `ScrollView(.horizontal)`

*`ScrollViewProxy.scrollTo(_:anchor:)` and `.scrollPosition(id:)` on a purely
horizontal scroll view whose content is a vertical stack (semantic audit 45's
remainder)*

A purely horizontal scroll view seeks a COLUMN of its horizontal stack; a row
of a vertical stack there is not sought, and `ScrollViewReaderTests` pins the
refusal. SwiftUI seeks it along x (measured,
`Tools/SwiftUIProbes/Scroll to a row/hrow.swift`): the row's own span —
narrower rows sit where the stack's alignment puts them — is aligned by the
anchor's `x`, and no anchor moves nothing where the row already shows. The
view cannot scroll down to the row, so only its horizontal place counts.

Declined for now: the shape is rare (a column of rows wider than the view,
scrolled only sideways), and each of the vertical stack's four paths — the
eager layout, the full walk, the uniform and the anchored windows — would
have to report the sought row's x span (its alignment offset and width) the
way a horizontal stack reports a column's, for the scroll view's existing
column arithmetic (`ScrollToRequest.columnOffset`) to place. About half a
day with tests. A behaviour of an existing method, so there is no parity-map
entry.
