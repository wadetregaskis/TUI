# A13, A43, A42 — selecting text, a wrapping editor, rich-text editing: a design study

*Read-only study at `a61b9748`, 2026-10-04. Inputs: the decisions doc's A13
(line 522), A25 (837), A42 (1299), A43 (1321), B62–B65 (3540–3670) and
B84–B92 (4263–4560); `Terminal compatibility survey.md` on Apple Terminal's and
iTerm2's mouse input (883–914, 1012–1060), on OSC 8 gestures (2864–2903) and on
keyboard modifiers (3747–3966); `Find pasteboard and the remote viewer.md`
(OSC 52, 132–147); SwiftUI's symbols through `plan/sdoc.py`; the parity
baseline and map in `Tools/APIParity/`. Nothing was built, run or measured.
Every cost is an estimate. Every terminal behaviour not already in the
compatibility doc is labelled a hypothesis, with the probe that would settle it.*

---

## 0. In one page

**A13, selection.** The owner's problem is that a TUI app reports the
mouse, so the terminal's own selection needs a modifier or a menu toggle. No
toggling trick removes that (§3): the terminal decides at the press whether a
gesture is its own, and with reporting off the app hears nothing more. The
only way to make the toggle unnecessary is for TUI to select and copy by
itself. **Recommended: D1.** A drag that no control uses selects what is on
the screen, as a terminal would, clipped to the pane it started in, and copies
it. `.textSelection(.enabled)` widens that to drags over list and table rows.
`.textSelection(.disabled)` turns it off. A **copy mode** is the keyboard
route. **D0** comes with it, about half a day more: one key hands the mouse
to the terminal, keeping the wheel through alternate-scroll mode. That is the
fallback where no clipboard route reaches the user.

D1 costs nothing per frame in an app that selects nothing. It needs no work
per `Text`, and the drawing is a pass after composition that runs only while
a selection exists. **D2** is the fuller version: each `Text` is its own
selection, keeps exact characters (a truncated tail included) and follows
scrolling. It costs an environment read for every `Text`. Defer it until a
ported app needs it. D0 + D1 is about 6½ days.

**A43, wrapping.** Wrap through `SoftWrapLayout` (B62) by default, with a
TUI modifier that keeps the sideways scroll. The entry's per-frame cost
worry has a better answer than a per-line memo. The editor already splits
the whole document on every frame, three times (§2.5). A layout cache on the
editor's handler, keyed by the text's identity and the width, makes an idle
frame *cheaper* than today's. An edit frame pays a split and a re-wrap, the
same order as today. About 3½ days, including an `NSTextView` probe and the
tab-stop work `SoftWrapLayout` lacks.

**A42, rich text.** One editor, not two. The handler edits through a
storage enum (`String` or `AttributedString`), and edits become range
replacements, so attributes survive them. Rows are styled from `Text`'s own
run reading (`Text.runs(of:)`). Rich text changes nothing about layout, so
wrapping and rich text share one layout. Formatting is reached through the
editor's context menu, by Shift-F10 or a right-click. SwiftUI's own route,
`TextFormattingCommands`, waits on A28's menu bar. About 6½ days. B84's
fuller version (½ day) should come first: without it, SwiftUI's spelling of a
formatting definition does not compile in a macOS app.

**How they meet.** There is one selection model, which serves `Text`,
`TextField` and `TextEditor` (§5):

- offsets plus an affinity for the app-facing types (`TextSelection`,
  `AttributedTextSelection`);
- one *active selection* in the app, which Ctrl-C copies;
- shared pointer semantics (click, shift-click, drag, double-click word,
  triple-click paragraph);
- one set of selection colours;
- one clipboard writer.

The editor is a control: its drags are its own selection, and the screen
selection never starts inside it.

**Seven things the inputs got wrong** (§1). Terminal.app has no Option bypass:
its ⌥-click reaches the app. TUI's clipboard path has no OSC 52 and no
`wl-copy`, so over ssh a field's copy goes to the server today. ⌘C never
reaches the app, and Ctrl-Shift-C is the same byte as Ctrl-C. A25 is not
waiting on A13. The Stress shape A43 names is not a `TextEditor`. The parity
tool cannot see the attributed editor's initializer. B84 blocks SwiftUI's
spelling of formatting definitions on macOS.

---

## 1. Corrections: what the inputs say that the repo contradicts

1. **Terminal.app does not select with Option held while an app reports the
   mouse.** The compatibility doc byte-captured ⌥-click on Terminal.app 455.1
   (`Terminal compatibility survey.md:900-914`). It arrives as button code +8 (meta)
   on both press and release, whether or not "Use Option as Meta" is set.
   The press reaches the app, so Terminal.app did not take it for a
   selection. `MouseSupport.swift:54-58` says the same in its table:
   "Apple Terminal.app (Sequoia): **None** — no modifier bypasses the
   program's capture". The bypass by host, as recorded:
   - iTerm2: ⌥-drag. Its ⌥-click is swallowed (`:1044-1047`), which fits.
   - Ghostty and Warp: Shift-click selects text (observed 2026-09-02,
     `:2897-2903`).
   - kitty and xterm: Shift, by their documentation.

   *Hypothesis to measure:* Fn-drag selecting in Terminal.app while reporting
   is on is widely reported, and is recorded nowhere here. It needs a human
   at `mouse_probe.py` (a drag cannot be scripted from inside).
2. **The existing clipboard path is `pbcopy`, else `xclip`, else `xsel`.
   There is no OSC 52 and no `wl-copy`** (`SystemClipboard.swift:88-104`;
   `WebAssembly port.md:148`: "OSC 52 … is not wired up").
   - **A live consequence, independent of A13:** over ssh, a `TextField`'s
     Ctrl-C writes the *server's* pasteboard (a Mac host) or nothing (a
     headless Linux box).
   - OSC 52 is new work. It needs a capability table with the shape of
     OSC 8's (`TerminalHyperlinkSupport.swift:75-154`), because a write is
     never acknowledged.
3. **The copy key is Ctrl-C, not "⌘C where forwarded, else Ctrl-Shift-C".**
   - No terminal forwards ⌘ on a key event (`:3752`). The terminal takes
     ⌘C as its own Copy of its own (here empty) selection.
   - Ctrl-Shift-C is 0x03, the byte Ctrl-C sends. Shift is not encoded on a
     C0 control (`:3792-3800`, `:3887-3903`). It becomes distinct only
     under A4's kitty protocol.
   - The key that exists is the app's ⌘C resolved through `commandKey`,
     Ctrl-C by default. The text controls already copy on it while text is
     selected (`:3945`).
   - The practical consequence: a Mac user's ⌘C reflex copies nothing,
     which argues for copying on release (owner question 1).
4. **A25 (`searchSelection(_:)`) is not waiting on A13.** It needs a
   selection binding on the search field. `TextField(_:text:selection:prompt:axis:)`
   shipped with B65, so this is a few lines now, independent of selection
   drawing.
5. **The A/B that A43 names does not exist.** `app-shapes/code-editor` is
   2,000 `Text` rows in a `LazyVStack` (`Stress/Scenarios/AppShapeViews.swift:343-390`),
   not a `TextEditor`. The only `TextEditor` in Stress is the notes session's
   (`Stress/Sessions/NotesSession.swift:162`), over short notes. A large
   `TextEditor` variant must be added before the wrap can be priced.
6. **The parity tool cannot see the attributed editor.** `api_parity.py`
   keys by owner, name and labels, so `TextEditor.init(text:selection:)` is
   one key for the `String` and the `AttributedString` overloads. The `String`
   form already exists. The 26 A42 gaps in `baseline.json` therefore omit
   the initializer the whole feature is about. The compile corpus
   (`Tools/APIParity/CompileCorpus.swift`, where `:524` pins the `String`
   form) must pin it.
7. **B84 bites A42.** SwiftUI's own example of a formatting definition is
   `var body: some AttributedTextFormattingDefinition<AttributeScopes.SwiftUIAttributes>`.
   That names the scope in a type position, which B84 records as ambiguous
   in a macOS app, because AppKit loads SwiftUICore's scope beside TUI's.
   B84's fuller version (move the AppKit bridges into their own module,
   ½ day) fixes it.

---

## 2. The machinery today (file:line at `a61b9748`)

### 2.1 Mouse dispatch, and who claims a left press

- **Entry.** `App.swift:744` hands every report to
  `MouseEventDispatcher.dispatch(_:)` (`MouseEventDispatcher.swift:667`).
  Regions are matched innermost-first, which means last-registered first
  (`:895`).
- **Gestures first.** A press over an attached gesture goes to the arena
  (`routeThroughGestures`, `MouseEventDispatcher+Gestures.swift:94`). The
  arena ranks recognizers and ordinary controls as measured on macOS
  (`GestureArena.swift:33-60`, B89). A control gets the press once
  everything ranked ahead of it has failed.
- **Then capture.** A claimed press captures the button, and the drags and
  the release go to the same closure (`offer`, `:792`;
  `routeAgainstItsPress`, `:822`). **A drag with nothing captured is
  dropped** (`:855`), and an unpaired left release is dropped too. So an
  unclaimed press today leads nowhere. That is exactly the gap D1 fills.
- **Speculative claims exist.** `passClickThrough(from:event:)` (`:946`)
  replays a press and release to the region *behind* a handler that took
  the press only to see whether it became a drag (`.draggable`). D1's
  click-versus-drag disambiguation is the same move.
- **Who claims every left press, and why** (the weak claims D1 must see
  past):

  | Region | Where | Claims a press to… |
  |---|---|---|
  | `ScrollView` viewport, inserted at index 0 | `ScrollView.swift:921-928`, `:943` | focus the scroll view on release |
  | `NavigationSplitView` column, at index 0 | `NavigationSplitView.swift:335-348` | activate the column's section on release |
  | `List` container, at index 0 | `_ListCore.swift:2454`, `:3065` | select the row on release; start a reorder on drag |
  | `Table` container | `Table.swift:3141…3433`, `:3521` | the same |
  | `OutlineGroup` row | `_BehindContentTapModifier`, `OutlineGroup.swift:569` | tap the row |
  | a modal's dimmed backdrop | consumes | block the page |

  Everything else that claims (Buttons, fields, the editor, sliders, tab
  chips, `.draggable`, the arena's gestures) is a control proper.
- **Reporting.** The default `MouseSupport` is `.standard` (clicks, wheel,
  drag; `MouseSupport.swift:127`), so drags are reported. Modes are switched
  by `Terminal.applyMouseSupport(_:)` (`Terminal.swift:502`), from the union
  of the scene base, a per-frame override (`setConfigOverride`,
  `MouseEventDispatcher.swift:365`) and per-frame feature requests.
- **Region roles live in the dispatcher.** Gestures already keep a side
  table, `gestureRoles: [HandlerID: GestureRole]`, filed at registration and
  journaled for memo replay (`MouseEventDispatcher+Gestures.swift:32-60`).
  `HitTestRegion` is 88 bytes with no padding (four `Int`s, a `UInt64` id, a
  `String?`, four more `Int`s), so a role byte on the region would add a
  word to every region copied through every composite. A side table adds
  nothing.

### 2.2 Selection in the text inputs

- **The app-facing type.** `TextSelection` and `TextSelectionAffinity`
  (`Views/TextSelection.swift`) are SwiftUI's.
  `_TextSelectionChannel` (`:138-181`) is the offsets-only bridge both
  handlers use, so neither stores a `TextSelection`. A third initializer
  over `Binding<AttributedTextSelection>` is all A42 needs from it.
- **The field.** It keeps `cursorPosition` and `selectionAnchor` as
  character offsets. The **editor** keeps line and column positions
  (`TextEditorHandler.swift:23-41`) and converts to offsets at the exchange
  (`TextSelection+Handlers.swift:42-92`).
- **The pointer.** Click, shift-click and drag are wired separately in each
  (`TextFieldMouseHandler.swift:105-160`, `TextEditor.swift:763-830`).
  **Neither handles a double- or triple-click.** `clickCount` is stamped by
  the dispatcher (`:1148`, a 400 ms window) and read only by `List`,
  `Table` and `ScrollView`.
- **Painting.** Selection is drawn in-band by each control, only while it is
  focused (`TextEditor.swift:470`). The colours come from the inputs'
  shared `caretSetup` and selection styling, with the SGR 7 fallback the
  compatibility doc specifies where the palette leaves colours to the
  terminal (`Terminal compatibility survey.md:2587`).

### 2.3 The clipboard

- **The path.** `ClipboardAccess` (`TextFieldHandler+Clipboard.swift:119-153`)
  is two closures, injectable through `\.clipboardAccess` for tests.
  `.system` calls `SystemClipboard` (`App/SystemClipboard.swift`), whose
  bounded, non-blocking child I/O is worth keeping.
- **The keys.** The stand-ins are Ctrl-C, Ctrl-X and Ctrl-Z in the editor,
  plus Ctrl-V and Ctrl-U in a field (`TextEditorHandler+Clipboard.swift:18-27`).
  Copy and cut decline with nothing selected, so the key goes on to the
  app's ⌘C or to `QuitShortcut.ctrlC`.
- **Typed values.** `TypedClipboard` (B9) keeps the values behind the
  text this app last copied. That is the natural carrier for a rich editor's
  attributes on an in-app copy and paste.

### 2.4 Text layout: two wrappers, on purpose

- **`TextWrapping`** (`Rendering/TextWrapping.swift`) wraps for *display*.
  It drops the space a line breaks at, truncates or folds into an ellipsis,
  and returns lines and widths but **no source offsets**. `Text` calls it at
  `Text.swift:913`.
- **`SoftWrapLayout`** (`Rendering/SoftWrapLayout.swift`) wraps for
  *editing*. Every character sits on exactly one row, and runs of spaces
  hang. The last cell is a margin for the caret. It maps offset ↔ (row,
  column) with an affinity. Its widths come from a per-character closure
  (`:82-94`), so **a tab's width cannot depend on its column**. The editor
  needs that (`TabLayout.advance`, `Views/TabWidth.swift:75`). The vertical
  field draws a tab as one space and is unaffected.
- **They should stay two.** A display wrap must not hold characters it
  hides, and an editing wrap must not lose any. What they share is
  `String.terminalWidth` and the CJK break rule.

### 2.5 The editor's per-frame text work

On every render, `_TextEditorCore` splits the whole bound string into
`[[Character]]` twice: in `sizeThatFits` (`TextEditor.swift:270`) and in
`renderToBuffer` (`:309`, through `lines(of:)` at `:509`). The handler
splits it again for each key (`readLines()`, `TextEditorHandler.swift:95-100`)
and for each pointer event (`TextEditor.swift:793-794`). Every edit rewrites
the whole string (`writeLines`, `:102-113`). Undo keeps whole-`String`
snapshots (`TextUndoHistory.swift:28`). The A43 entry's "roughly doubling"
is measured against this baseline. Caching the split removes most of it.

### 2.6 Attributed text (P8, lane 17t)

- **Reading.** `Text(AttributedString)` (`Views/Text+Attributed.swift:59-67`)
  reads runs into `TextStyle`s through `Text.runs(of:)` and
  `Text.style(of:)` (`:70-115`). It honours foreground, background, font,
  single underline and strikethrough, Foundation's
  `inlinePresentationIntent` on Darwin, and links.
- **The scope.** TUI declares its own `AttributeScopes.SwiftUIAttributes`
  (`Views/AttributeScopes+SwiftUI.swift:46`). `Font.Resolved` and
  `\.fontResolutionContext` exist (`Styling/Font+Resolved.swift`), as do
  `Font.bold(_:)` and `Font.italic(_:)`. So SwiftUI's documented bold-toggle
  example compiles once the editor and `AttributedTextSelection` exist.

### 2.7 The keyboard chain, where a copy would sit

`InputHandler.swift:9-60` documents the order:

1. the focus path;
2. layer 0, a focused text input;
3. layer 0.5, a drag in flight;
4. layers 1–3: the status bar, view handlers and the focus system;
5. layer 3.5, the app's shortcuts;
6. layer 4, the defaults.

A screen selection's copy and Escape belong just after layer 0. Copy mode,
like the drag layer, belongs ahead of everything while it is on.

---

## 3. The owner's question: is there a trick?

| Trick | Verdict | Why |
|---|---|---|
| Turn reporting off at the press, over plain text | **No** | The terminal classified the gesture when the press arrived, and it reported the press, so it is not selecting. Turning reporting off mid-drag leaves a drag nobody owns. (Cheap to confirm per host with `mouse_probe.py`. It is not worth building on even if one host differs.) |
| Turn reporting off while the pointer hovers plain text | **No** | With reporting off there are no motion reports, so the app never learns the pointer left the text. It cannot be undone. |
| Turn reporting off whenever no control is on screen | **Rarely applies** | Every scroll view registers a region for the wheel, so almost no screen qualifies. Modes would also flip under the user. |
| Scope reporting to regions | **Impossible** | Modes 1000, 1002, 1003 and 1006 are whole-screen. No terminal offers a region form. (xterm's 1001 highlight tracking is xterm-only.) |
| **Hand the mouse to the terminal on a key (D0)** | **Yes, as a fallback** | One key turns reporting off and turns on alternate-scroll mode (DECSET 1007), so the wheel still scrolls as arrow keys. The terminal's own selection and ⌘C then work, over ssh too, in any terminal, because the terminal copies on the user's machine. Escape or the same key gives the mouse back. It is an in-app version of Terminal.app's View ▸ Allow Mouse Reporting (⌘R), but it works the same in every host. |
| **TUI selects and copies by itself (D1)** | **Yes** | No toggling at all. The cost is a clipboard route to the user's machine: OSC 52 where the host honours it, the local helper when the session is local. |
| Tell users the host's bypass modifier | Document it | iTerm2 ⌥, Ghostty and Warp Shift, kitty and xterm Shift. Terminal.app: none measured, Fn to be measured. The Mouse page and the DocC article should name it per host, as the OSC 8 section does. |

So the honest answer is that no clever toggle exists. The trick is not to
need the terminal's selection: TUI selects, and writes the clipboard
itself.

---

## 4. A13: three designs

### D0 — hand the mouse to the terminal

- **Entering it.** A key, or `m` inside copy mode (§4.2). The dispatcher
  holds a hand-off flag, so `effectiveSupport` answers `.disabled` (beside
  `configOverride`, `MouseEventDispatcher.swift:356-367`).
  `Terminal.applyMouseSupport` then writes `?1003l ?1002l ?1000l ?1006l`
  and `?1007h`.
- **While it is on.** A status-bar item reads "Mouse: terminal — Esc takes
  it back". Escape or the key restores reporting and writes `?1007l`.
- **Cost.** About ½ day. Nothing per frame.
- **Hypotheses to measure.** Do Terminal.app, iTerm2, Ghostty, Warp and
  tmux honour 1007, and does the wheel then arrive as arrows? Terminal.app
  has "Scroll alternate screen" on by default as far as is known. It is
  unmeasured here.
- **What it does not do.** It is not `.textSelection`: it selects anything,
  blocks nothing, and is the terminal's.

### D1 — TUI's own selection, of what is on the screen (recommended)

#### 4.1 The ranking: what a left press and drag does

Every region that claims presses to act on a *click* files a **press role**
in a dispatcher side table at registration, journaled like the gestures'.
That is `ScrollView`, `NavigationSplitView` columns, `List`, `Table` and
`OutlineGroup` rows:

- `background`: `ScrollView` viewport, split-view column;
- `rows`: `List`, `Table`, `OutlineGroup`.

A region with no role is a control. `.textSelection(_:)` files a **scope
region** over its content: one region per application, with a reserved
handler id, journaled. Every handler skips scope regions; the selection
reads them.

On a left press with no gesture under it, the dispatcher walks the matching
regions innermost-first, as today. Hover observers are skipped, and a
control that declines is passed over. **The tier** is the innermost scope at
the point: `.enabled`, `.disabled`, or none, meaning the TUI default.

| Innermost claimer under the press | Default (no scope) | Inside `.enabled` | Inside `.disabled` |
|---|---|---|---|
| none (page background; a plain `Text` outside any scroll view) | **drag selects**, clipped to the content area; a click does nothing (as today) | drag selects, clipped to the scope | as today |
| `background` (scroll view, split column) | **drag selects**, clipped to that region; a click goes to it at the release (focus, as today) | drag selects, clipped to scope ∩ region; a click as today | as today |
| `rows` (List, Table, OutlineGroup row) | as today: a click selects the row, a drag reorders or drags out | a click goes to the row at the release; **a drag selects text, and a double-click selects a word** (owner question 4); reordering by pointer starts only from cells outside the scope | as today |
| a control: Button, Toggle, field, editor, slider, tab chip, `.draggable`, `.contextMenu`'s right button | as today | as today. A Button's label never selects, as SwiftUI documents ("Button views don't support text selection"); no special case is needed, because the Button is the innermost claimer | as today |
| any attached gesture (the arena) | as today; the gestures own the press | as today (v1). In the fuller version the selection joins the arena ranked last, starting when every gesture has failed (a tap fails past its slop, B90) | as today |
| a modal's backdrop, an open menu | as today | — | — |

**Mechanics.**

- **Pending press.** When the walk reaches a yielding claimer (or none) in a
  tier that allows selection, the dispatcher captures the button for a
  `PendingSelection` instead of offering the press.
  - The first `.dragged` at least one cell away (B90's distance) starts the
    selection.
  - A release with no motion replays press then release to the claimer
    through the `passClickThrough` path, with the stamped `clickCount`.
  - The claimers in the table act on the release, so nothing is visibly
    late. `List` arms a reorder on the *press*, but only where rows are
    `rows`-yielding, which means `.enabled`. That is owner question 4.
  - A press with `clickCount == 2` selects the word under it at once, and
    `3` selects the row inside the clip. Words come from
    `WordBoundary.isWordCharacter` over the row's characters
    (`Focus/WordBoundary.swift:25`).
- **Shape.** A stream selection, the way a terminal makes one: from the
  anchor cell to the head cell in reading order, with full clip-width rows
  between them. A meta-drag (⌥ in Terminal.app, ⌘ in iTerm2, which deliver
  the same +8 bit) selects a rectangle, as both terminals' own block
  selection does.
- **Reading the cells.** The selection reads characters, not views, from
  the last composited content buffer. The run loop keeps a reference to its
  lines: copy-on-write, so nothing is copied. The cell walker is Stress's
  `ScreenCells` (`Stress/Sessions/ScreenCells.swift`) promoted into TUI:
  it already takes a drawn frame apart into cells, SGR, OSC 8 and
  reverse video included.
  - Trailing blanks on each row are dropped.
  - A wide character is read once.
  - Rows are joined with `\n`.
- **Snapshot.** The text is read at every drag step and fixed at the
  release. That snapshot is what is copied, so a tailing log that moves
  under the highlight still copies what the user selected.
- **Highlight.** The selection colour (S) of the text inputs, from the
  same palette call, with the SGR 7 fallback (`:2587`).
  - **When it is painted:** in `RenderLoop.render` after `renderContent`
    and before `compositeOverlays` (`RenderLoop.swift:583`). Menus and
    popovers then draw over it rather than inside it.
  - **Opacity:** claims are clipped out of the painted cells
    (`OpacityRegion.clipped`), so `resolvingOpacity` (`:1069`) cannot blend
    the selection colours.
  - **Animated runs:** a run crossing the selection is restyled by the
    `restyleRuns` precedent (`ColorEffectModifiers.swift:268`), so a
    spinner inside a selection keeps animating in selection colours.
  - **Cost:** O(selected cells), and only while a selection exists.
  - **When it goes away:** the highlight is dropped, and the snapshot kept,
    when the cells under it no longer read the snapshot. That check is a
    re-read of the selected cells, done only while a selection exists.
    Any click, Escape (consumed only while a selection exists) and a
    resize clear both.
- **Copy.** On release (owner question 1); by Ctrl-C, meaning the app's ⌘C
  resolved through `commandKey`, at a new stage right after layer 0; and
  from a one-item context menu when the right button is pressed *inside*
  the selection. Outside it, the app's `.contextMenu` is untouched. A brief
  notification says "Copied 42 characters", or why it could not. The
  clipboard is §4.4's.

**Cost per frame for an app that selects nothing:**

- a nil check in `RenderLoop.render`;
- a dictionary write per `ScrollView`, `List` and `Table` registration,
  for its role (journaled with the registration that already exists);
- **no work per `Text`.**

`.textSelection` costs an environment write and a region where it is
applied. The dispatcher's walk changes only on left presses.

#### 4.2 The keyboard route: copy mode

The no-mouse-only rule needs a keyboard way to do everything a drag does.
Making selectable `Text`s focusable would put every row of SwiftUI's own
example (`.textSelection(.enabled)` on a `List`) into the Tab order, so the
route is a mode, as in tmux:

- A key enters it (owner question 3; F7 is caret browsing's key in
  browsers). So does a status-bar item.
- A block caret appears at the focused control's top-left cell, or the
  content's.
- Arrows move a cell. Up and Down move a row, and plain arrows are safe:
  Terminal.app strips modifiers only from Up and Down
  (`Terminal compatibility survey.md:885-888`). Option-←/→ move a word, and
  Home/End go to the row's ends.
- Space or `v` drops or lifts the anchor. Shift-←/→ extend.
- Return or Ctrl-C copies and leaves. `m` hands the mouse to the terminal
  (D0). Escape leaves.
- It is an input layer ahead of the others while on, like layer 0.5. Its
  hints are status-bar items. Cells inside a `.disabled` scope are skipped
  by the caret and never copied.
- About a day.

#### 4.3 What `.textSelection` means under D1

- **`.enabled`** means a drag selects here, even over list and table rows.
  On a single `Text` the scope is that `Text`'s rectangle, so the selection
  stays inside it, as SwiftUI's does. On a container it may cross from one
  row's text into the next, which SwiftUI's per-`Text` selection does not.
  That is D1's one visible deviation; D2 removes it.
- **`.disabled`** means TUI selects nothing here: no drag and no copy
  mode. The terminal's own modifier-drag still works. That is the
  terminal's, and documented as such.
- **No modifier** means the TUI default. `.textSelection(.disabled)` at
  the root turns it off for a whole app.
- **Types.** `TextSelectability` (protocol, with `allowsSelection`),
  `EnabledTextSelectability`, `DisabledTextSelectability` and their statics
  ship as SwiftUI declares them. That closes A13's 9 gaps. The environment
  holds a `Bool?`, which is `Equatable`, so the write does not defeat the
  memos (the "uncomparable environment writes" class).

#### 4.4 The clipboard writer (needed by D1, D2 and A42, and by today's fields over ssh)

- **OSC 52.**
  - **Format:** `ESC ] 52 ; c ; <base64> ESC \`.
  - **Delivery:** queued like the image store's pending graphics
    (`RenderLoop.swift:1091`) and written at the next frame. It is
    reached through the render context's services, not a static.
  - **When:** the host is in a measured table
    (`TerminalClient.honoursClipboardWrites(_:)`), with
    `clipboardWriteSupport: Bool?` and `TUIKIT_OSC52` as overrides — the
    hyperlink ladder, line for line.
  - **tmux:** see below.
- **The local helper when the session looks local.** No `SSH_CONNECTION`,
  `SSH_CLIENT` or `SSH_TTY`, the variables the pasteboard document
  validated (`Find pasteboard…md:100-113`). On macOS that is `pbcopy`. On
  Linux it is `wl-copy` when `WAYLAND_DISPLAY` is set, then `xclip` and
  `xsel`.
- **Both, when both apply.** The tmux-reattached-from-afar hole (`:115-128`)
  makes "local" unreliable. Two writes of the same text to one pasteboard
  are harmless.
- **Neither** means the notification says so and names the hand-off key.
- **Hypotheses to measure** with a new `Tools/TerminalProbes/clipboard_probe.py`.
  It writes a nonce by OSC 52 and, on a local host, reads it back with
  `pbpaste` (self-verifying: no human needed). It also checks the payload
  ceiling.
  - iTerm2 writes only with its "Applications in terminal may access
    clipboard" setting, and that setting is off by default.
  - Ghostty allows writes by default.
  - Apple Terminal has no OSC 52.
  - Warp is unknown.
  - tmux drops an app's OSC 52 under its default `set-clipboard external`.
    Passthrough (`allow-passthrough`) is off by default from 3.3.
- **Cost.** About a day with the probe and the compatibility doc's new
  section.

### D2 — each `Text` its own selection (the fuller version)

A `Text` under `.enabled` registers a recognizer in the arena
(`registerGesture`, journaled), ranked as its own gesture. It succeeds on
motion and fails on a release without it, so a `List` behind it still gets
its click. That needs no `rows` role.

- **Offsets.** The selection is offsets into the `Text`'s *display string*:
  case applied, before wrapping. Redacted and `privacySensitive` text is
  never selectable.
- **Map.** The map from cells to offsets is computed at the gesture, not
  per frame, from the display string and the `TextWrapping` lines it
  captured. Spaces dropped at a break are re-found. **The ellipsis cell
  maps to everything it hides**, so copying a truncated error message
  copies all of it.
- **State.** In `StateStorage` at the `Text`'s identity, under a new
  **negative** range (`-130…`, the next free ten in the table at `StateStorage.swift:58-72`):
  a composite whose body is that `Text` renders it at the composite's own
  identity, and slot `0` would alias its first `@State`. A selection write
  invalidates that path only.
- **Painting.** Done by the `Text` itself in its concatenation walk, so
  the selection scrolls, clips and layers with the text.
- **Labels.** `Button`, `Toggle`, `Link`, `Menu`, `Picker`,
  `DisclosureGroup` and tab items set `.disabled` for their labels, so
  their `Text`s file nothing.
- **Cost.** One more environment read in every `Text` render; the
  dictionary lookup is `EnvironmentKey.swift:58-88`. Plus a filing and a
  closure per selectable `Text` per render (not per memo hit). On
  `textwall` the read may approach 1%. If it does, fold selectability into
  the redaction read `Text` already makes (`Text.swift:912`).
- **About three days** on top of D1. D1's screen tier stays as the
  default; D2 only refines `.enabled`.

### Side by side

| | D0 hand-off | D1 screen selection | D2 per-`Text` |
|---|---|---|---|
| Needs disabling reporting? | the app does it on a key | never | never |
| `.textSelection` means what it says | no | yes (crosses rows on a container) | yes, exactly |
| Copies a truncated tail | no | no (copies the `…`) | yes |
| Selection follows scrolling | terminal-dependent | no (snapshot kept) | yes |
| Works over ssh in Terminal.app | **yes** | only if a route exists (it does not: no OSC 52) | same as D1 |
| Per-frame cost, app selects nothing | 0 | ~0 | an env read per `Text` |
| Days | ½ | 4½ with copy mode, clipboard and probes | +3 |

**Recommendation: D1 with D0, D2 deferred.** D1 is the owner's option 1 with
the TUI default, and it covers what was asked: no toggling, a keyboard
route, a copy, and `.textSelection` honoured. D0 is the only route that
reaches a Terminal.app user over ssh. D2 buys fidelity a terminal app rarely
needs, at a cost every `Text` pays.

---

## 5. One selection model for `Text`, `TextField`, `TextEditor`

What is shared, and where it lives:

1. **The app-facing values.** `TextSelection` (String) and
   `AttributedTextSelection` (A42) are both carried by `_TextSelectionChannel`
   offsets plus the `\.textSelectionAffinity` the control reports.
2. **One active selection per app.** A `TextSelectionCoordinator` on
   `TUIContext` (no singleton; reached the way `mouseEventDispatcher` is)
   holds the active owner: a focused field, a focused editor, the screen
   selection, or (D2) a `Text`.
   - **Who becomes active:** a new screen selection becomes active. Any key
     a focused text control handles makes it active again.
   - **Layer 0's copy:** a field's or editor's Ctrl-C copies only while it
     is the active owner, else it declines. So a field focused before a
     screen drag does not copy its own stale selection.
   - **Ctrl-C's precedence** is pinned through the input chain, like
     `TextInputShortcutPrecedenceTests`:
     1. the active text control's selection;
     2. the screen or `Text` selection;
     3. the app's ⌘C;
     4. `QuitShortcut.ctrlC`.
3. **Pointer semantics, one helper.** A `TextPointerSelection` gives every
   selectable surface click, shift-click and drag, and adds what neither
   input has:
   - double-click for a word (`WordBoundary`);
   - triple-click for the paragraph (the field's text, the editor's line,
     D1's row).

   `TextFieldMouseHandler` and `TextEditor.registerMouse` move onto it.
4. **One look.** The inputs' selection colour (S) everywhere, including the
   screen tier's post-pass. The owner's colour rules have one static
   selection background.
5. **One clipboard writer.** Fields, editors, the screen tier and the rich
   editor all write through §4.4. Only the rich editor also fills
   `TypedClipboard` with its `AttributedString`.

The editor is a control in D1's table. Its drags are always its own
selection, so the two never compete.

---

## 6. A43: wrapping the editor

### 6.1 Design W (the only serious one)

- **The cache.** The handler keeps an `EditorLayout`: the split lines, one
  `SoftWrapLayout` per line, and the rows' prefix sums.
  - **Key:** the bound `String`, the content width and the `TabWidth`.
  - **Identical text:** an unchanged binding hands back the same storage,
    and `String ==` answers that from its raw bits, so an untouched
    document costs one comparison per frame and no split.
  - **Who uses it:** `sizeThatFits`, `renderToBuffer`, `readLines()` and the
    mouse mapping all read it.
  - **Order:** step 1 lands this as a pure refactor, before wrapping
    exists, so its own A/B is clean.
- **The model.** The caret stays a line and a column. Each line is a
  paragraph, and its rows come from its own layout, so `(line, column)` maps
  to a row by `row(of:affinity:)`.
- **Scroll.** It is kept as *(line, row within line)* rather than a flat
  row, so a resize keeps the top paragraph in place. Horizontal scroll goes
  in wrap mode.
- **Motion.** All of it is checked against an `NSTextView` probe first,
  using `Tools/SwiftUIProbes/Vertical TextField keys, caret and size (wave 6b)/nav.swift`'s harness on a `TextEditor`:
  - Up, Down, Ctrl-P and Ctrl-N move by row, keeping a desired cell x
    through short rows.
  - Page Up and Down move a screen of rows.
  - Ctrl-A and Ctrl-E keep the line (the paragraph), as in the field.
  - Home and End stay the document's ends (the existing deviation).
  - A click past a row's end lands on the row's last caret offset under the
    affinity (`lastCaretOffset(inRow:affinity:)`).
- **Tabs.**
  - **The gap:** a second `SoftWrapLayout` initializer takes an
    `advance: (Character, Int) -> Int` (the column inside the row). Widths
    are then computed during the break walk, and a tab is a break
    opportunity like a space.
  - **Where stops are measured:** from the row's start, which is believed to
    be where `NSTextView` measures them (tab stops sit on the container's
    left edge). The probe confirms it.
  - **The field** keeps its one-space closure.
- **The scroll bar.**
  - **Width:** lay out at the full width, and if the rows overflow, lay out
    again one cell narrower. That is `ScrollView`'s rule, and both layouts
    are cached.
  - **Reflow:** the text reflows once as a document crosses the height,
    as legacy macOS scrollers make it do.
  - **Extent:** the extent and offset count rows.
- **Selection painting.** `selectedColumns(inLine:)` becomes per-row
  ranges.
- **Find.** The find bar's match (B81) is revealed by row.
- **Keeping the sideways scroll.**
  - **The modifier:** a TUI modifier, named by owner question 6,
    restores today's behaviour exactly.
  - **The tests:** the 35 `TextEditorTests` and 10 `TextEditorCellWidthTests`
    run under it unchanged, and become the no-wrap mode's tests instead of
    being rewritten.
  - **The goldens:** at the default flip, the Example's `TextInputPage`
    goldens are re-recorded.

### 6.2 Cost

| | |
|---|---|
| Days | probe ½, layout cache ½, tab advance ½, wrap mode 1½, default flip with docs, Example and goldens ½: **3½** |
| Apps without an editor | 0 |
| Editor, idle frame | **less than today**: one string comparison instead of two whole-document splits |
| Editor, edit frame | one split plus a wrap of every line, O(document), about today's cost. If the A/B wants it, refine by reusing the layouts of the unchanged lines before and after the edit |
| Risks | the bar-induced reflow; affinity at a wrap is still not tracked per caret (B62's fuller version); `String ==` falls to O(n) when a binding builds a fresh but equal string every read |

**Recommendation: W, after the batch, as the owner decided.**

---

## 7. A42: rich-text editing

### 7.1 Design R1: one editor, a storage enum (recommended)

- **Storage.** `_TextEditorCore` holds
  `enum EditorText { case plain(Binding<String>), attributed(Binding<AttributedString>, selection: Binding<AttributedTextSelection>?) }`.
  It is an enum, not a protocol existential, so the `String` path pays one
  switch and stays specialised.
- **Edits.** Every edit in `TextEditorHandler` becomes
  `replace(offsets:with:)`: insert, delete, newline, kill, yank, transpose,
  cut, paste and undo. On attributed storage that maps offsets to
  `AttributedString.Index`, inserts with the **typing attributes**, and
  deletes the range, so attributes survive. Step 1 is the pure refactor on
  `String`.
- **Undo.** `TextUndoHistory` becomes generic over its snapshot. Attributed
  snapshots restore attributes.
- **Typing attributes.** The selection's own, when the app gave some through
  `init(insertionPoint:typingAttributes:)`. Otherwise the macOS rule as the
  probe measures it: the attributes of the character before the caret, or
  after it at a paragraph's start. Constrained by the formatting definition.
- **Drawing.**
  - **Style source:** a per-character style index built from `Text.runs(of:)`
    and `Text.style(of:)`, cached with §6's layout, so P8's reading is
    reused and not repeated.
  - **Emission:** `styledRow` emits bold, italic, underline and
    strikethrough as well as colours.
  - **Selection and caret:** the selection overrides colours and keeps the
    rest; the caret flips as today.
  - **Links:** a link draws as a link, without OSC 8. Inside an editable
    field the terminal would take ⌘-click on it.
- **Formatting UI.**
  - **The menu:** the editor's context menu, by right-click, Ctrl-click or
    Shift-F10 (`ContextMenuModifier.swift:340-346`). It offers Cut, Copy,
    Bold, Italic, Underline and Strikethrough, and acts like
    `transformAttributes(in:)`: on the selected runs, or on the typing
    attributes at an insertion point.
  - **Filtering:** items the definition's scope or constraints exclude are
    not offered.
  - **Visibility:** `textInputFormattingControlVisibility(_:for: .contextMenu)`
    hides them. That reopens a refusal (`parity-map.json:385-387`, `:898`):
    the menu is now a TUI-drawn formatting control, so `.contextMenu` has
    a meaning. The other placements stay inert, which is O8's call.
- **Copy and paste.**
  - **Out:** plain text to the system clipboard, and the `AttributedString`
    to `TypedClipboard`.
  - **In:** a paste whose text matches the typed entry keeps its
    attributes. Any other paste takes the typing attributes.
- **Formatting definitions.**
  - **The types:** `AttributedTextFormattingDefinition` and
    `AttributedTextValueConstraint`; `AttributedTextFormatting`'s
    `ValueConstraint`, `AnyDefinition`, `EmptyDefinition`,
    `TupleDefinition` (a parameter pack), `DefinitionBuilder` and
    `AttributeContainerProxy`; and the three
    `.attributedTextFormattingDefinition(_:)` overloads into the
    environment. All of this is logic, not drawing.
  - **Where `constrain` runs:** on every edit the editor makes, and on the
    visible rows at display. SwiftUI documents that a binding may still hold
    unconstrained text off screen.
  - **Build risk:** the builder is a parameter pack in a result builder.
    Run the Linux cross-compile (it catches type-check timeouts macOS
    misses) and guard the release build (the closure-specialisation
    blow-up).
- **Declined.** `AttributedTextFormatting.Transferable` and
  `AttributedString.init(transferable:in:)`: RTF import and export through
  `UTType`, Darwin-only. A18 governs Apple-only API, and nothing else in
  TUI reads RTF.

**R2, a separate attributed editor core,** would duplicate 1,600 lines
(`TextEditor.swift` plus `TextEditorHandler.swift`). Rejected under the
reuse rule.

### 7.2 The API, gap by gap (26 in the baseline, plus the family the map holds back)

| Symbol | Ships as |
|---|---|
| `TextEditor.init(text: Binding<AttributedString>, selection: Binding<AttributedTextSelection>? = nil)` | R1; pinned by the compile corpus (§1.6) |
| `AttributedTextSelection` (`init()`, `init(insertionPoint:typingAttributes:)`, `init(range:)`, `init(ranges:)`, `indices(in:)`, `affinity(in:)`, `typingAttributes(in:)`, `attributes(in:)`, `Indices`, `Attributes` and its `subscript`) | a value type; `indices(in:)` falls back to a valid index for a string it no longer fits, as documented |
| `AttributedString.replaceSelection(_:with:)`, `(_:withCharacters:)`, `transform(updating:body:)`, `transformAttributes(in:body:)`, `subscript(selection:)` | extensions; index tracking per §7.3 |
| `AttributedTextValueConstraint`, `AttributedTextFormatting.*` (not `Transferable`), `View.attributedTextFormattingDefinition(_:)` | §7.1 |
| `AttributedTextFormatting.Transferable`, `AttributedString.init(transferable:in:)` | declined (map entry) |

### 7.3 Availability risks (step 0 checks; none measured)

- **Index tracking.** `transform(updating:)` must move a selection through
  an arbitrary body. Foundation added AttributedString index tracking with
  the 2025 OSes. Whether swift-foundation in the **6.2** toolchain has it on
  Linux, and the macOS 15 SDK at all, is unknown.
  - **Fallback:** keep the selection as character offsets and derive the
    new ones by the common prefix and suffix of the characters before and
    after the body. That is exact for one contiguous edit.
- **`DiscontiguousAttributedSubstring`** (the result of
  `subscript(selection:)`) is the same question. If it is missing on a
  supported toolchain, that subscript alone goes behind `#if compiler`.
  The owner allows that for parity, provided nothing *requires* a newer
  toolchain than 6.2.
- **`RangeSet`** needs macOS 15, as `TextSelection` already does
  (`TextSelection.swift:45`).

### 7.4 Cost

| | |
|---|---|
| Days | availability check ½ (plus B84 ½); storage refactor 1; selection type and extensions 1; attributed editor 1½; context menu and `TypedClipboard` 1; formatting definitions 1½: **about 6½** |
| `String` editors | one enum switch per operation; the A/B must show nothing |
| Rich editors | per-character style index on change; `AttributedString ==` may be O(n) per frame where `String`'s is O(1). That is unknown, and the `text-editor-rich` variant must price it |

**Recommendation: R1, after A43, on its cache.**

---

## 8. How the three meet

| Concern | A13 (D1) | A43 | A42 |
|---|---|---|---|
| Layout | reads composited cells; none of its own | `SoftWrapLayout` per line, cached | the same layout; styles do not affect cells |
| Selection | the coordinator's screen selection | the editor's own, painted per row | `AttributedTextSelection` over the same offsets |
| Clipboard | §4.4 | — | §4.4 plus `TypedClipboard` |
| Dispatcher | pending press; roles; scopes | the editor is a control | the same, plus a context menu |
| Memo | outside the tree (post-pass); roles and scopes journaled | the cache is handler state, not a memo | the style index rides the cache |
| Keyboard | copy mode; Ctrl-C after layer 0 | row motion | the formatting menu by Shift-F10 |
| A drag over a `List` row | default: the row's; `.enabled`: text | — | — |
| A drag over a `Button` | the Button's, always | — | — |

---

## 9. Decided here unless vetoed (minor, per "decide minor questions myself")

1. **D1's clip.** The innermost `background` region under the press, else
   the content area. The header and the status bar are never selected.
2. **Shape.** A stream selection. A meta-drag selects a rectangle. Reading
   drops trailing blanks per row, reads a wide character once, and joins
   rows with `\n`.
3. **Clearing.** A click anywhere, Escape (only while a selection exists),
   or a resize clears it. A changed cell drops the highlight and keeps the
   snapshot.
4. **No selection under a modal** backdrop or in an open menu. A
   presentation clears the selection.
5. **Clipboard.** OSC 52 when honoured *and* the helper when local, both
   when both apply. A notification reports the copy or its failure.
   Field copies stay silent unless they fail.
6. **Drag reporting.** An app that turns drag reporting off gets no drag
   selection. Copy mode still works.
7. **Editor scroll** is anchored by (line, row within line). The scroll bar
   reflows by `ScrollView`'s rule.
8. **The rich editor's menu** is Cut, Copy and the four styles. There is no
   colour item: an app adds colours through the selection binding, as
   SwiftUI's examples do.
9. **Declines:** `AttributedTextFormatting.Transferable` and
   `AttributedString.init(transferable:in:)`.
10. **Roles in a side table**, not a byte on `HitTestRegion` (88 bytes, no
    padding).

---

## 10. Questions only the owner can answer

1. **(A13)** When a drag ends, copy it at once, or only on Ctrl-C or the
   menu? Copying at once is tmux's and iTerm2's default, and the only thing
   a ⌘C reflex finds. Waiting is macOS's way, and an accidental drag then
   leaves the clipboard alone. *Recommend: copy at once.*
2. **(A13)** Ship D0, a key that hands the mouse to the terminal (its own
   selection and ⌘C, the wheel kept), as the fallback where no clipboard
   route reaches the user? Terminal.app over ssh is that case. *Recommend:
   yes, reached as `m` inside copy mode.*
3. **(A13)** Which key enters copy mode? *Recommend F7, caret browsing's key,
   plus a status-bar item. On a Mac keyboard F7 may need fn.*
4. **(A13)** With `.textSelection(.enabled)` on a `List` or `Table`, does a
   drag or a double-click that starts on row text select text (AppKit's
   rule; reorder and activation then start from blank cells or the
   keyboard), or keep the row's meaning? *Recommend: select text.*
5. **(A13)** D2, one exact selection per `Text`, now or when a ported app
   needs it? It copies a truncated tail, follows scrolling and never crosses
   rows. *Recommend: when needed.*
6. **(A43)** What should the modifier that keeps the sideways scroll be
   called? *Recommend `.textEditorWrapsLines(false)`* (alternatives:
   `.textEditorSoftWrap(false)`, `.textEditorLineWrapping(.disabled)`).
7. **(A42)** Do B84's fuller version first (the AppKit bridges into their
   own module, ½ day), so that SwiftUI's
   `some AttributedTextFormattingDefinition<AttributeScopes.SwiftUIAttributes>`
   compiles in a macOS app? *Recommend: yes.*
8. **(A42)** Formatting from the keyboard: through the context menu
   (Shift-F10) only, or chords as well? Under `.control`, ⌘I cannot arrive
   (Ctrl-I is Tab), and ⌘B and ⌘U meet Ctrl-B (back a character) and
   Ctrl-U. *Recommend: menu only; chords arrive with A28's
   `TextFormattingCommands`.* **Ruled 2026-10-23: the recommendation** —
   menu now, chords through `TextFormattingCommands` (decisions A42).
9. **(all)** Landing order: the clipboard writer, A13 (D1 + D0), A43, then
   A42? *Recommend: yes. The clipboard step also fixes a live bug (§1.2).*

---

## 11. Staged plan: one commit per step, docs in the same commit

Gates for every step: the 6.2.4 build and the suite. Stress `--selfcheck` for
drawing steps. The Linux cross-compile for the formatting builder. A/Bs on a
quiet box only (`ab_bench.py`), run by the owner, not by agents. New strings
in all seven Example languages.

### Clipboard

**C0. Measure.** No code. Commit `clipboard_probe.py`, and record
Terminal compatibility survey.md sections on:

- OSC 52 writes per host (and tmux under `set-clipboard on`, `external` and
  passthrough);
- the payload ceiling;
- DECSET 1007 per host;
- the native-selection bypass per host, Terminal.app's Fn included, from a
  human at `mouse_probe.py`.

Fix `MouseSupport.swift:54-58`'s table to match. Also run the `NSTextView`
and selectable-`Text` probes (the `Tools/SwiftUIProbes/Vertical TextField keys, caret and size (wave 6b)/` harness) for A43's motions and
for SwiftUI's selectable-`Text` answers to §4.1's rows.

**C1. The clipboard writer.** Add `TerminalClient.honoursClipboardWrites`,
`clipboardWriteSupport`, `TUIKIT_OSC52`; the OSC 52 queue drained in
`writeFrame`; the local and remote ladder; `wl-copy`.

- **Tests:** a `ClipboardRouteTests` table (override, environment, host ×
  local, remote; encoding; ST terminator; tmux wrapping if C0 says so) and
  `SystemClipboardTests` for `wl-copy` selection.
- **Docs:** `SystemClipboard`'s doc, and WebAssembly port.md:148.
- **A/B:** none needed (no render path).

### A13

**S1. Region roles and the pending press.**

- **What:** the dispatcher side table; `ScrollView`, `NavigationSplitView`,
  `List`, `Table` and `OutlineGroup` file their roles; `PendingSelection`;
  the click replayed at the release with `clickCount`. Nothing selects yet.
  A pending press that drags simply does what today's dropped drag does, so
  the step is behaviour-neutral.
- **Tests:** a `PendingPressTests` table: every claimer still gets its
  click, double-click and focus, and `List` reorder is unchanged.
- **A/B:** `scrollfollow`, `megalist`, `table`, `kitchensink`; expect
  identical checksums and memo counts.

**S2. The screen selection, default tier.**

- **What:** `TextSelectionCoordinator`; `ScreenCells` promoted into TUI;
  stream and rectangle selection; snapshot; the post-pass paint; the copy
  stage after layer 0; Escape; copy on release (pending question 1);
  double- and triple-click; the notification.
- **Tests:**
  - `ScreenSelectionTests`: extraction (wide characters, ANSI, OSC 8,
    trailing blanks, tmux compensation), clip, paint on a stated palette
    and on terminal-decided colours, a menu over a selection, an
    `.opacity` text, a spinner inside a selection, the highlight dropped on
    change;
  - `SelectionCopyKeyTests`: §5's precedence through `InputHandler`;
  - the `ListRowMouseRegionTests` style.
- **Stress:** the `log` session gains drag-select steps, with a per-frame
  check that the copied text equals the rows and that the highlight sits on
  those cells. Run with `--verify` and both memo verifiers.
- **A/B:** `scrollfollow`, `app-shapes/log-viewer`, `kitchensink`; expect
  ±noise.

**S3. `.textSelection(_:)`.** `TextSelectability` and the two types; the
scope regions, journaled; `.enabled` lets `rows` yield; `.disabled`
suppresses.

- **Tests:**
  - a `TextSelectionModifierTests` table of §4.1;
  - scopes served from a memo (`MouseRegionMemoTests`);
  - `.enabled` on a single `Text` clips to it.
- **Stress:** an `InboxVariant.selectable` (`inbox-selectable`, the message
  list under `.enabled`).
- **Parity:** re-baseline; 9 gaps close.

**S4. Copy mode.** The layer, the caret, the keys, `.disabled` skipped, the
status-bar hints.

- **Tests:** `CopyModeTests`.
- **Stress:** a keyboard-select step in the `log` session.

**S5. Hand-off (D0).** The flag; the 1007 writes; restore on Escape and on
the key; `m` in copy mode.

- **Tests:** `HandOffModeTests` (the bytes written, the restore, a resize
  while handed off).

**S6. One pointer helper.** `TextPointerSelection`; the field and the editor
move onto it and gain the double-click word and triple-click paragraph; the
active-owner rule in layer 0.

- **Tests:** extend `ReversedTextSelectionTests` and `TextSelectionTests`.
- **A/B:** `controls/fields`.

**S7. Example and docs.**

- **Example:** the Mouse page gains "Selecting text": per-host bypass
  notes, copy mode, hand-off.
- **Docs:** the DocC `MouseAndGestures.md` and `KeyboardShortcuts.md`
  (Ctrl-C's precedence); `SwiftUI compatibility guide.md` rows; the decisions doc
  turns A13 into a B entry and marks A25 unblocked.
- **A25:** lands as its own few-line commit beside this.

### A43

**E1. The editor's layout cache.** A pure refactor: no wrap yet; one split
per text change, shared by size, render, keys and pointer.

- **Stress:** add the `app-shapes` variants `text-editor` (2,000 lines, a
  tenth longer than the width) and `text-editor-typing` (a session that
  types) first, in their own commit, so the cache's A/B has a baseline.
- **A/B:** those two plus `notes`; expect a drop.

**E2. `SoftWrapLayout`'s column-dependent advance.**

- **Tests:** `SoftWrapLayoutTests` gain tabs at a row's start, middle and
  end, and a tab that hangs.

**E3. Wrap mode, default off behind the new modifier's inverse.**

- **What:** rows, motion, scroll, the bar, click, selection painting,
  find reveal.
- **Tests:** `TextEditorWrapTests`, mirroring each probe row.
- **Stress:** the `text-editor-wrapped` variant.
- **A/B:** `text-editor` against `text-editor-wrapped` (the pair is the
  measurement).

**E4. Flip the default.**

- **What:** the existing editor tests take the no-wrap modifier; the
  Example's `TextInputPage` gains a wrap toggle (seven languages).
- **Docs:** the goldens are re-recorded; `TextEditor`'s doc note
  (`TextEditor.swift:101-105`), `TextSelection.swift:21`, `:122` and the
  `SwiftUI compatibility guide.md` rows are updated; the decisions doc turns A43
  into a B entry.

### A42

**R0. B84's fuller version** (if owner question 7 is yes), and the
availability check of §7.3 on the 6.2 Linux container and the macOS 15 SDK.

**R1. The storage enum.** A pure refactor; every edit as a range
replacement; `TextUndoHistory` generic.

- **A/B:** `notes` and `text-editor-typing`; expect no change.

**R2. `AttributedTextSelection` and the `AttributedString` extensions.**

- **Tests:** `AttributedTextSelectionTests` and
  `AttributedStringSelectionEditTests` (fallback indices; typing
  attributes; both `replaceSelection`s; `transform(updating:)` across an
  insert, a delete and a replace; `transformAttributes` on a range and at
  an insertion point).

**R3. `TextEditor(text: Binding<AttributedString>, selection:)`.** The
styled rows; typing attributes; selection over styles; undo restoring
attributes.

- **Tests:** `RichTextEditorTests`; compile-corpus entries for SwiftUI's
  bold-toggle example.
- **Stress:** the `text-editor-rich` variant.
- **A/B:** against `text-editor`.

**R4. The formatting context menu and the `TypedClipboard` round trip.**
Reopen `textInputFormattingControlVisibility` for `.contextMenu`.

- **Tests:** keyboard (Shift-F10) and pointer routes; items on a selection
  and at an insertion point.

**R5. Formatting definitions.**

- **What:** the protocols, the builder and the three modifiers; `constrain`
  on edits and at display.
- **Tests:** `FormattingDefinitionTests`; compile-corpus entries for
  SwiftUI's `MyTextFormattingDefinition`.
- **Gates:** the Linux cross-compile; the release-build guard.
- **Docs:** the parity map drops the waiting family and adds the
  `Transferable` decline; the decisions doc turns A42 into a B entry.
- **Example:** a rich editor on the Text Input page.

Totals:

| Item | Steps | Days |
|---|---|---|
| Clipboard | C0–C1 | 1½ |
| A13 | S1–S7 | 5 |
| A43 | E1–E4 | 3½ |
| A42 | R0–R5 | 6½ |

---

## 12. Risks and loose ends

- **The pending press hides a press from a background claimer until the
  release.** Every claimer audited acts on the release. A future one that
  acts on the press would see it late. Document the role contract on the
  registration API.
- **Cell reading under tmux.** TUI's tmux cursor compensation
  (`String.withTmuxCursorCompensation()`) puts cursor motion inside lines.
  The cell walker must read the composited buffer *before* the writer's
  compensation, which is why it reads the content buffer and not
  `ReplayableFrame.contentLines`.
- **OSC 52's silence.** A write is never acknowledged, so "Copied" on an
  OSC 52-only route is a hope. Say "Sent to the terminal's clipboard"
  there, not "Copied".
- **Hand-off with no way back but the keyboard.** If the user forgets
  Escape, the app looks dead to the pointer. The status-bar item is the
  guard. It should not time out.
- **`AttributedString` equality per frame** may be O(n) (§7.4). If the
  `text-editor-rich` A/B shows it, key the cache on a change counter the
  editor bumps on its own writes, plus a cheap check (count and first and
  last runs) for app writes.
- **D2's environment read**, if D2 is ever built, is a `textwall` A/B away
  from being a problem. The fold into the redaction read is the planned
  answer.
- **Fn in Terminal.app** may turn out to be a real bypass. Then the
  compatibility doc and `MouseSupport`'s table say so. That changes nothing
  in the design: D1 is still the only route that needs no modifier at all.
- **Stale doc links.** `TextEditor.swift:105` and `SoftWrapLayout.swift:47`
  cite `SwiftUI-API-completion-decisions-W06b.md`, which no longer exists
  (the W06b entries were merged into the main decisions doc). E4 rewrites
  the first. Point the second at A43 and B62 in the same step.
- **Live bug, independent of all three:** over ssh, `TextField`'s and
  `TextEditor`'s Ctrl-C write the *server's* pasteboard. C1 fixes it. If
  C1 waits, it deserves its own issue.
