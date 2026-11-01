# TUI and SwiftTUI: a comparison, November 2026

**In short.** In the last days of October 2026 the owner asked for a competitive analysis of TUI against SwiftTUI (`github.com/SwiftTUI/swift-tui`, swifttui.sh). I read its source, then built and ran both. The first report expected SwiftTUI's retained engine to scale better. Measured, it doesn't: TUI is 5 to 100 times faster per interaction in most of what I tried, and uses far less memory. SwiftTUI wins in four places, the first of which TUI should fix: slow bodies whose inputs didn't change, compositing many blended layers, output bytes while scrolling, and idle with a focused control (which the owner accepted as the cost of breathing). SwiftTUI's real strengths are outside the engine: accessibility, tooling and hosts.

**Why this is kept.** To compare progress after optimisation, and to remember what was decided and why. To re-measure, use `Tools/SwiftTUIComparison`, whose README says how, and compare against its committed baseline.

**Versions measured.** TUI `3d605c2c4`. SwiftTUI `207913d23`, just after 0.20.0. Swift 6.4.0, release, on one macOS 15.8.1 arm64 VM, 14 cores, 32 GB, shared with other work. Treat timings as rough. Allocation counts and bytes repeat well.

## The numbers to beat, or keep

From `Answers, engine, size and safety.md`, which has ranges, caveats and method.

| Measure | TUI | SwiftTUI |
|---|---:|---:|
| One leaf changes, 1,920 cells, key to frame | 2 ms | 120 ms |
| Same, allocations | 642 | 469,700 |
| Small page, 40 cells, key to frame | 0.7 ms | 7 ms |
| **Two 50 ms sibling bodies with unchanged inputs** | **216 ms** | **28 ms** |
| **30 blended full-screen layers, frames per second** | **0.64** | **1.6** |
| **Wheel notch, dissimilar rows, bytes** | **10,200** | **290** |
| `List`, 10,000 rows, no stated height, per key | 1.3 ms | 1,578 ms |
| `List`, 10,000 rows, stated height, allocations per key | 1,861 | 32,200 |
| `Table`, 10,000 rows, no stated height, peak memory | 12 MB | 25 GB |
| 1,920 cells, memory | 20 MB | 154 MB |
| Hello, stripped size, selective modules | 8.56 MB | 21.45 MB |
| Deepest plain `VStack` nesting drawn | about 1,000 | about 180 |

The rows in bold are where SwiftTUI wins, and they are the ones to improve first.

## What is here

| File | What it holds |
|---|---|
| `The first report, evidence and claims.md` | The evidence behind the first report: read from source, before anything was built. Some of its expectations were wrong, and the answers correct them. |
| `Answers, summary and later updates.md` | The summary, questions 13 and 26, and what changed afterwards, including how questions 1 and 16 turned out. |
| `Answers, features.md` | Questions 1 to 12, 17 to 25, 27 to 29 and 33 to 37: what each SwiftTUI feature is, whether TUI has it, what it would take. |
| `Answers, engine, size and safety.md` | Questions 14, 15, 16, 30, 31 and 32: engines, size, tests, memory and concurrency safety. |

Those are as written at the time, in the owner's numbering, and say "you" to the owner.

## What the owner decided, 2026-11-01

They reviewed questions 1 to 12 and some others, with more to come.

| Subject | Decision |
|---|---|
| Arguments | TUI never takes over launch or parses arguments. An optional module could use swift-argument-parser, only if the dependency arrives only when used. |
| Colour conventions | `NO_COLOR`, `FORCE_COLOR`, `CLICOLOR` per their rules, keeping bold. Done. |
| ASCII-only mode | Makes no sense. Instead, degrade gracefully where a terminal truly can't draw something, and don't encourage it except in testing. |
| Environment variables | Precisely documented, including how they interact with code, easy to find, and easy for an app to put in its own man page, automatically. |
| Native GUI hosts | Never: use SwiftUI, or embed with SwiftTerm. |
| Browser without a terminal host | Not dismissed, not a priority. Reconsider later. |
| Hot reload | Wanted after 1.0, with a design doc now. Hot restart rejected, since it loses all state TUI doesn't know of. |
| Sixel | Kitty classic placements first, then revisit Sixel's limits. Needed for Windows. |
| `Canvas` | Yes, SwiftUI's, with TUI extensions if it inspires any. |
| Local web server | Never by default, and never a listening port unasked. Only as a separate package on standard Swift packages. |
| `DocumentGroup` | Yes. `FileWrapper` on Linux is the real question. |
| AI in the code | No. An `AGENTS.md` instead. |
| Pixel mouse | Wanted, with SwiftUI's types if it serves a purpose. |
| Engine | Keep the design, take ideas, aim to beat SwiftTUI everywhere. No trading memory for speed, keep scaling linear at worst, threads only with great care. |
| Scrolling | Wanted. Consider several approaches and hybrids. Say if it has a cost. |
| Running bodies twice | More work wanted. |
| Blank page at the depth limit | Fix it. |
| Frame cap | 60 Hz default, configurable. Already so: `App.maxFrameRate`. |
| Breathing | Stays. |
| Strict memory safety | Adopt, at low priority. |
| Unsafe concurrency | Kept to twelve exceptions, with a lint rule against more. A note on what macOS 26 would allow. |
| FIGlet | No 7 MB cost for a neat feature. |

## For a future reader

- SwiftTUI moves quickly. Every statement here about it is as of `207913d23`, and it may have changed.
- These benchmarks are my own synthetic scenes, written for one source to compile against both, so they don't show how a SwiftTUI app written its own way would do. They didn't try SwiftTUI's `.equatable()` boundaries.
- A wide margin at 1,920 cells doesn't mean a typical page feels different: at 50 to 300 views SwiftTUI costs 7 to 20 ms a key, which feels fine.
- Part of SwiftTUI's per-frame cost buys hosts and a semantic tree that TUI doesn't have. If TUI gains an accessibility tree, re-measure before assuming the margin holds.
