# SwiftUI API completion — lane SPF (the stripe's cost in tables): new judgement calls

*Lane SPF took the table regressions the looks lane's A/B found (stripes by
default, decisions A29: table +10.7% warm, +15.1% cold; tables-scroll cold
+34 MB) back towards the build before it, 2026-10-07, without changing what is
drawn. One call came up on the way. The safe option shipped; the alternative
and its price are given. Numbered as the main decisions document is: A = owner
decision, B = basic shipped, C = declined.*

## A. For the owner

### A-SPF-1. A striped row's bytes: state the background once, not after every cell

*`Table`'s single-line rows — performance only, no API*

**Shipped: no change to how a row is spelled.** What is left of the stripe's
cost once its overhead is gone is its bytes. A table row closes every cell
with a reset (`ESC[0m`) and opens the next with its ink, and a persistent
background has to be stated again after each reset, so a striped row carries
its background once per cell plus once for the selection mark: at truecolor,
`ESC[48;2;r;g;bm` (up to 19 bytes) nine times on an eight-column row.
Counted on `Stress --bench`, the same build with `--stripes disabled` and
without (deterministic counts, not timings):

| `table`, warm, per frame | stripes off | stripes on |
|---|---|---|
| bytes in the frame's lines | 15,567 | 18,287 (+17.5%) |
| bytes scanned for width (`strippedLength`) | 37,400 | 45,560 (+21.8%) |
| bytes allocated | — | +13 KB (the lines copied up the tree) |
| allocations, rows composed or painted | equal | equal (every row served) |

That is +160 bytes per striped row and the whole of the stripe's remaining
work on a warm static table: its rows are served, nothing is composed or
painted. What it costs in time is the coordinator's to measure (the same
binary under `TUIKIT_STRESS_STRIPES=disabled` and without it).

**The fuller option:** compose a row with ONE ink introducer and no reset
between cells wherever no cell carries escapes of its own (every column but a
view column draws plain text): the spacing between cells is then drawn in the
ink, which a space does not show, and the row ends with one reset. A stripe
is then its one background sequence at the start of the line, about +20 bytes
a row rather than +160, and every row, striped or not, sheds about 150 bytes
of escapes (207 → about 45 on an eight-column row at truecolor) — fewer bytes
than a table drew before stripes.

**Its price:** every table row's bytes change — not what is drawn: the same
glyphs in the same colours on the same fields — so every test and golden that
pins a row's escapes is rewritten, and the multi-line rows want the same
treatment to stay consistent; a cell whose text carries its own escapes keeps
today's spelling (its own reset would otherwise end the row's ink), so the
composer gains a branch per cell. Unmeasured in time.
