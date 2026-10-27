# Forms and control density

*How a `Form` lays out its rows — the labelled controls, the modifiers it puts
back around a row, a colour picker's place — and how controls draw at each
control size. Ids: O14, A-FORMS-1, B-FORMS-1 to 7.*

## In short

A labelled control is a field row; the modifiers a form puts back around a row
are named one by one; a grouped form starts a colour picker at 45% of the row.
At `.mini` a text field drops its caps; a switch under Lines is a knob between
the shape's caps. Where a bare `Button` goes in a columns form (A-FORMS-1) was
listed for the owner on 2026-10-18 and never answered (recommended: the value
column, as SwiftUI measured).

## The record

### A-FORMS-1. A button written bare in a columns form: at the trailing edge, or in the value column?

`Form`'s documentation says a `Button` is right-aligned "(macOS places
confirmation buttons on the right)", and the form does that. Measured, SwiftUI's
columns form puts a bare button in the value column, where a field's control
goes (`rows.out`: "Button bare", 21 points against a value column at 17), and
its grouped form at the row's leading edge; TUI puts it at the trailing edge
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
value column. TUI's text field draws no title at all (the semantic audit's
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
from 45% of the row (SwiftUI's rule for a field or a slider). TUI's colour
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
*Price:* an hour, now that FB3-OTHERCAPS has settled the knob (B-FORMS-7).

### B-FORMS-7. A switch under Lines: a knob between the shape's caps, four cells in every shape

The owner, 2026-10-24, from the FB3-OTHERCAPS probe card: "the current style
looks good for the 'Blocks' style. For capsule, I like B best. D looks good for
_rectangle_, but for rounded-rectangle how about something like "⦗●⦘"?"

**Shipped:** where controls are not filled, a switch is a knob in two cells
between the caps of the family and the `ButtonBorderShape` in force, read from
the shared cap table (`ControlEnds.SwitchTrack`):

| Family, shape | Off | On |
|---|---|---|
| filled (the default) | `▐▌ ` on the coloured track, as before | ` ▐▌` |
| lines, capsule (and `.automatic`, a capsule for a button) | `(○ )` (B) | `( ●)` |
| lines, rounded rectangle | `⦗● ⦘` | `⦗ ●⦘` |
| lines, radius zero | `│● │` (D) | `│ ●│` |
| lines, `.brackets(open, close)` | `❨● ❩`, the pair as caps, the knob D's | `❨ ●❩` |
| lines, `.circle` | `(○ )`, the capsule's, as a circle button's one-row caps are | `( ●)` |
| lines, `.underline` | `│● │`, the square's | `│ ●│` |
| Braille | the shape's dotted ends, as a segmented picker's: `⢎○ ⡱`, `⣏● ⣹` | `⢎ ●⡱`, `⣏ ●⣹` |
| blank | no caps, as no control has them there: `○ ` | ` ●` |

The caps are in the lines' ink (a lines button's, lifted under the pointer)
and breathe the accent while the switch holds the focus; the knob is the
accent when on, the tertiary ink when off, lifted under the pointer; all of it
faded while disabled. With no caps the knob breathes the focus itself. The
`.ascii` character set keeps its `[o ]` in every family, the glyphs above being
the ones it exists to avoid.

Three readings of the ruling, the first confirmed by the owner (2026-10-24: "4-wide is correct"; the "⦗●⦘" showed the three characters, not the render) and the rest accepted ("Shapes I didn't cover: Sure."):

- **⦗● ⦘, not ⦗●⦘.** The owner wrote the rounded rectangle's look as "⦗●⦘",
  the caps tight round the knob. Built with the four-cell track the other
  candidates have, so that a switch is one width in every shape and its knob
  slides a cell as in every other; `⦗●⦘` would be three cells with nowhere for
  the knob to go.
- **Underline takes the square's `│ │`.** A button underlined has no caps on
  one row, and a switch's track needs ends to read as a track; the sides are
  what an underline face's box is drawn in on three rows. The rounded
  rectangle's `⦗ ⦘` was the other candidate.
- **The capsule's knob is hollow when off; the straight-capped shapes' is
  solid.** As the card's B and D. Under blank, with no caps, the knob is hollow
  when off too, since its position alone says too little.

The switch draws the same track at every size (B-FORMS-6).

**Fuller version:** a longer track at `.large` and `.extraLarge`, as
B-FORMS-6 says. *Price:* an hour.
