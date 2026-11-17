# The first key from an empty selection

*What the first Down, Up, Home, End, page key or typed letter does in a list,
table, tree or picker with nothing selected, under `.selectionFollowsCursor()`
and without it, beside macOS; where the code would change, and a staged plan.
Ids: A-FIRSTKEY-1 to A-FIRSTKEY-3 (open).*

## In short

On macOS a list's keyboard cursor is its selection, and with nothing selected
there is no cursor: Down selects the first row, Up the last, a typed letter
the first row it names, and Home, End, Page Up and Page Down only scroll, with
a row selected or without. A selection the app clears is forgotten. TUI's
cursor is a row index that starts on row 0 and stays where it was put, so
under `.selectionFollowsCursor()` the first Down selects row 1, the letter of
row 0 skips it, and a selection the app clears (or starts with) leaves the next
arrow going on from the wrong row. Separately, TUI's Home, End and page keys
select under the modifier because APPFB-1 said so, where macOS's never select.

It is not one site, but it is one handler: every `List`, `Table`, tree table,
`OutlineGroup` and sidebar tab view keys through `ItemListHandler`, and the
change there is a flag and five functions. Pickers key through a second
handler, `RadioButtonGroupHandler`, and their macOS behaviour is unmeasured.
About a day in all, most of it tests; the Home/End question is the owner's.

## How it unfolded

1. **2026-11-14, APPFB-1.** The owner chose an opt-in
   `.selectionFollowsCursor()`, "every key that moves the cursor … selects what
   it lands on (the arrows, Home and End, the paging keys, type select …)".
   The APPFB probe measured Down and type select only.
2. **2026-11-16, lane G6** (`scrollTo` and the cursor) found with
   `Tools/SwiftUIProbes/Scroll to a row/selrow.swift` that with nothing selected
   macOS's Down selects row 0, and recorded TUI's row 1 as a known issue
   (`ScrollToLeavesTheCursorTests.nothingSelected`), judging the fix not small.
3. **2026-11-16, lane FIRSTKEY** (this story) extended the probe to every
   moving key and four starting states (`firstkey.swift`, `firstkey.out`),
   read the code paths, and pinned each difference in
   `Tests/TUITablesTests/FirstKeyFromEmptySelectionTests.swift`.

## The record

### What macOS does

`Tools/SwiftUIProbes/Scroll to a row/firstkey.out` (macOS 15.8.3, a SwiftUI
`List` and `Table` over 100 rows, `Int?` and `Set<Int>`, the table view the
first responder, each key the first in a fresh window). The four kinds agree
throughout, and so the table below is all of them:

| First key | Nothing selected | Row 5 selected | Row 5 selected, then cleared by the app | Nothing selected, scrolled to row 50 |
|---|---|---|---|---|
| Down | selects row 0 | selects row 6 | selects row 0 | selects row 0, scrolls back |
| Up | selects row 99 | selects row 4 | selects row 99 | selects row 99 |
| Home | scrolls to the top, selects nothing | scrolls, row 5 stays | scrolls, selects nothing | scrolls, selects nothing |
| End | scrolls to the bottom, selects nothing | scrolls, row 5 stays | scrolls, selects nothing | scrolls, selects nothing |
| Page Down, Page Up | scroll a page, select nothing | scroll, row 5 stays | scroll, select nothing | scroll, select nothing |
| `c` (rows 2, 28, 54, 80) | selects row 2 | selects row 28 | selects row 2 | selects row 2 |
| `a` (rows 0, 26, 52, 78) | selects row 0 | selects row 26 | selects row 0 | selects row 0 |

So the cursor is the selection: with none, a key that selects starts from
outside the list (Down from above it, Up from below, type select from the
top), the keys that only scroll never select, and clearing the selection
clears the cursor with it. A `List` is an `NSOutlineView` there
(`SwiftUIOutlineListView`), so an outline behaves as the list does.

**Not measured:** Shift with an arrow from nothing selected; a row the user
deselects (⌘-click) rather than the app; a radio group or segmented picker
whose selection matches none of its options.

### What TUI does today

The list's cursor is `ItemListHandler.focusedIndex`, an `Int` that starts at
0 and is moved by the keys, a click, the pointer while the focus follows it
(HOVER-FOCUS), a swipe, and a selection the app writes
(`followWrittenSelection()`); `scrollTo` and the wheel leave it. Under the
modifier, `followCursor(from:)` selects the row a key moved it to, and nothing
when the cursor did not move. Rows are 100, the cursor's row drawn whenever
the list has the focus.

| First key, nothing selected | Cursor never moved (row 0), or only scrolled | macOS | |
|---|---|---|---|
| Down | selects row 1 | row 0 | **differs** |
| Up | wraps to row 99, selects it | row 99 | same |
| Home | cursor stays on row 0, selects nothing | nothing | same, by accident |
| End | selects row 99 | nothing | **differs** (APPFB-1) |
| Page Down | selects the row a page down | nothing | **differs** (APPFB-1) |
| Page Up | cursor stays on row 0, selects nothing | nothing | same |
| `c` | selects row 2 | row 2 | same |
| `a` | selects row 26: a first character searches after the cursor | row 0 | **differs** |

| Other starting states | TUI | macOS | |
|---|---|---|---|
| Row 5 selected: Down, Up, `c` | rows 6, 4, 28 | the same | same |
| Row 5 selected: Home, End, Page Down | selects row 0, row 99, a page on | row 5 stays | **differs** (APPFB-1) |
| The app clears row 5: Down, Up | rows 6, 4 (the cursor stayed on row 5) | rows 0, 99 | **differs** |
| The app starts with row 5 selected: Down | row 1: a selection there at the first frame is not one written since, so the cursor is on row 0 | row 6 | **differs**, in both modes |
| The pointer parked the cursor on row k (`.focusFollowsPointer()`): Down | row k + 1 | row 0 (the pointer moves nothing) | differs, as lane-decided on 2026-11-16 under HOVER-FOCUS |

**Without the modifier** (deviation V2) no key selects: the cursor is drawn on
row 0 when the list takes the focus, Down moves it to row 1, and Space selects
the row under it. That is consistent with what is drawn, and macOS has no
counterpart to compare it with. The one difference that reaches V2 is the
starting selection: the cursor starts on row 0, not on the selected row, until
the focus has once left (`onFocusLost()` puts it on the selection) or the app
writes the selection again.

**Pickers** (radio group, segmented and palette pickers, through
`RadioButtonGroupHandler`): the cursor starts on the selected option, so a
picker with one is never "from nothing". With a selection that names no option
(an optional selection at `nil`, say) the cursor starts on option 0, and under
the modifier Down or Right chooses option 1; Up or Left chooses nothing in a
radio group (it is contained at the edge) and the last option in a segmented
picker (which wraps).

Each row of the tables above is a test in
`Tests/TUITablesTests/FirstKeyFromEmptySelectionTests.swift`, macOS's answer
expected under `withKnownIssue` where TUI's differs.

### Where the code would change

One handler covers every list: `List`, `Table`, the tree tables,
`OutlineGroup` and the sidebar tab view key through `ItemListHandler`, and both
drawing twins (`_ListCore.swift`, `Table.swift`) ask it which row carries the
cursor through `isCursorRow(_:)` and `isFocused(at:)`. There are no per-control
copies. The sites in it:

| Site | Today | The change |
|---|---|---|
| `ItemListHandler.swift` | `focusedIndex` starts at 0 | a `cursorIsPlaced` flag beside it: false at first; true when the keys, a click, the pointer or a written selection move the cursor; false again when the app empties the selection |
| `ItemListHandler+Keys.swift`, `handleCursorMovementKey` / `moveFocus(by:wrap:)` | Down and Up step from `focusedIndex` | from nothing (the modifier on, the selection empty, the cursor not placed), Down lands on `firstLandableRow`, Up on `lastLandableRow` |
| `ItemListHandler+Selection.swift`, `followCursor(from:)` | nothing when the cursor did not move | also selects when the key started from nothing, so Down onto row 0 selects it |
| `ItemListHandler+TypeSelect.swift`, `typeSelectMatch` | `current: focusedIndex` | `current: nil` from nothing; `TypeSelectBuffer.match` already starts at row 0 for `nil` |
| `ItemListHandler+Selection.swift`, `isFocused(at:)` | the cursor row drawn whenever focused | no cursor row drawn from nothing, as macOS draws none (the focus ring stays) |
| `ItemListHandler+WrittenSelection.swift`, `followWrittenSelection()` | the first frame only notes the selection | the first frame puts the cursor on it too, in both modes |
| `ItemListHandler+Keys.swift`, `handleExtensionMovement` | Shift+Down from nothing anchors at row 0 and selects rows 0 and 1 | unmeasured on macOS; probe first |
| `RadioButton.swift`, `RadioButtonGroupHandler.handleKeyEvent` | as above | the same flag, if macOS measures the same; segmented and palette pickers share it |

Home, End and the page keys under the modifier (A-FIRSTKEY-1) touch only
`handleCursorMovementKey` and the `followCursor` call after it.

### A-FIRSTKEY-1. Home, End and the page keys under `.selectionFollowsCursor()`: select, as APPFB-1 says, or only scroll, as macOS does?

APPFB-1 named them among the keys that select, as macOS's behaviour; the probe
shows macOS's never select, with a row selected or without. Options:

- **(a) Keep them selecting.** Nothing to build; recorded as a deviation under
  V2. A keyboard user reaches the first and last rows in one key.
- **(b) Scroll only, as macOS.** Under the modifier the cursor is the
  selection, so these keys would move the viewport and leave the cursor and
  selection, as the wheel does, and the next arrow scrolls back. About 2
  hours: `handleCursorMovementKey`, its SCROLL-FIT page handling, and the
  tests (`SelectionFollowsCursorTests.listMovementSelects`,
  `SelectionFollowsCursorPickerTests.radioFollows`'s End, which has no
  viewport and would need its own answer).

A deliberate deviation needs the owner; not decided here.

### A-FIRSTKEY-2. Does a cursor the pointer parked count as placed?

Lane-decided on 2026-11-16 under HOVER-FOCUS: the next arrow goes on from the
row under the pointer (`HoverFocusListTests.selectionFollowsCursorIgnoresPointer`,
four kinds). macOS has no such cursor, and its Down would select row 0.
Recommended: keep it placed (the pointer is where the user is looking, and
HOVER-FOCUS made the cursor follow it so the keys act there); the plan below
assumes so.

### A-FIRSTKEY-3. After the list's own Space clears the selection, is the cursor placed?

`SelectionFollowsCursorTests.tableMovementSelectsAndSpaceToggles` has the next
Down go on from it. macOS has no Space toggle; its ⌘-click deselect is
unmeasured. Recommended: placed (only the app clearing it, which macOS
measures, unplaces it), which keeps that test.

### The plan

| Stage | What | Estimate | Tests that encode today's behaviour |
|---|---|---|---|
| 1 | A selection there at the first frame places the cursor, in both modes | 1 h | `FirstKeyFromEmptySelectionTests.startingSelection` resolves; any test that starts a list with a selection and expects the cursor on row 0 (none found by grep among the follow tests; the V2 suites need the full run) |
| 2 | From nothing under the modifier: Down to the first row, Up to the last, type select from the top, no cursor row drawn; the app clearing the selection unplaces the cursor | 3 to 4 h | `SelectionFollowsCursorTests` (`listMovementSelects`, `tableMovementSelectsAndSpaceToggles`, `multipleSelection`, `treeLeftSelectsParent`), `TableOutlineRowsTwinTests.selectionAndParent` (Down ×4 lands one row earlier), `ScrollToLeavesTheCursorTests.nothingSelected` and four `FirstKeyFromEmptySelectionTests` known issues resolve |
| 3 | A-FIRSTKEY-1, if (b) | 2 h | `SelectionFollowsCursorTests.listMovementSelects`, `SelectionFollowsCursorPickerTests.radioFollows`, two known issues here |
| 4 | Pickers: probe a macOS radio group and segmented picker whose selection names no option, then the same flag in `RadioButtonGroupHandler` if it differs | 2 h | `SelectionFollowsCursorPickerTests` |
| 5 | Shift+arrow from nothing: probe, then `handleExtensionMovement` | 1 h | `SelectionFollowsCursorTests.multipleSelection` |

The grep covered every test target for `selectionFollowsCursor` (seven files);
stage 1 alone reaches lists without the modifier, which the full suite has to
answer for. Risks: the drawing change in stage 2 (a focused, following list
with nothing selected shows no cursor row until the first key) is visible in
any app using the modifier; the `cursorIsPlaced` flag has to be set by every
writer of `focusedIndex` (39 assignments in `TUILists` and `TUITables`, most
in reorder, all of which
already imply a placed cursor, so a setter on `focusedIndex` that sets it is
the safe spelling).

**Recommended:** stages 1 and 2 as one landing stream (they are parity in
cases macOS measures, with no deviation to decide), stage 3 when the owner
answers A-FIRSTKEY-1, stages 4 and 5 after their probes.
