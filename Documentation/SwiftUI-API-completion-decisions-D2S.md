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
