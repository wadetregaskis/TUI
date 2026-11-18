# Windows port

What it takes for TUI to be fully supported on Windows, which the owner made a 1.0 requirement on 2026-11-09
(API-STABILITY point 9: "WebAssembly and Windows need to be fully working and supported for 1.0"). This file is the
starting point for the session that does it, on a Windows VM, and the record it keeps as it goes, as
[WebAssembly port.md](<WebAssembly port.md>) is for that port.

## Where it stands (2026-11-17, on the VM)

- **The whole package builds on Windows** with Swift 6.2.4, 6.3.3 and 6.4.2, every library, tool and test target,
  with no warnings in its code (`swift build --build-tests`, each from a clean scratch path), on a Windows 11 arm64
  VM; 6.4.2 also warns about its own SDK (see "Toolchain"). CI has not seen it yet: its steps for `TUIApp`,
  `TUICommands`, `TUIScenes` and the Example are advisory until it has.
- **The test suite passes** on all three, one module at a time (see "The tests").
- **The Example runs in Windows Terminal and in the classic console (conhost)**, both measured with
  `Tools/TerminalProbes/` and both known hosts since 2026-11-16 (`TerminalClient.Program.windowsTerminal`,
  `.windowsConsole`; the terminal survey's "Windows Terminal and the classic console"). Driven by the mouse in each:
  it draws, a click selects and opens, the wheel scrolls, Windows Terminal draws its pictures in real pixels (Sixel),
  the emoji page's treatment rows line up in both, and the menu's Quit hands the console back. Under a pseudo
  console (`Tools/Smoke/conpty.py`) it also takes keys, follows a resize, asks on ⌃\, quits on ⌃Q, and leaves the
  console as it found it on ⌃Q and on Ctrl-Break.

## What "fully supported" means here

The same bar as macOS and Linux: the whole package builds with zero warnings on Swift 6.2, 6.3 and 6.4; the test
suite passes; the Example runs in Windows Terminal (and the classic console host, conhost, at least degraded
gracefully); CI's Windows jobs build and test everything with no `continue-on-error` left; and the docs say so.

## The work, in order

1. **What is green is binding** (done 2026-11-10, from the Mac): every per-module step and the four test targets'
   builds, so nothing that builds today can stop building while the rest is done.
2. **The console layer** (`TUIApp`), behind `#if os(Windows)` arms or a small protocol, so the POSIX code stays as
   it is and a reviewer sees few, obvious places (`.claude/CLAUDE.md`, "Cross-platform"). CONTRIBUTING's
   "known blockers" list, in its order:
   1. stdin wake-up: a thread blocking on `ReadConsoleInput`, since libdispatch refuses console handles;
   2. resize: `WINDOW_BUFFER_SIZE_EVENT` records from the same `ReadConsoleInput` (design 1 and 2 together);
   3. raw mode and VT output: `GetConsoleMode`/`SetConsoleMode` for `termios`,
      `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN`, `GetConsoleScreenBufferInfo` for the size;
   4. signals and the quit key: Ctrl-C/Ctrl-Break through `SetConsoleCtrlHandler`; what ⌃\, `SIGQUIT`, the stall
      watchdog and `FatalSignalTerminalRestore` mean there (the restore on a crash matters most: a console left in
      raw VT mode is the user's problem);
   5. the clipboard: a `WinSDK` arm (`OpenClipboard`/`SetClipboardData(CF_UNICODETEXT)`), and locality from
      `SSH_CONNECTION` plus a Toolhelp32 walk of the parents.
3. **The tests.** Build and run the whole suite on Windows (`swift test`; `Tools/ParallelTest/parallel_test.py` if
   it runs there). Expect path, line-ending and file-system differences in the file-panel and persistence tests.
4. **The smoke tests.** `Tools/Smoke/` is `pty`/`termios`; a ConPTY harness (or the tests' in-memory terminal where
   that is enough) for the quit keys, raw mode and a walk of the Example.
5. **Terminals.** Measure Windows Terminal and conhost with `Tools/TerminalProbes/` where they run, and record what is
   found in `Documentation/Terminals/Terminal compatibility survey.md` — every terminal-specific choice goes there
   (CLAUDE.md, "Terminal-specific behaviour").
6. **CI and docs.** Every Windows step binding, `TUI`, build-tests and test included; CONTRIBUTING's Windows section,
   README's platforms badge and table, CLAUDE.md's "Cross-platform" rule, and the API stability policy's
   "Supported platforms" section brought up to date.

## How to work on it

- Read `AGENTS.md`, `.claude/CLAUDE.md` and `CONTRIBUTING.md` first: SwiftUI parity, no singletons, zero warnings,
  docs changed in the commit that changes behaviour, one change per commit, a failing test before a bug fix.
- Toolchains: Swift 6.2, 6.3 and 6.4 for Windows, with the Visual Studio build tools they need; CI runs the official
  `swift:6.x-windowsservercore-ltsc2022` images through `Tools/ci-windows-swift.ps1`, which is the reference for
  flags and environment.
- Commit to the local `main` (which tracks `staging`) in small commits, and never push: the owner moves the work to
  the Mac, where it is gated and pushed like everything else (CONTRIBUTING, "Staging and `main`"). Keep the macOS and
  Linux builds untouched by Windows arms: they are checked there, not on the VM.
- Record decisions and measurements in this file as you go, with their reasons.

## Toolchain

Measured on a Windows 11 arm64 VM (Apple silicon host) with swift.org's 6.3.3 (`aarch64-unknown-windows-msvc`) and the
Visual Studio 2022 Build Tools 17.14, installed with `winget install Swift.Toolchain --version 6.3.3`.

- **`AttributedString.runs` does not link.** Any program that touches it — `for run in string.runs`, even
  `string.runs.count` — fails with `undefined symbol: $s22_FoundationCollections9BigStringV5IndexVMn`. `Runs` holds a
  `RangeSet<BigString.Index>`, and its code is inlined into the caller, which then needs that type's metadata;
  `BigString` is `_FoundationCollections`', which the SDK's `FoundationEssentials.dll` builds in without exporting a
  symbol of it, and which ships no library of its own. Reproduced in a ten-line program. `string.characters` and a
  substring's attributes (`string[range].link`) link, being Foundation's own code, so `Text(AttributedString)` walks
  the string by character on Windows and merges the runs itself (`Text+Attributed.swift`). Nothing else in the
  package uses `runs`. CI never saw this: its Windows steps built modules, and nothing linked a program.
- **Symlinks need Developer Mode** (or an administrator), both for SwiftPM's checkout of `swift-docc-plugin`, which
  keeps shared plugin code behind symlinks, and for the file-panel tests that make links. Until the owner turned it
  on (2026-11-16) the VM worked round the checkout by telling git to write links as files for SwiftPM's process
  (`GIT_CONFIG_COUNT=1`, `core.symlinks=false`); CI's containers run as administrator and need neither.
- **Toolchains install side by side** (6.3.3, then 6.4.2, each by `winget install Swift.Toolchain
  --version …`), each adding itself to the user's `PATH` and setting `SDKROOT`: the first on the `PATH` compiles and
  `SDKROOT` names the last installed, so a build sets both for the one it means. With more than one installed,
  6.4's SwiftPM stops before building ("platform 'windows' already registered from …\Platforms\6.3.3"): its default
  build system reads every platform in the install. `--build-system native`, deprecated, builds. A test runner needs
  the same toolchain's runtime first on its `PATH`, or it stops at launch with `0xC0000139`, an entry point not found.
- **Side by side goes upward only.** 6.2.4's installer, run with 6.3.3 and 6.4.2 installed, finds its packages
  "Obsolete" against theirs, installs nothing and reports success. It was measured unpacked instead, registered with
  nothing: the bundle's payload cabinet cut out of the `.exe` by its `MSCF` header (7-Zip reads only the first one),
  its files named from the bundle's manifest, and `msiexec /a <package>.msi TARGETDIR=…` for the runtime, the build
  tools, the compiler and the Windows platform. A short `TARGETDIR` (`%LOCALAPPDATA%\S624`): the toolchain's own paths
  are deep, and under the session's scratch folder they passed 260 characters (error 1304). The runtime's DLLs land at
  the top of `TARGETDIR`.
- **A full disk can look like a crashing compiler.** A debug build of the package and its tests takes about 4 GB per
  toolchain. Builds here crashed `swift-frontend` in IRGen, or with exception 5, in module after module, until one
  said "no space on device"; once space was freed, the same builds were clean. Check the disk before the compiler.
- **6.4.2 sees `_RegexParser`'s `String.init` beside the standard library's**, so `String(cells.map { … ? "." : "#" })`,
  literals that may be Strings or Characters, is ambiguous there (2aa30a83a). And it checks strict memory safety, which
  6.2 and 6.3 build without: a Win32 handle is a raw pointer in Swift, so the Windows arms needed `unsafe` (3b8bc906a).
- **6.4.2 warns about its own SDK on a cold module cache.** A clean build prints "reference to type 'wchar_t' broken
  by a context change; 'wchar_t' was expected to be in '_Builtin_stddef', but now a candidate is found only in
  'SwiftShims'", raised at `WinSDK.swiftmodule:1:1` (59 times in one clean build of the package), with a note that
  WinSDK was built in Swift 5.10. It names no line of TUI's, one file that raised it (`TUIEnvironmentDocsTool`'s
  `main.swift`, plain Foundation) does not raise it again when rebuilt with the cache warm, and a one-line program
  importing WinSDK or Foundation does not raise it at all. 6.2.4 and 6.3.3 do not print it. It is the toolchain's;
  TUI has nothing to change.
- **A Windows Terminal started before a toolchain was installed** has the old `PATH` in every tab and window it
  opens: a program built since stops at launch, "The code execution cannot proceed because
  `swift_StringProcessing.dll` was not found" (CONTRIBUTING).

## The console layer

Everything Windows-only is in three files — `WindowsConsole.swift` (Rendering), `SignalManager+Windows.swift` and
`FatalSignalTerminalRestore+Windows.swift` (App) — and the rest of `TUIApp` has `#if os(Windows)` arms beside its POSIX
code, which is unchanged. What each piece became, and why:

| POSIX | Windows | Why |
|---|---|---|
| `termios` raw mode | `ConsoleModes`: input with line input, echo, processing and Quick Edit off, and `ENABLE_VIRTUAL_TERMINAL_INPUT`, `ENABLE_WINDOW_INPUT` and `ENABLE_MOUSE_INPUT` on; output with `ENABLE_VIRTUAL_TERMINAL_PROCESSING` and `DISABLE_NEWLINE_AUTO_RETURN`; both code pages UTF-8 | Virtual-terminal input makes keys, mouse reports, pastes and the terminal's replies the bytes a POSIX terminal sends, so the parser and every startup exchange are unchanged. ⌃C arrives as 0x03, as with `VINTR` off |
| The output modes with raw mode | Taken before the alternate screen (`takeConsole()`), given back after the hand-back's last write (`giveBackConsole()`) | The run enters the alternate screen before raw mode, and the hand-back shows the cursor and leaves it after; conhost without VT processing would print those escapes |
| `DispatchSource` on stdin | `ConsoleInput`: a thread waiting on the console's handle and reading its records, each key-down record's UTF-16 unit as UTF-8 | libdispatch refuses a console handle. Records rather than `ReadFile`, which drops a resize |
| `SIGWINCH` | `WINDOW_BUFFER_SIZE_EVENT`, from the same reader | One call answers both, as CONTRIBUTING foresaw |
| Reading while running | The reader reads only while raw mode is on | So a hand-off's program keeps its keys |
| `write(2)` to stdout | `WriteFile` on the standard output handle | The C library's descriptor 1 is in text mode and would turn each line feed into CR LF |
| `TIOCGWINSZ` | `GetConsoleScreenBufferInfo`'s window | The buffer is often far taller than the window; the pixel fields have no counterpart, so the cell's pixel size falls back to its default, as on a terminal that reports zeros |
| `SIGINT`, `SIGTERM`, `SIGHUP` | `SetConsoleCtrlHandler`: `CTRL_C_EVENT` (sent, or the key outside raw mode), `CTRL_CLOSE_EVENT`, logoff and shutdown set `shouldShutdown`; for the last three the handler waits up to 5 s for the teardown, as the system ends the process when it returns | An orderly quit, as on POSIX |
| Job control | None | Nothing suspends a Windows process from its console; ⌃Z is a key |
| The driver's ⌃\ (`SIGQUIT`) | Ctrl-Break: the console raises `CTRL_BREAK_EVENT` in every mode, on a thread of its own, so it quits a hung app; it pays a quit's debt and exits with `STATUS_CONTROL_C_EXIT` | The way out of a hung app that needs no watchdog: the stall watchdog, the quit key's watch and the line discipline are left out |
| ⌃\ read as a key | 0x1C (`Terminal.quitKeyByte`), which the input chain takes as the quit key: it asks first by default, and quits as Ctrl-Break does (`QuitKeyReport`) | The same key quits the same way on every platform |
| Crash handlers (`SIGSEGV`, `SIGABRT`, …) | The unhandled-exception filter, chained to the one before; `SIGABRT`'s handler for `abort()`, which raises no exception; `SetThreadStackGuarantee(64 KiB)` where POSIX gives a thread an alternate stack | A crash's debt is paid and the console's modes put back. Unmeasured: nothing in the Example crashes on cue |
| `atexit` | `atexit` | The same |
| `isatty`, `getenv`, `setenv` | `GetConsoleMode` on the descriptor's handle; `GetEnvironmentVariableW`; `_putenv_s` | The C library's POSIX names are deprecated on Windows, and its `isatty` says yes to `NUL` |
| `/dev/tty` | `CONIN$` / `CONOUT$`, with `SetStdHandle` and the descriptor `_dup2`'d | What `NoTerminal` points a redirected stream at |
| `pbcopy`, `wl-copy`, `xclip` | `OpenClipboard`, `SetClipboardData(CF_UNICODETEXT)`, CR LF on the clipboard and LF in the app | No helper to run, so nothing can hang; locality from the ssh variables and a Toolhelp32 walk of the parents |
| `open`, `xdg-open` | `ShellExecuteW` | The user's default program for the scheme |

Measured under a pseudo console (`Tools/Smoke/conpty.py`, 2026-11-16, debug build):

- The first frame draws; Down, Up, Return, Escape and the digits drive the menu; a resize from 120x40 to 90x30 redraws
  at the new size.
- ⌃\ brings up "Quit Example?" (it read "Quit Example.exe?" until `programName`); ⌃Q exits with status 0, its teardown
  leaving the alternate screen; Ctrl-Break (sent in win32-input-mode, `CSI 3;70;0;1;8;1 _`) pays the quit's debt —
  styling reset, title popped, alternate screen left — and exits with `0xC000013A`.
- With the harness's piped handles inherited, the app says "standard input and output are not a terminal" and
  exits 1.
- The Colors page takes several seconds to draw in a debug build on this VM; every other page visited is prompt.

## The tests

Run on the VM, one test module at a time (a test that crashes takes its process down), debug builds.

Of the 35 modules, `TUIFilePanelsAppKitTests` has no tests outside macOS; run alone, its filter matches none, and
Swift Testing exits with `ERROR_NOT_FOUND` (`0x490`), as it does on Windows when no test is found.

**6.3.3** (2026-11-17): every module passes, all 35, with frames drawn on the fiber (below). One test has failed in
earlier runs under load: "a cancelled timeout never resumes a later waiter (no cascade spin)"
(`StdinArrivalNotifierTests`), which counts completions in a real-time window, and which passes alone.

**6.4.2** (2026-11-17): every module passes, all 35, with frames drawn on the fiber.

**6.2.4** (2026-11-17): every module passes, all 35, with frames drawn on the fiber, from the toolchain unpacked
beside the others (see "Toolchain").

**The stack a frame is drawn on.** A Windows thread gets the stack its executable names, 1 MiB unless the program was
linked asking for more: an app's main thread, and the libdispatch workers Swift Testing runs a `@MainActor` test on.
The stack guard keeps 256 KiB in reserve (`StackGuard.reserveBytes`), and the Example's whole Animation page, drawn in
a debug build, needs more than the 768 KiB left: on 6.4.2 "On the page itself, Show / hide fades the panel out"
(`AnimationPageShowHideTests.swift:330`) failed every run. Counted (`StackGuard.truncationCount`) over the frame that
starts the removal: 110 cuts on 6.3.3, none of them on what the test reads, and 285 on 6.4.2, whose debug frames are
larger, the panel among them. Linking with `/STACK` would have mended TUI's own programs and left every app to link
with it too, which TUI should not ask (owner, 2026-11-17). So a frame is drawn on a stack TUI provides
(`LargeStack`, in TUICore): on Windows, where the thread's stack is smaller than 8 MiB, `RenderLoop.render` and
`renderOnce`'s walk run on a fiber with 8 MiB reserved (committed as it is used), switched to and back on the same
thread, so thread-locals, the running task and the main actor's checks see nothing different. Windows reports the
fiber's stack to `GetCurrentThreadStackLimits` while it runs, so the guard measures 8 MiB. Two tests that set the
guard's floor by hand, or sized a chain to the thread's stack, now do so on the stack the walk runs on.

What the runs found, and fixed, on the way (each its own commit): the stack guard had no Windows arm, so too
deep a tree overflowed rather than being cut short; `AnyView.staysWhole(in:)` walked a chain of `AnyView`s with no
guard; tests that chose a depth against an 8 MiB stack overflowed Windows's 1 MiB (releasing a deep chain can never be
cut short, so those depths are now proportional to the thread's stack); the enum value witnesses, never called on
Windows, work there; a write to a control's `Binding` asked for no frame, as the thread that walks a frame did not
mark itself; a file panel listed no folder that held a link leading nowhere, and completed no path from a drive or a
share; `ExampleTests` needed the Example as a dependency on Windows; and tests that assumed `/dev/null/…` cannot be
written, that a system zlib exists, or that `timespec` has no padding.

Two things about the environment the runs needed:

- **LF line endings.** Several tests read source files and split them on `"\n"`, which never matches a CR LF (one
  `Character` in Swift). CI checks out with `core.autocrlf false` and `core.eol lf`; this checkout now does too.
- **The thread a test runs on.** Swift Testing on Windows runs a `@MainActor` test on a libdispatch worker thread,
  with the 1 MiB default stack, not on the process's main thread.

## Still to do

- **CI**: a run of every Windows step, then binding, per the ratchet; README's platform badge after it.
- **A crash under Windows Terminal and conhost**, to see the exception filter pay the debt: nothing in the Example
  crashes on cue.
- **Keys and the mouse, measured**: `Tools/TerminalProbes/`' key and mouse probes need someone at the keyboard, so how
  each terminal encodes modifiers, how many wheel reports a notch sends, and which pointer shapes it takes are
  unmeasured. The Example was driven by clicks and the wheel only.
- **The console's font**: conhost's Consolas has no quadrants (`▖ ▗ ▘ ▝ ▙ ▛ ▜ ▟`), which shapes and canvases draw with;
  TUI cannot ask a terminal what its font has, so the Terminal Support article tells users to choose Cascadia Mono.
- **An OSC 52 write over 8 KiB** left the clipboard as it was in both terminals; TUI sends a copy whole, whatever its
  size, so a larger one is lost there. Unaddressed.
- **Windows x86_64**: reasoned, not measured, where it differs (the enum witnesses); CI's lanes are x86_64.
