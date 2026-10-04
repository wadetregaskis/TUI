# Completing the SwiftUI API: Wave 6b decisions (vertical text fields and text selection)

*Wave 6b's entries, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
for folding into it. The wave covers `TextField`'s `axis:` initialisers — a
field whose text wraps over rows that grow downward — its `selection:`
initialisers, wired to the `TextSelection` exchange already on main, and the
soft-wrap question that both raise for `TextEditor`.*

Every SwiftUI behaviour below was measured on macOS 15.8 (the machine's OS;
the SDK is 26.2), by driving a SwiftUI `TextField` in an `NSWindow` with key
events through the window's key path and reading the bound text, the field
editor's selection and its layout manager's line fragments, and by measuring
`NSHostingView.fittingSize`. The probes are in the session notes
(`w06b/probe/`: `keys.swift`, `size.swift`, `nav.swift`, `affinity.swift`).
macOS 26 was not available.

---

## A. Needs your decision

### A-W06b-1. `TextEditor`: wrap long lines as SwiftUI's does, or keep scrolling sideways?

*No symbol: `TextEditor` is already API. This is how it lays its text out.*

SwiftUI's `TextEditor` is an `NSTextView`, which wraps a long line at the
editor's width. TUIkit's scrolls horizontally to follow the caret instead, as
many terminal editors do; its documentation calls soft wrapping "a possible
future option". That was a choice, not a constraint, and it is a parity gap: a
note-taking view ported from SwiftUI shows one long line per paragraph, cut at
the right edge, until the caret walks it sideways.

This wave built the half of soft wrapping that is about text rather than about
an editor — `SoftWrapLayout`, which lays text into rows by the macOS rules and
maps a caret's offset to a row and a column and back — and the vertical
`TextField` draws through it (B-W06b-1). The editor would draw through it too.

**Options:**

1. **Keep scrolling sideways.** Free. The gap stays, documented.
2. **Wrap by default, as SwiftUI does.** About two and a half days:
   - the editor's line-and-column caret gains rows: Up, Down, Page Up and
     Page Down move by row, and Ctrl-A and Ctrl-E stay on the line (the
     paragraph, as in the field), all measured against an `NSTextView` first;
   - scrolling, the scroll bar's extent, a click's position and the selection's
     painting all count rows rather than lines, and horizontal scrolling goes;
   - tabs: the layout gives a character one width wherever it sits, and an
     editor's tab reaches the next tab stop, so the layout needs a width that
     depends on the column a character starts at (the editor already computes
     one, `TabLayout.advance`);
   - the caret's affinity at a wrap starts to mean something in the editor;
   - every editor test that pins horizontal scrolling is rewritten;
   - cost: the editor already splits its whole document into lines on every
     frame, and wrapping adds a width walk over it, roughly doubling the
     per-frame text work on a large document. A per-line wrap memo keyed by
     the line and the width bounds it; that wants an A/B on the stress
     harness's two-thousand-line code editor before it lands.
3. **Option 2, plus a TUIkit modifier that keeps the sideways scroll** for the
   texts that want it — code, logs, tables in plain text. Half a day more.

**Recommendation:** 3, after the waves. Parity by default is what ported code
expects, and the sideways scroll is worth keeping as a choice, not as the only
behaviour.

## B. Shipped the safe option

### B-W06b-1. A vertical `TextField` is a text field that wraps, not an editor with a field's chrome

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

**Where TUIkit chose, unmeasured.** A combo box's `▾` sits on the first row,
and Down opens the suggestions only from the last row (above it Down moves a
row). Page Up and Page Down only scroll a SwiftUI vertical field, leaving the
caret where it was (measured); TUIkit's field scrolls only to follow its caret,
so it has nothing for them to page, and leaves them to the view around it.

**The fuller version:**

- **The caret's lean at a wrap, per caret.** Where a row wrapped, one offset is
  both the end of a row and the start of the next. TUIkit draws the caret by
  `\.textSelectionAffinity`, and `.automatic` at the start of the later row.
  macOS keeps a lean per caret (measured): an arrow key leaves it downstream,
  as TUIkit draws it, but typing, a click and Ctrl-E leave it upstream, at the
  end of the earlier row. The two draw the same offset in different places, and
  the next character typed goes to the same place either way. About half a day
  to track the lean through each kind of motion, after measuring the motions
  not yet measured (deletion, Up and Down, Home and End).
- **A scroll indicator** while the text is taller than the field, as the
  editor draws one. A field on one line shows no indicator for its sideways
  scroll either. Half a day, mostly finding a column for it: the margin cell is
  the caret's.
- **The wheel.** A pointer over a scrolled field could scroll it, which the
  editor does not do either. Half a day for both.
- **An Example page section** with a vertical field, which wants its strings
  in the Example's seven languages.

### B-W06b-2. A newline from the keyboard: Option-Return where the terminal sends it, Ctrl-O everywhere

*Part of `TextField.init(_:text:axis:)` and the other `axis:` forms*

Measured on macOS 15.8, in a vertical field:

| Key | SwiftUI |
|-----|---------|
| Return, Shift-Return, keypad Enter | submit (`onSubmit`), insert nothing, select all |
| Option-Return | inserts a newline, caret after it (`insertNewlineIgnoringFieldEditor:`) |
| Ctrl-Return | inserts U+2028 LINE SEPARATOR (`insertLineBreak:`) |
| Ctrl-O | inserts a newline, caret before it (Cocoa's open line) |
| Ctrl-J, Ctrl-M | nothing |

What a terminal delivers decides what TUIkit can honour:

- **Option-Return** arrives as ESC CR where the terminal sends Option as Meta
  (Terminal.app with "Use Option as Meta Key", iTerm2 with Option as Esc+, and
  the terminals whose own setting does the same). TUIkit inserts a newline
  for it. Without Meta it is a plain CR, indistinguishable from Return, and
  submits.
- **Ctrl-O** is byte 0x0F from every terminal. TUIkit opens a line, as macOS
  does. This is the route that is always there: Ctrl-O, then Ctrl-F (or Right)
  past the newline.
- **A paste** keeps its line breaks, each as one newline whatever the
  clipboard used.
- **Ctrl-Return and Shift-Return** arrive as a plain CR from every terminal
  that does not speak an extended keyboard protocol, so they submit. Ctrl-Return
  would be U+2028 in SwiftUI.

**The fuller version:**

1. **Ctrl-J as newline-and-advance on every terminal.** LF (0x0A) is Ctrl-J,
   and only Ctrl-J sends it in raw mode, where the Return key sends CR. Today
   the input parser reads LF and CR alike as `.enter`. Reading LF as its own
   key would make Ctrl-J deliverable everywhere — it is the newline key of many
   terminal chat and prompt tools. About half a day with the tests. The risk
   is any path that delivers LF for Return (none known with `ICRNL` off, but a
   multiplexer or a serial line would need checking), where every Return would
   insert a newline instead of submitting. It also bears on A4, which lists
   Ctrl-J among the chords only the kitty protocol frees.
2. **Shift-Return and Ctrl-Return** wherever A4's kitty keyboard protocol is
   negotiated, where they arrive as themselves. Comes with A4.

### B-W06b-3. `lineLimit`'s range forms ship, reversing their omission

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

### B-W06b-4. A text field's selection is one range

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

## C. Declined without asking

None.

## D. Deferred

- **Option-Return in a field on one line.** Measured on macOS 15.8, it inserts
  a newline even into a horizontal `TextField`. TUIkit's field on one line
  submits on Option-Return, and strips newlines from a paste, because it has
  nowhere to draw one. Found while measuring; left as it was.
- **`searchSelection(_:)` (A25).** Now that a `TextField` takes a selection
  binding, binding the search field's is a few lines, but A25 waits on A13
  (whether TUIkit draws its own text selection), which is unchanged.
- **macOS 26:** every measurement here is macOS 15.8's. A pass over the same
  probes on macOS 26 is owed.
