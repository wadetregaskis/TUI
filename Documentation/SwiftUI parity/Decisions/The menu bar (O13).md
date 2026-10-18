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
