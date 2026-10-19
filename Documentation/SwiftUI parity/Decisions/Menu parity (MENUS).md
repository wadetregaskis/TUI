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
