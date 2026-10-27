# Module split, compile time and binary size: how it came to be

One story per subject: the module split, winning back its cost, per-module products, binary size, compile time and the test targets. Each story has the record of its decisions below it (see the [Historical README](../README.md) for the arrangement).

| Story | In short |
|---|---|
| [Binary size](<Binary size.md>) | Dead stripping keeps nearly all of TUI: public symbols are marked `[no dead strip]` and conformance records root the witness tables, so Hello and a typical app differ by 16 KB.  |
| [Compile time and the test targets](<Compile time and the test targets.md>) | The project's own builds use Xcode's Swift 6.2.4 rather than swiftly's assertions build (−26% to −42%); inside a build SIL optimisation dominates.  |
| [Per-module products](<Per-module products.md>) | The owner, 2026-10-11: "C9b: do it. As I understand it, we can have the umbrella target, as well as the individuals, all with their own products, but if a user happens to overlap the two it won't cause any harm." Measured, that holds for every static mix; the one harmful mix (a user's own `.dynamic` library built from TUI beside a statically linked TUI product) is warned about in the user guide.  |
| [The linker's RWX warning on Linux aarch64](<The linker's RWX warning on Linux aarch64.md>) | GNU ld 2.39 and later warn that a Swift executable on Linux aarch64 has a `LOAD` segment that is writable and executable, because on aarch64 the linker puts code and Swift's metadata on shared pages.  |
| [The module split](<The module split.md>) | On 2026-10-07 an analysis of clean release builds found most of the gap was the toolchain (swiftly's assertions build; Xcode's 6.2.4 is 26–42% faster), and the one large package-side lever was splitting the module.  |
| [Winning back the module split's cost](<Winning back the module split's cost.md>) | Each step's A/B showed what crossing a module boundary costs: generic code not specialised across it, and storage reached through accessors.  |
