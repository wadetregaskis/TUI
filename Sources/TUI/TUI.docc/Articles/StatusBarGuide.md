# Status Bar

Show the keyboard shortcuts in force, in the window's bottom bar.

## Overview

The status bar is a line of key hints: the shortcuts in force and what each does. It is a view the app places — ``StatusBar``'s `init()` in the window's bottom bar:

```swift
ContentView()
    .toolbar {
        ToolbarItem(placement: .bottomBar) { StatusBar() }
    }
```

Every bar is opt-in: an app that places no `StatusBar()` shows no line of hints, and the content takes every row. The keys work either way — an item's action fires on its key with no bar on screen, and `q` quits.

The line updates every frame. It takes no row while it has nothing to show: no active user items and no visible system items.

Its bar is framed in the scene's window toolbar style — see ``WindowToolbarStyle`` — which the top bar shares. It defaults to a box: the line boxed like a container view.

## Architecture

The status bar system has three parts:

- **``StatusBarState``**: Manages the item stack and event handling
- **``StatusBarItem``**: A single shortcut entry (key + label + action)
- **``StatusBar``**: The view that renders items into a ``FrameBuffer``

## Defining Status Bar Items

Use the `statusBarItems` modifier on your views to register shortcuts:

```swift
VStack {
    Text("My App")
}
.statusBarItems {
    StatusBarItem(shortcut: "n", label: "new") {
        // handle "n" key press
    }
    StatusBarItem(shortcut: "d", label: "delete") {
        // handle "d" key press
    }
}
```

Items are registered per frame during rendering. When a view is removed from the tree, its items automatically disappear from the status bar.

## Shortcut Display Symbols

Use ``Shortcut`` to keep displayed shortcut symbols consistent. A key's
constant is the symbol a macOS menu draws for it, from the same formatter as
``KeyboardShortcut/displayString``, so the bar and a menu name a key the same
way:

| Constant | Display | Description |
|----------|---------|-------------|
| `Shortcut.quit` | `q` (drawn `Q`, see One-letter keys) | Default quit display |
| `Shortcut.enter` | `↩` | Return |
| `Shortcut.escape` | `⎋` | Escape |
| `Shortcut.tab` | `⇥` | Tab |
| `Shortcut.arrowUp` | `↑` | Arrow up |
| `Shortcut.arrowDown` | `↓` | Arrow down |
| `Shortcut.arrowsUpDown` | `↑↓` | Vertical navigation |
| `Shortcut.ctrl("q")` | `⌃Q` | Control and Q, named as a menu names the chord |

`Shortcut` defines how the item is displayed. If you do not pass `key:`, `StatusBarItem` derives a trigger key from the shortcut string where possible.

### One-letter keys

An item's `shortcut` string is the key it binds in the bar's own vocabulary, where the case is the Shift: `"n"` is n and `"N"` is Shift-N. The bar draws a one-letter key the way a macOS menu draws it, as every other key TUI names is drawn — `N new` for `"n"`, `⇧N new` for `"N"`, and `Q quit` — so the bar reads the same as `⌃Z undo` beside it. The string still binds the key and names the item. An app that prefers the TUI convention, in which lower case means no Shift, sets ``StatusBarKeySpelling/asTyped`` with ``View/statusBarKeySpelling(_:)``:

```swift
StatusBar()
    .statusBarKeySpelling(.asTyped)   // n new, N new, q quit
```

A key of anything but one letter — `1-9`, `c|C`, `↑↓`, `?` — is drawn as written either way.

## Context Stack

Status bar items use a **context stack**. Context-specific items can temporarily replace global items, for example while a dialog is visible:

```swift
Dialog(title: "Confirm") {
    Text("Delete file?")
} footer: {
    ButtonRow {
        Button("Delete") { delete() }
        Button("Cancel") { cancel() }
    }
}
.statusBarItems(context: "confirm-dialog") {
    StatusBarItem(shortcut: "y", label: "yes") { delete() }
    StatusBarItem(shortcut: "n", label: "no") { cancel() }
}
```

The topmost context replaces global user items in the display. System items remain visible unless a user item uses the same shortcut string.

## System Items

TUI registers built-in system items automatically:

| Key | Label | Action |
|-----|-------|--------|
| `q` | Quit | Exit the application |
| `a` | Appearance | Cycle to next border appearance |
| `t` | Theme | Cycle to next color theme |
| `⎋` | *(what claimed it)* | None — informational |
| `↩` | *(what claimed it)* | None — informational |

These appear on the right side of the status bar, drawn `Q quit`, `A appearance` and `T theme` (see One-letter keys). `q quit` is shown by default, `a appearance` and `t theme` are not, and the two common keys are — all four are controlled by ``View/statusBarSystemItems(theme:appearance:returnKey:escapeKey:)``.

### The two common keys

Return and Escape are the only keys the bar carries on their own account. They are common enough, and special enough, to be worth a permanent place — and unlike the rest, what they do changes with the focus, so a page cannot label them once and be right.

So the question is split. **Whether** the bar carries them is the app's decision, made once with the modifier above. **What they say** is the focused view's, published each render: a `Button` says "activate" (or "choose", in a menu), a `Toggle` says "toggle", a closed pop-up says "open menu", a `TextField` with an `onSubmit` says "submit", a list row says "select" — or "open", where the list has a row action.

An entry appears only while something has said what its key does. Nothing said, nothing shown: a slider does nothing with Return, so on a page whose focus is a slider there is no Return entry at all. The bar cannot know what an undeclared `onKeyEvent` closure would do with a key, so it does not guess — a key that works without saying so is a silence, which is better than an entry for a key that will do nothing.

Both entries are **informational**: they carry no action, so they display and do not intercept. Turning one off is a display decision and changes nothing about what the key does.

A page that wants Escape (or Return) to do something of its own publishes an ordinary user item for it. That wins the shortcut dedup, keeps its action — and is still renamed in place while a presented surface claims the key, so "⎋ back" reads "⎋ close popover" for as long as the popover is up.

A sheet's Escape is the sheet's. Items its content declares with `.statusBarItems` are added to the sheet's own "⎋ dismiss" (or "⎋ cancel", where Escape presses the content's cancel button), never put in its place, so a page's "⎋ back" declared around the view presenting the sheet does not answer Escape while the sheet is up. Content that declares an Escape item of its own keeps it: that item answers the key instead.

### Overriding `q quit`

A user-defined status bar item with shortcut `q` overrides the built-in quit binding for that view context:

```swift
EditorView()
    .statusBarItems {
        StatusBarItem(shortcut: "q", label: "close") {
            closeEditor()
        }
    }
```

This works because status bar items with actions are handled before the default quit binding. The built-in `q quit` system item is also removed from the display when a user item uses the same shortcut string.

### Changing the global quit shortcut

Change the built-in quit key through ``StatusBarState/quitShortcut``:

```swift
struct ContentView: View {
    @Environment(\.statusBar) private var statusBar

    var body: some View {
        MainView()
            .task {
                statusBar.quitShortcut = .escape
            }
    }
}
```

Available presets include ``QuitShortcut/q``, ``QuitShortcut/escape``, ``QuitShortcut/ctrlQ``, and ``QuitShortcut/ctrlC``. You can also create a fully custom ``QuitShortcut``.

### Hiding the status bar completely

Hide all system items and do not register any user items:

```swift
ContentView()
    .statusBarSystemItems(theme: false, appearance: false, returnKey: false, escapeKey: false)
```

```swift
@Environment(\.statusBar) private var statusBar

statusBar.showSystemItems = false
```

When there are no active items left, `StatusBar()` takes no row, and a bottom bar holding nothing else is not drawn — except while a tooltip is showing, which is the default presentation of `.help(_:)`: the bottom bar then takes the rows the tooltip needs, above any items, and is drawn for the tooltip alone when there is nothing else in it.

## Bar Styles

The bottom bar is framed in the scene's window toolbar style, which the top bar shares — SwiftUI's `windowToolbarStyle(_:)` on the scene:

- **`.automatic`, `.expanded`**: Items inside a bordered container (the default)
- **`.unified`**: Items in a single line under a full-width rule, which the top bar mirrors below its content
- **`.unifiedCompact`**: Items alone, no rule and no border

```swift
WindowGroup { ContentView() }
    .windowToolbarStyle(.unifiedCompact)
```

## Event Dispatch Priority

Status bar items are dispatched in **Layer 1** of the key event pipeline: they take priority over view-registered handlers and default bindings. See <doc:AppLifecycle> for the full dispatch order.
