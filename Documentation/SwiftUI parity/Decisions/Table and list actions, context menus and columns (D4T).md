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
with no selection binding acts on the cursor row, where macOS's Return does
nothing (its cursor not being a row apart from the selection). A list with no
selection binding takes no selection menu, and so runs no primary action, on
Return or a double-click — as SwiftUI's takes neither, measured on macOS 15.8
(see the modifier's documentation).

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

### B-D4T-3. Shift+F10, and the Menu key where the terminal reports it

*`View.contextMenu(forSelectionType:menu:primaryAction:)`,
`TableRowContent.contextMenu(menuItems:)` (decisions A30)*

**Shipped:** Shift+F10 opens a list's or table's menu on the cursor row, the
binding `.contextMenu` already uses for a focused view; and the PC
keyboard's Menu key does the same, as a new `Key.menu`. Only the kitty
keyboard protocol reports that key (functional key 57363); the legacy
encodings send nothing TUIkit could tell from another key, so elsewhere
Shift+F10 is the route. Both go through one test (`KeyEvent.opensContextMenu`),
honoured by every menu Shift+F10 opens and closes: `.contextMenu`, a list's
or table's row menu, a tab's context menu in the strip and the sidebar.

The first cut shipped Shift+F10 alone, on the reasoning that a new `Key`
case breaks exhaustive switches over `Key`, in TUIkit and in apps. The
lane's review set that beside the new `RowAction.customizeColumns`
(B-D4T-7), which breaks exhaustive switches over `RowAction` just the same —
and `RowAction`'s own documentation already says that cases will be added
and that this is "a semantic-version event, not a reason to avoid switching
over this exhaustively". The same holds for `Key`, which gained F13…F20
before; so the two calls now agree, and the Menu key shipped. In TUIkit the
cost was one switch (the Example's key names).

### B-D4T-4. A menu that builds nothing still takes the press, and reports an opening

*`View.contextMenu(forSelectionType:menu:primaryAction:)` (decisions A30)*

SwiftUI: "You can deactivate the context menu by returning nothing from the
closure." Whether the closure returns anything for a set is known only by
building it, and a press is answered between frames, where nothing can be
built. So a secondary click on a container with a selection menu opens the
menu's state, and the next frame — finding nothing to draw — closes it
without having shown it or taken the keyboard.

**Shipped:** that. The press is spent (it does not go on to a menu around the
container), and so is the rest of its gesture — its release is not a click on
the row under it, whether or not a frame closed the menu in between — and
`.onMenuOpen(_:)` hears an opening for a menu nobody saw.

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

Three edges follow. A table whose sections all have no rows — a collapsed
section alone, say — draws their headers on their own, in place of its
placeholder, as many as the content area holds whole (there is no row to
carry them, so nothing to scroll; one that does not fit is not drawn). A
hierarchical table draws its sections' rows without their headers. Stripes
(`alternatingRowBackgrounds`) count rows, headers aside.

**The fuller version:** headers as entries of their own in the table's
numbering, with every path taught to skip them — what A31 sketched. It would
scroll a table of more empty sections than fit, and put a header on screen
when only it fits in the viewport (today the row below it comes too, or
neither). Two days: the cursor, selection, select-all, reorder and drop
offsets all translate between the two numberings.

### B-D4T-6. A table section takes no section actions

*`SectionConfiguration.actions` (decisions B18)*

B18 recorded that `SectionConfiguration.actions` was always empty; B78 since
shipped `sectionActions(content:)`, which `actions` reads, so B18 is resolved
for sections of views. A section among a table's rows has none:
`sectionActions(content:)` is a `View` modifier and a row section is not a
view, in SwiftUI as here. Nothing shipped for it; noted so B18 can close.

### B-D4T-7. Column gestures need a customization binding and an identifier; the keyboard's are a mode

*`TableColumnCustomization`, `TableColumnCustomizationBehavior`,
`disabledCustomizationBehavior(_:)`, `RowAction.customizeColumns`
(decisions B45)*

**Measured on macOS 15.8** (a SwiftUI `Table` in an `NSHostingView`, its
outline view driven directly): a table bound to a customization allows column
reordering, one without does not, and both allow resizing; the header's
right-click menu exists only with a binding, and reads "Hide “Alpha”", a
divider, then every column in the order shown with a check while visible — a
column with no `customizationID` checked and disabled; a resize is recorded as
the column's `currentWidth` in the customization's encoding (SwiftUI records
every customizable column's width, from the first layout), and a move as a
`columnOrder` that names a column with no identifier by a transient entry;
emptying the customization does not shrink a resized column back.

**Shipped:** the three gestures — the header menu (right-click or Ctrl-click),
dragging a title to move its column (live, as the pointer crosses the
neighbour far enough that the swap does not swap back), dragging the gap after
a title to resize within the column's declared bounds — on a table bound to a
customization, for columns with an identifier, each taken away by the
column's `disabledCustomizationBehavior`. The width goes into the
customization and its encoding, as the owner expected and SwiftUI does; it is
recorded only once the user resizes, so the value still records "what has
been changed and nothing else", and an emptied customization puts the
declared widths back. The last shown column cannot be hidden from the menu.

From the keyboard the gestures are a mode rather than six chords: **Ctrl-K**
picks a column (drawn in the selected-row fill in the header); while one is
picked, ←/→ pick another, `<`/`>` (or Shift-←/→) move it, `-`/`+` resize it,
Return opens the column menu on it (the mode's own: closing it returns to
the mode, and hiding the picked column picks the first one left), and
Escape (or Ctrl-K) lets it go — the
shape of Ctrl-R's row move, for the same reason: a column has to be chosen
before anything can be done to it, and keys inside a mode need no modifier a
terminal might not send. Only Ctrl-K is a rebindable `RowAction`; free Ctrl
letters are too few for three pairs.

**Since 2026-10-18 (lane LISTS), the fuller version's resizing:** a table
without a binding, and a column without an identifier in one with, resizes
as any other — its gap dragged, or `-`/`+` in the column mode, which Ctrl-K
now opens on every table with a header — the width kept in the table's own
state (`ItemListHandler.transientColumnWidths`, by the column's identifier
or its place in the column closure, `_TableColumnSpec.place`, which a
condition before it does not move) for as long as the table is shown, as
SwiftUI keeps it in the outline view. Reordering and the column menu still need a binding and an
identifier, as measured. The price, paid by every table: a state lookup per
frame (`resizingColumns`), and a mouse region per resizable column gap
registered each frame on a table that had none. A/B owed: tables,
tables-scroll.

## C. Declined, with the reason

### C-D4T-1. B47 is not a gap: SwiftUI rejects the shape too

*`Group.init(content:)` for `TableColumnContent` (decisions B47)*

B47 recorded that `Table(people) { Group { TableColumn("Email", value: \.email) } }`
fails here with "cannot infer key path type from context" where SwiftUI
compiles it, and the owner asked for the Group initializer that captures the
type-checker to be found and disfavoured.

**Measured** (the macOS 26.2 SDK, Swift 6.2.4, `swiftc -typecheck` of SwiftUI
source): SwiftUI does not compile it either — the same error, at the same key
path — and not with a second column beside the `Group` either, nor in a
`@TableColumnBuilder` property. The compile corpus's existing comment
("SwiftUI cannot infer a key path's root here either") was right, and B47's
premise was not.

The probe, to re-check it on a later SDK — `swiftc -typecheck` of this file
fails with "cannot infer key path type from context" at each `\.email`, once
per shape, and compiles with `\Person.email` in all three. The same file
importing TUIkit in place of SwiftUI gives the same answers (measured
2026-10-05, against this lane's build):

```swift
import SwiftUI

struct Person: Identifiable {
    let id: Int
    var email: String
    var name: String
}

struct One: View {
    @State var people: [Person] = []
    var body: some View {
        Table(people) {
            Group {
                TableColumn("Label", value: \.email)
            }
        }
    }
}

// The second shape: a column beside the Group fails the same way.
struct Two: View {
    @State var people: [Person] = []
    var body: some View {
        Table(people) {
            TableColumn("Name", value: \.name)
            Group {
                TableColumn("Label", value: \.email)
            }
        }
    }
}

// The third: the Group in a @TableColumnBuilder property, the same again.
struct Three: View {
    @State var people: [Person] = []
    @TableColumnBuilder<Person, Never>
    var columns: some TableColumnContent<Person, Never> {
        Group {
            TableColumn("Label", value: \.email)
        }
    }
    var body: some View {
        Table(people) { columns }
    }
}
```

The solver's reason is the same on both sides: the `Group`'s row type is
`Content.TableRowValue`, and the outer builder states it only through
`Group<Content>`'s conformance, which cannot bind a type variable through an
associated type; the closure inside is then solved with no row type. No
other initializer is involved — the failing solution picks the column `Group`
in TUIkit, and SwiftUI has no other candidates in play.

**Nothing shipped:** TUIkit already rejects exactly what SwiftUI rejects, and
SwiftUI source that names the root (`\Person.email`) compiles on both. B47
can close. A TUIkit-only overload that infers the root for a lone column
(`init` over `TableColumn<RowValue, Sort, C, L>` content) would compile source
SwiftUI refuses, which the two parity rules do not ask for.
