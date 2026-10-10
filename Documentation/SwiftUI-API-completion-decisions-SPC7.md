# Completing the SwiftUI API: decisions from lane SPC7

*Lane SPC7 took steps C8 and C7 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-10: the last two PEELS of the TextInput group, the pickers first.
`Sources/TUIkitPickers` left the coarse group of step B7 for a target of its
own, TUIkitPickers, built on TUIkitFoundation alone, and then
`Sources/TUIkitNumericControls` for TUIkitNumericControls, built on
TUIkitFoundation alone too; the residual TUIkitTextInput compiles the text
inputs alone and depends on neither. TUIkitSearch gained its planned edge to
TUIkitPickers, and TUIkitColorPicker its edges to both. After these steps every
planned module of the split is a target of its own at its default path, and
Package.swift's helper for a target over several directories is gone. The step
numbers are the plan's (C7 numeric controls, C8 pickers); the lane took them in
the other order, which the map allows, since neither module depends on the
other. The steps changed no public API: the umbrella re-exports both new
modules, so `import TUIkit` gives an app what it gave before. This file holds
the judgement calls the steps reached that the plan did not already settle, in
the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPC7-n — needs your decision.** Nothing has shipped for these.
- **B-SPC7-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC7-n — declined.** With the reason.

There is no A or C entry: the steps reached no question that needs the owner,
and declined nothing.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUIkitTextInput`'s from step B7 and `TUIkitFoundation`'s after
step B1 (and `TUIkit`'s in v0.6.0, for those it had).

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUIkitPickers.Picker<…>`, `TUIkitPickers.RadioButtonGroup<…>`,
  `TUIkitPickers.RadioButtonItem<…>`, `TUIkitPickers.DatePicker<…>`,
  `TUIkitPickers.DatePickerComponents`, `TUIkitPickers.RadioButtonOrientation`,
  `TUIkitPickers.RadioButtonGroupEdgeBehavior` and the picker and date picker
  styles (`TUIkitPickers.MenuPickerStyle`, `TUIkitPickers.SegmentedPickerStyle`,
  `TUIkitPickers.GraphicalDatePickerStyle` …);
  `TUIkitNumericControls.Slider<…>`, `TUIkitNumericControls.SliderTick<…>`,
  `TUIkitNumericControls.Stepper<…>`, `TUIkitNumericControls.Gauge<…>`,
  `TUIkitNumericControls.ProgressView<…>`, `TUIkitNumericControls.TrackStyle`,
  `TUIkitNumericControls.IndeterminateStyle` and the gauge and progress view
  styles (`TUIkitNumericControls.LinearCapacityGaugeStyle`,
  `TUIkitNumericControls.CircularProgressViewStyle` …). They read
  `TUIkitTextInput.` from step B7 until these steps (decisions SPB7, "What an
  app can see", said they would change at the peels), so a release that ships
  both should give the new names. `UmbrellaQualifiedNameTests` pins them. The
  protocols the styles conform to that TUIkitFoundation declares
  (`PickerStyle`, `AutomaticPickerStyle`, `GaugeStyle` and its configuration)
  keep their `TUIkitFoundation.` names, and the text inputs' are unchanged
  (`TUIkitTextInput.TextField<…>`, `TUIkitTextInput.TabWidth`).
- **Saved state is unaffected.** Neither directory declares a `Codable` type,
  and no declaration of either is something a `NavigationPath` stores by name
  (checked by grep, 2026-10-10: no `Codable`, `_mangledTypeName`,
  `String(reflecting:)` or `String(describing:)` of a type in either
  directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUIkit_TUIkitStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it**
  (decisions SPC3). `Picker`'s, `DatePicker`'s and `RadioButtonGroup`'s
  pages list the pickers' style modifiers (`pickerStyle`, `datePickerStyle`,
  `radioButtonGroupEdgeBehavior`) and no longer the text inputs'
  (`textFieldStyle` and the rest) or the numeric controls' (`gaugeStyle`,
  `progressViewStyle`, `sliderShowsValue`); `Slider`'s, `Stepper`'s, `Gauge`'s
  and `ProgressView`'s list the numeric controls' and neither the pickers' nor
  the text inputs'; `TextField`'s lists neither; `View`'s lists them all
  (`trackStyle` is a member of `Slider` and `ProgressView` alone, as before).
  Checked in the strict docs build's archive, 2026-10-10: member pages
  `Picker` 310, `DatePicker` 303, `RadioButtonGroup` 291, `Slider` 304,
  `Stepper` 307, `Gauge` 297, `ProgressView` 309, `TextField` 316, `View` 520
  (lane SPC5's record of step C5: `Picker` 335, `TextField` 333, `View` 520).
  The archive has 45,228 pages, against 45,548 in that record. No doc link had
  resolved only through such a copy: the strict build reports nothing.
- **`import TUIkitPickers` and `import TUIkitNumericControls` each bring
  TUIkitFoundation and nothing of the text inputs'**, once per-module products
  ship. **`import TUIkitTextInput` no longer brings pickers or numeric
  controls.** **`import TUIkitSearch` brings TUIkitPickers too**: it re-exports
  it, since its scope bar is a `Picker`, beside TUIkitTextInput (a search field
  is a `TextField`). **`import TUIkitColorPicker` brings both**, beside
  TUIkitTextInput: its editors are `Slider`s, its channel picker a
  `RadioButtonGroup`, its hex field a `TextField`. Under the umbrella, which is
  the only product today, nothing changes.
- **No other module gained an edge.** No file of TUIkitTextInput,
  TUIkitPickers, TUIkitNumericControls or any other module names a
  declaration of the other two peeled-apart directories (the crossing reports
  after each peel: 0 sites), and nothing but TUIkitSearch and
  TUIkitColorPicker names the pickers, and nothing but TUIkitColorPicker the
  numeric controls.

## B. Shipped

### B-SPC7-1. `TrackRenderer.gradientColor` stays in TUIkitNumericControls, a `package` call from TUIkitColorPicker, not `@inlinable`

*Sources/TUIkitNumericControls/Rendering/TrackRenderer.swift — no API*

`TrackRenderer.gradientColor(_:index:span:fallback:depth:)` gives the colour
of one cell of a gradient spread over a span of cells. The track renderer
calls it for every cell of a gradient track it draws, inside
TUIkitNumericControls, and TUIkitColorPicker's gradient editor calls it once
per column of its preview strip and of each preset chip, every time the
editor's body is evaluated. Step B4 made it `package` for the colour picker,
when the colour picker became a module of its own; the step's brief asked
where it should live once the numeric controls are one too, decided by that
per-column call.

**Shipped:** it stays where it was, in the track renderer, `package` and not
`@inlinable`, so the per-cell calls stay inside the module that makes them,
and the colour picker's per-column call crosses into TUIkitNumericControls
as it crossed into TUIkitFoundation from step B4 and into TUIkitTextInput
from step B7 (the release binaries: the same two call sites, out of line in
the base and now; the one-module build before the split, c181ec0f9, inlined
both). Each call asks `Color.quantisedRamp` (TUIkitStyling) for the
gradient's ramp over the span, which serves a span of more than two cells
(the editor's are 36 and 8) from its cache once it holds it: a lock,
hashing the `Gradient` into the cache key, and a dictionary probe. Only a
miss samples the ramp, and at 256-colour depth repairs it into a monotone
one. Even the probe costs far more than a call (reasoned, unmeasured), so
a cross-module call adds nothing a strip column would notice; no Stress
scenario draws the editor. (Step C7's commit message, 059fa6908, says the
body quantises the whole ramp on every call; it does not.)

**The fuller version:** `@inlinable package`, with `TrackRenderer`
`@usableFromInline` and stating `Sendable` (CONTRIBUTING.md, "Crossing a
module boundary"; UsableFromInlineSendabilityTests would pin it), so the
colour picker inlines the five-line body. Price: one more `@usableFromInline`
type, for a call whose own work is a ramp-cache probe per column. Moving it
down into TUIkitFoundation instead would make every per-cell call of the
track renderer cross a module, which is the wrong way round.

## Not done here

- **The pickers' and numeric controls' crossings into TUIkitFoundation.**
  These steps add none: both directories' calls into TUIkitFoundation have
  crossed a module boundary since step B7 carved the TextInput group. The
  crossing reports list them (pickers: 319 member sites in 140 callees, 20 of
  them generic callees called unspecialised, the stacks', `Label`'s and the
  tag helpers'; numeric controls: 310 sites in 100 callees, 11 generic). They
  are B7's, and unchanged here; the coordinator's batch-3 A/B measures the
  menus, themes and settings sessions, app-shapes' settings form,
  control-rows' progress variant and the dashboard, which reach them.
