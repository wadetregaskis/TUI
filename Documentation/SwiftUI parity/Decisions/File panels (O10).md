# Completing the SwiftUI API: lane O10's judgement calls

*Lane O10, 2026-10-19, shipped the owner's ruling on refusal review
[O10](<../Refusals re-examined, wave 17 (2026-10-03).md#o10-file-panels-from-p16--ml>)
(2026-10-12: option (b), open and save dialogs drawn by TUIkit, adapted natively
and elegantly to the terminal), in a module of its own, TUIkitFilePanels. Where
the work met a judgement call the ruling did not settle, the safe option shipped
and is written up here, in the three parts the other lanes use: A needs a
decision, B shipped the safe option (with the fuller version and its price), C
declined with a parity-map reason. SwiftUI's side is its declarations and
Apple's documentation unless an entry says it was measured; the probes are in
the session notes' `O10/probe/`.*

## B. Shipped the safe option

### B-O10-1. The open panel is a sheet of TUIkit's own: a folder's items in a table

*`View.fileImporter(isPresented:allowedContentTypes:onCompletion:)` and its two
multiple-selection forms*

SwiftUI presents the system's open panel. TUIkit draws one (`FilePanel`), as
`ColorPickerPanel` stands in for the system colour panel: a ``Dialog`` in a
sheet of the `.page` size (96 columns, or the terminal's width, by the content
area's height), titled Open, holding

- the folder's path, the home folder written `~`, with a `..` to click to the
  folder above;
- the folder's items in a `Table` — Name, Size, Date Modified and Kind, sorted
  by any of them from its header or the table's sort keys — a folder's name in
  bold and ending in `/`, as `ls -F` marks one, rather than an icon some
  terminals draw at another width; an item of a type the caller does not allow
  is dimmed and the cursor passes over it (`.selectionDisabled`);
- the hidden-files switch, Cancel and Open.

The keys are a terminal file browser's: the arrows move the table's cursor and
typing finds a name (its type-select); Return on a folder opens it and on a
file chooses it, or the whole selection when the cursor is in it; Space selects;
← or Backspace goes up, `~` home; Escape cancels. A double-click is Return.
Open chooses the selection's choosable items, or the folder shown where a
folder may be chosen, or opens the one folder selected when it may not (as a
macOS panel's Open does). The folder is read and sorted off the main actor
(`FileBrowser`), so a large folder never holds a frame up; the table says
"Loading…" until it is read, and why when it cannot be.

**The fuller version**, in parts:
1. **A sidebar of places** (the working directory, home, Desktop, Documents,
   Downloads, recent folders, volumes), as the review's sketch has it: about
   half a day.
2. **A typed path**, `/` opening a field with Tab completion: about a day.
3. **A preview** of a text file's head (an image's needs TUIkitBitmaps, behind a
   seam): about a day.

### B-O10-2. Folders come first, whatever the order

SwiftUI's panel sorts folders and files together (Finder's list view, unless
"Keep folders on top" is set). TUIkit's keeps folders first and sorts each group
by the table's order (`FileBrowser.arrange`), as terminal file managers do
(`ls --group-directories-first`, Midnight Commander, ranger): the folders are
where a keyboard user goes next. **The fuller version** is a switch between the
two orders: an hour, and a question of whether an app or the user owns it.

### B-O10-3. A panel opens on the working directory, then where it was last used

SwiftUI's panel opens on the folder the app last used (AppKit keeps it). A
TUIkit panel opens on the process's working directory — the folder its user
started a terminal app from, the likeliest place for the file — and after a
choice on the folder that choice was made in, for as long as the view that
presents it lives (`FilePanelPresenter`). `fileDialogDefaultDirectory(_:)`
comes before that memory, and a `fileDialogCustomizationID(_:)`'s kept folder
before both (B-O10-8). **The fuller version** remembers the last folder
app-wide and across launches with no identifier, as AppKit does: an hour, but
it is a process-wide store, which TUIkit keeps out of its views (no
singletons), so it would be the app's storage under a key of TUIkit's choosing.

### B-O10-4. Return acts on the cursor; → is not bound

TUIkit's lists keep their keyboard cursor apart from the selection
([V2](<../Deliberate deviations from SwiftUI.md#v2-the-keyboard-cursor-is-apart-from-the-selection>)),
so a panel acts as its table does: Return is the table's primary action on the
cursor's row (or the selection when the cursor is in it), and the confirmation
button acts on the selection. A terminal file manager also opens a folder on →;
the panel cannot, because nothing outside a table reads which row its cursor is
on, and going up does not put the cursor back on the folder it came from
(Finder does), for the same reason. **The fuller version** is a `package` seam
in `ItemListHandler` that reports the cursor's row and accepts one to start
on: about half a day, in TUIkitLists, which other lanes are working in.

### B-O10-5. Linux has a `UTType` of TUIkit's own

*`UTType` where UniformTypeIdentifiers is absent*

UniformTypeIdentifiers is Apple's alone, and `allowedContentTypes: [UTType]` is
in every panel's signature, so on Linux TUIkitFilePanels declares a `UTType` of
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
`fileDialogImportsUnresolvedAliases(true)` says not to. TUIkit's resolve a
symbolic link the user chooses (`resolvingSymlinksInPath()`), and a link to a
folder opens as the folder. A Finder alias file (a bookmark, not a link) is a
file to TUIkit's panel.

### B-O10-7. `startAccessingSecurityScopedResource()` is left to Foundation

Apple's documentation for the panels asks for `startAccessingSecurityScopedResource()`
around a chosen URL's use, which a sandboxed app needs. On macOS the call works
on TUIkit's plain file URLs (it returns `true`, measured in an unsandboxed
process); Linux's Foundation has no such method, so code shared with Linux keeps
it in `#if canImport(Darwin)`. TUIkit does not add one to `URL` on Linux: a
method of its own on a Foundation type would turn ambiguous the day Foundation
adds the real one. The docs say so.

### B-O10-8. The customizations are read when a panel is presented; an identifier keeps the folder and the hidden switch

*`View.fileDialogMessage(_:)`, `fileDialogConfirmationLabel(_:)`,
`fileDialogDefaultDirectory(_:)`, `fileDialogBrowserOptions(_:)`
(`FileDialogBrowserOptions`), `fileDialogURLEnabled(_:)`,
`fileDialogImportsUnresolvedAliases(_:)`, `fileDialogCustomizationID(_:)`*

SwiftUI's documentation says what each does to the system panel on macOS, and
nothing of when a change takes effect. TUIkit's are one environment value
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
view style, recent places, and expanded window size". A TUIkit panel has no
view styles or window size, so it keeps the folder it was left in and whether
it listed hidden files, whenever the user ends it (a choice or Cancel; not an
app clearing the binding), under `TUIkitFilePanels.<id>.directory` and
`….showsHiddenFiles` in the app's storage (the store `defaultAppStorage(_:)`
names, else `StorageDefaults.backend`). It opens there next time, in place of
the default directory, as Apple documents; a kept folder that no longer exists
is passed over. **The fuller version** keeps the sort order and recent folders
too (once there is a sidebar to show them in): an hour each.
