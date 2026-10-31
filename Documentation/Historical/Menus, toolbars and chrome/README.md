# Menus, toolbars and chrome: how it came to be

One story per subject: pop-up menus, the menu bar, toolbars and the window's chrome. The menu engine's live design is in [Unifying the menu implementations](<../../Controls and presentation/Unifying the menu implementations.md>). Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Pop-up menus: submenus, type select and an alert's buttons](<Pop-up menus - submenus, type select and an alert's buttons.md>) | A `Menu` or a `Picker` inside a pop-up menu is a submenu, opened by Right and closed by Left or Escape, in the one engine every pop-up menu shares.  |
| [The menu bar](<The menu bar.md>) | `CommandMenu`, `CommandGroup`, the placements and `.commands` are drawn on the window's top row, in `TUICommands`. **Owed** work is listed in it. |
| [Toolbars and opt-in window chrome](<Toolbars and opt-in window chrome.md>) | A `.toolbar` draws its items in the window's bars, which are opt-in; a sheet or full-screen cover hosts its own toolbar round the view that declared it; a navigation stack's bar keeps its title beside a pushed screen's items; a customizable toolbar's items are customized from a panel hanging from the bar, kept per identifier.  |
