# Selective optimisation attributes (2026-10-08)

> **Status:** decided 2026-10-08. One change landed, the status bar's undo-hint cache (`d909004f3`, `cad89cd17`);
> no optimisation attribute did. **Decided by:** the owner. **Working notes** (not in git): `OPTN/options.md` (the
> options table and the raw numbers beside it), `OPTN/patches/`.

## Question

Could `@_optimize(none)`, `@_optimize(size)`, no-specialisation and similar attributes on cold code cut TUI's
compile time or bytes without costing run time? The owner, 2026-10-08: "I'm open to the concept. I think the bar has
to be higher for merely reducing compilation time because ultimately compilation is a relatively rare thing compared
to the accumulated runtime cost … I'm a little more inclined to accept a trade-off there if it reduces the binary
size … start with you presenting some options you've evaluated, and I'll try and make a judgment."

## Answer

- **`@_optimize(none)` grows the binary** wherever it was tried on non-generic code, by 1.6 to 30 KB per set: an
  unoptimised body is bigger and loses its inlining. It also costs microseconds to milliseconds on its path.
- **Per-function `-Osize` saves little:** closures inside an annotated function are separate functions and do not
  inherit the attribute, and a size-mode function changes what its callers inline. The sets saved 3–5 times less
  than the module-wide `-Osize` measurement had suggested.
- **The one clear win was not an attribute:** caching the status bar's undo and redo hints, which were rebuilt from
  the shortcut table up to four times a render (6.9 µs to 0.05 µs per bar render).
- **All the sets together** would have saved 44 KB of a stripped Stress (51 KB of `__text`) and about 1.4 s of
  compile CPU, for 597 annotated declarations to keep cold.

## Key measurements

Main 695d4c2cd, Xcode's Swift 6.2.4, on the development machine (an arm64 VM with no performance counters, shared
with other lanes): run time is thread-CPU time, the minimum over batches and the median of three rotated runs, so
factors within ±3–5% are noise. Bytes are stripped release binaries (moving in 16 KB pages; `__text` resolves the
rest). Compile time is SIL-optimisation CPU per set, from per-function pass timers.

| set (what is annotated) | run-time cost | bytes saved, Stress (`__text`) | compile CPU saved |
|---|---|--:|--:|
| S1a: no specialisation on `renderMenuPopup` | none measurable | 16.6 KB (18.7) | 0.16 s |
| S1b: S1a, the hint cache, and the shortcut tables unoptimised | faster overall; ×2.2 on a table rebuild | 30.8 KB (42.1) | 0.45 s |
| S2b, S3b, S5b, S6b, S7b, S8a: `none` on cold sets | none measurable (S2b) to ×14 on their paths | grows by 18–55 KB | 0.13–0.77 s |
| S4: one shared unspecialised sort | the ASCII image converter ×2.7 | 16.5 KB | 0.11 s |
| ALL (S1b, S2a, S3a, S4c, S5a, S6a, S7a, S8a) | sessions ×0.98–1.02 | 44.0 KB (50.9) | 1.6 s whole-job |

The ALL build passed the full suite (10,908 tests) with no warnings, and its stripped binaries matched the per-set
relinks to the byte for Hello and Stress.

## Reasoning

The owner ranks run time above bytes above compile time. Against that: every `none` variant failed on bytes; the
`-Osize` sets saved a few kilobytes each for a maintenance cost of keeping hundreds of declarations cold; the shared
sort moved large structs through value witnesses and ran 40 times slower, so it was dropped on measurement; S1b
slowed table rebuilds. S1a alone paid on all three counts, but carving the menus into their own module was expected
to remove the same specialised copies by making those calls cross-module.

## What was decided

The owner, 2026-10-08: "definitely do P0 … Do not do S1B. Because we definitely don't want to slow down tables.
And obviously don't do optimize none, because that clearly just makes everything worse. The other options … S1A and
the small call sets … are on the table … if it makes more sense to wait until the menu module is factored out, then
that's fine too." P0, the hint cache, landed (`d909004f3`, then `cad89cd17` so a kept hint follows a change of
language). S1a and the small sets were not taken up: `Sources` has no `@_optimize` or no-specialisation attribute at
5369ea867. Carving the menus out (step B5b) removed the specialised popup copies S1a was to save, so it has nothing
left to save (decisions
[B-SPB5b-4](<../../../SwiftUI parity/Decisions/Module split/Step B5b, carving TUIChrome, TUIEffects and TUIMenus (SPB5b).md#b-spb5b-4-an-open-menus-popup-draws-through-the-unspecialised-rendermenupopup>)).

Related: [pre-specialisation across module boundaries](<Pre-specialisation across module boundaries (2026-10-08).md>),
the same day's other attribute question; and the earlier
[compile time and binary size analysis](<../../Compile time and binary size analysis (2026-10-07).md>), whose D2
proposed `@_optimize(none)` on cold code.
