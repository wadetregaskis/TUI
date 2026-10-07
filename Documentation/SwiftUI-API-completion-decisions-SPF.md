# SwiftUI API completion — lane SPF (the stripe's cost in tables): new judgement calls

*Lane SPF took the table regressions the looks lane's A/B found (stripes by
default, decisions A29: table +10.7% warm, +15.1% cold; tables-scroll cold
+34 MB) back towards the build before it, 2026-10-07, without changing what is
drawn. One call came up on the way. The safe option shipped; the alternative
and its price are given. Numbered as the main decisions document is: A = owner
decision, B = basic shipped, C = declined.*

## A. For the owner

### A-SPF-1. A table row's bytes: one ink introducer per row, not one per cell

*`Table`'s rows — performance only, no API*

**Shipped: a row under a still fill states the fill once.** A table row opens
every cell with its ink and closed it with a reset (`ESC[0m`), and a
persistent background has to be stated again after every reset, so a striped
row of eight columns stated its stripe nine times: +160 bytes a row at
truecolor, +17.5% bytes in a static table's frame, carried up through every
container, copied and scanned for width on every frame the table is drawn. A
row under a still fill (a stripe, a selected row's tint) now closes its runs
with SGR 39 — the terminal's ink again, the fill left in force — so the paint
states the fill once (`Table.inkClose(under:)`). Every cell is the cell it was
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

**The fuller option:** every row, striped or not, opens with ONE ink
introducer and closes once at its end, wherever no cell carries escapes of its
own (every column but a view or a styled `Text` draws plain text): the spacing
between cells is then drawn in the ink, which a space does not show. An
eight-column row sheds about 150 bytes of escapes (207 → about 45 at
truecolor), striped or not — fewer bytes than any table drew before stripes.

**Its price:** every table row's bytes change — not what is drawn: the same
glyphs in the same colours on the same fields — so every test and golden that
pins a plain row's escapes is rewritten, and the spacing cells' SGR state
carries the ink, which a cell-by-cell comparison sees though the screen does
not. Unmeasured in time.
