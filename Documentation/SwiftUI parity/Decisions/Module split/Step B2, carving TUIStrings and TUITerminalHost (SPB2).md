# Completing the SwiftUI API: decisions from lane SPB2

*Lane SPB2 took step B2 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the first carve, in which TUIStrings and TUITerminalHost
leave TUIFoundation for targets of their own. It changed no public API:
TUIFoundation re-exports both, so `import TUI` gives an app what it gave
before, and an app's `TUI.X` reaches their types through two re-exports
(`UmbrellaQualifiedNameTests`). An app can still see three things, which every
carve changes; they are listed under [What an app can
see](#what-an-app-can-see). This file holds the judgement calls the step
reached that the plan did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB2-n — needs your decision.** Nothing has shipped for these.
- **B-SPB2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB2-n — declined.** With the reason.

## What an app can see

These are not judgement calls: the plan (§5, row C9a) lists all three for the
release notes, and C9a writes them. They are recorded here because this step
made them. Each name below was `TUIFoundation`'s after step B1, and
`TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUIStrings.LocalizationService.Language`,
  `TUIStrings.SystemFormatStyle.Timer`, `TUITerminalHost.TerminalClient`.
  `UmbrellaQualifiedNameTests` pins these three.
- **The resource bundle** is `TUI_TUIStrings.bundle`. An app run from
  its build directory finds it there, as before. An app shipped with the bundle
  copied beside its executable must copy it under the new name. SwiftPM's
  generated `Bundle.module` looks beside the main bundle, then in the build
  directory, and stops the process (`fatalError`) if neither holds the bundle.
  That happens at the first translation the framework looks up, or the first
  read of `tuiKitVersion`. (Read in the generated
  `resource_bundle_accessor.swift`, macOS, debug build.) Since lane BNDL
  (e5445e2cd) the missing bundle no longer stops the process: TUI looks for
  its bundle itself, never through `Bundle.module`, and without it reads its
  own words in English and its version as "unknown" (README, "Shipping a
  program"; decisions BNDL).
- **A saved `NavigationPath.CodableRepresentation`** stores each value's type
  by its mangled name, which names the declaring module. So a saved path
  holding `LocalizationService.Language` or one of the four `SystemFormatStyle`s
  (`Timer`, `Stopwatch`, `DateReference`, `DateOffset`) no longer decodes: it
  throws `DecodingError`, as `codable`'s documentation says. These are the only
  `Codable` public types that moved; TUITerminalHost declares none.
  `NavigationPathCodableTests` pins the module name a saved path now holds.

## B. Shipped

### B-SPB2-1. TerminalHost.swift spells a tmux client's pid `Int32`, not `pid_t`

*`TerminalHost.TmuxClient.pid`, the tmux hook builders — internal, no API*

Step B2 makes TUITerminalHost an advisory step of the Windows lane, and
decisions B-SPA2-5 left `TerminalHost.swift` naming `pid_t` outside any `#if`:
the tmux client's `pid`, `owningApplicationPath(ofTmuxClient:)`'s parameter,
the parse of `#{client_pid}`, and the six builders of hook and unhook
arguments. Windows' C runtime declares no `pid_t` (the premise
`ProcessAncestry.swift` already rests on), so the file could not compile there.

**Shipped: those signatures take `Int32`.** It is the type `pid_t` aliases on
every platform that has one (Darwin, Glibc, Musl, WASI) and the type
`ProcessInfo.processIdentifier` has everywhere, so nothing changes where the
file compiled before: the hook installers lose their `pid_t(pid)` conversions,
and the tests spell their expected pids `Int32`. Only the Darwin walk (the
tmux client's ancestry, `executablePath(ofProcess:)`) still reads a `pid_t`,
inside the `#if canImport(Darwin)` arms it already had. Unmeasured on Windows:
this machine has no Windows toolchain, so the CI lane is the first build there.

**The other version** is B-SPA2-5's: compile the tmux client probe and the hook
builders only where `pid_t` exists, with `nil` and empty Windows arms. It
keeps the POSIX type's name at the cost of four `#if` arms and a TmuxClient
whose stored layout differs by platform, for a probe that never runs on
Windows (`isTmux` reads `TMUX`, which no Windows terminal sets). About an hour,
if the name is wanted back.

### B-SPB2-2. The carved modules' tests stay in TUITests, which `@testable import`s them

*Test layout — no API*

The lower four modules each have a test target that links only that module
(`TUICoreTests` and the rest), so a unit test that leans on a higher layer
does not compile. B2 made TUIStrings and TUITerminalHost modules of the
same kind, and their tests live in `TUITests` beside everything else.

**Shipped: the tests stay where they are.** The 35 test files that reach
either module's internals gained `@testable import TUIStrings` (17) or
`@testable import TUITerminalHost` (18), next to their
`@testable import TUIFoundation`, and `TUITests` names both modules as
dependencies. What the framework itself now reaches across the new boundary is
`package` instead; a test reaching an internal member (an initializer such as
`LocalizationService(configDirectoryPath:)`, a `@TaskLocal` pin such as
`TerminalClient.$drawsBoldPin`) does so through `@testable`, so no declaration
was widened for a test alone.

**The other version:** `TUIStringsTests` and `TUITerminalHostTests`,
each linking only its module and TUICore, with a row each in
`Tools/validate-test-boundaries.sh` and an advisory Windows build like the
lower modules' test targets. **Price:** sorting the 35 files, and more where a
suite also renders (`RendersEnglishUI` and the localized-render suites use the
umbrella's render helpers, so they would stay); how many of the 35 use only
their module was not counted. Two more test bundles to build and link. Worth
doing with the per-module products (step C9b), or when a Windows test build of
these modules is wanted.
