# Forms and control density: decisions from lane FORMS

*Lane FORMS, 2026-10-19: three items from the 2026-10-18 inventory of open
work — a form row under a modifier the form could not put back (the semantic
audit's item 8), the labelled controls a form drew as plain rows (the
verifiers' finding on labelled controls), and the density of the controls
other than the button and the pop-up picker (O14). The calls below are the
ones the owner's rulings left open. The format is that of the main decisions
file:*

- **A-FORMS-n — needs your decision.**
- **B-FORMS-n — shipped the safe option.** Says what the fuller version
  would be, and its price.
- **C-FORMS-n — declined.** With the reason. (None this lane.)

What SwiftUI does was measured on macOS 15.8.1 with
`Tools/SwiftUIProbes/Form rows` (committed with its output).

## A. Needs your decision

The lane brief paired O14 with FB3-OTHERCAPS — whether the segmented picker,
the tab chips and the switch's knob follow the appearance's family. That is
already yours in `Documentation/Open owner decisions.md` (FB3-OTHERCAPS), and
this lane leaves it there: nothing shipped here changes a family, and the
density below draws a picker's caps only where the size does, so either answer
slots in without undoing it.

### A-FORMS-1. A button written bare in a columns form: at the trailing edge, or in the value column?

`Form`'s documentation says a `Button` is right-aligned "(macOS places
confirmation buttons on the right)", and the form does that. Measured, SwiftUI's
columns form puts a bare button in the value column, where a field's control
goes (`rows.out`: "Button bare", 21 points against a value column at 17), and
its grouped form at the row's leading edge; TUIkit puts it at the trailing edge
in both. The deviations document has no entry for it, so it is either an
undocumented deviation or a bug.

**Options.**

1. **Keep it, and record the deviation.** The trailing button is a dialog's
   convention, and a form's last row is often its confirmation. *Price:* an entry
   in `Deliberate deviations from SwiftUI.md`.
2. **Follow SwiftUI.** A button goes in the value column, and
   `.formRowAlignment(.trailing)` is how a form puts one at the edge. *Price:*
   an hour; every form whose buttons sit at the edge moves them (the Example's
   form page among them).

**Recommendation:** 2. Parity is the rule, and the TUI-specific
`formRowAlignment(_:)` already exists for the dialog's look.

## B. Shipped the safe option

### B-FORMS-1. A labelled control is a field row; a text field and a switch toggle are not yet

**Shipped:** a `Picker` of every style, a `Slider`, a `Stepper`, a `DatePicker`
under a built-in style and a `ColorPicker`, written bare in a form, put their
label in the label column and the control in the value column — in a grouped
form the label leads and the control trails — as measured
(`FormFieldControl`). A date picker under a style of the app's own is a row
drawn whole, since the style places its label.

**Fuller version:** SwiftUI does the same with two more (measured): a
`TextField`, whose title goes in the label column, and a `Toggle` in the
`.switch` style, whose label goes in the label column and the switch in the
value column. TUIkit's text field draws no title at all (the semantic audit's
TextField finding, pinned by `LocalizedTitleTests` as deliberate), so the first
is that finding's fix, scoped to forms; the second needs the form to read the
toggle style at extraction rather than at render. *Price:* about half a day
each.

### B-FORMS-2. The modifiers a form puts back around a row are named one by one

**Shipped:** a form keeps a row in its place under every modifier that can be
put back around the row it lays out: those that are `ContentRewrapping`, and,
through `FormRowRewrapping`, padding, an id and any buffer modifier,
`.background`, `.overlay`, `.help`, `.tag`, the lifecycle modifiers
(`.onAppear`, `.onDisappear`, `.task`), `.onChange`, a gesture, `.onHover`,
`.focused`, `.focusable`, `.onSubmit`, `.contextMenu` and `.keyboardShortcut`.
A leading padding widens the label column, as measured; `.labelsHidden()` on a
row hides its label and takes it out of the column, as measured. `.border` (its
rings erased per width) and a `ViewModifier` of the app's own still leave a
row plain, drawn whole.

**Fuller version:** the semantic audit's "proper version" — the label column as
an alignment guide the rows publish, so that the column survives any view
around a row, as SwiftUI's does (measured: even an `HStack` around a row keeps
its label in the column). *Price:* two to three days, and a redesign of the
form's layout; the walk it replaces is also what reads sections and `if`s.

### B-FORMS-3. A colour picker in a grouped form starts at 45% of the row

**Shipped:** a grouped form lays a colour picker's row out as it lays out any
labelled row whose content fills: the label at the leading edge, the content
from 45% of the row (SwiftUI's rule for a field or a slider). TUIkit's colour
picker carries its channel sliders inline, so in a row much under a hundred
cells its sliders shrink to their knobs. SwiftUI's colour well is a fixed
swatch at the trailing edge, so it never meets the case.

**Fuller version:** a filling content whose ideal width is more than 55% of the
row starts just after the label instead, or a colour picker in a grouped form
drops its channels (`.colorPickerChannels(.hidden)`, the swatch alone, which is
SwiftUI's shape). *Price:* an hour or two either way; the second is a look
choice.

### B-FORMS-4. The other controls' density stays on one row

**Shipped:** O14's table for the controls other than the button and the pop-up
picker, one commit each: a segmented or palette picker drops the space round
its options at `.small` and its caps too at `.mini`, and takes two spaces at
`.extraLarge`; a stepper the space round its value; a slider the gap between
each arrow and its track (the arrows stay: they are its buttons); a text field
its caps at `.mini`. Each reads the button's numbers
(`ControlSize.padding(regular:)`, `ControlSize.drawsEndCaps`).

**Fuller version:** the ruling's "extra render styles per size where they
help", as the button's three-row faces: a segmented picker and a text field
three rows tall at `.large` and `.extraLarge`, in the family's box. *Price:*
about a day each, the field's the larger (its caret, selection and click
mapping assume one row), and a look for you to see first — with
FB3-OTHERCAPS, since the box is the family's.

### B-FORMS-5. A text field drops its caps at mini, and gets no room at extra large

**Shipped:** at `.mini` a text field or secure field is its surface alone, two
cells narrower; at every other size it is drawn as before.

**Fuller version:** a blank inside each cap at `.extraLarge` (`│ text │`), the
look FB3 (a) left for you because it costs every field two cells. *Price:* an
hour; the caret's offset and the caps' claims move with it.

### B-FORMS-6. A checkbox and a switch draw alike at every size

**Shipped:** nothing changes; the table says so, and a test pins it. A checkbox
is a glyph and a gap and a switch a three-cell track, with nothing to trim; a
`.button` toggle follows the button's table.

**Fuller version:** a longer switch track at `.large` and `.extraLarge`.
*Price:* an hour, after FB3-OTHERCAPS settles the knob.
