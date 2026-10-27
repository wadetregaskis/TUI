# Scroll position, visibility and nested scrollables

*What a bound scroll position, `scrollTo` and the visibility observers see,
and who owns a binding when scrollables nest. Ids: A7, B-SCROLL-3,
B-SCROLL-6, C-SCROLL-1; SA-44; deviation R6. B30's anchor rules are in
[Holding the reader's place as rows change above](<Holding the reader's place as rows change above.md>).*

## In short

`onScrollTargetVisibilityChange` reports which of a stack's views show at
least the threshold of themselves along the stack's axis, from every stack
path, at the cost of nothing unless an observer is stated. A
`.scrollPosition` binding belongs to the first scrollable that reads it; one
nested in its content takes none of it, as SwiftUI measured. A row of a
vertical stack inside a purely horizontal scroll view is not sought by
`scrollTo` (declined, rare).

## How it unfolded

1. **A7** shipped `onScrollVisibilityChange`; the target-visibility reader
   was left unbuilt, and lane SCROLL built it on 2026-10-19 from what stacks
   already report (B-SCROLL-3).
2. **2026-10-19, lane SCROLL's review.** Since `List` and `Table` came to read
   a bound position (SA-44), every nested scrollable read the outer binding
   too, and each took the other's write-backs for requests. Measured in
   SwiftUI (`Tools/SwiftUIProbes/Nested scroll position/`): a nested
   scrollable neither follows nor writes. TUI now matches (B-SCROLL-6).
3. **The semantic audit's item 45 remainder** — `scrollTo` a row of a
   vertical stack inside `ScrollView(.horizontal)` — was measured (SwiftUI
   seeks it along x) and declined for now (C-SCROLL-1).

## Where it stands

Shipped as above; the fuller versions are recorded and unasked for.

## For a future reader

- **Visibility is measured along the stack's axis only**, and rows count
  whether or not the stack is marked `scrollTargetLayout()` (R6). A two-axis
  view whose row has scrolled out sideways still counts it.
- **An id only a nested scrollable holds** is not sought when the app writes
  it to the outer binding (B-SCROLL-6's fuller version, half a day).
- **C-SCROLL-1** has no parity-map entry (it is a behaviour of an existing
  method); `ScrollViewReaderTests` pins the refusal.

## The record

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
