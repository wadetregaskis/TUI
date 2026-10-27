# Toolbars and opt-in window chrome

*How toolbars came to TUI and the window's chrome became opt-in: the design
study's Design 2 with policy P2, a toolbar in a sheet, a navigation stack's
bar, toolbar customization, and the forms refused. Ids: A28 (the study,
appended), A28-CUSTOMIZATION, B-D5C-1 to 3, B-TOOLBARS-1 to 5, C-TOOLBARS-1
and 2.*

## In short

A `.toolbar` draws its items in the window's bars, which are opt-in; a sheet
or full-screen cover hosts its own toolbar round the view that declared it; a
navigation stack's bar keeps its title beside a pushed screen's items; a
customizable toolbar's items are customized from a panel hanging from the bar,
kept per identifier. `windowToolbarStyle(_:)` also takes a style chosen at run
time (kept by the owner, B-D5C-1).

## How it unfolded

1. **2026-10-04, the A28 design study** (appended); the owner chose Design 2
   with policy P2. Lane D5C built steps 0 to 6.
2. **2026-10-19, lane TOOLBARS** finished steps 6 and 7, the customization
   family (A28-CUSTOMIZATION, settled 2026-10-18), and B-D5C-3's fuller sheet
   hosting.
3. **2026-10-26, B-D5C-1:** the owner kept the existential overload.

## The record

### B-D5C-1. `windowToolbarStyle(_:)` also takes a style chosen at run time

*`Scene.windowToolbarStyle(_:)`*

SwiftUI's modifier is generic over the style, and an app picks one statically.
A scene's modifiers cannot be chosen with an `if` (`SceneBuilder` has no
`buildEither`), and a call with an `any WindowToolbarStyle` cannot open the
existential, because the result's opaque type would depend on it. So an app
that lets its user choose — the Example's Theme page — had no way to apply the
choice.

**Shipped:** a TUI addition beside SwiftUI's generic form,
`windowToolbarStyle(_ style: any WindowToolbarStyle) -> some Scene`, marked
`@_disfavoredOverload` so SwiftUI source (`.windowToolbarStyle(.unified)`, a
concrete style) still binds to the generic one. A style an app writes itself
(a conformance with no framework reading) is drawn as `.automatic`.

**The fuller version** is no addition at all: give `SceneBuilder` an
`if`/`else` (`buildEither` producing a conditional scene) so the choice is
written as SwiftUI cannot write it either — a TUI extension in a different
place. About half a day, and it would let every scene modifier be chosen at
run time, not only this one. Or drop the addition and have the Example choose
the style at launch only. Your call if the addition's name sharing bothers you.

### B-D5C-2. An oscillating bar is pinned for a second, then tried again

*`WindowChromeState.settle` — the oscillation guard of §11*

The study's rule: never release a bar in the frame after reserving it, and
pin the union when a bar flips back within a short window, reporting it.
Shipped as written, with one choice the study left open — how long a pin
holds. Pinned for good, a page that changed its chrome three times in a
quick burst for a legitimate reason (a user flicking between pages faster
than twelve frames) would keep an empty bar until it declared something
new.

**Shipped:** a pin holds for one second (`WindowChromeState.pinNanos`); the
frame at its end — asked for, so a still screen gets it — tries the page's
declaration again, and a real oscillation pins again (and reports again)
within four frames. A declaration of any third height unpins at once.

**The fuller version** tells a layout oscillation from an input-driven one —
pin for good when no input arrived between the flips — at the cost of
threading "an event was delivered since the last frame" into the chrome
state. About two hours. Worth it only if the once-a-second flicker of a
genuinely oscillating page (reported on the diagnostic channel every time)
turns out to matter.

### B-D5C-3. A toolbar in a sheet draws its items round the view that declared it

*`View.toolbar(content:)` in a sheet's, a full-screen cover's or a popover's
content; `ToolbarItemPlacement.confirmationAction`, `.cancellationAction`,
`.destructiveAction`*

The window's bars are drawn inert while a presentation holds the input, so
an item a sheet's content declared there — SwiftUI's common
`.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { … } } }`
— was a dead button in the window's top bar: no key, click or Tab reached it,
and the bar appeared a frame after the sheet did. Step 7 of the design study
(sheets as toolbar hosts) had not been reached; the review found the hole.

**Shipped:** in presented content a `.toolbar` hosts its own items, in rows
round the view it is attached to, inside the presentation and in its focus
section: below it, a button row as macOS lays out a sheet's (destructive
leading; the bottom bar's placements; cancellation, then confirmation,
trailing), the confirmation button bound as the default button (Return, when
the focused control lets it through) and the cancellation button as the
cancel button; above it, every other placement. The rows are part of that
view's layout, so they come and go with it in the same frame — no P2 lag. A
`.toolbarVisibility` inside presented content no longer reaches the window's
bars (it would have hidden the line of key hints that says how to close the
sheet), and hides no row either.

What differs from macOS: the rows hang off the view the modifier is on, so a
`.toolbar` on an inner view puts its row there rather than at the sheet's
bottom edge. Escape presses the cancel button, as on macOS: the sheet's own
Escape — and a popover's — runs the cancel button's action in place of
dismissing (`DismissalGate.escape`), which it did not when this first
shipped, so a Cancel that discarded a draft was skipped; the status bar
names the key `⎋ cancel` while it does. While a
`dismissalConfirmationDialog` would ask, Escape asks first and the button
waits: pressed, its action ran before anything asked, so a Cancel that
discarded the draft had discarded it by the time its `dismiss()` asked.

**The fuller version** has the sheet host the items itself, at its edges
wherever they are declared — the window chrome host's P2 reservation applied
to a sheet, with the sheet's state keeping last frame's rows — and honours
`.toolbarVisibility` in a sheet for its rows. About a day; it touches the
modal presenter, which another lane is changing for `presentationSizing`.

**Shipped 2026-10-19 (lane TOOLBARS)** for sheets and full-screen covers
(`PresentationToolbarItems`): the presentation's first frame seeds its rows
from a measuring render of its content, so it opens with them. A popover,
whose presenter is in TUIFoundation, still draws round the view (deviation
W2).

### B-TOOLBARS-1. `ToolbarTitleMenu()` with no items leaves the title as it is

*`ToolbarTitleMenu.init()`*

SwiftUI documents the empty form as "a toolbar title menu where actions are
inferred from your app's commands" — `CommandGroupPlacement.saveItem`,
`.printItem` and their kind. TUI's commands are the menu bar's
(TUICommands, refusal review O13), which TUIChrome, where the title is
drawn, cannot see; and a command drawn in a second place has its keyboard
shortcut registered twice.

**Shipped:** the empty form compiles and leaves the title a title: no caret,
nothing to open. `ToolbarTitleMenu { … }` and `.toolbarTitleMenu { … }`, with
items, make the title a pull-down of them.

**The fuller version** has TUICommands hand the window's chrome the File
menu's document groups (`newItem`, `saveItem`, `importExport`, `printItem`)
as a view, drawn by the empty title menu in the registration-free way the
menu bar draws a closed menu — so each command's key stays registered once.
About half a day; worth it if an app ported from iPadOS leans on the inferred
menu.

### B-TOOLBARS-2. A navigation stack's bar keeps its title beside a pushed screen's principal items

*`ToolbarItemPlacement.principal` in a screen pushed onto a `NavigationStack`*

A pushed screen's top-bar items are drawn in the stack's bar (the A28 study,
step 7). That bar is TUI's own: the crumb trail, or ‹ Back and the title,
on one row whose height is fixed before the screen draws. In the window's top
bar a principal item takes the title's place (iOS's reading); in the stack's
bar the title is also the end of the trail, which says where the person is.

**Shipped:** the stack's bar keeps the trail and the title, its leading items
after them, and the principal items at the trailing end before the secondary
and primary ones. Every item is laid out on the bar's one row; a taller one is
cut to it.

**The fuller version** gives the stack's bar the window bar's regions: the
principal items centred in place of the title (or beside it under
`.toolbarRole(.editor)`), the trail shortened to the screens before. About two
hours; it changes nothing an app can do, only where the item sits.

### B-TOOLBARS-3. A link in a split view's column pushes only while the split is collapsed

*`NavigationLink` in a `NavigationSplitView` column; decisions A21*

A21 (option 3 with B3) has a split view follow a compact class an app sets,
collapsing into a stack as on iPhone. A link in the column on top now pushes
its destination onto that stack, over the column — resolved by the
`navigationDestination`s the columns declare — with the trail, Escape and
`\.dismiss` going back through it as through the columns.

**Shipped:** the collapsed form. Links pushed over a column go when another
column comes to the top. In a regular class a split view's links push only
within a `NavigationStack`, as before — a link in a sidebar with no stack
round it is disabled — and links pushed while collapsed are kept, not shown,
until the split collapses again.

**The fuller version** is SwiftUI's regular form: a link in the sidebar (or
the content column) shows its destination in the next column, in place of
the column's own content, and a split that turns regular with links pushed
shows the last one there. About half a day: the split's columns read the
collapsed stack's links when they draw the next column.

### B-TOOLBARS-4. Toolbar customization: a panel from the bar, kept per identifier

*`View.toolbar(id:content:)`, `CustomizableToolbarContent` and its modifiers,
`ToolbarCustomizationBehavior`, `ToolbarCustomizationOptions`; the A28 study's
customisation family, option 1 (settled 2026-10-18)*

**Shipped:** a customizable toolbar's identified items are customized from a
panel that hangs from the top bar (the bottom bar, where the window has no top
bar): the items in the order the bars draw them, a checkbox per item, ▲ ▼ to
move it among the movable items of its place, the label styles where the scene
bound them, Reset and Done. It opens from the bar's
context menu — a right-click, or Shift+F10 while one of the bar's items has the
focus — and from the menu bar's View ▸ Customize Toolbar… (`ToolbarCommands`).
What the person chose is kept per toolbar identifier in the app's default
storage, as JSON in TUI's own encoding (`order`, `shown`), with nothing
written until they change something; Reset forgets it.

Where it differs from macOS:

- **Moving is within a place.** A bar's row lays its items out region by
  region — leading, principal, secondary, trailing — so an item moves among the
  others of its region of its bar's row (an accessory bar is a row of its own);
  an arrow with no movable item beyond it in that place is disabled. macOS
  drags an item anywhere in the toolbar.
- **No palette of spacers.** macOS offers Space and Flexible Space to drag in;
  a `ToolbarSpacer` here stays where it was declared.
- **The keyboard's way in needs a stop or the menu bar.** Shift+F10 opens the
  bar's context menu while one of the bar's items has the focus, and View ▸
  Customize Toolbar… needs `ToolbarCommands`; a bar of text alone, in an app
  with no menu bar, is customized by its right-click only.

**The fuller versions:** a stop of its own for a bar with no focusable item,
so Shift+F10 always reaches its menu — about two hours; moving an item across
placements, which changes where the app placed it — about half a day, and
arguably not the person's to change; spacers in the panel — about two hours.

### B-TOOLBARS-5. A tab view sidebar's toolbar items are rows at its foot

*`View.contentToolbar(for:content:)`, its `ToolbarContent` form*

SwiftUI's second `contentToolbar(for:content:)` takes toolbar content, and its
documentation puts a `.bottomBar` item at the bottom of the tab view sidebar
and an `.automatic` one in the sidebar's overflow menu (iPadOS; macOS marks
the placement unavailable). The parity baseline keys by name, so closing the
view-builder form hid this one; the review of the lane found it.

**Shipped:** the items drawn in the sidebar, under its tabs and footer: those
placed in the top bar in a row, and those placed in the bottom bar in a row
under it, each in declaration order, one column apart, in the sidebar's
environment as the view-builder form's views are. An `.automatic` item is in
the row rather than an overflow menu: a terminal sidebar hugs its widest row,
so it has room to show it. A title menu and a default item name the window's
bars and are not drawn; neither is an item hidden with `hidden(_:)`. The
placement, the view-builder form and the sidebar's slot moved to
TUIFoundation so this form, in TUIChrome, can reach the sidebar in
TUITabs without a module edge.

**The fuller version:** the `.automatic` and other top-bar placements in a
`»` overflow pull-down at the row's trailing end, as iPadOS's sidebar has,
built on the customizable toolbar's overflow menu — about two hours; worth it
only if an app puts more there than a sidebar is wide.

### C-TOOLBARS-1. `toolbarColorScheme(_:for:)` follows `preferredColorScheme(_:)`

*`View.toolbarColorScheme(_:for:)`*

The A28 study sends it to A17, which keeps `preferredColorScheme(_:)` out for
now (owner, 2026-10-04): a terminal's look is a palette, and TUI's palettes
do not come in light and dark pairs. A bar's fill is stated with
`.toolbarBackground(_:for:)`. Recorded in `parity-map.json`; it returns with
`preferredColorScheme` if light palettes are wanted for their own sake.

### C-TOOLBARS-2. `toolbarTitleDisplayMode(_:)` stays refused with its type

*`View.toolbarTitleDisplayMode(_:)`*

The refusal review's O8 (owner, 2026-10-12: omit the APIs that are inert on
macOS too, so they fail to compile) refused `ToolbarTitleDisplayMode`; the
modifier it feeds was still counted as an open gap. Recorded beside the type in
`parity-map.json`.

## Appendix: the toolbars and opt-in chrome design study, A28 (2026-10-04)

*Read-only study, 2026-10-04, against `main` at `f56c419d0`. Nothing was built or
run. Line numbers are from that tree. Anything marked **unverified** is
reasoning from the code, not something I watched happen.*

Covers the owner's A28 decision ("toolbars should ultimately be opt-in … you can
build anything … menu bar or not, top toolbar or not, bottom toolbar"), A1's
optional menu bar ("functionality must stay reachable without it"), and A21's
question about making "compact" an app-wide setting.

---

### 0. In one page

**What is hard-coded today.** TUI has two pieces of chrome, and both live in
`RenderLoop` outside the view tree. The **app header** is already opt-in: no
`.appHeader { }` means no header. The **status bar** is not. The system quit item
is always in it (`StatusBarState.currentSystemItems`, StatusBarState.swift:306-325),
so every app gets a bordered three-row bar unless it reaches into
`StatusBarState.showSystemItems`. Neither is a SwiftUI concept. Ported
`.toolbar { ToolbarItem(…) }` code does not compile (§2.6 of the compatibility doc).

**What is in the way.** One rule (owner, 2026-08-07, *Discarded render passes* §1):
*chrome whose height has to be found by rendering the content it displaces
forces a discarded walk.* The header breaks that rule today. It costs a
first-frame measure walk and a **correction re-render**, and the correction
re-render is the one effect leak nobody can close (`RenderPassScopeTests.swift:233`,
a `withKnownIssue`). The status bar dodges the rule only because the quit item
keeps it present. Once it is opt-in, it runs into the same problem: its height
is read before the walk, at RenderLoop.swift:512, and its items are declared
during the walk. SwiftUI's own model makes this worse. In SwiftUI a toolbar
exists *because* content declares items, deep in the tree.

**What I recommend.**

1. **Chrome becomes views, drawn by a scene-level host** (Design 2). It is a
   private `_WindowChromeHost` inside `WindowGroup.renderScene`. It lays out a
   menu bar, a top bar, the content and a bottom bar as one buffer. The host
   renders the bars *after* the content as ordinary views, from the
   `.toolbar` entries the content published. `RenderLoop` stops knowing about
   chrome. That deletes `AppHeaderState`, the correction re-render, the
   mouse-row translation, overlay lifting, the per-bar diff regions and the
   chrome-runs special case.
2. **A bar's height is known before the walk, because its presence is
   last frame's answer** (policy P2). Bars have fixed heights. A `.toolbar`
   that appears or disappears changes the layout one frame later, and that
   frame is drawn honestly. No walk is ever discarded. The menu bar is
   structural: it comes from `Scene.commands`, which is known before the walk.
3. **Every bar is opt-in.**
   - The **bottom bar** is the status bar. It exists when something is placed
     in it. TUI's key-hint line becomes a view, `StatusBar()`, that an app
     places there.
   - The **top bar** exists when items are placed there, and stands in for
     `.appHeader`, which is deleted.
   - The **menu bar** exists when the scene declares `.commands`.
   - The quit, Escape and Return keys keep working with no bar at all.
4. SwiftUI's `.toolbar` API ships with terminal placements (§3). Window toolbar
   styles become the app-wide way to choose compact chrome (A21).
   Customisation (`toolbar(id:)`) stays a gap.

**Cost.** Toolbars plus opt-in come to about 13–14 days on Design 2. The menu
bar adds 4–5. The first risky step moves today's two bars into the host with no
change in behaviour, and is A/B'd before any new API lands. Eight owner
questions are in §8. Each can be answered in a line.

---

### 1. The problem in TUI's terms

The owner has three goals:

1. **Nothing framing the page is mandatory.** An app with no chrome draws to
   every row of the terminal. Today it cannot without poking `StatusBarState`.
2. **SwiftUI's toolbar vocabulary works.** Ported code compiles. Items land
   somewhere sensible. `toolbarVisibility` hides a bar.
3. **An optional menu bar** carries `CommandMenu`/`CommandGroup` content.
   Everything in it stays reachable with the menu bar absent.

Four constraints follow from how TUI renders:

- **Heights before content.** The content area is the terminal minus the
  chrome, and the walk needs it before it starts. Chrome whose *presence*
  depends on the walk needs one of three things:
  - another walk (today's correction pass);
  - a frame of lag (P2);
  - a structural declaration (P3).

  See §4.1.
- **The bars must stay outside the modal backdrop.** A sheet dims and
  inerts the page. Today the header is undimmed but inert
  (RenderLoop.swift:603), and the status bar is undimmed *and* live: it shows
  the modal's items, and `q` still quits.
- **No mouse-only interactions.** Today's header controls are mouse-only. The
  header renders through `isolatedForBackground()` (AppHeaderModifier.swift:78),
  which throws away its focus registration *and* its `.keyboardShortcut`s
  (RenderContext+TUIContext.swift:146-151). So a `Button("Save").keyboardShortcut("s")`
  in `.appHeader` works only with a click. A toolbar must not repeat this.
- **Hot path.** A `RenderContext` field costs measurable percent (+2.4% for one
  `Int`). Nothing here needs one. New state goes in `EnvironmentValues` or an
  app-owned service object.

---

### 2. What exists today

#### 2.1 The two bars, and what each carries

| | App header | Status bar |
|---|---|---|
| Declared by | `.appHeader { }`, View+Presentation.swift:289 → `AppHeaderModifier` (Modifiers/AppHeaderModifier.swift:31) | `.statusBarItems { }` (View+Events.swift:525-619) → `StatusBarItemsModifier` (StatusBarItemsModifier.swift:54), plus system items |
| State object | `AppHeaderState` (AppHeader/AppHeaderState.swift:34): `contentBuffer`, `previousHeight = 3` (:47), `renderWidth` (:67), `style` (:74) | `StatusBarState` (StatusBar/StatusBarState.swift:41): items per section (:87), declared globals (:70), system flags (:105-143), quit key (:185), `style` (:194), Escape/Return claims (:226, :265), `tooltipLines` (:399) |
| Rendered | At the declaration site, into a buffer, isolated (AppHeaderModifier.swift:78-90); framed by `AppHeader` (AppHeader.swift:36-118) | By `RenderLoop.buildStatusBarBuffer` (RenderLoop.swift:1471) as the public `StatusBar` view (StatusBar.swift:42) → `_StatusBarCore` (:192) |
| Height known | After the walk (`appHeader.height`, AppHeaderState.swift:78) | Before the walk (`statusBar.height`, RenderLoop.swift:512; StatusBarState.swift:384) |
| Keyboard | None. Isolated focus *and* shortcuts | Items fire at InputHandler layer 1 (InputHandler.swift:182); quit is layer 4 (:214-231) |
| Under a modal | Drawn, regions dropped (RenderLoop.swift:603) | Drawn and live (RenderLoop.swift:610) |
| Style | `ChromeStyle` (Styling/ChromeStyle.swift:24): `.rule`/`.bordered`/`.compact`, set by `Scene.chromeStyle(_:)` / `(appHeader:statusBar:)` (App/Scene+ChromeStyle.swift:44-63) | Same |

#### 2.2 The frame (RenderLoop.swift)

`renderFrame` runs these steps in order:

1. `beginRenderPass()` (:911). This calls `appHeader.beginRenderPass()`, which
   snapshots `previousHeight` and clears the buffer (AppHeaderState.swift:102).
   It then calls `beginSceneRender()` (:977), which clears the status bar's
   declared items (StatusBarState.swift:528).
2. `appHeader.renderWidth = terminalWidth` (:467). The header is laid out at the
   full width, inside a tree that may be padded.
3. `applyChromeStyle(from: scene)` (:506, :1298) reads the scene's
   `RootChromeStyleProvidingScene`.
4. `resolveStatusBarTooltip` (:511, :1006) wraps the tooltip into
   `statusBar.tooltipLines` *before* the height is read. Tooltip triggers land
   between frames, so this costs no second walk.
5. `statusBarHeight = statusBar.height` (:512). **Read before the walk, so only
   imperative items and system items count.** Declared items were cleared in
   step 1.
6. `renderContent` (:694):
   - **First frame:** a throwaway walk marked `isMeasuring` (:709-735), whose
     only output is `appHeader.height`.
   - **Every frame:** a walk at `contentAreaHeight(terminal − status − estimate)`
     (:155, :749).
   - **When the header's real height differs from the estimate:** a
     **correction re-render** (:773-787) that discards the main walk. This is
     the walk `RenderPassScopeTests.correctionRerenderLeaksEffects` pins as a
     known gap.
7. Build the header buffer and lift its overlays onto the page (:566 →
   `buildAppHeaderBuffer` :1416 → `FrameBuffer.liftingOverlays`,
   AppHeader.swift:158). Build the status bar buffer (:573). Call
   `noteStatusBarPlacement` (:579, :1169), which invalidates the diff when the
   bar moves.
8. Composite the overlays over the **content area only** (:584,
   `compositeOverlays` :1398, `maxHeight: contentHeight`). This is why chrome
   is never dimmed.
9. Merge hit regions:
   - header regions `offsetY -= header` (:603-608), dropped under a modal;
   - status regions `+= contentHeight` (:610-616).
10. `writeFrame` (:1043) writes three diff regions:
    - `FrameDiffWriter.OutputRegion` `.appHeader/.content/.statusBar`
      (FrameDiffWriter.swift:149-150);
    - three background codes, three opacity surfaces (:1070-1073);
    - content at row `1 + headerHeight`, which the replay frame copies.
11. The `chromeRuns` liveness special case (:656, :1279-1288).

Mouse events are moved into content coordinates by
`MouseEvent.inContent(belowHeaderOf:)` (AppHeaderState.swift:147). This happens
in two places: App.swift:744 and HeadlessApp.swift:145.

#### 2.3 Why the status bar is "always there"

`StatusBarState.hasContent` (:377) is `hasItems || tooltip`. `hasItems` counts
`currentSystemItems`, and those include quit whenever `showSystemItems`
(:105, `true` by default) and `isQuitAllowed`. So the bar's pre-walk height is
nonzero in every app. Hiding it is documented as reaching into the state object
(StatusBarSystemItemsModifier.swift:91-93).

**Suspected latent bug (unverified).** Take an app that sets
`showSystemItems = false` and declares items only with `.statusBarItems { }`:

- The pre-walk height is 0, because the declared items were cleared in step 1.
- After the walk, `hasContent` is true.
- So the bar is built and written at row `terminalHeight − 0 + 1`
  (RenderLoop.swift:1138), one past the screen, with its regions shifted below
  the content.

The only test with `showSystemItems = false`,
`StatusBarFrameDiffTests.tooltipOnAnItemlessBarIsDrawn` (:126), declares no
items. **This is the exact circularity opt-in would expose.** It is the first
thing the plan pins with a test (§10, step 1).

#### 2.4 The one structural bar we already have: `NavigationStack`

`_NavigationStackCore` (Views/NavigationStack.swift:164) shows the pattern a
toolbar host should copy:

- The bar's height is a constant, `barHeight = 2` (:176), known whenever the
  path is non-empty.
- The screen renders first, inside a pushed preference scope (:380-386). The
  bar then reads `NavigationTitleKey`/subtitle/back-hidden back out (:387-389)
  and draws into rows that were already reserved (`renderBar` :403, view :510).
- Its controls are real `Button`s in the depth's focus section (`enterSection`,
  :310). Escape is a lightweight status-bar claim (:435-470).
- At depth 0 it draws **no bar**. The root's title is only recorded, for the
  crumbs (:295).

#### 2.5 Scene-level configuration

There are five internal protocols:

- `RootChromeStyleProvidingScene` (Scene+ChromeStyle.swift:16)
- `RootEnvironmentProvidingScene`
- `RootPaletteOverrideProvidingScene`
- `MouseSupportProvidingScene`
- `RootAppearanceOverrideProvidingScene`

There are **30 cross-forwarding conformances**. Each wrapper forwards the
concerns it does not own (for example Scene+ChromeStyle.swift:92-114). Adding
`.commands` and `.windowToolbarStyle` this way means two more protocols and
roughly 14 more forwarders. That is quadratic growth, so consolidate first
(§10, step 0).

#### 2.6 Machinery a menu bar would reuse

- **Pull-down `Menu`.** See `_MenuPopupCore.swift`. A closed menu renders only
  its trigger (`guard state.isOpen` at :77), so **its items' `.keyboardShortcut`s
  are not registered while it is closed.** SwiftUI's command shortcuts are live
  whether or not any menu is open. That needs a pass that renders the commands
  for registration only. `isolatedForBackground()` is the wrong tool, because it
  throws the shortcut registry away (RenderContext+TUIContext.swift:117-151).
- **`KeyboardShortcutRegistry`** (Views/KeyboardShortcutRegistry.swift:34): app
  shortcuts plus a defaults tier, fired at InputHandler layer 3.5.
- **`FocusedValue`/`FocusedValues`** (Focus/FocusedValue*.swift), shipped in
  W09. Commands act on the focused content through these. A reader drawn *before*
  its publisher lags a frame (B34). Bars drawn *after* the content do not.
- **Focus sections.**
  - `registerSection` (Focus.swift:1108) auto-activates the first section
    registered.
  - `markSectionFocusOptional` (:1147) lets a section rest unfocused. Pointer-opened
    menus use it; toolbar sections need it.
  - Tab traversal follows registration order.

#### 2.7 Who depends on today's chrome

- **Example.**
  - `.appHeader { DemoAppHeader(…) }` on **41 page files**.
  - `.statusBarItems` in 7 files.
  - `.chromeStyle(appHeader:statusBar:)` at the scene (Example/main.swift:53).
  - The Theme page drives that scene-level `.chromeStyle(appHeader:statusBar:)`.
  - The quit item's bar is relied on implicitly.
- **Stress.**
  - Scenarios render with `renderToBuffer`, with no chrome (Stress/Headless.swift:14).
  - **Sessions** run through `HeadlessApp` with the real `RenderLoop`.
    `SessionHost` (Stress/Sessions/Session.swift:132) is a bare `WindowGroup`,
    so every session today carries the quit item's three-row bar.
  - `MenusPage`/`ThemesPage` use `.appHeader`, and `KeyRows` uses `.statusBarItems`.
- **TerminalClientQuirks**: `.appHeader` plus `.statusBarItems` (main.swift:81-89).
- **Docs**:
  - README quick start (:49) and module list (:88, :306, :317);
  - DocC `StatusBarGuide`, `KeyboardShortcuts`, `AppLifecycle`, `RenderCycle`, `Architecture`;
  - compatibility doc §2.6 and the §4c rows;
  - `parity-map.json`: the `renamed`/`differentShape` entries for `ToolbarItem`,
    `ToolbarContent`, `ToolbarContentBuilder`, `ToolbarItemPlacement`,
    `ToolbarPlacement` and `DefaultToolbarItem`, and the `Commands*` family.
- **Tests**: about 33 files mention the header and about 67 the status bar.

#### 2.8 Incidental findings (not A28, worth a line each)

- **Doc drift.** App.swift:136-139 says the bars' default is `ChromeStyle.rule`.
  Both state objects default to `.bordered` (AppHeaderState.swift:74,
  StatusBarState.swift:194).
- **Bare `a` is unconditional.** It cycles the border appearance in every app,
  whether or not `showAppearanceItem` is set (InputHandler.swift:359-362). `t`
  is gated on `showThemeItem`. In an opt-in world this is a hard-coded chrome
  default (owner question 6).

---

### 3. SwiftUI's surface, read for a terminal

Availability below is macOS, which is what `api_parity.py` judges. iOS-only
spellings are noted where ported iOS code uses them.

#### 3.1 Bars (`ToolbarPlacement`, the `for:` argument)

| SwiftUI | Terminal reading |
|---|---|
| `.automatic` | Whichever bar the modifier's context implies: the window bars, or the stack's bar |
| `.windowToolbar` (macOS) | The **top bar**: row 1, or row 2 under a menu bar |
| `.navigationBar` (iOS) | A `NavigationStack`'s bar |
| `.bottomBar` (iOS) | The **bottom bar**, which is today's status bar |
| `.tabBar` | A `TabView`'s tab strip. `toolbarVisibility(.hidden, for: .tabBar)` hides it. Later stage |
| `.accessoryBar(id:)` (macOS) | An extra row under the top bar. Cheap once the host exists |

#### 3.2 Item placements (`ToolbarItemPlacement`)

| Placement (macOS unless noted) | Where it goes |
|---|---|
| `.navigation` | Top bar, leading (after a stack's Back/crumbs) |
| `.principal` | Top bar, centre (replaces the title there) |
| `.primaryAction`, `.automatic` | Top bar, trailing |
| `.secondaryAction` | Top bar, trailing, before the primary items; first to drop when the row overflows |
| `.status` | **Bottom bar** (iOS reading; macOS centres it in the window toolbar). Decided in §9, with a veto |
| `.bottomBar` (iOS) | Bottom bar |
| `.confirmationAction`, `.cancellationAction`, `.destructiveAction` | Inside a sheet or alert: its button row, bound as `.keyboardShortcut(.defaultAction/.cancelAction)`. Outside one: trailing top bar, as macOS does |
| `.keyboard` | Bottom bar, leading, while a text input inside the declaring subtree has focus |
| `.accessoryBar(id:)` | That accessory row |
| `.topBarLeading/Trailing`, `.title/.largeTitle/.subtitle` (iOS) | Aliases of navigation/primary and of the title slot. Cheap, and helps ported iOS code |

#### 3.3 The 44 symbols in A28, by verdict

The full list is in `TUI-session-notes/plan/w15_symbols.txt`.

- **Implement.**
  - `View.toolbar(content:)`, in both the `ViewBuilder` and `ToolbarContentBuilder` forms;
  - `ToolbarItemGroup` (2 inits) and `LabeledToolbarItemGroupContent`;
  - `ToolbarSpacer` and `SpacerSizing` (`.fixed` is one cell, `.flexible` is a `Spacer`);
  - `toolbarVisibility(_:for:)`;
  - `toolbarBackground(_:for:)` and `toolbarBackgroundVisibility(_:for:)`: the
    bar's fill, or no fill, instead of `palette.appHeaderBackground`/`statusBarBackground`;
  - `toolbarItemHidden(_:)`;
  - `toolbarRole(_:)`/`ToolbarRole`: `.editor` puts the title at leading,
    `.automatic` is the TUI default;
  - `toolbarTitleMenu`/`ToolbarTitleMenu`: the title becomes a pull-down `Menu` trigger;
  - `ToolbarLabelStyle` and `\.toolbarLabelStyle`: map onto `labelStyle`, now
    that `Image(systemName:)` draws glyphs;
  - `contentToolbar(for: .tabViewSidebar)` and `ContentToolbarPlacement`: the
    foot of B76's sidebar list.
- **Implement under the window-toolbar-styles reading (A21, owner question 7).**
  `DefaultWindowToolbarStyle`, `UnifiedWindowToolbarStyle`,
  `UnifiedCompactWindowToolbarStyle` (with `showsTitle:`) and
  `ExpandedWindowToolbarStyle`, through `Scene.windowToolbarStyle(_:)`. The
  decisions doc sent these to option 1 because "the terminal owns" the window
  toolbar. Under opt-in chrome TUI draws the top bar itself, so that reason
  no longer holds.
- **Follow other answers.**
  - `toolbarTitleDisplayMode` and `tabBarMinimizeBehavior` follow O8. Under
    (b) the first ships inert, and the second collapses to `TabViewStyle.compact`.
  - `toolbarColorScheme(_:for:)` follows A17 (keep it absent with `preferredColorScheme`).
- **Leave as gaps rather than refusals.** The customisation family:
  `toolbar(id:content:)`, `CustomizableToolbarContent` and its 4 members,
  `ToolbarCustomizationBehavior` (3) and `ToolbarCustomizationOptions` (3). A
  grid could do this (A28 option 3: a reorder sheet saved by `id:`, about 2
  days). It is just not first.

**The real surface is larger than 44.** Deleting today's `renamed` entries for
`ToolbarItem`, `ToolbarContent`, `ToolbarContentBuilder`,
`ToolbarItemPlacement`, `ToolbarPlacement` and `DefaultToolbarItem` makes their
members gaps too:

- `ToolbarItem`'s three inits and `id`;
- eleven macOS placement statics and three bar statics;
- `DefaultToolbarItem(kind:placement:)`, which goes with O17.

The `Commands*` family adds roughly forty more (§3.5).

#### 3.4 Where `StatusBarItem` fits

The owner calls the status bar "really just a bottom toolbar". The bar is
indeed just that. **What TUI puts in it is its own thing:**

- a line of key hints;
- per focus section, with merge or replace composition;
- system entries for quit, theme, appearance and the live Escape/Return verbs;
- the tooltip row.

A `StatusBarItem` is a key binding with a label. Its action fires at
InputHandler layer 1 whether or not anything draws it. So:

- **`.statusBarItems { }` stays.** It is TUI-native (§4c). It declares bindings
  and hint labels, and has no effect on presence.
- **The hint line becomes content an app places.** The existing public view
  `StatusBar` gets a parameterless `init()` that reads the live
  `StatusBarState`. An app opts in with
  `.toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }`.
- **The quit item no longer creates a bar.** `q` keeps quitting (layer 4) with
  no bar.
- **`ToolbarItem` stops mapping to `StatusBarItem`** in `parity-map.json`.

#### 3.5 Commands, and where a menu bar sits

The SwiftUI surface:

- `Scene.commands(content:)`, `commandsRemoved()`, `commandsReplaced(content:)`;
- `Commands`, `CommandsBuilder`, `CommandMenu` (4 inits), `CommandGroup`
  (`before:`/`after:`/`replacing:`);
- `CommandGroupPlacement`, with 20 statics: `appInfo`, `appSettings`,
  `appTermination`, `newItem`, `saveItem`, `undoRedo`, `pasteboard`,
  `textEditing`, `sidebar`, `toolbar`, `help`, and the others;
- `EmptyCommands`, and the five standard sets (`SidebarCommands`,
  `ToolbarCommands`, `TextEditingCommands`, `TextFormattingCommands`,
  `InspectorCommands`).

The recommended reading is refusal-review **O13 (b)**:

- **Where.** The menu bar is the **top row**, above the top bar. Commands are a
  *Scene* modifier, so its presence is known before the walk. It never needs P2.
- **Contents.** An app menu (`appInfo`, `appSettings`, `appTermination`),
  then the app's `CommandMenu`s in declaration order, then the standard menus
  that have content:
  - File: `newItem`, `saveItem`, `importExport`, `printItem`;
  - Edit: `undoRedo`, `pasteboard`, `textEditing`;
  - View: `toolbar`, `sidebar`;
  - Help.
- **Built-ins in the standard groups.**
  - `appTermination` gets Quit on `QuitShortcut`.
  - `appSettings` gets `openSettings`, which waits on O9 (c).
  - `undoRedo` gets A1's `UndoManager` on Ctrl-_.
  - `pasteboard` gets B9's copy, cut and paste.
  - `textEditing` gets B81's Find on Ctrl-G.
  - `sidebar` gets the split view's toggle.

  An app that never shows the menu bar still has every one of these keys. That
  is A1's "reachable without it".
- **Keys.**
  - F10 opens the first menu.
  - Left and Right move between menus. That is a small new handler: adjacent
    pull-downs while open.
  - Escape closes.
  - Alt-letter opens a menu where the terminal sends Meta. Terminal.app does not
    by default (Terminal compatibility survey.md:908, :3819).
  - A click on a title opens it.
  - **F10 and Alt-letter must be measured and recorded in
    Terminal compatibility survey.md** (CLAUDE.md, terminal-specific behaviour).
  - The menu bar is not a Tab stop. While open, each menu is a modal section,
    exactly as a pull-down `Menu` is today.
- **Shortcuts while closed.** Each frame, *after the content*, the bar renders
  the command content in a new isolation, `withRegistrationOnlyChannels()`:
  - throwaway focus manager, key dispatcher and status bar;
  - regions dropped;
  - a **live** `KeyboardShortcutRegistry`.

  Because it runs after the content, a `@FocusedValue` read in a command is
  current, with no B34 lag. Cost: one small render per frame, and only for apps
  that declare commands.
- **`onCommand(_:perform:)`** stays CONFIRM-declined. It takes an Objective-C
  `Selector` and needs the responder chain.

#### 3.6 Titles

- `.navigationTitle` outside a stack currently goes nowhere. The Example uses
  `.appHeader` for exactly that reason; see the comment at
  Example/Pages/MenusPage.swift:50.
- In the new model, a root title shows in the top bar's title slot *when there
  is a top bar*. `toolbarRole` decides where the slot sits, and `.principal`
  items replace it.
- A title alone does not create a top bar. That is decided here, with a veto.
  The window title (OSC 2, refusal review P15) is the natural home for a title
  with no bar.

---

### 4. The two questions every design answers

#### 4.1 How is a bar's height known before the content it displaces?

| Policy | Mechanics | Cost |
|---|---|---|
| **P1: estimate and correct** (today's header) | Lay out with last frame's height. If the walk disagrees, walk again in the same frame and throw the first away | A second full walk on every frame where chrome changes. **The effect leak in a discarded walk cannot be fixed** (pinned `withKnownIssue`). Upstream's per-walk effect staging (#60/#61) is the only cure, and it was declined |
| **P2: last frame's answer** | Bars are reserved from last frame's declarations. This frame's declarations are compared after the walk. A mismatch adopts the new set **next frame** (a render request through the scheduler, so a still screen still gets it). Frame 1 seeds from the existing measure-mode walk (RenderLoop.swift:709), with `.toolbar` registering there under an environment flag | No discarded walk, ever. On the frame where a bar appears or goes, that frame is drawn at the old reservation: a blank bar row for one frame, or the content shifting a row one frame (≥16.7 ms) late. Needs an oscillation guard (§11) |
| **P3: structural only** | A bar exists only if declared above the content (the scene, or a container whose depth is known) | No lag and no discard. But `.toolbar { }` deep in a page cannot create a bar, which breaks the commonest ported idiom unless something structural already reserved one |

The menu bar is P3 for free (`Scene.commands`). `NavigationStack`'s bar is P3
for free at depth > 0. Window-level toolbars and the bottom bar need P1 or P2.

#### 4.2 Who draws the bars?

- **`RenderLoop`, out of the tree** (today). This needs coordinate translation,
  overlay lifting, region shifting, per-bar diff regions and payload forwarding.
  AppHeader.swift:81-103 is the catalogue of features that went missing because
  of this.
- **A scene-level host view**, in the tree but above the content. The bars are
  ordinary views stacked with the content in one buffer.
- **The declaring view itself**, as `safeAreaInset` does (B6,
  Modifiers/SafeAreaInsetModifier.swift). A bar sits beside whatever carries
  `.toolbar`.

---

### 5. Three designs

#### Design 1: generalise the out-of-tree bars (RenderLoop keeps the chrome)

**Mechanics.**

- `AppHeaderState` becomes `WindowChromeState`, an app-owned object created by
  `AppRunner`/`HeadlessApp` and published like today's `\.appHeader`. It holds
  slots `menu`, `top` and `bottom`, each with a fixed content-row count, a
  reservation (P2) and this frame's entries.
- `.toolbar` publishes `ToolbarEntry` values. Each entry carries:
  - its placement;
  - an `AnyView`;
  - the declaration site's `EnvironmentValues`, which is a copy-on-write
    dictionary, so capturing it costs a retain;
  - an identity path;
  - an order.

  Publication uses a preference key with an appending `reduce`, declared with
  `recordRenderSideEffect` as `.appHeader` is today (AppHeaderModifier.swift:88).
- After the walk, `RenderLoop` builds each reserved bar as a view,
  `_ToolbarBar(entries, style)`, in its own optional focus section. Then it
  shifts regions, lifts overlays, and writes **four** diff regions:
  `OutputRegion` gains `.menuBar`/`.bottomBar`, and `.appHeader` becomes `.topBar`.
- The correction re-render is deleted in favour of P2.
- Mouse translation becomes "below the top chrome".
- The status bar's pre-walk height is replaced by the bottom slot's reservation.

**What it costs.**

| | |
|---|---|
| Work | About 2 days design-specific, on top of the common pieces (§6) |
| Hot path | About zero. Bars are built once per frame, as the header and status bar are today. The correction walk is gone. Scenario A/B is unaffected, since `renderToBuffer` never sees `RenderLoop` |
| Measure/render parity | No new risk. `RenderLoop` sizes the content explicitly |
| Memo | Entries go out through a preference, so any memo above a `.toolbar` refuses to serve, as above `.appHeader` today |
| Focus/input | Bar sections register after the content's. Under a modal, bars render through an isolation and their regions are dropped. The hint line keeps today's live regions |
| Risk | The four special cases (coordinates, lifting, region shifts, chrome runs) each grow by one bar. Every payload a bar carries still has to be forwarded by hand |

**What it makes possible.** SwiftUI `.toolbar` parity and opt-in chrome, with
the smallest change to the frame's shape. It does nothing for the out-of-tree
bug class.

#### Design 2 (recommended): chrome is views, under a scene-level host

**Mechanics.**

- `WindowGroup.renderScene` (App.swift:846) renders a private
  `_WindowChromeHost(content:)`, a `_*Core` that is `Renderable` and
  `Layoutable`, over the **whole** terminal. `RenderLoop` passes the full size
  and no longer subtracts anything.
- Per frame, the host:
  1. Reads its reservation from `WindowChromeState`:
     - **menu** if the scene declared commands;
     - **top** and **bottom** from last frame's declarations, from
       `toolbarVisibility`, and from the tooltip row (resolved before the walk,
       as now).
  2. Computes `contentRect` as the terminal minus the reserved rows, publishes
     `overlayContentHeight` (moved from RenderLoop.swift:756), and pushes a
     preference scope.
  3. Renders the content **at the content's existing identity**, so no `@State`
     or focus ID moves. The host stores nothing of its own in `StateStorage`, so
     the negative-`StateIndex` rule does not bite. The content is centred in
     `contentRect` exactly as `centerBuffer` does today (App.swift:936).
  4. Pops the `ToolbarEntry` values, and **composites the content's overlays
     inside `contentRect`**. That is today's RenderLoop.swift:584 call, moved,
     so a modal's dimming still stops at the chrome.
  5. Renders each reserved bar as a real view, `_ToolbarBar` (composition: an
     `HStack` of leading, principal and trailing groups with `Spacer`s, framed
     by `ChromeStyle`'s existing drawing, `ChromeStyle.ruleRow`/`BorderRenderer`),
     in its own **optional** focus section, under a child identity:
     - item identities come from the declaring view's identity path plus the
       item's index or `id:`, so button focus IDs stay identity-derived;
     - under a modal (`activeSectionIsModal`) the top bar renders inert and its
       regions are dropped, which is today's header rule;
     - the hint line keeps its regions, which is today's status-bar rule.
  6. Renders the menu bar the same way, plus the registration-only commands pass.
  7. Stacks menu, top, content and bottom with `appendVertically`, which already
     carries regions, overlays, runs and opacity claims (FrameBuffer.swift:373).
     It composites the bars' **anchored** overlays (a toolbar `Menu`'s drop-down,
     a menu-bar menu) over the full frame, and their **centred** ones (a sheet
     from a toolbar button) inside `contentRect`. That is the split
     `liftingOverlays` makes today (AppHeader.swift:148-153), done once in the
     right place.
  8. Compares this frame's declared set with the reservation. On a mismatch it
     stores the new set and asks for a frame (P2).

**What `RenderLoop` loses.**

- `AppHeaderState` and its file;
- `renderWidth`;
- `applyChromeStyle`, which moves into scene configuration;
- the first-frame header walk, which becomes the host's seed;
- the correction re-render;
- `buildAppHeaderBuffer`/`buildStatusBarBuffer`/`liftingOverlays`;
- the region shifts;
- `noteStatusBarPlacement`;
- two of the three `OutputRegion`s, and the three-surface opacity resolution
  (the bars paint `.background(palette.…Background)` themselves);
- `chromeRuns`;
- `MouseEvent.inContent(belowHeaderOf:)` at both call sites.

`InputHandler` is unchanged. Layer 1 still asks `StatusBarState` for item
bindings.

**What it costs.**

| | |
|---|---|
| Work | About 4 days design-specific. The move itself is about 2.5 days and must be byte-identical. The rest is P2, the compositing split, and the test churn where tests assume header offsets |
| Hot path | Expected neutral, **not measured**. The diff writer keeps one line-reuse cache instead of three, and the bars become ordinary rows in it. Stacking costs O(rows) of line appends, about what `writeFrame` already pays per region. The correction walk goes. There is no `RenderContext` field: the seed flag is an `EnvironmentValues` key read only by `.toolbar` |
| Measure/render parity | The host fills its proposal in both passes, and bar rows are constants. Low risk |
| Memo | As Design 1. The host is never under a memo (it is the scene root). Run the render-memo verifier on sessions |
| Focus/input | Ring order is content, then top bar, then bottom bar. Bars render after the content, and their sections are optional, so the bars never take the initial focus. "Tab enters at the edge" holds. Toolbar buttons' `.keyboardShortcut`s are live (not isolated). Drag previews must attach to the full frame, because mouse coordinates are no longer translated (test the drag suites) |
| Risk | The modal compositing move and the coordinate change touch drag and drop, popovers from the header, and the replay frame's `startRow`. Contained by doing step 2 of §10 as a pure move, guarded by golden snapshots and the PTY smoke walk |

**What it makes possible.**

- Chrome stops being a second rendering pipeline: one coordinate space, and no
  hand-forwarded payloads.
- The same host serves:
  - `NavigationSplitView` per-column toolbars later;
  - the `.accessoryBar(id:)` rows;
  - `.tabBar` visibility.
- `RenderLoop` shrinks.
- A frame is one walk, always.

#### Design 3: the declaring view hosts its own bar (`safeAreaInset`-style)

**Mechanics.**

- `.toolbar { }` becomes a layout modifier built on `SafeAreaInsetModifier`'s
  layout:
  - a top bar if *its own* items include top placements;
  - the content, proposed whatever is left;
  - a bottom bar if its items include bottom placements.

  Height comes from its own items, never from the content, so there is no
  circularity, no lag and no P2.
- **Merge-up rule.** An inner `.toolbar` whose bar an enclosing host already
  draws publishes into that host instead of drawing its own:
  - the enclosing `.toolbar`;
  - `NavigationStack` at depth > 0;
  - a sheet's button row.
- The menu bar is a scene host, the only scene-level chrome.
- The hint line is a bottom-bar item, so it is dimmed under modals and its
  regions drop. Alternatively it stays as `RenderLoop` chrome behind a
  TUI-specific scene opt-in, which keeps half of today's out-of-tree path.

**What it costs.**

| | |
|---|---|
| Work | About 2 days design-specific |
| Hot path | One more layout level wherever `.toolbar` is used. Nothing per frame otherwise |
| Parity | As `safeAreaInset`, already shipped (B6) |
| Memo | A local bar is ordinary content, so memo-friendly. Only merging publishes |
| Focus/input | Bars are in the page's sections. Dimmed and inert under modals, including the hint line, which then shows the modal's keys, dimmed |
| Risk | **Placement diverges from SwiftUI.** A `.toolbar` deep in a page draws a bar *there* unless an ancestor declared one. Ported code puts `.toolbar` on a `List` and expects the window toolbar. Under a modal it either dims the hint line or keeps two pipelines |

**What it makes possible.** It is the simplest model to explain ("a toolbar is
a `safeAreaInset`"), and it has no frame lag at all.

#### Side by side

| | D1 | D2 | D3 |
|---|---|---|---|
| Discarded walks | none (P2) | none (P2) | none |
| Frame of lag on chrome change | yes | yes | no |
| SwiftUI placement semantics | yes | yes | partial (merge-up) |
| Chrome undimmed under modals | yes | yes | no, unless the hint line stays out of the tree |
| Out-of-tree pipeline | kept, grows | **deleted** | half kept, or deleted with dimmed hints |
| Days, toolbars and opt-in, without the menu bar | ~11 | ~13–14 | ~11 |
| Menu bar | +4–5 | +4–5 | +4–5 |

---

### 6. Recommendation

**Design 2 with P2, a structural menu bar, and the opt-in rules of §0.**

1. **It closes the known effect leak** instead of building effect staging around
   it. The 2026-08-07 decision was "the chrome redesign is happening anyway".
   This is that redesign.
2. **It is the only design where every bar is a view in the normal pipeline.**
   That is what CLAUDE.md asks of public controls, and it ends the
   bare-`FrameBuffer(lines:)` payload losses the header has suffered (four so
   far, AppHeader.swift:81-103).
3. **It keeps SwiftUI's semantics.** Items declared anywhere join the window's
   bars, and the bars stay undimmed and keep today's modal behaviour.

The price is a frame of lag when a page's chrome changes. That happens only on
the frame a bar is reserved or released. An app that declares its bars at the
root, as the Example will, never pays it.

**Common pieces, in days, for any design:**

| Piece | Days |
|---|---|
| Toolbar types and builder, `.toolbar` ×2, entry collection | 2 |
| `_ToolbarBar` layout, focus section, keyboard reach | 1.5 |
| Visibility, background, hidden, role, title menu, label style, spacer, window toolbar styles | 1.5 |
| `NavigationStack` bar hosts a pushed screen's items, plus O17 `.title` | 1 |
| Sheet button row from confirmation/cancellation placements | 1 |
| Migration: delete `.appHeader`; opt-ins in Example, Stress and Quirks; docs; tests | 2.5–3 |

---

### 7. The end state, as an app writes it

```swift
@main struct NotesApp: App {
    var body: some Scene {
        WindowGroup { NotesView() }
            .commands {                                    // opt-in: the menu bar row
                CommandGroup(replacing: .newItem) {
                    Button("New Note") { … }.keyboardShortcut("n")
                }
                CommandMenu("Format") { … }
            }
            .windowToolbarStyle(.unifiedCompact)           // A21: compact chrome, app-wide
    }
}

struct NotesView: View {
    var body: some View {
        NoteList()
            .navigationTitle("Notes")                      // drawn in the top bar's title slot
            .toolbar {
                ToolbarItem(placement: .primaryAction) {   // top bar, trailing
                    Button("New", systemImage: "plus") { … }
                }
                ToolbarItem(placement: .bottomBar) { StatusBar() }   // the key-hint line, opted into
            }
            .statusBarItems { StatusBarItem(shortcut: "d", label: "delete") { … } }
    }
}
```

An app with none of this gets every row of the terminal. `q` still quits.
Escape and Return still do what the focused control says.

---

### 8. Questions only the owner can answer

1. **Presence lag.** When a page's chrome appears or goes, accept one frame
   drawn at the old layout, with no discarded walk (closing the known leak)?
   Or keep re-rendering in the same frame (no flash, leak stays)?
   *Recommend: accept the frame.*
2. **Placement model.** Should `.toolbar` items join window-level bars, as
   SwiftUI does (D1/D2)? Or should each draw beside the view that declares it,
   like `safeAreaInset` (D3)? *Recommend: window-level, D2.*
3. **The hint line.** Is TUI's key-hint line a view the app places in the
   bottom bar (`StatusBar()`)? Or a bar switched on by a TUI-specific scene
   modifier? *Recommend: a view; the README and template show it.*
4. **Menu bar display.** Does declaring `.commands { }` show the menu bar by
   itself? Or does display need a separate opt-in, with the commands' keys live
   either way? *Recommend: declaring shows it. Items without shortcuts would
   otherwise be unreachable.*
5. **Menu bar keys.** F10 to enter, Alt-letter where the terminal sends Meta, a
   click. Not in the Tab ring. Agreed? *Recommend: yes, after measuring F10 on
   Terminal.app and iTerm2.*
6. **Bare-key defaults with no chrome to show them.** Keep `q` quit live. Make
   `a` (appearance) and `t` (theme) opt-in, as `t` nearly is already?
   *Recommend: yes. A bare `a` restyling every TUI app is a hard-coded
   chrome default.*
7. **A21, compact app-wide.** Should one scene-wide style, spelt with SwiftUI's
   `.windowToolbarStyle(_:)`, govern every bar? The mapping would be
   `.unifiedCompact` to compact, `.unified` to rule, and `.expanded` to
   bordered. `Scene.chromeStyle(appHeader:statusBar:)` and its per-bar split
   would go. *Recommend: yes. Later, let a short terminal pick compact
   automatically if B3 makes it compact. Folding compact into O14's
   `ControlSize` is a separate call.*
8. **`.appHeader`.** Delete it outright, with no shim, moving the 41 Example
   pages to `.navigationTitle`/`.navigationSubtitle` plus one root `.toolbar`?
   *Recommend: yes.*

### 9. Decided here unless vetoed

- `.status` goes to the **bottom** bar (iOS reading). macOS centres it on top.
- A root `.navigationTitle` alone creates no top bar. It sets the terminal's
  window title once P15's OSC 2 work lands.
- Toolbar items join the Tab ring as optional sections, after the content.
  Today's mouse-only header controls are the thing to stop repeating.
- `NavigationStack`: a pushed screen's top items go in the stack's own bar. The
  root's items go to the window's top bar (macOS behaviour). The stack does not
  grow a root bar.
- Customisation (`toolbar(id:)` and its family) stays a gap, not a refusal.
- `StatusBar`, `StatusBarItem` and `.statusBarItems` keep their names. Renaming
  them to "key hints" is churn without a user.
- A `.statusBar`-style tooltip with no bottom bar still takes a transient row
  (today's behaviour). Its height is known before the walk.
- Stress `SessionHost` opts into today's chrome (a bordered bottom bar with
  `StatusBar()`) in the same commit that makes chrome opt-in. Session geometry
  then stays the same, and A/B across the change stays like for like.

---

### 10. Staged plan: one commit per step, docs in the same commit

**Gates for every step:**

- 6.2.4 build plus the full suite (`swift test --skip-build -q`);
- zero warnings, `TUIKIT_BENCHMARKS` target included;
- Stress `--selfcheck` for drawing changes;
- `TUIKIT_VERIFY_RENDER_MEMO=1 TUIKIT_VERIFY_MEASURE_MEMO=1` session runs where
  marked.

**"Sessions"** means `ab_bench.py` over `session/editor`, `session/inbox`,
`session/menus` (header), `session/themes` (header plus system items),
`session/settings`, `session/notes` and `session/log`. These are the only Stress
paths through `RenderLoop`.

0. **Consolidate scene configuration (pure refactor).**
   - Replace the five `Root*ProvidingScene` protocols and their 30 forwarders
     with one `SceneConfiguration` struct gathered by one walk, innermost wins
     per field.
   - Tests: the existing scene-modifier composition tests, unchanged.
   - A/B: none needed (once per frame), but run `--quick` scenarios as a sanity
     check.
1. **Pin today's chrome behaviour.**
   - Add a test for the suspected latent bug in §2.3: `showSystemItems = false`
     plus declared items draws on-screen. If it is red, mark it a known issue.
   - Add golden snapshots of the header, the status bar and both, at all three
     `ChromeStyle`s; a header `Menu` drop-down; a sheet over a header; a drag
     preview.
   - These are the oracle for step 2.
2. **`_WindowChromeHost`: move both bars into the scene, behaviour-identical.**
   - The host draws today's header (from `AppHeaderState`) and status bar (from
     `StatusBarState`) as views.
   - Delete the out-of-tree paths: lifting, region shifts, mouse translation,
     `OutputRegion`s, `chromeRuns`.
   - **Keep P1** (the host runs the correction itself) so this commit changes
     no behaviour.
   - Tests: step 1's goldens byte-identical, the PTY smoke walk
     (`Tools/Smoke/ci-pty-smoke.sh`), the drag/drop and popover suites.
   - **A/B: sessions** (before and after must sit within the noise; ~10% means
     optimise first).
3. **P2: adopt chrome next frame. Delete the correction re-render.**
   - Tests:
     - `RenderPassScopeTests.correctionRerenderLeaksEffects` flips from known
       issue to a plain test that every frame is one walk;
     - adoption takes exactly one extra frame;
     - a still screen still gets it, through the scheduler;
     - an oscillating page pins and reports.
   - A/B: sessions, especially `session/menus`, whose header comes and goes.
4. **Toolbar types and `.toolbar` collection, top and bottom bars.**
   - Add `ToolbarContent`, `ToolbarItem`, `ToolbarItemGroup`, `ToolbarSpacer`,
     the placements, the builder, both `.toolbar(content:)` forms and
     `_ToolbarBar`.
   - Delete the `renamed`/`differentShape` parity entries.
   - Tests:
     - each placement lands where §3.2 says;
     - focus ring order, and that a toolbar section never takes the initial
       focus;
     - item `@State` survives across frames;
     - `.foregroundStyle` and `.disabled` above `.toolbar` reach its items
       (CLAUDE.md's control test);
     - shortcuts on items fire;
     - inert under a modal;
     - the memo verifier is clean with `.toolbar` under a memoised ancestor.
   - A/B: `keyrows` and `--quick` (modifier cost); sessions unchanged.
5. **Make chrome opt-in; delete `.appHeader`.**
   - The quit item no longer creates a bar. `StatusBar()` gets its
     parameterless `init`.
   - Migrate Example (41 pages, ContentView declares the bars once),
     TerminalClientQuirks, Stress `MenusPage`/`ThemesPage`, and `SessionHost`'s
     opt-in.
   - Docs: README quick start, DocC (`StatusBarGuide`, `KeyboardShortcuts`,
     `RenderCycle`, `Architecture`, `AppLifecycle`), compatibility §2.6
     rewritten and the §4c rows, decisions A28 moved to shipped.
   - Tests:
     - a bare `WindowGroup` draws every row;
     - `q` quits with no bar;
     - Example page smoke;
     - localization parity (Example strings move).
   - A/B: sessions (geometry is held by the opt-in).
6. **Bar modifiers.**
   - `toolbarVisibility`, `toolbarBackground` ×2, `toolbarItemHidden`,
     `toolbarRole`, `toolbarTitleMenu`, `ToolbarLabelStyle`, `contentToolbar`,
     and window toolbar styles in place of `chromeStyle` (pending question 7).
   - Tests: one per modifier, plus the style-to-height arithmetic
     (`ChromeStyle.barHeight` stays the single source).
   - A/B: none (no per-frame path).
7. **`NavigationStack` and sheets as toolbar hosts.**
   - A pushed screen's top items go in its bar. Implement O17's `.title` removal.
   - A sheet's confirmation and cancellation items become its button row with
     default and cancel shortcuts.
   - Tests: the existing `NavigationStack` suites (Escape-back, crumbs, focus
     restore) stay green, plus item placement and sheet Return/Escape.
   - A/B: `session/notes`, `session/settings`.
8. **Commands types and the menu bar (O13 b).**
   - Add `Commands`, `CommandsBuilder`, `CommandMenu`, `CommandGroup`,
     `CommandGroupPlacement`, `.commands`/`commandsRemoved`/`commandsReplaced`,
     and a `_MenuBarCore` built from the pull-down `Menu`.
   - Add the registration-only isolation.
   - Add F10, Left/Right and Alt-letter.
   - Record the measurements in **Terminal compatibility survey.md**.
   - Tests:
     - shortcuts fire with every menu closed;
     - a `@FocusedValue` command acts on the focused content the same frame;
     - Escape and focus restore;
     - no menu bar row without `.commands`.
   - A/B: add `.commands` to one session (say `session/editor`) and compare the
     per-frame cost against the same session without it. That cost is paid every
     frame.
9. **The standard command groups wired to the built-ins.**
   - Quit, settings (when O9 c lands), undo (when A1 lands), pasteboard (B9),
     find (B81), sidebar.
   - `SidebarCommands` and `TextEditingCommands` are the first standard sets.
   - Tests: each group's key works with and without the menu bar shown.

Steps 6–9 are independent of one another after step 5, and can land in any
order.

---

### 11. Risks and what to watch

- **P2 oscillation.** Consider a page whose layout at the smaller height stops
  declaring a bar, for example `ViewThatFits` picking a variant without
  `.toolbar`. It would flip every frame. The rule:
  - never release a bar in the frame after reserving it;
  - a flip back within a short window pins the union and reports it through
    the body-mutation diagnostic channel.

  P1 has the same exposure today; it is just hidden inside one frame.
- **Seed-walk pollution.** On frame 1 the seed walk is measure-mode, and
  measure passes walk the tabs a `TabView` is not showing
  (measure-side-effect class). A toolbar declared in such a tab could reserve a
  bar for one frame. P2 corrects it on frame 2. This is acceptable for frame 1
  only, which is why `.toolbar` registers during a measure *only* under the seed
  flag.
- **Harness-driven tests and sessions** step frames themselves, so a P2
  adoption shows up one step later. Write tests to render twice where adoption
  is the point.
- **Opacity.** Bars become painted surfaces in the tree, not separate
  `resolvingOpacity(surface:)` roots (RenderLoop.swift:1070-1073). Faded hint
  colours must still fade toward the bar's colour. Covered by a test in step 2.
- **The width hack goes.** Today's `renderWidth` exists because the header is
  laid out inside a padded tree. In D2 the host lays the bars out at full width
  by construction. Example/ContentView.swift:153 applies padding outside the
  pages, and that stops mattering.
- **Profile shares are hypotheses.** None of the cost figures above is
  measured. Each step's A/B is what decides it (tolerance: a few percent is
  fine; ~10% means optimise first).

