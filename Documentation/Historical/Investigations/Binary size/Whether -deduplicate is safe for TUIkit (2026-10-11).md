# Whether `-deduplicate` is safe for TUIkit (2026-10-11)

> **Status:** landed: `Tools/DedupCheck` in CI on Swift 6.4 (2026-10-11, `21b2dc0a4`) and on Xcode's 6.2.4
> (2026-10-12, `e1b8e384f`); the README documents the flag as the app's own choice. **Decided by:** the owner,
> 2026-10-11 (a README opt-in section with CI checks; never an app-wide flag imposed quietly) and 2026-10-12 (the
> check on the 6.2.4 lane too). **Working notes** (not in git): `SIZE3/fu/dedup/`, `SIZE3/fu/dedup-pty/`,
> `SIZE3/q/dedup-check/notes.md`, `SYMS/notes.md` §4 (Xcode).

## Question

`-Xlinker -deduplicate` saved about 7% of every app (818 KB of a stripped hello world on 6.4.0) by giving functions
with identical machine code one address. Is a program folded that way still correct, can a check at build time keep
TUIkit safe under it, and should TUIkit apply it? (The SIZE3 review's question 10, paraphrased.)

## Answer

- **Correct today, with one latent hazard: key paths.** Swift identifies a key path to a computed property by its
  getter's address. Folding two identical getters makes two different key paths compare and hash equal; with
  different setters they still write to different places. Nothing else in TUIkit observes a function's address in a
  way a fold can change.
- **Xcode already does it.** An Xcode Release link hands ld `-Os`, and ld then folds: an Xcode-built hello world
  folded 20,575 of its 61,034 functions. So TUIkit must be safe under folding for every Xcode app now, whatever
  SwiftPM users choose. `swift build` does not fold.
- **The check is the link map, not ld's output.** `-verbose_deduplicate` prints counts, not names; a folded function
  keeps its name at the survivor's address (with size 0 in the map), so the unstripped binary's symbol table shows
  every fold as aliases.
- **TUIkit does not apply the flag.** SwiftPM 6.2+ would accept it from the package, but a link flag lands on the
  developer's whole program, changes what the developer's own key paths compare equal to, and on 6.4 with Swift
  Build cannot be undone, because the package's link flags come after the developer's.

## Key measurements

Stress, release, main 2c75a8c21 (swift.org 6.4.0 with Swift Build, and Xcode 26.3's 6.2.4, native), ld-1230.1, on
the development machine (arm64 macOS 15.8.1 VM). Probes of each key-path and closure shape were built on both
toolchains.

| | 6.4.0 | Xcode's 6.2.4 |
|---|--:|--:|
| functions folded / `__text` saved | 23,209 / 861,068 B | 22,110 / 763,424 B |
| TUIkit key-path getters in the binary | 313 | 313 |
| equal key-path groups among them | 0 | 1: `buttonStyle` and `installedButtonAppearance` |

| shape (probe) | folds under `-deduplicate`? |
|---|---|
| identical computed getters of one root and value type, one file or two objects | yes: the key paths compare equal |
| a writable pair, one getter, two setters | yes: equal, and a dictionary keyed by both holds one entry |
| a non-final class's properties | no: the id is the vtable entry |
| `@convention(c)` functions | no, wherever their address is taken |
| Swift closure literals compared by function word | yes |

A deduplicated Stress passed `--selfcheck` with both memo verifiers armed on both toolchains, 22 sessions of 150
frames came out byte-identical to the plain binary, and a 6.2.4 debug test build with the flag passed the full
suite (10,929 tests). In a PTY, folded Stress, Example and Hello on both toolchains matched the plain binaries in
96 sessions (raw mode, input, resize, suspend and resume, and all four ways to quit), with no failure; the byte
differences left were animation timing, as large between two runs of one binary.

## Reasoning

- **The inventory is small.** TUIkit compares key paths in three places: the render memo's environment slots, the
  root palette lookup, and `Table`'s same-column check. It compares one function address, the fatal-signal
  handler's, and a `@convention(c)` function never folds. The 94 `ObjectIdentifier` uses are of metatypes and
  objects, which are data, and `-deduplicate` moved no data symbol.
- **The one finding is harmless.** `installedButtonAppearance` is `buttonStyle` with a setter that also ends a custom
  primitive style. Only the environment slot table could confuse them, and no slot sees both, so the manifest
  allows the pair with that reason. 6.4.0 does not fold it.
- **Folding differs by compiler**, so the check runs per toolchain: 6.4.0 and 6.2.4 differ by that pair. Swift.org's
  6.3.3, measured once, folds what 6.2.4 folds (decisions
  [B-SHIP-1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md#b-ship-1-the--deduplicate-check-runs-on-two-toolchains-64-and-624>)).
- **`-no_deduplicate_allow_swift_addr_ref`** keeps key paths and closures distinct and still saves about 2%; the
  README offers it.

## What landed

- `Tools/DedupCheck` ([README](<../../../../Tools/DedupCheck/README.md>)): key paths TUIkit forms (K1), the
  functions that consume them (K2), address-taken C functions (F1), addresses the manifest says must stay unique
  (F2), and a report of public alias pairs for app developers (K3). Two SwiftLint rules flag a new key-path
  comparison or function-address cast in the library. CI also fails if a release program exports a TUIkit symbol
  (`cd0ffeee9`).
- README, [Shipping size](<../../../../README.md#shipping-size>): what folding changes in an app's own code, and how
  to opt in or out.

Part of [where the bytes of a TUIkit app go](<Where the bytes of a TUIkit app go (2026-10-10).md>); the flag's
reach is on [which links TUIkit's flags reach](<Which links TUIkit's flags reach, and the debug map (2026-10-11).md>).
