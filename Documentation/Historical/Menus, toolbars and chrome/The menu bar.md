# The menu bar

*How a terminal app got macOS's menu bar: SwiftUI's `Commands` drawn on the
window's top row, the order keys are offered in, the standard command sets,
About, Help, display options, and the keys that open it. Ids: O13 (refusal
review), A28's answers, B-O13-1 to 8, C-O13-1 to 3, A-MENUBAR-1,
B-MENUBAR-1 to 4, O13-KEYS.*

## In short

`CommandMenu`, `CommandGroup`, the placements and `.commands` are drawn on the
window's top row, in `TUICommands`. A page's own shortcut on a command's key
is asked first; nothing works from behind a modal; Alt-letter opens a menu.
The standard command sets are those a terminal app has; About reads the scene,
then the Info.plist, then the process; a Help menu of TUI's own shows tooltips;
`DisplayCommands` adds View ▸ Palette and Border Style.

## How it unfolded

1. **2026-10-04 and 12, the owner:** a full menu bar, the app header
   optional, any combination of the two (refusal review O13; A28's answers).
   Lane O13 built it.
2. **Lane MENUBAR** made it behave as macOS's; the owner ruled A-MENUBAR-1
   option 3 (a standard set for display options), built by lane MENUCMDS.
3. **2026-10-23, O13-KEYS:** the owner asked for other macOS routes, per-menu
   jump keys and earlier CLI systems, and a proposal; **2026-10-26:** the
   recommendation — F10 enters bar mode, mnemonics only then, and F10 and
   fn-F10 measured. **Not yet built.**

## Where it stands

Shipped; **owed:** O13-KEYS (F10 bar mode, mnemonics, the measurements).

## The record

### B-O13-1. The commands are a module of their own, the vocabulary with them

*`TUICommands`*

The lane brief asked for a new leaf module over the app, chrome and menu
modules. REFO's sketch offered a cut: the vocabulary (`Commands`,
`CommandMenu`, `CommandGroup`, the placements) in TUIMenus, by the module
plan's topic rule ("menus and commands"), and the scene modifiers and the bar
in the leaf.

**Shipped:** everything in the leaf, `TUICommands`, built on TUIApp. The
vocabulary has no client without `Scene.commands(content:)`, which needs
`Scene`; split, the two modules would have shared `package` surface (the walk
that turns commands into menus) for no app that uses one without the other.
The bar's drop-downs are TUIFoundation's menu engine, so the module needs
nothing of TUIMenus. The run loop and the chrome host reach the bar through
hooks that name nothing of it (`SceneCommandsDeclaration`,
`WindowChromeState.menuBar`), so an app that declares no commands links none of
it. Like TUIApp, it has no Windows build.

**The fuller version** is REFO's cut, if a library of commands that builds
without TUIApp ever matters (for the Windows port, say): about half a day,
moving five files and widening the walk to `package`.

### B-O13-2. The page's own shortcut on a command's key is asked first

*`KeyboardShortcutRegistry.registeringCommands(_:)`*

The menu bar is drawn after the page, so that a command reading the focused
view's `@FocusedValue` reads this frame's; under the registry's rule, the last
registration on a key wins, which would have given every key the page and a
command share to the command. AppKit documents the other order — a key
equivalent goes to the key window's views, and to the main menu only if none
takes it — but the probe could not make its window key on this machine, and
with no key window the main menu took the key. So SwiftUI's own order is not
measured.

**Shipped:** the documented order. While the commands register, a key the page
already registered this frame keeps its page action (deviation W7).

**The fuller version** is a measurement: run the probe's `keys` case from a
session that can activate an app (a person at the Mac, or an app bundle
launched with `open`), five minutes. If SwiftUI asks the menu first, the change
is the one line that keeps the page's registration.

### B-O13-3. No command works from behind a modal

*`_WindowChromeHost.menuBarBuffer`*

On macOS the menu bar stays usable while a sheet is up. Here a modal (a sheet,
an alert, a cover) holds the input, and every channel of the page behind it is
inert: its focus, its keys, its shortcuts, the top bar's items.

**Shipped:** the menu bar follows that rule: drawn inert under a modal, no menu
opens, by key or by a click on a title, a menu open when the modal comes up
closes, and no command's key fires (deviation W8). The modal's own keys work.

**The fuller version** lets commands work over a modal the way macOS's do,
reading the modal's focused values: a command that names no focused value (a
New, a Quit) would act from behind the sheet. About half a day, and a choice
about whether that surprise is wanted in a one-window terminal app.

### B-O13-4. A click while a menu is open closes it; the pointer does not move between menus

*`_MenuBarCore+Opening.swift`*

On macOS, once a menu is open, moving the pointer onto another title opens that
menu, and a click on another title opens it. The bar's open menu is a pop-up
`Menu`'s presentation, whose dismiss backdrop covers the window and takes the
next press, so a click anywhere — another title included — closes the menu, and
a second click opens the other one. The keyboard moves between menus (Left,
Right, Alt and a letter).

**Shipped:** that. A click on a title opens its menu on the press; a click while
any menu is open closes it.

**The fuller version** is a backdrop with a hole: the bar's row stays the bar's
while a menu is open, a press on another title switches to it, and the pointer
resting on another title switches as on macOS (motion is reported already, for
hover). About half a day, in the shared dismiss backdrop (`DropdownMenu`), which
a `Picker` and the context menus also use, so it wants their tests run too.

### B-O13-5. Alt opens the menu whose title starts with the letter, and no letter is underlined

*`_MenuBarCore.TitleRow.mnemonics`*

The owner's answer gives Alt and a letter; which letter is a choice. Windows
underlines a mnemonic in each title, chosen per menu; macOS has none.

**Shipped:** a title's first letter, when it is an ASCII letter, lowercased;
where two titles share one, the first menu has it (the other is one Right away).
The app's menu has none: its title is the app's name, whose first letter would
take another menu's (the Example's "Example" took Edit's E), and F10 opens it,
as the first menu.
No letter is drawn underlined: Apple Terminal, iTerm2 and Ghostty send Alt and
a letter only when set to (none is by default), and an underline promising a
key that does nothing on most Macs would mislead. The chords are framework
defaults, so an app's own ⌥ shortcut on a letter wins, and a focused text field
keeps the Alt chords it edits with.

**The fuller version** gives each menu a distinct letter (the first unclaimed one
of its title, as Windows assigns them) and underlines it where the terminal is
known to send Option as Meta, which the host cannot be asked. About two hours;
the underline waits on knowing the host's Option setting.

### B-O13-6. The scene's own commands do what their keys do, and are not validated

*`SceneOwnCommands`*

On macOS a `WindowGroup` brings its own commands — the app's menu, the Edit
menu's Undo, Redo, Cut, Copy, Paste, Delete and Select All, and more — and
AppKit enables each by asking the responder chain whether anything would take
it. TUI has the keys those commands stand for, and no responder chain.

**Shipped:** the commands a terminal app has, each the way to a key the app
already has, so the menu bar is a way to them and never the only one: About
(an alert), Quit (the quit key's quit, through the status bar — not the key
pressed, which a focused text field would type), Undo and Redo (the app's
`UndoManager`, disabled with no step to take), Cut, Copy and Paste (⌘X, ⌘C, ⌘V
through `commandKey`). An item that acts on what has the focus presses its key
once the frame that closed the menu has handed the focus back (`KeysAfterFrame`,
a new hook the run loop drains after each frame): while the menu is open it
holds the focus and the keyboard.
Each item shows its key (`keyboardShortcutHint`), which
it does not bind again. Cut, Copy and Paste are always enabled; choosing one
with nothing to take it does what the key does then (rings the bell). No Delete
or Select All: a terminal app has no key for either that every text control
takes.

**The fuller version** validates them: before drawing, ask the focused view
whether its focus path or its own key handling would take ⌘X, ⌘C or ⌘V
(`KeyEventDispatcher.declaresFocusPathBinding` already answers it for the
commands; a text field's own copy would need asking too), and disable the item
that nothing would. About half a day. Separately, a disabled item shows no key
(as every disabled menu row in TUI does today, `KeyboardShortcutRegistrar.claim`),
where macOS greys the key with the item: a one-line change to every menu, so
not made here.

### B-O13-7. Settings… waits for O9

*`CommandGroupPlacement.appSettings`*

The lane brief maps `.appSettings` to `openSettings`, which lane O9 (`Settings`
scenes) is building in parallel; it is not on this lane's base.

**Shipped:** the group is empty by default, as the app menu's other groups are.
An app's `CommandGroup(replacing: .appSettings)` (or `after:`) puts its own
Settings item there today.

**The fuller version** is one case in `SceneOwnCommands.items(for:)` once O9
lands: a "Settings…" item, on SwiftUI's ⌘, (through `commandKey`), that calls
the environment's `openSettings` when the scene has a `Settings` scene. About
an hour, with its test. The Window menu's groups (`windowList`,
`singleWindowList`, `windowArrangement`) wait on O9 (b) likewise.

**Shipped (2026-10-18, lane O9):** Settings… on ⌘, where the app declares a
`Settings` scene, and the Window menu's three groups for an app that can open
more than one window — [B-O9-9](<../Presentation and windows/Windows: several scenes on one surface.md#b-o9-9-the-window-menu-lists-the-windows-and-closes-the-one-in-front>).

### B-O13-8. The standard command sets, as a terminal app has them

*`SidebarCommands`, `InspectorCommands`, `ToolbarCommands`, `TextEditingCommands`*

What each adds on macOS was measured (the probe's `std` case): Show Sidebar
(⌃⌘S) and Show Inspector (⌃⌘I, disabled with no inspector) in the View menu's
sidebar group, Show Toolbar (⌥⌘T) and Customize Toolbar… in its toolbar group,
and in Edit the Find, Spelling and Grammar, Substitutions, Transformations and
Speech submenus.

**Shipped:**
- `SidebarCommands`: Show Sidebar / Hide Sidebar, titled by the window's first
  split view's sidebar, pressing the split view's own ⌃⌘S after the menu
  closes (so the split that holds the focus is toggled first, as the chord
  does); disabled with no split view, where macOS leaves it enabled and doing
  nothing.
- `InspectorCommands`: Show Inspector / Hide Inspector on ⌃⌘I, for the window's
  first inspector; disabled with none, as on macOS. Under `.commandKey(.control)`
  ⌃⌘I is ⌃I, which a legacy encoding sends as Tab, so the key works only under
  the kitty keyboard protocol and the menu is the way there.
- `ToolbarCommands`: Hide Toolbar / Show Toolbar on ⌥⌘T, the person's choice
  over the top bar (`WindowChromeState.topBarHiddenByCommand`), whatever the
  page's `.toolbarVisibility` says, until Show Toolbar; disabled while the page
  places nothing in the top bar. No Customize Toolbar…: `toolbar(id:)` is a gap.
- `TextEditingCommands`: Find… and Find Next, pressing a `TextEditor`'s own
  keys, ⌃F (⌘F's Control chord, which the editor yields to its find bar) and
  ⌃G (B81, 2026-10-19; Find… pressed ⌃G until then).

**The fuller version:** submenus, which TUI's menus do not have (a `Menu`
inside a menu draws as a control on its row), so Find's own submenu (Find
Next, Find Previous, Use Selection, Jump to Selection) and Transformations
(upper, lower, capitalised, which a text control could do) — about a day with
submenus, which every menu would then have. Spelling and Speech have no
counterpart.

### C-O13-1. `onCommand(_:perform:)`

A command sent up the responder chain by an Objective-C `Selector`. TUI has
no responder chain and no Objective-C runtime on Linux; what reaches the focused
view is SwiftUI's own focus-path commands (`onMoveCommand`, `onExitCommand`,
`onDeleteCommand`, `onCopyCommand`, …). Declined since refusal review O13
(CONFIRM). `parity-map.json`: the `View.onCommand*` family.

### C-O13-2. `ImportFromDevicesCommands`

Importing photos and scans from nearby devices (Continuity Camera): a service
macOS offers a window it can present a camera picker over, which a terminal app
has neither. `parity-map.json`: `notImplemented`.

### C-O13-3. `TextFormattingCommands`, until the rich-text editor

Its Font and Text submenus format a rich-text selection. TUI's text controls
hold plain text until A42's rich-text `TextEditor` lands, so the commands would
do nothing (rule 2): they fail to compile instead. With A42 they are the bar's
like `TextEditingCommands`, and they carry the formatting chords: the owner
ruled on 2026-10-23 (A42-Q8) that a rich-text editor has none of its own, and
that an app gets ⌘B and ⌘U (Ctrl-B and Ctrl-U under `.commandKey(.control)`)
by declaring these commands (decisions A42).
`parity-map.json`: `notImplemented`, with that reason.

### A-MENUBAR-1. A standard command set for display options (ruled: option 3)

*Owner item #6: "maybe a default TUI View menu with display options (theme
submenu, toggles…)".*

The Example's View menu now has them, written in the Example: Palette ▸ (a
`Picker` over the built-in presets, as a submenu, the current one checked),
Border Style ▸ (a `Picker` over the built-in appearances) and Text Styling ▸
(two `Toggle`s). Whether TUI should offer the same to every app, as SwiftUI
offers `ToolbarCommands` and `SidebarCommands`, is a public API question:

1. **Nothing in TUI** (today). An app writes its own, as the Example does —
   twenty lines with `Picker`s over `PaletteRegistry.all` and
   `AppearanceRegistry.all`. Free.
2. **`DisplayCommands()`, a TUI-only standard set** adding View ▸ Palette ▸
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

**Ruled (owner, 2026-10-24): 3.** "I think (3), then. Ideally it'd be fully
automatic, but failing that we should at least have a binding or somesuch to
allow for the menu to be hooked up correctly. We definitely don't want menu
items that basically don't work."

**Shipped (lane MENUCMDS):** `DisplayCommands`, in TUICommands beside
SwiftUI's sets and named apart from them, adds View ▸ Palette ▸, Border Style ▸
and Control Style ▸ in a section of their own at the top of the View menu.
Each is a `Picker`, so a submenu of the built-in choices — `PaletteRegistry.all`,
`AppearanceRegistry.all` (by their localized names) and the control styles,
Braille one to four dots thick among them — with the one in force checked.
TUICommands now depends on TUIPickers for it.

```swift
public init(
    palette: Binding<any Palette>? = nil,
    appearance: Binding<Appearance>? = nil,
    controlStyle: Binding<ControlStyle>? = nil
)
```

- **Automatic.** With no arguments each submenu chooses through the app's own
  manager: the palette and appearance managers the `t` and `a` keys cycle, and
  a control style manager, new (`\.controlStyleManager`, a third
  `ThemeManager`, over `ControlStyle`, now `Cyclable` with a localized `name`).
  TUI had no root control style an app did not set itself, so the run loop
  keeps one, as it keeps the other two, and writes its choice at the root of
  each frame where it is not the default; a scene's `.environment(\.controlStyle, …)`
  or a view's `.controlStyle(_:)` wins over it, as a scene's `.palette(_:)`
  wins over the palette manager. The root control style is in the frame's
  environment snapshot, so a change redraws memoized views.
- **Never a dead item.** A manager's choice shows nothing where the scene sets
  the value itself, so the run loop publishes, from the window in front's
  scene configuration, which of the three its modifiers state
  (`SceneDisplayOptions`, at the root as `\.displayOptionsSetByScene`): a
  `.palette(_:)` or `.theme(_:)`, an `.appearance(_:)` with an appearance (`nil`
  leaves the manager in charge, as it always has), a scene's
  `.environment(_:_:)` of `\.palette`, `\.appearance` or `\.controlStyle`
  (the modifier now records the key path it writes), or an environment
  modifier of one of those on the window group's root view (found by the walk
  that already found a root view's `.palette`). A `.transformEnvironment` is
  not counted: it changes the manager's value rather than replacing it. Such a
  submenu, with no binding, is disabled — a submenu of disabled items, which
  still opens, as macOS draws a disabled picker — showing the scene's value
  checked where it is a built-in one, with help: "The app sets this itself, so
  a choice here would not show." A modifier deeper in the content, round one
  page, is not seen: the manager's choice still shows everywhere else.
- **Binding form.** An app that owns its look passes its state; the submenu
  then writes the binding and is never disabled. The types are the ones the
  scene modifiers take: `.palette(_:)` takes `any Palette`, so the palette is a
  `Binding<any Palette>`, written with the built-in palette chosen (an app
  holding an editable palette, as the Example does, converts in its binding's
  setter); the appearance an `Appearance`; the control style a `ControlStyle`.
- **Strings.** The three titles, the help and the control styles' names are
  TUI's, in its seven languages.

The Example's View menu is now `DisplayCommands(palette:controlStyle:)`, bound
to its editable palette and its control style, with Border Style through the
appearance manager: TUI disables it while the Theme page's custom border is
in force, as the Example's own code did. Text Styling stays the Example's own.

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

*`Scene.aboutPanel(applicationName:applicationVersion:version:copyright:credits:)`, TUI-only*

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
through the scene's environment. The Example states its name, TUI's version
and its authors.

**The fuller version:** credits as `Text` (styled, with a link), an
application icon drawn from the app's image (Kitty graphics where the terminal
has them), and a Credits.rtf / Credits.html read from the bundle as macOS does.
Half a day for `Text` credits; the icon waits on a decision about what an
app's icon is in a terminal.

### B-MENUBAR-3. A Help menu of TUI's own: Show Tooltips and Show All Tooltips (⌥?)

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
and File went with it (nothing else belongs there; TUI draws a standard menu
only when something is in it). Main Menu shows Escape, the key the pages
already go back with, and is disabled on the main menu; Previous Page is ⌃B
and Next Page ⌃T. Finder's ⌘[ and ⌘] cannot be had: ⌃[ is Escape's byte and ⌃]
a byte TUI does not read; and of the Control letters a terminal sends as
themselves, A, C, D, F, G, K, N, O, R, S, V, X and Z are bound already (a list's
or table's row keys, the clipboard and undo, a text editor's find, the Menus
page's ⌘ shortcuts), and E is a text editor's end of line. B and T are only a
text control's Emacs chords, which give way to an app's shortcut. View gains
Palette ▸, Border Style ▸ (disabled while the Theme page's custom border is in
force) and Text Styling ▸, the submenu, checked-item, picker-as-submenu and
disabled-item examples the owner asked for (since A-MENUBAR-1 the first three
are TUI's `DisplayCommands`, bound to the Example's state). The top bar is a
`toolbar(id:)`, so Customize Toolbar… is enabled and offers the F2 and F3
actions as buttons, which start out of the bar.

**Not done: "Customise" (en-GB).** TUI's strings have one English table, in
US spelling, as Apple's base English is; an en-GB table of the few words that
differ (Customise, Colour, …) would need the localization service to fall back
from a regional table to its language's, which it does not. Half a day; worth
it with a second regional language to justify the mechanism.

**The fuller version:** decode ⌃] (`0x1D`) so Next Page can be Finder's ⌘], with
⌃B for Back. An hour with a survey row, but ⌃[ stays Escape, so the pair would
not match.
