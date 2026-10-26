# Completing the SwiftUI API: decisions from lane TC1

*Lane TC1 is the type-check half of the owner's request of 2026-10-07 to cut
TUI's clean release compile time: profile the build with
`-debug-time-function-bodies` and `-debug-time-expression-type-checking` and
make the simple fixes that ease the compiler's work, in the modules the split
has already carved out and in the test targets, which every lane builds. It
changed no public API and no behaviour. This file holds the judgement calls the
work reached that the request did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-TC1-n — needs your decision.** Nothing has shipped for these.
- **B-TC1-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-TC1-n — declined.** With the reason.

All times are Xcode 26.3's Swift 6.2.4 on the shared 16 GiB VM. "WMO" is a
module type-checked whole (`-typecheck`), "primary-file" is the given files
type-checked as primaries with the rest of their target secondary (as a debug
build's batch jobs do), min of 3 runs; both are noisy to about ±10%.

## A. Needs your decision

### A-TC1-1. Exit tests' bodies could move into helper functions

*38 `#expect(processExitsWith:)` tests in 18 files of TUITests*

Swift Testing 6.2's exit-test macro type-checks the closure's body twice: once
where it is written, as part of the `#expect` expression, and once in the
function the macro generates from a copy of it. Each of these closures holds a
whole test (`await MainActor.run { … }` with several `#expect`s inside), so
each exit test costs 200–700 ms to type-check, the largest single items left in
TUITests after this lane.

Moving a body into a `@MainActor private static func …Body()` and calling it
from the closure (`await MainActor.run { Self.gateOpenReachesTheOpenerBody() }`)
measured, for the two largest in `TerminalURLOpeningTests.swift`
(primary-file): the file's expressions 714.7 → 369.3 ms, about −170 ms per exit
test, plus the generated copy's body (about 100–170 ms each in WMO). Across all
38: roughly −7 to −10 s of type checking in a WMO run, −4 to −6 s of CPU in a
debug build (extrapolated from two, unmeasured as a whole).

**The price** is readability: each exit test's assertions move out of the test
function into a helper beside it, where the `#expect(processExitsWith:)` no
longer shows what the child process checks. The lane's brief said "contorting
a test is not [fine]", so nothing shipped. **Options:** (a) do it for all 38;
(b) only where the body is over ~20 lines; (c) leave them (the default).

**2026-10-12, the owner asked what the price means.** An exit test's trailing
closure is the code the *child process* runs: Swift Testing relaunches the test
binary to run only that closure, and the parent checks how the child exited,
with the child's own `#expect`s forwarded to it. So the closure's body *is*
what the child checks. Moved into a helper, the test reads only

```swift
await #expect(processExitsWith: .success) {
    await MainActor.run { Self.overridePublishesBody() }
}
```

and its setup and expectations are in another function. **What was measured
since** (session notes `EXITTC/research.md` §8.1, on 6.4.0): the exit tests'
in-place type-check totals about 2 s of a ~700 s whole-module type check of the
test target (≈0.2%), so the −7 to −10 s above overstated it at least 3.5
times. That was over 43 exit tests; on 2026-10-19 there are 60, in 28 files across nine test targets. The
recommendation stays **(c), leave them**; if the saving is ever wanted, a
smaller rewrite keeps the body in the test as a local `inChild()` function
passed as `performing:` ([Future options](<../../../Future options.md#exit-tests-bodies-as-functions>)).
Still yours to answer.

## B. Shipped the safe option

### B-TC1-1. TUITests' `#expect` floor: only the outliers were rewritten

*TUITests, about 25,000 `#expect`/`#require` lines*

In TUITests an `#expect` costs 14.8 ms to type-check on average in a WMO run
and 8.2 ms in the debug build's batch jobs; in the per-module test targets
(TUICoreTests, TUIStylingTests, TUIViewTests, TUIImageTests) it is
3–4 ms (5.4 in batch). With 25,000 of them, that floor is most of the target's
374 s (WMO) / 241 s (batch CPU) of expression type checking. The lane rewrote
the outliers only: about a hundred lines of 44 ms to 4.4 s each, by naming an
operand that was an operator chain, a literal, a closure or an implicit member
in a typed `let` before the `#expect` (`#expect` keeps the comparison, so the
failure message still prints both sides).

A probe (40 trivial `#expect(xs.count == N)`, primary-file, median of 3)
priced the floor's parts:

| probe file's imports | in TUITests | in TUICoreTests |
|---|---|---|
| `Testing` only | 5.9 ms per `#expect` | 3.6 ms |
| `Testing`, `TUICore` | 6.3 ms | 3.6 ms |
| `Testing`, `TUI` | 7.0 ms | — |
| `Testing`, `TUI`, `@testable TUIFoundation` | 8.1 ms | — |

So about two thirds of the difference is the module itself, not the file's
imports: a plain `a == b` in TUITests weighs 169 `==` overloads against 105
in TUICoreTests, the 64 extra being TUITests' own hand-written `static
func ==` (66 of them, mostly memo-test views whose partial equality is the
point of the test, so they cannot be synthesized). The rest is the umbrella
import and `@testable`.

**The fuller versions, and their price:**

- **Rewrite every `#expect` over 20 ms** (4,100 lines, 123 s in WMO, 48 s of
  batch CPU): a churn pass over a fifth of the suite for perhaps half of that,
  each line a typed `let` more. Not recommended.
- **Move tests out of TUITests as the split carves modules**, into per-module
  test targets that import only their module: the floor there is half, and
  each target compiles in parallel. This is the structural lever, and it
  belongs to the split's test-target plan rather than to this lane.

**Status, 2026-10-10.** Lane TT2 (b377b5f24) split the umbrella suite into four
test targets **by area**, each under 8,000 `#expect`s, rather than into
module-only targets: all four still import the umbrella and `@testable`
TUITestSupport. Measured by TT2 (CPU, two repeats): a one-file test edit
costs about 18 CPU s instead of about 60, and a rebuild of every test file
100 s (6.2.4) and 228 s (6.4.0) less, at or above what the module-only lever
was estimated to buy; wall time moved only 5 to 12 s. What is left is the import
part of the floor, unmeasured since the split (at most about 72 CPU s a full
rebuild, by estimate); both fuller versions are recorded in
[Future options](<../../../Future options.md#the-rest-of-the-test-targets-expect-floor>).

## C. Declined

### C-TC1-1. MemberImportVisibility on the test targets

It would hide Foundation's operator members from the test files that do not
import Foundation (950 of TUITests' 1,177). Measured on two such files
(primary-file, 547 expressions): 1,009.2 ms without it, 1,016.2 ms with it —
no change, and two files needed `import Foundation` added. Operator lookup is
not what that feature scopes.

### C-TC1-2. Rewrites that changed the optimised code

The library rewrites were each checked against whole-module `-O` assembly,
function by function. Four first spellings changed it and were respelled or
dropped: `UInt8(truncatingIfNeeded:)` in `StripeKey.colour` made it cheap enough
for the inliner to take into more callers; the same in `RowFills.entry`'s
`near` re-scheduled `rowFills(at:over:)`; `Int(truncatingIfNeeded:)` in
`KittyGraphics.base64`'s tail lost the optimiser's proof that `index + 1`
cannot overflow; and `RowFills.rowFills(at:over:)`'s `packed` (6.8 ms) split at
typed lets re-scheduled its registers. The first two keep their checked
conversions with a named, typed `UInt32` mask instead. The third keeps its
checked `Int` conversions and its mask, already a named, typed constant, and
types its first two sextets as `UInt32` lets instead. The fourth is
unchanged. Two more rewrites saved nothing and were dropped (`App.swift`'s
`frameDumpEnabled`, `changeIsMotionOnly(to:from:)`).
