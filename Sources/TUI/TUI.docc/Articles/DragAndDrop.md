# Drag and Drop

Let people drag values between views, with the mouse or from the keyboard.

## Overview

A view can be a drag source, a drop target, or both, using SwiftUI's own
modifiers. Mark a source with `draggable(_:)`, optionally with
a custom preview that floats at the cursor, and a target with
`dropDestination(for:action:isTargeted:)`:

```swift
Text("🍎 Apple")
    .draggable(Fruit.apple)

Text("🧺 Basket")
    .dropDestination(for: Fruit.self) { fruits, info in
        // info is a DropInfo: the drop cell in local space plus the
        // modifiers held at release
        basket.append(contentsOf: fruits)
        return true
    } isTargeted: { over in
        isHighlighted = over   // highlight while a compatible drag hovers
    }
```

A payload can be any value: unlike SwiftUI, TUI doesn't ask for `Transferable`,
because a drag stays inside the app. The floating preview's grab point is set
with `dragPreviewAnchor(_:)`. Dragging needs the mouse reporting drags, which it
does unless you've turned that off (see <doc:MouseAndGestures>).

## Dragging Selected Rows

Dragging one of several selected rows of a ``List`` or ``Table`` carries them
all. Its preview shows the grabbed row and a line such as "+2 more" for the
rest; `dragPreviewRowLimit(_:)` on the list or table lets that many rows ride
the pointer, stacked in the container's order, before the rest are counted.

A drag source has to take the press to find out whether it becomes a drag, but
it keeps only the ones that do: a press released without moving is a **click**,
and goes wherever it would have gone had the source not been there — to an
interactive view inside it, or failing that to whatever it sits on. So a
``List`` whose rows are `draggable(_:)` still selects a row when you click it,
and still starts a drag when you move.

## From the Keyboard

No drag needs the pointer. A `draggable(_:)` view and a drop destination are
focus stops — a control's own stop where the content has one, so a draggable
`Button` is still one stop. With a draggable focused, Copy takes its payload,
and Paste on a focused destination drops it there.

Or carry it: **Ctrl-R** on a focused draggable picks it up. While it is
carried, Tab and the arrows move the focus only among the stops that can
take it: the destinations that accept what it carries, the spring-loaded
controls a pause would press, and the stop it came from. Unrelated controls
are skipped, and each stop it can reach is marked with a `‹`. The carried
picture is drawn beside the focused stop, which is targeted as if the
pointer were over it, and wears the operation's badge. At a destination
taller than a row, such as a ``List``, Up and Down first move between its
rows, and the landing slot follows. The status bar names what Return and
Escape do.
**Return** drops it there, or presses the spring-loaded control there and
keeps carrying. **Escape**, or Ctrl-R again, puts it back. **Space** flips
the operation between a copy and a move, as Option does for the pointer.
The paging keys scroll what it is over, as they do for a pointer's drag.

## Spring Loading

A drag can open its own way to a destination. Hold the pointer still over a
spring-loaded control for half a second, mid-drag, and the control activates
as a click would — a ``TabView``'s tab is selected, a ``DisclosureGroup``
opens, a ``Button`` runs its action — with the payload still in hand:

```swift
Button {
    showFolders = true
} label: {
    Label("Show Folders", systemImage: "folder")
}
.springLoadingBehavior(.enabled)
```

Tabs spring-load unless told `.disabled`; buttons, links, navigation links,
`.button` toggles, segmented pickers and disclosure groups only under
`.enabled`, as on macOS. Moving to another cell starts the pause again, and a
control activates once each time the pointer arrives on it. The keyboard needs
no pause: while a drag is in flight, <kbd>Tab</kbd> still moves the focus and
<kbd>Return</kbd> or <kbd>Space</kbd> still activates the focused control.

## Abandoning a Drag

Let go with nowhere to land and the drag is abandoned: the floating preview
walks back to where it started rather than vanishing under the pointer — about
a fifth of a second, cell by cell. "Nothing happened" reads far better as a row
going home than as one disappearing in mid-air.

**No key cancels a drag**, deliberately. A drag has to be carriable across the
app — pick a row up on one page, navigate to another, drop it there — and that
requires the navigation keys to keep navigating while something is in hand.
<kbd>Escape</kbd> was the obvious candidate and is exactly the key that
navigation needs, so releasing over nothing is the cancel, as it is on macOS.
The movement keys are the other half of the same rule: mid-drag they scroll
rather than move the cursor, so a destination that is off screen can be reached
without letting go. They scroll **the view under the pointer**, not the one the
drag came from — carrying a payload somewhere else is the whole point, and
somewhere else is where you need to reach. A view the drag could not land in is
not scrolled under it, and with the pointer over nothing that qualifies the keys
mean what they usually mean.

A keyboard move (<kbd>Ctrl</kbd>+<kbd>R</kbd>) is a different thing — a mode,
not a gesture — and it does answer <kbd>Escape</kbd>, which puts the row back.
Its rows leave the list and are drawn as the landing slot, which pulses to say
"these are in your hand". Several rows at once make that pulse ambiguous, so the
row the cursor is on stays at full strength while the others travel faint: an
indicator every row wears is an indicator none of them wears.

The landing slot rides the pointer, not the rows: hold still near a scrollable's
edge and it auto-scrolls, and the slot stays where you are pointing while the
rows stream past underneath. It is a place in the list you are aiming at, and
you have not moved.

*Near* the edge is not the same as *past* it. Auto-scroll engages from a hot
margin just inside the control, where the pointer is still on a row; dragged
beyond the frame the pointer is on nothing.

What a release out there does depends on whether the rows left with it — see
``RowReorderFeedback``. Under `.cursor` they did, so the slot closes and the
release abandons the gesture; dragging out is how a user changes their mind.
Under `.live` and `.dimmed` they did not: those draw the rows inside the
control throughout, so the release commits to what is on screen, which is
whichever end the pointer left by.

A **row reorder** is carriable in the same way, with one limit that follows from
what it is: a reorder can only land in the list it came from, so leaving that
list's page and coming back resumes the gesture, and releasing anywhere else
abandons it. The rows go home and the preview walks back, exactly as a refused
drop does. Which control finishes a reorder is decided at the release, against
whatever is on screen then — not against the list that was there at the press —
so the drop lands in the list you are looking at, moving the rows you can see.

## What a Carried View Looks Like

A view being carried leaves its place: while its own drag is in flight it draws
blank, because it is already on screen at the cursor and drawing it twice says
two things are moving. Row reordering does the same under
``RowReorderFeedback/cursor``, so a row dragged out of one list and into another
looks the same as a row dragged within one. It goes blank rather than vanishing from the layout: the space is still the view's,
and a list closing up mid-drag would move the very rows the drop is aimed
between.

It stays blank until the picture is back, not until the button comes up. A
release over nothing sends the preview home rather than letting it vanish under
the pointer, and for the length of that flight the view it is flying to is still
somewhere else — so it keeps its blank, and one row lands in one place.

A cancelled row REORDER reads the same way, and gets there differently. Its rows
are put back in the data the moment the button comes up — a `List` that changed
length after the gesture was over would move the very rows you are looking at —
so they are back in the layout and simply draw nothing until the picture
arrives. Their space is held open, blank, and then the row appears in it.
`List` and `Table` both do this.

### Room for the Landing Slot

A list whose rows fill it exactly borrows a row's worth of scrolling while a
drag hovers it, because the landing slot needs a line and nothing left the list
to free one. It does not grow — the page must not shift under the pointer —
so instead it overflows by one and says so, with its "▼ N more rows below"
indicator or its scrollbar, and can be scrolled (by wheel, by the mid-drag
navigators, or by holding the pointer at its edge) one further than usual. That
last position is the one after the final row: without the borrowed line a full
list could not draw every row AND the slot, so "drop at the very end" could not
be pointed at. The indicators still count only real rows — the borrowed line is
the slot, which is on screen and is not a row.

They count from where the rows were **drawn**, too, which near the top is not
always where the scroll offset stands. A viewport one line down draws from the
line above instead, because saying "▲ 1 more row above" costs the very line it
would be reporting; normally the offset is then settled down to match, but not
while a drag is being steered — a viewport in motion is not resting anywhere.
So the two disagree, harmlessly, and only for as long as the drag lasts. What
must never differ is what the user is *told*: two frames that draw the same rows
say the same thing about what is off screen, and one <kbd>Page Down</kbd> from
either takes you to the same place. A page moves the picture by a page.

The movement keys are the exception, and have to be: a step moves the position
itself, so it measures from the position, which is the only way it can ever
leave a spot that looks like the one above it.

The one place it does close up is the list the row is being dropped back into.
A `List` whose rows are `.draggable` opens a landing slot while the drag hovers
it, and a slot plus a blank would be two gaps for one row — the list would grow
by a line for the duration of every same-list drag. So the row that the slot is
*for* is dropped from the drawing instead: one row out, one slot in, and the
list keeps its length, exactly as a ``ForEach/onMove(perform:)`` reorder has
always drawn it. Move the pointer to a different list and the blank comes back,
because that list has no slot of its own and nothing there should shift.

Only a row that is **on screen** can pay for the slot that way. Carry it far
enough — dragging to the bottom edge scrolls the list, and the row it came from
goes off the top — and nothing has left the drawing any more, so the list
borrows a line exactly as it would for a drag from elsewhere. Without that, the
end of a scrolled list could not be pointed at: the furthest the pointer could
reach was the position *before* the last row.

## Topics

### Drag and Drop

- ``DropInfo``
- ``DragPreviewAnchor``
- ``SpringLoadingBehavior``
- ``DragSession``
- ``DropSession``
- ``DragConfiguration``
- ``DropConfiguration``
- ``DragDropPreviewsFormation``

## See Also

- <doc:ListAndTable>
- <doc:MouseAndGestures>
- <doc:KeyboardShortcuts>
