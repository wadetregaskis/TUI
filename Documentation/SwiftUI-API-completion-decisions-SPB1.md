# Completing the SwiftUI API: decisions from lane SPB1

*Lane SPB1 took step B1 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-08: the target that compiles every planned module became
`TUIkitFoundation`, and `TUIkit` became an umbrella that only re-exports. It
changed no public API: `import TUIkit` gives an app what it gave before. This
file holds the judgement calls the step reached that the plan did not already
settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB1-n — needs your decision.** Nothing has shipped for these.
- **B-SPB1-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB1-n — declined.** With the reason.

## B. Shipped

### B-SPB1-1. TUIkitFoundation re-exports the four lower modules

*Module structure — no API*

The single TUIkit module's `Exports.swift` `@_exported import`ed TUIkitCore,
TUIkitStyling, TUIkitView and TUIkitImage. Within a module, those re-exports
put the lower modules' names in scope in every file of it, and the framework's
files lean on that: 482 of the 900 files B1 moves into TUIkitFoundation import
none of the lower modules, and most of them name `FrameBuffer`,
`RenderContext` or `Color` (counted 2026-10-08 with a grep for an
`import TUIkitCore|View|Styling|Image` line; how many of the 482 use a lower
name was not counted).

**Shipped: `Sources/TUIkitFoundation/Exports.swift` re-exports the same four,**
so every file of TUIkitFoundation sees what it saw before, and the umbrella's
`Exports.swift` re-exports TUIkitFoundation and the four again (it must go on
giving them after TUIkitImage leaves TUIkitFoundation at step B5c). This is
the plan's own assumption (§4: "each module `@_exported`-imports its direct
dependencies", plan question Q4), applied to TUIkitFoundation now rather than
at the per-module products step, because B1 cannot compile without it or the
imports below.

**The other version:** no re-export, and an explicit import in each file that
uses a lower module, as MemberImportVisibility asks of members already.
**Price:** an import line or two in up to 482 files now, and the same kind of
edit at each carve that moves a file to a module whose dependencies differ;
and `import TUIkitFoundation` alone would no longer give an importer the
lower modules, which no app can do today anyway (TUIkitFoundation is not a
product). Nothing user-visible changes either way, so it can be revisited at
step C9b, with the per-module products.
