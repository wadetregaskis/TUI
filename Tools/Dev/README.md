# Working efficiently on TUI

For agents and people alike: the loop that costs the least to run and to read. Each habit here replaced one that cost
whole build-and-run cycles or thousands of lines of output to read.

## The loop: `Tools/Dev/quick.py`

```bash
Tools/Dev/quick.py build                     # build with tests: only errors and warnings, then one verdict line
Tools/Dev/quick.py test SuiteA SuiteB        # build, then those suites (Swift type names): only the failures
Tools/Dev/quick.py test --no-build SuiteA    # run again without building
Tools/Dev/quick.py lint [BASE]               # SwiftLint --strict on the Swift files changed since BASE (default: main)
Tools/Dev/quick.py all -- SuiteA SuiteB      # all three
```

It runs suites through `Tools/ParallelTest/parallel_test.py`, never bare `swift test`, which doesn't set up the
environment CI tests in, so colour tests fail spuriously. It reads a parallel_test "FAILED" that comes only from a
filter matching more tests than planned (every group passed) as the pass it is. And it gives SwiftLint Xcode's
toolchain, without which SwiftLint crashes loading SourceKit. `TUI_RUN_WRAPPER` prefixes the heavy steps with a
command of yours, such as a machine-wide build slot.

## Habits

- **Batch edits before building.** A build is minutes; an edit is seconds. Make every edit a fix needs, then build and
  run its tests once. Don't edit a tree while it builds or a gate runs over it: what was built is then not what is on
  disk.
- **Several edits in one call.** An edit that touches several places, or files, can be one script with an exact-match
  check on each replacement, rather than an edit call per place.
- **Ask for the line you need.** `git grep -n PATTERN -- PATHS` (options before the pattern: `git grep -n -A3 …`),
  `sed -n A,Bp FILE`, `--stat`, `--format=%h %s`. Read a long log through `grep -E 'error|warning: |FAILED|passed'`.
- **Don't poll.** A background build, test run or benchmark says when it is done. Checking it in between costs a call
  and tells nothing new; when an estimate is needed, compute it once from how far it has got.
- **Revert to prove a test.** A regression test that passes with its fix taken out tests nothing. Take the fix out,
  run the test, see it fail, put the fix back.
- **Keep the ratchets in your local check.** `python3 Tools/check-ratchets.py` (sleeps in tests, unsafe-concurrency
  exceptions) runs in CI's API-parity job, so a local loop that skips it learns about a rise from CI.

## The suite in release

```bash
python3 Tools/ParallelTest/parallel_test.py --release -j 4    # build -c release with the checks on, then run
python3 Tools/ParallelTest/parallel_test.py --release --no-build --filter SuiteName
```

Every other run tests a debug build. This one builds the tests with `-O`, as an app ships, but with the invariant
checks forced on: `assert` and `assertionFailure` kept (`-assert-config Debug`), the `#if DEBUG` checks compiled in
(`-DDEBUG`), plus what any release test build needs (`-enable-testing` for `@testable import`, and
`-DTUI_TEST_SUPPORT`, which the support targets define only for debug). `RELEASE_TEST_FLAGS` in
`Tools/ParallelTest/parallel_test.py` is the one list, and says why each flag is there. It is for what differs under
`-O`: inlining, specialisation, exclusivity, a check only a debug build made.

It is the dearest build there is, so CI runs it only on the weekly schedule and on manual dispatch, as two advisory
jobs (`release_tests_linux`, `release_tests_macos`). Locally it builds into `.build/release`, a second copy of the
build beside the debug one: check the disk first.

Where it stands (2026-11-07, macOS 15.8, Xcode 26.3's Swift 6.2.4): the release build of every test target succeeds,
after one fix (a closure in `EnvironmentStampTests` whose actor a release build did not infer). Running it does not yet:
asked to list its tests, the release test bundle starts a TUI app, which stops at "standard input and output are not a
terminal", and lists nothing. The debug bundle, with the same `Example_main` and `main` symbols, does not. The cause is
not established; the lane stays advisory until it is, and its first run on a Linux runner will say whether it is
macOS's alone.

## Seeing it in a real terminal

Tests check behaviour, not looks; a change to what is drawn wants a look in a real terminal. `Example --page NAME`
(a case name of `DemoPage` in `Sources/Example/ContentView.swift`) opens on that page, and `Tools/Dev/pty_script.py`
feeds the app scripted clicks and keys while the terminal draws its output unchanged. It is for when the window can be
seen but not typed into: an automation tier that allows screenshots only, or background clicks, which macOS hands to the
terminal as a text selection, never as a mouse report the app could read.

```bash
cat > /tmp/look.command <<'X'
#!/bin/zsh
printf '\e[8;72;150t'; sleep 0.5        # resize the window to 150×72 first, so cell positions are known
Tools/Dev/pty_script.py '6,38;13,39;f6' -- .build/debug/Example --page overlays
X
chmod +x /tmp/look.command; open -a Terminal /tmp/look.command
```

Clicks are `COL,ROW` cells, 1-based: read them off a first screenshot (the window's content width over its columns,
and its height over its rows). Use a fresh `TUI_CONFIG_DIR` so the run leaves your settings alone.
