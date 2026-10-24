# The menu bar behaves as macOS's, and says what it offers: decisions for review

*The MENUBAR lane's companion to
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
in its format, for the owner's items of 2026-10-23 on the menu bar (#1, #2,
#3–#8, #25–#27), following [`The menu bar (O13).md`](<The menu bar (O13).md>).
2026-10-24.*

- **A. Needs your decision.** One: whether TUIkit offers a standard command
  set for display options (A-MENUBAR-1).
- **B. Shipped the safe option.** See below, each with its fuller version and
  price.
- **C. Declined without asking.** None.

## A. Needs your decision

### A-MENUBAR-1. A standard command set for display options

*Owner item #6: "maybe a default TUIkit View menu with display options (theme
submenu, toggles…)".*

The Example's View menu now has them, written in the Example: Palette ▸ (a
`Picker` over the built-in presets, as a submenu, the current one checked),
Border Style ▸ (a `Picker` over the built-in appearances) and Text Styling ▸
(two `Toggle`s). Whether TUIkit should offer the same to every app, as SwiftUI
offers `ToolbarCommands` and `SidebarCommands`, is a public API question:

1. **Nothing in TUIkit** (today). An app writes its own, as the Example does —
   twenty lines with `Picker`s over `PaletteRegistry.all` and
   `AppearanceRegistry.all`. Free.
2. **`DisplayCommands()`, a TUIkit-only standard set** adding View ▸ Palette ▸
   and View ▸ Border Style ▸, acting on the app's palette and appearance
   managers (`\.paletteManager`, `\.appearanceManager`) as the `t` and `a` keys
   do. The catch: an app that holds its palette itself and applies it with
   `.palette(_:)` or `.theme(_:)` at the scene — the Example does, to edit it
   on the Theme page — overrides the manager, so the set's Palette would do
   nothing visible there; it would have to be documented as acting on the
   managers only, or take a binding. Half a day with tests.
3. **2, plus a binding form**, `DisplayCommands(palette: $palette)`, for an
   app that holds its palette. A day.

**Recommendation: 2.** It is what `t` and `a` already do, offered where a Mac
reader looks for it, and an app that holds its own palette, as the Example
does, writes its own, as the Example now shows.

## B. Shipped the safe option

### B-MENUBAR-1. Find… and Find Next are validated; Cut, Copy and Paste are not

*`TextEditingCommands`, the scene's own `pasteboard` group*

**Shipped:** Edit ▸ Find… and Find Next are disabled unless the focus is in a
`TextEditor` that can find, through a package focused value the editor
publishes (`FocusedValues.textFinding`), as AppKit validates them against the
responder chain. The other standard items that act on the focused view were
already validated: Show/Hide Sidebar and Inspector (no panel), Undo and Redo
(nothing to undo), Close Window (may not close).

**The fuller version:** validate Cut, Copy and Paste the same way, enabled only
where something focused takes ⌘X, ⌘C, ⌘V — and, as on a Mac, Cut and Copy only
with a selection. What takes them is spread out: `TextField`, `SecureField` and
`TextEditor` (each with its own selection), `onCopyCommand` / `onCutCommand` /
`onPasteCommand`, `copyable` / `cuttable` / `pasteDestination`, a `List` or
`Table` selection with those, and the screen selection, which Copy reaches
from anywhere. Each would publish what it can do this frame (a small
`OptionSet` focused value), and the screen selection would be read beside it.
About a day with tests; the Edit menu then reads like a Mac's, where today
Cut, Copy and Paste on a page with nothing to take them press a key nothing
takes.

### B-MENUBAR-2. About says what the scene states, then the Info.plist, then the process

*`Scene.aboutPanel(applicationName:applicationVersion:version:copyright:credits:)`, TUIkit-only*

**Shipped:** a scene modifier, named after AppKit's About panel option keys
(SwiftUI has no spelling: a Mac app says more about itself through AppKit's
`orderFrontStandardAboutPanel(options:)`). Each value left `nil` comes from
the main bundle's Info.plist — `CFBundleDisplayName` then `CFBundleName`,
`CFBundleShortVersionString`, `CFBundleVersion`, `NSHumanReadableCopyright`,
the keys macOS's panel reads — and the name, failing both, from the process.
The alert shows the name, "Version 1.2 (42)" (the build only where it differs),
the credits and the copyright. The name titles the app's menu and its About
and Quit items too. A modifier rather than an environment value of the app's:
it is the scene's to say, once, and it reaches the chrome-drawn menu bar
through the scene's environment. The Example states its name, TUIkit's version
and its authors.

**The fuller version:** credits as `Text` (styled, with a link), an
application icon drawn from the app's image (Kitty graphics where the terminal
has them), and a Credits.rtf / Credits.html read from the bundle as macOS does.
Half a day for `Text` credits; the icon waits on a decision about what an
app's icon is in a terminal.

### B-MENUBAR-3. A Help menu of TUIkit's own: Show Tooltips and Show All Tooltips (⌥?)

*The scene's own `help` group; `TooltipState.showsTooltips`, `showsAllTooltips`*

**Shipped:** every app with a menu bar has a Help menu, as on macOS, holding
Show Tooltips — a check, on by default; off, the scene's root draws tooltips
`.never` — and Show All Tooltips (Hide All Tooltips while they show), which
draws them `.always`: every view's help at once, placed together. Its key is
the help key with Option, `⌥?`, by the owner's rule of one key per purpose and
a modifier on `?` (B-HELP-2's answer); Control-? is Backspace in every legacy
encoding, so Option is the one modifier a terminal delivers, and a text field
lets it through where it types `?`. Each item is disabled while no view on the
screen has help (counted per walk, replayed for a memoized view), except to
take back its own choice. The choices are published at the root, so a
subtree's own `tooltips(_:)` wins inside it, and the root's trigger is in the
render loop's environment snapshot, so a change redraws memoized views.

**The fuller version:** keep the two choices across launches (the person's,
like the toolbar's configuration), and a "help browse" mode for the keyboard —
step from panel to panel of the `.always` view, the focus following — which
B-HELP-2 left open. Half a day for persistence; the browse mode a lane-day with
its focus design.

### B-MENUBAR-4. The Example's menus: Go, the View submenus, and a customizable top bar

*`ExampleCommands`, `ContentView`*

**Shipped:** the page navigation moved out of File into a Go menu, as Finder's,
and File went with it (nothing else belongs there; TUIkit draws a standard menu
only when something is in it). Main Menu shows Escape, the key the pages
already go back with, and is disabled on the main menu; Previous Page is ⌃B
and Next Page ⌃T. Finder's ⌘[ and ⌘] cannot be had: ⌃[ is Escape's byte and ⌃]
a byte TUIkit does not read; and of the Control letters a terminal sends as
themselves, A, C, D, F, G, K, N, O, R, S, V, X and Z are bound already (a list's
or table's row keys, the clipboard and undo, a text editor's find, the Menus
page's ⌘ shortcuts), and E is a text editor's end of line. B and T are only a
text control's Emacs chords, which give way to an app's shortcut. View gains
Palette ▸, Border Style ▸ (disabled while the Theme page's custom border is in
force) and Text Styling ▸, the submenu, checked-item, picker-as-submenu and
disabled-item examples the owner asked for. The top bar is a
`toolbar(id:)`, so Customize Toolbar… is enabled and offers the F2 and F3
actions as buttons, which start out of the bar.

**Not done: "Customise" (en-GB).** TUIkit's strings have one English table, in
US spelling, as Apple's base English is; an en-GB table of the few words that
differ (Customise, Colour, …) would need the localization service to fall back
from a regional table to its language's, which it does not. Half a day; worth
it with a second regional language to justify the mechanism.

**The fuller version:** decode ⌃] (`0x1D`) so Next Page can be Finder's ⌘], with
⌃B for Back. An hour with a survey row, but ⌃[ stays Escape, so the pair would
not match.
