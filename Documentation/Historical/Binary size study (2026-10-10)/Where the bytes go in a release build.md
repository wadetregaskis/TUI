# Where the bytes go in TUI's release build

> **What this is.** The binary-size study of 2026-10-10, which the maintainers' working notes call SIZE3: where
> the bytes of TUI's built libraries and of a linked app go, measured at 247de05f9 on Swift 6.4.0 and Xcode's
> 6.2.4; the levers that would shrink them, priced; the questions it put to the owner (§5); and the follow-up
> measurements the owner asked for the same day (§6). How the artifacts were built, and the full byte inventory,
> are in [How the measurements were taken.md](<How the measurements were taken.md>), beside this file.
>
> **Historical; decided since.** This is the state of 2026-10-10. What landed or was decided after it:
>
> - **A program copied out of `.build` launches on macOS 14 and 15** (lane NODQ, aafa4a3cf): TUIApp reads stdin
>   into buffers of its own, and TUI no longer depends on swift-collections, so its three modules, counted in
>   the tables below, are no longer in a TUI app.
> - **A program without its resource bundle runs, in English** (e5445e2cd), so §6.7's trap is gone: see
>   [Running without the resource bundle (BNDL).md](<../../SwiftUI parity/Decisions/Compile time and binary size/Running without the resource bundle (BNDL).md>).
> - **The SF Symbols names are front-coded** in blocks of 16 (lane SFQ, eef95ccc9), §2.5's first option, and the
>   font probe draws a constant codepoint, so a Mac without the font never reads the name table.
> - **`-internalize-at-link` ships from the package**, as the default-on trait `DeadStripUnusedAPI`, with the
>   README's "Shipping size" recipe and the `-deduplicate` check, `Tools/DedupCheck` (lane SHIP, 6122a8646): see
>   [Shipping size (SHIP).md](<../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size (SHIP).md>)
>   and the [README](<../../../README.md#shipping-size>).
> - **TUI's symbols stay out of the program's export table**, behind a second default-on trait,
>   `UnexportTUISymbols`, and ColorPicker's tone-curve and channel-curve editors are a module of their own,
>   TUICurveEditors (lane SHIP2, 4b1e00743): see
>   [Shipping size and products, second round (SHIP2).md](<../../SwiftUI parity/Decisions/Compile time and binary size/Shipping size and products, second round (SHIP2).md>).
> - **Every module is a library product of its own** (C9b, lane C9B, 3df96c964), lever 5: see
>   [Per-module products (2026-10-11).md](<../Per-module products (2026-10-11).md>) and
>   [Library products for every module (C9B).md](<../../SwiftUI parity/Decisions/Module split/Library products for every module (C9B).md>).
> - **Declined, and kept as future options:** [single-module LLVM emission](<../../Future options.md#single-module-llvm-emission>),
>   and [the machine outliner and mergeable traps](<../../Future options.md#the-machine-outliner-and-mergeable-traps>).
> - **Full LTO with conditional runtime records** (lever 10) waits on an upstream change: the compiler still keeps
>   three kinds of reflection descriptor as roots, and they keep whole modules alive
>   ([Future options.md](<../../Future options.md#full-lto-with-conditional-runtime-records>)).
>
> **Paths.** The angle files (`angle-*.md`), `critic.md`, the artifacts (`artifacts/…`), the follow-up lanes'
> notes (`fu/…`), the earlier study SIZE2, and the scripts this report names (`buckets.py`, `usage.py`,
> `dupes/relink.py`) are in the maintainers' working notes, in the folder SIZE3; none of them is in this
> repository. Line numbers into TUI's sources are at 247de05f9.

Report for review, 2026-10-10. It brings together the six SIZE3 angles (`angle-composition.md`, `angle-symbols.md`, `angle-names.md`, `angle-dupes.md`, `angle-data.md`, `angle-usage.md`) and applies the corrections in `critic.md`. The artifacts are in the working notes' SIZE3 folder, under `artifacts/`. Nothing here is a decision; section 5 lists what needs one.

**What was measured.**
- **Source:** TUI main at 247de05f9, built in release mode with each build system's defaults (`-O`, whole-module, `-g`).
- **Toolchains:**
  - `6.4.0` is swift.org 6.4.0 with SwiftBuild, the default build system in 6.4.
  - `6.2.4` is Xcode 26.3's compiler with SwiftPM's native build system.
- **Linker:** Xcode's ld-1230.1 for both.
- **The libraries:**
  - the 25 TUI modules of the umbrella product;
  - swift-collections;
  - the C image decoder (CSTBImage).

  TUIAppKit (163 KB of objects) is outside the umbrella and left out.
- **Apps:** Hello is an app with one `Text`; Stress is the package's stress app. App sizes are after `strip` unless a row says otherwise.

**Labels.**
- **measured**: read from a built or relinked file.
- **emulated**: a measured link of library objects whose dead-strip flags were patched to model a compiler flag.
- **estimate**: arithmetic or a model over measured counts.

In tables, a number is measured unless its cell or the column header says otherwise. Causes are marked **established** or **hypothesis**.

**Why the library bytes matter today.** TUI ships as source, so each consumer's machine builds these libraries.
- The bytes land in each consumer's build directory: each SIZE3 scratch build was 0.6–1.1 GB.
- They would only be downloaded in a binary distribution, which TUI does not have.
- An app's bytes are what users download and run.

## 1. Summary

### Where the bytes of the built libraries go (all modules, measured)

The per-file objects are what both build systems compile: 1,235 objects, one per source file. SwiftBuild then merges each module's objects into one object (42.4 MB; see below the table).

| category | 6.4.0 bytes | % of objects | 6.2.4 bytes | % of objects |
|---|--:|--:|--:|--:|
| code (`__text`) | 8,619,156 | 9.9% | 9,114,692 | 10.1% |
| data and Swift/ObjC runtime metadata | 2,072,473 | 2.4% | 2,038,710 | 2.3% |
| unwind tables | 2,128,032 | 2.4% | 2,182,144 | 2.4% |
| relocations for code and data | 5,051,504 | 5.8% | 5,324,128 | 5.9% |
| symbol names (string table) | 13,291,424 | 15.3% | 12,998,080 | 14.4% |
| symbol records (16-byte `nlist` entries) | 4,000,496 | 4.6% | 3,834,592 | 4.2% |
| load commands, linker hints, padding | 4,268,963 | 4.9% | 3,178,204 | 3.5% |
| debug info: name strings (`__debug_str`) | 15,305,733 | 17.6% | 16,598,472 | 18.4% |
| debug info: accelerator tables (`__apple_*`) | 5,386,334 | 6.2% | 6,018,854 | 6.7% |
| debug info: everything else (type and variable records, line tables) | 22,275,973 | 25.6% | 23,410,004 | 25.9% |
| debug info: relocations | 4,481,240 | 5.2% | 5,540,368 | 6.1% |
| **objects, total** | **86,881,328** | 100% | **90,238,248** | 100% |
| `.swiftmodule` (what clients compile against) | 15,110,364 | | 14,710,660 | |
| `.swiftsourceinfo` (IDE source locations) | 5,277,604 | | 5,278,144 | |
| `.swiftdoc` (doc comments) | 4,439,628 | | 4,440,188 | |
| `.abi.json` (stubs; library evolution is off) | 4,172 | | 4,172 | |
| **everything the build writes for the libraries** | **111,713,096** | | **114,671,412** | |

The same bytes in other forms (measured, 6.4.0):
- **SwiftBuild's merged objects:** 42,439,273 B. They carry no DWARF; a 13.65 MB debug map points back at the per-file objects instead.
- **A `libtool` archive of the per-file objects** (`libTUI-all.a`): 95,804,080 B, of which the archive's symbol index is 8,816,112 B.
- **One dynamic library of the whole umbrella:** 13,616,080 B after `strip -S -x`.

### A linked, stripped app (measured)

| category | Hello 6.4.0 | Stress 6.4.0 | Hello 6.2.4 | Stress 6.2.4 |
|---|--:|--:|--:|--:|
| code (`__text` + stubs) | 8,304,260 (72.2%) | 9,403,520 (72.3%) | 8,408,452 (72.4%) | 9,531,004 (72.6%) |
| data and Swift/ObjC runtime metadata | 1,863,568 (16.2%) | 2,214,566 (17.0%) | 1,849,057 (15.9%) | 2,199,651 (16.8%) |
| export trie (left behind by `strip`) | 772,216 (6.7%) | 775,360 (6.0%) | 774,120 (6.7%) | 776,528 (5.9%) |
| code signature, chained fixups, function starts | 242,944 (2.1%) | 266,480 (2.0%) | 243,504 (2.1%) | 266,848 (2.0%) |
| unwind info | 184,736 (1.6%) | 206,276 (1.6%) | 187,820 (1.6%) | 210,852 (1.6%) |
| symbol table (imports) | 116,728 (1.0%) | 121,116 (0.9%) | 118,372 (1.0%) | 122,796 (0.9%) |
| header, load commands, padding | 18,508 (0.2%) | 21,274 (0.2%) | 40,435 (0.3%) | 18,817 (0.1%) |
| **file** | **11,502,960** | **13,008,592** | **11,621,760** | **13,126,496** |

How to read the table:
- **Stress's own code** is 1.48 MB of its live bytes. Hello's own code is 1.3 KB.
- **Duplicate copies.** On 6.4.0, about 0.32 MB of Hello's code (0.35 MB of Stress's) is copies that SwiftBuild's prelink duplicated (finding 6).
- **Name strings.** About 0.33 MB of name strings, plus the 200 KB SF Symbols name table, sit inside the data row. They are not a separate row, so nothing is counted twice.

### The findings that matter most

1. **Debug info is most of the built libraries.**
   - DWARF and its relocations are 47.4 MB (54.6%) of the 86.9 MB of 6.4.0 objects (measured).
   - Building TUI's modules without `-g` takes their objects from 85.0 to 36.4 MB (−48.6 MB, measured).
   - Line tables only takes them to 66.5 MB (−18.5 MB, measured).
   - None of this reaches an app.
2. **Names come next, and module names are a fifth of them.**
   - Symbol names and records are 17.3 MB (19.9%) of the objects (measured).
   - Renaming all 24 modules to three characters would save 2.64 MB (3.0%) of the objects, but only 16,942 B (0.15%) of a stripped Hello (estimate).
   - Halving every non-public identifier would save 1.30 MB (1.5%) and about 27 KB (0.24%) respectively (estimate).
3. **Code is a tenth of the libraries but nearly three quarters of an app.**
   - `__text` is 8.6 MB (9.9%) of the objects and 72% of a stripped Hello (measured).
   - Swift runtime metadata is 0.61 MB (5.3%) of Hello. Both compilers emit the same amount to within 0.4% (measured on the objects).
4. **Today every app carries all of TUI.**
   - Hello keeps 98.9% of the library bytes it links (measured).
   - Each of 17 small apps that add one API family to Hello is exactly one 16 KB page larger (measured).
   - The cause is established: every public symbol and every conformance record is a root that dead stripping must keep.
5. **Per-module products would make API usage count.**
   - Linking only the modules an app uses takes Hello from 11.50 to 7.44 MB (−4.06 MB, −35.3%) and Stress down by 0.50 MB (−3.8%).
   - These are measured relinks, which assume each product links exactly its module closure.
   - A family then costs between 0 (stacks, `Image(systemName:)`) and 2.64 MB (ColorPicker).
6. **About 1 MB of every app is duplicated code that link-time fixes remove.**
   - `-Xlinker -deduplicate` saves 818 KB (−7.1%) of Hello.
   - Stopping SwiftBuild's per-module prelink from hiding weak definitions saves 350 KB (−3.0%).
   - Together they save 1.07 MB (−9.3%).
   - All three figures are measured, but no deduplicated binary has been run yet.
7. **The cheapest single lever is the export trie.** It is 772 KB (6.7%) of a stripped Hello and serves no purpose once the app is stripped. `-Xlinker -no_exported_symbols` removes it (−778 KB, measured).
8. **The 6.4.0 compiler emits 5.4% less code than 6.2.4, but SwiftBuild gives most of that back.**
   - With the same flags, Hello is 467 KB (4.0%) smaller on 6.4.0.
   - SwiftBuild's prelink adds 350 KB back.
   - So the shipped Hello is only 118,800 B (1.0%) smaller (all measured; the arithmetic closes to within 1.4 KB).

## 2. The angles

### 2.1 Composition and attribution

**The forms, side by side (measured).**

| form | 6.4.0 | 6.2.4 | notes |
|---|--:|--:|---|
| per-file objects (1,235) | 86,881,328 | 90,238,248 | 54.6% / 57.1% debug info |
| SwiftBuild's per-module `ld -r` objects (29) | 42,439,273 | — | what 6.4.0's apps link; DWARF swapped for a 13,653,930 B debug map |
| `libTUI-all.a` (libtool, per-file objects) | 95,804,080 | 99,003,448 | index 8,816,112 / 8,767,984 (with headers) |
| SwiftBuild's own `libTUI.a` | 44,273,328 | — | index and headers 1,834,055 |
| module files (`.swiftmodule` + `.swiftsourceinfo` + `.swiftdoc` + `.abi.json`) | 24,831,768 | 24,433,164 | compile inputs only; never in an app |
| umbrella dylib, unstripped / `strip -S -x` | 25,618,376 / 13,616,080 | 25,524,408 / 13,768,144 | |
| 29 per-module dylibs, unstripped / stripped | 28,030,456 / 16,046,192 | 28,858,056 / 16,515,728 | 2.43 MB more than one dylib, stripped |
| Hello, unstripped / `strip` | 25,538,248 / 11,502,960 | 25,411,432 / 11,621,760 | dSYM 53.3 MB, not shipped |

**What each step removes.**
- **Per-file to merged objects (SwiftBuild).** The merge swaps 47.4 MB of DWARF for the 13.65 MB debug map. Outside debug info it removes 10.6 MB more:
  - **Names, −6.0 MB.** Each module now lists its undefined references once, not once per file: 68,866 become 13,094. The duplicate weak copies' names also go.
  - **Load commands, −3.8 MB.** That is about 3.1 KB per object.
  - **Code, −280 KB.** These are copies that several files of one module each emitted.
- **Merged objects to a stripped app.**
  - The link drops names (−24.8 MB), relocations (−4.8 MB), compact unwind (−1.8 MB) and linker hints (−0.45 MB).
  - It adds the export trie, a code signature, stubs and fixups.
  - Dead stripping removes only 117,656 B (1.1%), half of it the unused C image decoder (measured).
- **Umbrella dylib to Hello.** Section by section the two agree within 0.7%. An app that imports `TUI` is the library plus its own code, nothing less.
- **Symbolicating SwiftBuild's `libTUI.a`.** It has no DWARF, so it can be symbolicated only while the intermediate per-file objects exist (inferred from how a debug map works; not tested).

**Per module** (6.4.0 per-file objects; the last column is the module's live section bytes in Hello's link map; measured):

| module | objects | share | of which DWARF | `__text` | share of code | live in Hello |
|---|--:|--:|--:|--:|--:|--:|
| TUIFoundation | 35,145,096 | 40.5% | 17,233,068 | 3,187,068 | 37.0% | 3,878,217 |
| TUIView | 5,015,248 | 5.8% | 2,413,771 | 534,500 | 6.2% | 635,666 |
| TUICore | 4,743,432 | 5.5% | 2,660,661 | 496,072 | 5.8% | 567,845 |
| TUILists | 4,232,352 | 4.9% | 1,981,062 | 489,332 | 5.7% | 566,071 |
| TUITables | 3,364,680 | 3.9% | 1,619,146 | 430,924 | 5.0% | 497,215 |
| TUIStyling | 3,120,344 | 3.6% | 1,807,141 | 319,096 | 3.7% | 373,271 |
| TUIApp | 2,875,736 | 3.3% | 1,497,977 | 250,356 | 2.9% | 299,228 |
| TUITextInput | 2,869,400 | 3.3% | 1,560,216 | 274,496 | 3.2% | 308,742 |
| TUINumericControls | 2,673,088 | 3.1% | 1,374,304 | 319,308 | 3.7% | 358,032 |
| TUIStrings | 2,426,720 | 2.8% | 975,366 | 201,980 | 2.3% | 510,646 |
| the other 19 | 20,415,232 | 23.5% | 9,845,328 | 2,116,024 | 24.6% | 2,492,531 |
| **total** | **86,881,328** | | **42,968,040** | **8,619,156** | | **10,487,464** |

**The shape is the same in every module.**
- In every TUI Swift module, code is 15–29% of the non-debug object bytes and names are 35–50%.
- **TUIStrings** is the exception: it holds the 200 KB SF Symbols name blob.
- **TUIFoundation** is about 40% of everything. Its weight caps what any per-module scheme can save.

**Per source file (measured).**
- `Table.swift` and `_ListCore.swift` hold 4.4% of all code: 195,828 and 182,384 B of `__text`.
- 157 of the 1,235 files hold half the code.
- The 423 files with under 2 KB of code each together carry 3.83 MB of non-debug object bytes for 308 KB of code. That is per-object overhead, and every link removes it.

**6.4.0 against 6.2.4.**

| | 6.4.0 | 6.2.4 | change |
|---|--:|--:|--:|
| `__text` in the objects | 8,619,156 | 9,114,692 | −495,536 (−5.4%) |
| read-only data | 529,849 | 602,183 | −12.0%, half of it ObjC names moved to their own sections |
| Swift metadata | 681,072 | 679,627 | +0.2% |
| DWARF and its relocations | 47,449,280 | 51,567,698 | −8.0% |
| stripped Hello, same flags on both (plain `swiftc` harness) | 11,120,040 | 11,587,352 | −467,312 (−4.0%) |
| stripped Hello as each build system ships it | 11,502,960 | 11,621,760 | −118,800 (−1.0%) |

The compiler's share is now established, for the harness's flags. The rest of the gap:
- On 6.4.0, SwiftBuild's prelink adds back 349,896 B and `-g` adds 33,024 B.
- On 6.2.4, native SwiftPM's Hello is 34,408 B above the harness's, and `-g` explains all of that but 1.4 KB.

### 2.2 Symbols and types

**Code by kind** (6.4.0 merged objects, `__text` 8,339,516 B; kinds classified from demangled names; bytes measured):

| kind of code | bytes | share |
|---|--:|--:|
| ordinary functions, methods, initialisers | 3,039,760 | 36.5% |
| value witnesses and outlined copy/destroy (per-type copy, move and destroy code the compiler generates) | 1,345,532 | 16.1% |
| generic specialisations | 1,138,064 | 13.6% |
| signature-only specialisations (dead arguments removed, closures propagated) | 887,028 | 10.6% |
| closures, partial-apply forwarders, closure-context destructors | 594,324 | 7.1% |
| accessors (get/set/modify) | 514,372 | 6.2% |
| protocol witness thunks | 338,512 | 4.1% |
| metadata and witness-table accessors, runtime helpers, global initialisers, key paths, async parts | 363,960 | 4.4% |
| unnamed code, C (CSTBImage) | 117,964 | 1.4% |

Composition's version of this table put 107 KB of merged value witnesses under "other". Corrected, value witnesses are 16.1% of code, not 14.8%.

**Who wrote it** (symbol bytes of the merged objects, from a re-run of `buckets.py`; Hello is the same symbols in the linked app; measured):

| bucket | libraries | share | Hello |
|---|--:|--:|--:|
| TUI's own code: functions, accessors, closures, own specialisations, thunks | 5,013,616 | 48.8% | 4,944,348 |
| type machinery the compiler generates: value witnesses, witness thunks and tables, metadata, descriptors | 3,284,268 | 31.9% | 3,311,246 |
| stdlib and Foundation generics instantiated for TUI's types | 1,185,940 | 11.5% | 1,185,216 |
| data: C strings, static tables, key paths | 500,951 | 4.9% | 138,974 (anonymous in an app) |
| swift-collections | 133,421 | 1.3% | 127,376 |
| other data and labels (left out of the angle's table) | 106,820 | 1.0% | 5,902 |
| C image decoder | 58,685 | 0.6% | 0 |
| **total** | **10,283,701** | | **9,713,062** |

**Largest functions.** The largest is 11,768 B (`formElements(from:in:)` in Forms). The 40 largest total 312 KB, and most are renderers with helpers inlined into them. No module's size comes from one function: in each module, the 6–10% largest functions hold half the bytes (measured).

**Largest types** (every symbol owned by the type or its extensions; measured):

| type | bytes |
|---|--:|
| `View` protocol extensions (the modifiers) | 150,280 |
| `_TableCore` | 142,092 |
| `_ListCore` | 133,392 |
| `FrameBuffer` (extensions in 5 modules) | 118,644 |
| `EnvironmentValues` (366 inlined getters, 425 modify coroutines) | 117,416 |
| `_VStackCore` | 96,164 |
| `_ScrollViewCore` | 82,436 |
| `ItemListHandler` | 80,376 |
| `Color` | 57,762 |
| `Text` | 53,872 |

The median TUI type costs 1,060 B. The largest owners overall are stdlib types instantiated for TUI:
- `_NativeDictionary`, 252,340 B;
- `String`, 108,468 B;
- `_ArrayBuffer`, 97,260 B;
- sorting (`UnsafeMutableBufferPointer`), 95,144 B.

**Generic specialisations (measured).**
- 87% instantiate stdlib generics: 989,412 of 1,138,064 B. TUI's own generics are 127,520 B.
- Dictionary machinery is 331,716 B over 211 key/value combinations, about 1.6 KB per `Dictionary<K, V>` a module mutates.
- Sorting is 146,384 B. Of that, 103,648 B comes from 35 call sites that sort with a closure literal. Each got a private copy of the merge sort, about 3 KB apiece.

**Value witnesses (measured).**
- 1,488 types have value-witness functions.
- The 363 `View` types carry 561,524 B of them.
- A generic type's value witnesses have a median of 1,284 B; a non-generic type's, 340 B.
- Every type also gets the two single-payload enum-tag witnesses that serve `Optional<T>`: 420,684 B together.

**Price list** (medians and averages, measured on builds without `-deduplicate`; dedup folds much of the per-type boilerplate, §2.4):

| thing | cost |
|---|--:|
| a public `View` type, before its own code | ≈ 2.5 KB |
| a non-generic struct / enum / class, before its own code | ≈ 0.8 / 0.9 / 0.4 KB |
| a `Hashable` conformance (with `Equatable`) | ≈ 0.5 KB |
| an environment value (getter, setter, modify, key path) | ≈ 0.3 KB |
| a `Dictionary<K, V>` a module mutates | ≈ 1.6 KB per module |
| `sort(by:)` with a closure literal | ≈ 3 KB per call site |
| an escaping, capturing closure, beyond its body | ≈ 112 B |
| a public symbol in an executable's export trie | ≈ 31 B |

**What the `.swiftmodule` files hold.** The 15.1 MB of `.swiftmodule` (measured, parsed from the bitstreams) are:
- 5.89 MB of declarations and types;
- 3.33 MB (22%) of serialised SIL bodies, which clients can inline;
- 2.69 MB of lookup index;
- 1.83 MB of identifiers.

The source has only 278 `@inlinable` and no `@_alwaysEmitIntoClient`. The symbols angle estimated that at least 95% of the SIL comes from the compiler's default cross-module optimisation (CMO). **A measurement contradicts that.**
- Turning CMO off removes only 706 KB of TUI's 2.60 MB of SIL (27%).
- What the remaining 1.89 MB is has not been broken down.
- CMO pays for itself: without it Hello grows 99,648 B and Stress 183,184 B (measured).

### 2.3 Names and metadata

The question was: is it the length of the names or their metadata, and should function and module names be shorter?

**In the built libraries it is the names, not the metadata.**
- Swift's runtime metadata is 0.68 MB (0.8%) of the objects.
- Names in their various tables are 38.0 MB (43.7%):

| where the names are (6.4.0 objects; measured) | bytes | share |
|---|--:|--:|
| symbol string table | 13,291,424 | 15.3% |
| symbol records (`nlist`) | 4,000,496 | 4.6% |
| debug-info name strings (`__debug_str`) | 15,305,733 | 17.6% |
| debug-info accelerator tables | 5,386,334 | 6.2% |

- **Overlap.** The last two rows are part of the 54.6% debug info, not in addition to it.
- **Merged objects.** In SwiftBuild's merged objects the string table is 41.3% of the file, because it also holds the debug map's names.
- **Archive.** The archive index adds 7.9 MB of name strings.

**Whose names they are** (string-table bytes, measured):

| owner | names | bytes |
|---|--:|--:|
| hidden weak definitions that a link coalesces | 86,459 | 5.81 MB |
| references to other files' symbols | 68,866 | 3.12 MB |
| local symbols | 63,536 | 2.30 MB |
| exported (public, package, `@usableFromInline`) | 24,743 | 1.63 MB |
| other hidden | 6,427 | 0.43 MB |

The long names are generic types, not long identifiers. Defined names have a median of 63 characters and a maximum of 1,317. The longest are nested result-builder types such as `VStack<TupleView<…>>`.

**Shorter module names: no.** Module names are 22% of the Swift symbol-name bytes (2.06 of 9.38 MB; measured). The rename figures below are an estimate: tokens counted, the knock-on mangling costs modelled, nothing rebuilt.

| rename all 24 modules to 3 characters | saving |
|---|--:|
| per-file objects | −2,637,504 (−3.0%) |
| SwiftBuild's merged objects | −2,074,607 (−4.9%) |
| the archive index | −1,064,841 |
| unstripped Hello | −1,026,859 (−4.0%) |
| **stripped Hello** | **−16,942 (−0.15%)** |
| stripped Stress | −16,997 (−0.13%) |

- **Per character dropped:**
  - in the objects, about 102 KB for TUIFoundation, 55 KB for TUIView and 47 KB for TUICore;
  - in an app, almost nothing.
- **Why the app barely moves:**
  - `strip` removes the mangled names.
  - Type references are mostly 4-byte offsets.
  - The trie shares prefixes. The rename cuts the trie's name text by 19%, but the trie by only 7,860 B.
- **What it would cost:**
  - every `import` and every qualified name in client code changes;
  - `NavigationPath` data already saved with mangled type names would no longer decode;
  - resource bundle names change;
  - crash logs get harder to read.

**Shorter function names: no.**
- **Public names stay**, because they are SwiftUI's.
- **Halving every non-public identifier** (estimate, same model) would save:
  - per-file objects: 1.30 MB (−1.5%);
  - merged objects: 0.81 MB (−1.9%);
  - stripped Hello: about 27 KB (−0.24%);
  - stripped Stress: about 29 KB.
- **After `strip`, an internal function's name costs nothing.** A non-public name survives in only four places:
  - **a type's name in its descriptor:** 37,188 B of type names in Hello, half of them for non-exported types;
  - **stored-property names in the reflection strings:** 74,691 B, of which only 36,969 B are distinct, because each per-file LLVM module emits its own copy;
  - **Objective-C class names:** 33.5 KB;
  - **`package` and `@usableFromInline` names in the stale trie:** about 174 KB of it. `-no_exported_symbols` removes these along with the rest.

**Names in a stripped app** (measured; the right-hand column says which row of the §1 app table holds each one):

| item | Hello | Stress | in §1 row |
|---|--:|--:|---|
| export trie: 24,702 exported names, which `strip` cuts to one entry but leaves in the file | 772,216 | 775,360 | export trie |
| symbol table, almost all import names (`strip -N` removes 102,480 B) | 116,728 | 121,116 | symbol table |
| chained fixups: the import names dyld binds by | 72,332 | 74,768 | signature, fixups |
| SF Symbols name blob (`__cstring`) | 200,348 | 200,348 | data |
| other C strings: `#fileID` 13,558, `fatalError` messages 10,158, other literals, padding | 44,664 | 135,480 | data |
| type, protocol and module names | 41,562 | 44,580 | data |
| reflection field and case names (`__swift5_reflstr`) | 74,691 | 80,675 | data |
| mangled type-reference text (in a 133,364 B section that is half 4-byte symbolic references) | 54,066 | — | data |
| Objective-C class and ivar names | 33,529 | 36,777 | data |

These rows are not a fourth partition, and they do not add to the §1 total. The in-section strings (about 0.33 MB besides the SF table) are part of the 16.2% data row. All of TUI's module names together are about 12 KB of a stripped Hello.

**Reflection metadata stays (established from the source).** `@State` and `@Environment` are found with `Mirror(reflecting:).children` (`Sources/TUIView/State/State.swift:662`, `Sources/TUIView/Environment/EnvironmentProperty.swift:258`).

| flag | Hello | what it breaks |
|---|--:|---|
| `-disable-reflection-metadata` | −383,104 (−3.4%), measured | `Mirror` sees no children, so `@State` never binds |
| `-disable-reflection-names` | −60 to −68 KB, estimate | `String(describing:)` loses case names and field values, so `identityKey` gives every enum- or struct-keyed row the same key. TypeWalk is unaffected: it passes `""` for a missing name |

**Diagnostic strings** are 23.7 KB of Hello (measured).
- 188 of the `fatalError` messages are the `_*Core` "renders via Renderable" bodies. One shared helper would save about 15–25 KB (estimate).
- `precondition` and `assert` messages are already absent from release builds.

### 2.4 Duplication

**Inside the built libraries (6.4.0; models over the objects):**
- **Same-name copies within a module, 616 KB.** The per-file objects hold 616 KB of `__text` that is a second copy under the same name, mostly within one module across its files. Any link, or SwiftBuild's merge, coalesces these.
- **Copies across modules, 340 KB.** SwiftBuild's merged objects still hold 340 KB of copies across modules, and these can no longer coalesce (below).
- **Identical code under different names, 640 KB.** This is a further 640 KB of byte-identical code (an identical-code-folding model, so a lower bound).

**Into every app: two measured link-time levers.** These are relinks of the artifacts' own objects; each "as built" relink reproduces the shipped size to the byte.

| binary | today | `-deduplicate` | SwiftBuild prelink fixed | both |
|---|--:|--:|--:|--:|
| Hello 6.4.0 | 11,502,960 | −818,208 (−7.1%) | −350,192 (−3.0%) | −1,068,176 (−9.3%) |
| Stress 6.4.0 | 13,008,592 | −936,000 (−7.2%) | −400,064 (−3.1%) | −1,219,280 (−9.4%) |
| umbrella dylib 6.4.0 | 13,616,080 | −818,208 (−6.0%) | −350,208 (−2.6%) | −1,068,192 (−7.8%) |
| Hello 6.2.4 | 11,621,760 | −734,448 (−6.3%) | not affected | — |
| Stress 6.2.4 | 13,126,496 | −820,256 (−6.2%) | not affected | — |

The two levers overlap by about 100 KB (measured). Each is explained below.

- **SwiftBuild's prelink.**
  - **The mechanism.** SwiftBuild merges each module's objects with `ld -r` and passes no `-keep_private_externs`. That turns the compiler's hidden weak definitions into local symbols. Locals from different modules never coalesce, so each module keeps its own copy.
  - **The cause is established three ways:**
    - `man ld`;
    - the command line in the build log;
    - the symbol bindings: weak and private-extern in the per-file objects, local (`was_pext`) after the merge.
  - **What the copies are.** Hello carries 3,741 extra copies of 988 functions. They are mostly stdlib specialisations (198 KB), plus outlined copies, `__swift_*` helpers and metadata caches.
  - **Two measurements agree to 32 B.** One re-merged the objects with `-keep_private_externs`; the other linked the per-file objects directly. They replace composition's 344 KB and symbols' 290 KB, which were estimates.
  - **What is still untested:**
    - SwiftBuild itself passing the flag;
    - a 6.4 build with `--build-system native`.
  - **A user cannot fix it.** User `-Xlinker` flags do not reach the prelink (established from the build log).
  - **The fix has a library-side cost.** SwiftBuild's own `libTUI.a` index would list the hidden symbols again: up to about +5.7 MB of index (estimate). An app never carries that index.
- **ld's deduplication is off.**
  - **Why it is off.** Swift's link step passes no dedup flag, and ld-1230's default then folds nothing.
  - **What `-Xlinker -deduplicate` folds.** About 20,000 identical functions in Hello. By kind (model):
    - value witnesses of same-layout types, 317 KB, the largest group;
    - localised helpers, 130 KB;
    - witness thunks, 74 KB;
    - specialisations, 74 KB;
    - accessors, 54 KB;
    - outlined copies, 52 KB.
  - **This corrects two angles.** Composition and symbols said value witnesses have no bulk lever short of a macOS 15.4 deployment target; dedup is one.
  - **What is left.** After both levers, only 19.6 KB of identical code remains in Hello (model).
  - **The risk:**
    - 81% of the saving comes from folding Swift functions whose addresses sit in witness tables.
    - `-no_deduplicate_allow_swift_addr_ref` excludes those, and then saves only about 135 KB.
    - That the linker has a Swift-specific switch suggests Apple supports folding them. That the Swift runtime never compares those addresses is a hypothesis.
    - No deduplicated binary has been run.
- **Near-identical code is another 654 KB (model).** It has the same instructions but different call targets, and no shipping tool merges it.
- **TUI's own generics duplicated across modules: 4.5 KB** (measured). Not worth a change.
- **Strings and constant data are not where the duplication is.**
  - C strings are merged at link time.
  - Field-name strings repeat 37.7 KB in Hello, which ld cannot merge.
  - Identical constant data is at most 27 KB.

### 2.5 Data, resources and build options

**Data in the libraries** (6.4.0 merged objects, measured): 1,885,637 B, against 8,339,516 B of code.
- **About 75% is Swift runtime metadata**, emitted per type, conformance and field: 1.41 MB.
- **Tables** are 316 KB.
- **The one big table is the SF Symbols names: 251,236 B.** That is 200,348 B of names, 33,912 B of offsets and 16,976 B of codepoints, about 2.2% of a stripped Hello. It is compiled only for macOS (`#if canImport(AppKit)`). The options (estimates):
  - front-coding the names saves 149,784 B;
  - moving the table into the resource bundle takes all 251 KB out of the binary;
  - DEFLATE saves about 219 KB, but costs about 200 KB of heap.
- **The next-largest table** is the 23 KB glyph calibration, which code builds at first use.
- **The resource bundle** is 40,769 B: seven translation files and `VERSION`. None of it is duplicated in the binary.
  - Established: the bundle accessor traps when the bundle is missing.
  - Not established: that every app reaches it.
  - A bare CLI binary that never localises works without the bundle today. It would silently lose SF Symbols if the table moved into the bundle.

**Build options** (all measured). The figures come from a plain-`swiftc` harness with the same flags on both toolchains. App deltas are against the harness's own stripped base, which has no SwiftBuild duplicates: 11,120,040 B for Hello and 12,575,768 B for Stress.

| option | library objects (TUI's 25 modules) | Hello | Stress | runtime |
|---|---|--:|--:|---|
| `-g` (both build systems' release default) vs none | 85.0 vs 36.4 MB (DWARF 49.3%) | +33,024 | +33,024 | none |
| `-gline-tables-only` instead of `-g` | 66.5 MB (−18.5 MB) | 0 | 0 | none |
| `-Xlinker -no_exported_symbols` | n/a | −778,288 (−7.0%) | −781,376 (−6.2%) | none |
| `-internalize-at-link` | ≈ 0 | −1,623,312 (−14.6%) | −1,524,400 (−12.1%) | ±1% (pre-split A/B) |
| internalize + `-no_exported_symbols` | | −1,961,024 (−17.6%) | −1,878,144 (−14.9%) | ±1% |
| `-Osize` | `__text` −12.0%, but objects +3.7% (unwind +60%) | −920,768 (−8.3%) | −1,049,936 (−8.3%) | +4.5% to +20.5% CPU per frame (pre-split A/B) |
| `-Xlinker -no_function_starts` | n/a | −71,464 (−0.6%) | −80,480 (−0.6%) | profilers lose function boundaries |
| `-disable-cmo` | SIL −27%, `__text` +1.1% | +99,648 (+0.9%) | +183,184 (+1.5%) | unmeasured, likely slower |
| `-disable-reflection-metadata` | data −18% | −383,104 (−3.4%) | −382,880 (−3.0%) | breaks `@State` |
| ThinLTO | bitcode ×1.93 | +782,624 (+7.0%) | +782,336 (+6.2%) | unmeasured |
| full LTO | bitcode ×1.86 | +235,728 (+2.1%) | — | unmeasured |
| full LTO + internalize + conditional runtime records + `-no_exported_symbols` | | −4,038,160 (−36.3%) | −3,239,104 (−25.8%) | unmeasured; Stress `--selfcheck` passes |
| `-enable-library-evolution` | both compilers crash on TUICore (`FrameBuffer.lines` modify accessor) | — | — | — |
| `-enable-cmo-everything` | `.swiftmodule` ×4–8, then both compilers crash | — | — | — |

Notes on the table:
- **`-Osize` figures.** The old SIZE2 numbers were measured on 6.2.4 before the split: −9.1% Hello, −14.3% Stress. They are stale. On 6.4.0 it is −8.3% for both, so dedup plus the prelink fix (−9.3%, no recompiling) already beats it.
- **`-g` in a stripped app.** The +33 KB is measured but unexplained. Hypothesis: `__eh_frame` entries, since the objects' unwind bytes double with `-g`.
- **SwiftBuild writes absolute paths into every `.swiftmodule`.** These are the scratch directory, the SDK and the toolchain: about 0.44–0.47 MB over the closure (measured). They cost nothing in an app, but they would put the build machine's paths into a binary distribution.
- **Two compiler crashes** (library evolution, CMO-everything) are worth reporting upstream. Library evolution is what a binary distribution would need, so it is blocked today.

### 2.6 API usage and app size

**Today, usage does not change size.**
- Hello is 11,502,960 B.
- Each of 17 apps (a control app, plus 16 that each add one API family to Hello) is 16,544–16,712 B larger. That is one 16 KB page, since each adds only 1.5–5.8 KB of its own code.
- An app with all 16 families is +66.9 KB.
- The library part of all 22 binaries is the same to within 0.6 KB per module (measured).

Why (established with `-why_live`): three kinds of root keep everything.
- **All 24,700 public and `package` symbols.** Swift puts them in `llvm.used`, which marks them `N_NO_DEAD_STRIP`; 43 of the 24,743 exports are not marked.
- **6,254 runtime records.**
- **5,284 reflection descriptors.**

SwiftPM also links every object of the product's closure. So `Table.body`, a public symbol, and the `Table : View` conformance record each keep `_TableCore`'s renderer alive in Hello.

**With per-module products (C9b), usage counts per module.** The baseline is today's SwiftBuild link, stripped.
- **measured** rows are relinks of the same objects.
- **emul.** rows emulate internalize or conditional records.
- **C9b rows** assume each product links exactly its module closure. If products bundle several modules, the numbers move back toward today's.

| link | Hello | Stress | how known |
|---|--:|--:|---|
| today | 11,502,960 | 13,008,592 | measured |
| `-no_exported_symbols` | 10,724,680 (−6.8%) | 12,227,120 (−6.0%) | measured |
| internalize | 9,764,992 (−15.1%) | 11,386,448 (−12.5%) | emul. |
| internalize + `-no_exported_symbols` | 9,439,136 (−17.9%) | 11,044,480 (−15.1%) | emul. |
| C9b | 7,442,528 (−35.3%) | 12,511,168 (−3.8%) | measured |
| C9b + `-no_exported_symbols` | 6,870,512 (−40.3%) | 11,744,384 (−9.7%) | measured |
| C9b + internalize + `-no_exported_symbols` | 5,951,120 (−48.3%) | 10,446,096 (−19.7%) | emul. |
| conditional records + internalize + `-no_exported_symbols`, every module linked | 7,385,488 (−35.8%) | 9,641,808 (−25.9%) | emul. |
| the same with C9b | 4,431,616 (−61.5%) | 9,043,248 (−30.5%) | emul., never run |

What C9b would change for each sample app:
- **Hello** would link 11 of the 29 modules: App, Chrome, Foundation, Core, Styling, View, Strings, TerminalHost and the three swift-collections modules.
- **Typical** (List, Table, TextField, Toggle) goes from 11.52 to 8.92 MB (−22.6%).
- **Example** uses every module, so it does not change.
- **Stress** drops Bitmaps, ColorPicker and Grid.
- **On 6.2.4** the picture is the same: Hello goes from 11.62 to 7.64 MB.

**What a family costs under C9b** (stripped bytes over Hello, measured):

| family | cost |
|---|--:|
| `Image(systemName:)`, custom `Layout`, `GeometryReader`, stacks, `Toggle`, `@State`, `Button` | 0 |
| Grid | +55 KB |
| Menu | +56 KB |
| Form | +106 KB |
| animation | +145 KB |
| pickers | +233 KB |
| text input | +311 KB |
| bitmap image | +352 KB |
| numeric controls | +356 KB |
| navigation + sheet + alert | +487 KB |
| List | +616 KB |
| `.searchable` | +667 KB |
| TabView | +898 KB |
| Table | +1.14 MB |
| ColorPicker | +2.64 MB |

- **Modules add up; families overlap.** A module's live bytes are the same in every link, so a set of modules costs the sum of its members, within page rounding. Families share modules, though: the 16 marginals sum to 8.06 MB, while all 16 in one app add 4.13 MB.
- **ColorPicker is expensive because of what it imports.**
  - It pulls in 8 modules: its own (278 KB) plus Image, NumericControls, Pickers, Presentation, Tabs, Lists and TextInput.
  - If its panels could do without Tabs (and so Lists) and TextInput, it would cost about 1.2 MB less (estimate). Whether they can is a design question.

**Conditional runtime records: the earlier headline is retracted.**
- **What was claimed.** The duplication angle's model said conditional records plus internalize would take Hello's library bytes to 3.63 MB (−65%). SIZE2's earlier model said 3.66 MB.
- **Two results contradict it:**
  - a real full-LTO + internalize + conditional-records build of Hello is 7,100,088 B, with about 6.7 MB of library bytes still live (measured);
  - an emulation with 6.4.0's own conditions gives 7,385,488 B.
- **The cause, established for three modules.**
  - 6.4.0 keeps closure-capture, builtin and multi-payload-enum descriptors as unconditional roots.
  - Those descriptors name leaf types such as `ColorPicker`, `_TableCore` and `_AsyncImageCore`.
  - A type that is named passes its records' conditions, and its records keep its module.
  - This was traced for ColorPicker, Tables and Bitmaps. What keeps Lists is unknown.
- **Corrected figure.** With every module linked, conditional records give about −36%. Only together with C9b do they reach −61.5%, and that figure is emulated and has never been run.

**The two threads together: usage and the built libraries.** Under C9b, a consumer compiles and stores only the modules its app needs.
- Hello's 11 modules are 57.2 of the 86.9 MB of objects (−34%) and 10.2 of the 15.1 MB of `.swiftmodule` (−32%). These are estimates: sums of the measured per-module sizes.
- TUIFoundation alone is 61% of the objects Hello needs, which caps the gain on the library side.
- The compile time of such a build was not measured.

## 3. Levers

The owner's ranking is runtime > bytes > compile time. The tables below follow it:
- **App levers (§3.2).** Levers with no expected runtime cost come first, ordered by bytes saved per unit of effort. Levers that touch the per-frame path come after them, because the performance policy requires a quiet-box A/B before they can be recommended.
- **Library levers (§3.1).** They are listed separately, because they never reach an app.
- **Counting.** Each lever is counted once, even where several angles list it. Levers do not simply add; §3.3 has the measured combinations.

### 3.1 On the built libraries, before linking

These matter today for build directories, caches and CI disk, and for a binary distribution if one is ever made. The package cannot set them for consumers: SwiftPM refuses `unsafeFlags` in a dependency. So they are the distributor's or the consumer's settings.

| lever | library bytes (6.4.0) | effect on apps | cost | who | confidence |
|---|--:|---|---|---|---|
| build without DWARF | −48.6 MB of 85.0 MB of objects (TUI's 25 modules) | 0; `-g` costs a stripped app +33 KB | no source-level debugging from these objects | distributor; consumer's build settings | measured |
| `-gline-tables-only` | −18.5 MB of 85.0 MB | 0 | the debugger has file:line, no variables or types | as above | measured |
| archive index (`__.SYMDEF`) | 8.8 MB of the 95.8 MB per-file archive. It lists 86,459 hidden weak definitions. SwiftBuild's merged form needs only 1.8 MB because its merge hides them, and that hiding is exactly what creates the 350 KB of app duplicates | a trade-off with the prelink fix: up to +5.7 MB of index (estimate) against −350 KB per app | none | build system | measured; the +5.7 MB is an estimate |
| one dynamic library, not 29 | −2,430,112 B stripped (13.6 vs 16.0 MB) | n/a | product layout | package, if dynamic products ship | measured |
| dylib `strip -x -T` instead of `-S -x` | −2,135,248 B (−15.7%) | n/a | none expected; the stripped dylib was never loaded | distributor | size measured |
| `-deduplicate` on the dylib | −818,208 B (−6.0%); with the prelink fix −1,068,192 B | n/a | as for apps (§3.2) | product maintainer | measured |
| drop `.swiftsourceinfo` from a binary distribution | −5.28 MB | 0 | IDE jump-to-source into TUI | distributor | estimate (file size; role established, untested) |
| `-no-serialize-debugging-options` | about −0.44 to −0.47 MB of `.swiftmodule`, and no build-machine paths | 0 | the debugger may need search paths | distributor | size measured as a difference; the flag's effect is untested |
| SF Symbols front-coding | −149,784 B | the same in every macOS app | a decode per lookup (§3.2) | package | estimate |
| rename modules to 3 characters | −2.64 MB of objects (−3.0%) | −17 KB | breaks every import; not recommended | — | estimate |
| halve non-public identifiers | −1.30 MB (−1.5%) | −27 KB | readability; not recommended | — | estimate |
| library evolution (for a binary distribution) | `.swiftmodule` −37% for the one module that compiled | `__text` +3.7% | resilient access, slower | package | blocked: both compilers crash on TUICore |

### 3.2 On linked apps, ranked

All figures are 6.4.0. Stripped Hello is 11,502,960 B and stripped Stress 13,008,592 B. Stripped files grow and shrink in 16 KB steps, so a saving under about 50 KB may show as 0 or 16 KB.

| # | lever | libraries | Hello | Stress | runtime cost | compile-time cost | API / debuggability cost | who | confidence | effort |
|--:|---|---|--:|--:|---|---|---|---|---|---|
| 1 | `-Xlinker -no_exported_symbols` (Xcode `LD_EXPORT_SYMBOLS = NO`) | n/a | −778,280 (−6.8%) | −781,472 (−6.0%) | none: no code changes | none | the app can't serve its symbols to plugins; nothing is lost for a stripped app, whose trie `strip` already emptied | app developer | measured; three relinks agree to 8 B; selfcheck passed at B1 | a README line |
| 2 | `-internalize-at-link` on every module (`-Xswiftc -Xfrontend -Xswiftc -internalize-at-link`) | ≈ 0 (one flag bit per symbol) | −1.62 MB (−14.6% of the harness base; real flag, per-file link) / −1.74 MB (−15.1%; emulated, SwiftBuild link) | −1.52 MB (−12.1%) / −1.62 MB (−12.5%) | ±1% per frame, measured before the split on 6.2.4 | none | static links only: no dynamic TUI, no plugins calling the app's TUI | app developer | bytes measured and emulated; the runtime A/B predates the split | a README line + a re-A/B on the split tree |
| 3 | SwiftBuild's prelink keeps private externs (upstream fix), or users build with `--build-system native` on 6.4 | objects unchanged; SwiftBuild's `libTUI.a` index grows by up to 5.7 MB (estimate) | −350,192 (−3.0%) | −400,064 (−3.1%) | none expected: one copy instead of one per module; possibly slightly faster, with one metadata cache per type instead of one per module (hypothesis) | none | none | swift-build upstream; users via the native build system (deprecated in 6.4; untested there) | measured two ways, agreeing to 32 B | an upstream issue + a README note |
| 4 | `-Xlinker -deduplicate` | umbrella dylib −818,208 | −818,208 (−7.1%) | −936,000 (−7.2%) | unmeasured; expected neutral or slightly better. No folded binary has run | none (links take about 1 s) | folded functions share an address, so crash reports and profiler samples name one of several siblings; `Tools/Profiling` builds must not use it | app developer; dylib maintainer | bytes measured; safety unknown | selfcheck + golden snapshots + quiet-box A/B, then a README line |
| 5 | per-module library products (C9b) | 0 in objects and archives; a consumer builds only what its app needs (Hello: 57.2 of 86.9 MB, estimate) | −4,060,432 (−35.3%) | −497,424 (−3.8%) | none expected: identical machine code (unmeasured) | less for small apps (Hello compiles 11 of 29 modules; unmeasured) | users pick products and import per module; the umbrella stays | package (planned; deferred "for now") | measured relinks, assuming each product links exactly its module closure | the planned step C9b |
| 6 | `strip -N` after `strip` | n/a | −102,480 (−0.9%) | −105,776 (−0.8%) | none expected | none | `nm` and `otool` on the shipped binary lose import names | app developer | size measured; `codesign -v` passes; launch untested | a launch check, then a README line |
| 7 | SF Symbols names front-coded (already approved) | −149,784 (estimate) | ≈ −148 KB (−1.3%) | ≈ −148 KB (−1.1%) | a block decode per uncached lookup (estimate: under 1 µs); `Label(systemImage:)` looks a name up on every body, so it needs the A/B | none | none | package | bytes estimated from the current 8,466 names | a small lane |
| 8 | `@_alwaysEmitIntoClient` on the fixed-arity builder overloads (Table columns and rows, Tabs, Toolbar, Slider ticks) | −102,172 (estimate) | ≈ −107 KB (−0.9%) | ≈ −80 to −100 KB | none expected: client copies are specialised | apps compile the arities they call | none (library evolution is off) | package | estimate from measured symbols. Overlaps internalize, which drops them anyway, and C9b, under which Hello keeps only Toolbar's (≈ 15 KB) | small |
| 9 | `@_alwaysEmitIntoClient` on public `View` modifier wrappers | ≈ −130 KB (estimate) | ≈ −110 to −150 KB | ≈ −100 to −140 KB | changes inlining at every call site, so it needs the A/B | apps compile the modifiers they use | modifier frames move into callers | package | estimate; a probe compiles on 6.2.4 and 6.4.0 | medium: 534 modifiers |
| 10 | full LTO + internalize + conditional runtime records (+ `-no_exported_symbols`) | objects become bitcode (×1.86) | −4,038,160 (−36.3%, measured on the harness); −4,117,472 (−35.8%, emulated on SwiftBuild's link); with C9b −7,071,344 (−61.5%, emulated, never run) | −3,239,104 (−25.8%); with C9b −3,965,344 (−30.5%, emulated) | unmeasured; Stress `--selfcheck` passes | a full-LTO link of Hello takes 35–55 s, and every app link re-optimises all of TUI | experimental flags with open compiler issues; LTO dSYMs may be incomplete | app developer | bytes measured; correctness only smoke-tested | at most, document as experimental |
| 11 | one shared sort helper for the 35 sorts that each got a private merge sort | −28 to −95 KB (estimate, depending on how many sites move) | the same | the same | cold sites: none. The 13 render-path sites add an indirect compare per comparison, so they need the A/B | none | none | package | estimate | small–medium |
| 12 | fold the six Bool `View` trait requirements into one `_traits` | ≈ −29 KB (estimate); ≈ −15 KB once dedup is on | the same | the same | traits are queried per child on every render, so it needs the A/B | none | changes underscored requirements (not SwiftUI API) | package | estimate | medium |
| 13 | flatten the glyph calibration table to static data | ≈ −20 KB (estimate) | ≈ −16 KB (one page) | the same | none: it is built once today | none | none | package | estimate | small |
| 14 | one helper for the 188 `_*Core` `fatalError` bodies | negligible | ≈ −15 to −25 KB (estimate) | the same | none: the path runs only on a bug | none | the crash's file:line names the helper | package | estimate | small |

Levers 1–4 and 6 are link or strip flags that only the app developer can set, so they belong in a README size recipe. That recipe has been owed since SIZE2. Levers 5 and 7–14 are changes to TUI itself.

### 3.3 How the levers combine

| combination (6.4.0, stripped) | Hello | Stress | how known |
|---|--:|--:|---|
| `-deduplicate` + prelink fix | −1,068,176 (−9.3%) | −1,219,280 (−9.4%) | measured; 100 KB less than the sum of the two |
| internalize + `-no_exported_symbols` | −2,063,824 (−17.9%) | −1,964,112 (−15.1%) | emulated. Internalize already cuts the trie to 323–335 KB, so `-no_exported_symbols` then adds only 326–338 KB |
| C9b + `-no_exported_symbols` | −4,632,448 (−40.3%) | −1,264,208 (−9.7%) | measured |
| C9b + internalize + `-no_exported_symbols` | −5,551,840 (−48.3%) | −2,562,496 (−19.7%) | emulated |
| conditional records (full LTO) + internalize + `-no_exported_symbols` | −4,117,472 (−35.8%) | −3,366,784 (−25.9%) | emulated; the real build on the harness gives −36.3% / −25.8% |
| the same with C9b | −7,071,344 (−61.5%) | −3,965,344 (−30.5%) | emulated, never run |
| the full recipe: strip + `-no_exported_symbols` + `-deduplicate` + prelink fix + internalize, with and without C9b | unmeasured | unmeasured | link-only and cheap to measure (§4) |

Also not measured:
- dedup with internalize;
- dedup with C9b;
- the prelink fix with C9b;
- any package lever under C9b or internalize.

### 3.4 Not recommended

| option | Hello | why not |
|---|--:|---|
| `-Osize` | −920,768 (−8.3%), measured | +4.5% to +20.5% CPU per frame (pre-split A/B); levers 3 + 4 save more without recompiling |
| `-Xlinker -no_function_starts` | −74,464 (−0.6%), measured | profilers and crash tools lose function boundaries |
| `-disable-reflection-metadata` | −383,104 (−3.4%), measured | `@State` and `@Environment` silently never bind |
| `-disable-reflection-names` | −60 to −68 KB, estimate | rows keyed by an enum or struct all get the same identity |
| ThinLTO / full LTO alone | +782,624 (+7.0%) / +235,728 (+2.1%), measured | larger, not smaller |
| `-disable-cmo` | +99,648 (+0.9%), measured | larger, and likely slower |
| shorter module names | −16,942 (−0.15%), estimate | breaks every client's imports and saved `NavigationPath` data |
| shorter non-public identifiers | about −27 KB (−0.24%), estimate | worse readability everywhere, for 0.24% |
| `-disable-dynamic-actor-isolation` | (drops some `#fileID`s) | a safety trade-off, not a size lever |

## 4. What we do not know yet

| unknown | why it matters | what would settle it | cost |
|---|---|---|---|
| The size of the full recipe stacked (strip + `-no_exported_symbols` + `-deduplicate` + prelink fix + internalize), with and without C9b, for Hello and Stress | every lever was priced alone, and the measured overlaps show they do not add up | relinks with the existing `usage.py` and `dupes/relink.py` | link-only, minutes |
| Whether a deduplicated binary runs correctly | 81% of dedup's saving folds functions whose addresses sit in witness tables | Stress `--selfcheck` and the golden snapshots on a `-deduplicate` link | one link + one run |
| Runtime on the split tree of internalize, dedup, and LTO with conditional records | the only runtime data (internalize ±1%, `-Osize` +10%) predate the split | quiet-box A/Bs | quiet-box time |
| Runtime of the package levers on the per-frame path: SF front-coding, the render-path sorts, the trait fold, the modifier wrappers | all four touch code that runs every frame | a quiet-box A/B per lever, as each lands | quiet-box time |
| Launch time, page-in and dirty memory | binary size reaches users mainly this way, and no angle measured it | a launch benchmark of Hello and Stress, before and after the recipe | a small harness |
| What a 6.4 build with `--build-system native` looks like | it is the remedy users can apply today for the prelink duplicates; its other size effects are unknown | one build of Hello and Stress | one build slot |
| Whether SwiftBuild accepts the fix, as `-keep_private_externs` on its prelink or as `-Xxcbuild KEEP_PRIVATE_EXTERNS=YES` | it is the remedy for every 6.4 user | try the setting; file upstream | small |
| How much SwiftBuild's own `libTUI.a` grows with that fix | it is the fix's library-side cost (up to +5.7 MB, estimate) | build its archive with the flag | one build |
| Linux | no angle covers it; there, every public function is a retained root (SIZE2) | the same artifacts on the Linux static SDK | a build lane |
| Xcode-project consumers | it is a hypothesis that Xcode prelinks package targets the same way; whether Archive strips and whether links deduplicate is unknown | one Xcode archive of Hello | small |
| Debug-configuration library sizes | all six angles measured release builds only | one debug build | small |
| What the 1.89 MB of SIL that stays without CMO is | it is about an eighth of the `.swiftmodule` bytes, and unexplained | break the SIL block down by kind | analysis only |
| Why 6.4 grows more per module carve than 6.2.4 (+72.7 vs +39.5 KB for one carve) | it decides whether further carves cost more on 6.4 | relink one carve with and without the prelink fix | link-only |
| What keeps TUILists alive under conditional records | the −61.5% C9b figure depends on the emulation being right | `-why_live` on Lists' type descriptors under `cond` (the script is written but has not run) | link-only |
| C9b's real product shape | the −35% assumes one product per module closure | decide the products, then relink | design + link |
| Whether every app needs the resource bundle | it decides whether the SF table may move into the bundle | check which entry points reach `Bundle.module` | analysis |
| Whether `strip -N` binaries launch | it decides lever 6 | launch one | trivial |
| The +33 KB that `-g` adds to a stripped app | small; the hypothesis is `__eh_frame` | compare the two binaries' sections | analysis only |

## 5. Questions for the owner

1. **README size recipe.** Shall I write the README size section owed since SIZE2? It would give `strip`, `-Xlinker -no_exported_symbols` and internalize for static app links, with SIZE2's warnings: static links only, and never disable reflection.
   - I propose adding `-deduplicate` and `strip -N` only after the selfcheck, launch check and A/B in §4.
   - Without dedup, the recipe saves about 2 MB (−18%) of Hello (emulated). Dedup would add an amount not yet measured.
2. **Upstream reports.** Shall I draft three issues for you to file? (I never file or comment on issues myself.)
   - swift-build: the prelink drops `-keep_private_externs`, costing every 6.4 app 3% (measured).
   - swiftlang/swift: library evolution crashes on TUICore.
   - swiftlang/swift: `-enable-cmo-everything` crashes.

   Separately: once a native 6.4 build has been measured, should the README tell 6.4 users about `--build-system native`, which 6.4 marks deprecated?
3. **C9b timing and shape.**
   - Per-module products are the largest lever for small apps: Hello −35%, Typical −23% (measured relinks).
   - You chose umbrella-only "for now" to battle-test the split. Do you want to bring C9b forward?
   - Should products be one per module (the figures assume this), or grouped?
4. **ColorPicker's dependencies.** Under C9b, ColorPicker costs 2.64 MB, because its panels pull in Tabs, Lists and TextInput. Is a lighter panel, worth about 1.2 MB (estimate), a design change you would consider?
5. **SF Symbols table.** Which option do you want?
   - Front-coding: −150 KB and a decode per lookup. Already approved.
   - Moving it into the resource bundle: −251 KB, but a bare binary shipped without its bundle loses SF Symbols.
   - DEFLATE: −219 KB, plus 200 KB of heap.

   I lean to front-coding.
6. **The small package levers.** These are the builders, the modifier wrappers, the sorts, the traits, the glyph table and the `fatalError` helper. Together they are worth about 0.3–0.4 MB of Hello (estimate), and they shrink sharply under internalize or C9b. Do you want them as one lane with A/Bs now, or after C9b, when their real worth is known?
7. **A binary distribution.** Is one on the table, for example an xcframework?
   - If not, the library-side levers in §3.1 matter only for build directories and CI disk, and I would not pursue them.
   - If so, the compiler crash in library evolution blocks it today.
8. **Full LTO with conditional records.** It gives −36% on its own and −61.5% with C9b (emulated), but it uses experimental flags with open compiler issues, and its links are slow. Should I leave it unmentioned, or document it as experimental once a runtime A/B exists?

Unless you say otherwise, I will run the cheap measurements in §4 next, in this order:
- the stacked relink;
- the dedup selfcheck;
- a 6.4 native build;
- the `strip -N` launch check.

They are link-only or single builds, and questions 1, 2 and 6 depend on their figures.

## 6. Follow-up measurements (2026-10-10, after the first review)

The owner asked for the cheap link-only measurements from §4. Six lanes ran them, and a critic cross-checked them. Raw notes are in the working notes' SIZE3 folder, under `fu/<lane>/notes.md`. The critic's corrections are applied below, and this section supersedes §1–§5 where they differ.

### 6.1 The full recipe, stacked (6.4.0, stripped)

Every row that includes internalize is emulated, and so are the C9b columns. The internalize emulation is now checked against the real flag: it clears exactly the same bits in both compiled modules, and its app sizes come within about 1.6 KB, or one 16 KB page.

| step (cumulative) | Hello | Hello + C9b | Stress | Stress + C9b |
|---|--:|--:|--:|--:|
| strip | 11,502,960 (0) | 7,442,528 (−35.3%) | 13,008,592 (0) | 12,511,168 (−3.8%) |
| + `-no_exported_symbols` | −6.8% | −40.3% | −6.0% | −9.7% |
| + internalize | −17.9% | −48.3% | −15.1% | −19.7% |
| + prelink fix (`--build-system native` gives it today) | −20.7% | −49.3% | −17.9% | −22.3% |
| + `-deduplicate` | **8,512,256 (−26.0%)** | **5,444,640 (−52.7%)** | **9,965,696 (−23.4%)** | **9,450,944 (−27.3%)** |

- **The levers overlap.** Hello's four levers save 3.68 MB one at a time, but 2.99 MB stacked. Internalize alone cuts the export trie from 772 KB to 323 KB.
- **The README candidate** is strip + `-no_exported_symbols` + internalize, with no dedup: −17.9% for Hello and −15.1% for Stress. On today's 6.4 with SwiftBuild, dedup would add about 6 points more.
- **With 6.2.4** (native build): Hello −23.4% and Stress −20.5% with the full recipe.

### 6.2 Is a deduplicated binary correct?

**Sizes (measured).** `-deduplicate` works through `swift build` on both backends. It saves 936 KB of Stress on 6.4.0 (−7.2%) and 820 KB on 6.2.4, folding 23,190 functions on 6.4.0.

**What passed:**
- A release Stress on both toolchains passed `--selfcheck`, including with both memo verifiers armed.
- 22 sessions × 150 frames came out byte-identical to the normal binary.
- A 6.2.4 **debug** test build with dedup passed the golden snapshots and the full suite (10,929 tests). Dedup shrank that test bundle by 52 MB (−13%).

**What has not been run yet** (critic):
- a deduplicated binary in a PTY: the run loop, raw mode, input and signals;
- Hello or Example;
- any 6.4 or release-mode test run;
- a plain run of the suite at the same commit.

**One real semantic effect (established by a probe).** A computed property's key path is identified by its getter's address. So once identical getters are folded, two different key paths compare equal.
- On 6.4.0 this happens only with `-deduplicate`. On 6.2.4 it already happens without it, for getters in the same file.
- In Stress the folded pairs are aliases and constants, but on 6.2.4 they also include `EnvironmentValues.buttonStyle` and `installedButtonAppearance`. Those two share a getter but have different setters.
- TUI's three key-path comparisons are unaffected today: the memo's environment slots, the root palette lookup, and Table's same-column check.
- The one function-address comparison, `FatalSignalTerminalRestore.endsTheProcess`, is safe.

**Verdict:** safe for TUI as it stands, but a latent hazard for any future identity use of key paths. Before the README recommends dedup, it needs a PTY run and a runtime A/B.

### 6.3 Swift 6.4 with `--build-system native` (measured)

- **Size:** Hello 11,154,512 (−348,448, −3.03%) and Stress 12,609,504 (−399,088, −3.07%) against the SwiftBuild default. That is the prelink duplicates going away.
- **Nothing else differs** by more than 1.8 KB.
- **Correctness:** the native Stress passes `--selfcheck`.
- **Deprecation:** 6.4.0 prints a warning that the native build system "is deprecated and will be removed in a future release". So it is a stopgap, not a recommendation.

### 6.4 Can SwiftBuild be told to keep private externs? No (established)

- **Cause:** SwiftPM's build description sets `KEEP_PRIVATE_EXTERNS = NO` and `OTHER_LDRFLAGS = []` for every package target (`PackagePIFBuilder.addProjectBuildSettings`). That overrides the object-file product type's default of `YES`.
- **No workaround works.** None of these changes a single link:
  - `-Xxcbuild KEEP_PRIVATE_EXTERNS=YES`;
  - `XCODE_XCCONFIG_FILE`;
  - environment settings;
  - `-Xlinker`, which reaches only the final link;
  - clang's override hook.
- **The fix, emulated by adding the flag to SwiftBuild's own commands:**
  - Hello −350,192 (−3.04%) and Stress −400,032 (−3.08%);
  - SwiftBuild's `libTUI.a` grows by +5,687,984 B (+12.8%), all of it archive index.
- **It belongs to swift-package-manager, not swift-build.** A draft issue for the owner to file is in the working notes' SIZE3 folder, `fu/prelink/issue-draft.md`.

### 6.5 Does a `strip -N` binary work? Yes (measured)

- **Size:** −102 to −107 KB (−0.8 to −0.9%) on both toolchains. It stacks with `-no_exported_symbols`: Hello −7.66% and Stress −6.82% for the two together.
- **Checks:**
  - `codesign -v --strict` and `dyld_info -validate_only` pass;
  - 18 of 18 PTY launches drew, quit cleanly (with `q` and with ⌃\) and restored the terminal;
  - `--selfcheck` passes;
  - a dSYM still symbolicates crashes fully.
- **A trap for anyone re-checking:** on this machine, `atos` names functions in any binary whose UUID matches the unstripped one, even with no dSYM. Test symbolication on a copy with a fresh UUID.

### 6.6 Loose ends

**(a) LTO + conditional records + C9b.** The emulation's root set matches the compiler's IR. Two fixes make the old figure conservative:
- The ObjC class-list emulation had never taken effect.
- The figure is now taken from per-file objects, not the merged ones.

Result: Hello with C9b −61.9% (was −61.5%). With all modules the emulation is within 0.05% of the real LTO build.

**(b) Why 6.4 grows more per carve.** The cause is established, by emulation: the SwiftBuild prelink gives each new module its own copies of the hidden weak definitions it shares with other modules. For C2 that is +29.2 KB of sections, two 16 KB pages, which matches the measured gap against 6.2.4. So further carves cost 6.4 users about +16–33 KB each until SwiftPM keeps private externs.

**(c) The +33 KB that `-g` adds to a stripped app** is `__unwind_info` (+24.9 KB) and `__eh_frame` (+1.5 KB). It crosses two pages. With `-g`, LLVM emits unwind info for `nounwind` functions too (established).

### 6.7 Side finding: every TUI app traps at launch without its resource bundle (measured, cause established)

- **The crash:** without `TUI_TUIStrings.bundle` beside the binary, Hello traps on both toolchains with `Fatal error: unable to find bundle named TUI_TUIStrings`.
- **The path:** `LocalizationService.shared` → `loadTranslationsFromBundle` → `moduleResourceURL` → SwiftPM's generated `Bundle.module`, which calls `fatalError`. This happens during `RenderLoop.buildEnvironment()`.
- **It is a bug, not a size question.** Terminal apps are often shipped as a single binary (Homebrew, a release download).
- **The fix:** fall back to the untranslated (English) strings when the bundle is missing.
- **Effect on Q5:** moving the SF Symbols table into the bundle would add no new failure mode today, but it would once this bug is fixed.

### 6.8 What changes in the questions (§5)

- **Q1 (README size recipe):** strip + `-no_exported_symbols` + internalize gives −17.9% for Hello and −15.1% for Stress (emulated, checked against the real flag). `strip -N` is safe to add: about −0.9% more, measured. Dedup is held until the PTY run and the A/B.
- **Q2 (upstream issues):** the prelink issue belongs to swift-package-manager, not swift-build. Its draft is ready for the owner to file. The two compiler crashes still need reductions before they can be drafted.
- **Q5 (SF Symbols table):** it depends on whether a bundle-less app should run (§6.7). If it should, the table cannot move into the bundle.
- **Still open, and needing a quiet box:** runtime A/Bs of internalize, dedup and LTO on the split tree, and launch time.
