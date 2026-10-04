# Completing the SwiftUI API: Wave 8a decisions (the `Table` API)

*Wave 8a's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. SwiftUI's behaviour was
measured on macOS 26.2 with an offscreen `NSHostingView`; the probe sources are
in the session notes (`w08a/probe/`), not in the repository.*

---

## A. Needs your decision

### A-W08a-1. Should a table stripe its rows by default?

*`AlternatingRowBackgroundBehavior.automatic`*

`.alternatingRowBackgrounds(_:)` shipped for tables and lists alike:
`.enabled` stripes every other row with the tint a striped `ListStyle` has
always drawn (the accent at 15% over the page), `.disabled` never stripes.
`.automatic` defers to the component, and SwiftUI documents what the
components do: a macOS `Table` stripes by default, a `List` does not.
Measured: a plain SwiftUI `Table` on macOS 26.2 has
`usesAlternatingRowBackgroundColors` on.

TUIkit's table has never striped. Shipped: `.automatic` leaves it so.

**Options.**

1. **Unstriped by default** (shipped). Every existing table keeps its look,
   and SwiftUI source that asks for stripes gets them. The divergence is the
   default alone. Free.
2. **Striped by default, as SwiftUI's macOS table is.** Every table changes:
   half its rows draw a background, so frames grow by a background SGR per
   striped row (row memos keep them, but a churning table pays), and the
   accent tint sits under every other row of tables whose palettes were
   tuned without it. Golden and render tests that read a table's bytes need
   re-baselining. Half a day, most of it the tests.
3. **Striped by default under one table style.** SwiftUI ties the stripes to
   the `.inset` style's look; when `TableStyle` lands, `.inset` could stripe
   and `.bordered` (TUIkit's look today) not, with the default style deciding
   which a plain table gets. Folds into the table-style work.

**Recommendation:** 1, revisited with 3 when `TableStyle` ships. A terminal's
rows are a single line of text on a fixed grid, where a reader's eye does not
drift between rows the way it does across a wide window, and a stripe the
palette did not plan for is a cost every theme pays.

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

### B-W08a-2. Column customization is the app's to change; no gesture changes it yet

*`TableColumnCustomization` (all members), `TableColumnCustomizationBehavior`,
`TableColumnContent.customizationID(_:)`, `.defaultVisibility(_:)`,
`.disabledCustomizationBehavior(_:)`, the eight `columnCustomization:`
initializer keys*

On macOS a table bound to a `TableColumnCustomization` lets the user reorder
columns by dragging their headers, resize them by dragging the dividers, and
show or hide them from the header's context menu (measured: column reordering
is enabled only with a binding; resizing always). The binding records what the
user did, so it can be persisted.

**Shipped:** the whole vocabulary, and everything that does not need a
gesture. A column's default visibility hides it, with or without a binding —
measured, SwiftUI does the same. A bound customization shows and hides columns
by identifier, reads `.automatic` for anything nothing stated, encodes and
decodes (in TUIkit's own encoding: SwiftUI's is private), and persists through
`@SceneStorage` or `@AppStorage` with no default written, as Apple's sample
does. A stated column order, which only decoding can produce today, is
applied. `disabledCustomizationBehavior(_:)` is recorded with the column; with
no gesture to disable it takes nothing away, and it never restricted the app
in SwiftUI either.

**The fuller version** is the three gestures, each gated by the disabled
behaviors:

- **Visibility**: a column menu from the header — a right-click (or
  Ctrl-click, see the context-menu notes) and a key chord on the focused table
  — listing the identified columns with a mark, toggling one. Half a day: the
  menu engine and the row chords exist.
- **Reorder**: drag a header, and a chord pair to move the focused column
  left and right, which first needs a focused-column notion the table does not
  have. A day.
- **Resize**: drag the gap between two headers within the column's bounds, and
  a chord pair. A day, plus a decision on whether a resized width persists in
  the customization (SwiftUI's does).

---

## C. Declined without asking

*(none yet)*

---

## D. Deferred to other waves or lanes

*(none yet)*
