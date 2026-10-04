# Completing the SwiftUI API: Wave 8a decisions (the `Table` API)

*Wave 8a's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. SwiftUI's behaviour was
measured on macOS 26.2 with an offscreen `NSHostingView`; the probe sources are
in the session notes (`w08a/probe/`), not in the repository.*

---

## A. Needs your decision

### A-W08a-1. Should a table look like SwiftUI's by default — borderless and striped?

*`AlternatingRowBackgroundBehavior.automatic`, `AutomaticTableStyle`,
`TableStyle.automatic`*

`.alternatingRowBackgrounds(_:)` shipped for tables and lists alike:
`.enabled` stripes every other row with the tint a striped `ListStyle` has
always drawn (the accent at 15% over the page), `.disabled` never stripes.
`TableStyle` shipped too: `.bordered` is the rounded box every TUIkit table
has always drawn, `.inset` draws no border.

Both have an `.automatic`, and SwiftUI's macOS answers differ from TUIkit's
look. Measured on macOS 26.2: a plain SwiftUI `Table`, `.automatic` and
`.inset` alike, is an `NSTableView` of style `.inset` in a scroll view with no
border, with `usesAlternatingRowBackgroundColors` on; `.bordered` is style
`.fullWidth` in a scroll view with a line border, striped too. Stripes follow
`.alternatingRowBackgrounds(.disabled)` under either style.

Shipped: `.automatic` is bordered and unstriped — every TUIkit table keeps
its look, and SwiftUI source that names a style or asks for stripes gets
them.

**Options.**

1. **Bordered and unstriped by default** (shipped). The divergence is the two
   defaults alone. Free.
2. **SwiftUI's default: inset and striped.** Every table without a style
   changes: the border goes, which gives the rows two lines and moves every
   click target a line up and a cell left; half the rows draw a background,
   so frames grow by a background SGR per striped row (row memos keep them,
   but a churning table pays), under a tint palettes were tuned without.
   Golden and render tests that read a table's bytes need re-baselining.
   Half a day, most of it the tests.
3. **Inset by default, unstriped.** The border is where a terminal table's
   look differs most from a window's: a box around a table in a window of
   boxes reads as one more panel. The two lines it frees are worth the most
   on a short terminal. Same test cost as 2, without the stripe's.

**Recommendation:** 1. A terminal's rows are a single line of text on a fixed
grid, where a reader's eye does not drift between rows the way it does across
a wide window, and a stripe the palette did not plan for is a cost every theme
pays; the border is what tells a table from the text around it when nothing
else draws a frame. 3 is the one to take if TUIkit apps tend to put tables
inside their own bordered panels.

### A-W08a-2. Context menus on rows and on the selection — and does `onRowActivate` give way to `primaryAction`?

*`TableRowContent.contextMenu(menuItems:)`,
`TableRowContent.contextMenu(menuItems:preview:)`,
`View.contextMenu(forSelectionType:menu:primaryAction:)`*

SwiftUI gives a table's rows a context menu two ways. `.contextMenu` on a
row gives that row its own menu. `.contextMenu(forSelectionType:menu:primaryAction:)`
on the table (or a `List`) builds one menu from the set of rows it acts on: a
right-click on a selected row acts on the whole selection, on an unselected
row on that row alone, on empty space on none; `primaryAction` runs on a
double-click or Return with the same set.

TUIkit has `.onRowActivate(_:)` on `List` and `Table`, its own spelling of
`primaryAction` with one row's id where SwiftUI hands a set. A right-click on
a table row does nothing; a `.contextMenu` on a cell's view is dropped with
the cell's other mouse regions (B-W08a-3).

Nothing shipped: the three modifiers do not compile.

**Options.**

1. **Both menus on `Table` and `List`, through one menu host resolved when
   it opens; `primaryAction` replaces `onRowActivate`.** The host is
   `ContextMenuModifier`'s presentation with its items chosen at the press —
   from the row under the pointer, or Shift+F10 on the cursor row — and the
   keyboard and dismissal it already has. `onRowActivate` goes, as every
   superseded TUIkit spelling has before 1.0: call sites in Example, Stress
   and the tests move to `primaryAction`, whose set is the selection, or the
   cursor row when nothing is selected. A day and a half.
2. **The same, keeping `onRowActivate`** as a TUI-specific modifier beside
   `primaryAction`. Two ways to say one thing, which the no-shims rule exists
   to prevent. Same price, less the migration.
3. **Row menus only.** `contextMenu(menuItems:)` on rows, through the same
   host; the selection menu and `primaryAction` stay open. A day.

**Recommendation:** 1. The selection menu is the macOS idiom for tables —
Finder's and Mail's lists work that way — and `primaryAction` is what
`onRowActivate` was standing in for.

### A-W08a-3. Sections among a table's rows?

*`Section.TableRowValue`, `Section.TableRowBody` (`Section` as
`TableRowContent`), `TableHeaderRowContent` and its three members*

SwiftUI's rows can be grouped: `Section { rows } header: { Text("…") }` in a
`rows:` closure draws a header row — a view across the table's width —
above the section's rows.

TUIkit's table draws only rows that are values; every path through it — the
row window, the cursor, the selection, the row memo, the multi-line heights,
the mouse bands — counts rows by their index into the data. Nothing shipped:
`Section` in a `rows:` closure does not compile.

**Options.**

1. **Header rows.** A header is an entry of its own among the drawn bands —
   a line the full width of the row content, its view rendered there, never
   selected, stepped over by the cursor as a `.selectionDisabled()` row is —
   with the index arithmetic taught that some entries are not rows. A day,
   most of it the multi-line path and tests.
2. **Decline.** Tables that need groups use a hierarchical table, which
   ships.

**Recommendation:** 1. Grouped rows are common in macOS tables, and a
`List`'s sections already show what the header line should look like.

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

### B-W08a-3. A control in a view cell answers the keyboard, not the pointer

*`TableColumn.init(_:content:)` and every initializer that takes a
`content:` closure*

A view cell is rendered into the row's line, which carries the cell's
characters and not its mouse regions. A `Button` or `Toggle` in a cell is a
Tab stop like any other — Tab reaches it, Return or Space presses it — but a
click on it selects the row instead (measured on this branch: a click left a
`Button` in a cell unpressed; Tab then Return pressed it). A `.contextMenu` or
`.onTapGesture` on a cell's view is dropped the same way.

**Shipped:** the keyboard route, which every control has.

**The fuller version** carries each drawn cell's hit regions into the table's
buffer, offset to the cell's column and the row's band, so the control takes
the click and the row takes clicks elsewhere. The row memo would keep the
regions with the line it serves, or a row holding regions would not be kept.
Half a day, plus a measured A/B on `table` for the memo change.

### B-W08a-4. A `Group` as a table's only column statement needs the key path's root

*`Group.init(content:)` for `TableColumnContent`*

`Table(people) { Group { TableColumn("Email", value: \.email) } }` does not
type-check here — "cannot infer key path type from context" — where SwiftUI
compiles it. The builder and the `Group` initializer are SwiftUI's,
signature for signature; with a second statement beside the `Group`, or a
root on the key path (`\Person.email`), it compiles.

**Shipped:** everything else about `Group` of columns.

**The fuller version** finds which of TUIkit's other `Group` initializers
(views, rows, commands, tab content) takes the solver's attention in that
one shape and disfavours it. Half a day, most of it reducing the case.

---

## C. Declined without asking

### C-W08a-1. `OutlineSubgroupChildren`

*`OutlineSubgroupChildren`*

The content type of the `DisclosureGroup` that is SwiftUI's
`OutlineGroup<…, Subgroup>` for views — a type only ever written inside
`OutlineGroup`'s full generic signature. TUIkit's `OutlineGroup` declares
the three generic parameters that carry information and drops the two that
are always the same (`Parent` is `Leaf`; `Subgroup` is that one
`DisclosureGroup`), as its documentation records, so there is no subgroup
type for this to be the content of. Every `OutlineGroup` initializer, for
views and for table rows, is SwiftUI's; only spelling the type out by hand
differs.

---

## D. Deferred to other waves or lanes

### D-W08a-1. Dragging rows out of a table, and dropping onto them

*`TableRowContent.draggable(_:)`, `TableRowContent.dropDestination(for:action:)`,
`TableRowContent.itemProvider(_:)`, `DynamicTableRowContent.dropDestination(for:action:)`,
`DynamicTableRowContent.onInsert(of:perform:)`, `ItemProviderTableRowModifier`,
`OnInsertTableRowModifier`*

A table's own drags reorder its rows (`Table.onMove(_:)`), and a table takes
drops between its rows (`Table.dropDestination(for:action:)`, TUIkit's
spelling for a table with no `ForEach`). What is missing is a row that
carries a payload OUT — the press-drag starting a session drag with the row
as its picture rather than a reorder — a drop ONTO a row, and the insertion
spelled on a `ForEach` of rows, with its index counted within that
`ForEach`. `onInsert` and `itemProvider` are the item-provider forms, which
exist only where UniformTypeIdentifiers does, as `onDrag` and `onDrop` do.
The row-modifier plumbing they need shipped with `selectionDisabled(_:)` and
`onHover(perform:)`. A day and a half, for a follow-up lane.

### D-W08a-2. `IndexedIdentifierCollection`

*`IndexedIdentifierCollection` and its six members*

The `Data` of `ForEach(_:editActions:content:)` — a collection of a bound
collection's indices and ids. It belongs with the editable `ForEach` and
`List` initializers, which are Wave 8b's (List edit actions): built here it
would be a type nothing produces.
