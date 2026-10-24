# SwiftUI API completion — lane LISTSPERF (what lane LISTS cost every table): new judgement calls

*Lane LISTSPERF took back, on 2026-10-19, what lane LISTS (298d18b10) had
added to every table's frame — the coordinator's A/B put `table` at +10.2%
and `tables-vstack` at +11.2% over GLASS (01d6da6a9) — without taking back
anything LISTS shipped: every column of every table still resizes from its
header's gaps and from the column keys (decisions B-D4T-7), and a table's
cells still take the text cascade (`.bold()`, `.textCase(_:)` and
`.style(.control(.table))` on the table). The calls that came up on the way
are below. The safe option shipped; the alternative and its price are given.
Numbered as the main decisions document is: A = owner decision, B = basic
shipped, C = declined.*

## B. Basic option shipped

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
