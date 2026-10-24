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

### B-FP2-2. The path is a segmented picker whose selection is the folder shown

*Owner item #30: "a real segmented path control (distinct, hoverable segments)"*

macOS draws a folder's path as a path control (`NSPathControl`): a segment per
folder, each a target of its own, a click on one going there. A TUIkit panel's
path is a segmented `Picker` of the folders from the root, `/`, or from the
home folder, written `~` as a shell prompt writes it, to the folder shown —
whose selection is the folder shown, so a choice is a move
(`FilePanelPathBar`). So each segment is lifted under the pointer, the folder
shown is drawn as the chosen segment, a click goes there, and the keys are a
segmented control's, measured on macOS 15.8 for that control: one Tab stop, ←
and → move a cursor among the segments, wrapping, and Space or Return goes to
the one under it. macOS's path control is no Tab stop unless Full Keyboard
Access is on; this one is, since a keyboard would otherwise climb a level at a
time or type the path. The focus starts in the folder's rows to open, and
in the name field to save (`defaultFocus`), not on the path, the first control
in reading order; to save, Tab reaches the path before the folder.

Narrow, the path keeps what it can, in this order (`FilePanelPathSegment.fitting`):
every segment; the first, a `…` and as many of the last as fit, the `…`
going to the deepest folder it stands for, as a macOS path control collapses
its middle; the `…` and the folder shown; and that with the folder's name
shortened in the middle. A path of two keeps the first rather than a `…` that
stands for it alone.

**The fuller version**, in parts: a folder icon in each segment, once the panel
draws icons (B-FP2-4's glyphs, at a cell each): an hour. A pop-up of a
segment's own folders on a long press, as macOS's pop-up style offers: half a
day, and a menu per segment.

### B-FP2-3. The room between the panel's parts follows the control size

*Owner item #34: "size classes; in regular/large, space between list, path
control, name field"*

The size classes the item names are read as TUIkit's control sizes, which
`ControlSize`'s own documentation calls "the size classes, like regular or
small" and which say how much chrome a control draws: at `.regular` and
`.large` a blank row parts the panel's message, name field, path and folder,
as a macOS panel's margins set them apart; at `.extraLarge` two; at `.small`
and `.mini` none, as dense as the panel was (`FilePanel.spacing`). A compact
vertical size class — an app's word that the terminal is short — keeps it
dense at every size, the folder's rows being what a short panel needs most.
So a panel at the default size has a blank row more between each part than it
had. **The fuller version** reads the terminal's height as well, and spends
blank rows only where the folder keeps, say, ten rows: an hour, and a second
rule beside the size's for the same thing.

