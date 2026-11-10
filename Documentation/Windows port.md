# Windows port

What it takes for TUI to be fully supported on Windows, which the owner made a 1.0 requirement on 2026-11-09
(API-STABILITY point 9: "WebAssembly and Windows need to be fully working and supported for 1.0"). This file is the
starting point for the session that does it, on a Windows VM, and the record it keeps as it goes, as
[WebAssembly port.md](<WebAssembly port.md>) is for that port.

## Where it stands (CI run 100, 2026-11-10)

- **Every module but `TUIApp` builds**, on all five Windows jobs (Windows Server 2022 with Swift 6.2, 6.3 and 6.4;
  Server 2025 and Windows 11 arm64 with 6.3): the 26 library modules from `TUICore` to `TUITabImages`, and the test
  targets of the four lowest. All of those steps are binding since 2026-11-10.
- **`TUIApp` does not**: 43 errors, all "cannot find … in scope" for POSIX names, in seven files:
  `FatalSignalTerminalRestore.swift` (26), `Terminal+LineDiscipline.swift` (9), `StallWatchdog.swift` (3),
  `UnreadQuitKeyWatch.swift` (2), `Terminal.swift`, `SystemClipboard.swift` and `QuitKeyReport.swift` (1 each). They
  are the first errors only: each file is the console layer — the run loop, raw mode, signals, the stdin source.
- So nothing above `TUIApp` (the umbrella `TUI`, `TUICommands`, `TUIScenes`, the Example), no app, and no test of
  an app runs on Windows yet.

A step allowed to fail reports "success" to GitHub's API, so read a job's log, not its step list, for what failed.

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
- Commit on a branch of your own and never push: the owner moves the work to the Mac, where it is gated and pushed
  to `staging` like everything else (CONTRIBUTING, "Staging and `main`"). Keep the macOS and Linux builds untouched
  by Windows arms: they are checked there, not on the VM.
- Record decisions and measurements in this file as you go, with their reasons.
