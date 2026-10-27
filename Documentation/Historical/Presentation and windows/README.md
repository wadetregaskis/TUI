# Presentation and windows: how it came to be

One story per subject: sheets, windows, file panels, help, compact adaptation, dialogs and pickers. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Compact size classes: popovers, split views and the tab popover](<Compact size classes: popovers, split views and the tab popover.md>) | Size classes are the app's to set (B3).  |
| [Dialogs and pickers](<Dialogs and pickers.md>) | A critical alert or confirmation dialog starts with the ⚠️ emoji, as asked.  |
| [File panels](<File panels.md>) | The open, save and move panels are sheets TUI draws, in `TUIFilePanels`: a folder's items in a table (folders first), a name field first in the save panel, a question before replacing. **Open:** a question never answered. |
| [Help and tooltips on every view](<Help and tooltips on every view.md>) | Any view's help shows when the pointer rests on it; `.tooltips(.always)` shows every panel at once, avoiding one another. **Owed** work is listed in it. |
| [Sheets: sizes, detents, live sheets and the page behind](<Sheets: sizes, detents, live sheets and the page behind.md>) | A sheet sizes to its content up to `.form`'s 25 rows, with no minimum; a sheet with two or more detents can be resized, and one that enables background interaction is a live sheet, docked as a pane beside a page that stays live.  |
| [Windows: several scenes on one surface](<Windows: several scenes on one surface.md>) | Secondary scenes are full-surface covers stacked over the main one (the owner's O9 (b), 2026-10-12). **Open:** a question never answered. |
