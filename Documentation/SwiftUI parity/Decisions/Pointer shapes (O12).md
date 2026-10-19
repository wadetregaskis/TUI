# Completing the SwiftUI API: lane O12's judgement calls

*Lane O12, 2026-10-19, shipped the owner's ruling on refusal review
[O12](<../Refusals re-examined, wave 17 (2026-10-03).md#o12-pointerstyle-family--m>)
(2026-10-12: option (b), inert where unsupported), to the design in the
Ghostty study's
[§C4](<../../Terminals/Ghostty VT reference adoption study.md#c4-pointer-shapes-osc-22--adopt-as-o12-option-b-with-per-host-names-q2>):
`PointerStyle`, `View.pointerStyle(_:)`, `FrameResizePosition` and
`FrameResizeDirection`. Where the work met a judgement call the ruling did not
settle, the safe option shipped and is written up here, in the three parts the
other lanes use: A needs a decision, B shipped the safe option (with the fuller
version and its price), C declined with a parity-map reason.*

*Nothing about the pointer could be measured here: the window system draws it,
outside the byte stream, and screen capture was not available to the lane.
Every host fact below is from its documentation or its source (copies in the
lane's notes, `O12/docs` and `O12/ghostty-src`), and SwiftUI's own behaviour
was not measured either: an offscreen `NSHostingView` given synthetic
`mouseMoved` and tracking-area events never changed `NSCursor.current`
(`O12/probe/cursor.swift`), so what SwiftUI does needs the real pointer.
`Tools/TerminalProbes/pointer_shape_card.py` awaits the owner's reading.*

## A. Needs a decision

### A-O12-1. A hand over every button, or over links only?

The study's §C4 and the lane brief say "`pointer` over Link and Button"; the
same study's question to the owner (§5, Q2), which the owner answered yes,
says "over fields, links and dividers", without buttons; and a Mac's buttons
keep the arrow (AppKit's convention; SwiftUI's unmeasured, see above). Shipped as the brief says, and
off everywhere until a host's reset is read (B-O12-6), so nothing a user sees
depends on the answer yet.

- **(a) Every button**, as shipped: a hand says "this can be clicked", which in
  a terminal, where nothing else says so, is news. Cost: none.
- **(b) Links only**, the Mac's convention: a `Link` passes a flag to the
  button it draws, which files the hand only then. Cost: an hour.

*Recommend (b)*: the arrow over a button is what a Mac user expects, and the
hand keeps its meaning — this goes somewhere else.

## B. Shipped the safe option

### B-O12-1. Emitted only where a host documents OSC 22, in its own names

*`PointerShapeHost`, `TerminalClient.pointerShapeSupport`,
`TerminalClient.pointerShapesSupported`, `TUIKIT_POINTER_SHAPES`*

The ruling said "inert where unsupported"; the lane brief named the hosts
that document it. Shipped:

- **Ghostty** from 1.0.0, **kitty** and **foot** in CSS's `cursor` names;
  **iTerm2** from 3.5.0 in the nineteen X11 names its table reads (unchanged
  from 3.5.0 to 3.6.11); **xterm** from patch #367 in the X11 cursor font's.
  Everything else — Apple Terminal, Warp, tmux, an unidentified host — is
  sent nothing and owed nothing.
- **Found by the environment**, as the other detectors are: no portable query
  reports OSC 22. A version stated below the host's turns it off; a host that
  states none is taken to be recent, because every one of them parses OSC and
  an older release swallows the sequence (the cost of being wrong is nothing).
- **A style a host has no name for** — a closed hand on iTerm2 or xterm, a
  zoom glass, a diagonal resize on iTerm2 — gives the host its own pointer,
  never the shape left over from the last style.
- **tmux is off** whatever runs it: whether it passes OSC 22 to its client is
  unmeasured, and the study's hypothesis is that it drops it.

**The fuller version.** Each host's row read off the card, and the table
corrected where a name draws something else (½ day with the owner's
reading). Under tmux, a passthrough (`DCS tmux; … ST`, which needs the user's
`allow-passthrough on`) to a client named by `#{client_termtype}` (½ day, after
measuring that tmux drops the bare sequence). iTerm2's next release's `fleur`
and `plus`/`minus` once it ships with them (an hour).

### B-O12-2. The innermost style in front of the control under the pointer wins

*`MouseEventDispatcher.resolvePointerShape(at:y:)`*

SwiftUI's documentation says only that the style shows "when the pointer is
over the view". Shipped, read as the hover machine reads its observers:

- Of nested styles, the **innermost** under the pointer wins; one set on a
  container reaches every view in it that sets none.
- Of views that **overlap** — an overlay over its base, a `ZStack`'s layers,
  content over its background — the style of the one in front wins. The
  order of the regions cannot tell the two cases apart (a wrapper's region
  and a view in front of it both come after what they cover), so each style
  notes the styles inside its own view as it files its region, and the walk
  front to back goes past a style only into those.
- A view **covered** by another — a sheet's backdrop, an open menu, a control
  drawn over it — shows its style only where nothing covers it. A style set
  on a view INSIDE a `Button`'s label is covered by the button's own region,
  as an `.onHover` there is.
- A wrapper that takes events for its content without drawing it —
  `.draggable` (a `Table` row's drag handle too), `.focusable()`'s
  click-to-focus, `.onMouseEvent` — is **seen through** to the styles inside
  it, though its region covers its content: `.pointerStyle(.grabIdle)
  .draggable(item)` shows the open hand. It still covers what is behind it,
  and a control inside it what that control covers.
- A style the app set **beats a control's own shape** (B-O12-6), even one set
  further out: the app asked for it, and the control's is TUIkit's guess.
- `nil` sets none, and a view inside **`.disabled(true)`** shows none (as an
  `.onHover` there hears nothing): a resize arrow or a hand over a view that
  cannot be acted on says that it can.

SwiftUI's handling of the last three is unmeasured (see above).

**The fuller version.** The same rules measured against SwiftUI with the real
pointer — `CGWarpMouseCursorPosition` on a quiet machine, with the owner's
leave to move the pointer — and corrected where they differ (½ day).

### B-O12-3. Written as the pointer moves, with no frame for it

The study says "the frame resolves the topmost style under the last motion".
Shipped: a style's region has no handler, is passed over by every event and
by the hover machine, and so asks for no frame as the pointer crosses it. The
run loop asks the dispatcher for the shape where the pointer rests after every
batch of input and after every frame, and the terminal writes it only when it
changed. Motion reporting (mode 1003) is asked for only while a style is on
screen, and only where the terminal takes shapes. During a drag the shape
follows the pointer's cell, so a divider dragged with the pointer keeps its
arrow, and a drag that leaves a styled view loses its style (macOS holds a
cursor through a drag; unmeasured for SwiftUI).

**The fuller version.** The shape held at the press for as long as a button is
down (two hours, and a decision about which view's later style wins).

### B-O12-4. Put back before the mouse modes go off, on every way out

*`TerminalHostState`, `TerminalHostSetting`, `Terminal.inputModesOwed`*

The study asked for a probe to find which of `default`, an empty name, or
leaving the alternate screen restores Ghostty's pointer. Ghostty's source
answers it: turning any mouse mode off gives the I-beam a shell has, and
newer releases read an empty name as a reset. So the teardown — a quit and a
Ctrl-Z alike — writes the empty name, every host's documented reset, BEFORE the
mouse modes go off (a name after them would undo Ghostty's), and the debt a
fatal signal pays begins with the same. After any mouse mode change the
shape is written again, as Ghostty resets it on one; after a resume, the
first motion sends it afresh.

The reset is owed only once a shape has been sent, and the debt is armed with
it before that first shape goes out; paid, it is owed again only by the next.
An app that never sets a shape writes no OSC 22 at all, as it leaves or to a
signal. **A departure from the study**, whose rule (§4) keeps an OSC 22 reset
out of the debt until the probe has shown it gives the shell its own pointer
back; no host's has been read yet (`pointer_shape_card.py` awaits the
owner). The lane first owed it from the start, to every detected host, on the
documentation and the sources alone; the review held that to the rule. Where
the app has set a shape, though, the reset is still sent: the pointer left in
the app's last shape is the defect the study's reset exists to prevent, and an
empty name read as "the arrow" rather than "the shell's own" (xterm's handling
is the least clear) is no worse than that. Once a host's reset is read off the
card, the rule is met there.

**The fuller version.** Each host's reset read off the card, and the debt
holding it from the start where it reads clean (with the card's reading, an
hour).

The study's "one mechanism for state outside the grid" (§1.2) is built here
as `TerminalHostState`, one `TerminalHostSetting` per value (wanted, last
sent, the mid-run unset, the reset), owned by the `Terminal` instance rather
than the render loop: the terminal is what the bytes go to, what composes the
signal's debt, and what changes the mouse modes. A title or a progress bar
adds a setting to it.

### B-O12-5. One environment value for what the terminal does outside its grid

*`TerminalFeatures`, `EnvironmentValues.terminalFeatures`*

The study asked for one value, shaped like `\.keyboardReporting`, that later
features outside the grid add fields to. Shipped as `\.terminalFeatures`,
with `pointerShapes` its first field; decided once, as the app starts, from
the terminal's answer. `TerminalClient.pointerShapeSupport` is read then too,
so an app sets it in its `init` (the hyperlink override is live; making this
one live costs an `onChange` path through the context, an hour, and nothing
has asked for it).

### B-O12-6. TUIkit's own controls' shapes are built, and off until a host's reset is read

*`MouseEventDispatcher.fileControlPointerShape(_:for:in:)`,
`TerminalFeatures.controlPointerShapes`*

The ruling: built-in shapes "only where the reset is measured clean". Built,
each on the control's own region: the I-beam over `TextField`, `SecureField`
and `TextEditor`; a pointing hand over `Button` (and so `Link`, which draws
one; and a `Menu`'s trigger, but not its rows); a column's resize arrow over
`HSplitView`'s and `NavigationSplitView`'s dividers and over the gap after a
resizable `Table` column's title, a row's over `VSplitView`'s; the edges of a
`userResizable` view, its corner the diagonal. Each asks for motion
reporting while it is on screen, as a style does: a shape shows where the
pointer rests, which nothing else reports. A style the app set beats a
control's own (B-O12-2). No host's reset has been read yet
(`PointerShapeHost.resetIsMeasured` is `false` for all), so they are off
everywhere unless `TUIKIT_POINTER_SHAPES=all` asks for them; a host's row turns
on once the card is read there. Off, a control's call files nothing.

## C. Declined

### C-O12-1. `PointerStyle.image(_:hotSpot:)`

Both forms (an `Image`, an `ImageResource`). A terminal takes its pointer's
shape by name from the window system's own cursors, and none takes a picture
for one. It would have to draw nothing, so it fails to compile (parity map,
`notImplemented`).

### C-O12-2. `View.pointerVisibility(_:)`

No terminal documents a name that hides the pointer: `none` is not among the
names Ghostty, kitty or foot read, and iTerm2 and xterm take none. Refused
unless the card finds a name that hides it on a host (parity map,
`notImplemented`).
