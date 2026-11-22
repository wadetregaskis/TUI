# Windows port

What it took for TUI to be fully supported on Windows, which the owner made a 1.0 requirement on 2026-11-09
(API-STABILITY point 9: "WebAssembly and Windows need to be fully working and supported for 1.0"), and what is left.
It was the starting point for the session that did it, on a Windows VM, and is the record it kept as it went, as
[WebAssembly port.md](<WebAssembly port.md>) is for that port. **Windows is supported since 2026-11-20**, and the
docs say so: what an app's author needs to know is the Running on Windows article
(`Sources/TUI/TUI.docc/Articles/RunningOnWindows.md`). What is left is "Still to do": CI's Windows jobs made
binding, which waits for them to pass there (the owner, 2026-11-20: not binding yet).

## Where it stands (2026-11-20, on the VM)

- **The whole package builds on Windows** with Swift 6.2.4, 6.3.3 and 6.4.2, every library, tool and test target,
  with no warnings in its code (`swift build --build-tests`, each from a clean scratch path), on a Windows 11 arm64
  VM; 6.4.2 also warns about its own SDK (see "Toolchain"). CI has not seen it yet: its steps for `TUIApp`,
  `TUICommands`, `TUIScenes` and the Example are advisory until it has.
- **The test suite passes** on all three, one module at a time (see "The tests"), and on x86_64 too: built with
  6.3.3 for `x86_64-unknown-windows-msvc` with no warnings, and run under Windows 11's emulation with x64's own
  runtime, every module passes and so does the smoke check; the Example runs there and quits by its menu.
- **The Example runs in Windows Terminal and in the classic console (conhost)**, both measured with
  `Tools/TerminalProbes/` and both known hosts since 2026-11-16 (`TerminalClient.Program.windowsTerminal`,
  `.windowsConsole`; the terminal survey's "Windows Terminal and the classic console"). Driven by the mouse in each:
  it draws, a click selects and opens, the wheel scrolls, Windows Terminal draws its pictures in real pixels (Sixel),
  the emoji page's treatment rows line up in both, and the menu's Quit hands the console back. Under a pseudo
  console (`Tools/Smoke/conpty.py`) it also takes keys, follows a resize, asks on ⌃\, quits on ⌃Q, and leaves the
  console as it found it on ⌃Q and on Ctrl-Break.
- **Keys and the mouse are measured in both** (2026-11-19 and -20, by the owner's hand): Windows Terminal speaks the
  kitty keyboard protocol in full, and keeps the chords of its own default bindings, which TUI does not name, every
  one TUI's keys share now measured; conhost speaks the legacy encodings; both report every mouse button and modifier
  but Shift.

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
3. **The tests.** Build and run the whole suite on Windows (`swift test`, and `Tools/ParallelTest/parallel_test.py`,
   which runs there since 2026-11-20). Expect path, line-ending and file-system differences in the file-panel and
   persistence tests.
4. **The smoke tests.** `Tools/Smoke/` is `pty`/`termios`; a ConPTY harness (or the tests' in-memory terminal where
   that is enough) for the quit keys, raw mode and a walk of the Example.
5. **Terminals.** Measure Windows Terminal and conhost with `Tools/TerminalProbes/` where they run, and record what is
   found in `Documentation/Terminals/Terminal compatibility survey.md` — every terminal-specific choice goes there
   (CLAUDE.md, "Terminal-specific behaviour").
6. **CI and docs.** Every Windows step binding, `TUI`, build-tests and test included; CONTRIBUTING's Windows section,
   README's platforms badge and table, CLAUDE.md's "Cross-platform" rule, and the API stability policy's
   "Supported platforms" section brought up to date. The docs are (2026-11-20: every article, guide and record that
   named the platforms, and a Running on Windows article for what differs); CI waits for its Windows jobs to pass.

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
  build system reads every platform in the install. `--build-system native`, deprecated, builds. To build with the
  default (Swift Build), as CI's 6.4 lanes do, give 6.4.2 an install of its own: its `Toolchains`, `Platforms` and
  `Runtimes` folders mirrored by hard links under another root (no disk spent), with `PATH` and `SDKROOT` pointed
  there. Junctions do not serve: Swift Build follows them back to the shared install. So built on 2026-11-18, the
  whole package and its tests had no diagnostics, and `swift test`, which runs each test target in a process of its
  own under Swift Build, passed all 15,667 tests in 16 minutes. Its build folder holds paths past 260 characters
  (macro expansions), which PowerShell 5.1's `Remove-Item` cannot delete; `rmdir /s /q "\\?\C:\…"` can. A test runner needs
  the same toolchain's runtime first on its `PATH`, or it stops at launch with `0xC0000139`, an entry point not found.
- **Side by side goes upward only.** 6.2.4's installer, run with 6.3.3 and 6.4.2 installed, finds its packages
  "Obsolete" against theirs, installs nothing and reports success. It was measured unpacked instead, registered with
  nothing: the bundle's payload cabinet cut out of the `.exe` by its `MSCF` header (7-Zip reads only the first one),
  its files named from the bundle's manifest, and `msiexec /a <package>.msi TARGETDIR=…` for the runtime, the build
  tools, the compiler and the Windows platform. A short `TARGETDIR` (`%LOCALAPPDATA%\S624`): the toolchain's own paths
  are deep, and under the session's scratch folder they passed 260 characters (error 1304). The runtime's DLLs land at
  the top of `TARGETDIR`.
- **x86_64 from the arm64 VM.** The arm64 toolchain's SDK has x86_64's Swift libraries, and the Build Tools and
  Windows SDK have x64's, so `swift build --build-tests --triple x86_64-unknown-windows-msvc` builds it; the platform
  ships x64 Testing and XCTest DLLs too (`usr\bin64`, beside arm64's `bin64a`). The x64 runtime is not in the arm64
  installer: it was cut from swift.org's x64 6.3.3 installer as 6.2.4 was (its `rtl.msi`, `msiexec /a` to
  `%LOCALAPPDATA%\S633x64`, registered with nothing), and put first on the test runner's `PATH`.
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
| `DispatchSource` on stdin | `ConsoleInput`: a thread waiting on the console's handle and reading its records, each key-down record's UTF-16 unit as UTF-8, holding up to 1 MiB for the loop and leaving the rest in the console's queue until the loop reads; `Terminal.hasPendingInput` asks what it holds, as a read source fires again while bytes wait | libdispatch refuses a console handle. Records rather than `ReadFile`, which drops a resize |
| `SIGWINCH` | `WINDOW_BUFFER_SIZE_EVENT`, from the same reader | One call answers both, as CONTRIBUTING foresaw |
| Reading while running | The reader reads only while raw mode is on | So a hand-off's program keeps its keys |
| `write(2)` to stdout | `WriteFile` on the standard output handle | The C library's descriptor 1 is in text mode and would turn each line feed into CR LF |
| `TIOCGWINSZ` | `GetConsoleScreenBufferInfo`'s window | The buffer is often far taller than the window; the pixel fields have no counterpart, so the cell's pixel size falls back to its default, as on a terminal that reports zeros |
| `SIGINT`, `SIGTERM`, `SIGHUP` | `SetConsoleCtrlHandler`: `CTRL_C_EVENT` (sent, or the key outside raw mode), `CTRL_CLOSE_EVENT`, logoff and shutdown set `shouldShutdown`; for the last three the handler waits up to 5 s for the teardown, as the system ends the process when it returns, and the teardown leaves the handler installed (with nothing to route to) while it runs | An orderly quit, as on POSIX. Taking the handler out waits for every running handler to return, so the teardown stalled there and was ended after 5 s, closing conhost's window or Windows Terminal's (measured 2026-11-21, a probe logging each step of the teardown); it now ends in 25 ms. But logoff and shutdown never come: the system does not send them to a process that has loaded `user32.dll` (`SetConsoleCtrlHandler`'s documentation), and the clipboard and the shell's opener load it (the Example has it loaded, 2026-11-18) |
| The same, for a logoff or a shutdown | A hidden top-level window on a thread of its own (`SessionEndWatch`): `WM_QUERYENDSESSION` answered yes, and `WM_ENDSESSION` for a session that is ending sets `shouldShutdown` and waits up to 5 s for the teardown | How the system tells a process with `user32.dll` loaded; a message-only window gets no broadcast. Tested by sending the window the messages, and by a real logoff (2026-11-21, a probe app logging each step, in conhost and in Windows Terminal): both quit in order. In conhost the window's shutdown did it; in Windows Terminal the tab's `CTRL_CLOSE_EVENT` came 90 ms after `WM_ENDSESSION` and did it first. The system seems to send `WM_ENDSESSION` to a process's windows one after another: in conhost this window heard it 5 s late, once the probe's own window had waited its 5 s |
| Job control | None | Nothing suspends a Windows process from its console; ⌃Z is a key |
| A hand-off ignoring `SIGINT` and `SIGQUIT`, as `system(3)` does | While the console is handed over, both handlers take ⌃C and Ctrl-Break and do nothing (`SignalManager.isHandingOff`) | The console raises them in every process sharing it, the app included: ⌃C shut the app down when the program returned, and Ctrl-Break ended it |
| `posix_spawn` for `handOffTerminal(running:)` | `CreateProcessW` in the app's console, no handles inherited, waited on; its exit code is the ending, as there are no signals | The program shares the console as a POSIX one shares the foreground group |
| The driver's ⌃\ (`SIGQUIT`) | Ctrl-Break: the console raises `CTRL_BREAK_EVENT` in every mode, on a thread of its own, so it quits a hung app; it pays a quit's debt, after the frame being written if one is (up to 250 ms, as a write can block for good: `FatalSignalTerminalRestore.duringWrite`), and ends with `TerminateProcess` and `STATUS_CONTROL_C_EXIT` | The way out of a hung app that needs no watchdog: the stall watchdog, the quit key's watch and the line discipline are left out |
| ⌃\ read as a key | 0x1C (`Terminal.quitKeyByte`), which the input chain takes as the quit key: it asks first by default, and quits as Ctrl-Break does (`QuitKeyReport`) | The same key quits the same way on every platform |
| Crash handlers (`SIGSEGV`, `SIGABRT`, …) | The unhandled-exception filter, chained to the one before; `SIGABRT`'s handler for `abort()`, which raises no exception; `SetThreadStackGuarantee(64 KiB)` where POSIX gives a thread an alternate stack | A crash's debt is paid and the console's modes put back. A stack overflow on a fiber, as a frame's walk runs on (`LargeStack`), ran the filter as often without the guarantee asked on the fiber as with it, the filter using 8 to 56 KiB of stack (a probe, 2026-11-18, 4 or 5 runs each; one run in four failed at 40 KiB either way), so only the thread's own is asked |
| `atexit` | `atexit` | The same |
| `isatty`, `getenv`, `setenv` | `GetConsoleMode` on the descriptor's handle; `GetEnvironmentVariableW`; `_putenv_s` | The C library's POSIX names are deprecated on Windows, and its `isatty` says yes to `NUL` |
| `/dev/tty` | `CONIN$` / `CONOUT$`, with `SetStdHandle` and the descriptor `_dup2`'d | What `NoTerminal` points a redirected stream at |
| `pbcopy`, `wl-copy`, `xclip` | `OpenClipboard`, `SetClipboardData(CF_UNICODETEXT)`, CR LF on the clipboard and LF in the app | No helper to run, so nothing can hang; locality from the ssh variables and a Toolhelp32 walk of the parents |
| `open`, `xdg-open` | `ShellExecuteW`, for a URL that names a scheme | The user's default program for the scheme. A bare name (`calc`) the shell would run as a program |
| `Task.sleep` for the loop's timed wait | A high-resolution waitable timer, waited on by the thread pool (`PreciseSleep`) | Every wait on libdispatch's timers keeps the clock's 15.6 ms tick, whatever `timeBeginPeriod` says: 16 ms took 30–31 ms, so a frame due in 16.7 ms came in 31.2. The timer takes 16.4–16.5 and needs no change to the clock |

Measured under a pseudo console (`Tools/Smoke/conpty.py`, 2026-11-16, debug build):

- The first frame draws; Down, Up, Return, Escape and the digits drive the menu; a resize from 120x40 to 90x30 redraws
  at the new size.
- Walked again 2026-11-19 (6.3.3, debug), with F1's list of shortcuts, which names no chord the console cannot send
  (no ⌃⇧ chord, no ⌃,): all as before. A key sent before the page a previous one opened has drawn waits for it; a walk
  that sends the next key at once can read the old screen.
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

**As CI runs them** (6.3.3, 2026-11-17): `swift test`, the whole suite in one process after `swift build
--build-tests`, ran 15,667 tests in 19 minutes, its build adding a minute and a half, within the Test step's 30. One
failed, under that load only: a date picker's ▲, held through one yield, outlived the repeat's initial delay and
stepped the year 23 times; its tests now repeat on a `TestClock` and wait for each step. CI's smoke step, `swift run
Stress --selfcheck` with `TUI_VERIFY_RENDER_MEMO=1`, failed `deep` (the stack guard cut it: Stress drew its frames on
the thread's 1 MiB, not on the fiber, which it now does) and, with `NO_COLOR` set as it is in this VM's tool
environment, the menus session (its check read a highlight by colour alone, where at no colour it is reverse video).
Both fixed; all 158 cases and 43 sessions pass, on 6.2.4 and 6.4.2 too (2026-11-18), and on x86_64 (6.3.3, built
for `x86_64-unknown-windows-msvc` and run under emulation, in 40 minutes), where every module
passes again with those fixes in.

**Through `Tools/ParallelTest/parallel_test.py`** (6.3.3, 2026-11-20), which now runs on Windows (its README's
"Toolchains and platforms" has what it sets up: swift-testing's DLLs on `PATH`, `TMP` and `TEMP`, a lock without
`flock`): 15,726 tests in four processes, every one accounted for, all passed in 524 s. On 6.2.4 too (594 s), and on
6.4.2 (639 s, with `--build-system native`, as 6.4's default stops beside 6.3.3) all but two cost bounds that read the
wall clock here (below).

**In release** (2026-11-20, arm64): `swift build -c release`, as CI's macOS and Linux lanes build it, has no
diagnostics on 6.2.4, 6.3.3 and 6.4.2 (8 to 11 minutes each). The suite in release with the invariant checks on
(`parallel_test.py --release`, CI's release lanes on macOS and Linux) does not build on any of the three, each for a
bug in the compiler that its internal checks catch. swift.org's Windows toolchains are built with those checks on
(`6.3.3+Asserts`), its macOS and Linux ones without, so those lanes have never run them:

- **6.2.4 and 6.3.3**: `Assertion failed: Entry->getType() == Type && "Value Type mismatch?"`
  (`DeserializeSIL.cpp`, line 335 and 395), in `PerformanceSILLinker` while optimising `TUIApp`, deserializing
  `View.sheet(isPresented:onDismiss:content:)` from `TUIPresentation`. `-enable-testing` alone sets it off (6.3.3,
  `swift build -c release --target TUIApp -Xswiftc -enable-testing`); `-DTUI_TEST_SUPPORT` and `-DDEBUG` alone build.
  After it, a second compile of 6.3.3's sat idle for 50 minutes, and the build with it, until stopped.
- **6.4.2**: "Found ownership error?!" in `CopyPropagation` on `String.sanitizedForTerminal` (`TUICore`), a fatal
  error. `-assert-config Debug` alone sets it off (`swift build -c release --build-system native --target TUICore
  -Xswiftc -assert-config -Xswiftc Debug`), and turning the SIL verifier off (`-Xfrontend -sil-verify-none`, or
  `-disable-sil-ownership-verifier`) does not get past it.

Neither flag can go: `@testable import` needs the first, and the run is for the second. Tried, to work round them
with a switch where that was not hard and cost nothing notable (the owner, 2026-11-20), and given up:

- 6.2 and 6.3: `-Xfrontend -disable-cmo` loses to SwiftPM's own `-enable-default-cmo`, and `-Xllvm
  -sil-disable-pass=performance-sil-linker` left the pass running. Nothing short of reshaping `View.sheet` for a
  compiler's sake avoids it.
- 6.4.2: copy propagation off (`-Xfrontend -enable-copy-propagation=false`) builds `TUICore`, and the build then
  stops in `SemanticARCOpts` compiling `SwiftSyntax` ("Invalid SIL provided to OSSACompleteLifetime?!", on
  `SyntaxProtocol.debugWrite`). With the ownership verifier off as well (`-disable-sil-ownership-verifier`, which that
  message names), it stops lowering `TUIEnvironmentDocs` to SIL: "SIL verification failed: switch_enum default
  destination must take no arguments", on a `switch` over a pair of `TUIEnvironmentVariable.CodeSetting`s. Each
  crash also left a compile idle and the build waiting on it, until stopped. Three bugs deep, the switches stopped
  short of a workaround and were taken back out.

All of them are to be reported upstream, with these commands as the reproduction (the function alone, with what it
calls, did not reduce quickly); the release suite runs on Windows once they are fixed.

**Windows's own settings** (2026-11-20). Foundation on Windows reads neither the user's languages nor their region:
`Locale.preferredLanguages` is `["en-001"]` and `Locale.current` is `en_001` on a machine set to `en-US` (Swift 6.3.3),
so every app spoke English and wrote dates day first. TUI asks Windows (`GetUserPreferredUILanguages`,
`GetUserDefaultLocaleName`; `LocalizationService+Windows.swift`), behind the POSIX variables as everywhere. Its
accessibility settings are read too (`TerminalClient+Accessibility+Windows.swift`: `SPI_GETCLIENTAREAANIMATION`,
`SPI_GETHIGHCONTRAST`, the `EnableTransparency` value), with no process started, where the GNOME arm had run a
`gsettings` that is not there on every launch and focus. A file panel's Desktop, Documents and Downloads come from
`SHGetKnownFolderPath` where the folder it names exists (on the VM the Desktop is `OneDrive\Desktop` and the profile
has none, and Documents is named `OneDrive\Documents`, which does not exist, so the profile's is kept), and
Applications is Program Files. Its names follow Windows's rules (`FileNameRules`): `notes:old` had written an
alternate data stream of `notes`. Tab completion passes an item with the hidden attribute by unless nothing else
matches, and names sort as `localizedStandardCompare(_:)` orders them, which Windows's Foundation has without
`.localizedStandard`. A file's Kind is Windows's own word for its type (`SHGetFileInfoW`, by extension, once a
listing: "Text Document", "Compressed (zipped) Folder"). conhost, which answers no colour query (the survey's
"Capabilities"), has its colours read from its own record (`GetConsoleScreenBufferInfoEx`), so a light profile should be taken
as light (tested on Campbell's table; not yet seen in a light console). And `SessionLocality.isLikelyLocal` takes Windows Terminal's `WT_SESSION` as it takes `TERM_PROGRAM`.

The same day, at the owner's word: pictures decode through WIC (`ImageLoader+WIC.swift`), stb_image reading what it
has no codec for (TGA, HDR, PSD, PNM); measured on the VM, its decoders were BMP, GIF, ICO, CUR, JPEG, PNG, TIFF,
DNG, JPEG XR, DDS, HEIF/AVIF, WebP, camera raw and JPEG XL, and its flip rotator flips before it turns, so EXIF's
orientations 5 and 7 take each other's quarter turn. A file panel follows a shortcut as a symbolic link
(`ShellShortcut+Windows.swift`, `IShellLinkW` through `IPersistFile`, never `Resolve`): one to a folder opens there
and does not expand in the outline, as Explorer's tree does not; one to a file is chosen as it; one whose target is
gone, or that names none (File Explorer's), is a file. The classic console's cell size comes from its font
(`ConsoleFont.cellSize()`). And off Apple platforms and Windows, `Image(_:bundle:)` no longer looks for a `.tiff`,
which stb_image cannot draw. With WIC's pixels the adaptive palette's test on the Example's picture found an entry
serving a histogram bucket none of whose pixels is nearest to it (a limit of deriving from buckets, which reseeding
again did not move), so that test decodes its fixture with stb_image on Windows, as on Linux.

Later that day, at the owner's word: the classic console's cell is measured from its window (`ConsoleWindow.cell()`:
the client area over the grid, asked per-monitor aware, so in the window's pixels), and its calibration to points is
the window's dots an inch over 96 (`GetDpiForWindow`), taken only on `SessionLocality.isLocal()`'s evidence; at 200%
Consolas's font names 8 × 16, its 96-dpi cell, while the window draws 15 × 32, 7.5 × 16 points (the survey's "A
cell's size in points"). An image that is not resizable takes its natural size there now. And an animated WebP plays
(`AnimatedImageDecoder+WIC.swift`): WIC's WebP codec composites its frames itself, each one the whole canvas,
blended, replaced and disposed as the file says, and states `/ANMF/FrameDuration` and `/ANIM/LoopCount` (measured
on a hand-made file of four frames, the test's), so playing one took no compositor of TUI's. APNG still shows its
first image: playing it was set aside, as worth it only if it is little work (the owner, 2026-11-20), and whether
WIC reads an APNG's frames at all has not been looked at.

**No per-thread CPU clock on Windows** (owner, 2026-11-20: leave it on wall time). `threadCPUNanoseconds()` (TUICore)
answers `nil` there, so the tests' cost bounds (`bestCPUSeconds`) and the Stress bench read the wall clock, and under
`parallel_test.py`'s load two bounds failed on 6.4.2 that pass with their suites alone. Neither Windows clock serves:
`GetThreadTimes` moves in whole ticks (15.625 ms, measured 2026-11-20), coarser than a batch, and
`QueryThreadCycleTime` is precise but counts cycles (1.87–1.96 GHz against `QueryPerformanceCounter` here, by span),
which Microsoft says not to convert to time; converting them takes a measured rate, a process-wide value the
no-singletons rule does not exempt, as it is not a pure function. Those bounds are known to be load-sensitive there
(Tools/ParallelTest/README.md, "Known order dependence, and flakes").

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

- **CI**: a run of every Windows step, then binding, per the ratchet (the owner, 2026-11-20: not binding yet).
- **The release suite**: blocked on all three toolchains by compiler bugs that their assert-enabled Windows builds
  catch ("The tests", "In release"); to report upstream.
- **What Windows has that TUI does not read yet** (a survey of the sources, 2026-11-20), each left for a reason:
  colour management in WIC's pictures, and APNG's frames (set aside, 2026-11-20); the display's scale in Windows
  Terminal, which says nothing of its cell; press-and-hold repeat, which no Windows setting governs (its keyboard
  repeat is the terminal's); macOS's and GNOME's double-click and blink settings, beside Windows's (read since
  2026-11-20, `TerminalClient.hostInputTimings()`), for the Mac; and Japanese readings, zlib for Kitty images, and
  the Stress bench's memory figures. A `file:` link's host is not one: Windows Terminal refuses a link that names one
  (the survey's "Paint"). Nor is `TableColumn`'s default order any longer: a column of strings given no comparator
  sorts as Finder lists names on every platform (`TableColumn+StandardOrder.swift`, 2026-11-20), through an
  initializer of TUI's own beside SwiftUI's, since Foundation off Apple platforms has no `String.StandardComparator`
  but `.lexical` and refuses to decode one with `.localizedStandard`'s options.

Done since the list was first written: a crash in both terminals (the survey's "A crash": the exception filter pays the
debt), the mouse in both (the survey's "Mouse": every button and modifier reported but Shift, which neither terminal
hands the app, and no pointer shapes in either, as TUI assumed), the keys in both, and in Windows Terminal under the
kitty protocol too (the survey's "Keys under the kitty protocol": every key as the specification has it; ⌃-, ⌥⇧-, ⌃,,
⌃⇧V, ⌃⇧P, ⌃⇧N, ⌃⇧D, ⌃⇧A and ⌃⇧. kept by its own bindings, all measured 2026-11-19), the chords Windows Terminal keeps
(`TerminalClient.keptChords`: none of them is named where the app names its keys, and one that works is named instead,
so Settings… shows F2 there, undo and redo ⌃Z and ⌃⇧Z, and the file panel's preview `=`; the owner's rule of 2026-11-19,
for every terminal, which replaced 2026-11-17's "Just ⌃, for now", with `keyboardShortcutFallback(_:)` for an app to
name its own other key; the rest of its default bindings that TUI's keys share measured 2026-11-20 by the owner's
hand, its full screen, scrolling, search, tabs and window kept and listed, a pane's resize and a copy with nothing
selected arriving whole, as the survey's "Keys under the kitty protocol" has it), and copies too large for the
terminal (over a measured 24,567 bytes of text: sent to this machine's clipboard at the desk, reported as not copied
over ssh), x86_64, and the console's font (conhost names it, and where it has no quadrants, as Consolas has none, shapes
cut their corners in whole cells and a canvas draws half blocks; asked again on each resize, which a font change sends;
the survey's "conhost's font"), and the glyphs it lacks of TUI's own (`◀ ▶ ◯`, sent as `◄ ► ○` where the font has those;
the survey's "Stand-ins").
