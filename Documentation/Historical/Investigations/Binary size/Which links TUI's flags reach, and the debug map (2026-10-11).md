# Which links TUI's flags reach, and the debug map (2026-10-11)

> **Status:** decided; the one lever taken landed 2026-10-12 as the `UnexportTUISymbols` trait (`d159ab542`).
> **Decided by:** the owner, 2026-10-11 and 2026-10-12. **Working notes** (not in git): `SYMS/notes.md` (revised
> after the critic's review in `CRIT/SYMS/`), with the scope probe in `SYMS/scope/`.

## Question

The owner, 2026-10-11, in three parts: which of TUI's manifest flags reach the developer's own code ("never
impose app-wide flags quietly"); can TUI shrink the debug map and the symbol table of an unstripped app without
asking anything of its users; and are internalize, single-module emission, the machine outliner, mergeable traps and
the SF Symbols table change really invisible to users?

## Answer

- **Compile flags stay in TUI; link flags reach the whole program.** A flag in TUI's `swiftSettings` reached
  only TUI's compile lines, never the app's module or another target of the app's package. A flag in its
  `linkerSettings` landed on every final link containing TUI: the executable, and also the developer's own
  `.dynamic` libraries, for both architectures of a universal build (not on prelinks). From the package, `-Xlinker -S`
  left the app's own objects with no debug map, and an unexport pattern emptied the developer's dylib of TUI's
  symbols. Most link flags have no counter-flag, so the developer cannot undo them.
- **The debug map cannot be thinned without losing something.** It holds one four-entry group per function, one
  entry per global and four per object, whatever the debug-information level: `-g` and `-gline-tables-only` give the
  identical map. TUI owns 98% of an unstripped hello world's 14.0 MB of symbol table and debug map. Fewer
  functions, symbols and objects are the only levers that keep the debug information.
- **Four of the five "invisible" changes are visible.** Mergeable traps make every trap in a function share one
  instruction, so a crash cannot say which check failed; the outliner adds frames with no source line and grows the
  unstripped app by 1.5 MB; internalize makes unused API unreachable from lldb's `expr` and from plugins;
  single-module emission costs every build of TUI compile time and blurs about 4% of its functions in the debug
  information. Only the SF Symbols table change is invisible.

## Key measurements

`SYMS/scope/`: a test library at three tags (none; four compile flags and `-Xlinker -S`; the same compile flags and
an unexport pattern), consumed by exact version over `file://`, by an app package with its own library target,
executable and dynamic library; SwiftPM 6.2.4 (Xcode 26.3, native) and swift.org 6.4.0 (Swift Build), and Xcode 26.3
through a project with a remote package reference and on a root package. The levers below were measured on SIZE3's
hello world on main 0064b34bb with swift.org 6.4.0 and ld-1230.1, on the development machine (arm64 macOS 15.8.1
VM).

| lever on TUI alone | unstripped Hello | debug information kept? | visible to users |
|---|--:|---|---|
| `-internalize-at-link` | −4,256,352 B (−16.6%) | yes | plugins; `expr` on unused API |
| single-module LLVM emission | −1,558,160 B (−6.1%) | about 4% of functions and 2% of lines with code lose their own entries | +45% summed module compile time |
| `-unexported_symbol` for TUI's prefixes (link flag) | −745,216 B | yes | developers' dylibs and plugins |
| `-non_global_symbols_strip_list` for TUI's prefixes (link flag) | −901,728 B | DWARF yes; TUI's internal names gone from crash reports without a dSYM | crash reports |
| `-gline-tables-only` | ≈ 0 | — | the debug map does not change |
| the machine outliner | +1,499,936 B | yes | frames without a source line |

The user's own steps, for scale: `swift build -c release` 25,582,312 B; `strip -S` about 20.8 MB; `strip` about
11.5 MB.

## Reasoning and decisions

- **Link flags are the developer's.** The owner's rule since 2026-10-11: TUI never imposes an app-wide flag
  quietly. So `-deduplicate`, `-S`, `-x` and `-no_exported_symbols` stay README advice, and the manifest check
  refuses a link flag in TUI's manifest
  ([B-SHIP-2](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md#b-ship-2-packageswifts-unsafe-flags-every-one-behind-a-trait-link-flags-only-tuis-unexport-patterns>)).
- **One exception, ruled 2026-10-12:** "-unexported_symbol sounds worth doing". It became a default trait of its
  own, limited to patterns that match only symbols Swift names after a TUI module, because ld refuses it beside a
  developer's own export list
  ([B-SHIP2-1](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size and products, second round (SHIP2).md#b-ship2-1--unexported_symbol-is-a-trait-of-its-own-unexporttuisymbols-beside-deadstripunusedapi>)).
  It also takes the developer's own extensions of TUI's types out of the exports, which the README states.
- **Declined, 2026-10-12:** the strip list ("we need to support debugging properly"); the outliner and mergeable
  traps on the same grounds, and single-module emission for its build time; both are in
  [Future options](<../../../Future options.md#build-and-binary-size>).
- **A correction this work made:** Xcode Release builds already deduplicate, which made TUI's
  [dedup check](<Whether -deduplicate is safe for TUI (2026-10-11).md>) matter for every Xcode app.

See also [dead-stripping TUI's unused API](<Dead-stripping TUI's unused API from the package (2026-10-11).md>)
and README [Shipping size](<../../../../README.md#shipping-size>).
