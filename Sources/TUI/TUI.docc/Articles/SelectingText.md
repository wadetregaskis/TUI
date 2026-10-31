# Selecting Text

Let people select and copy what's on the screen.

## Overview

People can select and copy anything your app draws, and you don't have to write any code for it. They drag over it with the mouse, then press Control-C to copy.

TUI does this itself because an app that reports the mouse takes it from the terminal. The terminal's own selection then needs a modifier held: Option-drag in iTerm2, Shift-drag in Ghostty, Warp, kitty and xterm, and it isn't available at all in Apple Terminal.

## What a Drag Selects

- **A drag that no control uses selects what is drawn** — over the page's
  background, over plain text, over a scroll view's content. It runs from the
  press to the pointer in reading order, whole rows between, and keeps to the
  pane it started in: a scroll view's viewport, a split view's column, or else
  the content area. The app header and the status bar are never selected.
- **A drag that starts inside a bordered container keeps to its interior**:
  `.border()`, a `Box`, `Card`, `Panel` or `GroupBox`, a dialog, an alert.
  Its border, the title in it and the page around are left out, and in a
  box inside a box the inner one is the one. A drag that starts on the
  border, or outside the container, crosses it. A drag that goes on past the
  container, more than 3 rows above or below its interior or more than 6
  columns beside it, widens to what the container sits in (the box around
  it, or the pane) and stays widened until the release; overshooting the
  bottom border by a row or two on the way to a card's last line does not.
  ``View/textSelectionScope(_:)`` with `.pane`, on the root view or on one
  container, lets a drag run on to the pane instead; with `.container`,
  inside, it puts the rule back.
- **A double-click selects a word, a triple-click the line in its context,
  a quadruple-click the row**, and a drag after any of them extends by
  words, lines or rows. A double-click on a web address — from its scheme's
  `://` or a `www.` to the next blank, less a sentence's full stop or
  closing bracket — selects the whole address. A line in its context is the run of text between the
  walls either side — a box's border, a divider — or gaps of three blanks or
  more: triple-clicking a name on a bordered card selects the name, not the
  card's padding and walls, as macOS selects a line of the text view clicked
  rather than of the window. **Option-drag** selects a rectangle (iTerm2
  reports ⌘ the same way). Pressing Shift partway through swaps which
  corner the pointer moves — the corner the drag started from follows it,
  by as much as it moves — and letting Shift go swaps them back, so any side
  of the rectangle can be adjusted without starting again. That needs the
  terminal to report Shift on a drag it is already reporting; one whose
  Shift-drag is its own selection may take the drag back instead.
- **A drag that starts on a control is the control's**: a button, a field, a
  slider, a `.draggable` view, a list row — except that a drag starting on
  a list's or table's row text that `.textSelection(.enabled)` made
  selectable selects it, even on a row that is `.draggable`, `.itemProvider`
  or `.onMove`, as macOS's rows do; such a row drags
  from its blank cells. So does one on any `.draggable` view's selectable
  text, whichever of the two modifiers comes first
  (`Text(…).textSelection(.enabled).draggable(…)` and
  `Text(…).draggable(…).textSelection(.enabled)` alike, `textSelection`
  being environment-like), in a scroll view as in a list. A control's label
  is not text: a draggable tab drags from its title, and a `.draggable` view
  or row from a button's label in it, as they do with no scope, and a click
  there is still the button's. Nor is a field's: a drag on a `TextField`'s
  text in a `.draggable` view or row moves the view or row, and a click there
  focuses the field. An `.onMouseEvent` closure is asked, not
  taken for a control: it is offered the press in turn, so one that declines
  a left press leaves the drag to select, and one that takes it has it.

## Copying

**⌘C, which is Ctrl-C under the default `commandKey`,** copies the selection while
it is drawn, ahead of everything else, the focused text field included.
⌘C itself never reaches the app: the terminal takes it for its own,
empty, selection. **A right-click on the highlight** (or a Control-click)
offers **Copy** in a menu of its own, ahead of a row's own menu, as a
Mac's selected text offers its Cut, Copy and Paste there. **Escape** clears the
selection, and so does any click, any key a focused text field takes, and a
presentation (a sheet, an alert or a menu) over the page.

Nothing is copied until the user asks, as on a Mac. A scene can copy every
selection at the release instead, as tmux and iTerm2 do:

```swift
WindowGroup { LogView() }
    .textSelectionCopiesOnRelease()
```

Where a copy goes depends on where the user is: by OSC 52 to a terminal that
writes it, to this machine's clipboard only when the terminal is on this
machine, and otherwise nowhere — and the status bar says which.
A terminal that speaks kitty's clipboard protocol, OSC 5522, is sent every
form a copy has beside its text — a link's Copy Link as a URI list, its
Copy as Markdown as Markdown, a screen selection with its colours, weight
and decoration as HTML — so an app that pastes those takes them as such;
`TUI_OSC5522=1` or `0` overrides what the terminal said. Such a terminal
hands a paste over with its types too: a picture on the clipboard reaches a
view's `onPasteCommand(of: [.png])` as a PNG, beside any text.

There is no keyboard route to the screen selection: what it selects is what a
pointer points at. Text the app means to be copied from the keyboard belongs in
a ``TextField`` or ``TextEditor``, whose Shift-arrow selection and Ctrl-C are
the keyboard's.

## Choosing Where It Applies

`textSelection(_:)` says where the selection applies. With no modifier it is
on wherever a drag does nothing else. `.enabled` keeps a selection to the view
it is on — on a single `Text`, that `Text` — and widens it to the rows of a
``List`` or a ``Table`` inside it, as macOS does: a press on a row's text belongs
to the text, so a drag selects it (kept to the row), a double-click selects a
word, and a click selects nothing, while a press on the row's blank cells
selects, drags or activates the row as before. On a row's own `Text` it does
the same for that text, kept to it; on a `Table` cell's `Text`, for that text,
kept to its cell, and for the row's other text, kept to the row.
`.disabled` turns the selection off; the innermost modifier wins.

```swift
List(invite.recipients) { recipient in
    Text(recipient.email)
}
.textSelection(.enabled)
```

## How a Selection Looks

Selected text is drawn in the selection colours of the text fields, on the
text the selection crosses: each `Text` notes where it is drawn, and on every
row the highlight covers the texts the selection crosses there — a wrapped
paragraph's rows to its trailing edge, as a block — and not a padded card's
padding, the blanks past a short line or the gap between two texts side by
side, though a copy still reads those blanks. Drawing that is no `Text` — a
field's text, a table's text columns, a custom view — is highlighted by its
characters and the blanks between them, never a border's walls; and a
selection that crosses no `Text` at all is highlighted cell for cell. A
picture — an ``Image`` drawn in characters, blocks or Braille — keeps its
glyphs and colours under a selection and takes a tint of the selection colour
instead: its cells are pixels, and drawing them as text left a flat field of
selection colour where the picture was.

A selection reads characters, not views: a wide character once, each row's
trailing blanks dropped, rows joined with line breaks. Its text is fixed when
the drag ends, and the highlight goes as soon as the cells under it change —
a log that scrolls on, a list that moves, a spinner that turns — for good: an
equal line drawn there later is not the selection come back. A selection that
is not drawn takes no keys: ⌘C and Escape are the app's again. Only where the
page itself moved under it — a status-bar tooltip or a copy's line taking a
row from a centred page — do the highlight and its keys come back, when the
page does. It reads the page, not the layers over it: a menu or a popover
draws over the highlight.

## Selecting in Text Fields

Inside a text input a click places the caret and a drag selects, as in any
text control. A double-click selects the word clicked — or the run of blanks
or marks, or past the end the last word — and a triple-click the paragraph: a
field's text, an editor's line with its line break. A drag after either
extends by words or paragraphs, keeping what was clicked. A `SecureField`
selects all of its text on a double-click, as macOS's does, since it shows no
word breaks. While text is selected no caret is drawn, as on a Mac: typing
replaces the selection, so the highlight is where it goes.

In a `TextEditor`, **Option-drag** (⌘-drag in iTerm2) selects a block: the
same columns of every row it spans — the rows as drawn, where the editor
wraps. Copy takes them row by row, joined by line breaks; Cut, Backspace or
Delete take them out of every row; typing or pasting replaces them once, at
the block's top-left corner. Pressing Shift partway through the drag swaps
which corner the pointer moves, as on the screen selection. The app's
`selection:` binding is not told of a block; it sees the caret. A field's
one row makes a block and an ordinary selection the same, so in a
`TextField` an Option-drag selects as a drag does.

A right-click (or Ctrl-click) on a `TextField`, `SecureField` or `TextEditor`
opens its editing menu — Cut, Copy, Paste, Select All, and Yank while a ⌃K or ⌃U has
left text for it — and Shift+F10 opens it on the focused one. Cut and Copy
act on the selection, and are offered disabled without one, and always in a
`SecureField`, which never copies its contents. A disabled control offers no
menu.

## Topics

### Selection Types

- ``TextSelectability``
- ``EnabledTextSelectability``
- ``DisabledTextSelectability``

## See Also

- <doc:MouseAndGestures>
- <doc:KeyboardShortcuts>
