# Raising the minimum Swift to 6.4

The owner asked on 2026-11-08 whether raising TUI's minimum compiler from Swift 6.2 to 6.4 would pay, mainly by allowing wider use of `Span`. This note gives the answer, the measurements behind it, and what would change the answer. Everything here was compiled or run on this machine (macOS 15.8, Xcode 26.3 with its Swift 6.2.4, swift.org's 6.3.3 and 6.4.0, the macOS 26.2 SDK) unless it says otherwise. The prototypes are on the branch `study/swift64-min` and were not written to be landed.

**Recommendation: don't raise the minimum to 6.4 now.** At TUI's macOS 15 floor, 6.4 makes no `Span` use possible that 6.2 can't already compile. What blocks `Span` is the deployment target: `Array.span`, `String.utf8.span`, `InlineArray` and `UTF8Span` are all macOS 26 APIs on every compiler. And where TUI's hot code could use a `Span` it already uses unsafe buffers, which are faster: putting a `Span` in their place cost nothing measurable in two prototypes, about 4% in the third, and 15 to 70% in a micro-benchmark. Most render time goes on reference counting, hashing, allocation and runtime metadata, and a `Span` doesn't touch any of those. A rise to 6.3 has a stronger case than one to 6.4, for a different reason (see [the costs](#what-it-would-cost)). Look at this again when the deployment floor goes to macOS 26 ([Raising the floor to macOS 26](<Raising the floor to macOS 26.md>)), or when the next Xcode makes 6.4 the oldest compiler people use.

## What 6.4 has that 6.2 lacks

Each row was compiled with all three compilers, at a macOS 15 target and a macOS 26 target, by a probe script (`-typecheck`, `-swift-version 6`). "15" means it compiles at TUI's current floor.

| Feature | 6.2.4 | 6.3.3 | 6.4.0 | What limits it |
|---|---|---|---|---|
| The `Span`, `MutableSpan`, `RawSpan` and `OutputSpan` types, `UnsafeBufferPointer.span` / `.mutableSpan`, `RawSpan(_unsafeBytes:)`, `Data.span` / `.bytes` | 15 | 15 | 15 | Nothing. The types are back-deployed to macOS 10.14.4 |
| `Array`, `ContiguousArray` and `ArraySlice` `.span` / `.mutableSpan`; `String` and `Substring` `.utf8.span`; `.utf8Span` (`UTF8Span`); `String(copying:)`; `InlineArray` and its `[4 of T]` sugar; `Task.immediate` | 26 | 26 | 26 | **The deployment target**: "only available in macOS 26.0 or newer" on every compiler |
| `Array(capacity:initializingWith:)` and `append(addingCapacity:initializingWith:)`, which fill an array through an `OutputSpan` | no | 15 | 15 | The compiler (6.3) |
| `withTemporaryAllocation(of:capacity:)` handing over an `OutputSpan` | no | no | 15 | The compiler (6.4) |
| A safe `RawSpan.load(fromByteOffset:as:)` / `MutableRawSpan.load` for `ConvertibleFromBytes` types, and a safe `bitCast(_:to:)` | no | no | 15 | The compiler (6.4). Every other `RawSpan` load is still `unsafeLoad` |
| `@inline(always)`, `@export(implementation)`, `@specialized`, `@c` | no | 15 | 15 | The compiler (6.3). Each one is an official spelling of something 6.2 already has: `@inline(__always)`, `@_alwaysEmitIntoClient`, `@_specialize` and `@_cdecl`. No new codegen |
| Returning a `Span` from a function or property (`@_lifetime`), and a `~Escapable` type of your own that holds one | exp. | exp. | exp. | **Experimental on all three** (`-enable-experimental-feature Lifetimes`). The official `@lifetime` spelling needs `LifetimeDependence` even on 6.4. Works at 15 with the flag |
| `yielding borrow` / `yielding mutate` | no | no | exp. | Experimental (`CoroutineAccessors`). With the flag 6.4 warns that `read` / `modify` are deprecated. `_read` / `_modify` compile on all three without a flag, as `.claude/CLAUDE.md` says |
| A `for … in` loop over a `Span` (`Iterable`), `makeBorrowingIterator()`, `UniqueArray`, `UniqueBox` | no | no | 27 | macOS 27, on 6.4. `RigidArray` isn't in the standard library at all |
| `InlineArray` `==`; `String.append(contentsOf:)` from a `Span`; a `String` initializer that fills an `OutputSpan` | no | no | no | Not in any of the three |
| `Mutex`, `Atomic`, `~Copyable` generics with `Optional`, `borrowing` switches over noncopyable enums | 15 | 15 | 15 | Nothing. TUI already uses them |

**Strict memory safety.** On 6.4 a call whose closure takes an unsafe type (`withUnsafeBufferPointer { … }`) no longer needs `unsafe`, and writing it anyway is a warning. 6.2 and 6.3 want the `unsafe`. That is why `Package.swift` turns `strictMemorySafety()` on only from 6.4. A 6.4 minimum would make it one spelling everywhere and let that `#if` go. The checking itself doesn't change, because CI's 6.4 lanes already do it. `String(unsafeFormat:)` would not go: it exists because Apple's Foundation marks `String(format:)` `@unsafe` and swift-corelibs-foundation doesn't (its doc comment measured that on 6.4). That is a library difference, not a compiler one.

**Linking.** At a macOS 15 target, concrete code that uses these types links nothing from `libswiftCompatibilitySpan.dylib`. That held for `UnsafeBufferPointer.span`, `Array(capacity:initializingWith:)`, `withTemporaryAllocation`'s `OutputSpan`, a noncopyable owner that vends a `Span`, and the prototypes' release `Stress` and `ImageHarness` (`Tools/check-span-compatibility.sh`). Generic code and debug builds still can link it, as `Tools/check-span-compatibility.sh` explains, so that check stays at any compiler minimum. Only a macOS 26 floor removes it.

**Linux, WebAssembly and Windows.** These have no availability gates, so on Linux `Array.span` and the rest already compile with 6.2. But code shared with macOS has to compile at the macOS 15 target too. swift.org ships 6.4.0 for Linux, for Windows (the `swift:6.4-windowsservercore-ltsc2022` image CI's Windows lane already uses) and with a WebAssembly SDK, so a 6.4 minimum shuts out no platform. The wasm lane is on 6.3.3 only because nobody has measured the port on 6.4 yet (`ci.yml`).

## Where it would matter in TUI

**What the hot paths spend their time on.** `sample` was run for 8 s on release `Stress` built with 6.4.0, against `--bench` for the render half and `--autopilot` in a PTY (`TERM_PROGRAM=ghostty`) for both halves. Self time was bucketed after idle thread waits were dropped:

| Scenario | ARC | malloc / free | hashing, dictionaries | runtime metadata, casts, exclusivity | byte and string scanning (what a `Span` could reach) |
|---|---|---|---|---|---|
| `fanout` (bench) | 41% | 0% | 28% | 1% | 0% |
| `textwall` (bench) | 36% | 5% | 22% | 8% | 0.3% |
| `kitchensink` (bench) | 31% | 7% | 14% | 12% | 0.5% |
| `dashboard` (bench) | 25% | 8% | 17% | 9% | 2% |
| `churn` (bench) | 26% | 18% | 10% | 17% | 7% |
| `churn` (live, both halves) | 30% | 18% | 10% | 19% | 7% |
| `session/notes` (bench) | 17% | 13% | 9% | 22% | 12%, 3.7 points of it `SGRColorRewrite.rewritingSGR` |

The buckets are regex matches on symbol names, so treat them as a few points either way. The other live scenarios were too idle at the autopilot's frame rate to sample well (34 to 170 on-CPU samples). Most of the rest is TUI's own code: `RetainedSubtreeIndex.retains`, `RenderCache.removeInactive`, `Array.replaceSubrange`, plus the harness's own checksum (`Headless.mixed`). The image pipeline is the exception. There, resampling and dithering are almost all buffer arithmetic.

**Each candidate the brief named:**

- **Frame diff writer, SGR emission, row assembly.** A frame is an array of ANSI `String` lines, not a cell array, so this work goes through `String`, its UTF-8 bytes (`withUTF8`, `withContiguousStorageIfAvailable`) and `String.append`. The byte loops would take a `Span` from the buffer those calls lend. That works on 6.2 at macOS 15. What a `Span` can't do on any compiler is build a `String`: there is no `append` or initializer from a `Span` or `OutputSpan`, so the boundary stays an unsafe buffer. `String+SGRCollapsing.swift` appends slices with `UnsafeBufferPointer(rebasing:)`, for example. **Nothing here is blocked on 6.2.**
- **String width.** `asciiStrippedLength`, the most-executed width path, loops over the bytes `withContiguousStorageIfAvailable` lends. Prototype 1 below. A `Span` from `utf8.span` directly needs macOS 26. **Nothing here is blocked on 6.2.**
- **`ValueHashPlans` (the SAFE lane).** Its unsafety is of two kinds. One is its own table and plans: raw memory it allocates, owns and frees. A safe version of that wants an owned, noncopyable buffer that hands out `Span`s. `UniqueArray` is that, but it is macOS 27. A hand-written owner that vends a `Span` compiles at macOS 15 on 6.2, 6.3 and 6.4 alike, and only with the experimental `Lifetimes` feature. The other is the hash steps, which read fields of arbitrary types at offsets taken from metadata: references, existentials, generic payloads. A `RawSpan` can read only `BitwiseCopyable` values, and safely only `ConvertibleFromBytes` ones (6.4), so those reads stay `unsafe` whatever the compiler. **6.4 makes a safe `ValueHashPlans` no more possible.** At most it makes the integer reads of a step safe.
- **Images: resampling, dithering, Sixel, decoders.** All of these fill or read `[UInt8]` / `[RGBA]` through unsafe buffers. **6.3** adds `Array(capacity:initializingWith:)`, a safe way to fill a new array. That is prototype 3, and with `withTemporaryAllocation`'s `OutputSpan` (6.4) it is where a newer compiler adds most at macOS 15. **6.4** adds the safe `RawSpan.load` and `bitCast`, which suit decoders reading integers from bytes (the GIF decoder, `RGBAImage`). Neither one is about speed.

## The prototypes

Three spots, each behind `#if compiler(>=6.4) && STUDY_SPAN` in the same tree. "base" was built without `-DSTUDY_SPAN` and "proto" with it, both by swift.org 6.4.0 in release with `-g`, so the only difference is the code. All three compile at macOS 15 with no warnings under strict memory safety, and the `unsafe` left in each is the one that takes the span from its buffer.

1. **`String.asciiWidth` over a `Span<UInt8>`** (`String+TerminalWidth.swift`), the span taken from the `withContiguousStorageIfAvailable` buffer. Compiles on 6.2.
2. **Floyd–Steinberg dithering over a `MutableSpan<RGBA>`** (`ASCIIConverter+Dithering.swift`), the span taken from `withUnsafeMutableBufferPointer`. Compiles on 6.2.
3. **`RGBAImage.scaledBilinear` written through an `OutputSpan`** (`Array(capacity:initializingWith:)`) and read through `Span`s (`RGBAImage.swift`). Needs 6.3.

**Results.** All runs were under `slot.py --exclusive` on a shared machine. Its load average was 2 to 4 during the runs and reached 8 by the end of the last image run, so read the last image run with care. Correctness: `Stress --selfcheck` gave identical checksums for all 152 lines, and every image run gave equal pixel checksums.

| Prototype | Measured with | Change, proto against base | Floor (A/A) |
|---|---|---|---|
| 1. width over `Span` | `ab_bench.py` on `textwall truncate fanout kitchensink churn dashboard megalist session/notes session/log`, twice | **Indistinguishable** in all 18 verdicts. Medians from −1.2% to +3.6% (`truncate` +0.0 then +2.4%, `textwall` +1.7 then +1.9%) | The same suite, base against base: −3.5% to +3.4%, all indistinguishable |
| 2. dithering over `MutableSpan` | `ImageHarness --path pixel --dither floyd`, base and proto alternated, median of 7 to 15 rounds, four runs | `ansi16`: +3.9, +1.1, −2.1, +0.6%. `mono`: +0.2, +4.6, −2.6, +3.0%. **Indistinguishable**: each run's spread was 6 to 27% | −0.7% and −0.4% |
| 3. resampling through `OutputSpan` and `Span` | `ImageHarness --path pixel --mode truecolor` (resampling only), same method | +13.4% and +7.5% (6 iterations a run), then +3.6% and +3.7% (40 iterations). **About 4% slower**, in the same direction every time | −0.3% |

So none of the three got faster. The byte scan (1) and the dithering (2) didn't move. The one whose time is mostly the `Span` reads and writes themselves (3) got slower.

**Why a `Span` is slower than the buffer it replaces.** Every `Span` subscript is checked. A standalone loop shows that apart from TUI (`-O`, macOS 15 target, best of 7, two runs per compiler, results in ns per byte):

| Loop | 6.2.4 | 6.4.0 |
|---|---|---|
| `asciiWidth`'s state machine, `UnsafeBufferPointer` | 0.83 / 1.05 | 0.91 / 0.93 |
| the same, `Span` | 1.20 / 1.20 | 1.31 / 1.15 |
| a data-dependent table lookup, `UnsafeBufferPointer` | 0.22 / 0.23 | 0.21 / 0.23 |
| the same, `Span` | 0.38 / 0.31 | 0.33 / 0.33 |

A sequential scan costs 15 to 45% more and a gather 40 to 70% more, about the same on both compilers, so 6.4 doesn't make a `Span` cheaper. A `Span` is a safety tool. It would beat code that indexes an `Array` inside a loop, but TUI's hot loops moved to unsafe buffers long ago, and several of their comments record the measurement that moved them.

## What it would cost

- **Who'd be cut off.** On macOS, 6.4 comes only with Xcode 27 or swift.org's toolchain. `ci.yml` notes that no Xcode puts 6.4 on macOS 26, so an app developer on Xcode 26 (6.2 up to 26.3, 6.3 from 26.4) couldn't build TUI any more. `swift-tools-version: 6.4` would also stop SwiftPM resolving the package on older toolchains, for every app that depends on it.
- **CI.** The 6.2 and 6.3 lanes go (macOS 15 and 26 with Xcode 26, `swift:6.2-noble` and `swift:6.3-noble`, Windows 6.2 and 6.3), and with them the 6.2.4 type-check guard (`-solver-scope-threshold`). The macOS lane would run on swift.org's 6.4 on `macos-26` or on the `xcode-27` image, which is still marked preview and can queue.
- **Work.** Raising the floor is small: `Package.swift` (its `swift-tools-version` and the strict-memory-safety `#if`), CI, `.claude/CLAUDE.md`, `CONTRIBUTING.md`'s matrix, and the one version branch in `TypeWalkTests`. Using `Span` is the real work, and it would make the code slower and only somewhat safer.

**6.3 has a better case than 6.4.** 6.2.4 asserts on `TupleView`'s pack-expansion conformance when building `TUIView` for the static Linux SDK and for WebAssembly, which is why the wasm lane is on 6.3.3 (`ci.yml`). It also has none of the 6.3 attributes or `Array(capacity:initializingWith:)`. A 6.3 minimum would cut off only Xcode 26.0 to 26.3, which still run on macOS 15. This study didn't measure that change, so it is only an option.

## What would change the answer

- **A macOS 26 floor** makes `Array.span`, `String.utf8.span` and `InlineArray` usable without a buffer closure. That doesn't depend on the compiler: 6.2 has them at a macOS 26 target.
- **A macOS 27 floor with 6.4**: `UniqueArray` and `UniqueBox`, the owned buffers a safe `ValueHashPlans` table would want, and `for … in` over a `Span`.
- **`Lifetimes` leaving experimental**, so that a type of TUI's own can hand out a `Span` with no flag.
- **A profile where byte scanning is the cost.** At most it was 12% of self time (`session/notes`), and the unsafe code there already runs at full speed.
