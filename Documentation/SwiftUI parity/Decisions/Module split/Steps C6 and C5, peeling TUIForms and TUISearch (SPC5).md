# Completing the SwiftUI API: decisions from lane SPC5

*Lane SPC5 took steps C6 and C5 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-10: the first two PEELS of the TextInput group, the forms first.
`Sources/TUIForms` left the coarse group of step B7 for a target of its own,
TUIForms, built on TUIFoundation alone, and then `Sources/TUISearch`
for TUISearch, built on TUIFoundation and TUITextInput; the residual
TUITextInput compiles the text inputs, the pickers and the numeric controls
until steps C7 and C8, and depends on neither new module. The step numbers are
the plan's (C5 search, C6 forms); the lane took them in the other order, which
the map allows, since neither module depends on the other. The steps changed no
public API: the umbrella re-exports both new modules, so `import TUI` gives
an app what it gave before. This file holds the judgement calls the steps
reached that the plan did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPC5-n — needs your decision.** Nothing has shipped for these.
- **B-SPC5-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC5-n — declined.** With the reason.

There is no A or C entry: the steps reached no question that needs the owner,
and declined nothing.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUITextInput`'s from step B7, `TUIFoundation`'s after
step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUIForms.Form<…>`, `TUIForms.LabeledContent<…>`,
  `TUIForms.GroupBox<…>`, `TUIForms.Card<…>`, `TUIForms.Panel<…>` and
  the form, group box and labeled content styles (`TUIForms.AutomaticFormStyle`,
  `TUIForms.GroupedFormStyle` …); `TUISearch.SearchFieldPlacement`,
  `TUISearch.SearchFieldIconPlacement`, `TUISearch.DismissSearchAction`,
  `TUISearch.SearchScopeActivation` and the toolbar behaviours. They read
  `TUITextInput.` from step B7 until these steps (decisions SPB7, "What an
  app can see", said they would change at the peels), so a release that ships
  both should give the new names. `UmbrellaQualifiedNameTests` pins them. The
  text inputs', pickers' and numeric controls' names are unchanged
  (`TUITextInput.TextField<…>`, `TUITextInput.TabWidth`,
  `TUITextInput.TrackStyle`).
- **Saved state is unaffected.** Neither directory declares a `Codable` type,
  and no declaration of either is something a `NavigationPath` stores by name
  (checked by grep, 2026-10-10: no `Codable`, `_mangledTypeName`,
  `String(reflecting:)` or `String(describing:)` of a type in either
  directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it**
  (decisions SPC3). `Form`'s, `GroupBox`'s and `LabeledContent`'s pages list
  the forms' style modifiers and no longer TUITextInput's (`searchable`,
  `textFieldStyle`, `pickerStyle` and the rest), and `TextField`'s and
  `Picker`'s list neither the forms' nor search's; `View`'s lists them all
  (checked in the strict docs build's archive, 2026-10-10: member pages `Form`
  287, `GroupBox` 290, `LabeledContent` 293, `TextField` 333, `Picker` 335,
  `View` 520). The archive has 45,548 pages, against 46,581 in lane SPC3's
  record of step C3 (step C4 moved some too). No doc link had resolved only
  through such a copy: the strict build reports nothing.
- **`import TUIForms` brings TUIFoundation and nothing of the text
  inputs'**, once per-module products ship. **`import TUISearch` brings
  TUITextInput too**: it re-exports it, since a search field is a
  `TextField` and its scope bar a `Picker`, so the text inputs, and the pickers
  and numeric controls until steps C7 and C8, come with it. **`import
  TUITextInput` no longer brings forms or search**, nor does `import
  TUIColorPicker`, which re-exports TUITextInput. Under the umbrella,
  which is the only product today, nothing changes.
- **No other module gained an edge.** No file of TUITextInput,
  TUIColorPicker or any other module names a declaration of either
  directory (the crossing reports after each peel: 0 sites), and no form file
  names one of TUITextInput's.

## B. Shipped

### B-SPC5-1. Of plan tier 2's step-C5 callees, all three are annotated; the search field's initializer is not

*Sources/TUITextInput/Views/TextInputSuggestions.swift — no API*

The A1′ re-cut (tiers-A1p) lists three tier-2 callees that first cross at C5:
`EnvironmentValues.textInputSuggestions`, `TextSuggestions.none` and
`TextSuggestions.offering(_:tokenSink:)`. The coordinator's rule for these
steps: annotate only what the release binary shows called on a per-frame path.

**Shipped:** the carve's release Stress showed all three called out of line
on every evaluation of a `.searchable` (the field's suggestions, the search
suggestions' environment default, and the key path the field's
`transformEnvironment` writes through), where the base and premod inlined them,
and the inbox session evaluates its searchable every frame. They are
`@inlinable package`, with `TextSuggestions`, its fields, `_TextSuggestionEntry`
and `SearchTokenSink` `@usableFromInline`, the environment key
`@usableFromInline package` rather than `private`, and `tokenSink` a `let` with
no default, so that the inlined initializer runs no stored-property default out
of line. The binary shows the three calls gone, and every static total
unchanged.

What still crosses out of line on that path, and did not in the base or
premod: the search field's `TextField.init(verbatimTitle:text:prompt:)`, one
call per evaluation, behind the public initializer that conservative
cross-module optimisation inlines; and `SearchTokenSink.init(choice:)`, once
per evaluation of a searchable with tokens, which no scenario has.

**The fuller version:** `TextField`'s internal initializer `@inlinable` too.
Price: the ten stored properties of `TextField` (the editing closures, the
value formatting and the selection channel among them) `@usableFromInline`, and
the defaults of `axis` and `selection` assigned in each initializer instead
(CONTRIBUTING.md, "Crossing a module boundary"), to save one call per frame of
a searchable, in which the field's construction itself is the cost. Not done:
the A/B (batch 2, the inbox session) prices the call first.

## Not done here

- **The forms' and search's crossings into TUIFoundation.** These steps add
  none: both directories' calls into TUIFoundation have crossed a module
  boundary since step B7 carved the TextInput group. The crossing reports list
  them (forms: 133 sites in 59 callees, among them B7's `erasedID` and
  `erasedBorder` entry points for a form's `if` groups and grouped section
  boxes, and 33 generic callees called unspecialised, the stacks' and
  `frame`'s; search: 76 sites in 33 callees). They are B7's, and unchanged
  here; the coordinator's batch-2 A/B measures app-shapes, the dashboard,
  framed columns, key rows and the settings and inbox sessions, which reach
  them.
