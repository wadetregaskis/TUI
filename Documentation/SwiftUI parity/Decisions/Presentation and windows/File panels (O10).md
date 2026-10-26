# Completing the SwiftUI API: lane O10's judgement calls

*Lane O10, 2026-10-19, shipped the owner's ruling on refusal review
[O10](<../../Refusals re-examined, wave 17 (2026-10-03).md#o10-file-panels-from-p16--ml>)
(2026-10-12: option (b), open and save dialogs drawn by TUI, adapted natively
and elegantly to the terminal), in a module of its own, TUIFilePanels. Where
the work met a judgement call the ruling did not settle, the safe option shipped
and is written up here, in the three parts the other lanes use: A needs a
decision, B shipped the safe option (with the fuller version and its price), C
declined with a parity-map reason. SwiftUI's side is its declarations and
Apple's documentation unless an entry says it was measured; the probes are in
the session notes' `O10/probe/`.*

## A. Needs a decision

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

## B. Shipped the safe option

### B-O10-1. The open panel is a sheet of TUI's own: a folder's items in a table

*`View.fileImporter(isPresented:allowedContentTypes:onCompletion:)` and its two
multiple-selection forms*

SwiftUI presents the system's open panel. TUI draws one (`FilePanel`), as
`ColorPickerPanel` stands in for the system colour panel: a ``Dialog`` in a
sheet of the `.page` size (96 columns, or the terminal's width, by the content
area's height), titled Open, holding

- the folder's path, the home folder written `~`, with a `..` to click to the
  folder above (since 2026-10-24 a ↰ button and a segmented path control,
  [B-FP2-1](<File panels the Mac's way (FP2).md#b-fp2-1-the-enclosing-folder-button-is--and-no-tab-stop>)
  and [B-FP2-2](<File panels the Mac's way (FP2).md#b-fp2-2-the-path-is-a-segmented-picker-whose-selection-is-the-folder-shown>));
- the folder's items in a `Table` — Name, Size, Date Modified and Kind, sorted
  by any of them from its header or the table's sort keys — a folder's name in
  bold and ending in `/`, as `ls -F` marks one, rather than an icon some
  terminals draw at another width (since 2026-10-24 an icon where the terminal
  is known to draw one,
  [B-FP2-7](<File panels the Mac's way (FP2).md#b-fp2-7-icons-emoji-where-the-terminal-draws-them-else-sf-symbols-else-the-slash>)); in a narrow panel Kind gives way, then Date
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
[B-FP2-5](<File panels the Mac's way (FP2).md#b-fp2-5-the-list-view-is-an-outline-its-branches-read-as-they-open>)), `~` home; `/` turns the path bar into a field to type a
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
([V2](<../../Deliberate deviations from SwiftUI.md#v2-the-keyboard-cursor-is-apart-from-the-selection>)),
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
([B-FP2-6](<File panels the Mac's way (FP2).md#b-fp2-6-a-column-view-beside-the-list-chosen-with-a-segmented-switcher-and-kept>)).
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
should have instead is A-O10-1.

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

## C. Declined

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
