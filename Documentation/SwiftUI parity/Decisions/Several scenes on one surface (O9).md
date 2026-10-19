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

### B-O9-4. An interactive dismissal leaves a window with a modal presentation open

*`DismissBehavior`, `Transaction.dismissBehavior` (decisions A22)*

SwiftUI's documentation: under `.interactive`, the default, `dismissWindow`
does not dismiss a window "currently showing a modal presentation, such as a
sheet or alert" on macOS; under `.destructive` it does.

**Shipped:** that, with "modal presentation" read as a presentation holding the
window's keyboard — a sheet, a full-screen cover, an alert, a confirmation
dialog — as the presenter saw it on the window's last frame: the window in front
asks the focus manager, and a window held behind another asks the throwaway one
its off-screen frame was drawn with. A popover or an open menu does not keep a
window open. `dismiss()` at a window's root and Escape close their own window
without asking, as they can only be reached when nothing modal is up in it.

**The fuller version** is a measurement: whether macOS counts a popover, and
whether `dismiss()` at the root follows the transaction too. It needs a session
that can open windows (none could here); five minutes there with the probe.

### B-O9-5. The scenes shown over the windows are a module of their own, TUIkitScenes

*`TUIkitScenes`: `Settings`, `AlertScene`, the scene dialog modifiers*

A `Settings` scene is drawn with a sheet and an `AlertScene` with an alert, and
the scene dialog modifiers write TUIkitPresentation's dialog environment; the
scene presenter, in TUIkitApp, links none of TUIkitPresentation.

**Shipped:** a leaf, `TUIkitScenes`, on TUIkitApp and TUIkitPresentation, as
lane O13's `TUIkitCommands` is (B-O13-1): the presenter reaches its scenes
through a hook that names nothing of it (`OverlayScene`: the view that presents
the scene), so an app that declares neither links none of it. The window
scenes — `Window`, `WindowGroup`'s new forms — and the presenter stay in
TUIkitApp, which draws them with the window chrome it has; the actions, their
environment values and `SettingsLink` sit in TUIkitFoundation beside
`DismissAction`, where any view can read them.

**The fuller version** is TUIkitApp depending on TUIkitPresentation, with these
in it: one module fewer, at the price of TUIkitPresentation's code in every app
on TUIkitApp alone; the owner's à-la-carte rule (A52) prices that against it.

### B-O9-6. `Settings` is a sheet over the window in front

*`Settings`, `SettingsLink`, `DefaultSettingsLinkLabel`, `\.openSettings`*

The ruling: `openSettings` presents the `Settings` scene as a sheet. On macOS it
is a window of its own, brought to the front if it is open.

**Shipped:** `openSettings`, a `SettingsLink` (labelled "Settings…" with a gear,
in seven languages) and the menu bar's Settings… (B-O9-9) present the scene as a
sheet over the window in front, whichever that is; presented already, it stays.
Like every sheet it is its content's size, Escape or `dismiss()` in it closes
it, and the window behind it is inert until then (deviation W12). The scene's
own modifiers (`.environment`, a palette) reach its content and not the window,
and the window's content keeps its identity whether or not the app declares a
`Settings` scene (`_SceneOverlayHost` draws the sheet's presenter beside the
content, not around it). An app with no `Settings` scene presents nothing.

**The fuller version** opens settings as a window over the whole terminal, as
the other scenes are — a choice the ruling made against, since a settings pane
is usually small; a line to change, if the owner prefers it.

### B-O9-7. An alert scene is presented over the window in front, its dialog modifiers its own

*`AlertScene`, `Scene.dialogSeverity(_:)`, `Scene.dialogIcon(_:)`, `Scene.dialogSuppressionToggle` (decisions A26)*

SwiftUI's documentation: an alert scene is "not attached to any particular
window", presents "in the center of the current display", and must be answered
before anything else in the app is used.

**Shipped:** while its binding is true the alert is presented over the window in
front, whichever that is, as an alert written on a view in it would be —
centred over the dimmed window, holding the keyboard; every action dismisses it,
Escape chooses its cancel button, and with no actions it has an OK button. Its
`presenting:` forms present nothing while the data is `nil`. The dialog
modifiers are scene environment writes (A26's option 1): written on an alert
scene they reach its alert and not the window's own alerts, since the alert's
presenter is drawn beside the window's content in the scene's own environment
(`_SceneOverlayHost`); written on a window scene they reach the alerts its views
present. A scene keeps nothing from frame to frame, so the suppression toggle's
object is made afresh each frame, where the view modifier keeps one in its
state: the checkbox's binding is the one the modifier states now either way.

**The fuller version** is a measurement, once a session can open windows: that
SwiftUI's scene modifiers reach a window's own alerts, which A26 inferred from
the documentation's wording; and whether an alert scene presented while a sheet
is up comes over the sheet (here it comes over the window's content, under the
sheet's own presentations' order). Five minutes there with the probe.

### B-O9-8. Each window keeps its own scene storage, under a namespace that lasts from launch to launch where it can

*`@SceneStorage`, `EnvironmentValues.sceneStorageNamespace`*

SwiftUI keeps `@SceneStorage` per window and restores it with the window when
the system restores the app's windows. TUIkit keeps it in the store
`@AppStorage` uses, which outlives the app, and restores no windows: the window
opened at launch is the app's, and the others are opened by the app.

**Shipped:** each window's values under a namespace of its own, found as the
view is drawn (the property resolves it from the environment, as `@AppStorage`
resolves its store):

- the window opened at launch: `scene.` and the key, as an app of one window
  always had, so nothing stored before moves;
- a `Window`'s window: `scene.`, its identifier and the key
  (`scene.inspector.tab`), the same from launch to launch;
- a group's windows: `scene.`, the group's identifier — or its place among the
  app's window scenes, for one with none — and the key for the first opened in
  a session, and `#2`, `#3`… after the identifier for those after
  (`scene.viewer#2.tab`).

**The fuller version** restores windows: the windows open at quit are opened
again at launch, each with its storage (and a group's presented value), as macOS
restores them — with a way to say an app does not want that
(`Scene.restorationBehavior`, declined in the window family, would then have a
reading). About a day; it is the owner's whether a terminal app should come
back with the windows it had.

### B-O9-9. The Window menu lists the windows, and closes the one in front

*`SceneOwnCommands`: `appSettings`, `windowArrangement`, `windowList`, `singleWindowList` (decisions B-O13-7)*

SwiftUI's main menu, measured with several scenes (`O9/probe/scenes.swift`):
the app menu holds Settings… (⌘,) after About; File's New becomes a submenu
with a New *Title* Window for each window group, then Close (⌘W) and Close
All; the Window menu holds Minimize (⌘M) and Zoom, each `Window` scene by its
title, and Bring All to Front, with AppKit's list of the open windows after.

**Shipped:**
- **Settings…** in the app menu, after About, where the app declares a
  `Settings` scene, presenting it, and showing its key: SwiftUI's ⌘, (through
  `commandKey`), or the one the scene's `.keyboardShortcut` states, bound by
  the presenter whether or not the app shows a menu bar (B-O9-12).
- **A Window menu**, for an app that declares more than one window scene (an
  app of one window has nothing to list, and its bar keeps the menus it had):
  Close Window (`windowArrangement`), closing the window in front — disabled
  for the last, which the app menu's Quit closes — and showing Escape, its key;
  the open windows (`windowList`), back to front, titled by their scene, the
  one in front checked, choosing one bringing it to the front; and the
  `Window` scenes (`singleWindowList`), choosing one opening it.

Not shipped: Minimize, Zoom and Bring All to Front, which a surface has no
reading for; and File's New *Title* Window, Close and Close All: a group's
window opens from what the app offers, and Close is the Window menu's here,
beside the list it acts on (deviation W13).

**The fuller version** adds File ▸ New with an item per window group (a new
window of it) and Close / Close All on ⌘W and ⌥⌘W through `commandKey` — keys
a text field may want (⌃W deletes a word), so the owner's call; about two hours.

### B-O9-10. A window's content can take the person's ways to close it away

*`View.windowDismissBehavior(_:)`, `WindowInteractionBehavior`*

SwiftUI's `.windowDismissBehavior(.disabled)` disables a window's close button
and ⌘W, and Apple's documentation shows it on a welcome window its own button
closes; with no window openable on this machine, that is taken from the
documentation, unmeasured. Of `WindowInteractionBehavior`'s other uses —
minimising, resizing, full screen, dragging a window by its background — a
surface has none (the window-server family in `parity-map.json`).

**Shipped:** `.disabled` takes away a window's two ways to be closed by the
person: Escape (B-O9-2), whose claim is not made and which the status bar does
not name, and the Window menu's Close Window, disabled. `dismissWindow` still
closes it: that is the app, not the person. `.enabled` and `.automatic` are
the default, closable. The declaration is a view's, made each walk into the
window's bars as `.toolbar` makes its items, the one closest to the content
winning; the walk that seeds a new window's bars makes it too, so a window
that cannot be closed never offers Escape, even on the frame it opens.

**The fuller version** is none: there is no other way to close a window here.

### B-O9-11. A window visibility toggle shows a window by bringing it in front, and hides it by closing it

*`WindowVisibilityToggle`, `DefaultWindowVisibilityToggleLabel`*

On macOS the toggle shows a `Window` scene's window or hides it, labelled for
which it would do; with no window openable on this machine, that is taken from
Apple's documentation, unmeasured. On one surface a window is seen only while
it is in front (B-O9-1).

**Shipped:** while the window is not in front — closed, or held behind
another — the toggle reads "Show *Title*" and opens it or brings it to the
front; while it is in front, "Hide *Title*", and closes it, the window behind
coming back. The label is the window's title in the current language (seven
languages, as macOS names such items: Show Toolbar, Hide Sidebar), and the
identifier where the scene has no title. An identifier no `Window` scene has
leaves the toggle disabled, there being nothing for it to do. Hiding closes the window
rather than holding it behind the others, since a held window still runs
(its tasks, its clock) and the person asked for it to go.

**The fuller version** keeps a hidden window's state for when it is shown
again — held, but drawn no more — about an hour, with a measurement of what
macOS keeps.

### B-O9-12. A scene's key opens it, menu bar or none; a window group has no ⌘N

*`Scene.keyboardShortcut(_:)`, `Scene.keyboardShortcut(_:modifiers:localization:)`*

Apple's documentation: the key is bound to the command a scene adds to open a
window — a window group's New *Title* Window, a `Window`'s item that brings it
forward, `Settings`'s Settings… — and pressing it is choosing that item; `nil`
removes a scene's default key. A window group's default is ⌘N (File ▸ New
Window), `Settings`'s ⌘, — the latter measured (`O9/probe/scenes.swift`, the
app menu's Settings… on ⌘,); unmeasured beyond the menu, no window being
openable here.

**Shipped:** the presenter binds each scene's key every frame, as a menu
bar's command binds its own (below whatever the window's content binds on the
same key: the content keeps it), through `commandKey`, whether or not the app
shows a menu bar. A `Window`'s key opens its window or brings it to the front;
a group's opens a new window of it, presenting its default value or `nil`;
`Settings`'s presents the settings sheet, ⌘, by default, and `nil` takes the
key away. Settings… and a `Window`'s item in the Window menu show the key.
A window group has no key unless one is stated: TUIkit's menu bar has no
File ▸ New Window for it to be the key of (B-O9-9), and ⌘N would arrive as
⌃N, which a terminal app's own views often bind.

**The fuller version** adds File ▸ New *Title* Window with SwiftUI's ⌘N on the
first group, B-O9-9's fuller version; with it, a group's key is the item's.

### B-O9-13. The window in front titles the terminal

*`WindowGroup`'s and `Window`'s titles, a root `.navigationTitle` (refusal review P15; the A28 design study, §9; Ghostty adoption study, C2)*

On macOS a window's title is its root navigation title, or its scene's
title where it has none, drawn in the title bar. A terminal app's window is
the terminal's, whose title bar or tab the app can set with `OSC 2`.

**Shipped:** while a window is in front, the terminal's title is its root
`.navigationTitle` where no top bar shows it — A28 §9: a title alone makes
no top bar, and titles the terminal instead — and otherwise its scene's
title (`WindowGroup("Notes")`, `Window("Inspector", id:)`). It is written
on a change only, through a ledger of what the app has set on the terminal
emulator (`TerminalHostState`, which progress, pointer shapes and attention
are to join, Ghostty adoption study V8–V10). Before the first title the
terminal's own is pushed on its title stack (`CSI 22 ; 2 t`); it is popped
(`CSI 23 ; 2 t`) when the window in front has no title, on suspend, on exit
and on a fatal signal, so the shell gets its title back, and pushed and set
again on resume. The title is sanitised: control characters dropped (a `BEL`
or `ESC` would end the sequence early), line breaks as spaces. An app with
no title sends nothing. Measured safe on every host run (no host prints any
of it, on either screen); tmux keeps the stack for its pane title; whether
the GUI hosts show the title and keep the stack is owed to a look
(`title_probe.py --hold`; the survey's "The window title").

**The fuller version** follows a host's measured behaviour where it differs
— `OSC 0` on a host whose tab shows the icon name, an `OSC 2` of the
terminal's own title where a host keeps no stack and reports its title —
once the look is taken; about an hour each.

### B-O9-14. A scene's `onChange(of:)` is compared once a frame, for the scene

*`Scene.onChange(of:initial:_:)`*

SwiftUI's documentation: the modifier is a scene's, and `initial` runs the
action "when this scene initially appears"; on macOS a scene has as many
windows as are open. With no window openable on this machine, what it does with
several, or none, is taken from that, unmeasured.

**Shipped:** the value is compared once a frame, before any window draws, for
the scene rather than for any window of it: the action runs once for a change
however many of the scene's windows are open — none included, the scene being
declared for the life of the app — and `initial` runs it on the app's first
frame, not again as windows open. The scene catalogue gathers the watches each
frame, and the run loop compares them, each at a place of the scene's own in
the state storage that no window's walk reaches. (Compared as each window drew,
as this lane first had it, the action ran once for every open window, and again
with `initial` for each window opened.)

**The fuller version** is a measurement, in a session that can open windows:
whether SwiftUI runs a scene's action while none of its windows is open, and
whether `initial` waits for its first window. If it waits, the compare skips a
scene with no window open and keeps its last value; about an hour.

## C. Declined

### C-O9-1. Managing windows on a desktop

*`parity-map.json`'s window-server family: `WindowStyle`, `WindowResizability`, `WindowIdealSize`, `WindowLevel`, `WindowManagerRole`, `WindowPlacement`, `WindowLayoutRoot`, `WindowDragGesture`, `WindowToolbarFullScreenVisibility`, `WindowMenuBarExtraStyle`, `MenuBarExtra`, `DisplayProxy`, `FrameResize*`, `Scene.windowStyle`/`windowResizability`/`windowIdealSize`/`windowIdealPlacement`/`windowLevel`/`windowManagerRole`/`windowBackgroundDragBehavior`/`windowToolbarLabelStyle`, `defaultSize`, `defaultPosition`, `defaultLaunchBehavior`, `restorationBehavior`, `handlesExternalEvents`, `View.windowFullScreenBehavior`/`windowMinimizeBehavior`/`windowResizeBehavior`/`windowToolbarFullScreenVisibility`*

Every one sizes, places, raises, styles, drags, minimises or restores a window
among others on a display, which the window server does. On one surface the
windows are covers the size of the terminal (B-O9-1), which the person sizes,
not the app; nothing is beside a window to place it against or above, and a
terminal app is launched by the person each time, with nothing to restore or
route an external event to. `WindowInteractionBehavior` ships for the one
interaction a cover has, closing (B-O9-10).

### C-O9-2. macOS window chrome, launch and the utility window

*`parity-map.json`'s macOS-chrome family: `DefaultWindowStyle`, `HiddenTitleBarWindowStyle`, `PlainWindowStyle`, `TitleBarWindowStyle`, the menu-bar-extra styles, `Scene.defaultWindowPlacement`, `SceneLaunchBehavior`, `SceneRestorationBehavior`, `UtilityWindow`*

The window styles are a title bar's, which the terminal emulator draws; the
launch and restoration behaviours choose among windows macOS reopens. A
`UtilityWindow` is a panel that floats beside the main windows and shows the
focused values of whichever is key, as the main menu's commands do: on one
surface it would cover the window whose values it shows. Its useful half —
content that reads the focused window's values — is a `Window` holding views
that read `@FocusedValue`, which works for the window behind it only when the
policy shows two windows at once: a tiling policy's question, kept with the
room left for one (B-O9-1).

`DocumentGroup` and the `FileDocument` family are not this lane's: they need
the file panels of refusal review O10.
