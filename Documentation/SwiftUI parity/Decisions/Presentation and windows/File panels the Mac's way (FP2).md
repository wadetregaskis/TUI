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

## A. Needs a decision

### A-FP2-1. The system's own icons, drawn with Kitty graphics, need a dependency the module does not have

*Owner item #32: "real ones via Kitty graphics where supported"*

Where the terminal takes Kitty graphics (Ghostty, iTerm2, kitty: TUIkit's
`Image` draws real pixels there through Unicode placeholders), a panel could
draw each item's own icon, the Finder's, scaled to its two cells. Two things
stand in the way, and each is a choice about modules:

- **Getting the icon.** `NSWorkspace.icon(forFile:)` is AppKit's, and no
  module TUIkit is built from imports AppKit (decisions B50: from the macOS 15
  SDK it brings SwiftUICore into every app that imports the module).
  QuickLookThumbnailing's `QLThumbnailGenerator`, asked for an `.icon`
  representation, gives the same icon as a `CGImage` and does not: it loads
  only CoreTransferable (which the module loads already), Network,
  ExtensionFoundation and Distributed (measured with `-Rmodule-loading` on
  the Xcode 26 SDK).
- **Drawing it.** An `Image` of a `CGImage` is TUIkitBitmaps', which the file
  panels do not depend on.

**Options.**
1. **TUIkitFilePanels depends on TUIkitBitmaps on Apple platforms** (a
   conditional target dependency) and links QuickLookThumbnailing, asks it for
   each kind's icon once (an application's for each application), keeps them,
   and draws them where `KittyGraphics.isSupported` and `terminalGraphics`
   allow, the glyphs (B-FP2-7) elsewhere. About a day with its tests. An app
   that imports the umbrella links TUIkitBitmaps already; one that takes the
   file panels à la carte would link it, TUIkitImage and CSTBImage too, and
   load QuickLookThumbnailing at launch.
2. **A TUI-specific modifier for an app to hand the panel its icons**,
   `fileDialogIcon { url, type in Image? }`, beside SwiftUI's `fileDialog`
   ones, which TUIkitAppKit (that may import AppKit) fills from `NSWorkspace`
   in one call, `.fileDialogSystemIcons()`. No new dependency for the file
   panels; real icons only where an app asks. About a day, and TUIkitAppKit
   would depend on TUIkitFilePanels.
3. **Leave the glyphs** (shipped): emoji, SF Symbols or the slash.

**Recommendation:** 1, as the item asks for the real icons by default where
the terminal draws them, and the cost falls on an app that takes the panels
without the umbrella. 2 is the right shape if that cost is not wanted.

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
Backspace in the folder's rows, and ← in the column view (and in the list
view too, until it became an outline whose ← is its own, B-FP2-5). macOS's ⌘↑ cannot be
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
draws icons (B-FP2-7's glyphs): an hour. A pop-up of a
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
(`FilePanelListView.outlineRowLimit`), its folders opened by Return alone. **The
fuller version** makes `_TableOutline` (TUIkitTables) cost what the rows drawn
cost — kept from pass to pass while the rows and the expansion are the same,
or flattened lazily, a window at a time — and drops the limit: about a day, in
a module other lanes work in; an A/B (the stress harness's table scenarios
over an outline) is owed with it.

### B-FP2-6. A column view beside the list, chosen with a segmented switcher, and kept

*Owner item #31: "a column view (Miller columns), with a segmented switcher as
macOS's; the current list becomes one of them. Remember the chosen mode per
app"*

Finder and a macOS panel have four views: icons, list, columns and gallery. A
TUIkit panel has the two a terminal draws well: the list (B-FP2-5) and the
columns (`FilePanelColumnView`). The switcher is a segmented `Picker` at the
end of the path's row, List and Columns in words, where Finder's toolbar has
icons: one Tab stop, between the path control and the folder, ← and → among
its segments, Space or Return to choose.

The column view is a column for each folder from the path control's first —
`/`, or the home folder — to the folder shown, as many of the last as fit at
24 cells each (a name of about twenty), the last taking the rest, a rule
between each two; each column is a `List` of its folder's items, read as it
shows, with no header, as Finder's has none. In each column but the last the
folder on the way is the one selected; the last column's selection is the
panel's. The keys:

- ↑ and ↓ move in a column, typing finds a name, Space selects;
- Return on a folder opens it as a new column, and the keys follow into it,
  as they do when a click on a folder in an earlier column goes there (a file
  clicked there is selected in its folder);
- ← or Backspace closes the last column and goes back to the one before, its
  cursor still on the folder it opened — a column keeps its identity, and so
  its cursor, while it shows;
- → is not bound: Finder's → opens the folder under the cursor, and a list's
  cursor is not something the panel can read (B-O10-4, whose fuller version,
  a `package` seam in `ItemListHandler`, would bind it).

The view is kept in the app's storage (`@AppStorage`, the store
`defaultAppStorage(_:)` names, else `StorageDefaults.backend`) under
`TUIkitFilePanels.viewMode` for every panel of the app, and under
`TUIkitFilePanels.<id>.viewMode` for one with a `fileDialogCustomizationID(_:)`,
as macOS keeps a panel's "view style" under it; so a panel opens in the view
the last was left in, in this launch or a later one. **The fuller version**,
in parts: icons on the switcher's segments where SF Symbols draw (an hour);
an icon view, a grid of names under their icons, once icons draw at more than
a cell (B-FP2-7; a day); a preview column for a file, as Finder's last column
shows one (a text file's head: half a day; an image's needs TUIkitBitmaps).

### B-FP2-7. Icons: emoji where the terminal draws them, else SF Symbols, else the slash

*Owner item #32: "file/folder icons — SF Symbols/emoji elsewhere, some
diversity by type"*

A row's name is drawn after an icon of its kind (`FileKind`): a folder, an
application, an alias (a symbolic link, whatever it leads to, as Finder badges
one), a PDF, an image, audio, video, an archive, code, text, or any other
document — eleven, each told apart from the rest, by the type's conformances
with the narrower first (source code is text too). Which glyphs depends on the
terminal (`FilePanelIcon`):

- **Emoji** where the terminal draws emoji chrome legibly
  (`supportsEmojiChrome`, the allowlist the search field's magnifier and the
  emoji toggles use): 📁 🚀 🔗 📕 🌄 🎵 🎬 📦 📜 📝 📄. Each is a single
  scalar of default emoji presentation and East Asian Wide, two cells with no
  variation selector, the width corpus's `default_emoji` class.
- **SF Symbols** where they draw (the SF Symbols font installed, on Apple
  platforms): `folder`, `app`, `arrowshape.turn.up.right`, `richtext.page`,
  `photo`, `music.note`, `film`, `archivebox`,
  `chevron.left.forwardslash.chevron.right`, `text.document`, `document`.
- **None** elsewhere: a folder's name ends in `/`, as it did, `ls -F`'s mark
  and the icon-less terminal file managers' (Midnight Commander's). The item
  asked for "a plain text glyph" here; a glyph per kind in a terminal's own
  repertoire would be a new chrome glyph each, of the box-drawing and
  geometric blocks, read as icons by nobody, so the slash stays, which is
  what a terminal user reads as a folder.

With an icon, a folder's name has no slash, as Finder's has none. Typing still
finds a row by its name, past the icon. An emoji keeps its own colours, so a
dimmed row's icon is not dimmed. Both views draw the icons.

Each listing works out an item's kind as it reads the folder, off the main
actor, once per type: 20,000 files of ten types took 1.32 s to list with the
kinds worked out per file, 106 ms of it the kinds, and 1.29 s with each
type's kind kept (debug build). A test pins the icons
(`EnvironmentValues.filePanelIcons`), as the SF Symbols' font is the
machine's. **The fuller version** is A-FP2-1.

