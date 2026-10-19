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
