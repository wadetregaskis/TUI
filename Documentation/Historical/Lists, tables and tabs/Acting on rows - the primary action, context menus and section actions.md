# Acting on rows: the primary action, context menus and section actions

*What Return, Ctrl-click, Shift-F10 and the Menu key do on a list or table,
how a section header is drawn and acted on, and when a section's actions
show. Ids: B44 to B47 (via D4T), A30, A31, B-D4T-1 to 6, C-D4T-1, B78,
B78-VISIBILITY, B-LISTS2-3.*

## In short

Return runs the primary action on the cursor row's set (the whole selection if
the cursor is in it, else the cursor row alone), as SwiftUI's context menu
does. A list or table with a menu opens it on Ctrl-click, Shift-F10 and the
Menu key. A section header is drawn as lines of the row below it. A section's
actions show while the focused list's cursor, the focus or the pointer is in
the section, padded to the row's width.

## How it unfolded

1. **2026-10-05, lane D4T** built the owner's B46, A30, A31, B47, B45 and B44,
   measuring SwiftUI's `Table` and `List` on macOS 15.8 for each call; B47
   turned out not to be a gap at all (SwiftUI rejects the shape, C-D4T-1).
2. **B78** placed section actions after the header's title; lane LISTS2
   padded them to the row's width (B-LISTS2-3).
3. **2026-10-23 to 24, B78-VISIBILITY.** The owner chose (b): actions show only
   while the section is in use, which keeps a keyboard route and cuts Tab
   stops; built by lane MISC.

## The record

### B-D4T-1. Return's primary action acts on the cursor row's set, not on the selection as such

*`View.contextMenu(forSelectionType:menu:primaryAction:)` (decisions A30)*

**Measured on macOS 15.8** (a SwiftUI `Table` and `List` in an
`NSHostingView`, double-clicks and Return sent to the outline view):
a double-click selects the row it lands on and runs `primaryAction` with the
selection, which is then that row; Return runs it with the selection; Return
with nothing selected, and a double-click on empty space, run nothing. On a
table with no selection binding a double-click runs it with the clicked row,
and Return runs nothing.

On macOS the keyboard cursor IS the selection. In TUI it is not: the
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

TUI's rows toggle on Ctrl-click and Option-click — the stand-ins for ⌘,
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
encodings send nothing TUI could tell from another key, so elsewhere
Shift+F10 is the route. Both go through one test (`KeyEvent.opensContextMenu`),
honoured by every menu Shift+F10 opens and closes: `.contextMenu`, a list's
or table's row menu, a tab's context menu in the strip and the sidebar.

The first cut shipped Shift+F10 alone, on the reasoning that a new `Key`
case breaks exhaustive switches over `Key`, in TUI and in apps. The
lane's review set that beside the new `RowAction.customizeColumns`
(B-D4T-7), which breaks exhaustive switches over `RowAction` just the same —
and `RowAction`'s own documentation already says that cases will be added
and that this is "a semantic-version event, not a reason to avoid switching
over this exhaustively". The same holds for `Key`, which gained F13…F20
before; so the two calls now agree, and the Menu key shipped. In TUI the
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
importing TUI in place of SwiftUI gives the same answers (measured
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
in TUI, and SwiftUI has no other candidates in play.

**Nothing shipped:** TUI already rejects exactly what SwiftUI rejects, and
SwiftUI source that names the root (`\Person.email`) compiles on both. B47
can close. A TUI-only overload that infers the root for a lone column
(`init` over `TableColumn<RowValue, Sort, C, L>` content) would compile source
SwiftUI refuses, which the two parity rules do not ask for.

### B78. Section actions: shown while the section is in use, after the header's title

*`View.sectionActions(content:)`, `TabContent.sectionActions(content:)`*

macOS shows a list section's actions at the trailing end of its header while
the pointer is over the section.

**Shipped:** in a `List`, the actions are drawn one cell after the header's
title, and are ordinary controls there — Tab moves onto each, a click presses
one. A section with no header shows them alone on the header's line.

**Owner ruling (2026-10-23, B78-VISIBILITY): (b), shown while the section is
in use.** Built 2026-10-24 (lane MISC). A section's actions are drawn, and
register as focus stops, only while the focused list's cursor is on one of
the section's rows, the focus is on one of the actions, or the pointer is over
the section (header to footer). A keyboard user reaches them by moving into
the section and pressing Tab — the list's own place in the ring comes ahead of
them, and an action holding the focus keeps its section's shown; the mouse
finds them where macOS shows them, under the pointer. Not in use, the header
keeps their cells blank, measured rather than drawn, so a headerless section's
line, the rows below and a hugging list's width do not move as they come and
go. A list registers a hover observer only when a section has actions, and a
pointer move asks for a frame only when it crosses into another section
(`ItemListHandler.hoverSections(atContentY:)`). Tests:
`SectionActionsTests`. A custom container reads them as `SectionConfiguration.actions`.
Outside a list (a `Section` in a stack) the view draws as it would without
them, as SwiftUI's does. On a `TabSection`, a `.sidebarAdaptable` tab view's
sidebar draws them the same way; a tab strip, which lists a section's tabs
among the others, shows none, and on a lone `Tab` they do nothing, as
SwiftUI documents.

Where it differs:

- **Shown while the focus is in the section as well as under the pointer.**
  An action shown only under the pointer is one the keyboard cannot reach,
  so the cursor and the focus show them too (B78-VISIBILITY, above); they
  were always shown until 2026-10-24.
- **After the title, not flush right.** The list builds a header row before
  it knows the width a hugging list (a sidebar) settles on, so a flush-right
  action there would lose its trailing cells. Flushing right in a list that
  fills its width, and after the title in one that hugs, is half a day: the
  header row would carry the actions apart from its buffer and the list
  would place them as it places a badge. **Shipped (2026-10-19, lane
  LISTS2), more cheaply:** a list that fills draws its rows at the width it
  composes them at, so the header is drawn with its actions flush against
  that width, where a row's badge ends, and the list tells its rows whether
  it hugs them (`listRowsHug`), where the actions stay after the title.

### B-LISTS2-3. A section's actions are padded to the row's width, not placed as a badge is

*`View.sectionActions(content:)` (decisions B78)*

The priced design had the header row carry its actions apart from its buffer
for the list to place as it places a badge. A list that fills its width draws
its rows at the width it composes them at, which the header's context
already carries, so the header pads its line to that width itself and the
list changes in nothing but the flag that says it hugs (`listRowsHug`).

**Where it differs from a badge's placement:** a frame on which the list
draws a scrollbar it did not predict, or a row wider than the list's offer
widens the rows, puts the actions at the proposed width's edge — a cell or
two short of the trailing edge — until the next frame, where the rows are
drawn at the width the list now composes. The badge-like placement is half a
day, as priced.
