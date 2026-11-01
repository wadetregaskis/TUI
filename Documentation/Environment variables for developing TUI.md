# Environment variables for developing TUI

These are for working on TUI itself, or are read only by its tests, tools and demos. Someone using TUI has no use for
them, so they aren't on the website. What's for them is in
[Environment Variables](../Sources/TUI/TUI.docc/Articles/EnvironmentVariables.md), generated from the table in
`Sources/TUIEnvironmentDocs`.

## Adding a variable

`Tests/TUIEnvironmentDocsTests` fails if a variable is read in `Sources`, or named in `Tests`, `Tools`, `Benchmarks`,
`scripts` or `.github`, and isn't listed anywhere. So when you add one:

1. Decide who it's for.
   - Someone running an app, or building one: add a row to the table in `Sources/TUIEnvironmentDocs`, then run
     `swift run tui-environment-docs --update-article` to rewrite the article's generated tables. Say what code can do
     about it, under the rule at the top of the article.
   - Someone debugging TUI, or only a test or a tool: add it to `Tests/TUIEnvironmentDocsTests/InternalVariables.swift`
     and to a table here.
2. Follow the conventions: `1` and `0` for on and off, an empty value as unset (`ColorRequest.stated`), and anything
   else ignored rather than guessed at.
3. Read it through a function that takes the environment as a parameter, as `ColorDepth.detect(environment:)` does, so
   that a test can pose the question without writing to the one environment every thread reads. A lazily initialized
   `static let` over that function is what makes it read once.
4. If the app should be able to state the same thing, follow the shape of `TerminalClient.graphicsSupport`: an override,
   then the variable, then what was detected.

## Why the man page comes from an executable, not a plugin

`swift run tui-environment-docs` was first a command plugin, `swift package tui-environment-docs`. Measured on 2026-11-01
with a hello-world app on `TUIApp`, built with `swift build -c release` against a path dependency:

| | Stripped size | In the build's log |
|---|---|---|
| The tree before any of this | 9,109,496 bytes | Nothing |
| With the plugin in the package | 9,109,496 bytes | `[1/1] Compiling plugin TUIEnvironmentDocsPlugin`, before anything else |
| With the executable in the package | 9,109,496 bytes | Nothing |
| With the executable, and the app listing `TUIEnvironmentDocs` and printing the section | 9,159,512 bytes | The module's own files |

So the plugin added no bytes, but it did add a compile to every client's clean build, which is what this was not to do:
SwiftPM compiles every plugin of a package in the graph, used or not, and it builds an executable of a dependency only
when asked. The plugin also needed `--allow-writing-to-package-directory` in a script, even to print. A plugin in a
package of its own would avoid the compile, and would need a second repository and a second dependency.

The last row includes the flags example from the article (`ColorDepth.current`, `TerminalClient`), so the text itself is
at most those 50,016 bytes. `swift run tui-environment-docs` took 13 s from a client that had built nothing of it, and
SwiftPM's messages go to standard error, so its standard output is the text alone.

## The framework

Read by the library modules, for debugging them.

| Variable | Values | What it does |
|---|---|---|
| `TUI_DEBUG_FOCUS` | `1` | Logs the focus system, mouse dispatch and text fields to `/tmp/tui-debug.log`. Read once. |
| `TUI_OBSERVATION_RETIREMENT` | A name of `ObservationLeases.Retirement` | Which rule a new render cache cancels its observation scopes by, to compare them. `leases` by default. |
| `TUI_OPTION_C` | `0` | Turns off the render cache's re-checking of a row's value when its data moves (Option C), to compare with and without. |

## The Example and Stress targets

Read only by those two executables, for clips, sweeps and measuring. `Sources/Stress/README.md` has more on Stress's.

| Variable | Values | What it does |
|---|---|---|
| `TUI_EXAMPLE_PICTURE` | A picture's name, in any case | The picture the image page opens on, for a clip of one in particular. |
| `TUI_EXAMPLE_PALETTE_ALPHA` | `0` to `1` | Fades the whole palette, to run the faded-palette sweep (`Tools/Smoke/faded_palette_sweep.py`). |
| `TUI_EXAMPLE_GROUND_ALPHA` | `0` to `1` | Fades the ground alone, to show that the framework survives a ground with nothing behind it. |
| `TUI_STRESS_SCALE` | A whole number | How much of each scenario to build. |
| `TUI_STRESS_SEED` | A whole number | The seed of the scenario's random data. |
| `TUI_STRESS_AUTOPILOT` | `1` or `true` | Runs the scenario without input. |
| `TUI_STRESS_SCENARIO` | A scenario's name | The scenario to open on. |
| `TUI_STRESS_VARIANT` | A variant's name | The scenario's variant. |
| `TUI_STRESS_STRIPES` | A stripe set's name | The stripes that state is kept in. |

Stress's command-line flags override these, which is the rule at the top of the article, applied by an app of our own.

## The manifest, the tests and the tools

Read or set by nothing a client of the package builds, except `TUI_BENCHMARKS`, which a client's `Context.environment`
could see and wouldn't set.

| Variable | Where | What it does |
|---|---|---|
| `TUI_BENCHMARKS` | `Package.swift` | Adds the ordo-one benchmark dependency and the `TUIBenchmarks` target. |
| `TUI_BENCH_RUN_VIEW` | `Benchmarks/TUIBenchmarks` | `1` runs the benchmarks that draw views. |
| `TUI_BENCH_MAX_DURATION_MS` | `Benchmarks/TUIBenchmarks` | How long each benchmark runs, in milliseconds. |
| `TUI_AUDIT_DUMP` | `NoColorAuditTests` | A file to write what the audit found to, for a person to read. |
| `TUI_MEASURE_FLEX_PROBE` | `MeasureRenderEquivalenceTests` | Any value runs the probe that reports flexibility. |
| `TUI_SEED_MECHANISM_PROBE` | `TerminalIdentityQueryTests` | A test's own variable, written and read to show how seeding works. |
| `TUI_PARALLEL_TEST_LOCK` | `Tools/ParallelTest/parallel_test.py` | The path of the lock that keeps a second run out. |
| `TUI_PARALLEL_TEST_STALL_SECONDS` | `Tools/ParallelTest/parallel_test.py` | How long a shard may say nothing before it counts as stuck. |
| `TUI_PRODUCT_SMOKE_URL` | `Tools/ProductSmoke` | Where the fixture resolves TUI from. |
| `TUI_WASM_TOOLCHAIN` | `Tools/Web/build.sh` | The Swift version to build the web demo with. |
| `TUI_WASM_SDK` | `Tools/Web/build.sh` | The WebAssembly SDK's name. |
| `TUI_WASM_SWIFT` | `Tools/Web/build.sh` | The `swift` command to use. |

## Not variables

`TUI_TEST_SUPPORT` and `TUI_VALUE_HASH_CENSUS` look like variables and are compile-time conditions, set with `-D`.
`TUI_X` and `TUI_Y` are names a test makes up.
`TUI_TUIStrings` is the resource bundle.

## TUI writes one

`TUI_TERM_PROGRAM` is the one variable TUI writes as well as reads: when the startup exchange names a terminal that the
environment didn't, `TerminalHost.seedDiscoveredHost` sets it (it reads as though the person had, so every detector agrees).
A program the app starts inherits it. `.swiftlint.yml`'s `process_terminal_environment_mutation` keeps the tests from
writing the variables that latch.
