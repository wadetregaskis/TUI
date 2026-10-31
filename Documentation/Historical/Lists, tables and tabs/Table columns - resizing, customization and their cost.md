# Table columns: resizing, customization and their cost

*How a table's columns are resized, reordered and hidden — by the header's
gaps, a header menu and a keyboard mode — and what doing it for every table
cost and won back. Ids: B45 (column customization), B-D4T-7,
B-LISTSPERF-1 to 3.*

## In short

Every column resizes from its header's gaps and from the column keys; the
header menu and reordering need a customization binding and an identifier, as
SwiftUI's do; the keyboard's gestures are a mode. Lane LISTS made every table's
columns resizable (2026-10-18) at +10.2% on `table`; lane LISTSPERF took that
back without taking anything away (2026-10-19).

## For a future reader

- **The resize handler is the table's own**, not regions per gap
  (B-LISTSPERF-1); a later change that gives each gap a region brings the cost
  back.

## The record

### B-D4T-7. Column gestures need a customization binding and an identifier; the keyboard's are a mode

*`TableColumnCustomization`, `TableColumnCustomizationBehavior`,
`disabledCustomizationBehavior(_:)`, `RowAction.customizeColumns`
(decisions B45)*

**Measured on macOS 15.8** (a SwiftUI `Table` in an `NSHostingView`, its
outline view driven directly): a table bound to a customization allows column
reordering, one without does not, and both allow resizing; the header's
right-click menu exists only with a binding, and reads "Hide “Alpha”", a
divider, then every column in the order shown with a check while visible — a
column with no `customizationID` checked and disabled; a resize is recorded as
the column's `currentWidth` in the customization's encoding (SwiftUI records
every customizable column's width, from the first layout), and a move as a
`columnOrder` that names a column with no identifier by a transient entry;
emptying the customization does not shrink a resized column back.

**Shipped:** the three gestures — the header menu (right-click or Ctrl-click),
dragging a title to move its column (live, as the pointer crosses the
neighbour far enough that the swap does not swap back), dragging the gap after
a title to resize within the column's declared bounds — on a table bound to a
customization, for columns with an identifier, each taken away by the
column's `disabledCustomizationBehavior`. The width goes into the
customization and its encoding, as the owner expected and SwiftUI does; it is
recorded only once the user resizes, so the value still records "what has
been changed and nothing else", and an emptied customization puts the
declared widths back. The last shown column cannot be hidden from the menu.

From the keyboard the gestures are a mode rather than six chords: **Ctrl-K**
picks a column (drawn in the selected-row fill in the header); while one is
picked, ←/→ pick another, `<`/`>` (or Shift-←/→) move it, `-`/`+` resize it,
Return opens the column menu on it (the mode's own: closing it returns to
the mode, and hiding the picked column picks the first one left), and
Escape (or Ctrl-K) lets it go — the
shape of Ctrl-R's row move, for the same reason: a column has to be chosen
before anything can be done to it, and keys inside a mode need no modifier a
terminal might not send. Only Ctrl-K is a rebindable `RowAction`; free Ctrl
letters are too few for three pairs.

**Since 2026-10-18 (lane LISTS), the fuller version's resizing:** a table
without a binding, and a column without an identifier in one with, resizes
as any other — its gap dragged, or `-`/`+` in the column mode, which Ctrl-K
now opens on every table with a header — the width kept in the table's own
state (`ItemListHandler.transientColumnWidths`, by the column's identifier
or its place in the column closure, `_TableColumnSpec.place`, which a
condition before it does not move) for as long as the table is shown, as
SwiftUI keeps it in the outline view. Reordering and the column menu still need a binding and an
identifier, as measured. The price, paid by every table: a state lookup per
frame (`applyKeptWidths`). The header's gaps were a region and a handler
each, registered every frame on tables that had none; since lane LISTSPERF
the table's own handler, whose region covers the header line, takes them,
finding the gap at the press. A/B owed: tables, tables-scroll.

### B-LISTSPERF-1. The header's gaps are the table's own handler's, not regions of their own

*`Table`'s header — performance, and how the pointer's hover sees a gap*

Since lane LISTS a drag on the gap after any column's title resizes it, on
every table with a header. Each gap was a hit-test region with a handler of
its own, registered on every frame: on a table a value memo serves
(`tables-vstack`, `tables-scroll`), replayed and moved on every frame too —
47 handlers a frame on `tables-vstack`, where GLASS had 15.

**Shipped:** the table's own handler, whose region already covers the header
line and in front of which nothing lies at a gap, takes a left press on a
gap — looked up against the frame's column widths at the press — and the
drag and release that follow it. No region or registration is made for the
gaps; handlers per frame are GLASS's again (2 on `table`, 15 on
`tables-vstack`). A press anywhere else on the header, the wheel and the
secondary click go where they went before. What a pointer can tell apart:
the gaps are no longer a hover target of their own, so moving between a gap
and the rest of the table fires no enter and exit; nothing listened to them,
but each asked the run loop for a frame.

**The alternative:** keep the gaps as regions — one handler for all of them,
each gap a piece of the header line's one region (`HitTestRegion.clipped`,
which this lane shipped first, 4dcf951e7) — so that a gap stays a hover
target of its own, should something come to want that (a resize cursor, a
highlight on the gap under the pointer). Its price: a registration, a closure
and a region per gap on every frame of every table with a header; measured
on `tables-vstack`, `replayEffects` 4.1% → 6.1% and `renderValueMemoized`
6.7% → 8.7% of the frame. The terminal has no resize cursor to show, so
nothing wants it today.

### B-LISTSPERF-2. A pass's table is still a copy of the table, for the cascade's flag

*`Table`'s text cascade (lane LISTS, 65c5c0295) — performance*

Whether the style cascade says anything to a cell's text is asked once a
pass and kept on the table (`cascadesCellText`), because asking it per cell
was a dictionary lookup in the environment for every cell. Keeping it means
each entry point (`sizeThatFits`, `renderToBuffer`) lays the table out from
a prepared copy of itself, which GLASS made only for a table with rows to
resolve or size.

**Shipped:** one copy per entry point, made once with every step on it
(`prepared(_:)`), where LISTS made up to four and asked every question
twice. What is left of `prepared(_:)` on `table` is 0.2–0.3% of the frame:
the copy, the kept column widths' state lookup (B-LISTSPERF-3) and the
cascade's question.

**The fuller version:** no copy where nothing needs preparing — the flag
carried some other way: worked out in `Table.body` (an `@Environment` read
of the cascade and the claimed control kind, handed to `_TableCore` as it is
built), or answered into a per-pass box the cells read. The first costs every
`Table` an environment property resolved on every body, which would have to
be measured against the copy it saves; the second, an allocation a pass,
which is what the copy costs. About an hour and an A/B on `table` and
`tables-vstack`; worth it only if the A/B still finds `table` above GLASS.

### B-LISTSPERF-3. The widths a table keeps are looked up once a pass, in a state lookup of their own

*`ItemListHandler.transientColumnWidths` (decisions B-D4T-7) — performance*

A width a user gives a column that no customization records is kept by the
table's handler, and applied to the columns before they are laid out
(`applyKeptWidths(_:)`): a `StateStorage` lookup per entry point, on every
table, resized or not — about 0.1% of a frame of `table`.

**Shipped:** that lookup, once per entry point (LISTS made it twice).

**The fuller version:** fold it into the handler fetch the render already
makes (`resolveHandler`). The widths are needed before the column widths are
worked out, which comes before the handler is fetched on the render path and
without it on the analytic measure path, so the fetch would move up front
and the measure path would fetch the handler too. About two hours; the
saving is the one lookup.
