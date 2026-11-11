# The terminal's text cursor follows the focus: proof of concept

Status, 2026-11-07: **a rough proof of concept, off by default**, so the owner can see it and judge its side effects. It
is not finished, and nobody has seen it in a real terminal yet: screen capture on this machine shows only the wallpaper
(see `Terminal compatibility survey.md`, "What a reversed cell paints"). The question it answers is §25 of
[the SwiftTUI comparison's feature answers](<../Historical/SwiftTUI comparison, 2026-11/Answers, features.md>).

## How to try it

```sh
TUI_TEXT_CURSOR_FOLLOWS_FOCUS=1 swift run Example        # or =show: the real cursor, shown, on the focused control
TUI_TEXT_CURSOR_FOLLOWS_FOCUS=hidden swift run Example   # the real cursor moved there, but kept hidden
```

`1` and `show` are the same. Any other value, or none, leaves things as they were: the cursor hidden for the whole run,
parked on a focused text control's insertion point and nowhere else.

Things worth looking at: Tab through the Buttons page (the cursor on each button's first cell, over its focus colours);
a List (the cursor on the cursor row's first cell); a text field (the real cursor on the caret, beside TUI's own caret);
a sheet; the Spinners page (a spinner rewriting cells while the cursor sits elsewhere); a screen reader, BRLTTY or a
magnifier tracking the cursor between side-by-side panes.

## What it does

After each frame, and after each animation tick it replays, the run loop puts the terminal's cursor on the focused
control (`RenderLoop+Cursor.swift`):

- on a focused text control, its insertion point, as it always has, for an input method's marked text;
- on any other focused control, the first cell of the first region carrying its focus id that the frame drew. For a
  `List` or a `Table` that is the cursor row, the region `ScrollView`'s reveal already follows; for most controls it is
  their top-left cell.

Under `show` it writes `CSI ? 25 h` after that move, and `CSI ? 25 l` once nothing focused is on screen. Under `hidden` it
writes neither: the cursor stays hidden, but sits where the focus is, for a tool that tracks a hidden cursor's position.

## Why it is safe

- **The diff writer never relies on where the cursor was.** `FrameDiffWriter` starts every write with an absolute move
  (`CSI row ; col H`), and its only relative motion, Terminal.app's advance compensation, comes after one in the same
  row. So a cursor left anywhere at the end of a frame cannot misplace the next frame. That is what already lets the
  insertion point be parked (2026-10-17); this extends the same parking.
- **The move goes out inside the frame's held update** (synchronized output, mode 2026) where the terminal holds one, so
  the cursor does not visibly travel through the frame's writes there. It is written only when the frame wrote something
  or the target moved, so an idle frame stays empty.
- **Restored at exit, as before.** A quit and a suspend hand the terminal back with the cursor shown and the alternate
  screen left (`Terminal.handBack`); a resume hides it again and repaints, and the next frame shows it again. The PoC sets
  no cursor shape, so there is no shape to restore.

## Open issues

- **The focus breath.** Every breath tick rewrites cells next to the cursor, and a reader watching the screen may hear the
  change. `TUI_BREATHING=0` stills it; it is a separate switch on purpose, so the two can be judged apart and a later
  `TUI_READER` can turn on both.
- **The cursor over TUI's own decoration.** A block cursor on a focused button's coloured caps or a cursor row's fill may
  hide the cell it sits on. A bar or underline shape (`DECSCUSR`) would avoid it, at the cost of a shape to restore at
  exit and a choice per terminal.
- **Two carets in a text field** under `show`: the real cursor and TUI's synthetic one. SwiftTUI skips its synthetic
  caret while its real cursor is on; that wants the text field's renderer to know the mode.
- **Without synchronized output** (Terminal.app, tmux unless asked) the shown cursor jumps to each row a frame writes
  before it lands. A hide at the frame's start and a show at its end would cover that, for 12 bytes a frame.
- **Other writers.** A spinner's or a breath's tick is replayed through the same parking, so the cursor ends where the
  focus is, but whether an accessibility layer sees the intermediate moves is unknown: it needs one real reader.
- **No `cursorAnchor`.** A control can't yet choose its spot (a toggle its mark, a slider its thumb); it is the region's
  first cell.
- **The first cell of a region may be clipped.** Inside a scroll view the region is cut to what is drawn, so the cursor
  goes to the first cell still on screen, which is right, but a control scrolled wholly away leaves the cursor hidden.
- **Not measured on any terminal.** `Terminal compatibility survey.md` has no row for it yet.
