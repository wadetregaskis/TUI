# Completing the SwiftUI API: decisions from lane SPB7

*Lane SPB7 took step B7 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-09: the carve of the TextInput group, the third coarse group and
the last carve of the plan's coarse stage: one target, TUIkitTextInput, named
after the module the peels leave, that compiles five planned modules'
directories, `Sources/TUIkitTextInput`, `Sources/TUIkitPickers`,
`Sources/TUIkitForms`, `Sources/TUIkitSearch` and
`Sources/TUIkitNumericControls`, until steps C5 to C8 peel the last four into
targets of their own. TUIkitFoundation compiles only its own directory since,
and is an ordinary target at `Sources/TUIkitFoundation`. The step changed no
public API but one underscored witness (B-SPB7-2): the umbrella re-exports
TUIkitTextInput beside TUIkitFoundation, so `import TUIkit` gives an app what
it gave before. This file holds the judgement calls the step reached that the
plan did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB7-n — needs your decision.** Nothing has shipped for these.
- **B-SPB7-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB7-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitFoundation`'s after step B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIkitTextInput.TextField<TUIkitFoundation.Text>`,
  `TUIkitTextInput.TabWidth`. That includes the types of `Sources/TUIkitPickers`,
  `Sources/TUIkitForms`, `Sources/TUIkitSearch` and
  `Sources/TUIkitNumericControls`, which compile into TUIkitTextInput until
  steps C5 to C8: `TUIkitTextInput.RadioButtonOrientation`,
  `TUIkitTextInput.DatePickerComponents`, `TUIkitTextInput.AutomaticFormStyle`,
  `TUIkitTextInput.GroupedFormStyle`, `TUIkitTextInput.SearchFieldPlacement`,
  `TUIkitTextInput.SearchFieldIconPlacement`, `TUIkitTextInput.TrackStyle`,
  `TUIkitTextInput.IndeterminateStyle`. Those names change again at each peel,
  to `TUIkitPickers.`, `TUIkitForms.`, `TUIkitSearch.` and
  `TUIkitNumericControls.`, so the release notes should give the peeled name
  for a type if its peel ships in the same release. `UmbrellaQualifiedNameTests`
  pins at least one from each directory.
- **Saved state is unaffected.** None of the five directories declares a
  `Codable` type (checked by grep, 2026-10-09), so nothing an app saved names
  one of them, and none can be a saved value in a `NavigationPath` (decisions
  SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The five directories hold Swift files only (the
  fields', pickers' and search's labels come from TUIkitStrings' tables
  through `LocalizationService`), so the bundle is still `TUIkit_TUIkitStrings`
  (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIkitFoundation's.** As at steps B5 and B6:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `textFieldStyle(_:)`, `pickerStyle(_:)`, `formStyle(_:)` or `gaugeStyle(_:)`
  among its default implementations, while `View`'s and `TextField`'s,
  `Picker`'s, `Form`'s and `Slider`'s pages still do (checked in the strict
  docs build's archive, 2026-10-09). The archive has 47,313 pages. No doc link
  had resolved only through such a copy: the strict build reports nothing.
- **`import TUIkitColorPicker` brings the text inputs, pickers, forms, search
  and numeric controls too**, once per-module products ship: it re-exports
  TUIkitTextInput, its new direct dependency (its editors are `Slider`s, its
  panel's hex field a `TextField`, its channel-curve editor a
  `RadioButtonGroup`). After the peels it re-exports the modules they make
  (plan §4). Under the umbrella, which is the only product today, nothing
  changes.
- **No other carved module brings them.** TUIkitLists, TUIkitNavigation,
  TUIkitChrome, TUIkitMenus, TUIkitEffects, TUIkitBitmaps and TUIkitApp do not
  depend on TUIkitTextInput: no file of theirs names a declaration of the
  group's five directories (the pre-carve index: 0 references), and no build
  error asked for an edge. A searchable list (`List { … }.searchable(text:)`,
  as Stress's inbox session writes it) is TUIkitSearch's modifier on a
  TUIkitLists view: the app imports both, and today gets both from the
  umbrella.
- **`TimelineView` states `_handsOverChildren` itself** (B-SPB7-2): a public
  member, underscored like the protocol requirement it witnesses, with the
  value the default gave it.

## B. Shipped

### B-SPB7-1. TUIkitFoundation applies the five modifiers whose result types TUIkitTextInput cannot see, in seven methods: two draw in place and five erase

*Sources/TUIkitFoundation/Extensions/View+BuiltForAnotherModule.swift — no public API*

The carve left fifteen call sites in TUIkitTextInput that look an opaque
result's type up at run time (`swift_getOpaqueTypeMetadata2` and
`…Conformance2`, which demangle the type's name each time): the five public
modifiers `border`, `id`, `foregroundStyle`, `focused` and `onAppear`, whose
`some View` results name types only TUIkitFoundation can see, applied in the
group's views (release Stress, 513 opaque-runtime call sites against the
base's 498). One of them was hot: `_StyledFieldFrame`, which wraps every
`TextField` and `SecureField`, asked for `border(style:)`'s type at the top of
its render and its measure, so every field paid the lookup on every frame,
bordered or not. The rest are on paths no Stress scenario reaches: an `if`
among a form's rows (`id`), a grouped form's section box (`border`), a search
token (`foregroundStyle`), a text editor's open find bar (`focused`,
`onAppear`).

**Shipped:** seven `package` methods on `View` in TUIkitFoundation, each of
which applies one of those modifiers there, where the type is concrete.
`renderBordered(style:context:)` and `measureBordered(style:proposal:context:)`
draw and measure the bordered view as `_StyledFieldFrame` did, with nothing
erased. `erasedBorder()`, `erasedID(_:)`, `erasedForegroundStyle(_:)`,
`erasedFocused(_:)` and `erasedOnAppear(perform:)` return the modified view in
an `AnyView`: the same value for the form's `if` groups, which were erased
already; one more `AnyView` per evaluation of a grouped section or a token
chip, and two per evaluation of an open find bar (`focused` and `onAppear`).
The static count is the base's again (498).

**The other version:** for the four cold callers, a `Renderable & Layoutable`
wrapper per modifier in TUIkitFoundation, which draws and measures the
modified view at its own identity, as `_StyledFieldFrame` now does through the
first two methods, so nothing is erased. **Price:** five more types, each of
which must forward what its view's type tells a container (its member count,
`_providesAlignmentGuide`, which `ConditionalView` forwards for `border`'s
result), where a missed forward is a silent layout change; for an allocation
per evaluation on paths no scenario reaches. Or leave those lookups, about
one per evaluation on the same paths, and the static gate above the base's.

### B-SPB7-2. `TimelineView` states `_handsOverChildren`

*Sources/TUIkitFoundation/Views/TimelineView.swift — a public underscored member*

`ProgressView(timerInterval:)` labels itself with `DefaultDateProgressLabel`
(TUIkitTextInput), whose body is a `TimelineView`. Its `_handsOverChildren`
witness is View's default, `Body._handsOverChildren`, and TUIkitTextInput
inlined that default twice over: through `TimelineView`'s own default, it
asked for `TimelineView`'s body type, whose underlying core is private to
TUIkitFoundation, and looked it up at run time on every child walk (one of
B-SPB7-1's fifteen).

**Shipped:** `TimelineView` (TUIkitFoundation) declares
`public static var _handsOverChildren: Bool`, returning its core's answer,
which is what the default returned. Naming the private core keeps the witness
out of every other module's inline code, so the label calls it.

**The other version:** `DefaultDateProgressLabel` states its own answer,
`false`, in TUIkitTextInput. **Price:** no change to `TimelineView`'s public
surface, but a second module then hard-codes what a TUIkitFoundation type's
private core answers, and goes on answering it if the core changes.

### B-SPB7-3. The small per-frame calls the carve puts out of line stay calls

*Sources/TUIkitFoundation — no API*

Against the base's release Stress, the carve adds out-of-line calls from
TUIkitTextInput, per frame for a control, to callees TUIkitFoundation inlined
before (call sites by callee, base -> after the carve, all modules):
`ANSIRenderer.colorize` 45 -> 137 (per styled run of a field's text, a caret
frame and an editor row); `MenuHighlight`'s methods 19 -> 55 (a picker's menu
and a field's suggestions, per keystroke and per frame while open);
`FocusRegistration`'s statics 116 -> 123; `TextStyle`'s initializer and setters
118 -> 136 (a graphical date picker's day cells); `StyleChain` 28 -> 43 (the
styled controls' bodies); `CursorTimer`'s and `IndicatorCycleTiming`'s statics
81 -> 93 (a focused field's caret); `DropdownMenu` 79 -> 89; and the
environment accessors the plan's tier 2 lists at B7 (`styleCascade`,
`cursorTimer`, `indicatorCycleTiming`, `indicatorAnimationSpeeds`,
`appearsActive`).

**Shipped:** all stay calls, as steps B5c (B-SPB5c-3) and B6 left theirs.
`colorize` builds an escape string in `ANSIRenderer.render`, which it called
out of line before too, and an environment accessor is a dictionary lookup
beside its call; `MenuHighlight` is a class whose stored properties
CONTRIBUTING forbids widening, so its methods cannot be inlined into another
module without making every access to them checked at run time; the rest are
a call each per control per frame. The coordinator's A/B decides which
deserve the plan's tier 2: the hot ones are listed in the carve's commit
message, with their scenarios.

**The other version:** `@inlinable package` on the pure ones now:
`CursorTimer.blinkVisible(atFrame:)` and `pulsePhase(atFrame:of:)`,
`FocusRegistration.isFocused(context:focusID:)` (tier 2 since B4), and
`TextStyle`'s initializer and colour setters. **Price:** `CursorTimer` and
`TextStyle`'s storage `@usableFromInline`; one call and return saved per
control per frame, or per day cell, which no scenario draws.

### B-SPB7-4. No Stress scenario is added for the group's paths none reaches

*Sources/Stress — nothing shipped*

No scenario draws a `DatePicker`, a `RadioButtonGroup`, a grouped `Form`, a
`SecureField`, a search token, a timer `ProgressView` or a text editor's find
bar (checked by grep over Sources/Stress, 2026-10-09). So the date picker's
per-cell calls (B-SPB7-3), the radio group's per-item ones
(`styleCascade`, `StyleCascade.resolve(for:)`, the selection emphasis), and
the four cold paths of B-SPB7-1 are measured by nothing. The text field's hot
path is measured by `controls/fields`, `app-shapes/settings-form` and the
chat, inbox, notes and settings sessions; pickers by
`app-shapes/settings-form` and the menus, settings and themes sessions;
forms by `app-shapes/settings-form`, `dashboard` (`Panel`, `Card`) and the
settings session; the numeric controls by `controls/progress`, `dashboard` and
`app-shapes/settings-form` (a `Slider` and a `Stepper` per group); search by
the inbox session.

**Shipped: nothing**, for B-SPB6-2's reason: a scenario added in this lane
would exist only on the carved side of the coordinator's A/B.

**The other version:** a `ScenarioVariant` of `controls`, `pickers`: rows of
a graphical `DatePicker`, a `RadioButtonGroup` and a segmented `Picker`, and
a second, `grouped-form`, a `Form` in `.formStyle(.grouped)` with an `if`
section (about 40 lines with their summaries). **Price:** as B-SPB6-2's, two
scenarios the sweep runs on every A/B, landed on main before the next carve's
A/B; worth it before step C8 peels Pickers.
