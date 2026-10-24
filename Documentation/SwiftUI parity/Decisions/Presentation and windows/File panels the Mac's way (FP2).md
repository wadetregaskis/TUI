# File panels the Mac's way: lane FP2's judgement calls

*Lane FP2, 2026-10-24, carried out the owner's items #29 to #34 of 2026-10-23
for the file panels lane [O10](<File panels (O10).md>) built: a real
enclosing-folder button, a segmented path control, list and column views,
icons per entry, a file-type pop-up, and room between the panel's parts at the
larger control sizes. Where the work met a judgement call the items did not
settle, the safe option shipped and is written up here, in the three parts the
other lanes use: A needs a decision, B shipped the safe option (with the fuller
version and its price), C declined with a parity-map reason. macOS's side is
its Finder and open and save panels (15.8) unless an entry says otherwise.*

## B. Shipped the safe option

### B-FP2-1. The enclosing-folder button is ↰, no Tab stop, and its keys are ← and Backspace

*Owner item #29: "replace `..` with a real button, e.g. ↰"*

The `..` before the path, a piece of text that took a click, is now a button
(`FilePanelPathBar`): `↰` (U+21B0) in the link style — the glyph in the accent
and in its one cell, lifted under the pointer, dimmed at the root, where there
is no folder above. `↰` is of Neutral East Asian width, one cell in every
terminal, and a new chrome glyph, so it is width-corpus row
`chrome_enclosing_folder`, waiting for a probe run as `chrome_cross` does
(Terminal compatibility survey, "A file panel's ↰").

It is not a Tab stop, as a macOS panel's toolbar buttons are not in its key
view loop, and a click on it leaves the focus where it was. Its keys are the
ones the panel had: ← and Backspace in the folder's rows. macOS's ⌘↑ cannot be
offered: a key press never carries Command (`KeyPress.modifiers`), which
decision B-D1K-1 is to change. **The fuller version** binds ⌘↑ once Command
reaches `onKeyPress`, where the terminal reports it: a line, after B-D1K-1.
