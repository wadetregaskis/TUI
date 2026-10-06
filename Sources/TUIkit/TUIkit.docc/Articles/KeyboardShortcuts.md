# Keyboard Shortcuts

How keyboard input flows through TUIkit: from raw terminal bytes to your view handlers.

## Overview

TUIkit uses a layered event dispatch system. When a key is pressed, it passes through up to five layers. The first layer that consumes the event wins: remaining layers are skipped. Layer 0 (text input) and Layer 3 (focus system) are mutually exclusive: when a text input element is focused, Layer 0 runs and Layer 3 is skipped. The one key Layer 0 does not offer the focused text control is an Emacs editing chord your own `.keyboardShortcut` is on; see <doc:KeyboardShortcuts#Your-Shortcuts-and-the-Editing-Chords>.

Before any of them comes the **focus path**: SwiftUI's `onKeyPress` handlers on the views that contain the focused control, asked outermost first. They come even before a focused text input, as they do in SwiftUI, which is safe only because they are focus-gated; see *SwiftUI's onKeyPress* below.

Three additional stages refine the layer sequence. When an open drop-down (e.g. a ``Picker`` menu) has claimed Escape for the frame, ESC is pre-routed through the focus system *before* Layer 1, so the surface closes instead of a page-level handler firing. Layer 0.5 then offers the key to a drag in flight, which is how you scroll to an off-screen destination without letting go — it has to beat every layer below, all of which would otherwise spend the key on the focused control. And between Layer 3 and Layer 4, a shortcut stage (Layer 3.5) fires your `.keyboardShortcut`s — the default button on Return and the cancel button on Escape, à la SwiftUI's `.keyboardShortcut(.defaultAction)` / `.keyboardShortcut(.cancelAction)`, and any other key equivalent on its key — when the focused control let the key fall through.

@Image(source: "keyboard-event-dispatch.svg", alt: "Flowchart of the keyboard dispatch: a hasTextInputFocus check gates Layer 0 (Text Input via focusManager.dispatchKeyEvent for TextField/SecureField/TextEditor), except that an editing chord the focused control gives up to an app shortcut registered on it skips Layer 0 and continues down the chain. Without text focus, an ESC-claimed-by-an-open-surface check pre-routes Escape through the focus system so an open drop-down closes before any page-level handler. Layer 0.5 Drag Navigators (while a drag is in flight, arrows and paging scroll whatever the pointer is over). Layer 1 Status Bar Items (statusBar.handleKeyEvent). Layer 2 View Handlers (keyEventDispatcher.dispatch, deepest view first). A second hasTextInputFocus check skips Layer 3 if text input was focused. Layer 3 Focus System (focusManager.dispatchKeyEvent: focused element delegation, Tab/Shift+Tab, arrow key fallback). Layer 3.5 Semantic Shortcuts (Return fires the default button, Escape the cancel button, and a key-equivalent .keyboardShortcut fires on its key). Layer 4 Default Bindings (q quit and ? help always; t theme and a appearance gated while a modal grabs input). Unmatched events are dropped.")

`⌃C` is an ordinary key here. A terminal normally turns it into SIGINT, but TUIkit's raw mode switches that off, so it reaches these layers as `c` held with Control like any other chord, and nothing binds it unless you do: a ⌘C shortcut under the default ``EnvironmentValues/commandKey``, or ``QuitShortcut/ctrlC``. `⌃Z` arrives the same way, and Layer 4 suspends the app on it only when nothing earlier claimed it (see Default Bindings).

## Available Keys

The ``Key`` enum defines all keys that TUIkit can recognize from terminal input:

### Character Keys

Any printable character is represented as `.character(Character)`:

```swift
.onKeyEvent(Key.from("x")) {
    // handle "x" key
}
```

Uppercase detection: when a capital letter is typed, the resulting ``KeyEvent`` has `shift: true` set automatically.

### Special Keys

| Key | Description |
|-----|-------------|
| `.escape` | Escape key |
| `.enter` | Enter / Return |
| `.tab` | Tab |
| `.backspace` | Backspace / Delete backward |
| `.delete` | Forward delete |
| `.space` | Space |
| `.paste(String)` | Bulk text from a bracketed terminal paste |

### Arrow Keys

| Key | Description |
|-----|-------------|
| `.up` | Arrow up |
| `.down` | Arrow down |
| `.left` | Arrow left |
| `.right` | Arrow right |

### Navigation Keys

| Key | Description |
|-----|-------------|
| `.home` | Home |
| `.end` | End |
| `.pageUp` | Page Up |
| `.pageDown` | Page Down |

### Function Keys

| Key | Description |
|-----|-------------|
| `.f1` … `.f12` | Function keys F1 through F12 |

## Key Events and Modifiers

A ``KeyEvent`` combines a ``Key`` with modifier flags:

```swift
public struct KeyEvent {
    public let key: Key
    public let ctrl: Bool     // Ctrl modifier
    public let alt: Bool      // Alt / Option modifier
    public let shift: Bool    // Shift modifier
}
```

The terminal encodes modifiers differently from GUI frameworks:

- **⌃-letter**: Detected from ASCII control codes (0x01–0x1A). For example, `⌃C` produces byte `0x03`.
- **⌥-key**: Detected from ESC prefix sequences (`ESC` followed by the key byte).
- **Shift**: Only auto-detected for uppercase letters. The terminal does not send distinct shift codes for most keys.

## SwiftUI's onKeyPress

``View/onKeyPress(phases:action:)`` and its four siblings behave as they do in
SwiftUI on macOS:

- **The focus decides who hears a press.** A handler runs only while the focus
  is on its view or inside it. `Text("x").onKeyPress { … }` hears nothing
  until it is `.focusable()`; a handler on a container hears every press while
  any control inside it holds the focus.
- **Outermost first.** The handlers on the path to the focused control are
  asked from the outside in, and the first to return
  ``KeyPress/Result/handled`` stops the rest.
- **Before the focused control.** They are asked before the control itself —
  a focused ``TextField`` does not type a letter a handler took, and a handled
  Tab does not move the focus — and before your `.keyboardShortcut`s.

```swift
List(selection: $selection) { … }
    .onKeyPress(.space) {
        togglePlayback()
        return .handled
    }
    .onKeyPress(characters: .decimalDigits) { press in
        jump(to: Int(press.characters)!)
        return .handled
    }
```

What a terminal cannot say, ``KeyPress`` does not pretend to. Where the
terminal speaks the kitty keyboard protocol, which TUIkit turns on wherever
the terminal answers its query, the three phases are SwiftUI's: a press is
``KeyPress/Phases/down``, each auto-repeat ``KeyPress/Phases/repeat``, and the
release ``KeyPress/Phases/up``. In the legacy encodings a terminal sends a held
key's repeats as more presses and never sends a release, so every press is
`.down` (a `.down` or `.repeat` handler hears them all) and an `.up` handler
never runs. ``EnvironmentValues/keyboardReporting`` says which, for an app that
wants to offer a fallback. Its ``KeyPress/modifiers`` are the three a terminal
reports — Control, Option and Shift.

An open drop-down takes every key before the focus path does, as an open menu
does on macOS, and so does a drag in flight (Layer 0.5).

### Move, exit and delete commands

``View/onMoveCommand(perform:)``, ``View/onExitCommand(perform:)`` and
``View/onDeleteCommand(perform:)`` ask the same path the other way round:
innermost first, and only once the focused control has let the key go. A
`List` keeps its arrows and a ``TextField`` its Backspace; an arrow, Escape or
Delete the control does not use becomes the command of the nearest view that
has one — before the focus system spends an arrow on moving the focus, and
before your `.keyboardShortcut`s, so an exit command takes Escape from a
cancel button.

On Apple platforms the copy, cut and paste commands —
`onCopyCommand(perform:)`, `onCutCommand(perform:)` and
`onPasteCommand(of:perform:)` — ride the same path. Their keys are SwiftUI's
⌘C, ⌘X and ⌘V resolved through ``EnvironmentValues/commandKey``, and a paste
is also the terminal's own bracketed paste. Only text crosses: a terminal's
clipboard holds a string.

## Registering Key Handlers

To bind a key whatever holds the focus — a page's own shortcuts, a function
key, a paste — use the TUI-specific `.onKeyEvent()` modifier, which sees the
terminal's own ``KeyEvent`` at Layer 2:

### Handle All Keys

```swift
Text("Press any key")
    .onKeyEvent { event in
        if event.key == .enter {
            doSomething()
            return true   // consumed: stops propagation
        }
        return false      // not consumed: passes to next handler
    }
```

### Handle Specific Keys

```swift
Text("Use arrow keys")
    .onKeyEvent(keys: [.up, .down]) { event in
        if event.key == .up { moveUp() }
        else { moveDown() }
        return true
    }
```

### Handle a Single Key

The single-key variant always consumes the event:

```swift
Text("Press Enter to continue")
    .onKeyEvent(.enter) {
        continueAction()
    }
```

### Handler Priority

Handlers are dispatched in **reverse registration order**: the deepest view in the tree (most recently registered) gets the event first. This means inner views can intercept events before outer views see them.

```swift
VStack {
    Text("Outer")
        .onKeyEvent(.enter) {
            // Only reached if inner handler did NOT consume it
            print("outer enter")
        }
    Text("Inner")
        .onKeyEvent(.enter) {
            // Gets the event FIRST
            print("inner enter")
        }
}
```

> Important: All key handlers are re-registered every render frame. If a view is not rendered (e.g. behind a conditional), its handlers are not active.

This precedence holds inside memoized subtrees too. A `ForEach` row or an `.equatable()` view served from the render cache registers its handlers again at the place in the tree where it would have rendered, so they rank exactly as they would if it had rendered (see <doc:RenderCycle#Registrations-a-Hit-Makes-Again>).

A `Button`'s own shortcut is registered again the same way, on one condition: the `keyboardShortcut(_:)` modifier has to be inside the memoized subtree, as it is when you write the button and its shortcut together. Planted above the boundary instead — `Button("Save") { … }.equatable().keyboardShortcut("s")` — the subtree goes on declining the cache, because the modifier offers its shortcut to the first control that renders *under* it and a served frame renders none.

## Focus Navigation

The `FocusManager` dispatches key events in three steps:

1. **Focused element delegation**: the focused element's `handleKeyEvent(_:)` is called first. If it consumes the event, dispatch stops.
2. **⇥ / ⇧⇥**: cycles focus between elements (wraps around).
3. **Arrow key fallback**: Up/Left move to the previous element in the section, Down/Right move to the next. This only triggers if the focused element did not consume the arrow key in step 1.

| Key | Action |
|-----|--------|
| ⇥ | Move focus to the next focusable element (wraps around) |
| ⇧⇥ | Move focus to the previous focusable element (wraps around) |
| Up / Left | Move to previous element in section (fallback) |
| Down / Right | Move to next element in section (fallback) |

For more details, see <doc:FocusSystem>.

## Framework Shortcuts

A few controls bind keys of their own, the way SwiftUI's built-in menu items do.
``NavigationSplitView`` binds SwiftUI's sidebar chords, View ▸ Show Sidebar
(⌃⌘S) and Toggle Sidebar (⌥⌘S). A terminal cannot report ⌘, so they go through
``EnvironmentValues/commandKey`` like any other ⌘ shortcut: <kbd>⌃S</kbd> and
<kbd>⌥⌃S</kbd> under the default `.control`, nothing under `.unavailable`.

| Chord | Default keys | Action |
|-------|--------------|--------|
| ⌃⌘S | ⌃S (0x13) | Toggle the sidebar of the split view that holds the focus, else the first on screen |
| ⌥⌘S | ⌃⌥S (ESC 0x13, where Option sends ESC) | The same |

They work wherever the focus is, but they are the framework's, not yours, so
everything of yours on the same keys comes first:

- A `.keyboardShortcut` on the same keys wins, wherever its button renders. Under
  `.control`, your ⌘S *is* ⌃S, so a Save button takes ⌃S and the split
  view keeps ⌃⌥S.
- An `onKeyEvent` handler that consumes the key wins.
- A focused control that uses the key wins: a sortable ``Table`` sorts on
  ⌃S. A `TextField`, a `TextEditor` and a `List` do not use it, so the chord
  works while typing. That holds for every framework shortcut, including the
  text controls' own editing chords against a framework default. Only your
  own shortcuts can take one of those, as the next section describes.

A `.disabled()` split view ignores them.

## Your Shortcuts and the Editing Chords

A focused control is offered a key before your shortcuts are (Layer 0 and
Layer 3 come before Layer 3.5), so as a rule a focused control that uses a key
keeps it. The text controls are the exception, for one family of keys.

Under the default ``EnvironmentValues/commandKey`` of `.control`, a SwiftUI ⌘
shortcut arrives as a Control chord: `.keyboardShortcut("f")`, Find, is ⌃F.
⌃F is also an Emacs editing chord in ``TextField``, ``SecureField``, a
`.searchable` field and ``TextEditor``, where it moves the caret forward a
character. Under `.option`, ⌘B and ⌘F arrive as ⌥B and ⌥F,
readline's word motions, which every text control answers. The text controls
read those chords the way the macOS text system and readline do, and they are
a bonus: whatever one does can be done some other way, with another key or by
selecting and typing. So **your shortcut wins them**. Layer 0 does
not offer the chord to the focused text control when a `.keyboardShortcut` is
registered on it. The chord goes on down the chain as a chord the control does
not bind would, and Layer 3.5 fires your button.

| Chord | What the text control does with it | With your shortcut on it |
|-------|------------------------------------|--------------------------|
| ⌃A, ⌃E | A field: start, end of the line, as Home and End do | Yours |
| ⌃A, ⌃E | `TextEditor`: start, end of the line; its Home and End go to the ends of the document | The editor's |
| ⌥B, ⌥F | Back, forward a word, as ⌥← and ⌥→ do (a character in a `SecureField`); with Shift, a field extends its selection | Yours |
| ⌃⌥B, ⌃⌥F | A field: back, forward a word. `TextEditor`: back, forward a character | Yours |
| ⌃B, ⌃F | Back, forward a character | Yours |
| ⌃D | Delete forward | Yours |
| ⌃K, ⌃Y | Kill to the end of the line, yank it back (a `SecureField` keeps no kill to yank) | Yours |
| ⌃T | Transpose the characters around the caret | Yours |
| ⌃P, ⌃N | `TextEditor`: previous, next line | Yours |
| ⌃O | `TextEditor`: open a line after the caret | Yours |
| ⌃V | `TextEditor`: page down | Yours |
| ⌃⌥A | Select all | The control's |
| ⌃C, ⌃X | Copy and cut the selection | The control's while text is selected; with nothing selected, yours. While a mouse selection is on the screen, ⌃C copies that instead, until the control takes a key |
| ⌃Z | Undo | The control's |
| ⌃V, ⌃U | A field's paste and erase | The field's |

A chord gives way when what it does can be done some other way in that
control, and keeps the key when it is the only way. Select-all has no other key
at all, since ⌘A cannot reach a terminal app. A field's Home and End go to the
ends of its line, so its ⌃A and ⌃E give way. The editor's Home and End
go to the ends of the whole document, which leaves ⌃A and ⌃E its only
keys for the ends of a line, so there they stay. The clipboard and undo chords
stand in for ⌘C, ⌘X, ⌘V and ⌘Z and do what those would, and a field's ⌃U
erases it; those stay too, except that copy and cut have nothing to act on
without a selection. Then ⌃C and ⌃X are not the control's at all: they
go on down the chain whether or not you have a shortcut on them, so your ⌘C
fires, and so does ``QuitShortcut/ctrlC``. ⌃Z never passes on: it is the
app's undo, which a focused text control's ⌃Z stands in for, and so it
stays the control's even in an app that has taken ⌃Z out of its undo keys
to make it suspend.

Only your shortcuts take a chord this way, and only one that is registered: an
enabled button on screen, not on a page behind a modal. A framework default,
such as the split view's sidebar chord above, never takes a key from the
focused control.

Nor does an `onKeyEvent` handler. Layer 0 comes before Layer 2, so a focused
text control keeps its editing chords, and every key it types, from your
focus-blind key handlers: an `onKeyEvent` sees keys wherever the focus is, so
asking it first would let any handler on the page take typing away from a
field. SwiftUI's `onKeyPress` is the other way round, here as on macOS 15: a
handler on a view that contains the focused `TextField` sees even a plain
letter before the field does, and returning `.handled` takes it from the
field — which is safe because it only sees keys while the focus is inside its
view. So to take a chord from a focused text control, put an `onKeyPress` on
the control or a view around it, or give the chord a `.keyboardShortcut`.

A key the control lets go of does pass Layer 2 on its way, though: ⌃C and
⌃X with nothing selected, and an editing chord given up to your shortcut.
An `onKeyEvent` matches a key whatever its modifiers — as SwiftUI's
`onKeyPress` does, whose `onKeyPress("c")` also fires for ⌃C — so a page's
`.onKeyEvent(.character("c"))` runs on ⌃C from a field with nothing
selected, ahead of your ⌘C and of a `.ctrlC` quit. Where that is not what you
want, use the form whose handler takes the ``KeyEvent``, check its `ctrl`, and
return `false` to let the key go on.

## Default Bindings

Layer 4 provides six built-in key bindings, but only quit, undo and redo, and help are enabled without configuration:

| Key | Action | Condition |
|-----|--------|-----------|
| `q` / `Q` | Quit application | Enabled by default; gated by ``QuitBehavior`` |
| Undo and redo | ``UndoCommand/defaultShortcuts``: ⌃Z, ⌃- and ⌃/ undo; ⌃⇧Z, ⌃_ and ⌥_ redo | Always, after your shortcuts; set app-wide with ``Scene/undoShortcuts(_:)``. A bound key is taken whether or not there is a step, so ⌃Z with nothing to undo does nothing |
| ⌃Z | Suspend the app, as the shell's `^Z` would | Only where the undo keys leave it out, and only once no view has claimed the key, so a focused text field's or editor's undo wins |
| `?` | Show the focused view's `View.help(_:)` tooltip | Enabled by default; falls through when the focused view has no help text. Reachable behind a modal, unlike `t` and `a` |
| `t` / `T` | Cycle to next color theme | Opt-in: requires `statusBarSystemItems(theme: true)` (or `showThemeItem = true`) |
| `a` / `A` | Cycle to next appearance | Opt-in: requires `statusBarSystemItems(appearance: true)` (or `showAppearanceItem = true`); then active unless a modal surface has grabbed input |

One more key quits: ⌃\\, which the terminal driver takes before any layer
unless you bind it (see "⌃\\ quits, unless you bind it" below).

### The help key, and the one place it cannot reach

`?` toggles the tooltip for whatever holds the focus. It is settable —
`tooltipState.helpKey = .f1`, or `nil` to claim no key at all — and, like `q`, an
app beats it at any earlier layer: a status-bar item with shortcut `"?"`, an
`.onKeyEvent`, or a `.keyboardShortcut(KeyboardShortcut("?", modifiers: []))`.

> Important: **A focused text control swallows `?`.** It is punctuation, and
> Layer 0 gives a focused ``TextField``, ``SecureField``, ``TextEditor`` or
> ``DatePicker`` first refusal on every printable key — so inside one the
> question mark is typed and Layer 4 is never reached. That precedence is
> correct: a help key must not stop the reader typing a question mark. It is
> also a real gap, and the awkward part of it is that the controls whose help
> most needs explaining are exactly the ones the key cannot reach. Their
> tooltips are still available by hovering, and an app wanting a keyboard route
> inside a text field should move `helpKey` to something text input does not
> consume. (An F-key would not have this problem, and was declined for a
> different one: F-keys are frequently claimed system-wide, so they fail
> elsewhere and less visibly.)

### Quit Behavior

The ``QuitBehavior`` enum controls when `q` is allowed to quit:

| Value | Behavior |
|-------|----------|
| `.always` | `q` quits from any screen (default) |
| `.rootOnly` | `q` only quits when no status bar context is pushed |

`.rootOnly` is useful for modal dialogs: push a status bar context for the dialog, and `q` will be blocked until the user dismisses it:

```swift
Dialog(title: "Confirm") {
    Text("Are you sure?")
} footer: {
    ButtonRow {
        Button("Yes") { confirm() }
        Button("No") { cancel() }
    }
}
.statusBarItems(context: "confirm-dialog") {
    StatusBarItem(shortcut: "y", label: "yes")
    StatusBarItem(shortcut: "n", label: "no")
}
```

### Changing the built-in quit key

The default quit binding is configurable through ``StatusBarState/quitShortcut``:

```swift
@Environment(\.statusBar) private var statusBar

statusBar.quitShortcut = .escape
statusBar.quitShortcut = .ctrlQ
statusBar.quitShortcut = QuitShortcut(
    key: .f12,
    shortcutSymbol: Shortcut.f12,
    label: "exit"
)
```

This changes both the Layer 4 quit binding and the displayed system item.
`.ctrlC` quits from a focused text field or editor too, unless text is
selected there: then ⌃C copies it. Nor does it quit while something on the
screen is selected with the mouse: then ⌃C copies that, ahead of every
layer (see <doc:MouseAndGestures>, "Selecting Text").

### ⌃\\ quits, unless you bind it

Whatever the quit binding, ⌃\\ quits — the backup for when `q` or a
⌃C your app binds cannot: when the app has hung. Raw mode leaves the
terminal's line discipline one signal character, the user's quit key, ⌃\\
unless they changed it; ⌃C and ⌃Z are turned off as signals and arrive as
keys. So the terminal driver turns ⌃\\ into `SIGQUIT` before the app reads a
byte, over ssh too, and the app leaves the terminal as a quit does: the
alternate screen left, the cursor shown, the shell's line discipline back.
The shell then reports `Quit: 3`. A user who turned the quit key off with
`stty quit undef` keeps it off.

Your own binding on ⌃\\ wins. While your app declares one — a
`.keyboardShortcut` (a live sheet's too, whichever pane holds the focus,
though it fires, as any shortcut, only from its own), an `onKeyPress` on the
key on the path to the focused view, the status bar's quit key or an item,
an undo key — TUIkit masks the
driver's quit, so the key reaches the input chain, and your binding has it
first. A ⌃\\ none of your bindings takes still quits:
TUIkit sends `SIGQUIT` itself, as the driver would have. The same goes for
⌃4, ⌃| and ⌃⇧\\, for which some terminals send ⌃\\'s byte in their legacy
encoding — iTerm2 and Warp for both, Ghostty for ⌃4, Apple Terminal for ⌃⇧\\
(measured 2026-10-06; Apple Terminal sends nothing for ⌃4), and xterm, VTE,
Konsole and the Linux console for both by their tables (not measured; a
terminal not measured is assumed to) — where the terminal may: with a ⌘4 shortcut on
screen — ⌃4 under `.commandKey(.control)` — the quit is masked, the byte
arrives as ⌃\\, and where nothing takes ⌃\\ it is offered as ⌃4, ⌃| and ⌃⇧\\
in turn to the bindings declared for them, so your ⌘4 fires — a handler that
hears every key hears the byte once, as ⌃\\. Bind both ⌃\\ and ⌃4 and the byte is ⌃\\'s: it
cannot be told apart. So ``KeyboardShortcut/isDeliverableInTerminal`` is
`true` for ⌃\\ and `false` for the other three.

Two things to know. A handler that hears every key — `onKeyEvent`,
`onKeyPress(phases:action:)` — cannot be read without running it, so it does
not mask the quit, and does not see ⌃\\ while the driver has it. Nor does an
`onKeyPress` on a set of characters, which asks for typed text, not chords:
Control is not looked at, so a field's `.decimalDigits` would otherwise
claim ⌃4, and type a 4 for the user's ⌃\\. Nor does an `onKeyPress` on a key
count for a Control chord the key does not name: `onKeyPress("|")` counts for
⌃|, but a PIN field's `onKeyPress(keys:)` on "0"…"9" does not count for ⌃4,
though it hears a ⌃4 the terminal sends apart, since its keys match without
Control. And while
such a binding is on screen, a hung app does not quit by ⌃\\: that is the
backup your binding traded away. `kill -QUIT` from another shell still ends
it.

A terminal that speaks the kitty keyboard protocol sends ⌃\\ as a key report
rather than the byte the driver acts on. TUIkit offers that report to your
bindings first, as any key — a ⌃\\ shortcut or handler of yours takes it —
and where none does, sends `SIGQUIT` itself, to the app's process group as
the driver would, so ⌃\\ quits there too. A hung app reads no report, so
TUIkit's stall watchdog pops the protocol's flags once input has waited
unread for 1.5 s: the next ⌃\\ reaches the driver as its byte and quits, so
under the protocol a hung app quits at the second ⌃\\. There ⌃4 and ⌃|
arrive as themselves, and a shortcut on them fires without masking the
driver's quit. But the watchdog's pop puts the terminal back in its legacy
encoding, where ⌃4 may be ⌃\\'s byte again, and the driver would quit your
app on the user's ⌃4 during a slow frame — so while a binding on ⌃4, ⌃| or
⌃⇧\\ is on screen there is no watchdog, and a hung app does not quit by ⌃\\
under the protocol either.

### Overriding `q` in a local view context

A user-defined status bar item with shortcut `q` and an action intercepts the key before the default quit binding runs:

```swift
EditorView()
    .statusBarItems {
        StatusBarItem(shortcut: "q", label: "close") {
            dismissEditor()
        }
    }
```

This is the correct way to repurpose `q` for a specific screen, dialog, or focus section. The matching user item handles the event in Layer 1, so Layer 4's built-in quit binding is never reached.

## Key Symbols

Every key TUIkit names on screen — a menu row's shortcut column, the status
bar's keys and its undo and redo hints, the ``Shortcut`` constants — is named
by one formatter, the way a macOS menu names a key equivalent: the modifiers
in the order ⌃ ⌥ ⇧ ⌘ (Control, Option, Shift, Command), then the key, a
letter in upper case. ``KeyboardShortcut/displayString`` is that name for a
shortcut, `KeyEvent.displayString` for a key as it arrived, and
``EventModifiers/displayString`` for a set of modifiers alone:

| Shortcut | Shown |
|----------|-------|
| `KeyboardShortcut("s", modifiers: .control)` | `⌃S` |
| `KeyboardShortcut("z", modifiers: [.control, .shift])` | `⌃⇧Z` |
| `KeyboardShortcut("Z", modifiers: .control)` | `⌃⇧Z` — an upper-case key is its Shift chord |
| `KeyboardShortcut("?", modifiers: .option)` | `⌥?` — punctuation as typed, with no ⇧ |
| `KeyboardShortcut(.upArrow, modifiers: .option)` | `⌥↑` |
| `KeyboardShortcut(.tab, modifiers: .shift)` | `⇧⇥` |

The keys that type nothing are macOS's symbols for them: ⎋ Escape, ↩ Return,
⇥ Tab, ⌫ Delete (backspace), ⌦ Forward Delete, ← → ↑ ↓, ↖ Home, ↘ End, ⇞ Page
Up, ⇟ Page Down. The function keys are `F1`…`F20`, and the space bar is named
in the app's language, as macOS names it: `Space`, `Leertaste`, `Espace`.
Command (⌘) is shown only by a shortcut that still holds it once
``EnvironmentValues/commandKey`` has resolved it, which is to say never under
the default: ⌘S is shown as the `⌃S` that fires it.

The status bar is the one place a letter is written otherwise. In the bar an
upper-case letter means Shift — an item on `"N"` is Shift-N — so the undo and
redo hints write a letter held with nothing but Shift in the case it types,
as the bar's own items are written: a redo on a bare u reads `u redo`, and one
on Shift-U `U redo`. A chord with ⌃, ⌥ or ⌘ in it is written as a menu
writes it there too (`⌃Z`, `⌃⇧Z`).

The symbols are drawn in the terminal's font. For a font with no glyph for
them, the user sets `TUIKIT_KEY_SYMBOLS=0`, or the app asks with
`.keyNotation(.spelledOut)` on its scene, and the status bar and a menu's
shortcut column write the keys' names instead: `Ctrl-Shift-Z`, `Esc`,
`Shift-Tab` (see ``KeyNotation``). Text of your own that names a key follows
the same choice through ``KeyNotation/spelling(_:)``, which keeps a joiner
the text already has — `⇧-click` is `Shift-click`, `⌃+C` is `Ctrl+C` — and
joins a minus that is the key like any other key: `⌃-` is `Ctrl--`.

```swift
@Environment(\.keyNotation) private var keyNotation

var body: some View {
    Text("Save: " + keyNotation.spelling(save.displayString ?? ""))
}
```

## Status Bar Shortcuts

The status bar displays available shortcuts to the user. Use the ``Shortcut`` namespace for consistent symbols: a key's constant is the symbol a macOS menu draws for it, from the one formatter every key TUIkit names comes from (see <doc:KeyboardShortcuts#Key-Symbols>):

### Display Symbols

```swift
.statusBarItems {
    StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
    StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
    StatusBarItem(shortcut: Shortcut.escape, label: "back")
}
```

### Common Symbols

| Symbol | Constant | Description |
|--------|----------|-------------|
| `⎋` | `Shortcut.escape` | Escape |
| `↩` | `Shortcut.enter` | Return |
| `⇥` | `Shortcut.tab` | Tab |
| `⇧⇥` | `Shortcut.shiftTab` | Shift-Tab |
| `⌫` | `Shortcut.backspace` | Delete (backspace) |
| `⌦` | `Shortcut.delete` | Forward Delete |
| `Space` | `Shortcut.space` | The space bar, named in the app's language |
| `↖` | `Shortcut.home` | Home |
| `↘` | `Shortcut.end` | End |
| `⇞` | `Shortcut.pageUp` | Page Up |
| `⇟` | `Shortcut.pageDown` | Page Down |
| `↑` | `Shortcut.arrowUp` | Arrow up |
| `↓` | `Shortcut.arrowDown` | Arrow down |
| `←` | `Shortcut.arrowLeft` | Arrow left |
| `→` | `Shortcut.arrowRight` | Arrow right |
| `↑↓` | `Shortcut.arrowsUpDown` | Vertical arrows |
| `←→` | `Shortcut.arrowsLeftRight` | Horizontal arrows |
| `↑↓←→` | `Shortcut.arrowsAll` | All arrows |
| `⌃` | `Shortcut.control` | Control modifier |
| `⌥` | `Shortcut.option` | Option (Alt) modifier |
| `⇧` | `Shortcut.shift` | Shift modifier |
| `⌘` | `Shortcut.command` | Command modifier |

### Shortcut Helpers

```swift
// Control and a key, named as a shortcut is: "⌃C"
Shortcut.ctrl("c")

// Join symbols: "↑↓"
Shortcut.combine(Shortcut.arrowUp, Shortcut.arrowDown)

// Range display: "1-9"
Shortcut.range("1", "9")
```

### Common Shortcut Letters

| Constant | Value |
|----------|-------|
| `Shortcut.quit` | `q` |
| `Shortcut.yes` | `y` |
| `Shortcut.no` | `n` |
| `Shortcut.cancel` | `c` |
| `Shortcut.ok` | `o` |

### Automatic Key Matching

``StatusBarItem`` automatically derives the trigger key from the shortcut string when no explicit `key:` parameter is given:

- Symbol shortcuts (`⎋`, `↩`, `⇥`) map to their corresponding ``Key`` values
- Single-character shortcuts (`"q"`, `"y"`) map to `.character(thatChar)`
- Arrow combinations (`"↑↓"`) match **both** individual arrow keys
- Multi-character non-symbol strings are informational only (no trigger key)

```swift
// Automatic: shortcut "q" triggers on Key.character("q")
StatusBarItem(shortcut: "q", label: "quit") { quit() }

// Explicit: override the trigger key
StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter) { select() }

// Informational: no action, no trigger
StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
```

## Status Bar Context Stack

The status bar supports a context stack for temporary shortcut overrides: useful for modals and nested navigation:

```swift
// Set global items
.statusBarItems {
    StatusBarItem(shortcut: Shortcut.arrowsUpDown, label: "nav")
    StatusBarItem(shortcut: Shortcut.enter, label: "select", key: .enter)
}

// Push context-specific items (e.g. for a dialog)
.statusBarItems(context: "my-dialog") {
    StatusBarItem(shortcut: "y", label: "yes") { confirm() }
    StatusBarItem(shortcut: "n", label: "no") { cancel() }
}
```

When a context is pushed, its items replace the global items in the display. System items (quit, theme, appearance) remain visible unless a user item uses the same shortcut string.

### System Items

There are three system items; only quit is shown by default:

| Shortcut | Label | Order | Shown by default | Description |
|----------|-------|-------|------------------|-------------|
| `q` | quit | 900 | Yes | Quit the application |
| `a` | appearance | 910 | No (opt-in) | Cycle border appearance |
| `t` | theme | 920 | No (opt-in) | Cycle color theme |

System items appear on the right side of the status bar. Opt in to the theme and appearance items with the `statusBarSystemItems(theme:appearance:)` modifier, or toggle them individually:

```swift
// As a modifier
ContentView()
    .statusBarSystemItems(theme: true, appearance: true)

// Or directly on the state
statusBar.showSystemItems = false       // Hide all system items
statusBar.showThemeItem = true          // Show theme cycling (also enables the `t` binding)
statusBar.showAppearanceItem = true     // Show appearance cycling (also enables the `a` binding)
```

The line of hints is a view the app places, `StatusBar()` in the window's bottom bar (<doc:StatusBarGuide>); the keys above work whether or not it is shown. When all system items are hidden and there are no active user items, it takes no row — until a status-bar tooltip shows, which the bottom bar still makes room for and draws.

## Topics

### Input Types

- ``Key``
- ``KeyEvent``
- ``KeyNotation``
- ``QuitBehavior``

### Focus

- ``FocusReference``
- ``Focusable``

### Status Bar

- ``StatusBar``
- ``StatusBarItem``
- ``StatusBarItemProtocol``
- ``Shortcut``
