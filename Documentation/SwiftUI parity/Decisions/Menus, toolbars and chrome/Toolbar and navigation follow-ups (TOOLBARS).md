# Completing the SwiftUI API: decisions from lane TOOLBARS

*Lane TOOLBARS finished the toolbar work the owner's decision A28 started
([`Toolbars and opt-in chrome design study, A28 (2026-10-04).md`](<../../Design studies/Toolbars and opt-in chrome design study, A28 (2026-10-04).md>),
§10 steps 6 and 7, and the customisation family §3.3 left as a gap), the
fuller sheet hosting [`Toolbars and opt-in window chrome (D5C).md`](<Toolbars and opt-in window chrome (D5C).md>)
priced as B-D5C-3, and A21's link in a collapsed split view. Where that work
reached a judgement call the owner's answers did not settle, the safe option
shipped and is written up here, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):
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

### B-TOOLBARS-2. A navigation stack's bar keeps its title beside a pushed screen's principal items

*`ToolbarItemPlacement.principal` in a screen pushed onto a `NavigationStack`*

A pushed screen's top-bar items are drawn in the stack's bar (the A28 study,
step 7). That bar is TUIkit's own: the crumb trail, or ‹ Back and the title,
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
storage, as JSON in TUIkit's own encoding (`order`, `shown`), with nothing
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
TUIkitFoundation so this form, in TUIkitChrome, can reach the sidebar in
TUIkitTabs without a module edge.

**The fuller version:** the `.automatic` and other top-bar placements in a
`»` overflow pull-down at the row's trailing end, as iPadOS's sidebar has,
built on the customizable toolbar's overflow menu — about two hours; worth it
only if an app puts more there than a sidebar is wide.

## C. Declined

### C-TOOLBARS-1. `toolbarColorScheme(_:for:)` follows `preferredColorScheme(_:)`

*`View.toolbarColorScheme(_:for:)`*

The A28 study sends it to A17, which keeps `preferredColorScheme(_:)` out for
now (owner, 2026-10-04): a terminal's look is a palette, and TUIkit's palettes
do not come in light and dark pairs. A bar's fill is stated with
`.toolbarBackground(_:for:)`. Recorded in `parity-map.json`; it returns with
`preferredColorScheme` if light palettes are wanted for their own sake.

### C-TOOLBARS-2. `toolbarTitleDisplayMode(_:)` stays refused with its type

*`View.toolbarTitleDisplayMode(_:)`*

The refusal review's O8 (owner, 2026-10-12: omit the APIs that are inert on
macOS too, so they fail to compile) refused `ToolbarTitleDisplayMode`; the
modifier it feeds was still counted as an open gap. Recorded beside the type in
`parity-map.json`.
