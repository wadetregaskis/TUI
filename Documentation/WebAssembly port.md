# WebAssembly

TUI builds for `wasm32-unknown-wasip1`, and the Example app runs in a
browser. This file is the record of what that took, what works, what does not,
and why — the same kind of record `Terminal compatibility survey.md` keeps for
terminals.

    Tools/Web/build.sh      # builds Example.wasm and collects its resources
    Tools/Web/serve.py      # serves them with the headers the page needs
    open http://127.0.0.1:8000/

`build.sh --package-path ~/MyApp --product MyApp` builds another app for the same
page; the DocC article *Running Your App in a Browser* is the guide for an app's
author, and `Tools/Web/README.md` lists the page's settings.

## The toolchain, and why it is not the one you already have

Three things have to line up, and two of them are not obvious.

1. **A swift.org toolchain, not Xcode's.** Xcode's compiler is built without
   the WebAssembly LLVM target: it does not fail to *link*, it stops at
   `No available targets are compatible with triple wasm32-unknown-wasip1`
   while compiling the first file.
2. **6.3 or newer.** 6.3.3 builds the whole package, and it is the only version
   this has been measured with. swift.org's 6.2.4 is an assertions build, and
   it aborted on `TupleView`'s `@preconcurrency` pack conformance
   (`SILGenPoly.cpp`, `isPreconcurrency`) — the same assertion that blocked the
   Linux static-SDK check. `TupleView` now spells that conformance in a way that
   does not abort (see `Tools/CompilerBugs/README.md`, section 3), but whether
   6.2.4 builds for WebAssembly since has not been measured.
3. **A Swift SDK whose version matches the toolchain exactly.** A 6.2.4 SDK
   under a 6.3.3 toolchain fails to load the standard library.

```sh
swiftly install 6.3.3
swift sdk install \
  https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum <published by swift.org>
```

Two flags are not optional. `--static-swift-stdlib` is what points the compiler
at the SDK's `swift_static` resources, and without it Foundation is missing
(`no such module 'Foundation'`, from an SDK that plainly contains it). And the
SDK must be named by its *bundle id* — `--swift-sdk swift-6.3.3-RELEASE_wasm` —
not by the triple: the artifact bundle installs an embedded-Swift SDK under the
same triple, SwiftPM picks between them arbitrarily, and the embedded one has no
standard library to find.

## What had to change in the framework

Very little in the four lower modules, which is the dividend of the rule that
keeps POSIX above them: `TUICore` built for wasm unchanged, and
`TUIStyling`, `TUIView` and `TUIImage` needed one fix each.

| Where | What | Why |
|---|---|---|
| `ShapeSampling` | a `WASILibc` arm on the libm ladder | `cos`/`sin` are C, and an unnamed platform gets no `cos` — the same failure Windows had |
| `BodyMutationDiagnostic` | `Thread.current` → a token | Foundation has no `Thread` where the platform has no threads |
| `ImageLoader` | the remote-image path is gated | `URLSession` is in neither Foundation nor FoundationNetworking on WASI, and wasip1 has no sockets to use it with |

The work was above them, in what was then one module, TUI. Its files are
TUIFoundation's since module split step B1, except the tmux queries below,
which are TUITerminalHost's since step B2, and the console layer below
(`SignalManager`, the stdin notifier, `Terminal`, `SystemClipboard` and
`SystemURLOpener`), which is TUIApp's since step B3. `Dispatch` does not
exist on wasip1, and it was imported into six files — mostly to read a clock.
`MonotonicClock` (in `TUICore`) replaced
`DispatchTime.now().uptimeNanoseconds` at a dozen call sites, which removed the
dependency from every file that only wanted to measure an interval. What
remained genuinely needed a platform arm:

| Subsystem | On WASI |
|---|---|
| `SignalManager` | a whole stub: no signals, no job control, no resize notification |
| `StdinArrivalNotifier` | `poll` — one call that waits on stdin *and* a timeout, which is exactly what the dispatch-source-plus-`Task.sleep` race was emulating |
| `Terminal` raw mode | the `termios` calls go; every escape sequence stays, because bracketed paste, mouse tracking and the modifier-key mode are the terminal's business, not the kernel's |
| `Terminal` size | no `ioctl`, so `COLUMNS`/`LINES` from the environment, which come first everywhere |
| `SystemClipboard`, `SystemURLOpener`, tmux queries | stubs: all three are subprocesses, and wasip1 cannot start one |
| `@AppStorage`'s file backend | writes inline instead of on a queue, and non-atomically — WASI's Foundation refuses `.atomic`, which needs a temporary file |

## Two bugs the port found in code that was not WebAssembly's

Worth recording, because both were latent everywhere:

- **`MonotonicClock`'s first reading.** Written as `SuspendingClock.now - epoch`
  with `epoch` a lazily-initialised `static let`, Swift evaluates the left
  operand first — so the very first call reads the clock, *then* initialises the
  origin from a later reading, and subtracts a larger number from a smaller one.
  The negative `Duration` has `seconds == 0` and negative attoseconds, walks
  past a `seconds >= 0` guard, and traps converting to `UInt64`. It aborted the
  first WebAssembly launch on its first frame and would have been a rare
  unreproducible crash anywhere.
- **Bundle resources are found by path, not by name.** `Bundle.module` resolves
  on WASI, but `url(forResource:withExtension:subdirectory:)` returns `nil` for
  a file that is sitting in the bundle directory. The symptom is quiet: the
  framework's own strings render as their keys (`statusbar.quit` across the
  status bar) and `tuiVersion` reads `unknown`. `ModuleResources.url(named:
  extension:subdirectory:)` asks by name first and works it out from the bundle
  URL second.

## Running it in a browser

The demo is three files under `Tools/Web/site/` and one non-obvious constraint.

**The program blocks, so it runs in a Worker.** A terminal app spends its life
in `poll_oneoff` waiting for a keystroke; that has to be a real block, or the
Swift runtime spins, and a real block on the main thread is a frozen tab. The
worker parks with `Atomics.wait` on a `SharedArrayBuffer` the page shares with
it, and the page wakes it by bumping a sequence word when a key arrives. This is
why the page must be **cross-origin isolated** — `SharedArrayBuffer` does not
exist otherwise — and why `serve.py` exists rather than a line in a README
telling you to use `python3 -m http.server`. A host that cannot send the
headers, such as GitHub Pages (where the demo is published, see
`Tools/Site/README.md`), gets them from `isolation-sw.js`: a service worker,
installed when the visitor presses Run, that adds them to every response from
the demo's directory, after which the page reloads once and arrives isolated.

Three details in `wasi.js` are load-bearing, and each one was a bug first:

- **stdout is flushed before the guest blocks, not on a microtask.** `_start()`
  does not return while the app is running, so anything queued behind the
  current task never runs: the first version batched output into
  `queueMicrotask` and drew a blank terminal with every frame sitting in a queue.
- **`fd_read` on stdin never blocks; it returns `EAGAIN`.** That is what raw
  mode gives a POSIX guest (`VMIN`/`VTIME` of zero), and it is what TUI's
  drain loop expects. A blocking read parks the worker inside a call the guest
  expected to return at once, and the app draws one frame and freezes.
- **`poll_oneoff` reports an fd subscription ready only when bytes are queued.**
  A guest told stdin is readable reads it, and the read has to have something
  behind it.

**The terminal fills the page, and says when that changes.** The page measures
how many cells fit (`@xterm/addon-fit`) and starts the guest with that in
`COLUMNS`/`LINES`. wasip1 has no `ioctl` and no SIGWINCH, so a later size goes
down the keystroke ring as the in-band resize report a terminal sends under mode
2048, `ESC [ 48 ; rows ; columns ; 0 ; 0 t`, which the input parser takes for the
new size (`Terminal.windowSizeReport`). A report outranks the two variables, so a
guest started with them still follows the page.

**A wait is cut into slices, and the host cuts the executor's sleeps short.** A
`poll` holds the only thread, so no `Task.sleep` ends during one: waiting for a
key with no timeout stopped every animation driven by a task until the next key
or mouse report. `StdinArrivalNotifier` polls for 8 ms at a time and yields
between. And the yield needs help, because `CooperativeExecutor.runUntil` (6.3.3,
and still on `main` on 2026-11-01) sleeps until its next timer without looking at
its run queue: with a 500 ms timer pending, whatever was ready waited for it, and
the Progress page drew 3 frames a second. Nothing in the guest can get round that,
a task kept waking for the purpose included, since at the moment the executor
decides to sleep that task is itself in the run queue. So `wasi.js` ends any sleep
with no descriptor after 2 ms, and the executor goes round again. Another WASI host
gets the stalls.

**`Int` is 32 bits.** Seconds since 2001 times a rate does not fit, and converting
it traps: that was the Text Styles page, which then filled the terminal with the
stack trace. A trap now resets the terminal and says so in one line, with the
stack in the browser's console.

**The stack has to be raised at link time.** A view tree renders by recursion,
and wasm's default linear-memory stack runs out inside the Example's deeper
pages. `Tools/Web/build.sh` links with `-z stack-size=16777216`.

## What works, and what does not

Works: the whole Example — every page, the focus ring's pulse, animations,
gradients, the mouse, pictures, resizing, `@AppStorage` within a session, all seven
languages, and a clean exit on ⌃Q.

**The WebGL renderer, for the block elements.** xterm.js's default renderer draws
box drawing and block elements from the font, as DOM text, so a three-row button's
quadrant corners are whatever the font and the browser's line box make of them. The
WebGL renderer (`@xterm/addon-webgl`) draws those characters itself to fill the cell.
The page falls back to the default where WebGL2 is missing or its context is lost.

**Emoji need an addon, and this is not optional.** xterm.js ships Unicode 6
width tables, under which an emoji is one cell: the glyph is drawn clipped and
every character after it on the row sits one column left of where the app put
it. The demo loads `@xterm/addon-unicode-graphemes` and sets
`terminal.unicode.activeVersion = "15-graphemes"`, which replaces the tables
and clusters by grapheme. Measured over the shared width corpus, that takes
xterm.js from 33 of 78 clusters to 61 — second only to Ghostty's 63 among the
terminals this project has measured, and ahead of iTerm2, Apple Terminal and
Warp. `addon-unicode11`, the more obvious choice, is *worse than nothing* (31):
it widens emoji but cannot cluster, so every ZWJ sequence counts as its parts.
`Tools/Web/glyph-probe.html` is the measurement; §"xterm.js — the browser" in
`Terminal compatibility survey.md` is the record.

Does not, and why:

| | |
|---|---|
| Remote images | no sockets. A file image works; `Image(url:)` reports that the platform has no URL loading. |
| Clipboard | the page has one; the guest cannot reach it. OSC 52 lets the *terminal* do it, and TUI sends it where the terminal is known to write it (`Terminal compatibility survey.md`, "OSC 52 clipboard writes"); xterm.js writes it only with its clipboard addon, which TUI cannot see, so a copy says "Not copied" unless `TUI_OSC52=1` says the page has the addon. |
| Opening links | no subprocess. OSC 8 hyperlinks still work, because the terminal opens those, not the app: the page opens one in a new tab, as well as whatever the app does with the click. |
| Terminal graphics | the released xterm.js implements no picture protocol at all, so the handshake gets silence and pictures fall back to cells. The beta image addon (with the beta core) *acknowledges* Kitty and decodes the pixels but does not place a virtual placement — the only kind TUI emits — so turning it on draws blank space where the ramps belong. Measured; see the xterm.js section of `Terminal compatibility survey.md`. |
| Some glyph widths | 29 of 145 corpus clusters still disagree with the framework even with the addon — newer emoji than its Unicode 15 tables, SF Symbols (private-use codepoints have no width anywhere), and Indic vowel signs. The SF Symbols page will shift; no terminal measured does better on that row. |
| Grapheme-clustering mode | `DECRQM ?2027` answers "not recognised", so the framework keeps its own advance model rather than pinning the terminal's. |
| Size on disk | 88.3 MB of wasm, 27.8 MB gzipped (`gzip -9`): 40.3 MB of data and 32.2 MB of code, almost all of it Foundation and ICU, and a 14.7 MB `name` section (function names, for stack traces; without it, 73.0 MB and 25.5 MB gzipped). Measured 2026-10-24, 6.3.3 release build, no `wasm-opt`; it was ~50 MB earlier in the port. |

## The build's shape

`build.sh` writes `Tools/Web/site/manifest.json`, which maps each resource file
to the absolute path the binary expects it at. That path is the developer's own
build directory, because SwiftPM compiles the bundle's location into the binary
and there is no way to ask it to look elsewhere — the manifest is regenerated on
every build, so it stays true, but a site built on one machine will not find its
resources on another. Anyone shipping this properly should embed the resources
instead. TUI's own bundle is the exception (B-BNDL-4, the owner's ruling of
2026-11-09): TUI looks for it beside the program, as on every other platform,
and runs with its words in English where it is not there, never stopping. So
the manifest serves it at `/` too, beside the program (`argv[0]` is a bare
name). Checked in the browser that night: Deutsch reads "↩ auswählen" and
"⌃Q beenden"; with the copy beside the program left out of the manifest the
page still runs, in English ("↩ choose", "⌃Q quit"). An app's own resources are
still found only by its own `Bundle.module`, at the build directory's path.

## Toward full support (1.0)

The owner made WebAssembly a 1.0 platform on 2026-11-09 (API-STABILITY point 9: "WebAssembly and Windows need to be
fully working and supported for 1.0"), which is the bar macOS and Linux meet: the whole package builds with zero
warnings, the test suite passes, the Example works, and CI binds all three. [Windows port.md](<Windows port.md>) is
the same record for Windows. Measured 2026-11-09 on macOS with swift.org 6.3.3 and its `wasm` SDK, the only pair
installed; the tests ran under WasmKit, the runtime that ships in the toolchain.

### Where it stands

**The whole package builds, tests included** (`swift build --build-tests --swift-sdk swift-6.3.3-RELEASE_wasm
--static-swift-stdlib`), and CI's `wasm` job now builds it so, binding. Before, it stopped in two tools
(`EmojiBugScanner`'s `termios`, `IdleProbe`'s `posix_spawn`), the `Stress` harness (`Dispatch`, for a clock), 9 of
the 35 test targets, and then the link: `ExampleTests` depends on an executable, which SwiftPM can test only on
macOS and Linux, and on wasm its `main` collided with the test runner's. What the test targets needed:

| Cause | Sites | Now |
|---|---|---|
| Exit tests (`#expect(processExitsWith:)`), unavailable on WASI: no child processes | 61 tests in 30 files | left out, `#if !os(WASI)` |
| A second thread (`Thread`, `Dispatch`) | 9 tests or helpers | left out, or run in place where the point survives |
| Pipes, ptys, signals, process ids, `mkfifo`, helper programs, the call stack | 6 whole files, 14 other sites | left out, `#if !canImport(WASILibc)` |
| A 64-bit `Int` (literals past 2^31; `CGFloat` is a `Float`) | 6 | a 32-bit equivalent, or 64-bit only |
| `UserDefaultsStorage` had no WebAssembly arm | 1 | Linux's arm, a JSON file per suite |
| `ExampleTests` depends on the app | 16 files | the dependency on macOS and Linux only; the tests `#if canImport(Example)` |

Counting the gates that were there before, 225 `@Test` functions are compiled out on WebAssembly: 59 exit tests, 5
that need a thread, 99 that need POSIX, 17 whose values need a 64-bit `Int`, and the 45 of `ExampleTests`.

**The tests run, though not yet as a suite.** `swift test --disable-xctest` runs a filter that touches no resource
bundle (without `--disable-xctest` it asks Xcode's XCTest helper to open the wasm file, and fails). A whole run does
not get far: SwiftPM starts WasmKit with `--dir .`, so the guest cannot see the absolute paths the resource bundles
were compiled to be at, and the first `Bundle.module` stops the run (B-BNDL-4, gap 6). Run directly, with the host's
`/` given to the guest and the module named by its absolute path (a relative one leaves `Bundle.main` unable to
find itself, and it traps), it runs:

    wasmkit run --dir / --stack-size 268435456 \
      --env TUI_CONFIG_DIR=… --env LANG=en_US.UTF-8 --env TERM=xterm-256color --env COLORTERM=truecolor \
      "$PWD/.build/wasm32-unknown-wasip1/debug/TUIPackageTests.xctest" \
      --testing-library swift-testing --no-parallel --filter '^TUICoreTests\.'

One test target at a time, serially, each held to 15 minutes, it measured:

| Target | Passed | Failed | Run | Seconds |
|---|---:|---:|---|---:|
| TUIAppKitTests | 20 | 6 | ran to the end | 55 |
| TUIAppTests | 1016 | 2 | out of time | 902 |
| TUIBitmapsTests | 330 | 1 | ran to the end | 658 |
| TUIChromeTests | 101 | 2 | ran to the end | 40 |
| TUIColorPickerTests | 204 | 1 | ran to the end | 348 |
| TUICommandsTests | 137 | 2 | ran to the end | 222 |
| TUICoreTests | 517 | 16 | ran to the end | 237 |
| TUICurveEditorsTests | 32 | 0 | ran to the end | 61 |
| TUIDocumentsTests | 11 | 1 | trap: unreachable | 213 |
| TUIEffectsTests | 258 | 0 | ran to the end | 40 |
| TUIEnvironmentDocsTests | 14 | 3 | ran to the end | 167 |
| TUIFilePanelsTests | 46 | 17 | out of time | 901 |
| TUIFormsTests | 33 | 0 | trap: unreachable | 60 |
| TUIFoundationTests | 2301 | 44 | trap: indirect call to null element | 366 |
| TUIGridTests | 128 | 2 | ran to the end | 25 |
| TUIImageTests | 187 | 0 | trap: unreachable | 461 |
| TUIIntegrationTests | 241 | 2 | trap: out of bounds memory access | 116 |
| TUIListsTests | 1023 | 0 | ran to the end | 541 |
| TUIMacrosTests | 8 | 0 | ran to the end | 25 |
| TUIMenusTests | 167 | 0 | ran to the end | 266 |
| TUINavigationTests | 205 | 0 | ran to the end | 55 |
| TUINumericControlsTests | 334 | 3 | ran to the end | 75 |
| TUIPickersTests | 200 | 6 | ran to the end | 35 |
| TUIPresentationTests | 415 | 20 | ran to the end | 221 |
| TUIScenesTests | 33 | 0 | ran to the end | 60 |
| TUISearchTests | 121 | 1 | ran to the end | 70 |
| TUIStylingTests | 294 | 0 | ran to the end | 85 |
| TUITabImagesTests | 4 | 0 | ran to the end | 25 |
| TUITablesTests | 695 | 1 | ran to the end | 226 |
| TUITabsTests | 128 | 0 | ran to the end | 50 |
| TUITestingTests | 32 | 1 | ran to the end | 30 |
| TUITextInputTests | 633 | 0 | ran to the end | 86 |
| TUIViewTests | 147 | 4 | ran to the end | 381 |
| **All** | **10015** | **135** | | |

A test is one `@Test` function, its arguments together; a test still running when a target stopped is in neither
column. That run was before the fixes below: run again after them, the animation tests (40) and the mesh animation
tests (5) all pass, and of the fixture tests only `AssetCatalogTests`' copies and the language tests still fail.

Two runner limits shape that. **WasmKit is an interpreter**: TUIAppTests' nine-thousand-row menu test alone took
224 s, and the two largest targets ran out of time rather than failing. And it answers `poll_oneoff`, the WASI call a
timed wait makes, with `"poll_oneoff" not implemented yet` (seen in TUIAppTests).

**Not measured here**: wasmtime (not installed; a compiling runtime with a complete `poll_oneoff`, so the runner to
try first), Swift 6.4 (no 6.4 `wasm` SDK installed) and 6.2 (none either; see "The toolchain" above), a clean
build's warnings (the incremental builds here showed none but the two now fixed), and the browser demo, which
nothing here drives.

### What the run found in the framework

Fixed here, each with the test that failed on WebAssembly:

- **Repeating animations stopped after one pass.** `Animation.fraction(at:)` capped its pass count at
  `Double(1 << 62)`, and a shift past a 32-bit `Int`'s width is 0, not an error. Nine animation tests.
- **A `bezierPoints:` mesh gradient trapped on its first frame.** `PaintAnimation`'s mesh slots were
  `-(1 << 40) - shape * (1 << 20)`: the shift is 0, and a shape past 2,047 (every control-point mesh) times 2^20
  overflows. The slots are laid out for 32 bits there now; `MeshGradientAnimationTests` has the case.

Found and not fixed, in the gaps below: the stack guard (gap 3), atomic writes (gap 4), dynamic properties inside
enum payloads and the value-hash plans (gap 5).

### The gaps, in order

1. **A runner that can run the suite (S).** wasmtime, or a WasmKit that implements `poll_oneoff`, with `/` (or the
   build directory, at its own path) given to the guest; then the `wasm` job runs the suite, every target, with the
   environment `parallel_test.py` gives the native runs. Under the interpreter the run above took two hours (7,129 s),
   with two targets cut short, so a compiling runtime is what makes it a CI step.
2. **The tests' own assumptions (S each).** Tests that pin a 64-bit memory layout (`MemoryLayout<RenderContext>.size`
   and the padding tests), expect libz (`SystemZlib`, Kitty compression), arm a signal's debt
   (`KeyboardProtocolNegotiationTests`), read the source tree (`TUIEnvironmentDocsTests`), compute a length past
   `Int32` (`STBLengthGuardTests`), or time real work (`BodyKeepTests`): each wants a 32-bit expectation, a
   platform condition, or a reason. And the runner's own: Foundation's
   `createDirectory(withIntermediateDirectories:)` recursed into a stack check under `--dir /`, and `copyItem` and
   symbolic links failed under the host's `/tmp` (itself a link on macOS); with the build directory given to the
   guest instead those may go.
3. **The stack guard does nothing on WebAssembly (M).** `StackGuard.currentThreadExtent` has arms for Darwin and
   Linux and returns `nil` elsewhere, which turns the guard off. Natively a stack overflow is a crash; on wasm the
   stack is a region of linear memory with no guard page, so a view tree deeper than it writes over the data below
   it: the deep-tree tests in TUIFormsTests, TUIFoundationTests and TUIIntegrationTests ended in "indirect call to
   null element", "out of bounds memory access" and a trap in the metadata cache. The bounds are the linker's
   (`__stack_low` and `__stack_high`), read through a small C shim. The most serious finding: memory corruption,
   not a refusal.
4. **Atomic writes fail on WASI (S–M).** WASI's Foundation refuses `atomically: true` and `.atomic` (NSCocoaError
   3328). `@AppStorage` already writes plainly there; `fileExporter`, `LocalizationService`'s language file and
   `DiagnosticChannel` still ask Foundation for one, and `FileDocument` saves make their own (a temporary file, then
   a replace, in the portable `FileWrapper`). On WebAssembly the exporter's saves wrote nothing
   (`FileDocumentExporterTests`); which of the two steps failed is the first thing to find. One helper, atomic where
   the platform can and plain where it cannot, used at each site.
5. **Enum payloads (M).** `EnumWitnesses` is `nil` on wasm32 (and Windows), so a dynamic property inside an enum's
   payload is not found (`DynamicPropertyDiscoveryTests`: a `@State` in `.on(…)` still reads its first value after
   a write), and a view whose value hash needs an enum's payload is not hashed (`.bypass`), which costs memo hits,
   not correctness (`ToolbarValueHashTests`, `SubviewsTests`, the gesture plan tests). The first is a correctness
   gap an app can meet; it needs the value witnesses called in a way wasm's calling convention allows.
6. **The resource bundle (S, done for TUI's own).** The owner ruled on 2026-11-09 (B-BNDL-4): look beside the
   program, then fall back to the built-in English. Done: TUI no longer stops where its bundle is missing. What is
   left: the tests that read German from the bundle found English under the runner (`BuiltInEnglishTests`,
   `PanelLocalizationTests`, `SceneRootLanguageChromeTests`), which the runner's `--dir /` and the bundle's place
   should now explain, and should be re-run; and an app's own resources, which only its own `Bundle.module` finds.
7. **Symbolic links in the file panels (S–M).** A link to a folder lists as a file (`DirectoryListingTests`):
   Foundation on WASI did not follow it for `isDirectory`. Whether that is the runner's `/tmp` or WASI's is the
   first question.
8. **The coverage left out (M).** Of the 225 tests compiled out, the exit tests mostly test process-wide state; with
   one thread and no processes a test of the same promise is possible for some (a pin seen from a second task rather
   than a second thread), not for signals, pipes or ptys. Worth it where the code has a WebAssembly arm of its own:
   `StdinArrivalNotifier`'s `poll` arm, `NoTerminal`, `SystemClipboard`'s and `SystemURLOpener`'s stubs.
9. **`ExampleTests` on WebAssembly (M).** Split the Example into a library of its pages and a two-line executable,
   so the tests depend on the library everywhere; `Tools/Web/build.sh`, the Pages workflow and the docs that name
   the product follow.
10. **Swift 6.4, and 6.2 (S to try).** The lane is 6.3.3 because that is the one pair the port was measured with,
    and a Swift SDK loads only under its own toolchain. Moving to 6.4 is the 6.4.0 `wasm` SDK's URL and checksum in
    `ci.yml` and `pages.yml`, `swift:6.4.0-noble` for the container, and `TUI_WASM_TOOLCHAIN`'s default in
    `Tools/Web/build.sh`; then these measurements again, and `CooperativeExecutor.runUntil`'s stall (above) checked
    on 6.4's runtime. 6.2 needs its own SDK, and a try now that `TupleView` no longer asserts.
11. **The browser demo in CI (M).** Nothing drives the page: a headless browser that loads `Tools/Web/site/`,
    starts the Example, types a few keys and reads the screen (`__tuikit.screen()`) would make "the Example works"
    binding.
12. **Host limits, not gaps.** Remote images (no sockets), the clipboard and opening links from the guest (no
    subprocess; OSC 52 and OSC 8 reach the page instead), signals, job control, the stall watchdog and the
    off-thread quit-key watch (no threads: a hung app is a reloaded tab), and terminal graphics in xterm.js. They are
    the platform's, recorded under "What works, and what does not", and an app meets them as documented absences.
13. **Size (L).** 88 MB of wasm (above); `wasm-opt`, and less of Foundation and ICU, are the levers. Not a
    correctness gap.

### What CI runs when it is done

The `wasm` job, on each supported toolchain with an SDK: the four lower modules one at a time (as now), the Example
with its stack size (as now), the whole package with `--build-tests` (as now), and then the suite under a runner
that can run it, every step binding; and the Pages workflow's build of the demo, with a headless-browser smoke of
it. A test left out on WebAssembly says why where it is left out, as the ones above do.
