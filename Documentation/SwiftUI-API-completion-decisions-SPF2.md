# Completing the SwiftUI API: decisions from lane SPF2

*Lane SPF2 shipped decisions A-SPF-1's fuller option, 2026-10-07: a table row
states its cells' ink once per run of plain cells rather than around every
cell (`TableRowInk`; see A-SPF-1 in
[`SwiftUI-API-completion-decisions-SPF.md`](SwiftUI-API-completion-decisions-SPF.md)
for what shipped and what it measured). It changed no public API. This file
holds the one judgement call the work reached that the decision did not
already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPF2-n — needs your decision.** Nothing has shipped for these.
- **B-SPF2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPF2-n — declined.** With the reason.

## B. Shipped

### B-SPF2-1. A row with a styled cell shares the ink among its plain cells too

*`Table`'s rows — performance only, no API*

A-SPF-1 put the rule as "one ink introducer per row, wherever no cell carries
escapes of its own", and the lane's brief as "keep the per-cell path for rows
whose cells carry escapes of their own". Read per ROW, a row with one styled
cell — a bold `Text` column, a view cell — would keep stating and closing the
ink around every cell.

**Shipped: the rule per RUN of cells.** A cell with escapes of its own is
closed with a reset, as before (its bold or underline needs it), and the ink
is stated again for the next plain cell; the plain cells on either side of it
share one introducer as in any other row. A row with a bold middle column
states the ink twice, not once per cell.

Both readings draw the same picture — the safety criterion here, since the
bytes are the only thing either changes. `TableRowInkTests` composes random
rows that mix plain, empty and escaped cells (a reset-closed bold, an
underline closed with SGR 24, an italic left running, an ink of the cell's
own) and checks every column's visible state against the per-cell spelling at
four depths under five paints; the change's capture matched the build before
cell for cell for a bold column first and in the middle. So the choice was on
cost alone, and the run is the cheaper one: it is the per-cell scan the row
already makes as it writes each cell, where the per-row reading needs a scan
of every cell BEFORE the row is composed.

**The per-row reading, and its price:** a second walk over every cell's bytes
per composed row, and no saving at all on a table with a styled column —
`truncate`, `table-churn`, `table-tail` and `table-api` would keep their bytes
(every one of their rows has a styled cell: 35 of 35 composed cold), where the
run takes them down 17–24% (`truncate` 15,562 → 11,802 bytes a frame).
