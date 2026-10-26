# Completing the SwiftUI API: decisions from lane SPB3

*Lane SPB3 took step B3 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the carve of TUIApp, the first module built on
TUIFoundation rather than under it. It changed no public API: the umbrella
re-exports TUIApp beside TUIFoundation, so `import TUI` gives an app
what it gave before, and an app's `TUI.X` reaches TUIApp's types through
one re-export (`UmbrellaQualifiedNameTests`). What an app can still see is
listed under [What an app can see](#what-an-app-can-see). This file holds the
judgement calls the step reached that the plan did not already settle, in the
format of [`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB3-n — needs your decision.** Nothing has shipped for these.
- **B-SPB3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB3-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIApp.WindowGroup<TUIFoundation.Text>`,
  `TUIApp.DefaultWindowToolbarStyle`. `UmbrellaQualifiedNameTests` pins
  both.
- **`renderOnce(content:)` is TUIApp's** (the plan names it for C9a).
  `TUI.renderOnce` and the unqualified name resolve as before.
- **The bundle and saved paths are unchanged.** TUIApp holds no resources,
  so the bundle is still `TUI_TUIStrings` (decisions SPB2); and it
  declares no `Codable` public type, so no saved
  `NavigationPath.CodableRepresentation` changes.

## B. Shipped

### B-SPB3-1. Tests reach TUIApp's internals through `@testable import TUIApp`, in 479 files

*Test layout, and where `EnvironmentValues.applyRuntimeServices(from:)` lives — no API*

B-SPB2-2 kept the carved modules' tests in `TUITests`, each file that
reaches a carved module's internals gaining `@testable import` of it. Step B3
follows that pattern, at a larger scale: 478 files of `TUITests` and one of
`ExampleTests` (which now names TUIApp as a dependency) gained
`@testable import TUIApp`, found from the pre-carve index (every test file
that names a non-public declaration of a `Sources/TUIApp` file) and
confirmed by the build. No declaration was widened for a test alone.

300 of the 479 need TUIApp for one method only:
`EnvironmentValues.applyRuntimeServices(from:)`
(`Sources/TUIApp/Environment/ServiceEnvironment+Runtime.swift`), which wires
a `TUIContext`'s services into an environment, and which those tests call to
build the environment a render pass reads. The module map puts it in TUIApp
because its two framework callers, `RenderLoop` and `ViewRenderer`, are
TUIApp's, although everything it reads and writes is TUIFoundation's.

**Shipped: the map as it stands.** The method stays in TUIApp, internal.

**The other version:** move `ServiceEnvironment+Runtime.swift` (69 lines) to
`Sources/TUIFoundation/Environment/` with a `package` method, so only the
179 test files that reach the run loop itself (`HeadlessApp`, `RenderLoop`,
`InputHandler`, `FrameDiffWriter`, `Terminal` …) import TUIApp. **Price:**
a `git mv`, one widened method, the module map re-run (the file has no other
dependents), and dropping the 300 imports; about an hour. The run loop's
once-a-frame call would then cross into TUIFoundation, where today it
stays in TUIApp (one call a frame; not measured). Worth doing if the
import count bothers anyone; it moves nothing an app sees.
