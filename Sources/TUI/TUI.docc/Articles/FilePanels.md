# Open and Save Panels

Let people choose files and folders, and save documents, from inside the terminal.

## Overview

SwiftUI's `fileImporter` presents the system's open panel. A terminal has none, so TUI draws one, in a sheet as large as a page:

```swift
@State private var importing = false

Button("Open…") { importing = true }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json]) { result in
        if case .success(let url) = result { open(url) }
    }
```

`fileExporter` and `fileMover` work the same way. All three browse the machine the app runs on: over `ssh`, that's the remote one.

## What a Panel Shows

A panel lists a folder's items in a table, under the folder's path, with the
hidden-files switch and the buttons below. The table has Name, Size, Date
Modified and Kind columns, and sorts by any of them, folders first. Each name
follows an icon of its kind where the terminal draws emoji or SF Symbols, and a
folder is marked with a trailing `/` where it draws neither. In a narrow terminal
Kind gives way, then Date Modified, then Size, so that a name keeps its room.
The path is a path control, as on a Mac: a segment per folder from `/`, or
from the home folder, written `~`, each a target of its own — a click goes
there, and with the focus on it <kbd>←</kbd> and <kbd>→</kbd> move among the
segments and <kbd>Space</kbd> goes to the one under the cursor. At the
`.regular` and larger control sizes a blank row sets the parts apart; under
`.controlSize(.small)` the panel is as dense as it can be.

Where a panel has more than one type, a pop-up under the folder lists them:
to open, "Show:" narrows the files that can be chosen to one of them, or
widens them to All Files; to save, "Format:" chooses the type to save as and
gives the name its extension. `fileDialogContentTypePicker(.visible)` shows it
for a single type too, and `.hidden` never:


```swift
Button("Open…") { importing = true }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in … }
    .fileDialogContentTypePicker(.visible)
```

Items of a type the caller does not take are dimmed: the cursor lands on them,
but they can be neither selected nor chosen.

`fileDialogIcon(_:)` draws an app's own icon before each name, in the two
cells an emoji icon takes; its closure is given the item's URL and type, and
`nil` keeps the kind's icon. On macOS, `fileDialogSystemIcons()`, from
`TUIFilePanelsAppKit`, draws the Finder's where the terminal draws pictures (Ghostty,
kitty, iTerm2, WezTerm), and the kinds' icons elsewhere:

```swift
import TUIFilePanelsAppKit

Button("Open…") { importing = true }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in … }
    .fileDialogSystemIcons()
```

## Keys

The keys are a terminal file browser's: <kbd>↑</kbd> and <kbd>↓</kbd> move,
typing a name's first letters finds it, <kbd>Return</kbd> opens a folder or
chooses a file, <kbd>Space</kbd> selects (adding to the selection where several
may be chosen), <kbd>→</kbd> opens a folder in place and <kbd>←</kbd> closes
it, <kbd>Backspace</kbd> goes to the enclosing
folder and <kbd>~</kbd> to the home folder, and <kbd>Esc</kbd> cancels. A
double-click opens or chooses, and the ↰ button before the path goes up. <kbd>/</kbd>
turns the path into a field to type a path in, as at a shell prompt:
<kbd>Tab</kbd> completes it and <kbd>Return</kbd> goes there.

Finder's chords work too, ⌘ written as the app's `commandKey` says (⌃ by
default): <kbd>⌘2</kbd> and <kbd>⌘3</kbd> the list and the column view,
<kbd>⇧⌘P</kbd> the preview, <kbd>⌘↑</kbd> the enclosing folder and
<kbd>⌘↓</kbd> into the folder selected (or choosing the file, as Return
does), <kbd>⇧⌘G</kbd> the path field, <kbd>⇧⌘H</kbd>, <kbd>⇧⌘D</kbd>,
<kbd>⌥⌘L</kbd>, <kbd>⇧⌘O</kbd> and <kbd>⇧⌘A</kbd> home, Desktop, Downloads,
Documents and Applications where they exist, <kbd>⇧⌘N</kbd> New Folder,
<kbd>⇧⌘.</kbd> the hidden files and <kbd>⌘.</kbd> cancel. A text field keeps
a chord it reads as its own. Their Control stand-ins arrive as themselves
only under the kitty keyboard protocol — elsewhere Shift is lost on a
Control letter, ⌃2, ⌃3 and ⌃. have no keys of their own, and macOS keeps ⌃↑
and ⌃↓ for Mission Control — so the status bar names them only there, and
the typed keys above are the route every terminal has.

## List, Columns and Preview

A switcher at the end of the path's row chooses between that list and a
column view, as Finder's view buttons do: a column for each folder on the way
to the one shown, side by side, <kbd>Return</kbd> or <kbd>→</kbd> opening a
folder as a new column and <kbd>←</kbd> or <kbd>Backspace</kbd> going back to
the one before. A folder selected shows its items in a column after its own,
and going up selects the folder come from, so the way back down stays in view
until another row is chosen. The panel opens in the view the last was left in,
kept in the app's storage.

While it shows, a preview of the item selected follows the folder: in the
list a pane behind a splitter, whose divider a drag moves, or ← and → once
<kbd>Tab</kbd> reaches it; in the column view a column of its own after a
file's folder. It shows a file's opening lines, or the app's preview
(`fileDialogPreview(_:)`), then its name, kind, size and date, and "No
Selection" while there is no one item to show. The Preview button after the
view switcher, or <kbd>⇧⌘P</kbd>, opens and closes it. Until the user does,
it is open where the folder has room for it beside a list that keeps its
Size and Date Modified — 82 cells, as in a terminal 90 columns wide — and
closed in a narrower panel, such as an 80-column terminal's; the user's
choice is kept in the app's storage beside the view.

## What Happens When the Panel Closes

The callbacks come in SwiftUI's order: `isPresented` becomes `false`, then
`onCompletion` hears the choice; a cancellation clears the binding and calls
`onCancellation`, never `onCompletion`. The panel opens on the folder the app
was started from, and later on the folder of the last choice. It browses the
machine the app runs on — over `ssh`, the remote one, and then a line above
the path says so: "You are browsing the file system on *host*, not your local
machine." It shows where TUI has evidence that the user is elsewhere (an
ssh or mosh session, or a tmux client attached from one), not where it cannot
tell (inside GNU screen or zellij); `fileDialogRemoteNotice(.hidden)` turns it
off, and `.visible` shows it where TUI cannot tell as well.

## Moving and Saving

`fileMover` presents the same panel titled Move, to choose a folder, opening
on the folder that holds the file and later, as every panel does, on the
folder of the last choice: Move moves the file (or files) into the folder
selected, or the one shown, and
`onCompletion` hears the new URLs, or the error — an item of the same name
already in the folder is one.

`fileExporter` presents the panel titled Save, with a name field above the
folder, offering `defaultFilename`, else the item's suggested name, else
Untitled; Return in
the field saves, a name without the type's extension is given it, and saving
over a file asks first. The item is exported through its
`transferRepresentation` — on Apple platforms, since `Transferable` is
CoreTransferable's — and `fileExporterFilenameLabel(_:)` labels the field.

```swift
.fileExporter(isPresented: $exporting, item: note, contentTypes: [.plainText]) { result in
    if case .success(let url) = result { print("Saved to \(url.path)") }
}
```

On Apple platforms a `FileDocument` exports the same way, written through its
`fileWrapper(configuration:)`:

```swift
.fileExporter(isPresented: $exporting, document: TextFile(text: draft), contentType: .plainText,
              defaultFilename: "Draft") { result in … }
```

## Customizing the Panel

The `fileDialog` modifiers customize the panel, written outside the modifier
that presents it, as with SwiftUI:

```swift
.fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
    …
}
.fileDialogMessage("Choose the PDFs to combine")
.fileDialogConfirmationLabel("Combine")
.fileDialogDefaultDirectory(documents)
.fileDialogBrowserOptions(.includeHiddenFiles)
.fileDialogCustomizationID("combine")
```

The message is a line above the folder and the label the confirmation
button's. `.includeHiddenFiles` starts the hidden-files switch on and
`.enumeratePackages` opens a package as a folder. `fileDialogURLEnabled(_:)`
dims, and refuses, the items whose URL its predicate rejects, and
`fileDialogImportsUnresolvedAliases(true)` hands back a chosen link rather
than what it leads to. With a `fileDialogCustomizationID(_:)` the panel keeps
the folder it was left in, and its hidden-files switch, in the app's storage,
and opens there next time, launches later included.

## File Types

`allowedContentTypes` takes UniformTypeIdentifiers' `UTType` on Apple
platforms (import that module where you name the type, as beside SwiftUI);
where the framework does not exist, `TUIFilePanels` declares a `UTType` of
its own with the same spelling and the common types, so the code compiles
unchanged on Linux. Type a file of your app's own by its extension with
`UTType(filenameExtension:conformingTo:)`, which works everywhere.

## See Also

- <doc:Presentation>
