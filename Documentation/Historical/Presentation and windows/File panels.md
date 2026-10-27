# File panels

*How `fileImporter`, `fileExporter` and `fileMover` came to TUI as panels it
draws itself, and then came to look and behave as the Mac's. Ids: O10
(refusal review), A-O10-1, B-O10-1 to 12, C-O10-1, A-FP2-1, B-FP2-1 to 8.*

## In short

The open, save and move panels are sheets TUI draws, in `TUIFilePanels`: a
folder's items in a table (folders first), a name field first in the save
panel, a question before replacing. Since 2026-10-24 they look as the Mac's
do: an enclosing-folder button, a segmented path control, list and column
views, a file-type pop-up, icons per entry (emoji, SF Symbols, or the system's
own through Kitty graphics where the app asks), and room between the parts at
larger control sizes. On Linux, where every SwiftUI `fileExporter` takes an
Apple-only type, two TUI-only exporters save a value's bytes or an `Encodable`
value on every platform (A-O10-1, answered 2026-10-27).

## How it unfolded

1. **2026-10-12, the owner on refusal review O10:** (b), panels drawn by TUI,
   adapted natively and elegantly to the terminal. Lane O10 built them on
   2026-10-19.
2. **2026-10-23, items #29 to #34:** the Mac's look. Lane FP2 built them on
   2026-10-24; the system icons need a dependency the module lacks (A-FP2-1),
   and the owner chose option 2: "Okay, go with (2)."

## The record

### A-O10-1. Linux has no save panel: `fileExporter` takes only Apple-only types

*`View.fileExporter` (every form) on Linux*

Every `fileExporter` form takes a value of an Apple-only protocol: a
`Transferable` (CoreTransferable) or a `FileDocument` (whose `FileWrapper` is
Objective-C Foundation's). Under A18 option 1 both are absent on Linux, and so
is every exporter: a Linux app can open and move files through TUI's panels
but cannot ask where to save one, though the save panel itself is portable
(it is drawn by TUI and writes with `Data.write`).

**Options.**
1. **Leave it** (shipped). SwiftUI code compiles on Apple platforms and fails
   to compile on Linux at the exporter, which is A18's rule.
2. **A TUI-only exporter of `Data`**, beside SwiftUI's:
   `fileExporter(isPresented:data:contentType:defaultFilename:onCompletion:onCancellation:)`
   on every platform — the save panel and an atomic write. About two hours
   with its tests; a TUI-specific spelling with no SwiftUI counterpart
   (allowed: kept apart from SwiftUI's names, as CLAUDE.md asks).
3. **A portable stand-in for `Transferable`**: a TUI protocol with a value's
   data and type, which `fileExporter(item:)` takes on Linux. About a day, and
   a second protocol beside Apple's that code shared with macOS must satisfy
   twice.
4. **`FileDocument` on Linux over a TUI `FileWrapper`** (a regular file, a
   directory of them, a symbolic link). About a day and a half, and a type of
   Foundation's re-declared, which turns ambiguous the day Foundation ships
   its own.

**Recommendation:** 2: the cheapest, it adds no second spelling of anything
SwiftUI has, and it is what a Linux app needs. 3 and 4 make SwiftUI source
compile on Linux, which none of the other Apple-only API does (A18).


**Answered 2026-10-27: 2, and more generic than `Data`** ("strings and maybe
anything that's `Codable`"). Built, on every platform:
`fileExporter(isPresented:contents:contentType:defaultFilename:onCompletion:onCancellation:)`
takes a `FileExportContents` — `Data` as it is, a `String` as UTF-8, or a type
of the app's own that answers per content type — and
`fileExporter(isPresented:encoding:contentType:defaultFilename:onCompletion:onCancellation:)`
takes any `Encodable` value, written as a property list where the type is one
and as JSON (sorted keys, pretty-printed) otherwise, JSON by default. Both are
the save panel and atomic write of the other exporters; an error making the
contents ends the save with it (`FileContentsExporterTests`).
### B-O10-1. The open panel is a sheet of TUI's own: a folder's items in a table

*`View.fileImporter(isPresented:allowedContentTypes:onCompletion:)` and its two
multiple-selection forms*

SwiftUI presents the system's open panel. TUI draws one (`FilePanel`), as
`ColorPickerPanel` stands in for the system colour panel: a ``Dialog`` in a
sheet of the `.page` size (96 columns, or the terminal's width, by the content
area's height), titled Open, holding

- the folder's path, the home folder written `~`, with a `..` to click to the
  folder above (since 2026-10-24 a ↰ button and a segmented path control,
  [B-FP2-1](#b-fp2-1-the-enclosing-folder-button-is--and-no-tab-stop)
  and [B-FP2-2](#b-fp2-2-the-path-is-a-segmented-picker-whose-selection-is-the-folder-shown));
- the folder's items in a `Table` — Name, Size, Date Modified and Kind, sorted
  by any of them from its header or the table's sort keys — a folder's name in
  bold and ending in `/`, as `ls -F` marks one, rather than an icon some
  terminals draw at another width (since 2026-10-24 an icon where the terminal
  is known to draw one,
  [B-FP2-7](#b-fp2-7-icons-emoji-where-the-terminal-draws-them-else-sf-symbols-else-the-slash)); in a narrow panel Kind gives way, then Date
  Modified, then Size, each where the name would have fewer than 20 cells
  (`FilePanelColumns.shown(inWidth:)`; with every column kept at its width, a
  name had four cells at 64 columns, beside eighteen of Kind); an item of a type the caller does not allow
  is dimmed (`FileEntry.isDimmed`): the cursor lands on it, as the review's
  sketch has a macOS panel's, but the selection binding refuses it and Return
  chooses nothing. Not `.selectionDisabled()`, which would also take the
  cursor past it: that needs the table's row builder, which builds every row's
  traits every frame (195 ms a frame for 20,000 items in a debug build, against
  22 for the data form);
- the hidden-files switch, Cancel and Open.

The keys are a terminal file browser's: the arrows move the table's cursor and
typing finds a name (its type-select); Return on a folder opens it and on a
file chooses it, or the whole selection when the cursor is in it; Space selects;
← or Backspace goes up (Backspace alone since the outline,
[B-FP2-5](#b-fp2-5-the-list-view-is-an-outline-its-branches-read-as-they-open)), `~` home; `/` turns the path bar into a field to type a
path in, as a shell takes one — `~/…`, absolute, or relative to the folder
shown — which Tab completes (`PathCompletion`: the one match, a folder's with
its `/`, or as much as several share) and Return goes to (a file's folder, and
to save its name); Escape cancels, or closes that field. A double-click is
Return.
Open chooses the selection's choosable items, or the folder shown where a
folder may be chosen, or opens the one folder selected when it may not (as a
macOS panel's Open does). The folder is read and sorted off the main actor
(`FileBrowser`), so a large folder never holds a frame up; the table says
"Loading…" until it is read, and why when it cannot be.

**The fuller version**, in parts:
1. **A sidebar of places** (the working directory, home, Desktop, Documents,
   Downloads, recent folders, volumes), as the review's sketch has it: about
   half a day.
2. **A list of the matches** under the go-to field when Tab cannot complete
   further, as zsh lists them: half a day.
3. **A preview** of a text file's head (an image's needs TUIBitmaps, behind a
   seam): about a day.

### B-O10-2. Folders come first, whatever the order

SwiftUI's panel sorts folders and files together (Finder's list view, unless
"Keep folders on top" is set). TUI's keeps folders first and sorts each group
by the table's order (`FileBrowser.arrange`), as terminal file managers do
(`ls --group-directories-first`, Midnight Commander, ranger): the folders are
where a keyboard user goes next. **The fuller version** is a switch between the
two orders: an hour, and a question of whether an app or the user owns it.

### B-O10-3. A panel opens on the working directory, then where it was last used

SwiftUI's panel opens on the folder the app last used (AppKit keeps it). A
TUI panel opens on the process's working directory — the folder its user
started a terminal app from, the likeliest place for the file — and after a
choice on the folder that choice was made in, for as long as the view that
presents it lives (`FilePanelPresenter`). `fileDialogDefaultDirectory(_:)`
comes before that memory, and a `fileDialogCustomizationID(_:)`'s kept folder
before both (B-O10-8). **The fuller version** remembers the last folder
app-wide and across launches with no identifier, as AppKit does: an hour, but
it is a process-wide store, which TUI keeps out of its views (no
singletons), so it would be the app's storage under a key of TUI's choosing.

### B-O10-4. Return acts on the cursor; → is not bound

TUI's lists keep their keyboard cursor apart from the selection
([V2](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md#v2-the-keyboard-cursor-is-apart-from-the-selection>)),
so a panel acts as its table does: Return is the table's primary action on the
cursor's row (or the selection when the cursor is in it), and the confirmation
button acts on the selection. A terminal file manager also opens a folder on →;
the panel cannot, because nothing outside a table reads which row its cursor is
on, and going up does not put the cursor back on the folder it came from
(Finder does), for the same reason. **The fuller version** is a `package` seam
in `ItemListHandler` that reports the cursor's row and accepts one to start
on: about half a day, in TUILists, which other lanes are working in.

### B-O10-5. Linux has a `UTType` of TUI's own

*`UTType` where UniformTypeIdentifiers is absent*

UniformTypeIdentifiers is Apple's alone, and `allowedContentTypes: [UTType]` is
in every panel's signature, so on Linux TUIFilePanels declares a `UTType` of
its own (`ContentTypes/UTType.swift`) with the members a panel's caller uses —
the identifier, the preferred extension and MIME type, `conforms(to:)`,
`supertypes`, the initializers from an identifier, an extension and a MIME
type, `exportedAs:`/`importedAs:`, `Codable` — and the static members that
name the common types. Its knowledge is a table of about ninety types read off
UniformTypeIdentifiers on macOS 15.8 (`ContentTypeTable`), which the tests hold
to Apple's on every macOS run; an unknown extension gives a dynamic type
conforming to `.data`, as Apple's does. On Apple platforms the module uses
UniformTypeIdentifiers' own `UTType` and does not re-export it, as SwiftUI does
not. Two differences from Apple's, both because there is no type database:
`UTType(exportedAs:conformingTo:)` conforms to the parent given and has no
extension (an unbundled macOS process gets neither, measured), so an app types
its own files with `UTType(filenameExtension:conformingTo:)`, which works on
every platform; and `localizedDescription` is English. **The fuller version**
reads the system's shared MIME database (`/usr/share/mime`) for the types the
table lacks: about a day, and a file format to parse.

### B-O10-6. A chosen link is the item it leads to

SwiftUI's panels resolve an alias to the item it refers to unless
`fileDialogImportsUnresolvedAliases(true)` says not to. TUI's resolve a
symbolic link the user chooses (`resolvingSymlinksInPath()`), and a link to a
folder opens as the folder. A Finder alias file (a bookmark, not a link) is a
file to TUI's panel.

### B-O10-7. `startAccessingSecurityScopedResource()` is left to Foundation

Apple's documentation for the panels asks for `startAccessingSecurityScopedResource()`
around a chosen URL's use, which a sandboxed app needs. On macOS the call works
on TUI's plain file URLs (it returns `true`, measured in an unsandboxed
process); Linux's Foundation has no such method, so code shared with Linux keeps
it in `#if canImport(Darwin)`. TUI does not add one to `URL` on Linux: a
method of its own on a Foundation type would turn ambiguous the day Foundation
adds the real one. The docs say so.

### B-O10-8. The customizations are read when a panel is presented; an identifier keeps the folder and the hidden switch

*`View.fileDialogMessage(_:)`, `fileDialogConfirmationLabel(_:)`,
`fileDialogDefaultDirectory(_:)`, `fileDialogBrowserOptions(_:)`
(`FileDialogBrowserOptions`), `fileDialogURLEnabled(_:)`,
`fileDialogImportsUnresolvedAliases(_:)`, `fileDialogCustomizationID(_:)`*

SwiftUI's documentation says what each does to the system panel on macOS, and
nothing of when a change takes effect. TUI's are one environment value
(`FileDialogCustomization`) written where the modifiers are — outside the
presenting modifier, as Apple's examples write them — and read when a panel is
presented, as `allowedContentTypes` is ("will apply the next time it is
presented"). The message is a line above the folder, the label the
confirmation button's (the title stays Open). `.includeHiddenFiles` starts the
hidden-files switch on; `.enumeratePackages` lists a package as the folder it
is; `.displayFileExtensions` does nothing, as on macOS, where Apple documents
it as inert. `fileDialogURLEnabled(_:)`'s predicate is evaluated as the folder
is read, off the main actor; an item it refuses or throws on is dimmed and
cannot be chosen, and a folder it refuses can still be opened. The predicate is
handed down in a box the modifier keeps, so the environment value compares
equal from frame to frame and the memos beneath it stay on.

`fileDialogCustomizationID(_:)` is documented to keep "the current directory,
view style, recent places, and expanded window size". A TUI panel has no
view styles or window size, so it keeps the folder it was left in and whether
it listed hidden files, whenever the user ends it (a choice or Cancel; not an
app clearing the binding), under `TUIFilePanels.<id>.directory` and
`….showsHiddenFiles` in the app's storage (the store `defaultAppStorage(_:)`
names, else `StorageDefaults.backend`). It opens there next time, in place of
the default directory, as Apple documents; a kept folder that no longer exists
is passed over. Since 2026-10-24 a panel has views, and the identifier keeps
its view too, under `TUIFilePanels.<id>.viewMode`, as it keeps its
"view style" on macOS
([B-FP2-6](#b-fp2-6-a-column-view-beside-the-list-chosen-with-a-segmented-switcher-and-kept)).
**The fuller version** keeps the sort order and recent folders
too (once there is a sidebar to show them in): an hour each.

### B-O10-9. A mover chooses a folder, moves in order, and fails on a name already there

*`View.fileMover(isPresented:file:onCompletion:)`, `fileMover(isPresented:files:onCompletion:)`
and their `onCancellation:` forms*

Apple documents what the mover is for and not how it decides. TUI's is the
open panel titled Move, choosing a folder: its files are dimmed, Return opens a
folder, and Move moves into the folder selected, or the folder shown when none
is. It opens on the folder that holds the (first) file, the natural place to
go from — until a move has been made through the view: then, as every panel
does (B-O10-3), on the folder last moved into, where the next file is likely
to go too, as a macOS panel opens on the folder used last. A customization
names another before both. The move is
`FileManager.moveItem(at:to:)`, off the main actor; `onCompletion` is called
on the main actor once it is done, after `isPresented` was cleared. The files
move in the collection's order and the first that fails ends the operation
with its error — the ones before it stay moved, since moving them back could
fail too. An item of the same name already in the folder is such an error
(`CocoaError.fileWriteFileExists`): the panel does not offer to replace it.
Moving a file to the folder it is already in is a success that moves nothing.
**The fuller version** asks to replace, as the save panel does (B-O10-10), with
the replaced item kept in the Trash where there is one: half a day, and a
question of whether a mover should ever destroy an item.

### B-O10-10. The save panel: a name field first, the type's extension added, and a question before replacing

*`View.fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)`,
`fileExporter(isPresented:items:contentTypes:onCompletion:onCancellation:)`,
`View.fileExporterFilenameLabel(_:)`*

SwiftUI presents the system's save panel. TUI's is the open panel titled
Save with a name field above the folder, as a macOS save panel has one: Save
As:, or the `fileExporterFilenameLabel(_:)`, offering `defaultFilename`, else
the item's suggested file name, else Untitled. The field takes the focus, and
Return in it saves; Tab reaches the folder (past the path control, since
B-FP2-2). A file of a type the panel saves
as is not dimmed, and Return on it puts its name in the field and the focus
back there, as a click on such a file does on macOS — it does not save. The
name typed is the file's, trimmed, and given the first type's extension when it
has none of the types' own (`SaveName.resolve`): `notes` saved as plain text is
`notes.txt`, `notes.md` stays, since Markdown is plain text, and `notes.pdf` is
`notes.pdf.txt` (macOS asks which extension to use; this panel does not ask).
A name no file can have (empty, `.`, `..`, a `/`) or that is a folder's in the
folder shown cannot be saved under: Save is disabled. Saving over a file asks
first — "“beta.txt” already exists. Do you want to replace it?", Cancel and
Replace, as macOS words it — and Replace writes over it.

`items:` saves several files, so it asks for a folder, as the mover does, and
saves each item into it under its suggested name, else Untitled (as for a
suggestion no file can have), with its type's extension — numbered as Finder
numbers a copy it keeps beside the original, `note 2.txt`, `note 3.txt`, where
the folder has the name already or a file before it in the export took it
(`ExportNames`). So an export never replaces a file, and never fails on its own
names: before the numbering, two items suggesting one name, or documents
exported twice into one folder, ended at the second file with the first
written. They are written in order and the first failure ends the operation;
the panel shows no question per file. **The fuller version** asks once whether
to replace whichever already exist or keep both, as numbered now: half a day.

### B-O10-11. A `Transferable` is exported through an item provider, on Apple platforms only

SwiftUI exports an item through its `transferRepresentation`.
`Transferable.exported(as:)` would do that, but it is macOS 15.2's and TUI
runs on macOS 14, so the item is registered with an `NSItemProvider` (macOS 13)
and loaded from it (`TransferableExport`): the provider says which types the
item exports as and the name it suggests, and loads its data as the type the
file's name names — of `contentTypes`, or of the types it exports when
`contentTypes` is empty, as SwiftUI documents. The data is written atomically,
off the main actor. The provider is made when the panel is presented and again
when it saves, from the item the latest body gave, never on every body.
`Transferable` is CoreTransferable's, which Linux does not have, so on Linux
these two forms are absent and fail to compile (decisions A18, option 1:
platform API where the feature is intrinsically the platform's). What Linux
has instead is A-O10-1's two exporters.

### B-O10-12. `FileDocument` ships on Apple platforms, to be written; nothing in TUI reads one

*`FileDocument` (+ `ReadConfiguration`, `WriteConfiguration`),
`FileDocumentReadConfiguration`, `FileDocumentWriteConfiguration`, and
`View.fileExporter(isPresented:document:…)` and `(isPresented:documents:…)` in
their `contentType:` and `contentTypes:` forms*

SwiftUI's `FileDocument` is how `DocumentGroup` reads and writes documents, and
how `fileExporter(document:)` writes one. TUI has the exporter and not the
document group, so its `FileDocument` is written and never read: the panel
calls `fileWrapper(configuration:)` — off the main actor, as SwiftUI calls it
on a background thread — with `existingFile: nil`, since an export writes a new
file, and writes the wrapper atomically (`FileDocumentWrite`); `init(configuration:)`
is a requirement for the app's own use. The configurations have no public
initializer, as SwiftUI's have none. A document is a `FileWrapper`, which is
Objective-C Foundation's, so all of it is present only where Objective-C is
(`#if canImport(ObjectiveC)`): the Apple platforms. On Linux it is absent and
fails to compile (A18, option 1). Without `contentTypes`, the document's
`writableContentTypes` (by default its readable ones) are the panel's; the
name offered is `defaultFilename`, else Untitled. `documents:` saves into a
folder as `items:` does, as Untitled, Untitled 2, …, numbered past the names
the folder has.

### C-O10-1. `ReferenceFileDocument` and the exporters that take one

A `ReferenceFileDocument` is an `ObservableObject`, a family TUI does not
have (compatibility guide §2.3), and its `snapshot(contentType:)` exists for
`DocumentGroup`'s undo and autosave, which TUI does not have either. The
`fileExporter` overloads constrained to it share their labels with the
`FileDocument` ones, so a call with a reference document fails to compile with
a type error. An app exports one through a `FileDocument` value made from its
snapshot. Parity map: `ReferenceFileDocument`. `DocumentGroup` and its
configurations stay declined in the document family: they open a window per
document, and a terminal app has one surface.

### A-FP2-1. The system's own icons, drawn with Kitty graphics, need a dependency the module does not have

*Owner item #32: "real ones via Kitty graphics where supported"*

Where the terminal takes Kitty graphics (Ghostty, iTerm2, kitty: TUI's
`Image` draws real pixels there through Unicode placeholders), a panel could
draw each item's own icon, the Finder's, scaled to its two cells. Two things
stand in the way, and each is a choice about modules:

- **Getting the icon.** `NSWorkspace.icon(forFile:)` is AppKit's, and no
  module TUI is built from imports AppKit (decisions B50: from the macOS 15
  SDK it brings SwiftUICore into every app that imports the module).
  QuickLookThumbnailing's `QLThumbnailGenerator`, asked for an `.icon`
  representation, gives the same icon as a `CGImage` and does not: it loads
  only CoreTransferable (which the module loads already), Network,
  ExtensionFoundation and Distributed (measured with `-Rmodule-loading` on
  the Xcode 26 SDK).
- **Drawing it.** An `Image` of a `CGImage` is TUIBitmaps', which the file
  panels do not depend on.

**Options.**
1. **TUIFilePanels depends on TUIBitmaps on Apple platforms** (a
   conditional target dependency) and links QuickLookThumbnailing, asks it for
   each kind's icon once (an application's for each application), keeps them,
   and draws them where `KittyGraphics.isSupported` and `terminalGraphics`
   allow, the glyphs (B-FP2-7) elsewhere. About a day with its tests. An app
   that imports the umbrella links TUIBitmaps already; one that takes the
   file panels à la carte would link it, TUIImage and CSTBImage too, and
   load QuickLookThumbnailing at launch.
2. **A TUI-specific modifier for an app to hand the panel its icons**,
   `fileDialogIcon { url, type in Image? }`, beside SwiftUI's `fileDialog`
   ones, which a module that may import AppKit fills from `NSWorkspace`
   in one call, `.fileDialogSystemIcons()`. No new dependency for the file
   panels; real icons only where an app asks. About a day, and the module that
   fills it would depend on TUIFilePanels (built in TUIAppKit, which then
   cost every app on it 29.3%; placed in its own module, below).
3. **Leave the glyphs** (shipped): emoji, SF Symbols or the slash.

**Recommendation:** 1, as the item asks for the real icons by default where
the terminal draws them, and the cost falls on an app that takes the panels
without the umbrella. 2 is the right shape if that cost is not wanted.

**Decided 2026-10-24, owner: option 2** — "Okay, go with (2)". **Built**
(lane PANELS, 2026-10-24):

- **`fileDialogIcon(_:)`** (TUIFilePanels), a TUI-specific modifier
  written beside the `fileDialog` ones:
  `.fileDialogIcon { url, type in … }`, a closure of each item's URL and
  content type returning a view, or `nil`. It is an environment value, so the
  sheet the panel is presented in inherits it, and both views read it in
  each name cell (`FilePanelNameCell`). The view is drawn in the two cells,
  one row high, an emoji icon takes (`.frame(width: 2, height: 1)`), so the
  names line up with the rows the closure answered `nil` for, which keep the
  kind's emoji, SF Symbol or none (B-FP2-7). The type is passed because the
  panel has it already, worked out off the main actor as the folder was read,
  and an icon is usually the type's: the URL alone would have the closure
  look the type up again on every row. The closure is kept in a box held in
  the modifier's `@State` and compared by the box, as `fileDialogURLEnabled`'s
  predicate is, so the memos below stay on; the price is that a row the table
  serves from its memo keeps its icon until the row changes. The module
  gains no dependency.
- **`fileDialogSystemIcons()`** (TUIFilePanelsAppKit, see "Placed in a
  module of its own" below): a `fileDialogIcon` whose views are
  `Image(nsImage:)` of `NSWorkspace`'s icon, resizable and fitted, drawn
  where an `Image` draws pictures — `KittyGraphics.isSupported` (asked as each
  row draws, since the handshake may answer after the first frame) and the
  app's `terminalGraphics`, read where the panels are presented. Elsewhere it
  answers `nil`, and the panel draws its glyphs: a two-cell icon in glyphs
  is a smudge. The icons are kept in a store of the modifier's own
  (`FileDialogSystemIcons`): `NSWorkspace` makes a new `NSImage` per call,
  and an `Image(nsImage:)` is named by its `NSImage`'s address, so an icon
  asked for afresh would be read out and sent to the terminal again every
  frame. A file's icon is its type's (`icon(for:)`), asked once per type; a
  folder's, a package's (an application's) and a symbolic link's are their
  own (`icon(forFile:)`), kept by path, as the Downloads folder or an app has
  an icon of its own; the store starts again past 512. Drawn out at 32
  points, more pixels than two cells hold on a Retina terminal. The main
  thread: `NSWorkspace` may be asked from any thread, and an `NSImage` made
  on one drawn on another; the closure runs on the main actor anyway, as the
  rows draw, which is where the store is.

So a panel draws real icons only where an app asks. Untested live: no terminal session in the lane
ran an app with the modifier; the tests pin the store, the key, the gate and
the fallback (`FileDialogSystemIconsTests`, `FilePanelIconTests`).

**Placed in a module of its own: TUIFilePanelsAppKit** (owner, 2026-10-24,
option 2 of the follow-up). Built first in TUIAppKit, `fileDialogSystemIcons()`
made that module depend on TUIFilePanels, and through it on TUIPickers,
TUIPresentation, TUITables and TUITextInput (and so the lists), so an
app that took TUIAppKit only for `Color(nsColor:)` linked the file panels
too. Measured (Xcode's Swift 6.2.4, release, `strip -o`, one executable on
TUIApp + TUIAppKit using only `Color(nsColor:)`, the TUI package by
path):

| app | with the modifier in TUIAppKit | in TUIFilePanelsAppKit |
|---|---|---|
| TUIApp + TUIAppKit, `Color(nsColor:)` only | 10,816,112 B (+2,448,912 B, +29.3%) | 8,367,216 B (main before the modifier: 8,367,200 B) |
| the same plus TUIFilePanelsAppKit, a `fileImporter` and `.fileDialogSystemIcons()` | - | 10,849,200 B |

So the module, a library product (the 31st) built on TUIAppKit,
TUIBitmaps, TUIFilePanels and TUIFoundation, holds the modifier, its
icon store and its tests (`TUIFilePanelsAppKitTests`). TUIAppKit's
dependencies are what they were before the modifier. Like TUIAppKit it
re-exports nothing, the umbrella does not re-export it, and an app writes
`import TUIFilePanelsAppKit` beside `import TUI`; it is empty off Apple
platforms. The icons' own cost is the file panels': an app that shows a file
panel at all has them.

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
folder, each a target of its own, a click on one going there. A TUI panel's
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

The size classes the item names are read as TUI's control sizes, which
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
TUI panel draws the two as a menu `Picker` under the folder
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

### B-FP2-5. The list view is an outline, its branches read as they open

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

A table worked out its outline afresh for every row on every pass, where a flat
table touches only the rows it draws: a frame of a folder of 20,000 files took
87 ms as an outline and 6.5 ms flat (debug build; 1,000 files 8.9 ms, 5,000
18 ms). So a folder of more than 5,000 rows was drawn flat, its folders opened
by Return alone, until the outline cost what the rows drawn cost. **Since
2026-10-24 (lane MISC) it does, and the limit is gone:** a
`Table(_:children:)` keeps its roots as the collection they came from
(`_TableOutlineRoots`) rather than a node per root made with the table, and
keeps its outline at its identity (`_TableOutlineCache`) while the roots are
the same array buffer and the open branches the same. A pass that changes
neither, a cursor move or a scroll, makes no outline. One that does visits only
the branches among the roots, and shares the roots' array where none is open.
Measured in a debug build, 100×40, three key-path columns, a tenth of the
rows folders, a frame after a ↓:

| Rows | Flat | Outline before | Outline after | Outline, new roots every frame |
|---|---|---|---|---|
| 1,000 | 1.56 ms | 3.48 ms | 1.66 ms | 1.99 ms |
| 5,000 | 1.49 ms | 11.00 ms | 1.64 ms | 3.48 ms |
| 20,000 | 1.57 ms | 41.81 ms | 1.66 ms | 8.67 ms |

Roots are compared by their buffer only where they cannot change under it:
the children a stored property of a value type, itself a value. Any other tree,
and the rows of `OutlineGroup` or `DisclosureTableRow` written in a `rows:`
builder, are flattened every pass as before. The A/B owed is the stress
harness's table scenarios.

### B-FP2-6. A column view beside the list, chosen with a segmented switcher, and kept

*Owner item #31: "a column view (Miller columns), with a segmented switcher as
macOS's; the current list becomes one of them. Remember the chosen mode per
app"*

Finder and a macOS panel have four views: icons, list, columns and gallery. A
TUI panel has the two a terminal draws well: the list (B-FP2-5) and the
columns (`FilePanelColumnView`). The switcher is a segmented `Picker` at the
end of the path's row, List and Columns in words, where Finder's toolbar has
icons: one Tab stop, between the path control and the folder, ← and → among
its segments, Space or Return to choose.

The column view is a column for each folder from the path control's first —
`/`, or the home folder — to the folder shown, as many of the last as fit at
24 cells each (a name of about twenty), the last taking the rest, a rule
between each two; each column is a `List` of its folder's items, read as it
shows, with no header, as Finder's has none. In each column but the last the
folder on the way is the one selected, and the column scrolls to it as its
items arrive, as Finder's do, so a folder of thousands does not open at its
top with the folder out of sight; the last column's selection is the
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
`TUIFilePanels.viewMode` for every panel of the app, and under
`TUIFilePanels.<id>.viewMode` for one with a `fileDialogCustomizationID(_:)`,
as macOS keeps a panel's "view style" under it; so a panel opens in the view
the last was left in, in this launch or a later one. **The fuller version**,
in parts: icons on the switcher's segments where SF Symbols draw (an hour);
an icon view, a grid of names under their icons, once icons draw at more than
a cell (B-FP2-7; a day); a preview column for a file, as Finder's last column
shows one (a text file's head: half a day; an image's needs TUIBitmaps).

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
machine's. **The fuller version** is A-FP2-1, built as its option 2: an app's own
icons through `fileDialogIcon(_:)`, and the Finder's through TUIFilePanelsAppKit's
`fileDialogSystemIcons()`.

### B-FP2-8. A panel browsing another machine than the user's says so, on evidence only

*Owner, 2026-10-24: "If we believe that the client is on a different machine
to the app itself, add a warning in file dialogs, something like '⚠️ You are
browsing the file system on <hostname>, not your local machine'."*

A panel browses the file system of the machine the app runs on, which over
ssh is not the one the user sits at (deviations W14), and nothing on a panel
said so. Now a line above the path does (`FilePanelRemoteNotice`): "You are
browsing the file system on *host*, not your local machine.", in the
palette's warning colour, after the alert's ⚠️ where the terminal draws emoji
chrome (`supportsEmojiChrome`) and a bold `!` elsewhere — the bare U+26A0 is a
character of text presentation that terminals draw one cell or two. It sits
on the path with no blank row between, whatever the control size
(B-FP2-3), as it is about the file system the path is in; it is one line,
cut at its end in a narrow panel, and takes no focus. *Host* is the name
`gethostname` gives, as `hostname` prints it (the one `file:` links name,
`TerminalClient.localHostName`), else `ProcessInfo`'s. The sentence is
`filePanel.remoteNotice` in TUI's seven languages.

**When.** The judgement is `SessionLocality`'s, the one TUI's clipboard
and spring-loading delay ask, given its other side
(`SessionLocality.judgement()`, `SessionLocality+Remote.swift`): **local**
where `isLocal()` finds positive evidence of the desk; **remote** on positive
evidence of a session from elsewhere *as the session is now* — inside tmux,
an attached client whose chain passes `sshd`, `mosh-server` or another
remote-session daemon (the pane's own variables were the server's when it
started, so a session started over ssh and attached at the desk is not
remote); outside it, such a daemon in this process's chain nearer than any
session keeper, or OpenSSH's variables where no keeper holds the session;
and **unknown** otherwise: inside GNU screen, zellij, dtach and the other
keepers whose clients cannot be asked, a tmux that cannot be asked, a chain
that cannot be read, a platform with no processes to walk.

The notice shows on **remote** only, not on unknown. The sentence is a
statement, and a statement wrong at the desk — every zellij user at their
own machine told they are on another — teaches the user to read past it;
a notice missing over a keeper costs what the panel cost before this one, and
the path (a home folder of another name, a server's folders) still says where
it is. It is judged as the panel is presented, off the main actor (`@concurrent`,
since inside tmux it asks tmux for its clients, a subprocess), so it appears
a moment after the panel; a test pins the session
(`EnvironmentValues.filePanelSession`, package API), as what a test shows must
not depend on how its process was started.

**`fileDialogRemoteNotice(_:)`**, a TUI-specific modifier beside
`fileDialogContentTypePicker(_:)` and taking the same `Visibility`, since two
kinds of app want otherwise and nothing else would let them: one only ever run
over ssh (a server's admin tool), whose users know where they are, writes
`.hidden`; one usually run inside a keeper on a server, which would rather
warn in doubt, writes `.visible`, which shows the line on unknown too.
`.automatic`, the default, is the rule above.

The Example's File Panels page has a switch that pins a remote session on
this machine's name, to show the line at the desk (seven languages).

**The fuller version** asks the other keepers for their clients, as tmux is
asked, turning those unknowns into answers: a different interface per keeper
(screen's `-Q`; zellij unclear; dtach and abduco have none), a subprocess
each, and the clipboard would gain from it too. The owner's answer to
D4X-LOCALITY (Open owner decisions) keeps such queries to a keeper someone
uses and asks for.
