# A program copied out of its build stopped at launch: libswiftCompatibilitySpan (2026-10-11)

> **Status:** fixed and landed, 2026-10-11 (`02863940b` to `aafa4a3cf`), with a CI check; two upstream reports are
> drafted for the owner to file. **Decided by:** the owner, 2026-10-11, who approved landing the replacement "for
> now". **Working notes** (not in git): `SIZE3/q/span/` (the cause), `SIZE3/q/spanq/` (the whole chain, the
> upstream drafts, and the downsides of swift-collections' fix), `NODQ/` (the replacement's gates).

## Question

A release hello world built with swift.org's Swift 6.4.0 and copied out of `.build` stopped before `main` on
macOS 15.8.1: `dyld: Library not loaded: @rpath/libswiftCompatibilitySpan.dylib` (2026-10-10). Xcode's 6.2.4 build
of the same code ran. Why, is TUIkit's own use of `Span` to blame, and what should TUIkit do? The owner then asked
for "the exact nature of the problem", and whether swift-collections' fix would have downsides.

## Answer

- **Not TUIkit's Span code.** No TUIkit object referred to any of the 33 symbols the library serves. The one import
  was `OutputSpan`'s metadata accessor, `$ss10OutputSpanVMa`, from swift-collections' unspecialised generic
  `RigidDeque`/`UniqueDeque` code, which TUIkit never called. Swift keeps every public symbol, so linking
  DequeModule linked the reference.
- **Not a compiler bug either: two intended changes collided.** swift-collections 1.4 built Deque on code that fills
  an `OutputSpan`, and SwiftPM 6.4 compiles a package for macOS 12 instead of 10.13. At 12 the import is strong
  (`OutputSpan` is declared from 10.14.4); at 10.13 it was weak, which is why the 6.2.4 build ran. macOS has the
  library from 26 only, and SwiftPM ships nothing beside an executable.
- **Weak is not a fix.** A weakly linked symbol is NULL below macOS 26: a one-line program calling into it died
  at `pc 0x0`. It is safe only where the code needing it provably never runs there.
- **TUIkit dropped swift-collections.** TUIkitApp, its only user, keeps stdin bytes in a buffer of its own
  (`InputByteBuffer`) and decoded events in `InputQueue`, about 300 lines that touch no Span type. That also saves
  about 165 KB per app.

## Key measurements

macOS 15.8.1 arm64 VM, Xcode 26.3 (SDK 26.2, ld-1230.1); swift.org 6.4.0 with Swift Build, and Xcode's 6.2.4 with
the native build system; swift-collections 1.5.1; main at 2c75a8c21. "Copied out" means the toolchain rpaths
deleted and nothing placed beside the binary.

| case | result |
|---|---|
| Hello, 6.4.0, copied out | stops at launch, exit 134 |
| Hello, Stress and Example, Xcode's 6.2.4, copied out | full PTY sessions pass (import weak) |
| DequeModule's 108 KB in a linked app | 100 B dead-stripped |
| swift-collections' cost in Hello | about 165 KB, of which TUIkit used 5.4 KB |
| TUIkit's own Span patterns that link the library strongly | none on main (three patterns found, below) |

The patterns that make a strong link, measured on both toolchains: requesting a Span type's metadata
(`Span<T>.self`, or as an argument to unspecialised generic code); mutating a `MutableSpan` or `OutputSpan` in a
public generic function that is not `@_alwaysEmitIntoClient`; a public type storing a Span. `@available(macOS 26, *)`
prevents none of them, and a debug build links the library more often than a release build of the same code.

## Reasoning

Options were priced against "every TUIkit app deployable with no action by its author":

- **Replace Deque (chosen).** Works on every toolchain and build system, costs app authors nothing, and is the size
  win.
- **Ship the dylib beside the app:** a 157–188 KB file to copy, sign and know about; the failure shows only on a
  user's Mac.
- **Weak-link it, or internalize:** a hidden flag on every build; with internalize, a program on
  swift-collections 1.7 still stopped at launch.
- **Pin swift-collections below 1.4, or fork it:** blocks every app that uses 1.4 or later, or splits package
  identity.
- **Wait for upstream:** a small, source-compatible change to swift-collections removes the import (measured:
  its Deque tests pass, and the client runs copied out), but the maintainer's stated position is that the package
  cannot fix it.

If a swift-collections release ever links nothing for a Deque-only client, deployability stops being a reason;
then the choice is about 300 lines of TUIkit's own against about 165 KB per app.

## What landed

- `02863940b`: TUIkitApp's own buffers; swift-collections out of `Package.swift`.
- `914137ed6`, `c69521c23`, `aafa4a3cf`: `Tools/check-span-compatibility.sh`, run by CI on a release build. It fails
  on any load of the library, strong or weak, and on any symbol imported from it, in the executables and in every
  library module's objects. The owner asked for a unit test if cheap; it stays in CI because a debug build links the
  library where release does not (decisions
  [C-SHIP-1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md#c-ship-1-the-libswiftcompatibilityspan-check-stays-in-ci-not-in-the-unit-tests>)).
- `de9e3d06d`: README, [Shipping a program](<../../../../README.md#shipping-a-program>), says what an app that uses
  Span types or swift-collections 1.4+ itself must ship or weak-link.

## Still open

Two drafts for the owner to file: to swift-collections, the change above (`SIZE3/q/spanq/swift-collections-issue.md`);
to swift-package-manager, that `swift build` makes a macOS 14 executable that cannot start there without warning,
and that under Swift Build an executable gets the `@loader_path` rpath only through a library target it depends on
(`SIZE3/q/spanq/swift-package-manager-issue.md`). The compiler team already calls the 6.4 combination a regression
and shipped an opt-in flag for it (swiftlang/swift#91294).

Part of [where the bytes of a TUIkit app go](<Where the bytes of a TUIkit app go (2026-10-10).md>).
