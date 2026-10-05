# Completing the SwiftUI API: decisions from lane D2S

*Lane D2S implemented the owner's decisions A8 (`ScrollAnchorRole.alignment`),
A9 (`scrollContentBackground`), A6 (scroll target behaviours) and A10
(`scrollClipDisabled`). This file holds the judgement calls the work reached that
the owner's decisions did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-D2S-n — needs your decision.** Nothing has shipped for these.
- **B-D2S-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-D2S-n — declined.** With the `parity-map.json` reason.

## B. Shipped the safe option

### B-D2S-1. The alignment role places content on the vertical axis only

*`ScrollAnchorRole.alignment` (A8)*

SwiftUI places content shorter than a scroll view by the anchor's `y` on a
vertical view and by its `x` on a horizontal one (measured on macOS 15: a
100-point item in a 300-point `ScrollView(.horizontal)` sits at `x` 200 under
`.trailing` for `.alignment`, at 100 under the unlabelled `.bottom`, whose `x`
is 0.5). The cross axis is always centred, whatever the anchor says.

What ships reads `y` on a view that scrolls vertically, which is what the
owner's option 1 described, and ignores `x`, as TUIkit already does for the
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

### B-D2S-4. `scrollClipDisabled` reaches `ScrollView`; `List` and `Table` keep clipping

*`View.scrollClipDisabled(_:)` (A10)*

The owner's A10 decision is about the scroll view: its content past the
viewport draws as a floating layer around it, over the neighbours, with its hit
regions. That ships for `ScrollView`. SwiftUI's `List` on macOS honours the
modifier too (measured on macOS 15: rows draw on below a 100-point list's frame
when it is set, and do not when it is not), and TUIkit's `List` and `Table`
still clip: the modifier compiles on them and changes nothing.

**The fuller version:** a list draws only the rows its window walks, so it
would draw a row or two past each edge under the modifier (its band, as a lazy
stack's), and hand them out as the scroll view's overflow layers are; the
header, the border and the indicators stay where they are. About half a day
for both, with tests, and no cost to a list without the modifier.

### B-D2S-5. A later view hides an unclipped scroll view's overflow from its first painted cell to its last

Under `scrollClipDisabled`, the content after a scroll view hides the scroll
view's overflow where that content draws — SwiftUI's stacking (measured). A
terminal cell is drawn or not, so "where it draws" has to be said in cells.
Shipped: on each line of the later content, from its first painted cell (a
glyph other than a space; a space styled to show — a background, reverse
video, an underline, a strikethrough, an overline; or a cell an animated run
repaints) to its last; the unstyled blank
cells either side — a stack's alignment padding, an overlay's `Spacer`, an
`.offset` view's empty footprint — hide nothing, and the overflow shows there
as SwiftUI's does. The overflow is drawn by the same rule: its blank cells at
either end of a line draw nothing and take no click.

**Clicks follow the drawing.** A TUIkit tap covers its view's whole frame,
padding included, and where the overflow draws over a later view's padding the
overflow takes the click there: `Text("OK").frame(width: 12,
alignment: .leading).onTapGesture { … }` under a scroll view whose row 2 runs
down into it draws "OKw 2", and a click on the "w 2" is row 2's, while "OK" and
the padding past the overflow's last cell stay OK's. That is SwiftUI's routing
for a view with no `contentShape` — its padding is not hit at all — and the
alternative, the later view keeping its frame under the overflow, sends a
click on visible overflow text to the view beside it. With a `contentShape`
SwiftUI's later view takes that area; TUIkit has no `contentShape` yet (a
baseline gap waiting on shapes), and when it lands its shape should cut the
overflow's regions as a painted cell does. Pinned by
`laterViewPaddingClicksFollowTheDrawing`.

**The fuller version:** treat EVERY unstyled blank cell as transparent, inside
a line too, so the overflow shows between the words of a later `Text` as it
does between SwiftUI's glyphs. It is a small change (cut per run of painted
cells rather than per line, an hour or two with tests, no cost where nothing is
unclipped), but two texts interleaved cell by cell are hardly legible, which is
why it is not the default. Owner's call.

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
at every offset, as `.visible` does, and reserved lines come off the
`containerRelativeFrame` container (under `.visible` too, with or without a
behaviour). The content window is then one size at every stop: it is the page
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

### Notes on A6 that are not decisions

- `ScrollGranularity.row` did nothing `.viewAligned` cannot: on `List` and
  `Table` the two are the same mechanism, and `.row` never reached a
  `ScrollView`. It is removed, and its users (the Example's List and Table
  pages, the tests) use `.viewAligned`. `ScrollGranularity` keeps `.line`, and
  `.scrollGranularity(.line)` now takes a subtree back to line steps from a
  behaviour stated further out — which SwiftUI cannot say. The public
  `EnvironmentValues.scrollGranularity` is gone (SwiftUI has none).
- `ScrollTarget.rect` is a `CellRect`, the context's sizes `CellSize` and its
  `velocity` a `CellVector`: cells, as the rest of TUIkit's geometry. The
  velocity is the step in cells — a terminal's steps have no duration to
  measure points per second from.
- `.viewAligned` finds the rows (or columns) of the stack that is the scroll
  view's content, under a `Section`'s header, or inside the content margins —
  the reach of the scroll window. A marked stack further in (below a header
  in a `VStack`) is not found, and the view scrolls freely, as an unmarked one
  does. The anchored path (a lazy stack over 256 rows of varying height) knows
  only the rows of its band, so a step past them settles on the furthest it
  knows.
