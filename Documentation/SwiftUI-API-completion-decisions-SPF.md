# SwiftUI API completion — lane SPF (the stripe's cost in tables): new judgement calls

*Lane SPF took the table regressions the looks lane's A/B found (stripes by
default, decisions A29: table +10.7% warm, +15.1% cold; tables-scroll cold
+34 MB) back towards the build before it, 2026-10-07, without changing what is
drawn. One call came up on the way. The safe option shipped; the alternative
and its price are given — and the owner took the alternative, which has
shipped too (A-SPF-1). Numbered as the main decisions document is: A = owner
decision, B = basic shipped, C = declined.*

## A. For the owner

### A-SPF-1. A table row's bytes: one ink introducer per row, not one per cell — shipped

*`Table`'s rows — performance only, no API*

**Owner (2026-10-07): the fuller option. Shipped:** a table row states its
cells' ink once for every run of cells whose text carries no escapes of its
own, and closes it once at the run's end (`TableRowInk`), striped or not — so
a row of plain columns opens with ONE ink introducer and closes once, where it
stated and closed the ink around every cell. The blank cells between cells
are drawn in the ink, which a blank does not show. A blank selection mark (an
unselected row's) states no colour at all. A cell with escapes of its own (a
styled `Text`, a view cell's line) still closes with a reset, which its bold
or underline needs, and the ink is stated again for the cell after it — so a
styled column costs a row one more introducer, not one per cell (the rule
applied per run of cells, not per row: decisions-SPF2 B-SPF2-1). Two rows keep
the close around every run, exactly as before: a REVERSAL (under SGR 7 a
cell's ink is the colour it is filled with, so a blank's ink shows), and a
row whose ramp varies along it (painted per cell). Only `Table`: a `List`
row's content is its own views' buffer, with no row-wide ink to state. An
ANCESTOR's reversal a row cannot see — a table nested in a `List`'s cursor row
or another table's view cell, under a palette whose highlight cannot be
measured — shows the blanks' ink: decisions-SPF2 B-SPF2-2.

What is drawn did not change, but for that. `TableRowInkTests` composes 600 random rows
(plain, empty and escaped cells, a mark or none) both ways at each depth —
truecolor, 256, 16, mono — under each paint a row is finished with (none, a
still fill, a breathing fill's frame, a dim, a dim on a fill) and compares
every column's glyph and VISIBLE state (`PaintedCell.visibleState`: a blank
cell's ink and weight are not seen unless an underline, a strike or a
reversal shows them), and the column after the row; and pins why a reversal
is the exception. Across the change, 12 tables (selection, cursor row,
stripes on and off, a bold column first and in the middle, a wrapped
multi-line table, rows refusing selection, a scrolled table with its bar, a
translucent ink and a translucent fill over text, two reversal palettes) at
the four depths, each as rendered and as resolved on screen, matched the
build before cell for cell (96 renders, 0 mismatches). No test or golden
pinned a plain row's escape bytes, so none was re-baselined; the suite passed
unchanged.

Bytes in the frame's lines, `Stress --bench` (deterministic counts), the
build before and this one, stripes on (`--stripes disabled` in brackets),
warm and cold alike; and how the rows composed cold divide — a row of plain
cells, or one with a cell of escapes of its own:

| scenario | before | after | rows composed cold |
|---|---|---|---|
| `table` | 15,992 (15,567) | 9,976 (9,687) −37.6% | 35 plain |
| `table-multiline` | 11,821 (11,475) | 9,307 (9,018) −21.3% | 12 plain |
| `table-churn` | 15,289 (14,371) | 11,529 (10,696) −24.6% | 35 with a styled cell |
| `table-churn-wrapped` | 11,015 (10,686) | 9,253 (8,964) −16.0% | 12 plain |
| `table-tail` | 13,179 (12,295) | 10,923 (10,090) −17.1% | 35 with a styled cell |
| `table-api` | 15,429 (14,511) | 11,669 (10,836) −24.4% | 35 with a styled cell |
| `truncate` | 15,562 (14,372) | 11,802 (10,697) −24.2% | 35 with a styled cell |
| `tables-scroll` | 13,124 (12,816) | 9,904 (9,666) −24.5% | 200 plain |
| `tables-vstack` | 11,658 (11,372) | 8,758 (8,537) −24.9% | 33 plain |
| `megalist` | 11,995 | 11,995 (a `List`) | — |

A striped table now draws fewer bytes than any table drew before stripes;
the stripe itself costs `table` +3.0% bytes (one fill statement per striped
row). Unmeasured in time: the A/B is owed.

**First shipped, before the owner's call — a row under a still fill states
the fill once.** A table row opened every cell with its ink and closed it with a reset (`ESC[0m`), and a
persistent background has to be stated again after every reset, so a striped
row of eight columns stated its stripe nine times: +160 bytes a row at
truecolor, +17.5% bytes in a static table's frame, carried up through every
container, copied and scanned for width on every frame the table is drawn. A
row under a still fill (a stripe, a selected row's tint) now closes its runs
with SGR 39 — the terminal's ink again, the fill left in force — so the paint
states the fill once (`inkClose(under:)` then, `TableRowInk` now). Every cell is the cell it was
(`stripeStatedOnce` compares every cell's SGR state with the unstriped row's
under the stripe); a cell whose text carries escapes of its own keeps its
reset, and the stripe is stated again after it. Rows with no fill are
unchanged, byte for byte: under `--stripes disabled` the frames of six table
scenarios match the build before stripes.

Counted on `Stress --bench`, one build, `--stripes disabled` against stripes on
(deterministic counts, not timings), bytes in the frame's lines, warm:

| scenario | before | after |
|---|---|---|
| `table` | +17.5% (15,567 → 18,287) | +2.7% (→ 15,992) |
| `truncate` | +18.9% | +8.3% (a styled column restates) |
| `table-churn` | +17.0% | +6.4% |
| `table-tail` | +15.5% | +7.2% |
| `table-multiline` | +12.7% | +3.0% |
| `tables-scroll` | +12.2% | +2.4% |

**The fuller option (as proposed; shipped above):** every row, striped or
not, opens with ONE ink introducer and closes once at its end, wherever no cell carries escapes of its
own (every column but a view or a styled `Text` draws plain text): the spacing
between cells is then drawn in the ink, which a space does not show. An
eight-column row sheds about 150 bytes of escapes (207 → about 45 at
truecolor), striped or not — fewer bytes than any table drew before stripes.

**Its price (as proposed):** every table row's bytes change — not what is drawn: the same
glyphs in the same colours on the same fields — so every test and golden that
pins a plain row's escapes is rewritten, and the spacing cells' SGR state
carries the ink, which a cell-by-cell comparison sees though the screen does
not. Unmeasured in time.
