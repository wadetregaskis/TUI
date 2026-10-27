# Copying out of a terminal: the clipboard, screen selection and session keepers

*How a copy reaches the user's clipboard from a terminal app — OSC 52 where a
terminal TUI can name takes it, through tmux and GNU screen, and the app's own
copy where nothing does — and how the screen selection works: what a drag
selects, where it stops, and when it goes. Ids: B-D4X-1 to 9, B-D4X-13 to 15,
B-D4X-17, B-D4X-7-17, D4X-LOCALITY, C-TEXTFMT-2, C-TEXTFMT-3.*

## In short

A copy goes by OSC 52 only to terminals TUI can name as taking it (Ghostty,
kitty, WezTerm, foot; iTerm2 is a maybe), through tmux's plain sequence or
passthrough and GNU screen's DCS strings where they reach the outer terminal,
and a line in the status bar says what happened. Away from this machine, a
paste chord pastes the app's own latest copy. A drag selects the page (not the
layers over it) wherever it does nothing else; a table cell's
`.textSelection(.enabled)` keeps its selection to the cell.

## How it unfolded

1. **Lane D4X** built the clipboard and the screen selection (and the wrapping
   editor, in its own story), with the calls below.
2. **2026-10-23, the owner** concurred on keeping a cell's selection to the
   cell (B-D4X-7-17), found the screen and tmux paths fine, and asked about
   asking keepers for their clients (D4X-LOCALITY). Lane TEXTFMT built both on
   2026-10-24, measured on GNU screen 4.00.03 and tmux, and declined asking
   keepers for clients for now (C-TEXTFMT-3).

## For a future reader

- **B-D4X-15 is recorded until someone runs into it**: a screen selection
  whose content moves inside an unchanged area (settled 2026-10-18).
- **iTerm2 writes OSC 52 only with its "Applications in terminal may access
  clipboard" setting on**, which TUI cannot read.

## The record

### B-D4X-1. OSC 52 goes only to a terminal TUI can name

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
access clipboard", off by default, and nothing TUI can read says which. At
the desk TUI uses `pbcopy` instead (sure); over ssh it sends OSC 52 and
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
`.textSelection(.enabled)`. Free; it would leave a TUI app with less than a
terminal gives a plain program.

### B-D4X-7. Row text under `.enabled` is kept to the row, not to the cell

**Shipped:** following macOS (measured, macOS 15.8, a SwiftUI `List` and
`Table` with `.textSelection(.enabled)`): a press on a row's text belongs to
the text — a drag selects it, a double-click a word, a click selects nothing,
the row selection untouched — and a press on blank cells is the row's. macOS
keeps a selection inside one `Text`, so in a multi-column `Table` inside one
cell; TUI keeps it to the row, crossing the columns.

**Menus on such a row** (measured, macOS 15.8.1, a SwiftUI `List` and `Table`
whose rows carry `Text(…).textSelection(.enabled)` and a `.contextMenu`, the
D4X `rowdrag.swift` probe): a right-click on the row's text with nothing
selected opens the row's menu; a right-click on a selection's highlight opens
the text's own menu (Look Up, Translate, Cut, Copy, Paste…), not the row's.
TUI does both: the highlight's Copy menu is offered the press first. A
Control-click on the row's text — the owner's call, 2026-10-06 — opens the
row's menu as a right-click does, and with no menu the row takes it as on its
blank cells; it no longer starts a selection. It is the secondary click for
what reads it so — rows, `.contextMenu`, a tab — and not for a control that
acts on a left press: a Control-click on a `Button` in a table cell presses
it, where a right-click there opens the row's menu (the follow-ups' review
found the article saying "wherever it lands"; macOS unmeasured there).
Where nothing takes it as a secondary click, it falls through to the pane it
landed in, as the owner's "falls through the view hierarchy" reads: a scroll
view's viewport focuses the scroll view, a split view's column activates its
section, as a Control-click did before it was the secondary click (the
follow-ups' review found those panes passed over with nothing behind them, so
a Control-click there did nothing, in apps that use no menu too). It is that
pane's click where it is released inside the pane, a drag about it making
nothing; dragged out of the pane and released elsewhere, it does nothing, as
a button let go off it does (its second review found any Control-drag, however
far, delivered as the pane's click). (Synthesised Control-clicks
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
press and tracked the drag.) TUI matches: a drag handle under selectable
text gives a press on the text to the selection (`PressRole.dragSource`), and
the row still drags from its blank cells and from text no `.enabled` made
selectable. Selectable is decided by the innermost scope under the press,
filed inside the handle or around it alike, so the order of `.textSelection`
and `.draggable` does not matter, as it does not in SwiftUI, where
`textSelection` is environment-like; nor does the container (a scroll view
of draggable text selects as a list of it does). A control's label is not
selectable text (on macOS a tab's title and a button's label are not): a
handle in front of a region that would take the press as a control — before
anything that holds it for a selection — keeps it, as with no scope, and a
press released there is still the control's click. A field is such a
control: a drag on a `TextField`'s text in a draggable row moves the row,
and a click there focuses the field, under a scope as with none (the review
of the follow-ups' fixes found the rule described of a label only). What
takes no plain left press is not a control: a scope, a hover observer, a drop zone, a context
menu's trigger. Nor is an app's `.onMouseEvent` closure (and
`onScrollGesture`, built on it), which says whether it takes a left press
only when offered one: the handle stands aside, and the closure is offered
the press in turn, so one that declines it leaves the drag to select, and
one that takes it has it, as under the scope with no handle (the review of
the follow-ups' fixes found a closure declining left presses taken for a
control, so a drag on its text moved the view). (The follow-ups' first review found a draggable tab's title,
a gradient stop and a `Button` in a `.draggable` view passing the press on
under an outer scope, so the tab strip or the button took it and nothing
dragged; its second, that the fix — selectable only under a scope the
handle's own content filed — made the result depend on the modifiers'
order, and on the container.) A sidebar tab view's
list of tabs opts out of selection for the same reason: under an enabled
scope around the tab view it kept a press on a tab's title for a selection,
as row text is kept, so a click there selected no tab. The alternative, the owner's expectation — the row drags, and
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

### B-D4X-13. A session under a session keeper is never "at this machine", and under GNU screen no OSC 52 is sent

*The clipboard rule's locality (`ClipboardLocality`) and the writer's ladder
(`TerminalClient.clipboardWrites`)*

**Shipped:** a session keeper TUI knows — GNU screen, zellij, dtach,
abduco, shpool, tmate, WezTerm's mux server, and a tmux above a tmux client
in its chain (a tmux run inside another tmux's pane) — in the process's chain
or by its variable (`STY`, `ZELLIJ`, `ZELLIJ_SESSION_NAME`, `ABDUCO_SESSION`,
`SHPOOL_SESSION_NAME`), answers "not local" even at the desk: its server is
detached from the terminal that started it, so a session begun at the desk
can be attached over ssh with nothing in the process to say so, and none of
them can be asked for its clients as tmux is. Eternal Terminal's
`etterminal` joins `etserver` as a remote-session daemon. A keeper TUI
does not know passes as a plain parent: the list is what has been found, not
everything there is. (Review 2 found nested tmux, `wezterm-mux-server` and
`tmate` missing; the first is the one that put text on a server Mac's
pasteboard.)

Under a keeper a copy goes by OSC 52 where the terminal's rung takes it, and
is "Not copied", said so, where none does — and under GNU screen always:
screen passes an application's OSC 52 on only inside its own DCS passthrough,
so the ladder answers unsupported inside screen (`STY`) whatever terminal the
inherited environment names, where it used to report "Sent" (iTerm2) or
"Copied" (Ghostty) of a write screen dropped. In a tmux pane under
`set-clipboard on`, tmux's clients decide — those that see the write, whose
session holds the app's pane (`TMUX_PANE` among the session's panes that
`list-clients` prints), not every client of the server: where every one of
them runs in a screen window (screen holds its terminal: the first process
above the client attached to another terminal, or to none, is screen's —
not screen anywhere above it, as a GUI terminal started from a shell inside
screen draws its clients itself), nothing is sent and the copy is "Not
copied"; where one does not, tmux's answer stands ("Sent"); a screen run
in a tmux pane, seen in the app's own chain, sends nothing. Neither `STY` nor
the pane's chain can tell: a tmux server started inside screen keeps its
`STY` whoever attaches, and the server daemonizes, so a pane's chain ends at
it however the session is attached (the follow-ups' first review found `STY`
saying "Not copied" of such a session attached straight from Ghostty or
iTerm2; its second, the chain then saying "Sent" of one still attached from
inside screen, where nothing arrives; the review of that fix, every client of
the server counted, so that a client of another session, attached from the
terminal, said "Sent" for the app's own, attached from inside screen, and
screen anywhere above a client said "Not copied" of one in a GUI terminal
started from inside screen). Where
the clients cannot be read, or none shows the pane, the write goes as a
maybe, reported "Sent", never "Copied". A paste chord under a keeper,
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
row, unmeasured. **Shipped 2026-10-24** (lane TEXTFMT, owner ruling
D4X-LOCALITY), with tmux's passthrough under `allow-passthrough`, both
measured with `Tools/TerminalProbes/keeper_passthrough_probe.py`: decisions
[TEXTFMT](<Formatting and live text.md>). (b) Ask each keeper for its clients where it can be asked —
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
highlight is gone for good, and the selection with it (unless its own menu is
open over it, whose Copy still copies it): the follow-ups' review found a dead
selection kept, reading its cells every frame until a press. If the content
area moved — a status-bar
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

**Fixed 2026-10-24 (lane TEXTFMT, owner ruling B-D4X-7-17, option 1).** A
cell's `.textSelection(.enabled)` makes that cell's text selectable, kept to
the cell, and nothing else: a press on the row's other text is under no
scope, so a drag there selects nothing and a click selects the row, as on
macOS. No column geometry was needed — the scoped cell's own region, which
the table already carried up, is what a selection keeps to — so the fix is
the removal of the flag (`cellsSelectText`) that treated the row's unscoped
text as enabled. An enabled scope around the table still keeps a selection
to the row, crossing its columns (B-D4X-7). Decisions
[TEXTFMT](<Formatting and live text.md>).

### e7ce4b0f7's suspend flush — not an issue, now pinned

The question: does Ctrl-Z (suspend) flush an OSC 52 write still queued — a
copy made between the last frame and the key? Yes. The run loop handles the
suspend flag by setting the scene phase to `.background` and drawing one more
frame (`App.swift`, `renderOutsidePacer`) before `suspendUntilContinued` hands
the terminal back. That frame is an ordinary `RenderLoop.render`, which has
no early return before `writeFrame`, and `writeFrame` writes
`clipboardWriter.takePendingSequences()` right after `beginFrame`, ahead of
every cell — so the copy reaches the terminal while it is still the app's.
Quitting has its own drain (`cleanup`), as before.
`ClipboardWriterTests` pins the frame half: a copy queued for a terminal that
writes OSC 52, then a frame drawn at `.background`, leaves the queue empty and
the bytes written. The signal half (that the suspend path draws that frame)
is read from the code; it needs a real stop to test.

### Still open after the follow-ups

After the follow-ups' own review (round 1), which found the upstream drag
head read on the row before, drag handles yielding to a tab's title, a
Control-click going nowhere over a pane with no menu, a stale `STY`
outranking tmux (whose fix the second review found moving the error to a
tmux still attached from inside screen; tmux's clients decide now),
`tmux*`-named wrappers taken for tmux, a dead screen selection read every
frame, and the probe advising a plain-text copy where types cannot be
listed — all fixed — these remain:

- **Clipboard locality** (B-D4X-13): a session keeper TUI does not know
  passes as a plain parent; a nested tmux at the desk is "not local" (its
  outer server is not asked for its clients); under GNU screen a copy goes
  through its DCS passthrough since 2026-10-24 (measured on 4.00.03), and
  screen 5 is unmeasured; nothing on a host
  is measured yet (`clipboard_probe.py` is owed its runs). A tmux server
  started inside screen keeps screen's stale `STY`, which still makes its
  sessions "not local" at the desk even when attached straight from the
  terminal (failing safe: tmux's `set-clipboard` carries the copy by OSC 52
  there). Where tmux's clients cannot be read, a tmux under screen sends the
  copy as a maybe and reports it "Sent", though nothing may arrive; so it
  does where a client in a screen window runs behind a pty of its own — a
  `sudo` with `use_pty`, `script` — which then holds its terminal, not
  screen (unmeasured).
- **Paste away from the machine** (B-D4X-14): Ctrl-V pastes the app's own
  last copy, which may be older than the user's — said so now, still pasted.
- **The screen selection** (B-D4X-15): content moved inside an unchanged
  content area — a scroll view shortened by a tooltip's row — loses the
  selection for good; a change of the terminal's height leaves one displaced
  (no highlight, no keys) until the height comes back.
- **Upstream affinity** (B-D4X-16): one affinity per view, not per caret;
  downstream, a drag to a wrapped row's margin stops before its hanging
  space.
- **Right-press hand-off** (review 2 of 9873ddc07) — fixed: drags that
  arrive in the same read as a menu-opening right press, before the menu's
  first frame, were hit-tested against page controls, and `TextEditor`'s
  `.dragged` arm did not check the button, so a fast right-drag on a
  highlight over an editor could move the editor's selection. The
  dispatcher spends such drags until a frame has drawn the menu, the
  highlight's Copy menu's included (`MouseEventDispatcher.routeAgainstItsPress`),
  and since 2026-10-18 the editor's and `TextField`'s drag arms take the
  left button's drag alone (`TextEditorRightDragTests`).
- **`textSelection` on multi-member content** (review 2 of b61f80177): on a
  `ForEach` or a `Group` each member files its own scope, so a drag keeps to
  the member it began on (SwiftUI's per-`Text` behaviour); the modifier's
  doc said a drag inside an enabled container "may cross from one Text into
  the next", true only of a container that is one view. The doc says so since
  2026-10-19 (lane DOCS).
- **The wrap cache** (review 2 of f543a9c2d): a frame that asks more than
  eight widths evicts its own first width.
- **Drag sources** (B-D4X-7): a `.draggable` view outside a list whose text
  is selectable follows the rows' rule — a drag on its text selects — which
  is unmeasured on macOS for a view outside a list. A draggable view or row
  drags from a control's label in it (a `Button`), and a click there is the
  control's, as with no scope (unmeasured on macOS). So it does from a
  field's text: a drag in a `TextField` in a draggable row moves the row and
  selects nothing in the field, scope or no scope (macOS unmeasured; a field
  that kept such a drag for its own selection would change the no-scope
  case too, so it is a design question, not this rule's). A region of TUI's
  that takes no plain left press but is not filed as passive is taken for a
  control, so a handle in front of it keeps a press on text: the passive
  regions are drop zones, spring-loading zones, context menus' triggers and
  two containers' inert regions (a tab view's, the 256-colour grid's),
  besides scopes and hover observers; an app's `.onMouseEvent` closure is
  offered the press instead, so one that takes a left press on selectable
  text inside a `.draggable` view has it, where with no scope the view
  drags.
- **Control-click on a control** (B-D4X-7): a control that acts on a left
  press — a `Button` in a table cell, a field — takes a Control-click as its
  click, where a right-click there opens the row's menu. Making every control
  decline a Control-press would change every app's buttons; macOS unmeasured.
- **Table cell readers** (B-D5G-2): located now, but a cell carries no
  origin, so a reader's first frame costs a second walk of the scene.
- **The probe** (148a07f5d): with no helper to read the clipboard (over ssh
  without `--manual`), the leak check runs only with `--clobber`, since its
  write cannot be put back. Its macOS rich-text type names (`«class rtfd»`
  and the rest) are unverified on a Mac; they only choose the refusal's
  wording.
- **The A/B note on 2b3295280**: the `text-editor*` Stress variants now sit
  in a conditional, so an A/B of f543a9c2d must hold the Stress sources
  fixed across both builds.

### C-TEXTFMT-2. Declined: a modifier to choose cell or row for a table-wide scope

*A `TextSelectionScope.cell`, or a table modifier, making `.textSelection(.enabled)`
around a `Table` keep each selection to one cell, as macOS does*

Not built, because where the modifier goes already chooses: on the cells'
`Text` (`TableColumn("Name") { Text($0.name).textSelection(.enabled) }`) a
selection keeps to the cell, as macOS's does, and around the table it crosses
the row's columns, which is TUI's screen selection everywhere else (T6). A
third spelling for the first would add API without adding a behaviour, and no
app has asked for a table-wide scope that keeps to cells.

**Price, if wanted:** about two hours. A `.cell` case on `TextSelectionScope`
(TUI's existing modifier for what a selection keeps to), read by the table,
which files its columns' x-ranges with its rows so that a press under a
table-wide scope keeps to the column under it.

### C-TEXTFMT-3. Declined for now: asking keepers for their clients

*screen's and zellij's session sockets, an outer tmux's `list-clients`*

The follow-up's answer, and the ruling's: only for a keeper someone uses and
asks for. It is the one way to know the user is at the desk under a keeper,
which would let `pbcopy` and the desk's clipboard serve such a session, but
each keeper has its own interface (dtach and abduco have none), the answer is
a snapshot a reattach makes stale, and it does nothing over ssh. About half a
day per keeper.
