# Completing the SwiftUI API: decisions from lane O13

*Lane O13 built the menu bar: SwiftUI's `Commands` — `CommandMenu`,
`CommandGroup`, the placements, `.commands`, `commandsRemoved()` and
`commandsReplaced(content:)` — drawn on the window's top row, after the owner's
ruling on refusal review O13 (2026-10-12: a full menu bar; the app header
optional, any combination of the two) and the A28 answers of 2026-10-04
(declaring `.commands` shows it; F10, Alt-letter and a click open it; it is not
in the Tab ring). The design is the A28 study's §3.5 and steps 8–9
([`Toolbars and opt-in chrome design study, A28 (2026-10-04).md`](<../Design studies/Toolbars and opt-in chrome design study, A28 (2026-10-04).md>)),
refined in the REFO notes' §4. Where the work reached a judgement call those
did not settle, the safe option shipped and is written up here, in the format
of [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

*What SwiftUI does was measured on macOS 15.8 with a probe that builds a
SwiftUI app per case and reads its main menu back (session notes
`O13/probe/menus.swift`): the order of the menus, how `CommandGroup`'s three
positions compose, what `commandsRemoved()` and `commandsReplaced` take away,
what the standard command sets add.*

## B. Shipped the safe option

### B-O13-1. The commands are a module of their own, the vocabulary with them

*`TUIkitCommands`*

The lane brief asked for a new leaf module over the app, chrome and menu
modules. REFO's sketch offered a cut: the vocabulary (`Commands`,
`CommandMenu`, `CommandGroup`, the placements) in TUIkitMenus, by the module
plan's topic rule ("menus and commands"), and the scene modifiers and the bar
in the leaf.

**Shipped:** everything in the leaf, `TUIkitCommands`, built on TUIkitApp. The
vocabulary has no client without `Scene.commands(content:)`, which needs
`Scene`; split, the two modules would have shared `package` surface (the walk
that turns commands into menus) for no app that uses one without the other.
The bar's drop-downs are TUIkitFoundation's menu engine, so the module needs
nothing of TUIkitMenus. The run loop and the chrome host reach the bar through
hooks that name nothing of it (`SceneCommandsDeclaration`,
`WindowChromeState.menuBar`), so an app that declares no commands links none of
it. Like TUIkitApp, it has no Windows build.

**The fuller version** is REFO's cut, if a library of commands that builds
without TUIkitApp ever matters (for the Windows port, say): about half a day,
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
opens and no command's key fires (deviation W8). The modal's own keys work.

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
it. TUIkit has the keys those commands stand for, and no responder chain.

**Shipped:** the commands a terminal app has, each the way to a key the app
already has, so the menu bar is a way to them and never the only one: About
(an alert), Quit (the quit key), Undo and Redo (the app's `UndoManager`,
disabled with no step to take), Cut, Copy and Paste (⌘X, ⌘C, ⌘V through
`commandKey`). An item that acts on what has the focus presses its key once the
frame that closed the menu has handed the focus back (`KeysAfterFrame`, a new
hook the run loop drains after each frame): while the menu is open it holds the
focus and the keyboard. Each item shows its key (`keyboardShortcutHint`), which
it does not bind again. Cut, Copy and Paste are always enabled; choosing one
with nothing to take it does what the key does then (rings the bell). No Delete
or Select All: a terminal app has no key for either that every text control
takes.

**The fuller version** validates them: before drawing, ask the focused view
whether its focus path or its own key handling would take ⌘X, ⌘C or ⌘V
(`KeyEventDispatcher.declaresFocusPathBinding` already answers it for the
commands; a text field's own copy would need asking too), and disable the item
that nothing would. About half a day. Separately, a disabled item shows no key
(as every disabled menu row in TUIkit does today, `KeyboardShortcutRegistrar.claim`),
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
- `TextEditingCommands`: Find…, pressing a `TextEditor`'s own find key, ⌃G
  (⌃F is its caret's forward a character).

**The fuller version:** submenus, which TUIkit's menus do not have (a `Menu`
inside a menu draws as a control on its row), so Find's own submenu (Find
Next, Find Previous, Use Selection, Jump to Selection) and Transformations
(upper, lower, capitalised, which a text control could do) — about a day with
submenus, which every menu would then have. Spelling and Speech have no
counterpart.

## C. Declined

### C-O13-1. `onCommand(_:perform:)`

A command sent up the responder chain by an Objective-C `Selector`. TUIkit has
no responder chain and no Objective-C runtime on Linux; what reaches the focused
view is SwiftUI's own focus-path commands (`onMoveCommand`, `onExitCommand`,
`onDeleteCommand`, `onCopyCommand`, …). Declined since refusal review O13
(CONFIRM). `parity-map.json`: the `View.onCommand*` family.

### C-O13-2. `ImportFromDevicesCommands`

Importing photos and scans from nearby devices (Continuity Camera): a service
macOS offers a window it can present a camera picker over, which a terminal app
has neither. `parity-map.json`: `notImplemented`.

### C-O13-3. `TextFormattingCommands`, until the rich-text editor

Its Font and Text submenus format a rich-text selection. TUIkit's text controls
hold plain text until A42's rich-text `TextEditor` lands, so the commands would
do nothing (rule 2): they fail to compile instead. With A42 they are the bar's
like `TextEditingCommands`, with the chords open question A42-Q8 decides.
`parity-map.json`: `notImplemented`, with that reason.
