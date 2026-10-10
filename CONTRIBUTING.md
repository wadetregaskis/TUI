# Contributing to TUIkit

TUIkit is a SwiftUI-like framework for building Terminal User Interfaces in pure Swift, with no ncurses or external C dependencies (the only C is the in-tree `stb_image` decoder, used as the image-decoding fallback where AppKit's `NSImage` is unavailable). It targets SwiftUI API parity wherever possible.

## Hard Requirements (non-negotiable)

| Requirement | Details |
|-------------|---------|
| **Swift 6.2** | `swift-tools-version: 6.2`. Language features up to 6.2 are fair game; nothing newer. |
| **Cross-platform** | Must build and run on macOS and Linux. WebAssembly builds and runs (see below); Windows is a work in progress. |
| **CI must pass** | All tests and linting must pass before merge. |

### What CI covers

Every lane runs `swift build`, the test suite, and both smoke tests
(`Stress --selfcheck` everywhere; the PTY walk on macOS and Linux). On macOS
and Linux the suite runs through `Tools/ParallelTest/parallel_test.py -j 4`
rather than `swift test` — see "Running the suite in parallel" below; Windows
runs `swift test`.

The three released Swift versions, 6.2, 6.3 and 6.4, are each covered on every
operating system, and trunk on macOS and Linux:

| Swift | macOS | Linux | Windows |
|-------|-------|-------|---------|
| 6.2 | Xcode 26 on `macos-15` | `swift:6.2-noble` | `swift:6.2-…` |
| 6.3 | Xcode 26 on `macos-26` | `swift:6.3-noble` | `swift:6.3-…` |
| 6.4 | Xcode 27 on `xcode-27` (macOS 27); swift.org 6.4 release on `macos-26` | `swift:6.4-noble` | `swift:6.4-…` |
| main | swift.org trunk snapshot | `nightly-main-noble` | — |

Released Swift comes from Xcode on macOS. 6.4 also runs from swift.org's
release toolchain on `macos-26`, where no Xcode carries it. Trunk comes from
swift.org too: the newest snapshot of `main`, never a release branch's, and
the lane checks the snapshot it installed says so. Windows has no trunk lane because its trunk image is rebuilt too rarely to be
worth reporting as a nightly (on 2026-09-27 it was eleven weeks old).

Until 6.4.0 shipped (2026-09-14) its row was `release/6.4.x` snapshots and
nightlies, advisory; the release images replaced them, and they block. The
next release branch's nightlies take that place when it is cut.

Every released lane takes the newest patch of its line — an Xcode major, a
`swift:6.x` image tag, swift.org's newest 6.4.x — so a patch toolchain arrives
without a workflow edit. It can also break the build without a TUIkit change;
that is accepted, as the price of never testing a stale toolchain.

WebAssembly is built by its own lane, on a pinned 6.3.3 container plus the
matching Swift SDK — pinned because a Swift SDK loads only under the toolchain
version it was built for, and still 6.3.3 because that is the only version the
port has been measured with (see [`Documentation/WebAssembly.md`](Documentation/WebAssembly.md)).

Linux additionally runs Swift 6.3 on arm64, and lint runs on Linux only — it
gates everything else, so a style slip fails in a minute rather than after
eighteen builds.

Three checks run on chosen lanes only:

| Check | Lanes | What it catches |
|-------|-------|-----------------|
| Release build (`swift build -c release`: every library target, Stress, Example and the tools; no tests) | `macOS 26 · Swift 6.4`, `Linux · Swift 6.3 · arm64` | Failures that exist only under `-O`. Every other build in CI is debug; on 2026-10-08 Swift 6.3.3 could not build the library in release while every lane was green. |
| Type-check budget (the library rebuilt with every expression capped at a number of solver scopes, `-solver-scope-threshold`) | `macOS 15 · Xcode 26` (6.2.4) at 2,000; `macOS 26 · Swift 6.4` at 1,500 | An expression that has become expensive to type-check, as a count rather than a time, so a slow runner cannot fail it. The count belongs to the compiler, so each lane's cap sits just above its own compiler's worst expression. |
| Module map (`Tools/ModuleMap`) | `macOS 15 · Xcode 26` | A reference that would cross a planned module boundary upward. It reads the index store the build wrote, and the map is the same on every Swift. |

The workflow's comment on each step has the measurements behind it and says
how to read a failure.

Nightly-toolchain lanes are **advisory** (`continue-on-error`): visible, but
unable to block a merge, because they break for reasons that have nothing to do
with this package. Everything on a released toolchain — including Windows —
blocks.

macOS 27 runs on GitHub's `xcode-27` image (macOS 27.0 with Xcode 27, and so
Xcode's own Swift 6.4), and is required alongside `macos-15` and `macos-26`.
GitHub still labels that image a preview and warns it may queue; a queued
macOS 27 lane holds the `CI` check pending until it runs. When a `macos-27`
label appears, the lane moves to it (see the macOS 27 note at the top of the
workflow).

#### The `CI` gate job

`CI` is a job that runs after everything else and fails if any non-advisory
lane did not succeed. **It is the only check that should be marked as a
required status check in the repository's branch-protection settings**
(Settings → Branches → branch protection rule for `main` → "Require status
checks to pass before merging"). A required check is one GitHub refuses to
merge a PR without.

Requiring it rather than the individual jobs matters for two reasons:

- Matrix job names change whenever the matrix changes, and branch protection
  matches checks *by name*. Requiring them directly means editing repository
  settings every time a Swift version is added.
- A **skipped** job reports as *success* to branch protection. If `macos` were
  required directly and it got skipped — because `lint` failed, say — the PR
  would look mergeable having built nothing. The gate treats `skipped` as a
  failure, so that cannot happen.

### WebAssembly

TUIkit builds for `wasm32-unknown-wasip1`, and the Example app runs in a browser
— `Tools/Web/build.sh` compiles it, `Tools/Web/serve.py` serves it. The CI lane
builds every module and the Example for wasm and is **binding**: what compiles
for WebAssembly today has to keep compiling.

Three things about the toolchain are worth knowing before you try it locally,
because each fails in a way that does not name its cause:

* **Xcode's compiler cannot do it.** It is built without the WebAssembly LLVM
  target and stops at `No available targets are compatible with triple
  wasm32-unknown-wasip1`. Use a swift.org toolchain (`swiftly install 6.3.3`).
* **6.3 is what it has been measured with.** swift.org's 6.2 asserted on
  `TupleView`'s pack conformance, exactly as it did for the Linux static SDK, so
  `TUIkitView` would not build. That conformance no longer asserts
  (`Tools/CompilerBugs/README.md`, section 3), but nobody has built for
  WebAssembly on 6.2 since.
* **`--static-swift-stdlib` is required**, and the SDK must be named by its
  bundle id rather than by the triple. Without the first, Foundation is missing
  from an SDK that contains it; without the second, SwiftPM may pick the
  embedded-Swift SDK that ships in the same bundle and has no standard library.

The port's shape — what needed a platform arm, what does not work in a browser,
and the two latent bugs it turned up in platform-independent code — is in
[`Documentation/WebAssembly.md`](Documentation/WebAssembly.md).

### Windows

Windows is **not supported yet** — the package does not build there in full.
The CI lane is a **ratchet**: every step says for itself whether it is allowed
to fail, so the job as a whole promises exactly *"everything that builds on
Windows today still builds"*. That set can only grow — when a step goes green,
delete its `continue-on-error` and it is binding from then on. When the console
layer lands, the last flag goes and nothing staged is left in the file.

The lane is therefore **required** on released toolchains. Observed state:

| Step | Status |
|---|---|
| `TUIkitCore`, `TUIkitStyling` | pass everywhere — **binding** |
| `TUIkitView` | passes on 6.3+; **fails on 6.2**, cause not yet diagnosed — binding except there |
| `TUIkitImage` | failed everywhere until 2026-08-07; green on all five lanes since, `continue-on-error` removed 2026-09-04 — **binding** |
| `TUIkitStrings`, `TUIkitTerminalHost` | carved out of TUIkitFoundation at module split step B2 (2026-10-08), on TUIkitCore alone; advisory, each with a 30-minute timeout, until CI has seen them green (no Windows build of them yet) |
| `TUIkitFoundation` | held the console layer until module split step B3 (2026-10-08) carved it out as TUIkitApp, so the `TUIkit` step stood for it; advisory, with a 30-minute timeout, until CI has seen it green (no Windows build of it without the console layer yet) |
| `TUIkitChrome`, `TUIkitEffects`, `TUIkitMenus` | carved out of TUIkitFoundation at module split step B5b (2026-10-09), each built on it alone, with no POSIX API (TUIkitEffects' one `#if`, `canImport(Symbols)`, leaves out the `.symbolEffect` modifiers that take Apple's Symbols types); advisory, each with a 30-minute timeout, until CI has seen them green (none can pass before `TUIkitFoundation` does) |
| `TUIkitBitmaps` | carved out of TUIkitFoundation at module split step B5c (2026-10-09), built on it and on TUIkitImage (which TUIkitFoundation no longer depends on since), with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitNavigation` | carved out of TUIkitFoundation at module split step B5 (2026-10-08), built on it, with no POSIX API; it compiled the presentations' directory too, and depended on TUIkitChrome for them (from step B5b), until step C1; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitPresentation` | peeled out of TUIkitNavigation at module split step C1 (2026-10-09), built on TUIkitFoundation and TUIkitChrome, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before both do) |
| `TUIkitLists` | carved out of TUIkitFoundation at module split step B6 (2026-10-08), built on it, with no POSIX API; it compiled the tables', the tabs' and the grids' directories too until steps C2 to C4; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitTables` | peeled out of TUIkitLists at module split step C2 (2026-10-09), built on TUIkitFoundation and TUIkitLists, with no POSIX API; its three `#if`s are `canImport(Darwin)` (a string column's default comparator) and `canImport(UniformTypeIdentifiers)` twice (a table row's item provider), none around a POSIX call; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` and `TUIkitLists` do) |
| `TUIkitTabs` | peeled out of TUIkitLists at module split step C3 (2026-10-10), built on TUIkitFoundation and TUIkitLists, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` and `TUIkitLists` do) |
| `TUIkitGrid` | peeled out of TUIkitLists at module split step C4 (2026-10-10), built on TUIkitFoundation, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitTextInput` | carved out of TUIkitFoundation at module split step B7 (2026-10-09), built on it, with no POSIX API and no `#if`; it compiled search's, the forms', the pickers' and the numeric controls' directories too until steps C5 to C8; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitNumericControls` | peeled out of TUIkitTextInput at module split step C7 (2026-10-10), the last peel, built on TUIkitFoundation alone, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitPickers` | peeled out of TUIkitTextInput at module split step C8 (2026-10-10), built on TUIkitFoundation alone, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitSearch` | peeled out of TUIkitTextInput at module split step C5 (2026-10-10), built on TUIkitFoundation and TUIkitTextInput, and since step C8 on TUIkitPickers, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation`, `TUIkitTextInput` and `TUIkitPickers` do) |
| `TUIkitForms` | peeled out of TUIkitTextInput at module split step C6 (2026-10-10), built on TUIkitFoundation alone, with no POSIX API and no `#if`; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before `TUIkitFoundation` does) |
| `TUIkitColorPicker` | carved out of TUIkitFoundation at module split step B4 (2026-10-08), built on it, on TUIkitImage and (since steps C3, B7, C8, C7 and C1) on TUIkitTabs, TUIkitTextInput, TUIkitPickers, TUIkitNumericControls and TUIkitPresentation (on TUIkitLists from step B6 until C3, and on TUIkitNavigation from step B5 until C1), with no POSIX API; advisory, with a 30-minute timeout, until CI has seen it green (it cannot pass before all five of those do) |
| the four modules' own test targets | advisory, each with a 30-minute timeout |
| `TUIkit`, build-tests, test, smoke | fail until the console layer is ported (TUIkitApp since module split step B3, which has no Windows step of its own: it is POSIX by design) |

Do not take the table on trust — it is a record of what CI did, and the whole
point of binding the lane is that it stays true. `TUIkitImage`'s failure went
unnoticed for as long as the lane was advisory, and this file previously claimed
it passed. It then stayed *advisory in this table* for a month after the flag came
off in CI, which is the same failure from the other end: the ratchet only reads
as a ratchet if the record moves with it.

That failure, for the record, was `ShapeSampling.swift` importing
`Glibc`-or-`Darwin` and then calling `cos`/`sin` unconditionally: on Windows
neither module exists, so there was no `cos` to call. `StackGuard.swift` has the
same two-armed ladder and builds fine, because every *use* there sits behind the
same conditions — which is the distinction to check when adding one.

The known blockers, in rough order of difficulty:

1. **stdin wake-up.** `StdinArrivalStream` uses
   `DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO,…)`.
   swift-corelibs-libdispatch's Windows backend explicitly refuses console
   handles (`FILE_TYPE_CHAR` → `WIN_PORT_ERROR()`), so the whole mechanism has
   to be rebuilt around a thread blocking on `ReadConsoleInput`.
2. **Resize notification.** Windows has neither `SIGWINCH` nor a
   `TIOCGWINSZ` equivalent. Size changes arrive as `WINDOW_BUFFER_SIZE_EVENT`
   records from `ReadConsoleInput`, which is the same call as (1) — so they
   want designing together. Do not plan around the in-band resize escape
   (`CSI ? 2048 h`); it is an unassigned backlog item on Windows Terminal.
3. **Raw mode and VT output.** `GetConsoleMode`/`SetConsoleMode` replace
   `termios`, and VT output must be opted into with
   `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN`.
   `GetConsoleScreenBufferInfo` replaces `ioctl(TIOCGWINSZ)`.
4. **The PTY smoke harness.** Everything in `Tools/Smoke/` — `tui_walk.py`,
   `tui_screens.py`, `raw_probe.py`, `persistence_probe.py`,
   `faded_palette_sweep.py` — uses `pty`/`termios`, so it is POSIX-only; a
   Windows equivalent needs ConPTY. (`faded_palette_sweep.py` runs at `full`
   depth only, and is 7 min 15 s of the 11 min 23 s that costs; §68 of
   `Documentation/Opacity as composition.md` explains what it catches that a
   walk cannot.)
   `Tools/Smoke/ci-pty-smoke.sh` is skipped on the Windows lanes for this
   reason, and they run `Stress --selfcheck` alone.

Two things that are *not* blockers, despite looking like them: `@AppStorage`
already falls back to JSON-file storage off Apple platforms, so the open
Windows `UserDefaults` bug does not affect it; and SwiftLint gained Windows
support in 0.64.0.

## Build, Test & Lint

```bash
# Build
swift build

# Build with Xcode's own toolchain too, if `swift` on your PATH is a swift.org
# one (swiftly puts itself first, and DEVELOPER_DIR does not change that). The
# two differ by more than version: Apple's SDKs build the standard library from
# its PUBLIC interface, so an `@_spi` import of `Swift` sees nothing there, and
# the macOS CI lanes use Xcode's. A separate scratch path keeps the two builds
# from invalidating each other. `xcrun --toolchain XcodeDefault` is not enough
# on its own: while `xcode-select` points at the Command Line Tools it runs
# THEIR `swift` (6.1.2 here, 2026-10-07). Xcode's also takes ~26% less time
# over a clean release build than swiftly's 6.2.4, an assertions build — see
# the README's "Build time".
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --build-tests --scratch-path .build/xcode

# Run all tests (7,591 tests in 1,082 suites, Swift Testing framework)
swift test

# The same tests, in 12 processes instead of 1: 54.1s -> 14.0s (see below)
Tools/ParallelTest/parallel_test.py --calibrate   # once, ~95s
Tools/ParallelTest/parallel_test.py -j 12

# Run a single test suite. NOTE: --filter matches the Swift TYPE name, not the
# @Suite display string — `--filter AlertDismissalTests`, not "Alert dismissal".
swift test --filter <TestSuiteName>

# Lint (must report zero violations)
swiftlint

# Format (configured but not enforced in CI)
swift-format format -i -r Sources Tests

# Build the documentation (one archive covering every module)
Tools/BuildDocs/build-docs.sh            # add --analyze for every diagnostic
```

> Use the script, not `swift package generate-documentation --target TUIkit`.
> The latter documents only what the umbrella module itself declares, which
> is nothing: `View`, `Color`, `Binding`, `Text` and everything else are
> declared in the modules it re-exports — see [`Tools/BuildDocs/README.md`](Tools/BuildDocs/README.md).
> Swift Package Index does build that way, a target at a time, which is why
> `.spi.yml` lists every library module, the umbrella first; the docs build
> fails if one is missing.

## Running the suite in parallel

`swift test` runs the suite in one process. 81% of the tests are in
`@MainActor` suites, so they queue on that one actor: 77% of the CPU in the
late part of a run is `syscall_thread_switch` and friends — threads taking
turns, not working. `Tools/ParallelTest/parallel_test.py` splits the suite
across processes, each with its own main actor. Re-measured here (12 logical
cores / 16 GiB) after the test splits in `a7bdea3f` and `638dd69f`, as the
suite time each command reports for itself:

| command | median suite wall | reps | sd | speedup |
|---|---:|---:|---:|---:|
| `swift test` | 54.10 s | 4 | 2.50 | 1.00x |
| `Tools/ParallelTest/parallel_test.py -j 6` | 20.73 s | 6 | 0.74 | 2.61x |
| `Tools/ParallelTest/parallel_test.py -j 8` | 17.32 s | 4 | 0.55 | 3.12x |
| `Tools/ParallelTest/parallel_test.py -j 12` | **13.96 s** | 10 | 0.59 | **3.88x** |

That is −40.1 s a run at `-j 12`, or ~6.7 hours across a 600-run landing batch.
Three paired reps with the arm order randomised agreed on all three arms:
`-j 6` − `-j 12` = +6.64 s, `-j 8` − `-j 12` = +3.47 s, `swift test` − `-j 12`
= +40.14 s, each with the same sign in every rep. The ±2.4 s band this repo
quotes for wall-clock noise is a SINGLE-PROCESS figure — the harness arms
repeat far more tightly, which is what makes the 3.5 s between `-j 8` and
`-j 12` readable at all.

**The curve has not flattened at 12.** The harness prints the floor as part of
its plan — today `popUpReachesItsLastRowAtItsLongest(count:)`, 3.85 s alone, so
`-j` beyond 28 cannot help — but `-j 12` is nowhere near it: the run reaches
10.2x cores on a 12-core machine, so what binds is the machine, not the slowest
test. More cores would keep paying until about 28.

Add ~1.5 s of enumeration, planning and reconciliation for the wall you
actually wait for, plus the incremental build — 0.1–0.8 s if the last thing you
ran was another harness run, but **6.5–7.2 s on the first `swift build
--build-tests` after a `swift test`** (5 of 5 observed; two consecutive builds
with nothing between them cost 0.3 s). A repeat `-j 12` run therefore lands
around 16.3 s of wall, against ~62 s for `swift test`.

Memory at `-j 12` on 16 GiB: the twelve test processes peaked at 2,576 MiB of
combined RSS, the largest single one 265 MiB. `swift test` peaks lower in total
(1,177 MiB) but far higher in one process (1,031 MiB). No arm touched swap —
`vm.swapusage` read `total = 0.00M` before, during and after every run, the
compressor never moved, and there were no swapins or swapouts. `-j 12` is
comfortable here; the ceiling is cores, not RAM.

**CI's macOS and Linux lanes use it**, at `-j 4`, since single-process
`swift test` runs there had grown to 290–650 s and one of them outlasted a
test's 600 s sleep (see the comment on the macOS Test step in
`.github/workflows/ci.yml`; `-j 4` is an experiment, and the arm64 macOS
runners' 7 GB is the thing to watch). The Windows lanes still run `swift
test`. The harness runs every test, and fails loudly unless the union of test
IDs returned by its processes matches the enumerated suite exactly, so a
process that quietly ran nothing cannot be mistaken for a pass. That identity
check held in all 25 full-suite runs behind this section: 7,591 tests, 1,082
suites, 21 known issues, nothing missing, extra or duplicated. Two of the 25
did print a reconciliation problem, but it was a gap in how the harness parsed
a summary line — since closed, and recorded in its README — and not a test
that failed to run.

Because the tests are spread differently, anything depending on the
interleaving one process happens to give it can behave differently — that is a
property of the test. [`Tools/ParallelTest/README.md`](Tools/ParallelTest/README.md)
records the tests known to do that today, the flakes seen while measuring, and
why weights are measured serially rather than taken from the timings
swift-testing reports.

## Pull Request Requirements

1. Branch from `main`
2. Fill in the PR template completely
3. The `CI` gate check must be green — it covers macOS, Linux and, on
   released toolchains, Windows; only the nightly-toolchain lanes are
   advisory (see "What CI covers" above)
4. No new SwiftLint warnings
5. Follow the architecture and API rules below

## Architecture

### SwiftUI API Parity

Public APIs **must** match SwiftUI signatures exactly unless terminal constraints require deviation (document why in comments).

| Aspect | Requirement |
|--------|-------------|
| Parameter names | Exact (`isPresented`, not `isVisible`) |
| Parameter order | Exact (title, binding, actions, message) |
| Parameter types | Match closely (ViewBuilder closures, not pre-built values) |
| Trailing closures | `@ViewBuilder () -> T`, not `String` |

**Before implementing any SwiftUI-equivalent API:** Look up the exact SwiftUI signature first.

### View Architecture

- Every **public** control must be a `View` with a real `body: some View`
- The `body` must return actual Views (not `Never`, not `fatalError()`)
- `Renderable` is only for leaf nodes (`Text`, `Spacer`, `Divider`), private `_*Core` views, layout primitives, and modifier infrastructure — never public controls
- All modifiers must propagate through the entire View hierarchy
- Environment values must flow down automatically

### General Principles

- No singletons
- Built-in views draw with the palette's roles, never a literal colour, unless
  the colour is content (an image, a swatch, a user's gradient). SwiftLint's
  `framework_colour_literal` rule flags a new literal in `Sources/TUIkitView`
  and in every directory of the module split (`Sources/TUIkit`,
  `Sources/TUIkitFoundation` and the others Tools/ModuleMap/rules.json
  lists), not in the other targets (TUIkitCore, TUIkitStyling, TUIkitImage,
  TUIkitAppKit, the macros, the width corpus); see "What built-in controls
  draw with" in the Theming Guide article
- Search the codebase for similar patterns before implementing anything new
- Consolidate and reuse before adding new functions or types

### Crossing a module boundary

The module split (Documentation/Historical/Module split plan, revision 4) puts
code that was one module into several, and a call between two of them is
compiled differently from a call inside one. These rules keep that from costing
anything at run time:

- **Import what a file uses, in the file.** A module carved out above
  TUIkitFoundation re-exports it from its `Exports.swift`, which is enough to
  compile, but Swift gives every closure passed to a module that the calling
  FILE does not import (directly, or through a module it imports that
  re-exports it) a run-time check that it runs on the main actor. So each file
  of such a module imports TUIkitFoundation, and any other carved module it
  uses, itself. Tools/ModuleMap's `imports` check fails CI on a file that
  does not, and its `stale-imports` check on one that still imports a
  carved module it names nothing of (a peel leaves those behind).
- **Widen an accessor, never a class's stored property.** A stored property
  of a class (or a `static var`, or a global) that another module can see is
  one the optimiser cannot prove free of overlapping accesses, so every
  access to it keeps a run-time exclusivity check (`swift_beginAccess`), this
  module's own included (AccessEnforcementWMO). When another module needs it,
  keep the stored property private, as `_name`, and give that module a
  `package` computed property (`package var name: T { get { _name } set {
  _name = newValue } }`) or method over it, not `@inlinable`, as
  `FocusManager.currentPaneID` does; move a property observer to the
  storage. Never mark the stored property `package` or `@usableFromInline`,
  either of which makes it visible outside the module, unless the binary
  shows every access to it is already dynamic. The optimiser decides per
  property, all or nothing, so one `swift_beginAccess` on the property in
  its own module's functions shows that every access to it is checked
  (read with `otool -tV` from a release `Stress` that links those
  functions: the call's address is the object plus the property's field
  offset). Without such a call the property is statically enforced, whether
  or not the class's other properties are checked, and widening it adds a
  check to every access. A property checked already costs nothing more
  when widened, and an `@inlinable` accessor over it is then how a hot read
  from another module avoids a call. `LazyListRowContent.cached` is one such
  property, and four of `ItemListHandler`'s are more (step C2: `tableRowMemo`
  and `returningRows`, which a table in TUIkitTables reads for every row it
  draws, `reorder` and `outlineActivation`); each one's doc comment holds the
  evidence. Even so, measure before widening one: a widened stored property
  also gets a getter, setter and `modify` of its own, for its property
  descriptor, each with a check (code nothing calls), where private storage
  under an accessor is usually statically enforced (ten of the twelve
  `ItemListHandler` properties step C2 tried both ways lost every check).
  Struct fields are not affected.
  A settable property requirement of a `package` protocol hands out its
  class conformers' stored properties the same way; ask for a method that
  sets it instead (`PersistedFocusable.repoint(focusID:)`).
  What the split widened complies, steps B2 and B3's included, which
  predate the rule and were converted after it. Some class stored
  properties were `package` before the split began, most of them
  `RenderCache`'s in TUIkitView: they are owed the same conversion; do not
  copy one.
- **No stored-property default under an `@inlinable` initializer** whose
  value is more than a literal scalar (an empty array, say): a default is a
  function of its own that every initializer runs, and inlined into another
  module the initializer calls it out of line. Assign the value in each
  initializer instead; assigning it while keeping the default changes
  nothing (`ClaimingRow.claims`).
- **An `@inlinable` member needs a type the other module can name.** A
  member of a type that is only `package` gets no body another module can
  inline (the client sees it as `package_external`) and is called out of
  line whatever its attribute says. So the type is `@usableFromInline`, as
  are the stored properties the body touches, and it states `Sendable`
  itself: the compiler infers `Sendable` only for a type that is not usable
  from inline code (UsableFromInlineSendabilityTests pins each one).
  `@inline(__always)` alone does not cross a module either: it reaches only
  callers in the declaring module, so a `package` function that was always
  inlined becomes an out-of-line call from the module that a split moves its
  caller to. Make it `@inlinable` too (step C2: `ScrollRowWindow.resolve`,
  which a table calls every frame with a per-row closure).
- **Build a view in the module whose `some View` results it uses, when
  those results name types the caller cannot see.** A function's opaque
  result (`some View`) is concrete in a caller in another module only if
  every type its underlying type names is `package` or public: at Swift
  6.2.4 a client of a module not built for library evolution substitutes
  the underlying type only when each of those types' effective access is
  above `internal` (TypeSubstitution.cpp L925–929 and L988–994), and
  otherwise keeps the opaque type (L1036–1047). The caller then asks the
  runtime for the type and its conformances
  (`swift_getOpaqueTypeMetadata2`, `swift_getOpaqueTypeConformance2`), and
  the runtime finds the type by demangling its name each time it is asked.
  How often it is asked depends on where the compiler puts the question,
  which only the binary shows. In the calling function itself, every call
  asks: the inline menu's column did, in its getter and in
  `planMenuColumn`. In a lazy accessor that keeps what it finds (a `…Wl`
  lazy witness-table accessor), the process asks once: `_MenuPopupCore`'s
  `focusable(_:)` result does. Inside the callee's module the same call is
  concrete. A `some View` that the result itself returns from another
  function counts too: that function must be above `internal`, and its own
  underlying type is checked the same way. Step B5b's carve met this: it
  moved the inline menu's column into TUIkitMenus, where it called
  `bordered`, whose result names the internal `_BorderRings`, and
  `foregroundStyle(_:)`, whose result names the internal
  `_StyleEnvironmentView`, and resolved both on every draw. The column is
  TUIkitFoundation's again, and `_InlineMenuCore` is `package` for
  `InlineMenuStyle` to make. So keep caller and callee in one module, or
  give the other module a concrete entry point: a non-generic `package`
  function that builds the view where its types are concrete. When the view
  it modifies is one of the caller's own types, which the callee's module
  cannot name, the entry point is generic over it: a `package` method on
  `View`, as step B7's are (TUIkitFoundation's
  View+BuiltForAnotherModule.swift, for a text field's frame, a form's `if`
  groups and grouped section boxes, a search token and a text editor's find
  bar). The caller then reaches it unspecialised (the second class, below),
  and one that returns an `AnyView` boxes its result on every call, and the
  `AnyView` probes the render cache on each draw and measure of it
  (TUIkitView's `contentContext(noting:)`). That is likely cheaper than the
  lookup, which demangles a name, but unmeasured per call (the carve's A/B
  prices it), and it is paid on every render pass, so the commit names the
  scenarios that reach it. Do not widen the underlying type, nor make the
  callee `@inlinable`, to make it visible: either lets every app see through
  the same modifier as well, which changes the app's own code. The same
  column showed a second class, with the same remedies: a generic function
  (a protocol extension's method is one, generic over `Self`) reaches
  another module only as a call to its unspecialised entry, unless its body
  crosses too, which `@inlinable` does, and which conservative cross-module
  optimisation does only for a small public function; `bordered` is not
  public, so the column called it unspecialised. A release `Stress` shows
  both (`otool -tV`): the `swift_getOpaqueType…` calls, in the caller (each
  call pays) or in a `…Wl` accessor (once), and a `bl` to the generic entry
  where a `specialized` copy would be.

## Code Style

- Line length: 160 characters (warning), 200 (error)
- 4-space indentation
- Trailing commas in multi-line collections
- See `.swiftlint.yml` and `.swift-format` for full configuration

## Testing

- Uses Swift Testing framework (`@Test`, `#expect`, `@Suite`)
- **Tests run in parallel, and every suite of every test target shares one
  process.** `.serialized` orders a suite's own tests, not other suites, so it
  does not protect process-wide state. Other tests read that state on other
  threads. Restoring a value does not help either, because its generation
  counter has already moved. So a test never writes, in the shared process:
  the width traits, the reported colours, link, picture or URL-opening
  support, the `TerminalClient` knobs that republish them, the latest
  storage failure and its count (`StorageDiagnostics.report` and `reset`),
  or the environment. Instead it does one of three things:
  - pins the value for its own task (`TerminalWidthTraits.withTraits`,
    `TerminalColors.withCurrent`, `ColorDepth.withCurrent`,
    `TerminalHyperlink.withSupport`, `KittyGraphics.withSupport`);
  - poses the question on arguments (`ColorDepth.detect(environment:)` and
    its siblings);
  - if the publication itself is the subject, writes the value through
    `ProcessWideState` inside an exit test (`#expect(processExitsWith:)`). An
    exit test's body runs in a child process of its own.
  SwiftLint's `process_wide_write_in_tests` forbids the raw writes, and
  `ProcessWideState` refuses a write made outside an exit test. See
  `Tests/TUIkitTests/TestHelpers/ProcessWideState.swift` for the two flakes
  this came from.
- **A test that asserts the framework's own UI words** — "No items", "dismiss",
  "Done" — depends on the language `LocalizationService.shared` picked from
  `LANGUAGE` / `LC_ALL` / `LC_MESSAGES` / `LANG`. Declare that on the suite with
  `.rendersEnglishUI` (see `Tests/TUIkitTests/TestHelpers/RendersEnglishUI.swift`),
  which pins English for the process before the suite runs. Without it the suite
  passes for you and fails for anyone whose POSIX locale is not English. Do not
  set a locale variable from inside a test: `LocalizationService.shared` is a
  lazy global whose first touch reads the live process environment, so a
  process-wide `setenv` latches that language for every test that follows.
- **Numbers** in rendered chrome are grouped by `\.locale`, which is republished
  from the app language every frame. A test asserting "4,994" pins
  `environment.locale` explicitly rather than relying on the default.
- Test files mirror source structure in `Tests/TUIkitTests/`
- The four lower library modules also have a test target each
  (`TUIkitCoreTests`, `TUIkitStylingTests`, `TUIkitViewTests`,
  `TUIkitImageTests`) that links **only that module**, so a module test cannot
  reach across a layer boundary. Put a test in the module target it belongs to;
  `Tests/TUIkitTests` is for integration tests and the modules with no test
  target of their own: `TUIkitFoundation` (the substrate) and the modules
  carved out of it, `TUIkitStrings` and `TUIkitTerminalHost` (step B2),
  `TUIkitApp` (step B3), `TUIkitColorPicker` (step B4), `TUIkitNavigation`
  (step B5), `TUIkitLists` (step B6), `TUIkitChrome`, `TUIkitEffects` and
  `TUIkitMenus` (step B5b), `TUIkitBitmaps` (step B5c), `TUIkitTextInput`
  (step B7), `TUIkitPresentation` (step C1, peeled out of
  `TUIkitNavigation`), `TUIkitTables`, `TUIkitTabs` and `TUIkitGrid`
  (steps C2 to C4, peeled out of `TUIkitLists`), and `TUIkitForms`,
  `TUIkitSearch`, `TUIkitPickers` and `TUIkitNumericControls` (steps C5 to
  C8, peeled out of `TUIkitTextInput`).
  A test there imports `TUIkit`, as an app does, and adds `@testable import` of
  each module whose internals it reaches: `TUIkitApp` for the run loop and the
  console layer (`HeadlessApp`, `RenderLoop`, `InputHandler`, `FrameDiffWriter`,
  `Terminal`, and `applyRuntimeServices(from:)`, which builds a render pass's
  environment: 300 test files import `TUIkitApp` for it alone, decisions
  B-SPB3-1), `TUIkitColorPicker` for the colour picker's grids, handlers and
  editors, `TUIkitNavigation` for the navigation containers' (crumbs,
  split-view widths, the inspector), `TUIkitPresentation` for the
  presentations' (sheet detents and sizing, alert buttons, dialog
  suppression),
  `TUIkitLists` for the lists' (`ItemListHandler`, row bands and
  reordering), `TUIkitTables` for the tables' (table columns), `TUIkitTabs`
  for the tabs' (tab bars), `TUIkitGrid` for the grids' (grid tracks),
  `TUIkitChrome` for the window chrome's (the status bar view, toolbars,
  notifications, tooltips, the window chrome host), `TUIkitEffects` for the
  transitions' and the visual, scroll and colour effects', `TUIkitMenus` for
  `Menu`'s, `ControlGroup`'s and `.contextMenu`'s, `TUIkitBitmaps` for the
  bitmap path's (`_ImageCore`, `AsyncImage`'s decoding, the image options'
  environment, asset catalogues), `TUIkitTextInput` for the text inputs'
  (`TextFieldHandler`, `TextEditorHandler`, the field renderer),
  `TUIkitPickers` for the pickers' (`_PickerMenuCore`, the radio group's
  handler, the date picker's model), `TUIkitNumericControls` for the numeric
  controls' (`SliderHandler`, `TrackRenderer`, the indeterminate renderer),
  `TUIkitForms` for the forms'
  (`FormContentExtraction`, a card's or panel's title), `TUIkitSearch` for
  search's (the search presentation, dismissal and scope bar),
  `TUIkitStrings` or
  `TUIkitTerminalHost` for theirs, and `TUIkitFoundation` for the rest. A declaration's module is its directory's: each directory under
  `Sources/` is a target of its own in `Package.swift`, at its default path,
  since step C7 peeled the last member out of the last coarse group, a
  target that named several directories.
  (`Sources/TUIkitPresentation` compiled into `TUIkitNavigation` from step
  B5 until step C1, `Sources/TUIkitTables`, `TUIkitTabs` and `TUIkitGrid`
  into `TUIkitLists` from step B6 until steps C2 to C4, and
  `Sources/TUIkitForms`, `TUIkitSearch`, `TUIkitPickers` and
  `TUIkitNumericControls` into `TUIkitTextInput` from step B7 until steps C5
  to C8.)
  `Tools/validate-test-boundaries.sh` checks the four modules' targets and runs
  in CI.
- `Tests/ExampleTests` holds tests of the Example app's own views
  (`@testable import Example`), for when a test must drive what the app
  ships rather than a copy of its shape: a copy goes on passing after the
  app's view is changed back.
- To run the whole suite faster while developing, see "Running the suite in
  parallel" above. CI runs the suite the same way on macOS and Linux (`-j 4`),
  and plain `swift test` on Windows.

## The `project-template/` directory

`project-template/` is a starter kit for spinning up a new app built on
TUIkit (a `tuikit` scaffold plus an `install.sh` and its own README). It
is intentionally kept **inline in this repository** rather than split into
a separate repo: it's small, low-churn, and easiest to keep in step with
the library when it lives alongside it. It is excluded from source
archives / GitHub release tarballs via `export-ignore` in `.gitattributes`,
so it adds no weight for SwiftPM consumers. If it ever grows enough to
warrant independent versioning, revisit moving it out.

## Detailed Architecture Rules

For comprehensive architecture documentation including the `_*Core` pattern, focus system, state management, and interactive view rules, see [`.claude/CLAUDE.md`](.claude/CLAUDE.md).
