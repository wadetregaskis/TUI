# AGENTS.md

TUI is a terminal UI framework for Swift with SwiftUI's API. This page says where things are. It's written for coding agents, and it works just as well for people.

## Using TUI in an app

| To | Read |
|---|---|
| Add it to a package and run something | [Getting Started](Sources/TUI/TUI.docc/Articles/GettingStarted.md) |
| Bring SwiftUI knowledge or code across | [Coming from SwiftUI](Sources/TUI/TUI.docc/Articles/ComingFromSwiftUI.md) |
| Build a small app step by step | [Building Your First App](Sources/TUI/TUI.docc/Articles/BuildingYourFirstApp.md) |
| Test an app | [Testing Your App](Sources/TUI/TUI.docc/Articles/TestingYourApp.md) |
| Fix a compile error or odd behaviour | [Troubleshooting](Sources/TUI/TUI.docc/Articles/Troubleshooting.md) |
| Everything else | [The documentation site](https://swift-tui.com/docs/documentation/tui/) |

A compile error of the form `'x' is unavailable: …` is deliberate. It's a SwiftUI spelling TUI doesn't have, and the message says what to write instead.

## Working on TUI

**The rules are in [`.claude/CLAUDE.md`](.claude/CLAUDE.md). Read it before changing code.** It covers compatibility, SwiftUI API parity, how views are built, focus and state, and performance records. [`CONTRIBUTING.md`](CONTRIBUTING.md) has the reasons, and what CI checks.

```bash
swift build                                      # zero warnings, on every target
swift test --filter SuiteTypeName                # the Swift type, not the display name
Tools/ParallelTest/parallel_test.py -j 8         # the whole suite, far faster than swift test
swiftlint                                        # zero violations
Tools/BuildDocs/build-docs.sh --strict           # the documentation, as CI builds it
```

CI also builds and tests on Linux and builds four lower modules on Windows, so don't use Apple-only API outside `#if canImport`, in tests too.

## Where things are

| Looking for | Go to |
|---|---|
| The code's layout | `Sources/`, one folder per module. `Tools/ModuleMap` checks how they depend on each other |
| What's public and how it's meant to be used | `Sources/TUI/TUI.docc` |
| How the renderer works | [Architecture](Sources/TUI/TUI.docc/Articles/Architecture.md), [Render Cycle](Sources/TUI/TUI.docc/Articles/RenderCycle.md) |
| Designs, investigations and measurements | [`Documentation/README.md`](Documentation/README.md) |
| Why something is the way it is | [`Documentation/Historical`](Documentation/Historical/README.md). Search it by symbol before calling something a gap |
| What a terminal really does | [`Documentation/Terminals/Terminal compatibility survey.md`](<Documentation/Terminals/Terminal compatibility survey.md>). Measure with `Tools/TerminalProbes`, and record it there |
| How SwiftUI really behaves | `Tools/SwiftUIProbes`, which holds recorded measurements |
| API parity with SwiftUI | `Tools/APIParity`, and [the compatibility guide](<Documentation/SwiftUI parity/SwiftUI compatibility guide.md>) |
| Deliberate differences from SwiftUI | [`Deliberate deviations from SwiftUI.md`](<Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md>). Check here before "fixing" one |
| Decisions still open | [`Documentation/Open owner decisions.md`](<Documentation/Open owner decisions.md>) |
| Profiling and benchmarks | [`Tools/Profiling/README.md`](Tools/Profiling/README.md). `ab_bench.py` is the A/B tool, and its verdict is the result |
| Driving a real app in a pseudo-terminal | `Tools/Smoke` |

## Habits that matter here

- **Change behaviour and its documentation in one commit,** and keep each commit to one change.
- **Test through the real thing.** A test that can't fail when the feature breaks is worse than none. Prefer driving the app with `TUITesting`, and use the PTY smokes for what only a terminal shows.
- **Measure before claiming.** Say what you measured and what you inferred, and don't state a cause you haven't established.
- **A performance change quotes its profile in the commit message.** Never commit `.trace` bundles.
- **Stage explicit paths.** Don't commit or push unless asked.
