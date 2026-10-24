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

### B-FP2-1. The enclosing-folder button is ↰, and no Tab stop

*Owner item #29: "replace `..` with a real button, e.g. ↰"*

The `..` before the path, a piece of text that took a click, is now a button
(`FilePanelPathBar`): `↰` (U+21B0) in the link style — the glyph in the accent
and in its one cell, lifted under the pointer, dimmed at the root, where there
is no folder above. `↰` is of Neutral East Asian width, one cell in every
terminal, and a new chrome glyph, so it is width-corpus row
`chrome_enclosing_folder`, waiting for a probe run as `chrome_cross` does
(Terminal compatibility survey, "A file panel's ↰").

It is not a Tab stop, as a macOS panel's toolbar buttons are not in its key
view loop, and a click on it leaves the focus where it was. Its key is
Backspace in the folder's rows (and ← too, until the list view became an
outline whose ← is its own, B-FP2-5). macOS's ⌘↑ cannot be
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

### B-FP2-4. A file-type pop-up shows where a panel has several types, or the app asks

*Owner item #33: "an optional file-type filter pop-up, with All Files"*

SwiftUI has no API for it. AppKit's prior art is two: an app adds an "Enable:"
pop-up to an `NSOpenPanel` as its accessory view (TextEdit, Office), which
narrows the files the panel takes to one kind or widens them to all; and
`NSSavePanel.showsContentTypes` (macOS 15) shows a "Format:" pop-up of its
allowed types, whose choice is the type saved and the name's extension. A
TUIkit panel draws the two as a menu `Picker` under the folder
(`FilePanelTypePopUp`):

- **To open,** "Show:": All Supported Files — the caller's types together, as
  asked for, and where it starts — then each type, by the system's
  description ("PDF document"), then a rule and All Files. A type narrows the
  files that can be chosen to it, All Files takes every file whatever its
  type; the rest are dimmed, as a type the panel does not take always was
  (`FileChoiceRule.fileTypes`). The folder is read again for it. Folders are
  not filtered: a panel that chooses folders still does.
- **To save,** "Format:": each type the panel saves as, and no All Files. The
  choice is the name's: the pop-up shows the type the name's extension names,
  and choosing one gives the name that type's extension (`SaveName.renamed`:
  `draft.txt` saved as Markdown is `draft.md`), as macOS's rewrites the name.
  So the type a name names is now the one written even where it conforms to
  another of the types too: `notes.md` among plain text and Markdown is
  written as Markdown, where it was written as plain text, the first it
  conformed to.

It shows where the panel has more than one type, as the item asks.
`fileDialogContentTypePicker(_:)`, a TUI-specific modifier written beside
SwiftUI's `fileDialog` ones, says otherwise: `.visible` shows it for one type
too (that type, and All Files), `.hidden` never. A panel that takes every
type, a mover's, and one that chooses a folder to save into have nothing to
filter, and show none. **The fuller version** remembers the choice under a
`fileDialogCustomizationID(_:)`, as the folder is kept: an hour.

### B-FP2-5. The list view is an outline, its branches read as they open, up to 5,000 rows

*Owner item #31: "a list (outline view: disclosure triangles, Name / Date
Modified / Size / Kind columns, sorting)"*

The table of a folder's items is now an outline, as Finder's list view is
(`Table(_:children:…)`): every folder has a triangle, a file none, and → opens
a folder where it is, a click on the triangle too; ← closes it, or goes from
an item to its folder's row. The
columns, the order (each branch sorted as the folder is, folders first) and
the dimming are the table's as they were. A branch is read when it opens, not
before: until it is, its one row says "Loading…", and that row's appearing is
what asks for the read (`FileBrowser.loadFolder`, off the main actor, kept
until the folder shown is read again). Items of open branches are chosen as
the folder's own are, and a selection may span them: Return on one chooses it,
Open chooses them all. Return on a folder still opens it as the folder shown.

So the outline has ←, which went to the enclosing folder: that is Backspace's
alone in the list view now (and the ↰ button's), as ⌘↑ is on a Mac, where ←
in an outline is the outline's. The status bar says ⌫.

A table works out its outline afresh for every row on every pass, where a flat
table touches only the rows it draws: a frame of a folder of 20,000 files took
87 ms as an outline and 6.5 ms flat (debug build; 1,000 files 8.9 ms, 5,000
18 ms). So a folder of more than 5,000 rows is drawn flat
(`FilePanel.outlineRowLimit`), its folders opened by Return alone. **The
fuller version** makes `_TableOutline` (TUIkitTables) cost what the rows drawn
cost — kept from pass to pass while the rows and the expansion are the same,
or flattened lazily, a window at a time — and drops the limit: about a day, in
a module other lanes work in; an A/B (the stress harness's table scenarios
over an outline) is owed with it.

