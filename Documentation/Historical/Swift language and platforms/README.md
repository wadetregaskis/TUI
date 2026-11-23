# Swift language and platforms: how it came to be

How TUI's use of the Swift language and its platform floor came to be. Live notes on the language are in [Swift language](<../../Swift language/>). Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Building views off the main actor](<Building views off the main actor.md>) | View values and modifiers are nonisolated, as in SwiftUI, and `Button`'s action is `@MainActor` with a plain overload instead of `@preconcurrency` (2026-11-01). The async overloads and press policies the study recommended were declined by the owner. `State` and `Binding` became `Sendable` as SwiftUI's are, off-main access going through the main actor (O-25, 2026-11-21), then behind a lock of the box's, as SwiftUI's is (O-25-FIRSTREAD (d), 2026-11-22); a render pass's reads all agree, a write off the main actor showing from the next pass (O25-D-2, 2026-11-22). |
| [Strict memory safety](<Strict memory safety.md>) | The last `@safe` type, `ValueHashPlans`, moved to arrays with no measurable cost (2026-11-08), and numbers written with `FormatStyle` and `digits(width:)` rather than printf formats; `String(unsafeFormat:)` kept for `specifier:` and `%g`. |
| [Raising the floor to macOS 15](<Raising the floor to macOS 15.md>) | The floor is macOS 15 since 2026-10-31: `Mutex`, `Atomic` and the rest of Swift 6.0's runtime adopted, the dead gates deleted; what it does not give (macOS 26's `InlineArray`, `Observations`, `Array.span`). |
