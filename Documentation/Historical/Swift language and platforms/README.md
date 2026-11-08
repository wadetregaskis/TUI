# Swift language and platforms: how it came to be

How TUI's use of the Swift language and its platform floor came to be. Live notes on the language are in [Swift language](<../../Swift language/>). Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Building views off the main actor](<Building views off the main actor.md>) | View values and modifiers are nonisolated, as in SwiftUI, and `Button`'s action is `@MainActor` with a plain overload instead of `@preconcurrency` (2026-11-01). The async overloads and press policies the study recommended were declined by the owner. |
| [Strict memory safety](<Strict memory safety.md>) | The last `@safe` type, `ValueHashPlans`, moved to arrays with no measurable cost (2026-11-08). |
| [Raising the floor to macOS 15](<Raising the floor to macOS 15.md>) | The floor is macOS 15 since 2026-10-31: `Mutex`, `Atomic` and the rest of Swift 6.0's runtime adopted, the dead gates deleted; what it does not give (macOS 26's `InlineArray`, `Observations`, `Array.span`). |
