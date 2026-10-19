# Completing the SwiftUI API: decisions from lane O9

*Lane O9 built SwiftUI's multi-scene apps on the one surface a terminal app has:
several scenes in one body (`SceneBuilder`'s variadic `buildBlock`,
`buildOptional`, `buildLimitedAvailability`, `Group`), `Window`,
`WindowGroup(id:)` and `WindowGroup(for:)`, `openWindow` and `dismissWindow`,
after the owner's ruling on refusal review O9 (2026-10-12: (b), secondary scenes
are full-surface covers stacked over the main one; leave room for a real
windowing model later). Every scene presentation goes through one internal
presenter (`ScenePresenter`, in TUIkitApp), whose first policy is that one; a
tiling or overlapping manager replaces the policy, not the API. Where the work
reached a judgement call the ruling did not settle, the safe option shipped and
is written up here, in the format of
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

*What SwiftUI does was measured on macOS 15.8 where it could be, with a probe
that builds a SwiftUI app per case and reads its main menu back (session notes
`O9/probe/scenes.swift`): the main menu of an app of several scenes. No window
could be opened on this machine — SwiftUI creates none, run from a shell or
bundled and launched with `open` — so what a window does is taken from Apple's
documentation and said so.*

## A. For the owner

### A-O9-1. `\.supportsMultipleWindows` is `true`

*`EnvironmentValues.supportsMultipleWindows`*

The refusal review proposed shipping it as `false` (X5), when nothing opened a
second window; under O9 (b) `openWindow` opens one, over the window in front.
SwiftUI's own example reads the value to decide whether to offer an "Open New
Window" button, and here the button works.

**Options.**

1. **`true`** (shipped): the app can open more windows than one, which it can,
   one at a time on the surface.
2. **`false`**: no two windows are seen at once, which is also true; an app
   reading it would hide its "open another" affordances, which do work.

**Recommendation:** 1. The coordinator's call under the owner's rule for minor
questions, proposed in the lane brief; the owner may overrule it, which is a
one-line change.

## B. Shipped the safe option

### B-O9-1. Windows are full-surface covers stacked over one another

*`ScenePresenter`, `StackedCoversPolicy`*

The ruling's policy, with the details it left open:

- **The window opened at launch** is the first window scene of the body, as on
  macOS: a `WindowGroup`, or a `Window` written first.
- **`openWindow`** opens the window over the whole terminal, in front of the
  others; a `Window` that is open is brought to the front instead, and a
  `WindowGroup` opens a new window each time, each at an identity of its own,
  so each has its own state.
- **The windows behind** are drawn off-screen every frame, isolated from the
  focus, the keys, the status bar and the clock, their buffers dropped — as a
  navigation stack's covered root is. So their state, their lifecycle (no
  `onDisappear`) and their tasks carry on, as a window's do behind another on
  macOS, and their scenes' own modifiers (`.environment`, `.palette`) still
  reach them.
- **Each window keeps its own bars** (`WindowChromeState`): coming back to the
  front, its top and bottom bars are where it left them, with no frame drawn
  with another window's rows. A window's first frame seeds its bars by a
  measuring walk, as the app's first frame does.
- **The focus** goes to where it rested in a window coming back to the front,
  and into a new window's first control; a window other than the launch window
  registers its content in a focus section of its own.
- **The commands** are the app's: every scene's, in declaration order, whichever
  window is in front (measured: SwiftUI's main menu holds a window group's, a
  `Window`'s and a `Settings` scene's menus at once). The frame's other scene
  statements — mouse support, toolbar style, undo keys — are the front
  window's.

**The fuller version** is a windowing model: a policy that tiles or overlaps
windows, with the presenter drawing each into a region of the surface and
compositing them, the focus moving between them, and a way to resize and place
them from the keyboard. Several days; the presenter, the actions and the scenes'
API stay as they are, which is what the ruling asked of this one.

### B-O9-2. Escape closes a window opened over another

*`ScenePresenter.claimEscape(closing:at:context:)`*

On macOS every window has a close button and ⌘W. A terminal has neither, and a
window's content need not offer a way out of it, so a window opened over the
main one could hold the reader for good.

**Shipped:** with another window open behind it, Escape closes the window in
front when nothing in it takes the key — the way a pushed navigation screen's
Escape goes back: a lightweight claim on the status bar ("close window"), made
after the window has drawn and only if nothing in it claimed the key or holds
the keyboard (a sheet, an open menu), and a handler filed ahead of the window's
own, so its content is asked first. The window opened at launch, when it is the
only one, keeps Escape for its content, as before (deviation W10).

**The fuller version** draws a close button in the window's top bar, clickable,
as macOS's title bar has one — an item the chrome adds to every window but the
last, about half a day with its placement rules, and a question of whether an
app that hides its top bar wants one.

### B-O9-3. The last window closing quits the app

*`ScenePresenter.close(_:)`*

On macOS, an app whose windows are all closed keeps running with only its menu
bar, unless its only scene is a `Window`.

**Shipped:** the app quits when its last window closes, by any route
(deviation W11): a terminal app with no window would show nothing and could be
given no input that opens one. `dismiss()` at a window's root closes the window,
as SwiftUI documents of a window's root view on macOS; at the launch window, the
only one open, that quits the app, as it did before.

**The fuller version** keeps an app with commands running with only its menu
bar on an empty surface, from which a command opens a window — an app shape
nobody has asked for in a terminal; about two hours.
