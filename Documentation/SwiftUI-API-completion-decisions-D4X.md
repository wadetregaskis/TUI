# Clipboard, screen selection and the wrapping editor: decisions for review

*The D4X lane's companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, for the owner-decided clipboard rule, A13 (D1) and A43, built
from [`SwiftUI-API-completion-design-text-editing.md`](SwiftUI-API-completion-design-text-editing.md)
and `Ghostty-VT-adoption.md` C1. 2026-10-05.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Seventeen, each with its fuller version and
  price. B-D4X-13 to 17 came out of the lane's review (round 1), which also
  found defects that are fixed rather than recorded here.
- **C. Declined without asking.** None.

Not built, as instructed: the mouse hand-off key (D0, you are choosing the
key), exact per-`Text` selection (D2, held), A42 rich text (after A43), and
copy mode (declined as feature creep).

## B. Shipped the safe option

### B-D4X-1. OSC 52 goes only to a terminal TUIkit can name

*The clipboard writer's ladder (`TerminalClient.clipboardWrites`)*

**Shipped:** a copy is sent by OSC 52 to Ghostty, kitty, WezTerm and foot
(writes by default), and — reported as "Sent to the terminal's clipboard" —
to iTerm2, tmux with `set-clipboard on`, and an unnamed terminal whose DA1
lists `52`. Any other terminal gets no OSC 52; over ssh such a copy is "Not
copied", with `TUIKIT_OSC52=1` as the user's way in.

**The fuller version:** send OSC 52 to every terminal as a best effort,
reported as sent. Most modern terminals write it (Alacritty, Windows
Terminal, Konsole, xterm with its resource set), and every host measured
swallows an OSC it does not implement. The risk is the host with no OSC
parser, which would print the base64 across the row — the reason OSC 8
follows the same table. About an hour; worth doing after `clipboard_probe.py`
has been run on a few more hosts.

### B-D4X-2. Under tmux, the plain sequence only

**Shipped:** inside tmux the plain OSC 52 is sent when `set-clipboard` is
`on` (asked of tmux at each copy), and nothing otherwise — `external`, the
default, ignores an application's write (measured, 3.7c).

**The fuller version:** wrap the write in DCS passthrough
(`ESC P tmux; … ESC \`) when `allow-passthrough` is on, which reaches the
outer terminal whatever `set-clipboard` says. Half a day with a probe row.

### B-D4X-3. iTerm2 is a maybe, whatever its setting

**Shipped:** iTerm2 writes OSC 52 only with "Applications in terminal may
access clipboard", off by default, and nothing TUIkit can read says which. At
the desk TUIkit uses `pbcopy` instead (sure); over ssh it sends OSC 52 and
says "Sent".

**The fuller version:** if `clipboard_probe.py` shows iTerm2's DA1 `52`
following the setting, ask iTerm2 its DA1 too (today DA1 is asked only where
the environment named no host) and treat a `52` as honoured. Half a day once
measured.

### B-D4X-4. The line about a copy stands in for the status bar's items

**Shipped:** for three seconds the line replaces the items' labels (their keys
still work), cut to one row so a narrow bar keeps its height too. A bar with
no items gains a row, as for a tooltip. A status-bar tooltip still adds a row
above the items and moves a centred page while it shows; a selection's
highlight goes for that time and comes back with the page (B-D4X-15).

**The alternative:** a row above the items, as a tooltip takes. That moves a
centred page half a row, and with it a selection's highlight. A notification
toast would need `.notificationHost()`, which an app may not have.

### B-D4X-5. Locality under tmux costs two subprocesses per copy

**Shipped:** `ClipboardLocality` asks tmux for its clients (`list-clients`)
and `set-clipboard` when a copy is made: two bounded forks per copy, none per
frame. A paste chord (Ctrl-V, a `PasteButton`) asks for the clients too: one
fork per press.

**The fuller version:** keep both in `ClientCapabilityRefresher`, which the
client-change hooks already refresh. Half a day; worth it only if a copy's
latency under tmux is ever noticed.

### B-D4X-6. The screen selection is on wherever a drag does nothing else

*A13, `textSelection(_:)`*

**Shipped:** with no modifier, D1's default tier: a drag on the page's
background, plain text or a scroll view's content selects. SwiftUI's default
is `.disabled`, but the terminal's own selection — which an app reporting the
mouse took away — selected any text. List and Table rows keep their meaning
unless `.enabled`.

**The alternative:** SwiftUI's default literally — nothing selectable without
`.textSelection(.enabled)`. Free; it would leave a TUIkit app with less than a
terminal gives a plain program.

### B-D4X-7. Row text under `.enabled` is kept to the row, not to the cell

**Shipped:** following macOS (measured, macOS 15.8, a SwiftUI `List` and
`Table` with `.textSelection(.enabled)`): a press on a row's text belongs to
the text — a drag selects it, a double-click a word, a click selects nothing,
the row selection untouched — and a press on blank cells is the row's. macOS
keeps a selection inside one `Text`, so in a multi-column `Table` inside one
cell; TUIkit keeps it to the row, crossing the columns.

**Menus on such a row** (measured, macOS 15.8.1, a SwiftUI `List` and `Table`
whose rows carry `Text(…).textSelection(.enabled)` and a `.contextMenu`, the
D4X `rowdrag.swift` probe): a right-click on the row's text with nothing
selected opens the row's menu; a right-click on a selection's highlight opens
the text's own menu (Look Up, Translate, Cut, Copy, Paste…), not the row's.
TUIkit does both: the highlight's Copy menu is offered the press first. A
Control-click on the row's text — the owner's call, 2026-10-06 — opens the
row's menu as a right-click does, and with no menu the row takes it as on its
blank cells; it no longer starts a selection. (Synthesised Control-clicks
open no menu on a SwiftUI row in the probe, the plain control list included,
so macOS's Control-click is read as its right-click, which it is.)

**A drag on a draggable or movable row's text** (measured, the same probe,
asked by the owner 2026-10-06, who expected the row to drag): in a SwiftUI
`List` whose rows are `.onMove`, `.draggable` or `.itemProvider`, and a
`Table` whose rows are `TableRow(…).draggable` or `.itemProvider`, a drag
that starts on the row's selectable text selects the text — the text view
takes the press and becomes the first responder, the copy reads what the drag
crossed — and the row is neither moved nor selected; a press on the plain
control list's text goes to the list instead. (The probe cannot see a row
drag begin even from blank cells — synthesised drags start no AppKit drag
session — so the evidence is that the text, not the row, received the
press and tracked the drag.) TUIkit matches: a drag handle under selectable
text gives a press on the text to the selection (`PressRole.dragSource`), and
the row still drags from its blank cells and from text no `.enabled` made
selectable. The alternative, the owner's expectation — the row drags, and
selecting its text needs a modifier or a long press — is an hour (the
handle simply keeps the press), but it is not what a Mac does.

**The fuller version:** the `Table` files its columns' geometry with its rows
(`PressRole.rows`), and a selection keeps to the cell. About two hours. D2,
held, would make every `Text` exact.

### B-D4X-8. What is selected is the page, not the layers over it

**Shipped:** the selection reads and paints the page before menus, popovers
and offset drawings are composited, so a menu draws over the highlight, as
the design study placed it. Text inside a popover cannot be selected, and a
presentation (a sheet, an alert, an app's menu) clears the selection; its own
Copy menu is the exception.

**The alternative:** read the finished frame, overlays and all. Tried first:
a menu opened over the highlight then read as changed cells, and the
highlight went for good.

### B-D4X-9. `textSelectionCopiesOnRelease(_:)`

**Shipped:** the TUI-only scene setting that opts into copying at the
release is spelled `Scene.textSelectionCopiesOnRelease(_ copies: Bool = true)`,
beside SwiftUI's `textSelection(_:)` family. Rename freely.

### B-D4X-10. The wrapping editor's vertical keys follow `NSTextView`; its page keys do not

*A43*

**Shipped:** measured on macOS 15.8 with a SwiftUI `TextEditor` (an
`NSTextView`): Up, Down, Ctrl-P and Ctrl-N move by rows keeping the column
through short rows; Up from the first row goes to the start and Down from the
last to the end; Ctrl-A and Ctrl-E keep the paragraph; a tab's stop is counted
from its row's start. TUIkit's wrapping editor does all of these. Page Up and
Page Down only scroll an `NSTextView`, and Home and End scroll to the ends;
TUIkit's editor moves the caret for them, by a screen of rows and to the
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
Example's seven languages. Half a day.

### B-D4X-13. A session under a session keeper is never "at this machine", and under GNU screen no OSC 52 is sent

*The clipboard rule's locality (`ClipboardLocality`) and the writer's ladder
(`TerminalClient.clipboardWrites`)*

**Shipped:** a session keeper TUIkit knows — GNU screen, zellij, dtach,
abduco, shpool, tmate, WezTerm's mux server, and a tmux above a tmux client
in its chain (a tmux run inside another tmux's pane) — in the process's chain
or by its variable (`STY`, `ZELLIJ`, `ZELLIJ_SESSION_NAME`, `ABDUCO_SESSION`,
`SHPOOL_SESSION_NAME`), answers "not local" even at the desk: its server is
detached from the terminal that started it, so a session begun at the desk
can be attached over ssh with nothing in the process to say so, and none of
them can be asked for its clients as tmux is. Eternal Terminal's
`etterminal` joins `etserver` as a remote-session daemon. A keeper TUIkit
does not know passes as a plain parent: the list is what has been found, not
everything there is. (Review 2 found nested tmux, `wezterm-mux-server` and
`tmate` missing; the first is the one that put text on a server Mac's
pasteboard.)

Under a keeper a copy goes by OSC 52 where the terminal's rung takes it, and
is "Not copied", said so, where none does — and under GNU screen always:
screen passes an application's OSC 52 on only inside its own DCS passthrough,
so the ladder answers unsupported inside screen (`STY`) whatever terminal the
inherited environment names, where it used to report "Sent" (iTerm2) or
"Copied" (Ghostty) of a write screen dropped. A paste chord under a keeper,
as anywhere away from the machine, pastes the app's own last copy and says
so, or says to use the terminal's paste (B-D4X-14).

**The cost at the desk** (review 2: unpriced): a session at the desk inside
any of these keepers no longer reaches the desk's clipboard. Copies go by
OSC 52 only where the outer terminal is named and takes it — Ghostty, kitty,
WezTerm, foot by default, iTerm2 as a maybe — and under screen nowhere: an
iTerm2 → screen copy that `pbcopy` used to make is now "Not copied". Ctrl-V
and a `PasteButton` there no longer read the desk's clipboard: text copied in
Safari comes in by the terminal's ⌘V, and Ctrl-V pastes the app's own last
copy (said so) or says to use ⌘V. The terminal's own selection and paste work
throughout. `TUIKIT_OSC52=1` still forces OSC 52, screen or not.

**The fuller version:** (a) screen's DCS passthrough — the OSC 52 wrapped as
`ESC P ESC ] 52 ; c ; … BEL ESC \`, chunked under screen's string limit —
would carry copies through screen to the terminal: half a day and a probe
row, unmeasured. (b) Ask each keeper for its clients where it can be asked —
zellij's and screen's session sockets, an outer tmux's `list-clients` (its
socket from the outer server's environment) — and walk each client's chain
as tmux's are: half a day per keeper, and only where the keeper answers at
all (dtach and abduco keep no client list).

### B-D4X-14. Away from this machine, a paste chord pastes the app's own latest copy

**Shipped:** where this machine's clipboard is not the user's, Ctrl-V, a
`PasteButton` and a `pasteDestination` find the text of the latest copy the
app made, whatever became of it, so the in-app round trip the server's
pasteboard used to carry over ssh still works (a field's Ctrl-C into another
field; a `copyable` value into a `PasteButton`, as itself). With no such copy
the status bar says "Nothing to paste here: use the terminal's paste"; with
one, it says "Pasted this app's last copy: for your clipboard, use the
terminal's paste", because the copy may be older than what the user last
copied on their own machine (review 2: that paste was silent).

**The alternative:** paste nothing away from the machine, with the same line
— the user's own clipboard is never stale then, but nothing the app copied
can be pasted back into it without the terminal's paste. Free either way;
this follows tmux's buffer and vim's register.

### B-D4X-15. A screen selection whose highlight has gone stands aside, and comes back only with its page

**Shipped:** the highlight is drawn while the cells under it read the
selected text. When they stop, the selection takes no keys (Ctrl-C and Escape
are the app's). If the content area is where the highlight was last drawn,
the cells themselves changed — a log scrolled on, a spinner turned — and the
highlight is gone for good. If the content area moved — a status-bar
tooltip's row, a copy's line, taking a row from a centred page — the page
moved under it, and the highlight, its keys and its Copy menu come back when
the area is back and the cells read the text again. (Review 2: coming back on
any match made it blink over a line that cycles back to the text, its keys
flipping with it, and revived a selection when an equal log line scrolled
onto its cells.)

**The alternatives:** keep the invisible selection's keys, so Ctrl-C copies a
log line that has scrolled away (the design study's reading; it took the
focused view's Ctrl-C and an `onExitCommand`'s Escape); or clear the
selection the moment its highlight goes (a tooltip would then lose it for
good). Free either way. A move of the page's content inside the area — a
scroll view the tooltip's row shortened — is a change of the cells, and loses
it.

### B-D4X-16. Upstream, a caret moved onto a wrapped row lands after its first character

**Shipped:** under `.textSelectionAffinity(.upstream)` the start of a wrapped
row is drawn at the end of the row before it, so Up, Down and a click put a
caret on a wrapped row at its first upstream position, after its first
character, in a vertical `TextField` and a wrapping `TextEditor` alike. A
selection's ends are not carets: a drag that starts or ends on a wrapped
row's first cell, and a Shift-click there, take that character in ("aaaa
bbbb cccc" at width 6, dragged across "bbbb" from its first cell, selects
"bbbb"; review 2 found it selecting "bbb" once the caret rule fed the drag).
The affinity is the view's, one for every caret.

**The fuller version:** an affinity per caret, as the macOS text system keeps
— a caret an arrow key moved to a row's start leans downstream and is drawn
there, one typed or clicked to the end of a row leans upstream — with the
view's affinity as the default. Half a day in `SoftWrapLayout` and the two
handlers. Downstream, the mirror case is unchanged from before the rule: a
drag ending on a wrapped row's trailing margin stops before its hanging
space, which a drag onto the next row takes.

### B-D4X-17. `.textSelection(.enabled)` on a Table cell's Text makes the row's text selectable

**Shipped:** on a `List` row's own `Text` the modifier makes that text
selectable, kept to it, as SwiftUI's example does. On a `Table` cell's `Text`
it makes the whole row's text selectable, kept to the row — as the modifier
around the table does (B-D4X-7) — but for a press on that cell's own text,
which is kept to the cell: the table carries a view cell's regions up (B46),
the scope's among them, and draws the rest of the row as text, keeping no
rectangle of it. Inside an outer `.textSelection(.disabled)` the cell's
`.enabled` still wins on its own text, the innermost modifier winning as in a
`List` (review 2 read it the other way; `innermostWinsInRows` pins it); the
row's other text is under the outer scope alone, and selects nothing. A
`TableRow(…).draggable` row's selectable text, too, is selected by a drag
that starts on it, as on macOS, and the row drags from elsewhere (B-D4X-7).

**The fuller version:** the table remembers which columns' cells filed an
enabled scope and files the columns' geometry with its rows, so only those
cells' text selects and a selection keeps to the cell. About half a day;
it is B-D4X-7's fuller version with one more input.
