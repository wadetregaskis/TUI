# SwiftUI API completion — lane LISTS2 (lists, tabs and tables: settled parity items): new judgement calls

*Lane LISTS2 built, on 2026-10-19, the list, tab and table items whose open
questions prior owner rulings had settled (decisions B73, B76, B78, B79, B80),
and three items lane LISTS left (B-LISTS-2's three sites, decisions-D2S
B-D2S-4 and decisions-D5G B-D5G-9). The calls that came up on the way are
below. The safe option shipped; the alternative and its price are given.
Numbered as the main decisions document is: A = owner decision, B = basic
shipped, C = declined.*

## B. Basic option shipped

### B-LISTS2-1. A selection background raises the prominence of what is in front of it, in its two spellings

*`ShapeStyle.selection` (`SelectionShapeStyle`), `EnvironmentValues.backgroundProminence`,
`View.background(_:)`, `View.background(_:in:fillStyle:)` (decisions B73)*

SwiftUI documents that "standard shape styles like `ShapeStyle.selection`
will automatically update the background prominence of foreground views".
Its own behaviour could not be measured: a probe (`LISTS2/probe/selprom.swift`
in the working notes) could not make its offscreen window key, and in a
window that is not key neither a selected list row nor a `.selection`
background raised.

**Shipped:** `background(_:)` and `background(_:in:fillStyle:)` raise it for
their content when the style is `.selection`, erased in an `AnyShapeStyle` or
not; no other style does. TUIkit's selection style is drawn vivid always, as a
terminal's one window is always the key one, so it raises always.

**Not shipped:** the selection drawn by a view rather than a style —
`.background { Rectangle().fill(.selection) }`, `ZStack { Color… }` — and a
modified selection (`.selection.opacity(0.5)`, `.selection.shadow(…)`). The
first would need the view background to look through its content for the
fill it draws; the second, each style wrapper to forward the answer. About
an hour for the wrappers, and the view form is not recommended without a
measurement saying SwiftUI raises it.

### B-LISTS2-2. Home and End go to the list's top and bottom

*`List` and `Table` keys (a consequence of decisions B76's header and footer rows)*

Home put the cursor on the first row it can land on and revealed that row
alone, so a row above it the cursor cannot reach — a section's header where
it is not pinned, a row the selection cannot name, a tab view sidebar's
header — stayed out of sight, and with it any control in it, a Tab stop only
while drawn. End did the same at the bottom.

**Shipped:** Home scrolls to the top and End to the bottom before revealing
the cursor, as macOS's Home and End go to a list's top and bottom; the cursor
still wins where the rows beyond it are taller than the window. Nothing
changes for a list whose first and last rows the cursor can land on.

**The alternative:** reveal the rows beyond the cursor whenever it reaches
the first or last landable row by any key — an Up onto the first tab would
then show the sidebar's header too. The reveal runs on every cursor move, so
it is a test of the landing set on each; about an hour, if the owner prefers
it.

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

### B-LISTS2-4. A sidebar's sections move among the identified sections, and a drag drops onto a header

*`TabViewCustomization`, `TabContent.customizationID(_:)` (decisions B79)*

**Shipped:** only a section with a customization identifier moves — the
order is stored by identifier — and it moves among the places identified
sections have, as a stated order is applied; the loose tabs between sections
keep theirs. From the keyboard the section in hand is drawn faint and the
others step aside as it moves, and it goes back if the focus leaves its
header, as a list's row in hand does; a drag carries the header's title, and
a release over another header puts the section in that one's place.

**The fuller version:** a drag that shows a landing line between sections, as
a list's row reorder does, and drops above or below the header it is over by
which half of it the pointer is on. The sections are list rows, so the line
is the list's reorder slot drawn for a section's span of rows: about half a
day.

### B-LISTS2-5. A list that does not clip draws the rows past its frame, not clicked; a table still clips

*`View.scrollClipDisabled(_:)` on `List` and `Table` (decisions-D2S B-D2S-4)*

**Shipped:** a `List` under the modifier draws the row before its window and
the one after, outside its frame, as overflow layers at its place in the
stacking order (B-D2S-4). They are drawn, not clicked: the list's click
mapping covers its frame, and a row's own controls there take no press.

**The fuller version:** carry each overflow row's own regions out with it,
and map a click on one to its row as a click on a drawn row is mapped — about
two hours. And a `Table`: its two composers (single- and multi-line rows)
each need the same rows drawn and handed out — about half a day.

### B-LISTS2-6. A list owns `.scrollView`, but does not place its rows before drawing them

*`GeometryReader` and `scrollTransition` in a `List` row (decisions-D5G B-D5G-9)*

**Shipped:** the list draws its frame as the owner of `.scrollView` and
`.scrollView(axis: .vertical)`, answering a row's reader in its content
window and drawing the frame once more where one drew from a wrong answer.
A list with nothing asking pays the walk's checkpoint and a test of the
geometry's waiting count each frame.

**The fuller version:** place each drawn row at its line in the window before
it is drawn, so a scrolled list's readers are told where they are rather
than found there — no second drawing per frame. The line is what the window
walk renders rows to learn, so the prediction would take each row's height
from its measure: about a day, with the `table`, `tables-scroll` and
`session/inbox` A/Bs.

### B-LISTS2-7. A slot two loops of a hierarchical table reach goes to the deeper loop

*`DynamicTableRowContent.dropDestination(for:action:)`, `onInsert(of:perform:)`
in a hierarchical table (decisions B80)*

SwiftUI's outline view aims a drop at the end of a branch's rows or before the
next row out by the pointer's indentation (measured, `Tools/SwiftUIProbes/
Hierarchical table insertions/`); a terminal's drop line has none. **Shipped:**
the deeper loop that takes the payload has that slot, and the next row's loop
the ones it alone reaches. **Not copied:** where a branch's rows have no loop
that takes the drop, SwiftUI hands it to the roots' loop at the offset it had
among the branch's rows; TUIkit gives the slot to the loop whose rows it is
among, or to none.

**The alternative:** aim by the pointer's column, as the outline view does —
left of the deeper level's indentation, the shallower loop. A drag's column
is known; about two hours, with the gap drawn at the matching indentation.

### B-LISTS2-8. A tab view sidebar is as wide as its widest tab, whatever its bottom bar

*`TabViewStyle.sidebarAdaptable` (found on the way to B76)*

The sidebar's column was a fixed-size stack of the header, the list, the
footer, the toolbar and the bottom bar. A list has no ideal width (SwiftUI's
has none), so the column took the widest of the others and drew the list at
it: a tab title wider than all of them was cut to them. **Shipped:** the
list is fixed on its own too, and answers its hugged width. Nothing to add.
