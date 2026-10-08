# Completing the SwiftUI API: decisions from lane SPB4

*Lane SPB4 took step B4 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-08: the carve of TUIkitColorPicker, the second module built on
TUIkitFoundation rather than under it, after TUIkitApp. It changed no public
API: the umbrella re-exports TUIkitColorPicker beside TUIkitApp and
TUIkitFoundation, so `import TUIkit` gives an app what it gave before. This
file holds the judgement calls the step reached that the plan did not already
settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB4-n — needs your decision.** Nothing has shipped for these.
- **B-SPB4-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB4-n — declined.** With the reason.

## B. Shipped

### B-SPB4-1. TUIkitColorPicker names TUIkitImage as a dependency, and re-exports it

*Package.swift and `Sources/TUIkitColorPicker/Exports.swift` — no API*

The plan's map gives TUIkitColorPicker every lower module ("all (uses
Image)": `rules.json` has no `lower` list for it), and the step's brief asked
for an explicit TUIkitImage edge only if that list said so. It says nothing
either way, and TUIkitFoundation re-exports TUIkitImage today, so the module
would build on TUIkitFoundation alone.

**Shipped: the edge is explicit.** `.target(name: "TUIkitColorPicker",
dependencies: ["TUIkitFoundation", "TUIkitImage"])`, and its Exports.swift
`@_exported import`s both, as plan §4 (Q4) has each module re-export its
direct dependencies. Three reasons, all checked in the tree: the two curve
editors `import TUIkitImage` themselves; TUIkitImage's `ASCIIToneCurve`
(`Sources/TUIkitImage/ASCIIToneCurve.swift`) is in their public initializers
(`ToneCurveEditorPanel(stops:isPresented:)` takes `[ASCIIToneCurve.Stop]`,
`ChannelCurveEditorPanel(channels:isPresented:)` an `ASCIIToneCurve.Channels`),
so `import TUIkitColorPicker` alone must give an app that type; and step B5c
removes TUIkitImage from TUIkitFoundation's dependencies (plan §5), at which
point the transitive route goes away. TUIkitAppKit, the other target built on
TUIkitFoundation that uses TUIkitImage directly, already names both.

**The other version:** `dependencies: ["TUIkitFoundation"]` and one
re-export, leaving B5c to add the edge. **Price:** nothing now, and one more
line for B5c to remember. The explicit edge orders nothing new: TUIkitImage
already builds before TUIkitFoundation, which depends on it, so
TUIkitColorPicker's job starts at the same point either way.
