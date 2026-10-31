# Pop-up menus: submenus, type select and an alert's buttons

*Submenus in a pop-up `Menu` and a `.contextMenu`, type-ahead in menus and
drop-downs, and the modifiers an alert keeps on its buttons. Ids:
B-MENUS-1 to 3. The menu engine's design is live, in
[Unifying the menu implementations](<../../Controls and presentation/Unifying the menu implementations.md>).*

## In short

A `Menu` or a `Picker` inside a pop-up menu is a submenu, opened by Right and
closed by Left or Escape, in the one engine every pop-up menu shares. Type
select in an open drop-down or menu follows the list's rule. An alert keeps
`.disabled` and `.keyboardShortcut` on its buttons, and its default button
answers Return.

## How it unfolded

**2026-10-18, lane MENUS** worked through the open menu items of that day's
inventory. On 2026-10-23 the owner's B77-KEYTIME ruling extended type select's
hold on bare keys to open drop-downs and menus (in the lists topic).

**PICKER-POINTER-OPEN** (settled 2026-10-18): a `Picker`'s drop-down opened by
the pointer keeps its highlight on the current value. A pointer-opened `Menu`
and a combo box highlight nothing, by the 07-27 rule against a highlight on an
arbitrary first item, but a mis-click on the current value changes nothing.
Confirmed on macOS 15.8 (2026-10-27): a clicked `.menu` `Picker`'s pop-up
highlights its current value (`Tools/SwiftUIProbes/Picker pop-up
highlight/popup.out`).

## The record

### B-MENUS-1. An alert keeps `.disabled` and `.keyboardShortcut` on its buttons; its default button answers the Return the focused button lets through

*`AlertAction`, `alertActions(from:in:)`*

A dialog draws its actions' buttons itself, so it looks through the modifiers
written on each to find the `Button`, and it dropped them all. A macOS alert,
read back (`alert.out`, `dialog.out`), keeps two: `.disabled`, which disables the
button, and `.keyboardShortcut`, which gives it that key equivalent — Return for
`.defaultAction`, which also makes it the default button, and Escape for
`.cancelAction`. It shows none of `.help`, `.tint` and `.foregroundStyle`.

**Shipped:** the dialog keeps the two macOS keeps, wherever they are written on
the button, and leaves the rest as macOS does. A `.disabled(true)` anywhere
disables the button; the innermost `.keyboardShortcut` is put back on the
button where the dialog draws it, so a key equivalent chooses it; Escape answers
with a `.keyboardShortcut(.cancelAction)` button where no button has the
`.cancel` role, the role first where both are written (macOS gives both Escape,
which leaves the choice to the order AppKit asks them in).

The default button answers Return by TUI's rule for every default button: when
the focused control lets Return through, and a focused button keeps its own
Return (`KeyboardShortcut`'s documentation). A dialog opens with the focus on its
first button, so Return chooses that one, where macOS's alert gives Return to the
default button wherever the focus is (deviations W15).

**The fuller version:** the dialog opens with the focus on its `.defaultAction`
button, so Return chooses it until the person moves the focus, as on macOS. About
two hours: a focus request for that button's identity at the presentation's
first frame, pinned by a test, and a look at the drawn order, which puts a
`.cancel`-role button first in a row and so gives it the focus today. Not done
here because it changes what Return does in every existing dialog that marks a
default button, which is the owner's to weigh.

### B-MENUS-2. A `Menu` and a `Picker` in a pop-up menu are submenus, opened by Right and closed by Left or Escape

*`_MenuSubmenuRow`, `MenuPopupController.openSubmenu`, `renderMenuLevel`*

A `Menu` written in a pop-up `Menu` or a `.contextMenu` drew its own collapsed
control on a line of the menu, and choosing it closed the menu it was in; a
`Picker` drew a drop-down on a line the menu's arrows walked past. SwiftUI makes
both submenus (measured, `pickers.out`): a `Picker` of the menu, segmented or
palette style is a submenu titled by its label with the selected option
checked, an `.inline` one its label as a section header over its options in the
menu itself, a nested `Menu` a submenu whatever its style or primary action,
and a disabled one a submenu of disabled items.

**Shipped:** the same, in the menu engine every pop-up menu shares — a pop-up
`Menu`, a `.contextMenu`, a list's row menu, a toolbar pull-down, the menu
bar's menus. The submenu's row is a `Button` of the menu, so it takes the row's
look, with the submenu caret ▸ in the key-equivalent column; it publishes,
beside its ordinal, how to draw the submenu, and the menu draws the open one as
a layer of its own buffer, hung beside the row with its first item level with
it, so it goes wherever the compositor puts the menu. With no room on the
right it goes to the menu's left, and a chain of submenus goes on the way it
turned (`OverlayLayer.besideAnchorWidth`, `opensLeading`); with no room below it
slides up. The keyboard: Right or Return on the row opens the submenu with its
first item highlighted, Left or Escape closes it back to its row, and moving
the highlight off the row closes it; the keys go to the deepest submenu that
has a highlight, so one the pointer opened leaves them with its menu. In a menu
bar's menu, Right on a row that opens nothing steps to the next menu, and Left
at the top level to the one before. The pointer: over the row it opens the
submenu with nothing highlighted; over another row it closes it; a click on the
row opens it and chooses nothing, and a press-and-hold released on it leaves
the menu up. A radio-group picker draws inline, where macOS draws its label and
options as disabled items with no check (measured): a menu form nobody can use.
An inline picker's separators are placed as a `Section`'s are: SwiftUI builds
both alike, a separator either side of a section-header item, and AppKit draws
a menu with no separator at its top or bottom and never two in a row, whatever
its items (measured, `inline.out` and `shown.out`). The menu finds the picker
among its items, under the wrappers round it (`MenuSectionDrawing`); inside a
view of the app's own it does not look, and the picker draws its separators
itself, wherever it stands.

An item's key equivalent in a submenu works while the menu it is in is up,
whether or not the submenu is open, and — in a menu bar's menu — with every
menu closed, as a command's does: a closed submenu's items are rendered for
their registrations alone each frame (`registerMenuItemShortcuts`), from the
menu it opens from and from the menu bar's pass, where a `Menu` renders its
items so too.

Escape closes one level, as the lane's brief asked and as Windows and GTK
menus do; macOS, unmeasured here, is believed to close the whole menu. Recorded
as deviation W16.

**The fuller version**, each priced separately:
- **The pointer's diagonal.** A desktop menu keeps a submenu open while the
  pointer crosses other rows on its way into it (macOS's safe triangle,
  unmeasured); here the pointer over another row closes it at once, so the way
  to a submenu's lower items is across, then down. About a day: the direction
  of the pointer's last moves, and a grace of a few frames before another row
  takes the highlight.
- **The status bar's hint.** With a submenu's row highlighted, the bar could
  say "→ open"; it says what it says for any row. An hour and seven strings.
- **An inline picker inside a view of the app's own.** The menu could look into
  an item whose body is one view, evaluating that body as an alignment-guide
  query does, to place such a picker's separators too. About two hours, and
  one more body evaluation per such item each time the menu lays out.
- **The menu bar's Find submenu** (B-O13-8's fuller version), now that there
  are submenus: Find's own items as a submenu of Edit. Lane O13's to weigh;
  it needs the first item above for their keys.

### B-MENUS-3. Type select in an open drop-down and an open menu follows the list's rule, but a drop-down's first character fires no app shortcut behind it

*`TypeSelectBuffer`, `_PickerMenuHandler`, `MenuPopupController.typeSelect(_:)`, `InputHandler` layer 2.5*

A `List` and a `Table` find a row by its first characters; a `Picker`'s open
drop-down swallowed every character, and an open menu let them fall through.
On macOS an open menu, and an open pop-up button's menu, take them as type
select (AppKit's documented menu behaviour; not measured here, the probe's
window not taking the keyboard on this machine).

**Shipped:** both take them by the list's rule, through one `TypeSelectBuffer`:
the characters, the second's pause, the match from the highlight, a row found
by its title from its first letter or digit (so a toggle row's mark, a picker
option's check or an icon does not hide it). The first character of a prefix
gives way to a bare-key binding that claims it, as in a list (B77): in a menu,
a row's own key equivalent, an app's bare shortcut, the quit key, the help key;
in a drop-down, the quit key and the help key alone. The open drop-down holds
the keyboard (it grabs it, so no page handler or status item fires behind it),
so every app shortcut is behind it — a page's `Delete` on a bare `d` would
fire from under a drop-down whose `Date` the `d` was typed to find — and its
options carry no key equivalents of their own
(`TypeSelectingFocusHandler.givesWayToAppShortcuts`). An open menu, which holds
the keyboard without the focus, is asked at a layer of its own (2.5) after its
keys decline the character; the drop-down, a focused control, at layer 3 as the
list is.

One consequence to know: with a `Picker`'s drop-down open, the quit key as the
first character of a prefix now quits, where the drop-down swallowed it — the
list's rule, which the owner settled for bare keys in B77. A menu already let
it through.

**Superseded by the owner's ruling B77-KEYTIME (2026-10-23; built 2026-10-24,
lane KEYS):** "Where type select exists, bare keys never pass to shortcuts."
A list, a table, an open drop-down and an open menu take every character type
select takes, the first of a prefix included: no row's key equivalent, app
shortcut, status-bar item, quit key or help key hears one. The give-way and
`givesWayToAppShortcuts` are gone (`TypeSelectingFocusHandler.takesTypedCharacters`
says only whether a control takes characters now). What follows records the
rule before it.

**Left as it was:** an open menu's first character still reaches an app
shortcut on the page behind the menu, as every character did before the menu
had type select: the shortcut registry does not tell a row's key equivalent,
which must have the key, from the page's. Telling them apart is a scope for
what an open menu registers, as a pane has one (`KeyboardShortcutRegistry`'s
panes) — about half a day, and it changes what a page's shortcut does while
any menu is open, so not done in passing.

**The fuller version:** a closed `Picker` that type-selects as a focused macOS
pop-up button does (choosing the option without opening the menu) — unmeasured,
about two hours with a probe, and a change to what a character does on a
focused picker, so not done silently.
