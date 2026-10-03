# Completing the SwiftUI API: Wave 8a decisions (the `Table` API)

*Wave 8a's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. SwiftUI's behaviour was
measured on macOS 26.2 with an offscreen `NSHostingView`; the probe sources are
in the session notes (`w08a/probe/`), not in the repository.*

---

## A. Needs your decision

*(none yet)*

---

## B. Shipped the safe option

### B-W08a-1. A cell is one line unless its column says more

*`TableColumn.init(_:content:)` and every other initializer that takes a
`content:` closure*

SwiftUI grows each row to its tallest cell. Measured: a cell holding a
`VStack` of two `Text`s makes a 40-point row where single-line rows are 24
(`NSTableView.usesAutomaticRowHeights` is on). A long `Text` in a narrow column
does not wrap; it stays one row high and truncates.

**Shipped:** every column is one line unless its `lineLimit(_:)` — TUIkit's own
column modifier, which existed before this wave for key-path columns — allows
more. A view cell is rendered at the column's width and the limit's height, and
anything below the limit is clipped. With `.lineLimit(2)` the two-`Text`
`VStack` draws both lines, as SwiftUI's does. A `Text` cell under a limit above
1 wraps, which SwiftUI's does not; that matches what a key-path column under
the same limit has always done here.

**The fuller version** is automatic row heights: a view column with no stated
limit grows the row to the view's natural height. The price is the multi-line
row path for every table that has a view column. A single-line table answers
its size without building a row; a multi-line one measures every row below 256
rows (and samples above), and measuring a view cell means rendering it. So a
table that uses a view column for a coloured status `Text` would pay for
measuring every row, every frame, to learn that each is one line high. A middle
road: grow rows automatically only where the column's view is not a `Text` —
`VStack`s and the like, which are the cases that are actually taller.
Roughly a day, plus a measured A/B on `table` and `table-churn`.

---

## C. Declined without asking

*(none yet)*

---

## D. Deferred to other waves or lanes

*(none yet)*
