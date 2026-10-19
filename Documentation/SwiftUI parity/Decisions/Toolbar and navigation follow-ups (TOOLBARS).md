# Completing the SwiftUI API: decisions from lane TOOLBARS

*Lane TOOLBARS finished the toolbar work the owner's decision A28 started
([`Toolbars and opt-in chrome design study, A28 (2026-10-04).md`](<../Design studies/Toolbars and opt-in chrome design study, A28 (2026-10-04).md>),
§10 steps 6 and 7, and the customisation family §3.3 left as a gap), the
fuller sheet hosting [`Toolbars and opt-in window chrome (D5C).md`](<Toolbars and opt-in window chrome (D5C).md>)
priced as B-D5C-3, and A21's link in a collapsed split view. Where that work
reached a judgement call the owner's answers did not settle, the safe option
shipped and is written up here, in the format of
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

## B. Shipped the safe option

### B-TOOLBARS-1. `ToolbarTitleMenu()` with no items leaves the title as it is

*`ToolbarTitleMenu.init()`*

SwiftUI documents the empty form as "a toolbar title menu where actions are
inferred from your app's commands" — `CommandGroupPlacement.saveItem`,
`.printItem` and their kind. TUIkit's commands are the menu bar's
(TUIkitCommands, refusal review O13), which TUIkitChrome, where the title is
drawn, cannot see; and a command drawn in a second place has its keyboard
shortcut registered twice.

**Shipped:** the empty form compiles and leaves the title a title: no caret,
nothing to open. `ToolbarTitleMenu { … }` and `.toolbarTitleMenu { … }`, with
items, make the title a pull-down of them.

**The fuller version** has TUIkitCommands hand the window's chrome the File
menu's document groups (`newItem`, `saveItem`, `importExport`, `printItem`)
as a view, drawn by the empty title menu in the registration-free way the
menu bar draws a closed menu — so each command's key stays registered once.
About half a day; worth it if an app ported from iPadOS leans on the inferred
menu.
