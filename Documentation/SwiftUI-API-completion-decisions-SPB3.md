# Completing the SwiftUI API: decisions from lane SPB3

*Lane SPB3 took step B3 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-08: the carve of TUIkitApp, the first module built on
TUIkitFoundation rather than under it. It changed no public API: the umbrella
re-exports TUIkitApp beside TUIkitFoundation, so `import TUIkit` gives an app
what it gave before, and an app's `TUIkit.X` reaches TUIkitApp's types through
one re-export (`UmbrellaQualifiedNameTests`). What an app can still see is
listed under [What an app can see](#what-an-app-can-see). This file holds the
judgement calls the step reached that the plan did not already settle, in the
format of [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB3-n — needs your decision.** Nothing has shipped for these.
- **B-SPB3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB3-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIkitFoundation`'s after step B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIkitApp.WindowGroup<TUIkitFoundation.Text>`,
  `TUIkitApp.DefaultWindowToolbarStyle`. `UmbrellaQualifiedNameTests` pins
  both.
- **`renderOnce(content:)` is TUIkitApp's** (the plan names it for C9a).
  `TUIkit.renderOnce` and the unqualified name resolve as before.
- **The bundle and saved paths are unchanged.** TUIkitApp holds no resources,
  so the bundle is still `TUIkit_TUIkitStrings` (decisions SPB2); and it
  declares no `Codable` public type, so no saved
  `NavigationPath.CodableRepresentation` changes.

## B. Shipped

### B-SPB3-1. Tests reach TUIkitApp's internals through `@testable import TUIkitApp`, in 479 files

*Test layout, and where `EnvironmentValues.applyRuntimeServices(from:)` lives — no API*

B-SPB2-2 kept the carved modules' tests in `TUIkitTests`, each file that
reaches a carved module's internals gaining `@testable import` of it. Step B3
follows that pattern, at a larger scale: 478 files of `TUIkitTests` and one of
`ExampleTests` (which now names TUIkitApp as a dependency) gained
`@testable import TUIkitApp`, found from the pre-carve index (every test file
that names a non-public declaration of a `Sources/TUIkitApp` file) and
confirmed by the build. No declaration was widened for a test alone.

300 of the 479 need TUIkitApp for one method only:
`EnvironmentValues.applyRuntimeServices(from:)`
(`Sources/TUIkitApp/Environment/ServiceEnvironment+Runtime.swift`), which wires
a `TUIContext`'s services into an environment, and which those tests call to
build the environment a render pass reads. The module map puts it in TUIkitApp
because its two framework callers, `RenderLoop` and `ViewRenderer`, are
TUIkitApp's, although everything it reads and writes is TUIkitFoundation's.

**Shipped: the map as it stands.** The method stays in TUIkitApp, internal.

**The other version:** move `ServiceEnvironment+Runtime.swift` (69 lines) to
`Sources/TUIkitFoundation/Environment/` with a `package` method, so only the
179 test files that reach the run loop itself (`HeadlessApp`, `RenderLoop`,
`InputHandler`, `FrameDiffWriter`, `Terminal` …) import TUIkitApp. **Price:**
a `git mv`, one widened method, the module map re-run (the file has no other
dependents), and dropping the 300 imports; about an hour. The run loop's
once-a-frame call would then cross into TUIkitFoundation, where today it
stays in TUIkitApp (one call a frame; not measured). Worth doing if the
import count bothers anyone; it moves nothing an app sees.
