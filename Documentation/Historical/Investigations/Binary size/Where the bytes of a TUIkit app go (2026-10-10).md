# Where the bytes of a TUIkit app go (2026-10-10)

> **Status:** decided, and the levers TUIkit controls have landed (2026-10-10 to 2026-10-12). **Decided by:** the
> owner. **The long-form report** is committed: [Where the bytes go in a release build](<../../Binary size study (2026-10-10)/Where the bytes go in a release build.md>)
> and [How the measurements were taken](<../../Binary size study (2026-10-10)/How the measurements were taken.md>).
> **Working notes** (not in git): `SIZE2/research.md` (2026-10-08) and `SIZE3/` (2026-10-10): its answers to the
> review `SIZE3/answers.md` and its follow-up questions `SIZE3/q/`.

## Question

What makes a release binary that uses TUIkit large, and what can shrink it? SIZE2 asked it from the flags'
side (2026-10-08). The owner then asked for a byte analysis of the built libraries from many angles, and how API
usage affects an app's size (2026-10-10), and, reading the first answer: "11.5 MiB for hello world is horrifying".

## Answer

- **`swift build -c release` does not strip.** A one-`Text` hello world is 25,538,248 B as built and
  11,502,960 B after `strip` (6.4.0). The 14 MB between them is the debug map and the symbol tables.
- **Every app carried all of TUIkit.** Hello kept 98.9% of the library bytes it linked, and each of 17 apps that
  added one API family to it was exactly one 16 KB page larger. Every public symbol and every conformance record is
  a root for the linker's dead stripping, so using less API saved nothing.
- **So the levers that matter cut the roots or what is linked:** per-module products, `-internalize-at-link`,
  keeping TUIkit's symbols out of the export table, and a few package changes. `strip` and `-deduplicate` are the
  app's own choices, and the rest needs an upstream change or a redesign.
- **Debug information is most of the built libraries (54.6% of the objects) and none of an app.** The owner ruled
  that only final-app bytes matter; TUIkit keeps building with `-g`.

## Key measurements

Hello is a `WindowGroup` holding one `Text`; Stress is the package's stress app. Main at 247de05f9 unless a row
says otherwise. Swift 6.4.0 (swift.org, Swift Build) and Xcode 26.3's 6.2.4 (SwiftPM's native build system), Xcode's
ld-1230.1, on the development machine (an arm64 macOS 15.8.1 VM, 16 GiB, shared with other work). Sizes are file
bytes; a stripped file moves in 16 KB pages. "Emulated" means a measured link of objects whose dead-strip flags were
patched to model a compiler flag, checked against the real flag where one exists.

| what | Hello | how known |
|---|--:|---|
| as built, then stripped (6.4.0) | 25,538,248 → 11,502,960 | measured |
| linking only the modules Hello uses (relink at 247de05f9) | −35.3% | measured relink |
| the package's own levers stacked: products, internalize, `-no_exported_symbols`, prelink fix, `-deduplicate` | −52.7% (5,444,640) | emulated |
| `DeadStripUnusedAPI` trait, off → on (`a3218056d`'s tree) | 11,374,080 → 9,700,016 (−14.7%) | measured |
| on `TUIkitApp` alone against the `TUIkit` umbrella, with the internalize trait | 5,964,832 against 9,552,376 (−37.6%) | measured, 2026-10-11 |
| `UnexportTUIkitSymbols` trait: the export table 317 KB → 9 KB | −3.2% | measured, 2026-10-12 |
| `-Xlinker -deduplicate`, both traits on | −7.5% | measured, 2026-10-12 |

The built libraries for 6.4.0: 86.9 MB of per-file objects, of which DWARF and its relocations are 47.4 MB, symbol
names and records 17.3 MB, and code (`__text`) 8.6 MB (measured). In a stripped Hello, code is 72% and Swift
runtime metadata 5.3%.

## Reasoning

- **Roots, not usage.** IRGen marks every public symbol "used" unless `-internalize-at-link` is given, and the
  runtime finds conformance records by scanning their section, so the compiler keeps each one, and a kept record
  keeps its witness table and its code. Hence Hello keeping `Table`'s renderer. Products cut what is linked;
  internalize cuts the public-symbol roots; the records need full LTO with conditional records, which the compiler
  does not yet make complete (see the open
  [LTO page](<../../../Investigations/Full LTO, conditional runtime records and the reflection descriptor request.md>)).
- **Who may set a flag.** A link flag in TUIkit's manifest lands on the developer's whole program, so TUIkit sets
  only compile flags of its own and an unexport list limited to its own modules, each behind a trait
  ([who the flags reach](<Which links TUIkit's flags reach, and the debug map (2026-10-11).md>)).
- **Ruled out:** `-Osize` (−8.3% of Hello, but +4.5% to +20.5% CPU per frame in a pre-split A/B); disabling
  reflection metadata (`@State` and `@Environment` silently stop binding); shorter module or identifier names
  (0.15% and 0.24% of Hello, estimated); library evolution (it crashes both compilers on TUIkitCore); ThinLTO or
  full LTO alone (larger, not smaller). Single-module emission, the machine outliner and mergeable traps are in
  [Future options](<../../../Future options.md#build-and-binary-size>).
- **6.4 against 6.2.4.** 6.4.0's compiler emits 4.0% less of Hello than 6.2.4, but Swift Build's per-module
  prelink hides weak definitions, which leaves 350 KB of duplicate code per 6.4 app; SwiftPM sets
  `KEEP_PRIVATE_EXTERNS = NO` for every package target, and no setting reaches it. An issue for
  swift-package-manager is drafted for the owner to file (`SIZE3/q/swiftpm-issue-keep-private-externs.md`).
- **A side finding** became a bug fix: every TUIkit app stopped at launch without its resource bundle (decisions
  [BNDL](<../../../SwiftUI parity/Decisions/Compile time and binary size/Running without the resource bundle (BNDL).md>)).

## What was decided

The owner, 2026-10-10 to 2026-10-12: only final-app bytes matter; land swift-collections' removal
([its own page](<A program copied out of its build stopped at launch, libswiftCompatibilitySpan (2026-10-11).md>)),
front-coded SF Symbol names, the README's opt-in size recipe with CI checks of what it recommends, internalize as a
default trait, per-module products ("C9b: do it"), the unexport list, and the curve editors in a module of their
own. Declined: `-non_global_symbols_strip_list` ("we need to support debugging properly"). Deferred: single-module
emission and pay-for-use services.

## Links

- README, [Shipping size](<../../../../README.md#shipping-size>) and
  [Depending on fewer modules](<../../../../README.md#depending-on-fewer-modules>): what an app developer can do.
- Commits: `a3218056d` (internalize trait), `d159ab542` (unexport trait), `17a63a3a7` (products), `f8ec22f19`
  (SF Symbol names, described in [Baking a large static lookup table](<../../../Swift language/Baking a large static lookup table in Swift.md#front-coding-the-names-2026-10-11>)),
  `02863940b` (swift-collections out), `7612c03a4` (README's recipe), `97d8cf928` and `af87dc403` (editor modules).
- Decisions: [SHIP](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md>),
  [SHIP2](<../../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size and products, second round (SHIP2).md>),
  [C9B](<../../../SwiftUI parity/Decisions/Module split/Library products for every module (C9B).md>).
- Long form: [Per-module products](<../../Per-module products (2026-10-11).md>); the earlier
  [compile time and binary size analysis](<../../Compile time and binary size analysis (2026-10-07).md>).
- Sibling pages: [`-internalize-at-link`](<Dead-stripping TUIkit's unused API from the package (2026-10-11).md>),
  [`-deduplicate`](<Whether -deduplicate is safe for TUIkit (2026-10-11).md>),
  [SwiftUI's size](<SwiftUI's size beside TUIkit's (2026-10-10).md>).
