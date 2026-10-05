# SwiftUI API completion — lane D4T (tables): new judgement calls

*Lane D4T implemented the owner's decisions B46, A30, A31, B47, B45 and B44
(2026-10-05). Each call below came up on the way. The safe option shipped;
the alternative and its price are given. Numbered as the main decisions
document is: A = owner decision, B = basic shipped, C = declined.*

## B. Shipped the safe option

### B-D4T-1. Return's primary action acts on the cursor row's set, not on the selection as such

*`View.contextMenu(forSelectionType:menu:primaryAction:)` (decisions A30)*

**Measured on macOS 15.8** (a SwiftUI `Table` and `List` in an
`NSHostingView`, double-clicks and Return sent to the outline view):
a double-click selects the row it lands on and runs `primaryAction` with the
selection, which is then that row; Return runs it with the selection; Return
with nothing selected, and a double-click on empty space, run nothing. On a
table with no selection binding a double-click runs it with the clicked row,
and Return runs nothing.

On macOS the keyboard cursor IS the selection. In TUIkit it is not: the
arrows move a cursor and Space selects, so the cursor can rest on a row the
selection does not include. A30 described the set as "the selection, or the
cursor row when nothing is selected".

**Shipped:** the context menu's rule, applied to the cursor row — the whole
selection when the cursor row is in it, the cursor row alone when it is not.
It is A30's set wherever the two can be told apart by what macOS does (a
selected cursor row; a double-click, whose first click selects), and where
they cannot it acts on the row the cursor marks rather than on rows elsewhere
on the page, which matters when the action is "Delete". The same rule is what
Shift+F10 opens the menu on, so the menu and Return agree about a row. A table
or list with no selection binding acts on the cursor row, where macOS's Return
does nothing (its cursor not being a row apart from the selection).

**The alternative:** A30's wording, literally — the selection whenever it is
non-empty. One line in `RowContextMenuHost.activation(for:selection:)`.

### B-D4T-2. Ctrl-click on a list or table with a menu opens the menu, not a toggle

*`View.contextMenu(forSelectionType:menu:primaryAction:)`,
`TableRowContent.contextMenu(menuItems:)` (decisions A30)*

TUIkit's rows toggle on Ctrl-click and Option-click — the stand-ins for ⌘,
which no terminal reports — and `.contextMenu` opens on Ctrl-click where a
terminal keeps the right button (iTerm2 does by default).

**Shipped:** on a list or table that has a menu to open, Ctrl-click is the
menu's, as it is on macOS; Option-click still toggles. A Ctrl-click on a row
with no menu of its own (a table whose rows have menus and this one does not)
is still a toggle. A list or table with no menu at all is unchanged.

**The alternative:** keep Ctrl-click as the toggle and leave the menu to the
right button alone, which strands iTerm2's default configuration without a
pointer route to the menu. Free.

### B-D4T-3. Shift+F10 only; the Menu key has no `Key`

*`View.contextMenu(forSelectionType:menu:primaryAction:)`,
`TableRowContent.contextMenu(menuItems:)` (decisions A30)*

**Shipped:** Shift+F10 opens a list's or table's menu on the cursor row, the
binding `.contextMenu` already uses for a focused view. The PC keyboard's Menu
key is not read: the kitty keyboard protocol reports it as a private-use code
(57363) TUIkit decodes to no key, and legacy terminals send nothing of their
own for it.

**The fuller version:** a `Key.menu` case, decoded from the kitty report and
honoured wherever Shift+F10 is (lists, tables, `.contextMenu`, tab context
menus). Adding a case to the public `Key` enum breaks every exhaustive switch
over it, in TUIkit and in apps; an hour, most of it the switches.

### B-D4T-4. A menu that builds nothing still takes the press, and reports an opening

*`View.contextMenu(forSelectionType:menu:primaryAction:)` (decisions A30)*

SwiftUI: "You can deactivate the context menu by returning nothing from the
closure." Whether the closure returns anything for a set is known only by
building it, and a press is answered between frames, where nothing can be
built. So a secondary click on a container with a selection menu opens the
menu's state, and the next frame — finding nothing to draw — closes it
without having shown it or taken the keyboard.

**Shipped:** that. The press is spent (it does not go on to a menu around the
container), and `.onMenuOpen(_:)` hears an opening for a menu nobody saw.

**The fuller version:** build the menu for the set at the press, in the
container's last render context kept for the purpose, and decline the press
when it is empty. Half a day, and a context held across frames, which the
framework otherwise avoids.

### B-D4T-5. A section header is lines of the row below it, not a row of its own

*`Section` as `TableRowContent`, `TableHeaderRowContent` (decisions A31)*

**Measured on macOS 15.8** (a SwiftUI `Table` with sections, in an
`NSHostingView`): each section with a header adds a row of its own, 28 points
high where a row is 24, drawn in the group-row style across the table's full
width, not pinned; Down from a section's last row lands on the next section's
first row, Up from the first row stops there, and select-all leaves the
headers out; a section with no header adds no row; a collapsed section keeps
its header and drops its rows; the header shows no disclosure control of its
own while the pointer is elsewhere.

A31's option 1 described the header as "an entry of its own among the drawn
bands … with the index arithmetic taught that some entries are not rows".

**Shipped:** the drawing and the behaviour measured, by another route. A
header is carried as lines of the row below it (or, after the last row, of
that row) — so every path that counts rows by their index into the data (the
window, the cursor, the selection, select-all, type select, the "N more rows"
indicators, the primary action and the context menus) keeps counting rows,
and a header is stepped over because it is not a row. Its lines are chrome
bands: a click there selects nothing, a right-click is the table's empty
space to a selection menu, and nothing lands there. A sectioned table takes
the multi-line layout, which already lays rows out at their own heights. A
collapsible section's header is the `List`'s: its disclosure triangle is a
control, so the keyboard reaches it with Tab.

Three edges follow. A table whose sections all have no rows draws its
placeholder, not their headers (there is no row to carry them). A
hierarchical table draws its sections' rows without their headers. Stripes
(`alternatingRowBackgrounds`) count rows, headers aside.

**The fuller version:** headers as entries of their own in the table's
numbering, with every path taught to skip them — what A31 sketched. It would
draw a table of empty sections, and put a header on screen when only it fits
in the viewport (today the row below it comes too, or neither). Two days: the
cursor, selection, select-all, reorder and drop offsets all translate
between the two numberings.

### B-D4T-6. A table section takes no section actions

*`SectionConfiguration.actions` (decisions B18)*

B18 recorded that `SectionConfiguration.actions` was always empty; B78 since
shipped `sectionActions(content:)`, which `actions` reads, so B18 is resolved
for sections of views. A section among a table's rows has none:
`sectionActions(content:)` is a `View` modifier and a row section is not a
view, in SwiftUI as here. Nothing shipped for it; noted so B18 can close.
