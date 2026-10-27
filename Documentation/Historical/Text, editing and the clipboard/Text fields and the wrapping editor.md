# Text fields and the wrapping editor

*How TUI's text controls came to behave as macOS's: a vertical text field, a
newline from the keyboard, line limits, one-range selection, the wrapping
editor's keys and caret, the find bar, Ctrl-U, a drag selection kept to a
bordered container, and rich-text editing. Ids: B62 to B65, B62-FULLER,
B63-CTRLJ, B63-KITTY, B-D4X-10 to 12, B-D4X-16, D4X-FULLER, B81, A-TEXT2-1,
B-TEXT2-1, B-TEXT2-2, TEXT2-INTERIOR, A42, A42-Q8.*

## In short

A vertical `TextField` is a field that wraps, not an editor. A newline is
Option-Return where the terminal sends it, Ctrl-O everywhere, LF read as
Ctrl-J, and Ctrl-Return (under the kitty protocol) an app's handler, then a
context menu, then U+2028 in a vertical field or `TextEditor`. The wrapping
editor's vertical keys follow `NSTextView`. Ctrl-U is readline's
`unix-line-discard` in every text control. A drag selection begun inside a
bordered container keeps to its interior, and widens to the pane when it goes
well past it. The find bar opens on Ctrl-F. Rich-text editing (A42) is
decided and not started.

## How it unfolded

1. **2026-10-04, A42:** build rich-text editing (not started; A42-Q8 recorded
   on 2026-10-24: bold, italic and underline through the context menu, chords
   only through `TextFormattingCommands`).
2. **Lanes for B62 to B65 and D4X** shipped the fields and the editor; B81's
   find bar was built on 2026-10-19.
3. **2026-10-23 to 26, the owner on newlines:** LF is Ctrl-J (B63-CTRLJ,
   built 2026-10-26); Ctrl-Return's chain (B63-KITTY, built 2026-10-26).
4. **2026-10-24, lane TEXT2** built the owner's items of 2026-10-23: Ctrl-U,
   the selection kept to a container (A-TEXT2-1's widening built for the owner
   to try, lane SELWIDEN).
5. **2026-10-26, TEXT2-INTERIOR:** the containment's cost (`modifiers` +6.4%,
   `dashboard` +3.7%) is accepted, the default kept, and an attempt to cut it
   asked for. **Not yet made.**

## Where it stands

Shipped as the record says. **Owed:** TEXT2-INTERIOR's optimisation; the
per-caret lean at a wrap (B-D4X-16, settled with D4X-FULLER on 2026-10-18);
B65's several ranges, after A42's first stage; A42 itself.

## The record

### B62. A vertical `TextField` is a text field that wraps, not an editor with a field's chrome

*`TextField.init(_:text:axis:)`, `TextField.init(_:text:prompt:axis:)`,
`TextField.init(text:prompt:axis:label:)`*

**What shipped.** On `.vertical` the field soft-wraps its text over rows and
grows a row at a time as it is typed. Measured on macOS 15.8: with no line limit
it grows without end; `lineLimit(2)` stops it at two rows;
`lineLimit(3, reservesSpace: true)` keeps three and `2...4` two; an empty field
grows to show its whole prompt; a field on one line ignores the limit. At its
cap the field scrolls to keep the caret's row in view; unfocused it shows its
first rows. The wrap is the macOS text system's: after a run of spaces, which
hangs at the end of the row it breaks (`"aaa bbb ccc "` then `"ddd"`), between
the characters of a word too long for a row, and at every newline. The last
cell of a row is kept for the caret, so text wraps one cell short of the
field's edge.

**Why on the field's machinery.** A vertical `TextField` in SwiftUI is the same
AppKit field editor as one on a single line (measured: the first responder is
`_SystemTextFieldFieldEditor` on either axis). Return and Shift-Return submit
and insert nothing; the Emacs chords are the field's. So it is built on
`TextFieldHandler`, whose caret is a character offset — the natural coordinate
of a wrapped layout — and keeps every key a text field has: Ctrl-V pastes,
Ctrl-U erases, Shift-arrows select, a submit-less field lets Return through to
a dialog's default button, suggestions and content types work. The editor's
handler would have brought the editor's map instead: Return inserting a newline,
Ctrl-V paging, no keyboard selection. What a field on one line had no use for
is added, each measured on macOS 15.8:

| Key | In a vertical field |
|-----|---------------------|
| Up / Down, Ctrl-P / Ctrl-N | a row, keeping the column through short rows; off the first row Up goes to the start, off the last Down to the end |
| Shift-Up / Shift-Down | extend the selection a row |
| Ctrl-A / Ctrl-E | the start / end of the caret's line (Cocoa's paragraph commands); they keep the key from an app's shortcut, since Home and End go to the ends of the text |
| Ctrl-K | to the end of the line; at its end, the newline |

**Where TUI chose, unmeasured.** A combo box's `▾` sits on the first row,
and Down opens the suggestions only from the last row (above it Down moves a
row). Page Up and Page Down only scroll a SwiftUI vertical field, leaving the
caret where it was (measured); TUI's field scrolls only to follow its caret,
so it has nothing for them to page, and leaves them to the view around it.

**The fuller version:**

- **The caret's lean at a wrap, per caret.** Where a row wrapped, one offset is
  both the end of a row and the start of the next. TUI draws the caret by
  `\.textSelectionAffinity`, and `.automatic` at the start of the later row.
  macOS keeps a lean per caret (measured): an arrow key leaves it downstream,
  as TUI draws it, but typing, a click and Ctrl-E leave it upstream, at the
  end of the earlier row. The two draw the same offset in different places, and
  the next character typed goes to the same place either way. About half a day
  to track the lean through each kind of motion, after measuring the motions
  not yet measured (deletion, Up and Down, Home and End).
- **A scroll indicator** while the text is taller than the field, as the
  editor draws one. A field on one line shows no indicator for its sideways
  scroll either. Half a day, mostly finding a column for it: the margin cell is
  the caret's.
- ~~**The wheel.**~~ Built 2026-10-19 (lane TEXTEDIT, B62-FULLER): the wheel
  scrolls a capped field's rows, and a `TextEditor`'s text, three rows a tick,
  and leaves the caret where it is, as a Mac text view does. A key or a click
  brings the view back to the caret, and a tick at either end goes on to a
  scroll view around it.
- ~~An Example page section~~ with a vertical field: shipped 2026-10-18 (lane
  PARITYMISC), on the Text Input page.

### B63. A newline from the keyboard: Option-Return where the terminal sends it, Ctrl-O everywhere

*Part of `TextField.init(_:text:axis:)` and the other `axis:` forms*

Measured on macOS 15.8, in a vertical field:

| Key | SwiftUI |
|-----|---------|
| Return, Shift-Return, keypad Enter | submit (`onSubmit`), insert nothing, select all |
| Option-Return | inserts a newline, caret after it (`insertNewlineIgnoringFieldEditor:`) |
| Ctrl-Return | inserts U+2028 LINE SEPARATOR (`insertLineBreak:`) |
| Ctrl-O | inserts a newline, caret before it (Cocoa's open line) |
| Ctrl-J, Ctrl-M | nothing |

What a terminal delivers decides what TUI can honour:

- **Option-Return** arrives as ESC CR where the terminal sends Option as Meta
  (Terminal.app with "Use Option as Meta Key", iTerm2 with Option as Esc+, and
  the terminals whose own setting does the same). TUI inserts a newline
  for it. Without Meta it is a plain CR, indistinguishable from Return, and
  submits.
- **Ctrl-O** is byte 0x0F from every terminal. TUI opens a line, as macOS
  does. This is the route that is always there: Ctrl-O, then Ctrl-F (or Right)
  past the newline.
- **A paste** keeps its line breaks, each as one newline whatever the
  clipboard used.
- **Ctrl-Return and Shift-Return** arrive as a plain CR from every terminal
  that does not speak an extended keyboard protocol, so they submit. Ctrl-Return
  would be U+2028 in SwiftUI.

**Shipped since (owner ruling B63-CTRLJ, 2026-10-26): Ctrl-J is a newline in
a vertical field on every terminal.** The parser reads LF as Ctrl-J and CR as
Return; a field on one line lets the chord through, and a Ctrl-J that nothing
takes goes round the chain again as Return, so it submits there as it always
did. Automation that means Return sends CR, as the repository's own PTY
harnesses do. Test: `VerticalTextFieldTests.controlJ`.

**The fuller version, as it was written:**

1. **Ctrl-J as newline-and-advance on every terminal.** LF (0x0A) is Ctrl-J,
   and only Ctrl-J sends it in raw mode, where the Return key sends CR. Today
   the input parser reads LF and CR alike as `.enter`. Reading LF as its own
   key would make Ctrl-J deliverable everywhere — it is the newline key of many
   terminal chat and prompt tools. About half a day with the tests. The risk
   is any path that delivers LF for Return (none known with `ICRNL` off, but a
   multiplexer or a serial line would need checking), where every Return would
   insert a newline instead of submitting. It also bears on the kitty keyboard
   protocol (A4, shipped 2026-10-05), which frees Ctrl-J among other chords.
2. **Shift-Return and Ctrl-Return** wherever the kitty keyboard protocol is
   negotiated, where they arrive as themselves. Possible now that the
   protocol has shipped (A4, 2026-10-05).

**Ctrl-Return, shipped since (owner ruling B63-KITTY, 2026-10-26).** Where the
terminal sends it as itself (the kitty keyboard protocol; every legacy encoding
sends a plain CR, which stays Return), it goes as macOS layers it: to the app's
handlers and shortcuts first (an app's ⌘↩ is Ctrl-Return under
`.commandKey(.control)`); then to a context menu, as macOS's Control-Return
"Show contextual menu" — an app's `.contextMenu` answers it, and with no text
input focused it goes round as Shift-F10 so a list's or a tab's row menu opens,
but a text control's own editing menu does not answer it; then to a vertical
`TextField` as a line separator (U+2028, the text system's `insertLineBreak:`);
and otherwise as Return. A `TextEditor` puts in a newline for it, not U+2028:
the editor keeps its text as lines joined by newlines, where a separator would
neither break the row nor survive the next write. On macOS the terminal itself
may keep the chord for its own menu; nothing relies on it alone. Tests:
`ControlReturnTests`.

### B64. `lineLimit`'s range forms ship, reversing their omission

*`View.lineLimit(_:)` with `ClosedRange<Int>`, `PartialRangeFrom<Int>`,
`PartialRangeThrough<Int>`*

The compatibility doc omitted the three range forms because no terminal text
control grew to be sized by them. The vertical field does, and SwiftUI documents
them for a `Text` as well: the lower bound is a floor and the upper a cap, as
`reservesSpace:` and the limit are. `Text("one").lineLimit(2...4)` keeps two
rows and long prose stops at four; `lineLimit(...2)` is `lineLimit(2)`. Listed
because it reverses a recorded omission. (The parity tool counts a function's
overloads under one name, so these were never in its gap list.)

They are stored without widening every `Text`: a range that reserves nothing,
or exactly its cap, is the existing `.lines` case, and the rest a new
`LineLimit.range` whose bounds are 32-bit, so `LineLimit` stays nine bytes.

### B65. A text field's selection is one range

*`TextField.init(_:text:selection:prompt:axis:)`,
`TextField.init(text:selection:prompt:axis:label:)`*

Wired as `TextEditor(text:selection:)` is: the field writes its caret and
selection to the binding after every key and pointer event, and a selection the
app writes moves them at the next frame. A field selects one range, so an app's
multiple selection selects its first range, as the editor's does.

**The fuller version:** draw and edit several ranges. A terminal has no gesture
that makes a second range (macOS's is Command-drag), so only an app could ask
for one. Painting every range is cheap; what typing over several ranges does
needs measuring on an `NSTextView` first.

### B-D4X-10. The wrapping editor's vertical keys follow `NSTextView`; its page keys do not

*A43*

**Shipped:** measured on macOS 15.8 with a SwiftUI `TextEditor` (an
`NSTextView`): Up, Down, Ctrl-P and Ctrl-N move by rows keeping the column
through short rows; Up from the first row goes to the start and Down from the
last to the end; Ctrl-A and Ctrl-E keep the paragraph; a tab's stop is counted
from its row's start. TUI's wrapping editor does all of these. Page Up and
Page Down only scroll an `NSTextView`, and Home and End scroll to the ends;
TUI's editor moves the caret for them, by a screen of rows and to the
document's ends, as it already did. With `textEditorWrapsLines(false)` the
editor is exactly as before, Up and Down stopping at the first and last line.

**The fuller version:** page and Home/End keys that only scroll, leaving the
caret, as macOS's do. Half a day; it would make the caret leave the screen,
which a terminal editor rarely does.

### B-D4X-11. A caret in a run of spaces hanging past the margin

**Shipped:** the caret further into a hanging run is drawn on the last cell,
as `SoftWrapLayout` already holds it (macOS clamps it the same way). Where a
tab straddles the margin, nothing starts on that cell and the caret is not
drawn until it moves. Rare: a tab at the very end of a full row.

**The fuller version:** draw the caret on the margin cell whatever covers it.
An hour, in the row renderer both editors share.

### B-D4X-12. No wrap toggle on the Example's Text Input page

**Shipped:** the modifier, the docs and the tests; the Example's editor wraps
by default.

**The fuller version:** a toggle beside the editor, with its label in the
Example's seven languages. Shipped 2026-10-18 (lane PARITYMISC): the Text
Input page's editor section has a "Wrap long lines" toggle that both its
editors read.

### B-D4X-16. Upstream, a caret moved onto a wrapped row lands after its first character

**Shipped:** under `.textSelectionAffinity(.upstream)` the start of a wrapped
row is drawn at the end of the row before it, so Up, Down and a click put a
caret on a wrapped row at its first upstream position, after its first
character, in a vertical `TextField` and a wrapping `TextEditor` alike. A
selection's ends are not carets: a drag that starts or ends on a wrapped
row's first cell, and a Shift-click there, take that character in ("aaaa
bbbb cccc" at width 6, dragged across "bbbb" from its first cell, selects
"bbbb"; review 2 found it selecting "bbb" once the caret rule fed the drag).
A head put there is on the row the pointer put it on, though the same offset
is the end of the row before to an upstream caret: the editor and a
`lineLimit` field follow it without scrolling, and Down goes from it to the
next row — in a vertical field Shift+Down extends the selection there; the
editor, which has no keyboard selection, drops it and moves the caret — until
a key moves it off (the follow-ups' review found it read on the row before:
a drag back onto the top row's first cell scrolled the view up a row each
time, and Down kept to the head's own row; its second, that this entry said
the editor's Shift+Down extended the selection, which it drops).
A head that ends no selection is a caret: a drag or a Shift-click that comes
back onto its own anchor there leaves the caret where a click puts it, after
the row's first character, and a key that ends the selection without moving
the head (Backspace deleting a backward selection) leaves a caret read as any
other at that offset (the follow-ups' second review found both still drawn at
the row's first cell, where no upstream caret is).
The affinity is the view's, one for every caret.

**The fuller version:** an affinity per caret, as the macOS text system keeps
— a caret an arrow key moved to a row's start leans downstream and is drawn
there, one typed or clicked to the end of a row leans upstream — with the
view's affinity as the default. Half a day in `SoftWrapLayout` and the two
handlers. Downstream, the mirror case is unchanged from before the rule: a
drag ending on a wrapped row's trailing margin stops before its hanging
space, which a drag onto the next row takes.

### B81. The find bar: Ctrl-F opens it, Ctrl-G finds the next match, and its options are a row

*`View.findNavigator(isPresented:)`, `View.findDisabled(_:)`, `View.replaceDisabled(_:)`,
`FindContext`, `\.findContext`*

**Shipped** for `TextEditor` (refusal review P17): a bar above the text with a
search field, the match count, previous and next, Done, and a replacement row
unless replace is disabled. Matching ignores case. Return finds the next match,
Escape closes the bar, and the bar writes `false` back to the binding when it
closes.

**What differs, and what a fuller version would cost:**

- **The key.** macOS opens find with Cmd-F, which a terminal keeps for itself.
  Ctrl-F is the editor's "forward a character" (macOS's standard key binding),
  so the bar opens with Ctrl-G. A different key is a one-line change.
- **Only the current match is marked**, by selecting it in the editor, which
  scrolls to it. macOS also highlights every other match. Drawing them all is
  about half a day: the editor's rows would take a list of ranges to tint, as
  they take the selection.
- **No options menu.** macOS's find bar offers "Contains", "Starts with",
  "Full word" and case matching. The bar searches for the literal text,
  ignoring case; the options would be a menu and a day.
- **No Find Next from the editor.** With the bar closed, Cmd-G and Shift-Cmd-G
  move between matches on macOS. A terminal binding for them is the same
  question as the key above.

**Built 2026-10-19** (lane TEXTEDIT; all three, settled by the owner's rulings
on keys — Emacs chords are a bonus, Ctrl-F find is common, and N6's Ctrl-V
precedent): Ctrl-F, ⌘F's Control chord, presents the bar, the editor giving
up Emacs "forward a character" where it has one (Right arrow does the same; a
field keeps it); Ctrl-G finds the next match with the bar up or closed, and
Shift-Ctrl-G the previous where the kitty protocol tells Shift apart; every
match is tinted, the selection's colour a third of the way over the well, the
current one selected over it; and macOS's options, which it keeps in a menu
under the magnifier, are a row under the search field: an Ignore Case toggle
and a button that steps through Contains, Starts With and Full Word
(`FindNavigatorTests`). A menu and a picker would have made the text editor's
module depend on TUIMenus and TUIPickers, which the module split keeps
it free of. An app's own shortcut on ⌘F or ⌘G takes the key from the bar, as
the editor's other chords give way to one; `TextEditingCommands`' Edit ▸
Find… and Find Next press the two keys.

### A-TEXT2-1. A gesture that widens a container's selection to the pane

*#10's opt-out, from the mouse*

You asked for suggestions for getting past a container's interior from the
mouse; Option (a rectangle), Shift (a rectangle's moving corner, and many
terminals' own bypass) and Control (the secondary click) are taken.

What already works, at no cost: **start the drag on the container's border,
or outside it.** The border is not the interior, so a press there is the
pane's, and the drag crosses the container as it always did. The same goes for
a press in the page's blank cells beside the box.

Options for a gesture from inside:

1. **None beyond the border (shipped).** *Price:* nothing. A drag from the
   middle of a card's text cannot reach the page.
2. **A drag that leaves the container by more than N cells widens to the
   pane.** *Price:* small to build (`HeldPress` keeps the outer pane and
   re-clips the selection once), but ambiguous: a drag down to "the end of the
   card" overshoots the bottom border by a row or three as a matter of course,
   since a stream dragged past the clip's bottom already runs to the end of
   the last row. Whatever N is, a fast drag crosses it by accident, and the
   selection then jumps out to the page mid-gesture; and an N large enough to
   be safe is often more rows than there are below a card near the screen's
   foot.
3. **A double-press-and-drag on the border itself selects the whole box and
   extends from there.** *Price:* small; a new rule to learn.

**Recommendation:** 1. The border is a visible, unambiguous handle, and
`.textSelectionScope(.pane)` covers an app that wants the old reach
everywhere. I did not build 2 because of the overshoot.

**Ruling (owner, 2026-10-24): 2, as an experiment.** "I think (2) has
potential — let's try that first, and see how it feels." Built on lane
SELWIDEN for the owner to try; the border handle and
`.textSelectionScope(.pane)` work as before.

- **What widens.** A drag kept to a bordered container's interior that goes
  more than **3 rows** above or below it, or more than **6 columns** beside
  it, widens to the scope the container sits in, and the selection re-clips
  to it at once. The distance is counted in cells outside the interior, the
  border's own row or column being 1, separately per axis; either one past
  its limit widens. One constant pair, `HeldPress.wideningRows` and
  `wideningColumns`, in `TUIFoundation/App/HeldPress+Widening.swift`,
  which holds the whole rule.
- **Why 3 and 6.** The border and two rows beyond it stay inside, because a
  drag to "the end of a card" overshoots the bottom border by a row or two as
  a matter of course, and a stream dragged past the clip already runs to the
  end of the last row, so that overshoot loses nothing. The third row beyond
  the border is a drag that meant to leave, and still few enough rows to be
  there below a card near the screen's foot. Sideways it is twice that,
  because a cell is about half as wide as it is tall, so 6 columns are about
  the same distance on the screen as 3 rows, and a drag to a line's end
  overshoots sideways as freely as one to a card's end does downward.
- **One way.** Once widened, the selection stays widened until the release:
  a pointer that comes back inside the card does not narrow it again, so it
  cannot flicker between the two mid-gesture. Leaving is all that counts. The
  drag need not also be moving away, since the overshoot that should not
  widen is itself outward, and only its distance tells the two apart.
- **One scope at a time.** The next scope out is the next bordered
  container's interior around this one, an enabled `textSelection` around it
  (the widening stops there, since that scope is the app's own), or else the
  pane (a scroll view, a split view's column, the content area), which is
  always the limit. A card inside a card widens to the outer card's interior
  first. Leaving that by the same distance widens to the pane. The steps are
  measured from the rectangle in force, so one long jump can take two steps
  in one event, as it would in two shorter ones. A scope no wider than the
  last (an interior that fills its scroll view) is skipped.
- **Unchanged.** A drag begun on the border or outside the container, a
  drag kept to a list's or table's row, a cell's own `.textSelection(.enabled)`,
  and a Control-press, which selects nothing. TUI has no keyboard
  extension of the screen selection (no Shift-arrows), so there is nothing
  for the rule to apply to there.
- **Cost.** The check runs on each drag event of a gesture begun inside an
  interior. The rungs are built once at the press, from the hit regions it
  already walks. Nothing is added per frame or per region.

What to feel for: whether 3 rows is enough slack for a quick drag to a
card's end, and whether the jump to the page, when it comes, reads as
deliberate or as a surprise.

### B-TEXT2-1. Ctrl-U is readline's `unix-line-discard` in every text control

*#15. `TextField`, `SecureField`, a vertical `TextField`, `.searchable`'s field,
`TextEditor`*

The report was "Ctrl-U doesn't work". Measured in the live Example under a
PTY (legacy bytes, 0x15): every field erased its whole text wherever the
caret was, and kept nothing for Ctrl-Y; `TextEditor` passed the key on and
did nothing (it declined it on purpose: "one chord erasing a whole document is
a different thing"). Nothing earlier in the input chain took the key.

Now Ctrl-U kills from the caret to the start of the caret's line: in a field
on one line the whole text before the caret, in a vertical field and in the
editor the caret's logical line (its wrapped rows and all). One undoable edit,
kept in the kill ring for Ctrl-Y as Ctrl-K's kill is; a `SecureField` deletes
and keeps nothing, as for Ctrl-K. A selection goes first, as for Ctrl-K. At a
line's start it kills nothing and never takes the line break before it.
Ctrl-U still keeps the key from an app's ⌘U (which arrives as Ctrl-U): it is
the terminal's own line kill, not an Emacs bonus. Cocoa binds no Ctrl-U; ⌘⌫
is its delete to the start of the line (deviations T7).

**The fuller version:** readline's append rule, where consecutive kills
(Ctrl-K, Ctrl-U, the word deletions) join into one kill ring entry, and a
real ring with Option-Y to cycle. *Price:* half a day for the append rule in
both handlers; the ring is a larger design (the macOS text system keeps one
slot, which is what TUI follows today).

### B-TEXT2-2. A bordered container keeps a drag selection begun inside it to its interior

*#10. `.border()`, `Box`, `Card`, `Panel`, `GroupBox`, `Dialog`, `Alert` —
every bordered `ContainerView` around content; not a `List`'s, a `Table`'s
or a menu's own box*

Each bordered box files its interior (inside the border lines, title row and
bottom line excluded) as a selection scope, as `textSelection(_:)` files its
content. The innermost scope under the press is what a selection keeps to,
the existing rule; an interior says nothing about *whether* text selects, so a
box inside `.textSelection(.disabled)` still selects nothing, and a box does
not turn on a list's row text as `.enabled` does. A drag begun on the border
or outside the box crosses it. The Example's Contact card is fixed by this
default: dragging from "Contact" down past the card selects the card's four
interior rows and nothing else (measured in the live Example under a PTY,
before and after). Since A-TEXT2-1's experiment, a drag that goes more than
3 rows or 6 columns outside the interior widens to the scope around the box.

The opt-out is a TUI-only modifier, `.textSelectionScope(_:)` with
`TextSelectionScope.container` (the default) and `.pane`: on the root view it
restores the old reach everywhere, on one box it frees that box, and
`.container` inside puts the rule back. Named for the scope it sets, as the
brief suggested; `.pane` rather than `.page`, since a selection already keeps
to its pane (a scroll view, a split view's column), never to the page.

**Cost, measured 2026-10-24.** As first shipped, each bordered box registered
a hover observer and journalled its scope, which a memoized row replayed every
frame: release A/B against the commit before the lane, warm, `modifiers`
+28.7%, `dashboard` +7.4%, `anyview` +3.8%. Since b8acc3898 the interior is a
region under the reserved `HitTestRegion.HandlerID.selectionInterior`, which
registers and journals nothing (`modifiers` −16.8% against that first form).
What remains is the region itself: a box that carried no regions now makes
every ancestor carry one, measured by switching the interior off — `modifiers`
+6.4% and `dashboard` +3.7% warm for having it, `modifiers` +1.3% cold. Under
the owner's ~10% line and accepted as the cost of the behaviour; making the
interior opt-in would remove it, and is the owner's call.

A list's, a table's and a menu's own box files none
(`ContainerConfig.keepsSelectionInside`): their presses are the control's,
and a list's or table's rows keep a selection to themselves already, so an
interior there would cost a region a frame for nothing — and it came in front
of a table's own region at its header gaps, which a test pins.

**The fuller version:** a scope on any surface that reads as a container
without a border (a `.background` panel, a `GroupBox` styled borderless).
*Price:* a rule for what counts, per view; not attempted.

### A42. Rich-text editing, now that P8 has shipped

*`AttributedTextSelection` and its members, `AttributedTextValueConstraint`,
`AttributedString.replaceSelection(_:with:)` and `(_:withCharacters:)`,
`AttributedString.subscript(_:)` (by selection),
`AttributedString.transform(updating:body:)`,
`AttributedString.transformAttributes(in:body:)`,
`AttributedString.init(transferable:in:)`,
`View.attributedTextFormattingDefinition(_:)`, `Optional.Scope` (an optional formatting definition's scope)*

SwiftUI's rich-text editing: a `TextEditor` over an `AttributedString`, its
selection carrying typing attributes, and constraints on which attributes an
edit may set. It presupposed `Text(AttributedString)` (P8 of the refusal
review), which has shipped with lane 17t (B84–B88): bold, italic, underline,
strikethrough, colours and links draw in cells. An attributed editor is now
the plain editor with styled runs, about two days; the selection type itself
is a day on top of `TextSelection`, which has shipped. **Recommendation:**
build it after the batch, with the formatting-definition constraints, if
rich text in a terminal editor is wanted; otherwise decline the family.

**Decided 2026-10-04: yes, build it.** Lane owed: about three days (the
attributed editor two, the selection type one), with the
formatting-definition constraints; the design is §7 of
[`Text selection and editing design study, A13, A42 and A43 (2026-10-04).md`](<../../SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md>).

**Formatting keys ruled (owner, 2026-10-23, A42-Q8: "the recommendation"):
menu now, chords through `TextFormattingCommands`.** A rich-text editor has
no formatting chords of its own: Bold, Italic, Underline and Strikethrough
are in its context menu (Shift-F10, a right-click, the Menu key), beside Cut
and Copy, so the Emacs chords Ctrl-B (back a character) and Ctrl-U (erase to
the start of the line) stay the editor's. An app that declares SwiftUI's
`TextFormattingCommands` in the menu bar gets their key equivalents as an
app's shortcuts: ⌘B and ⌘U, Ctrl-B and Ctrl-U under the default
`.commandKey(.control)`, which take the key from the Emacs chords (the
owner's 2026-09-23 rule, `TextEditingCommand.givesWayToKeyboardShortcuts`).
⌘I's Ctrl-I is Tab's byte in a legacy encoding, so Italic is the menu's
there; it fires where the kitty keyboard protocol sends Ctrl-I as itself
(B-D1K-3), and on a real ⌘I where the app asks for one
(`.keyboardShortcutsMatchCommand()`, B-D1K-1). Recorded by lane KEYS
(2026-10-24); built with A42, which has not started, and with
`TextFormattingCommands` (C-O13-3).

*Wave 6b's entries (A43, B62–B65): SwiftUI's behaviour was measured on macOS 15.8 (SDK 26.2) by driving a SwiftUI `TextField` in an `NSWindow` with key events; the probes are in `Tools/SwiftUIProbes/Vertical TextField keys, caret and size (wave 6b)/`.*

*Wave 10b's entries (B66–B71; A44 shipped, and A45 on 2026-10-07: a `List` pins its section headers under every style but `.sidebar`), pinned section headers and footers.* What SwiftUI does was measured on macOS 15.8, with offscreen `NSHostingView`s
in scroll views scrolled through their `NSScrollView`, reading the pixels down
a column (probes in [`Tools/SwiftUIProbes/Pinned section headers and footers`](<../../../Tools/SwiftUIProbes/Pinned section headers and footers>)):

- A header pins to the viewport's top while its section's **content** is under
  it. The content's last row pushes it up and away — the footer's top when the
  footer scrolls, the next header's top when there is none — so a header never
  sits over its own footer, and a header taller than what is left of its
  section rides up with it.
- A footer pins to the bottom, never above its section's first content row:
  with only a sliver of the content showing, it sits on that sliver, clipped by
  the viewport's edge.
- Pinned views draw over the content with no background of their own: rows
  show through wherever the header draws nothing.
- Only the stack's own sections pin — a `ForEach` of them, or ones written in
  its content, with any modifiers (a `.padding` on a section is applied to each
  of its parts, and its header still pins). A section in a row's `VStack` does
  not. Outside a scroll view nothing pins.
- A pinned stack below other content in the scroll view (a title above it)
  pins exactly as one at the top.
- Grids: a header and a footer span every column and pin the same way.
  Horizontal stacks and grids pin to the leading and trailing edges.
- `scrollTo(_:anchor: .top)` puts the row at the viewport's top edge, under a
  pinned header: nothing allows for it.
- `List`: `.plain` and `.inset` (and the macOS default) keep the first
  section's header at the top as the list scrolls; `.sidebar` does not. Read
  from the header's reported frame, which a floating table row may not update,
  so weaker evidence than the pixels above.

*Wave 8b's entries (A46–A51, B72–B80, C11): SwiftUI's behaviour was measured on macOS 15.8 (SDK 26.2) with an offscreen `NSHostingView`; the probes are in `Tools/SwiftUIProbes/Tab badges, sections and customization (wave 8b)/`. macOS 26 APIs could not be probed.*
