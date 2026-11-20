# Paragraph attribute types (attralign)

Compile probes for the owner's ruling attralign (2026-11-19) on a paragraph's alignment in an `AttributedString`:
"(a) but provide our own version anywhere that Core Text doesn't (e.g. macOS 15) if possible". Nothing here runs
SwiftUI or Core Text; each case is a type-check, so it needs no macOS 26. Cited by
`Sources/TUIFoundation/Views/AttributeScopes+CoreText.swift` and §5 and §7 of the [G3
design](<../../../Documentation/Historical/Text, editing and the clipboard/An attributed TextEditor - design (G3).md>).

- `StandIn.swift`: TUIFoundation's declarations in each shape weighed. `-D SAME_NAMED` is what a6fa64c8f shipped
  (TUI declares Core Text's names on every platform). The default is the ruling: Core Text's own types on the macOS
  26 SDK, re-exported, TUI's identical ones on the macOS 15 SDKs (and Linux, Windows, WebAssembly), and TUI's own
  `paragraphAlignment`, valued TUI's `TextAlignment`, everywhere. `-D NO_CORETEXT_REEXPORT` is the ruling without
  the re-export.
- `ClientGuarded.swift`: SwiftUI's spelling inside `if #available(macOS 26, *)`, the types named.
  `ClientUnguarded.swift`: the same with no guard. `ClientFallback.swift`: TUI's `paragraphAlignment`.
- `LineHeightReading.swift`: the three ways TUI could read Core Text's `LineHeight` back. It type-checks; none can run
  here. The owner ruled A-ATTRED-13 (b) on 2026-11-19: the first, `==` against made values, is what TUI does
  (`Sources/TUIFoundation/Views/AttributeScopes+LineHeight.swift`, every multiple of 0.05 from 1.5 to 8.45).
- `probe.sh`: the matrix; `probe.out` is what it printed.

Run with `sh probe.sh` (Xcode's swiftc; the 15 SDK is the Command Line Tools' 15.5, tuitree's).

## What it showed (2026-11-19, Xcode 26.3's Swift 6.2.4, macOS 26.2 and 15.5 SDKs, on macOS 15.8)

| SDK | Shape | Imports | Guarded, types named | Unguarded at a macOS 15 target | `paragraphAlignment` |
|---|---|---|---|---|---|
| 26.2 | same-named (a6fa64c8f) | TUI | ok | ok | ok |
| 26.2 | same-named | TUI + AppKit | **ambiguous type name 'TextAlignment'** | ok | ok |
| 26.2 | ruling | TUI, TUI + AppKit, TUI with `MemberImportVisibility` | ok | refused: macOS 26 only | ok |
| 26.2 | ruling, no re-export | TUI with `MemberImportVisibility` | **"missing import of defining module 'CoreText'"** | refused | ok |
| 26.2 | SwiftUI itself | SwiftUI, with or without `MemberImportVisibility` | ok | refused: macOS 26 only | — |
| 15.5 | every shape | every import | ok | ok | ok |
| 15.5 | SwiftUI itself | SwiftUI | no `alignment` at all | no `alignment` at all | — |

So on the 26 SDK the ruling compiles exactly where SwiftUI does and refuses exactly what SwiftUI refuses, with AppKit
imported or not, and with `MemberImportVisibility` only if TUI re-exports Core Text (SwiftUI's import chain gives a
`MemberImportVisibility` file Core Text's members; TUI's must too). On the 15 SDK nothing else declares the names,
so TUI's own are unambiguous and need no gate. `paragraphAlignment` compiles in every case.

A stored property cannot be newer than its type ("stored properties cannot be marked potentially unavailable with
'@available'", measured), so on the 26 SDK the scope's `alignment` is a computed property.

**Not measured here, because it needs macOS 26 to run:** what Core Text's key's `runBoundaries` is (the tests that
set it through SwiftUI's spelling assert `.paragraph`, and run on CI's macOS 26 lane); whether Codable decoding with
`\.swiftUI`'s scope carries `alignment` (with a computed member it should not); and what `LineHeight`'s encoding or
reflection shows.
