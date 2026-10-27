# Paging and view-aligned scrolling

*How SwiftUI's scroll target behaviours (`.paging`, `.viewAligned`, an app's
own `ScrollTargetBehavior`) and the alignment anchor role came to TUI, and
what each scrollable does with them. Ids: A6, A8, B-D2S-1, B-D2S-2, B-D2S-3,
B-D2S-6, B-D2S-7, B-SCROLL-1, B-SCROLL-2; deviation R15.*

## In short

A `ScrollView` honours every behaviour, built-in or the app's own, with
SwiftUI's geometry: the container is the window less the content margins, a
row or card lands at the top or leading margin, and a page sized with
`containerRelativeFrame` is exactly the step. `List` and `Table` honour the
two built-in behaviours in whole rows, and never consult an app's own, as
SwiftUI's macOS `List` does not either. Under a behaviour, a scroll view
whose indicator style is `.text` keeps its "▲ N more" / "▼ N more" lines
reserved at every stop, so every page lands whole between them.

## The problem

SwiftUI's paging idiom is `.scrollTargetBehavior(.paging)` over pages sized
with `.containerRelativeFrame`. In a terminal three things work against it:
offsets are whole lines, a list's offset is a row and a clip rather than a
point, and TUI's `.text` indicator style draws "N more" lines over the first
and last lines of the viewport, which makes the visible area a line shorter
at each end exactly where a page is meant to fit.

## How it unfolded

1. **The owner's decisions A6, A8, A9 and A10.** Behaviours on `ScrollView`,
   and `.paging` and `.viewAligned` on `List` and `Table` too; the
   `.alignment` anchor role (A8). Lane D2S built them. SwiftUI's `List` was
   measured never to call a custom behaviour (B-D2S-2), so the lists honour
   only the two built-ins. `ScrollGranularity.row` was folded into
   `.viewAligned` and removed (the notes at the end).
2. **The "N more" lines.** Two reviews pulled opposite ways: handed the whole
   viewport, `.paging` left the lines under the indicators unread at every
   stop; handed the lines between them, it stopped off every
   container-sized page. The rule that shipped reserves the pair at every
   stop under a behaviour (B-D2S-6).
3. **2026-10-19, lane SCROLL: margins.** The owner settled B-D2S-7 as "probe,
   then follow SwiftUI". A resize probe (`Tools/SwiftUIProbes/Scroll target
   behaviours/`) confirmed the documented reading, and behaviours now get
   SwiftUI's container, content and target. One measured quirk was not copied:
   SwiftUI's own `.paging` steps half the top margin more than the container
   (B-SCROLL-1, R15). The same day the horizontal case of the alignment role
   was built (B-D2S-1) and a pager's `.automatic` horizontal bar was settled
   before its container (B-SCROLL-2).
4. **2026-10-26, the owner on B-D2S-6.** Asked whether "▲ 0 more" should ever
   show, the owner went further: variable page sizes where they can be had,
   blank reserved lines where they cannot (or would cost too much), and never
   a row cut off. **Not yet built.** B-D2S-7 was put to the owner again that
   day by mistake (it had shipped on 10-19).

## Where it stands

Shipped as described, except the owner's 10-26 refinement of B-D2S-6, which
is owed. The lists' anchors under `.viewAligned` (B-D2S-3) and a custom
behaviour on a list (B-D2S-2) are recorded fuller versions nobody has asked
for.

## For a future reader

- **B-FU2-2** (a two-axis pager's horizontal bar and its container) was a follow-up lane FU2 recorded and lane SCROLL settled on 2026-10-19 (B-SCROLL-2); its entry is the last below.
- **Owed: B-D2S-6 as the owner ruled on 2026-10-26** — variable pages where
  possible, blanks where not, never a cut row; and "▲ 0 more" should not show
  at a count of zero (the 10-23 analysis recommended a bare dim arrow or a
  blank line).
- **R15 is a judgement that SwiftUI slipped.** If a later SwiftUI changes its
  half-margin page, re-measure with the probe and follow it either way.
- **SwiftUI consults a behaviour only on a gesture or a resize**, which is
  why the margins needed a resize probe; anything else about behaviours that
  needs measuring needs that probe too.
- **`.viewAligned` finds rows only in the stack that is the scroll view's
  content** (through a section header or the margins). A marked stack further
  in scrolls freely; past 256 rows of varying height the anchored path knows
  only its band's rows.

## The record

### B-D2S-1. The alignment role places content on the vertical axis only

*`ScrollAnchorRole.alignment` (A8)*

SwiftUI places content shorter than a scroll view by the anchor's `y` on a
vertical view and by its `x` on a horizontal one (measured on macOS 15: a
100-point item in a 300-point `ScrollView(.horizontal)` sits at `x` 200 under
`.trailing` for `.alignment`, at 100 under the unlabelled `.bottom`, whose `x`
is 0.5). The cross axis is always centred, whatever the anchor says.

What ships reads `y` on a view that scrolls vertically, which is what the
owner's option 1 described, and ignores `x`, as TUI already does for the
other two roles ("the anchor modes are defined over rows"). So
`ScrollView(.horizontal) { … }.defaultScrollAnchor(.trailing, for: .alignment)`
compiles and keeps narrow content at the leading edge — a documented
deviation, on the role's doc comment and in the compatibility doc.

**The fuller version:** slide a horizontal view's drawn viewport right by the
anchor's `x` of the room, as the vertical slide does. What makes it more than
the vertical case's hour is that a horizontal view lays content narrower than
its viewport out at the viewport's width (`contentExtents`), so its natural
width has to be carried out of the measure, and content that fills the width
it is given (a `.frame(maxWidth: .infinity)`) has no room to place; SwiftUI
lays it out at its ideal width instead. About half a day, with tests, and it
changes the drawing of every horizontal view under an unlabelled `.bottom` or
`.center` (they would centre). SwiftUI's two-axis view adds the room to an
already centred position (an item drawn past the view's bounds, measured), which
looks like a SwiftUI bug and would not be copied.

**Done 2026-10-19 (lane SCROLL).** The content's own width is measured as the
scroll view's extents measure it (`naturalContentWidth`), only for a view
with an alignment anchor that scrolls across, and the drawn window slides
right by the anchor's `x` of the room, to a column — the lines, hit regions,
layers and runs with it, the offset staying 0 — reported in `ScrollGeometry`
as a leading inset, as the vertical shift is a top one. So a horizontal view
under the unlabelled `.top` or `.bottom` now centres narrow content, as
SwiftUI's does. Content that fills whatever width it is offered has no width
of its own and is not moved (SwiftUI lays it out at its ideal width), and a
two-axis view places each axis by its own coordinate.

### B-D2S-2. `List` and `Table` honour the built-in behaviours, and no behaviour of the app's own

*`View.scrollTargetBehavior(_:)`, `ScrollTargetBehavior` (A6)*

The owner's A6 decision puts `.paging` and `.viewAligned` on `List` and
`Table`. What ships there: `.paging` moves every step a page from where the
view is, as Page Down does, and `.viewAligned` is whole-row steps (what
`ScrollGranularity.row` was) with its limits. A behaviour of the app's own is
not consulted — the list steps by lines, as with none.

That is also what SwiftUI's `List` does on macOS: a custom behaviour's
`updateTarget(_:context:)` is never called while a `List` scrolls, by the wheel
or by a resize (measured on macOS 15, 2026-10-05, with a behaviour that logs
every call; the same behaviour on a `ScrollView` is called).

**The fuller version:** hand a custom behaviour a list's geometry in lines. A
`List`'s offset is a row and a clip, and a target rect in lines needs every
row's height above the viewport — a walk the list exists not to make, at
`rowHeight` calls that build the rows. About a day, with a prefix-sum cache,
for something SwiftUI's own `List` does not do.

### B-D2S-3. In a `List` or `Table`, `.viewAligned` aligns rows at the top, whatever its anchor

*`ViewAlignedScrollTargetBehavior.init(anchor:)`, `.viewAligned(anchor:)` (A6)*

In a `ScrollView`, the anchor is honoured: `.viewAligned(anchor: .center)`
settles with a row's centre at the view's. In a `List` or `Table`, whole-row
steps keep the top row whole, as `ScrollGranularity.row` did, and the anchor is
not consulted; the limits are.

**The fuller version:** after each row step, move the list's top row and clip
so the row nearest the anchor meets the view's anchor point — a walk of the
heights of the rows on screen, which the list already makes for its reveal.
About half a day, with tests over rows of mixed heights.

### B-D2S-6. Under a scroll target behaviour, the "N more" lines are kept out of the content

The `.text` indicator style draws "▲ N more" / "▼ N more" over a scroll view's
first and last line while something is hidden that way (`.automatic`), or
reserves both lines at every offset (`.visible`). A behaviour lands pages and
views in the visible area, and drawn over the content the pair made that area
a line shorter at each end wherever it showed. Two reviews pulled opposite
ways: handed the whole viewport, `.paging` left the lines under the indicators
at every page boundary unread at every stop; handed the lines between them
(2add33c43), it stopped off every page sized with `containerRelativeFrame` —
SwiftUI's paging idiom — since those pages were sized against the whole
viewport.

Shipped: a `ScrollView` under any behaviour but the default reserves the pair
at every offset, as `.visible` does, wherever its content overflows the
window it is seen through — decided once per layout, on the content's height
in that window with nothing reserved (the viewport, less a horizontal bar that
is always drawn), so it is the same at every stop; content that fits has nowhere to
step and reserves nothing (scroll lane review 3: five rows in a dialog drew
three between "▲ 0 more" and "▼ 2 more", and scrolled). Reserved lines come
off the `containerRelativeFrame` container (under `.visible` too, with or
without a behaviour), and count in the view's ideal height wherever they are
reserved whatever the content (`.visible`), so a parent that sizes to it gives
them room. The content window is then one size at every stop: it is the page
`.paging` steps, the container a page is sized against, and `ScrollGeometry`'s
container. Every line is read at some stop, every container-sized page lands
whole between the two lines, and `.viewAligned` lands a row on the first line
below "▲". The cost is `.visible`'s look: at the very top "▲ 0 more lines
above" holds the first line, where `.automatic` shows content. Only the `.text`
style under a behaviour changes; the bar style, the default, spends a column.

**The alternative:** keep `.automatic`'s coming-and-going hint under a
behaviour and size the container to the lines between the two indicators
whatever is drawn. Pages land between them too, but a page is two lines shorter
than the view even at the top, where only "▼" shows, and the container would
have to depend on the behaviour, or every `.text` scroll view's full-height
content would lose two lines. About as small a change; owner's call if the
always-drawn pair reads badly.

### B-D2S-7. A scroll target behaviour's container and content include the content margins

SwiftUI documents the context's `containerSize` as the scroll view's bounds
less its insets, and `ScrollGeometry` already reads that way here. Shipped
(since ac1bb4801): the behaviour's container is the content window, margins
included, its content the margined content, and its target the window at the
offset. So under `.contentMargins`, `.paging` steps the whole window while a
`containerRelativeFrame` page is the window less the margins, and
`.viewAligned` lands a view at the window's edge with its margin scrolled off
(`viewAlignedUnderAMargin`, `viewAlignedColumns`). No other case is affected:
the end and every edge agree either way.

**The fuller version:** SwiftUI's coordinates — the target is the area inside
the margins, the content its size without them, and the target layout's spans
moved back by the top or leading margin — so a page sized against the
container lands inside the margins, and a carousel's views align at its
leading margin with their neighbours showing beside it, if SwiftUI's
view-aligned behaviour honours the margins as its documentation of
`containerSize` suggests. Not measured: SwiftUI consults a behaviour only on a
gesture or a resize, which an offscreen probe does not drive readily. Half a
day with a resize probe and the two tests' new numbers. Owner's call.

**Done 2026-10-19 (lane SCROLL), the owner having settled it as "probe, then
follow SwiftUI".** A window resize drives SwiftUI's behaviour offscreen
(`Tools/SwiftUIProbes/Scroll target behaviours/`), and a behaviour of the
probe's own logs what it is handed. It confirmed the documented reading: the
container is the bounds less the margins, the content its size without them,
and the target the area inside them, the content's first line at 0;
`.viewAligned` lands a row at the top margin and a carousel's card at the
leading one, the view before it showing in the margin. That is what a
behaviour is handed here now, the target layout's spans moved back by the top
and leading margins with it. `.paging` steps the container, so a page lands
inside the margins and a container-sized page is the step — where SwiftUI's
own page is half the top (leading) margin longer, which is not copied
(decisions SCROLL B-SCROLL-1, deviation R15).

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

### Notes on A6 that are not decisions

- `ScrollGranularity.row` did nothing `.viewAligned` cannot: on `List` and
  `Table` the two are the same mechanism, and `.row` never reached a
  `ScrollView`. It is removed, and its users (the Example's List and Table
  pages, the tests) use `.viewAligned`. `ScrollGranularity` keeps `.line`, and
  `.scrollGranularity(.line)` now takes a subtree back to line steps from a
  behaviour stated further out — which SwiftUI cannot say. The public
  `EnvironmentValues.scrollGranularity` is gone (SwiftUI has none).
- `ScrollTarget.rect` is a `CellRect`, the context's sizes `CellSize` and its
  `velocity` a `CellVector`: cells, as the rest of TUI's geometry. The
  velocity is the step in cells — a terminal's steps have no duration to
  measure points per second from.
- `.viewAligned` finds the rows (or columns) of the stack that is the scroll
  view's content, under a `Section`'s header, or inside the content margins —
  the reach of the scroll window. A marked stack further in (below a header
  in a `VStack`) is not found, and the view scrolls freely, as an unmarked one
  does. The anchored path (a lazy stack over 256 rows of varying height) knows
  only the rows of its band, so a step past them settles on the furthest it
  knows.

### B-FU2-2. A two-axis pager's container leaves out a horizontal bar only when it is `.visible`

*`containerRelativeFrame` inside `ScrollView([.horizontal, .vertical])` under a
scroll target behaviour (scroll lane review 3, item 2)*

**Shipped:** the container takes the horizontal bar's row off where the bar is
known before anything is measured — `.visible`, which is always drawn — so a
container-sized page is the page `.paging` steps. Under `.automatic` the bar
comes with overflow, which is decided by measuring the content after its
container is published, so such a pager's container-sized pages are a row
taller than the step and drift by it at each stop; the container's doc and the
compatibility doc say so, and how to avoid it.

**The fuller version** decides the automatic bar first: measure the content's
width at the unreserved container (a second measure for a two-axis pager, the
only view that pays), or take the bar from the frame before (no measure, one
frame of drift when the bar first appears). About two hours with tests.

**Done 2026-10-19 (lane SCROLL), the first way.** A view under a scroll target
behaviour that scrolls across, with an `.automatic` horizontal bar, measures
its content's width at the whole viewport before it publishes the container
(`_ScrollViewCore.horizontalBarDecidedFirst`), in a measure generation keyed
by the container's height, as the text-style pager's overflow probe is; wider,
and the bar's row comes off the container and the bar rounds start with it.
So a two-axis pager's container-sized pages are the step, and a horizontal
pager's container-sized cards end above the bar instead of under it. Content
that fits the whole width and overflows only once a vertical bar takes its
column is left to the rounds, as before. The frame before was not used: a
frame would then depend on its history, which the memo verifiers and the
selfcheck compare against a fresh render. Views with no behaviour keep the
old container (decisions SCROLL B-SCROLL-2).
