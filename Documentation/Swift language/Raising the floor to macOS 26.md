# Raising the floor to macOS 26

TUI's floor is macOS 15, and it can't rise yet. This note says what a rise to macOS 26 or later would gain, and what to change on the day, so nobody has to rediscover it. Nothing here has been built at a macOS 26 target unless it says so.

Each macOS carries a Swift runtime: macOS 15.0 has Swift 6.0's, 15.4 has 6.1's, 26.0 has 6.2's and 26.4 has 6.3's (`utils/availability-macros.def` in the Swift repo). Raising the deployment target changes what's available at run time. The compiler TUI requires is a separate question, with Swift 6.2 its minimum today.

## What it would gain

| Feature | Where in TUI | What it gains | How sure |
|---|---|---|---|
| `Array.span`, `Span` and `RawSpan` without `libswiftCompatibilitySpan.dylib` | `InputByteBuffer.swift` avoids `DequeModule` because of that library. The ANSI scanners, `ValueHashPlans` and the dithering all use unsafe pointers | Bounds-checked buffer access in hot code, and fewer unsafe sites for strict memory safety to mark: about 90% of its 1,080 sites point at an `Unsafe*` or C pointer type. `Tools/check-span-compatibility.sh` and its CI step can go | The availability is measured: at target 15, `OutputSpan` links the library. The performance cost in hot paths is **not** measured, so A/B each move |
| `InlineArray` | `TerminalColors.swift`'s palette is a tuple only because of this, as its comment says. `TypeWalk.swift` loses its `@available` | Plainer code, the same layout | High. Small gain |
| Task names without a check | `TUIContext.swift`'s `#available(macOS 26, *)`, and the doc comments on `task(name:)` | Names apply everywhere, and a sentence goes from each comment | High. Small gain |
| `Task.immediate` | `ActivationHold`, which lets a `Task` an action started run to its first suspension before a frame draws | Could replace part of what it does, by running the start of the task synchronously | Inferred, not tried. Check it against the `SwiftUI` probe in `Tools/SwiftUIProbes/Disabled between queued events` |
| `Observations` | `withObservationTracking` and `ObservationLease` | An async sequence of changes. It has no public cancel at any version, and the frame walk needs a synchronous read of what changed, so this probably doesn't replace the lease's sentinel | Inferred. Don't assume a gain |

## What to fix on the day

- **Availability:** delete `@available(macOS 26…)` and `#available(macOS 26, *)`. They give no warning at a higher target, so nothing will prompt this: search for them. Keep the checks that are the subject of a test, and `Tools/SwiftUIProbes`, which is a record.
- **`UndoManager`:** the macOS 26 SDK isolates it to the main actor, and the macOS 15 SDK doesn't. `UndoManagerEnvironment.swift` and `TextUndoBridge.swift` work around the difference and can simplify. This goes with the SDK rather than the target, so check which of them each comment means.
- **macOS 15 stand-ins:** the `#expect` metatype crash in `CONTRIBUTING.md` is a macOS 15 runtime limit, and those two tests can go back once macOS 15 is gone. Check it first.
- **Comments:** search for "macOS 15" and "macOS 26" in `Sources`, `Tests`, `Tools` and CI. Dated measurements stay; statements about what's possible don't.
- **CI:** drop the macOS 15 lanes, and `Tools/check-span-compatibility.sh` if `Span` is adopted.

## What it won't do

- **It won't clear the twelve exceptions.** Those `concurrency_escape` cases come from SwiftUI's own unconstrained signatures, Apple classes not marked `Sendable`, a signal handler's raw memory, and one thread-confined note. None is a floor problem. `Disconnected` (SE-0538) might remove the six that are SwiftUI's signatures, if it ships and fits. Check when it does: it isn't in Swift 6.4.0.
- **It won't remove the noncopyable field limit.** A noncopyable field reported as `()` (`ValueHashPlan.swift`) lasts until macOS 27, so that one needs a higher floor.
- **Regex lookbehind doesn't compile on any compiler we use,** at either target, though the Swift 6.2 list in `.claude/CLAUDE.md` names it. SE-0448 is accepted and names no release.

## What macOS 15 gave, for the record

Raised in November 2026 at the owner's request. Adopted: `Mutex`, `Atomic`, `String(validating:)`, five more `UTType`s on Linux, read-only global array literals in `__DATA,__const` with no `swift_once`, and every macOS 15 availability gate deleted. The `@unchecked Sendable` and `nonisolated(unsafe)` lines fell from about 147 and 74, comments included, to 8 and 4 declarations, each with its reason at the site.

Two things it taught, which a later rise should expect:
- **Swift 6 checks the executor on any closure a main-actor function hands to the standard library,** about 100 ns against about 3 ns for a `Mutex` (measured on a busy machine, so an order of magnitude). So hot classes went non-`Sendable` rather than `@MainActor`.
- **Re-entering a `Mutex` on macOS is an uncatchable kill,** where `NSLock` hung, and on wasip1 it spins forever. Read the body of any lock that calls out before moving it.
