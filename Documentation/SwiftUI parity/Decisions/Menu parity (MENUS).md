# Completing the SwiftUI API: decisions from lane MENUS

*Lane MENUS worked through the open menu items of the 2026-10-18 inventory:
submenus in a pop-up `Menu` and a `.contextMenu` (a nested `Menu`, and a
`Picker`, which SwiftUI makes a submenu), type-ahead in menus and `Picker`
drop-downs, the modifiers an alert keeps on its buttons, the memos under
`.onMenuOpen`, and a popover closed by a click inside it. Where the work reached
a judgement call, the safe option shipped and is written up here, in the format
of [`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

*What SwiftUI does was measured on macOS 15.8 with a probe that reads back the
`NSMenu` SwiftUI builds for a `CommandMenu`, and the `NSAlert` it presents for an
alert:
[`Tools/SwiftUIProbes/Menu items and alert buttons/`](<../../../Tools/SwiftUIProbes/Menu items and alert buttons/menus.swift>).*

## B. Shipped the safe option

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

The default button answers Return by TUIkit's rule for every default button: when
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
- **The menu bar's Find submenu** (B-O13-8's fuller version), now that there
  are submenus: Find's own items as a submenu of Edit. Lane O13's to weigh;
  it needs the first item above for their keys.
