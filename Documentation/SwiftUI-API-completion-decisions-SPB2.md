# Completing the SwiftUI API: decisions from lane SPB2

*Lane SPB2 took step B2 of the module split
([`Module split plan, revision 4`](Historical/Module%20split%20plan,%20revision%204%20(2026-10-07).md),
§5), 2026-10-08: the first carve, in which TUIkitStrings and TUIkitTerminalHost
leave TUIkitFoundation for targets of their own. It changed no public API:
TUIkitFoundation re-exports both, so `import TUIkit` gives an app what it gave
before. This file holds the judgement calls the step reached that the plan did
not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-SPB2-n — needs your decision.** Nothing has shipped for these.
- **B-SPB2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB2-n — declined.** With the reason.

## B. Shipped

### B-SPB2-1. TerminalHost.swift spells a tmux client's pid `Int32`, not `pid_t`

*`TerminalHost.TmuxClient.pid`, the tmux hook builders — internal, no API*

Step B2 makes TUIkitTerminalHost an advisory step of the Windows lane, and
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

### B-SPB2-2. The carved modules' tests stay in TUIkitTests, which `@testable import`s them

*Test layout — no API*

The lower four modules each have a test target that links only that module
(`TUIkitCoreTests` and the rest), so a unit test that leans on a higher layer
does not compile. B2 made TUIkitStrings and TUIkitTerminalHost modules of the
same kind, and their tests live in `TUIkitTests` beside everything else.

**Shipped: the tests stay where they are.** The 35 test files that reach
either module's internals gained `@testable import TUIkitStrings` (17) or
`@testable import TUIkitTerminalHost` (18), next to their
`@testable import TUIkitFoundation`, and `TUIkitTests` names both modules as
dependencies. What the framework itself now reaches across the new boundary is
`package` instead; a test reaching an internal member (an initializer such as
`LocalizationService(configDirectoryPath:)`, a `@TaskLocal` pin such as
`TerminalClient.$drawsBoldPin`) does so through `@testable`, so no declaration
was widened for a test alone.

**The other version:** `TUIkitStringsTests` and `TUIkitTerminalHostTests`,
each linking only its module and TUIkitCore, with a row each in
`Tools/validate-test-boundaries.sh` and an advisory Windows build like the
lower modules' test targets. **Price:** sorting the 35 files, and more where a
suite also renders (`RendersEnglishUI` and the localized-render suites use the
umbrella's render helpers, so they would stay); how many of the 35 use only
their module was not counted. Two more test bundles to build and link. Worth
doing with the per-module products (step C9b), or when a Windows test build of
these modules is wanted.
