# Completing the SwiftUI API: decisions from lane SPF2

*Lane SPF2 shipped decisions A-SPF-1's fuller option, 2026-10-07: a table row
states its cells' ink once per run of plain cells rather than around every
cell (`TableRowInk`; see A-SPF-1 in
[`SwiftUI-API-completion-decisions-SPF.md`](SwiftUI-API-completion-decisions-SPF.md)
for what shipped and what it measured). It changed no public API. This file
holds the judgement calls the work reached that the decision did not already
settle, in the format of
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

### B-SPF2-2. A table nested in a reversed row shows its shared ink in the blanks between its cells

*`Table` rows drawn inside a `List` row or another table's view cell — drawing, no API*

A-SPF-1 rests on a blank cell showing no ink. Reverse video is the exception:
under SGR 7 a cell is FILLED with its ink. A table row's own reversal keeps its
closes, as A-SPF-1 says. An ANCESTOR's reversal the row cannot see: a `List`'s
cursor row, a table row around a view cell, a menu item's or a drop-down row's
highlight and a picker's segment reverse their content
(`ANSIRenderer.applyPersistentReverse`) where the palette's highlight cannot be
measured — an accent, a page or a focus wash with no RGB. They paint it over
lines already composed: a `List` renders a row's content once, whatever its
background, and paints the background over it. So a table nested in such a
row, on the row the cursor is on, shares its ink there, and its blanks show it.

What differs, pinned by `TableRowInkTests.ancestorReversalDiffersOnlyInBlankCells`
(random rows through the `List` row's own reversal paint, at four depths):
- No glyph: every cell that draws one is in the state it was.
- The spacing between two cells is filled with the cells' ink, not the
  reversal's. The colour is the same unless the nested table's ink differs
  from the palette's foreground (a `.foregroundStyle` on it, say), which is the
  reversal's ink.
- An unselected nested row's blank selection mark is filled with the
  reversal's ink. It was a block of the mark's colour.
- The gap after a nested row's ● is filled with the mark's colour. It was the
  reversal's.

Nothing differs without colour, where no ink is stated, or under a breathing
reversal's reversed frame, which drops every colour of the row's own first
(`applyReversedPair`).

**Shipped: the shared ink anyway.** The case needs a table inside a list row
or a table cell, on the cursor's row, under a palette whose highlight cannot be
measured. With the table's default ink only the mark column differs. There the
old picture was no more deliberate than the new: a blank mark, which says "not
selected", drawn as a coloured block.

**The fuller version, and its price:** tell the nested table it is drawn under
reverse video, and stop the sharing there. The reversing rows would pass that
down to their content as an internal environment value. The table would read
it once per render. For a `List`, its cursor row's content would render again
whenever the cursor arrives or leaves under such a palette. The focused,
selected row already does that for `\.backgroundProminence`
(`raiseBackgroundProminence`, in `_ListCore` and in `Table`). The fuller
version extends it to the focused row the selection does not include, in both
twins, with their memo clearing, and to the menu, drop-down and picker rows,
or leaves those documented as uncovered.

A cruder version would not need the cursor row at all: a table nested in any
list row or table cell keeps the per-cell closes. A list row says so already,
through `\.listRowEditRestrictions`. A table's view cells would need a marker
written per view cell, which every table with a view cell pays. Every nested
table would lose the saving, reversed or not, and the menus and pickers would
stay uncovered.
