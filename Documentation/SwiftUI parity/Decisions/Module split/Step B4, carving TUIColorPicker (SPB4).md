# Completing the SwiftUI API: decisions from lane SPB4

*Lane SPB4 took step B4 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the carve of TUIColorPicker, the second module built on
TUIFoundation rather than under it, after TUIApp. It changed no public
API: the umbrella re-exports TUIColorPicker beside TUIApp and
TUIFoundation, so `import TUI` gives an app what it gave before, and an
app's `TUI.X` reaches its types through one re-export
(`UmbrellaQualifiedNameTests`). What an app can still see is listed under
[What an app can see](#what-an-app-can-see). This file holds the judgement
calls the step reached that the plan did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB4-n — needs your decision.** Nothing has shipped for these.
- **B-SPB4-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB4-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIColorPicker.ColorPicker`,
  `TUIColorPicker.ColorPickerPanel`, `TUIColorPicker.ToneCurveEditorPanel`.
  `UmbrellaQualifiedNameTests` pins all three.
- **The bundle and saved paths are unchanged.** TUIColorPicker holds no
  resources (its labels come from TUIStrings' tables, through
  `LocalizationService`), so the bundle is still `TUI_TUIStrings`
  (decisions SPB2); and it declares no `Codable` type, public or not, so no
  saved `NavigationPath.CodableRepresentation` changes.

## B. Shipped

### B-SPB4-1. TUIColorPicker names TUIImage as a dependency, and re-exports it

*Package.swift and `Sources/TUIColorPicker/Exports.swift` — no API*

The plan's map gives TUIColorPicker every lower module ("all (uses
Image)": `rules.json` has no `lower` list for it), and the step's brief asked
for an explicit TUIImage edge only if that list said so. It says nothing
either way, and TUIFoundation re-exports TUIImage today, so the module
would build on TUIFoundation alone.

**Shipped: the edge is explicit.** `.target(name: "TUIColorPicker",
dependencies: ["TUIFoundation", "TUIImage"])`, and its Exports.swift
`@_exported import`s both, as plan §4 (Q4) has each module re-export its
direct dependencies. Three reasons, all checked in the tree: the two curve
editors `import TUIImage` themselves; TUIImage's `ASCIIToneCurve`
(`Sources/TUIImage/ASCIIToneCurve.swift`) is in their public initializers
(`ToneCurveEditorPanel(stops:isPresented:)` takes `[ASCIIToneCurve.Stop]`,
`ChannelCurveEditorPanel(channels:isPresented:)` an `ASCIIToneCurve.Channels`),
so `import TUIColorPicker` alone must give an app that type; and step B5c
removes TUIImage from TUIFoundation's dependencies (plan §5), at which
point the transitive route goes away. TUIAppKit, the other target built on
TUIFoundation that uses TUIImage directly, already names both.

**The other version:** `dependencies: ["TUIFoundation"]` and one
re-export, leaving B5c to add the edge. **Price:** nothing now, and one more
line for B5c to remember. The explicit edge orders nothing new: TUIImage
already builds before TUIFoundation, which depends on it, so
TUIColorPicker's job starts at the same point either way.
