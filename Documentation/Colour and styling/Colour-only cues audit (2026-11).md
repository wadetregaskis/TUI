# Colour-only cues: an audit for colour-vision deficiency (2026-11-08)

The owner asked (2026-11-08, option 1) for every control to be checked for a meaning carried by colour alone, and for
any that is to get a cue that isn't colour, in the existing look. Read from source, 2026-11-08, at a colour depth (24-bit,
256 or 16 colours). `.noColor` already has its own cues (`FrameBuffer+NoColorStates.swift`) and isn't the subject here.

## What counts

Colour-vision deficiency loses **hue**, not lightness. So a cue is graded by what is left without hue:

- **glyph / attribute**: a different character, or bold, underline, italic, faint or reverse video. Safe for everyone.
- **lightness**: a fill against no fill, or a grey ink against the normal one. Seen without hue, though a weak one
  with low contrast.
- **motion**: the focus breath. Seen, until `TUI_BREATHING=0` or the View menu's Breathing Focus holds it still
  (Reduce Motion leaves it alone), when only the colour is left: the breath's bright end. A control that rests in that
  colour (a checked checkbox, a switch that is on, a link, a radio group's chosen option) reverses its label then, as
  under DWC (`reversedWithoutBreath`, 2026-11-10: before that, the focus on those was not drawn at all).
- **hue only**: two states drawn in two colours of about the same lightness. The case to fix.

## Differentiate Without Colour

`EnvironmentValues.accessibilityDifferentiateWithoutColor` (SwiftUI's name and type) is read from macOS's
Accessibility ▸ Display ▸ Differentiate without colour (`com.apple.universalaccess` `differentiateWithoutColor`) when
`SessionLocality` says the person is at this machine, and `TUI_DIFFERENTIATE_WITHOUT_COLOR=1` or `0` beats it each way.
GNOME has no such setting: there, only the variable turns it on. Both were already in place
(`TerminalClient+Accessibility.swift`, `RenderLoop`); until now nothing read the value.

Now, under it, a control says its state the way it does at no colour, over its colours, at every depth: the focus in
reverse video, disabled faint, a `Table` row's selection with its `●`, a radio button's `●` only on the selected
option. One rule in one place (`RenderContext.statesWithoutColor`), which every no-colour cue already asked as a depth
test, so every control turns on together. Off by default, since it changes the look; see "Open" below.

## At the terminal's depth (2026-11-10)

A cue that is a colour is only as good as the colours the terminal has. Rounded to sixteen, Silver Aerogel's accent is
its page, so ten controls' focus drew as their rest; and six palettes' disabled grey is a resting button's label. The
owner ruled (THEME-16 (b)) that where a state's colour draws as the resting colour at the terminal's depth, the
control falls back to its colour-free cue automatically: reverse video for the focus, faint for disabled. Each control
compares the colours it draws the state in with the ones it rests in, as the depth draws them
(`RenderContext.drawsAsResting`, `breathDrawsAsResting`), and passes the answer to the cue it already draws without
colour; a highlight whose fill draws as its ground is reversed (`Palette.highlightFill`), which is how a block caret
the colour of its field reverses its cell instead. `StateColourCollisionTests` sweeps every control through every
shipped palette at every depth (`TUI_COLLISION_SWEEP=1`): before, at 16 colours, 16 focused controls drew as at rest
and 51 disabled ones as enabled; after, none. At 256 colours
and without colour nothing collided. A disabled `TabView` looked enabled at every colour depth, which is not a rounding
(see the table); a disabled `ColorPicker` still does, at every depth: its label stays in the secondary tier and its
channels' arrows rest in the grey a disabled slider's do.

## The table

| Control | State | Cue at a colour depth | Status |
|---|---|---|---|
| Toggle, checkbox | on / off / mixed | `■ □ ⊟` | glyph |
| Toggle, switch | on / off | knob position | glyph |
| Toggle, `.button` | on | bold | attribute |
| Toggle, any | focus | the mark or track breathes in the accent | motion; under DWC or held still, the label reversed |
| Toggle, any | disabled | grey ink | lightness; under DWC, faint |
| Button, string title | focus | bold (plain style: `●`) | attribute |
| Button, view label, `Link`, `.borderedProminent` | focus | breath of label or caps | motion; under DWC, reversed; a `Link` (and a link in a `Text`) held still, reversed |
| Button | destructive / success role | error / success colour | hue only, but the label's words carry the meaning, as in SwiftUI; left as is |
| Button | disabled | grey ink | lightness; under DWC, faint |
| Link | against plain text | underline | attribute |
| RadioButton | selected against focused | both `●`, the focused one breathes | motion; under DWC or held still, `●` only when selected and the focused label reversed |
| RadioButton | disabled | `◌` unselected; selected grey | glyph / lightness; under DWC, faint |
| Slider, Stepper | focus | the arrows breathe | motion; under DWC, the arrows reversed |
| Slider, Stepper | disabled | grey | lightness; under DWC, faint |
| ProgressView `.block` | filled against empty | accent `█` on the track's fill | lightness |
| ProgressView, indeterminate | running | sweeps or pulses | motion |
| Gauge `.shade` | fill | `▓ ░` | glyph |
| Gauge, circular | arc | lit arc, number in the centre | lightness, and the number; under DWC, at no colour and where the depth draws the accent as the ring's grey, the lit cells in heavy lines (2026-11-11: before that, a ring with no number said nothing there) |
| Notification | severity | `i ✓ ! ✗` | glyph |
| Segmented Picker | selected / cursor / disabled | bold / fill / grey | attribute / lightness / lightness; under DWC, disabled faint |
| TabView | active tab / focus / disabled | bold / breath / faint | attribute / motion / attribute, at every depth (2026-11-10: before that, nothing at a colour depth; the strip greys only a tab disabled on its own); under DWC, reversed |
| Menu, Picker menu | highlighted row | filled bar | lightness |
| Menu, Picker menu | checked / disabled item | `✓` / grey | glyph / lightness |
| List | selected / cursor row | `●` / filled bar | glyph / lightness |
| Table, file dialog's list | selected rows | tint | lightness, weak; under DWC, `●` |
| TextField, TextEditor, SecureField | disabled | grey | lightness; under DWC, faint |
| List, Table | disabled | faint, at every depth | attribute (2026-11-10: before that, nothing at a colour depth; they have no ink of their own to grey) |
| `.selectionDisabled` row | can't be selected | faint | attribute (italic too in Warp's light theme) |
| TextField | focus / prompt | caret / grey | glyph / lightness |
| DatePicker, field | active part / disabled | fill / no underline | lightness / attribute |
| DatePicker, calendar | selected day | accent fill | lightness; reversed where the fill draws as the page, at no colour or rounded to the depth (2026-11-11: before that, no cell said which day was chosen there) |
| DatePicker, calendar | today | accent ink | **hue only: fixed, today is bold** (also gave it its first cue at no colour) |
| DatePicker, calendar | out of range / weekend / past | grey / secondary / faint | lightness / lightness / attribute |
| File dialog | folder / greyed-out file / hidden file | bold and icon or `/` / grey / leading `.` | glyph / lightness / glyph |
| Status bar | shortcut / hover | bold / underline | attribute |
| Scroll bar | thumb | thumb colour on the track | lightness |

There is no chart module, so no series told apart by colour.

## Open

- **On by default?** The DWC cues could be TUI's default look rather than an opt-in: reverse video for every focus
  and faint for every disabled control, at every depth. It would make the breath redundant and every focus look like a
  list's cursor row, and it changes every screenshot. Kept opt-in for now; the owner's call.
- A disabled control's grey and a text field's prompt rest on lightness, which is weak with low contrast;
  `colorSchemeContrast == .increased` could add the faint there too.
