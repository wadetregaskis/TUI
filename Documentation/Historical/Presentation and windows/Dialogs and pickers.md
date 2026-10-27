# Dialogs and pickers

*A critical dialog's caution sign, and how pickers take the keyboard. Ids:
B-D3M-1, B-D2C-1, B-D2C-2.*

## In short

A critical alert or confirmation dialog starts with the ⚠️ emoji, as asked. A
segmented picker's Return chooses (macOS's does nothing); a compact date
picker's calendar takes the keyboard as it opens.

## The record

### B-D3M-1. A critical dialog's caution sign is the ⚠️ emoji, not a full-size icon

*`DialogSeverity.critical` (B41)*

**Shipped:** as you asked, a critical alert or confirmation dialog starts its
title with ⚠️ (U+26A0 U+FE0F), keeping the warning colour on its border and
title. It is a VS-16 pictograph, a measured row of `Terminal compatibility survey.md`'s
advance table, so the writer's existing compensation squares the two hosts that
advance it one cell (Terminal.app, iTerm2); it is drawn on every host, not only
the `supportsEmojiChrome` allowlist.

**The fuller version** is macOS's own presentation: a large caution symbol,
drawn as a picture through the Kitty graphics protocol on the hosts where
`Image` already draws pictures, sized to four or five rows beside the message
as the dialog icon is, and the emoji where it cannot. The picture machinery
exists; the work is a caution glyph rasterised at the cell size, a dialog
layout that makes room for it, and the snapshot and PTY tests. About a day.
You said this is a later project; it is recorded here so it is not lost.

### B-D2C-1. A segmented picker's Return chooses, where macOS's does nothing

*`SegmentedPickerStyle`, `PalettePickerStyle` (decisions B13)*

**Measured on macOS 15.8** (a SwiftUI `.segmented` picker in an
`NSHostingView`, its `NSSegmentedControl` made first responder and sent key
events): the keyboard cursor starts on the selected segment; Left and Right
move it **without choosing** — the owner's note expected macOS to choose as
the arrows move, and it does not — wrapping at either end; **Space** chooses
the segment under it; **Return does nothing**.

**Shipped:** all of that, except that Return chooses too. The control keys
through the horizontal radio group's handler, where Return and Space both
choose, and Return is the activation key of every TUI control. The
arrows wrap here as on macOS, whatever `.radioButtonGroupEdgeBehavior(_:)`
says to radio groups around it.

**The alternative:** Return passes through, as macOS's does, so a default
button can take it. A flag on the shared handler; a quarter of an hour.

### B-D2C-2. A compact date picker's calendar takes the keyboard as it opens

*`CompactDatePickerStyle` (decisions B14)*

**Shipped:** Return or a click on a `.compact` field opens the `.graphical`
calendar in a popover, and the calendar takes the focus as it appears, so
the arrows move the day at once; Return closes it on that day, Escape or a
click outside just closes it. A TUI popover otherwise leaves the focus
where it was until a first key finds its content, which would spend that
key.

**Not measured:** what macOS's keyboard does while a compact picker's
calendar overlay is up. If it stays in the field, with the calendar
following it, then matching that makes the calendar a pointer-only
surface, which TUI's rule against mouse-only interactions forbids — so
the alternative is "the field keeps the keyboard and the calendar is
reached by Tab", an hour, and worth measuring first.
