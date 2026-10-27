# Binary size

*Where the bytes of a TUI app go, the levers that shrink them, what ships from
the package and what an app developer must pass, running without the resource
bundle, and the probes committed for it. The study of 2026-10-10 and the
investigations and lanes that followed it.*

## In short

Dead stripping keeps nearly all of TUI: public symbols are marked
`[no dead strip]` and conformance records root the witness tables, so Hello
and a typical app differ by 16 KB. The large levers are flags an app developer
passes (a package used as a dependency cannot use `unsafeFlags`), so
`-internalize-at-link` ships from the package as a default-on trait, with the
README's "Shipping size" recipe and a `-deduplicate` check. A program copied
out of `.build` launches on macOS 14 and 15, and one without its resource
bundle runs in English. The owner's order of priority: run time, then bytes,
then compile time.

## For a future reader

- **SIZE-SMALL-LEVERS** (settled 2026-10-18: drop any package lever worth
  under about 1% of Hello, land the rest within the A/B tolerance), worked
  through 2026-10-27 against §3.2's figures. Hello under the per-module
  products (lever 5, shipped) is about 7.4 MB stripped, so 1% is about 74 KB.
  - **Lever 7, the SF Symbols names front-coded:** already shipped. The
    generated table is front-coded in blocks of 16 (`SFSymbolTable.generated.swift`).
  - **Levers 8, 11, 12, 13 and 14: dropped.** Each is estimated at 15 to
    30 KB of Hello, lever 8 at 15 KB once Hello links only its own modules.
  - **Lever 9, `@_alwaysEmitIntoClient` on the public modifier wrappers:**
    still a candidate, estimated at 110 to 150 KB. It changes inlining at
    every call site, so its bytes need re-measuring on the split tree and its
    runtime cost a quiet-box A/B before it lands. **Owed.**
- **BINARY-DISTRIBUTION** waits on two compiler bug reports on the Desktop.

## The study: where the bytes go in a release build (2026-10-10)

> **What this is.** The binary-size study of 2026-10-10, which the maintainers' working notes call SIZE3: where
> the bytes of TUI's built libraries and of a linked app go, measured at 247de05f9 on Swift 6.4.0 and Xcode's
> 6.2.4; the levers that would shrink them, priced; the questions it put to the owner (§5); and the follow-up
> measurements the owner asked for the same day (§6). How the artifacts were built, and the full byte inventory,
> are in [How the measurements were taken.md](<Binary size.md>), beside this file.
>
> **Historical; decided since.** This is the state of 2026-10-10. What landed or was decided after it:
>
> - **A program copied out of `.build` launches on macOS 14 and 15** (lane NODQ, aafa4a3cf): TUIApp reads stdin
>   into buffers of its own, and TUI no longer depends on swift-collections, so its three modules, counted in
>   the tables below, are no longer in a TUI app.
> - **A program without its resource bundle runs, in English** (e5445e2cd), so §6.7's trap is gone: see
>   [Running without the resource bundle (BNDL).md](<Binary size.md>).
> - **The SF Symbols names are front-coded** in blocks of 16 (lane SFQ, eef95ccc9), §2.5's first option, and the
>   font probe draws a constant codepoint, so a Mac without the font never reads the name table.
> - **`-internalize-at-link` ships from the package**, as the default-on trait `DeadStripUnusedAPI`, with the
>   README's "Shipping size" recipe and the `-deduplicate` check, `Tools/DedupCheck` (lane SHIP, 6122a8646): see
>   [Shipping size (SHIP).md](<Binary size.md>)
>   and the [README](../../../README.md#shipping-size).
> - **TUI's symbols stay out of the program's export table**, behind a second default-on trait,
>   `UnexportTUISymbols`, and ColorPicker's tone-curve and channel-curve editors are a module of their own,
>   TUICurveEditors (lane SHIP2, 4b1e00743): see
>   [Shipping size and products, second round (SHIP2).md](<Binary size.md>).
> - **Every module is a library product of its own** (C9b, lane C9B, 3df96c964), lever 5: see
>   [Per-module products (2026-10-11).md](<Per-module products.md>) and
>   [Library products for every module (C9B).md](<Per-module products.md>).
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

### 1. Summary

#### Where the bytes of the built libraries go (all modules, measured)

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

#### A linked, stripped app (measured)

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

#### The findings that matter most

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

### 2. The angles

#### 2.1 Composition and attribution

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

#### 2.2 Symbols and types

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

#### 2.3 Names and metadata

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

#### 2.4 Duplication

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

#### 2.5 Data, resources and build options

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

#### 2.6 API usage and app size

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

### 3. Levers

The owner's ranking is runtime > bytes > compile time. The tables below follow it:
- **App levers (§3.2).** Levers with no expected runtime cost come first, ordered by bytes saved per unit of effort. Levers that touch the per-frame path come after them, because the performance policy requires a quiet-box A/B before they can be recommended.
- **Library levers (§3.1).** They are listed separately, because they never reach an app.
- **Counting.** Each lever is counted once, even where several angles list it. Levers do not simply add; §3.3 has the measured combinations.

#### 3.1 On the built libraries, before linking

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

#### 3.2 On linked apps, ranked

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

#### 3.3 How the levers combine

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

#### 3.4 Not recommended

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

### 4. What we do not know yet

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

### 5. Questions for the owner

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

### 6. Follow-up measurements (2026-10-10, after the first review)

The owner asked for the cheap link-only measurements from §4. Six lanes ran them, and a critic cross-checked them. Raw notes are in the working notes' SIZE3 folder, under `fu/<lane>/notes.md`. The critic's corrections are applied below, and this section supersedes §1–§5 where they differ.

#### 6.1 The full recipe, stacked (6.4.0, stripped)

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

#### 6.2 Is a deduplicated binary correct?

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

#### 6.3 Swift 6.4 with `--build-system native` (measured)

- **Size:** Hello 11,154,512 (−348,448, −3.03%) and Stress 12,609,504 (−399,088, −3.07%) against the SwiftBuild default. That is the prelink duplicates going away.
- **Nothing else differs** by more than 1.8 KB.
- **Correctness:** the native Stress passes `--selfcheck`.
- **Deprecation:** 6.4.0 prints a warning that the native build system "is deprecated and will be removed in a future release". So it is a stopgap, not a recommendation.

#### 6.4 Can SwiftBuild be told to keep private externs? No (established)

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

#### 6.5 Does a `strip -N` binary work? Yes (measured)

- **Size:** −102 to −107 KB (−0.8 to −0.9%) on both toolchains. It stacks with `-no_exported_symbols`: Hello −7.66% and Stress −6.82% for the two together.
- **Checks:**
  - `codesign -v --strict` and `dyld_info -validate_only` pass;
  - 18 of 18 PTY launches drew, quit cleanly (with `q` and with ⌃\) and restored the terminal;
  - `--selfcheck` passes;
  - a dSYM still symbolicates crashes fully.
- **A trap for anyone re-checking:** on this machine, `atos` names functions in any binary whose UUID matches the unstripped one, even with no dSYM. Test symbolication on a copy with a fresh UUID.

#### 6.6 Loose ends

**(a) LTO + conditional records + C9b.** The emulation's root set matches the compiler's IR. Two fixes make the old figure conservative:
- The ObjC class-list emulation had never taken effect.
- The figure is now taken from per-file objects, not the merged ones.

Result: Hello with C9b −61.9% (was −61.5%). With all modules the emulation is within 0.05% of the real LTO build.

**(b) Why 6.4 grows more per carve.** The cause is established, by emulation: the SwiftBuild prelink gives each new module its own copies of the hidden weak definitions it shares with other modules. For C2 that is +29.2 KB of sections, two 16 KB pages, which matches the measured gap against 6.2.4. So further carves cost 6.4 users about +16–33 KB each until SwiftPM keeps private externs.

**(c) The +33 KB that `-g` adds to a stripped app** is `__unwind_info` (+24.9 KB) and `__eh_frame` (+1.5 KB). It crosses two pages. With `-g`, LLVM emits unwind info for `nounwind` functions too (established).

#### 6.7 Side finding: every TUI app traps at launch without its resource bundle (measured, cause established)

- **The crash:** without `TUI_TUIStrings.bundle` beside the binary, Hello traps on both toolchains with `Fatal error: unable to find bundle named TUI_TUIStrings`.
- **The path:** `LocalizationService.shared` → `loadTranslationsFromBundle` → `moduleResourceURL` → SwiftPM's generated `Bundle.module`, which calls `fatalError`. This happens during `RenderLoop.buildEnvironment()`.
- **It is a bug, not a size question.** Terminal apps are often shipped as a single binary (Homebrew, a release download).
- **The fix:** fall back to the untranslated (English) strings when the bundle is missing.
- **Effect on Q5:** moving the SF Symbols table into the bundle would add no new failure mode today, but it would once this bug is fixed.

#### 6.8 What changes in the questions (§5)

- **Q1 (README size recipe):** strip + `-no_exported_symbols` + internalize gives −17.9% for Hello and −15.1% for Stress (emulated, checked against the real flag). `strip -N` is safe to add: about −0.9% more, measured. Dedup is held until the PTY run and the A/B.
- **Q2 (upstream issues):** the prelink issue belongs to swift-package-manager, not swift-build. Its draft is ready for the owner to file. The two compiler crashes still need reductions before they can be drafted.
- **Q5 (SF Symbols table):** it depends on whether a bundle-less app should run (§6.7). If it should, the table cannot move into the bundle.
- **Still open, and needing a quiet box:** runtime A/Bs of internalize, dedup and LTO on the split tree, and launch time.

## The study: how the measurements were taken

> **What this is.** The method behind the binary-size study of 2026-10-10 (SIZE3): which toolchains built what, the
> exact commands, how every report was made, and the full byte inventory of the built libraries and four apps, at
> 247de05f9. The study's findings, levers and follow-ups are in
> [Where the bytes go in a release build.md](<Binary size.md>), beside this file, which
> also lists what was decided since.
>
> **Historical.** TUI has changed since: it no longer depends on swift-collections, every module is a library
> product, and two default-on traits change how an app links it, so a rebuild today gives other numbers.
>
> **Paths.** Relative paths here (`artifacts/…`, `tools/…`, `minapp/`, `linkcwd/`, `<tag>/…`) are in the
> maintainers' working notes, in the folder SIZE3, and `plan/slot.py` and `buildtime/minapp` are elsewhere in those
> notes; none of them is in this repository, and the worktree the builds ran in is gone. The commands in §2 are
> kept as they ran.

Prepared 2026-10-10 for an analysis of where the bytes of the BUILT TUI libraries go (objects, archives, a dylib),
with four linked apps beside them for the "linked vs unlinked" and API-usage angles. This directory holds artifacts and
per-file reports only; it draws no conclusions beyond the observations in §5. Every byte count here is **measured**
(a file size, or a field read from a Mach-O header) unless it says otherwise; causes are labelled **established** or
**hypothesis**.

- Source: TUI main **247de05f9**, built from the worktree `.claude/worktrees/wf_16d11454-ce5-1`, with ONE
  uncommitted edit during the builds: a product `.library(name: "TUIDynamic", type: .dynamic, targets:
  ["TUI"])` (`tools/worktree-edits.diff`; resolution also added a swift-syntax pin to `Package.resolved`). Both
  edits were reverted afterwards; nothing was committed.
- Machine: the 16 GiB arm64 VM, macOS 15 (Darwin 24.6.0), Xcode 26.3 (17C529), SDK MacOSX26.2, linker ld-1230.1
  (Xcode's; both toolchains linked with it: every binary's LC_BUILD_VERSION names LD 1230.1). Release, default settings, `-j 4`, every build through `plan/slot.py`
  under an RSS guard (`tools/guard.sh`, 7 GiB; the largest sampled `swift-frontend` RSS was 3,397,616 KB, in x624's TUI step).
- Apps: Hello (one `Text`) and Typical (List, Table, TextField, Toggle) from `minapp/` (a copy of
  `buildtime/minapp`, depending on the worktree by path, pinned to the same swift-collections 1.5.1); Example and Stress
  from the package itself.

### 1. Toolchains

| tag | compiler | build system (`swift build` default) | demangler used for the TSVs |
|---|---|---|---|
| `s640` | swift.org **6.4.0** release via swiftly (`Apple Swift version 6.4 (swift-6.4-RELEASE)`, `TOOLCHAINS=org.swift.640202609131a`), no assertions | **SwiftBuild** (the 6.4 default; output under `out/Products/Release`, `out/Intermediates.noindex`) | 6.4.0's `swift-demangle --compact` |
| `x624` | Xcode 26.3's **6.2.4** (`swiftlang-6.2.4.1.4 clang-1700.6.4.2`), slot.py's default | SwiftPM **native** (`.build/arm64-apple-macosx/release`) | Xcode's `swift-demangle --compact` |

So `s640` vs `x624` changes the compiler AND the build system at once. The compile flags they share: `-O
-whole-module-optimization -num-threads 12 -g -target arm64-apple-macos14.0 -swift-version 6 -package-name
wf_16d11454_ce5_1`. Only SwiftBuild adds `-DXcode -emit-const-values -enable-experimental-feature
DebugDescriptionMacro -explicit-module-build -save-temps -Xfrontend -serialize-debugging-options
-no-emit-module-separately-wmo -emit-objc-header`; only native adds `-Xcc -fPIC`. Full commands: `<tag>/logs/build-*.log`
(verbose). No `s640` build with `--build-system native` was made, so the two effects are not separated (§6).

### 2. Exact commands

```sh
N=/Users/robot/Documents/TUI-session-notes; Z=$N/SIZE3; WT=/Users/robot/Documents/TUI/.claude/worktrees/wf_16d11454-ce5-1
## builds (one slot each; tools/build.sh runs every step under tools/guard.sh with J=4 LIMIT_GB=7 and -v):
cd $WT
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run $Z/tools/build.sh s640 root   +6.4.0   # TUI, TUIAppKit, TUIDynamic, Example, Stress
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run $Z/tools/build.sh s640 minapp +6.4.0   # Hello, Typical
python3 $N/plan/slot.py $Z/tools/build.sh x624 root
python3 $N/plan/slot.py $Z/tools/build.sh x624 minapp
##   each step is: swift build -c release -j 4 --scratch-path $Z/scratch-<tag>-<root|minapp> -v --product <P> \
##                 [-Xlinker -map -Xlinker $Z/artifacts/<tag>/{lib/dylib,apps/<P>}/<P>.map]   (dylib and apps only)
## extraction (copies out of the scratch, then the reports; no slot: no compiling or linking):
python3 $Z/tools/extract.py <tag> lib            # objects, module files, archives (libtool -static), reports
python3 $Z/tools/extract.py <tag> apps-root      # Example, Stress  (strip -o <P>.stripped)
python3 $Z/tools/extract.py <tag> apps-minapp    # Hello, Typical
python3 $Z/tools/extract.py <tag> dylib          # libTUIDynamic.dylib (+ strip -S -x copy)
## per-module dylibs, linked from the copied objects (a slot each; run from $Z/linkcwd, see §6):
cd $Z/linkcwd
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run python3 $Z/tools/link_dylibs.py s640 +6.4.0
python3 $N/plan/slot.py python3 $Z/tools/link_dylibs.py x624
python3 $Z/tools/extract.py <tag> permodule
python3 $Z/tools/inventory.py s640 x624 > $Z/artifacts/inventory.md
```

Archives: `xcrun libtool -static -no_warning_for_no_symbols -o lib<M>.a <M's objects in the build's own order>`, and
`libTUI-all.a` from every module of the umbrella closure (all but TUIAppKit) in dependency order; libtool
reported no duplicate member names. Per-module dylibs (`lib/dylib/per-module/link-commands.txt` has each command):
`swiftc -Xlinker -reproducible -target arm64-apple-macos14.0 -emit-library -sdk <SDK> @<objects> -l<every module in
its declared dependency closure> -Xlinker -install_name -Xlinker @rpath/lib<M>.dylib -Xlinker -rpath -Xlinker
/usr/lib/swift -Xlinker -rpath -Xlinker @loader_path -Xlinker -dead_strip -link-objc-runtime -Xlinker -map …
-no-stdlib-rpath`, mirroring the build systems' own TUIDynamic link (no dsymutil). Stripping: apps `strip -o`
(full), dylibs `strip -S -x` (debug STABS and local symbols; exported symbols must stay).

Scratch directories (`scratch-<tag>-<root|minapp>`, 0.6–1.1 GB each) were deleted once extracted. Disk on
/System/Volumes/Data went from 17 GiB free to a low of 10 GiB (another lane's clean test build was running at the
time) and was 11 GiB at the end, with other lanes still building; `artifacts/` is about 1.5 GB.

### 3. Layout

```
artifacts/<tag>/
  logs/                 toolchain-*.txt, build-<step>.log (-v), build-<step>.err (/usr/bin/time -l + guard peak), steps-*.txt, df-*.txt
  lib/objects-inventory.tsv
  lib/<Module>/objects/*.o        per-file objects as the compiler wrote them (+ ORDER.txt, the build's link order)
  lib/<Module>/<Module>.o         s640 only: SwiftBuild's per-module `ld -r` object, what its products link
  lib/<Module>/modules/           .swiftmodule, .swiftdoc, .abi.json, .swiftsourceinfo (+ s640: -Swift.h, .swiftconstvalues)
  lib/<Module>/objects.*          reports over the per-file objects (below); merged.* = the same for <Module>.o
  lib/archives/lib<Module>.a, libTUI-all.a (+ .members.tsv), archive-overhead.tsv, and reports per archive
  lib/archives/swiftbuild/        s640 only: SwiftBuild's own libTUI.a (kept) and libTUIAppKit.a (members + sizes only)
  lib/dylib/libTUIDynamic.dylib(.stripped), TUIDynamic.map, .exports.txt (dyld_info -exports), reports, sizes.tsv
  lib/dylib/per-module/lib<Module>.dylib(.stripped), .map, .objects.resp, link-commands.txt, reports
  apps/<P>/<P>, <P>.stripped, <P>.map, objects/ (the app's own objects), sizes.tsv, reports (unstripped and stripped)
  inventory.tsv; root-vs-dependency-build.tsv (§5.4)
artifacts/inventory.md    the tables of §4
tools/                    every script used (macho.py is a dependency-free Mach-O/ar reader)
minapp/                   Hello + Typical package (its dependency path is the worktree, which may since be gone)
```

Reports, for every object set / archive / dylib / app (prefix `<x>`):
- `<x>.size-m-l.txt` (`size -m -l`), `<x>.otool-l.txt` (`otool -l`), `<x>.otool-r-lines.tsv` (`otool -r | wc -l` per
  file; this counts header lines too: 2 per relocated section + 1 per file).
- `<x>.symbols.tsv.gz`: `file member module object addr size section binding flags alias kind map_size mangled demangled`.
  `size` = distance to the next symbol address in the same section (or the section end); among symbols at one address
  the first (external, then private-external, then local; `ltmp*`/`l_*`/`L*` last) carries the size and the rest have
  `alias=1`, size 0, so sizes can be summed. `binding` ∈ local / external / weak (a weak definition) / undefined;
  `flags`: `pext` (private external, i.e. hidden), `was_pext`, `autohide`, `weak_ref`, `alt_entry`,
  `no_dead_strip`, `ordN` (dylib ordinal of an import). Undefined/abs/indirect symbols are listed with section
  `(undf)` etc. and size 0. STABS (the debug map) are not rows; they are counted in `summary`. `module`/`object`: for
  objects and archives from the path or the archive's member list; for dylibs and apps from the linker map (symbol
  address → input file → module); `map_size` is the map's own atom size. In s640 apps the map's inputs are the
  per-module `ld -r` objects, so `object` there is `<Module>.o`; join on `mangled` with `lib/<Module>/objects.symbols`
  for the source file. Every defined symbol of the four apps got a module from its map; rows with an empty `module`
  are imports.
- `<x>.sections.tsv`: every section with type, attributes, size, alignment, `nreloc` (exact), relocation bytes, defined
  symbol count, and `unattributed_lead` (bytes before the section's first symbol).
- `<x>.layout.tsv`: every byte of each file by category: header + load commands, each section's file bytes, each
  section's relocations, each LINKEDIT blob (symtab nlist, string table, LOH, chained fixups, export trie, function
  starts, code signature, …), and the remainder as padding.
- `<x>.summary.tsv`: per file: filetype, size, symbol counts by binding and STABS, `strsize` (the string table),
  symtab bytes, relocations, DWARF bytes, `__text` bytes.
- Linked images also get `<x>.map-live-by-module.tsv` (live and dead-stripped bytes per input module, from the map) and
  `<x>.map-dead.tsv` (every dead-stripped atom).

### 4. Inventory (all bytes measured)

Columns: `.o files`/`objects` = the per-file objects; `of which DWARF` = their `__DWARF` sections; `__text` = summed over
those objects; `merged .o` = s640's per-module `ld -r` object; `lib<M>.a` = libtool archive of the per-file objects;
per-module dylib = linked by `link_dylibs.py`; module files as copied. The bold row sums every module except
TUIAppKit (not in the umbrella). `dep` = CSTBImage (the C target) or swift-collections 1.5.1.

#### s640: library modules (bytes, measured)

| module | src | .o files | objects | of which DWARF | `__text` | merged `.o` | `lib<M>.a` | per-module dylib | stripped (-S -x) | .swiftmodule | .swiftdoc | .abi.json | .swiftsourceinfo |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| CSTBImage | dep | 1 | 339,592 | 226,396 | 54,876 | 112,908 | 341,216 | 120,368 | 103,384 |  |  |  |  |
| InternalCollectionsUtilities | dep | 19 | 333,536 | 178,898 | 17,880 | 153,512 | 368,704 | 151,736 | 104,832 | 251,736 | 18,460 | 149 | 60,392 |
| ContainersPreview | dep | 39 | 188,424 | 104,844 | 3,208 | 16,064 | 197,808 | 63,160 | 54,800 | 86,964 | 3,164 | 149 | 17,300 |
| DequeModule | dep | 45 | 1,083,568 | 613,518 | 96,296 | 419,624 | 1,141,640 | 344,312 | 226,208 | 945,288 | 181,680 | 149 | 215,848 |
| TUICore | TUI | 69 | 4,743,432 | 2,660,661 | 496,072 | 1,846,760 | 5,094,952 | 1,287,120 | 817,120 | 763,440 | 466,028 | 149 | 416,220 |
| TUIStyling | TUI | 39 | 3,120,344 | 1,807,141 | 319,096 | 1,237,184 | 3,353,368 | 833,368 | 527,680 | 467,496 | 188,072 | 149 | 208,752 |
| TUIView | TUI | 81 | 5,015,248 | 2,413,771 | 534,500 | 2,523,696 | 5,550,848 | 1,696,944 | 1,018,400 | 958,028 | 429,736 | 149 | 525,428 |
| TUIStrings | TUI | 27 | 2,426,720 | 975,366 | 201,980 | 1,242,975 | 2,621,688 | 900,152 | 636,912 | 409,120 | 59,772 | 149 | 96,876 |
| TUITerminalHost | TUI | 10 | 554,904 | 287,514 | 51,332 | 249,488 | 605,144 | 201,304 | 137,704 | 122,688 | 36,276 | 149 | 47,768 |
| TUIFoundation | TUI | 478 | 35,145,096 | 17,233,068 | 3,187,068 | 17,194,215 | 39,114,048 | 10,501,224 | 5,477,664 | 5,667,232 | 1,732,304 | 149 | 2,255,656 |
| TUIChrome | TUI | 29 | 1,705,360 | 843,937 | 174,600 | 768,608 | 1,864,056 | 562,968 | 348,400 | 215,500 | 47,852 | 149 | 60,136 |
| TUIApp | TUI | 60 | 2,875,736 | 1,497,977 | 250,356 | 1,131,160 | 3,096,832 | 785,232 | 465,960 | 329,740 | 38,548 | 149 | 53,680 |
| TUIImage | TUI | 21 | 1,851,296 | 1,122,987 | 177,020 | 681,552 | 1,980,824 | 504,280 | 322,048 | 230,636 | 87,408 | 149 | 72,088 |
| TUIBitmaps | TUI | 19 | 1,213,368 | 581,493 | 120,616 | 596,504 | 1,335,264 | 417,336 | 242,272 | 190,384 | 40,820 | 149 | 37,104 |
| TUINumericControls | TUI | 26 | 2,673,088 | 1,374,304 | 319,308 | 1,262,455 | 2,922,864 | 864,464 | 531,992 | 489,396 | 131,316 | 149 | 131,884 |
| TUIPickers | TUI | 18 | 1,690,536 | 743,139 | 207,008 | 939,680 | 1,867,056 | 651,848 | 398,160 | 319,176 | 65,536 | 149 | 70,012 |
| TUIPresentation | TUI | 26 | 1,800,312 | 750,485 | 200,824 | 1,100,664 | 2,035,184 | 712,424 | 382,936 | 333,016 | 113,296 | 149 | 100,048 |
| TUILists | TUI | 61 | 4,232,352 | 1,981,062 | 489,332 | 2,266,624 | 4,668,064 | 1,539,688 | 914,464 | 682,912 | 153,944 | 149 | 261,780 |
| TUITabs | TUI | 19 | 1,989,560 | 926,911 | 228,120 | 1,123,176 | 2,209,408 | 729,392 | 409,056 | 336,172 | 75,040 | 149 | 82,472 |
| TUITextInput | TUI | 36 | 2,869,400 | 1,560,216 | 274,496 | 1,077,912 | 3,084,920 | 745,720 | 448,752 | 352,984 | 80,140 | 149 | 80,592 |
| TUIColorPicker | TUI | 13 | 2,268,648 | 1,082,578 | 225,036 | 1,348,552 | 2,577,048 | 839,128 | 392,272 | 243,360 | 36,328 | 149 | 31,408 |
| TUIEffects | TUI | 14 | 1,107,816 | 473,592 | 121,388 | 711,552 | 1,254,984 | 475,912 | 259,792 | 233,396 | 83,096 | 149 | 73,128 |
| TUIForms | TUI | 9 | 848,720 | 376,715 | 88,504 | 534,128 | 967,000 | 364,840 | 199,152 | 176,908 | 48,488 | 149 | 47,932 |
| TUIGrid | TUI | 8 | 581,536 | 288,130 | 53,760 | 317,568 | 647,384 | 241,264 | 142,288 | 143,404 | 25,648 | 149 | 26,568 |
| TUIMenus | TUI | 7 | 483,768 | 194,213 | 44,780 | 345,192 | 558,264 | 260,504 | 154,288 | 142,740 | 31,068 | 149 | 35,916 |
| TUINavigation | TUI | 20 | 1,759,968 | 821,683 | 182,276 | 988,432 | 1,968,840 | 650,696 | 346,272 | 266,772 | 58,228 | 149 | 59,836 |
| TUISearch | TUI | 10 | 604,768 | 222,537 | 68,500 | 435,576 | 690,456 | 308,328 | 190,368 | 163,388 | 36,664 | 149 | 34,012 |
| TUITables | TUI | 30 | 3,364,680 | 1,619,146 | 430,924 | 1,809,344 | 3,678,760 | 1,241,944 | 759,264 | 546,860 | 170,344 | 149 | 174,124 |
| TUI | TUI | 1 | 9,552 | 5,758 | 0 | 4,168 | 10,248 | 34,800 | 33,752 | 41,628 | 372 | 149 | 644 |
| TUIAppKit | TUI | 4 | 162,776 | 74,621 | 14,820 | 80,176 | 177,152 | 100,808 | 79,504 | 72,528 | 9,900 | 149 | 8,916 |
| **umbrella closure (all but TUIAppKit)** | | 1235 | 86,881,328 | 42,968,040 | 8,619,156 | 42,439,273 | 95,806,872 | 28,030,456 | 16,046,192 | 15,110,364 | 4,439,628 | 4,172 | 5,277,604 |

#### s640: whole-library forms (bytes, measured)

| form | bytes |
|---|--:|
| `libTUI-all.a` (libtool -static, every per-file object of the umbrella closure) | 95,804,080 |
| `libTUI.a` made by SwiftBuild itself (the per-module `ld -r` objects) | 44,273,328 |
| `libTUIDynamic.dylib` (the umbrella as a `.dynamic` product, unstripped) | 25,618,376 |
| `libTUIDynamic.dylib` after `strip -S -x` | 13,616,080 |
| `libTUIDynamic.dylib.dSYM` (not kept) | 53,305,572 |

#### s640: apps (bytes, measured)

| app | unstripped | `strip` | dSYM (not kept) | link map | app's own objects | resource bundles beside it (not kept) |
|---|--:|--:|--:|--:|--:|--:|
| Hello | 25,538,248 | 11,502,960 | 53,332,502 | 13,870,341 | 17,256 | 41,913 |
| Typical | 25,571,208 | 11,519,568 | 53,389,740 | 13,885,706 | 85,440 | 41,913 |
| Example | 31,047,656 | 13,816,720 | 62,998,302 | 20,708,602 | 14,249,856 | 279,673 |
| Stress | 29,082,040 | 13,008,592 | 60,483,446 | 17,003,957 | 11,150,696 | 279,673 |

#### x624: library modules (bytes, measured)

| module | src | .o files | objects | of which DWARF | `__text` | merged `.o` | `lib<M>.a` | per-module dylib | stripped (-S -x) | .swiftmodule | .swiftdoc | .abi.json | .swiftsourceinfo |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| CSTBImage | dep | 1 | 486,632 | 324,010 | 99,972 |  | 488,264 | 169,040 | 152,984 |  |  |  |  |
| InternalCollectionsUtilities | dep | 19 | 325,744 | 174,094 | 19,084 |  | 360,488 | 154,120 | 105,600 | 249,036 | 18,480 | 149 | 60,412 |
| ContainersPreview | dep | 39 | 172,368 | 99,025 | 4,908 |  | 180,256 | 67,400 | 55,968 | 92,340 | 3,184 | 149 | 17,320 |
| DequeModule | dep | 45 | 937,160 | 504,873 | 92,332 |  | 993,800 | 328,840 | 210,560 | 962,896 | 181,700 | 149 | 215,868 |
| TUICore | TUI | 69 | 5,300,984 | 3,077,913 | 566,884 |  | 5,641,760 | 1,385,456 | 900,128 | 753,576 | 466,048 | 149 | 416,240 |
| TUIStyling | TUI | 39 | 3,301,568 | 1,937,559 | 340,576 |  | 3,531,576 | 867,368 | 546,240 | 459,724 | 188,092 | 149 | 208,772 |
| TUIView | TUI | 81 | 5,166,512 | 2,571,554 | 560,388 |  | 5,690,928 | 1,737,616 | 1,034,672 | 941,544 | 429,756 | 149 | 525,448 |
| TUIStrings | TUI | 27 | 2,533,248 | 1,076,101 | 213,512 |  | 2,721,832 | 928,168 | 653,056 | 399,080 | 59,792 | 149 | 96,876 |
| TUITerminalHost | TUI | 10 | 612,504 | 326,160 | 57,208 |  | 660,512 | 223,256 | 154,456 | 109,688 | 36,296 | 149 | 47,788 |
| TUIFoundation | TUI | 478 | 36,468,872 | 18,490,741 | 3,361,464 |  | 40,366,296 | 10,836,712 | 5,662,592 | 5,672,436 | 1,732,324 | 149 | 2,255,676 |
| TUIChrome | TUI | 29 | 1,747,344 | 909,366 | 180,884 |  | 1,899,672 | 569,848 | 347,792 | 196,104 | 47,872 | 149 | 60,156 |
| TUIApp | TUI | 60 | 2,920,680 | 1,620,731 | 261,368 |  | 3,121,752 | 807,440 | 483,528 | 308,660 | 38,568 | 149 | 53,700 |
| TUIImage | TUI | 21 | 2,107,128 | 1,331,530 | 185,204 |  | 2,236,232 | 512,488 | 322,736 | 213,896 | 87,428 | 149 | 72,108 |
| TUIBitmaps | TUI | 19 | 1,265,016 | 634,953 | 124,856 |  | 1,383,064 | 425,704 | 242,656 | 173,516 | 40,840 | 149 | 37,124 |
| TUINumericControls | TUI | 26 | 2,730,608 | 1,390,355 | 330,608 |  | 2,978,312 | 871,968 | 531,816 | 474,008 | 131,336 | 149 | 131,904 |
| TUIPickers | TUI | 18 | 1,761,808 | 784,994 | 224,820 |  | 1,938,880 | 677,192 | 413,840 | 301,724 | 65,556 | 149 | 70,032 |
| TUIPresentation | TUI | 26 | 1,834,664 | 792,074 | 212,416 |  | 2,063,056 | 718,696 | 382,888 | 318,164 | 113,316 | 149 | 100,068 |
| TUILists | TUI | 61 | 4,310,936 | 2,068,207 | 512,836 |  | 4,736,344 | 1,578,984 | 930,704 | 654,248 | 153,964 | 149 | 261,800 |
| TUITabs | TUI | 19 | 2,192,888 | 1,066,022 | 243,496 |  | 2,421,136 | 756,944 | 425,584 | 313,412 | 75,060 | 149 | 82,492 |
| TUITextInput | TUI | 36 | 2,792,736 | 1,548,622 | 265,720 |  | 2,998,832 | 734,264 | 432,176 | 338,292 | 80,160 | 149 | 80,612 |
| TUIColorPicker | TUI | 13 | 2,337,024 | 1,146,768 | 224,724 |  | 2,650,392 | 826,280 | 375,424 | 221,800 | 36,348 | 149 | 31,428 |
| TUIEffects | TUI | 14 | 1,113,592 | 486,764 | 127,160 |  | 1,256,168 | 492,872 | 276,608 | 213,160 | 83,116 | 149 | 73,148 |
| TUIForms | TUI | 9 | 758,240 | 318,511 | 85,212 |  | 878,408 | 370,152 | 199,152 | 158,212 | 48,508 | 149 | 47,952 |
| TUIGrid | TUI | 8 | 606,136 | 309,877 | 56,696 |  | 672,968 | 263,344 | 159,072 | 125,668 | 25,668 | 149 | 26,588 |
| TUIMenus | TUI | 7 | 484,304 | 193,399 | 47,680 |  | 560,000 | 264,216 | 153,920 | 125,192 | 31,088 | 149 | 35,936 |
| TUINavigation | TUI | 20 | 1,852,768 | 892,340 | 192,788 |  | 2,062,064 | 680,888 | 361,968 | 246,632 | 58,248 | 149 | 59,856 |
| TUISearch | TUI | 10 | 589,680 | 220,894 | 70,544 |  | 672,736 | 308,184 | 189,696 | 141,808 | 36,684 | 149 | 34,032 |
| TUITables | TUI | 30 | 3,517,984 | 1,724,574 | 451,352 |  | 3,830,688 | 1,265,816 | 776,160 | 527,532 | 170,364 | 149 | 174,144 |
| TUI | TUI | 1 | 9,120 | 5,319 | 0 |  | 9,816 | 34,800 | 33,752 | 18,312 | 392 | 149 | 664 |
| TUIAppKit | TUI | 4 | 167,304 | 85,782 | 16,132 |  | 180,104 | 101,272 | 79,664 | 43,072 | 9,920 | 149 | 8,936 |
| **umbrella closure (all but TUIAppKit)** | | 1235 | 90,238,248 | 46,027,330 | 9,114,692 |  | 99,006,232 | 28,858,056 | 16,515,728 | 14,710,660 | 4,440,188 | 4,172 | 5,278,144 |

#### x624: whole-library forms (bytes, measured)

| form | bytes |
|---|--:|
| `libTUI-all.a` (libtool -static, every per-file object of the umbrella closure) | 99,003,448 |
| `libTUIDynamic.dylib` (the umbrella as a `.dynamic` product, unstripped) | 25,524,408 |
| `libTUIDynamic.dylib` after `strip -S -x` | 13,768,144 |
| `libTUIDynamic.dylib.dSYM` (not kept) | 53,447,347 |

#### x624: apps (bytes, measured)

| app | unstripped | `strip` | dSYM (not kept) | link map | app's own objects | resource bundles beside it (not kept) |
|---|--:|--:|--:|--:|--:|--:|
| Hello | 25,411,432 | 11,621,760 | 53,373,998 | 15,518,116 | 16,800 | 40,769 |
| Typical | 25,427,352 | 11,621,824 | 53,414,836 | 15,535,898 | 83,472 | 40,769 |
| Example | 31,189,656 | 13,884,848 | 62,366,526 | 22,710,426 | 14,572,976 | 277,397 |
| Stress | 28,984,456 | 13,126,496 | 59,939,623 | 18,418,975 | 11,654,320 | 277,397 |


### 5. Observations made while preparing the artifacts

Facts read from the files (measured, cause established unless marked):

1. **Objects: one per source file, on both toolchains.** Release compiles each module whole-module with
   `-num-threads 12`, which writes one object per source file: 1,235 objects for the umbrella closure (TUI's 1,131
   plus 104 from CSTBImage and swift-collections). **SwiftBuild (s640) then `clang -r`s each module's objects into one
   `Products/Release/<M>.o`, and every product it links (its own `libTUI.a`, the dylib, the apps) takes those**
   (`Link <M>.o` steps and the `LinkFileList`s in `s640/logs/build-TUI.log`). Native SwiftPM (x624) links the
   per-file objects directly and makes no archive for an automatic library product.
2. **Debug info.** Every per-file object carries DWARF: 42,968,040 of 86,881,328 B (49.5%) on s640 and 46,027,330 of
   90,238,248 B (51.0%) on x624. SwiftBuild's per-module `ld -r` objects carry no `__DWARF` at all: they have a STABS
   debug map instead (312,249 STABS entries across the closure, among them one `N_OSO` per per-file object and one
   `N_AST` naming the `.swiftmodule`), and their string tables are larger (17,522,712 B against 13,291,424 B for the
   per-file objects; the debug map's names and object paths, inferred). So SwiftBuild's `libTUI.a` (44,273,328 B) can be symbolicated only while the intermediate objects
   exist (inferred from how a debug map works; not tested).
3. **What `ld -r` removes besides DWARF (s640).** Per-file objects less their DWARF: 43,913,288 B; the merged objects:
   42,439,273 B (−1,474,015). `__text`: 8,619,156 → 8,339,516 B (−279,640, −3.2%). Hypothesis: `ld -r` coalesces the
   weak definitions that several files of one module each emit, and merges literal sections. The same hypothesis would
   explain why x624's Hello map lists 296,673 dead-stripped bytes for TUIFoundation against s640's 26,433: in
   x624 those duplicates first reach the final link.
4. **Root and dependency builds are the same code.** The library objects of the worktree build (root package) and of
   the minapp build (TUI as a path dependency) match section for section, outside debug info:
   - s640: 28 of 29 merged module objects have byte-identical sections; TUI.o differs only in
     `__LLVM,__swift_modhash`; file sizes differ by 0–952 B, all of it string table (the longer scratch path in the
     debug map).
   - x624: 1,234 of 1,235 per-file objects are identical outside `__DWARF` and `__swift_modhash`; the exception is
     TUIStrings' `resource_bundle_accessor.swift.o`, whose `__cstring` holds the bundle's build path.
   So `lib/` stands for what a consumer's build compiles (`<tag>/root-vs-dependency-build.tsv`).
5. **Module files.** No `.swiftinterface` and a 149-byte `.abi.json` stub per module: library evolution is off (no
   `-enable-library-evolution` in any command). `.swiftmodule` totals 15,110,364 B (s640) and 14,710,660 B (x624);
   `.swiftsourceinfo` about 5.28 MB and `.swiftdoc` about 4.44 MB on both.
6. **Archives.** The `__.SYMDEF` table is 8,816,112 B of `libTUI-all.a`'s 95,804,080 B (s640); per archive in
   `lib/archives/archive-overhead.tsv`.
7. **Dylibs.** The umbrella dylib exports 24,743 symbols on both toolchains (`dyld_info -exports`). The 29 per-module
   dylibs of the umbrella closure together are larger than the single one: s640 28,030,456 against 25,618,376 B unstripped, 16,046,192 against
   13,616,080 B after `strip -S -x` (umbrella closure only).
8. **Apps.** Typical's stripped binary is 64 B larger than Hello's on x624 and 16,608 B larger on s640. s640's stripped
   Hello is 118,800 B (1.0%) smaller than x624's. Whether the compiler or the build system's flags cause the
   s640/x624 differences (here and in `__text`: 8,619,156 against 9,114,692 B over the per-file objects) is not
   established (§6).
9. **Build behaviour seen on the way (not a benchmark: busy box, wall times from the logs).** On x624 (native),
   `swift build -c release --product TUI` also compiled and linked the package's executables (Example, Stress,
   TerminalClientQuirks, the tools) and the macro plugin with swift-syntax's host (`-tool`) modules, in 154.9 s; the later `--product Example` and
   `Stress` steps only relinked. On s640 (SwiftBuild) the same command built only the product's closure (68.4 s), and
   the Example and Stress steps then compiled those modules (34.0 s and 16.5 s). For comparison, the minapp's Hello
   step, which compiles TUI as a dependency, took 81.9 s on s640 and 74.1 s on x624. Cause of the native
   behaviour not investigated.

### 6. What failed, and what was not done

- **Failed and fixed during the run:** the first object copy and the first per-module dylib link both broke on
  swift-collections object names that contain spaces (`Integer rank.o`, `BorrowingSequence+Standard
  Conformances.o`). `common.py` now reads `-filelist` lists by line and `link_dylibs.py` quotes response-file paths;
  everything was rerun from the start of each step. Nothing is missing.
- **A build-script edit hazard, avoided:** `tools/build.sh` was edited while the x624 minapp build was executing it;
  the original bytes were written back before bash read past the running step, and the variant was saved as
  `tools/build-extra.sh` (adds `SIZE3_EXTRA` flags). The minapp logs show both steps ran normally.
- **Slot use:** the per-module dylib links (seconds each, no compiling) ran from `SIZE3/linkcwd`, whose stub
  `.build/arm64-apple-macosx/debug` makes `slot.py` count them as incremental rather than wait for the clean-build
  lock another lane held. They still took a build slot.
- **Not done:** an s640 build with `--build-system native` (it would separate compiler from build system for every
  s640/x624 difference above; skipped because disk was at the 10 GiB line during the other lane's build); TUIMacros
  (needs swift-syntax; not part of the umbrella); dSYMs were measured, not kept; the apps' resource bundles were
  measured, not kept; nothing was run (no runtime measurements).
- No message from the owner arrived during this task.

## Where the bytes of a TUI app go (2026-10-10)

> **Status:** decided, and the levers TUI controls have landed (2026-10-10 to 2026-10-12). **Decided by:** the
> owner. **The long-form report** is committed: [Where the bytes go in a release build](<Binary size.md>)
> and [How the measurements were taken](<Binary size.md>).
> **Working notes** (not in git): `SIZE2/research.md` (2026-10-08) and `SIZE3/` (2026-10-10): its answers to the
> review `SIZE3/answers.md` and its follow-up questions `SIZE3/q/`.

### Question

What makes a release binary that uses TUI large, and what can shrink it? SIZE2 asked it from the flags'
side (2026-10-08). The owner then asked for a byte analysis of the built libraries from many angles, and how API
usage affects an app's size (2026-10-10), and, reading the first answer: "11.5 MiB for hello world is horrifying".

### Answer

- **`swift build -c release` does not strip.** A one-`Text` hello world is 25,538,248 B as built and
  11,502,960 B after `strip` (6.4.0). The 14 MB between them is the debug map and the symbol tables.
- **Every app carried all of TUI.** Hello kept 98.9% of the library bytes it linked, and each of 17 apps that
  added one API family to it was exactly one 16 KB page larger. Every public symbol and every conformance record is
  a root for the linker's dead stripping, so using less API saved nothing.
- **So the levers that matter cut the roots or what is linked:** per-module products, `-internalize-at-link`,
  keeping TUI's symbols out of the export table, and a few package changes. `strip` and `-deduplicate` are the
  app's own choices, and the rest needs an upstream change or a redesign.
- **Debug information is most of the built libraries (54.6% of the objects) and none of an app.** The owner ruled
  that only final-app bytes matter; TUI keeps building with `-g`.

### Key measurements

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
| on `TUIApp` alone against the `TUI` umbrella, with the internalize trait | 5,964,832 against 9,552,376 (−37.6%) | measured, 2026-10-11 |
| `UnexportTUISymbols` trait: the export table 317 KB → 9 KB | −3.2% | measured, 2026-10-12 |
| `-Xlinker -deduplicate`, both traits on | −7.5% | measured, 2026-10-12 |

The built libraries for 6.4.0: 86.9 MB of per-file objects, of which DWARF and its relocations are 47.4 MB, symbol
names and records 17.3 MB, and code (`__text`) 8.6 MB (measured). In a stripped Hello, code is 72% and Swift
runtime metadata 5.3%.

### Reasoning

- **Roots, not usage.** IRGen marks every public symbol "used" unless `-internalize-at-link` is given, and the
  runtime finds conformance records by scanning their section, so the compiler keeps each one, and a kept record
  keeps its witness table and its code. Hence Hello keeping `Table`'s renderer. Products cut what is linked;
  internalize cuts the public-symbol roots; the records need full LTO with conditional records, which the compiler
  does not yet make complete (see the open
  [LTO page](<../../Investigations/Full LTO, conditional runtime records and the reflection descriptor request.md>)).
- **Who may set a flag.** A link flag in TUI's manifest lands on the developer's whole program, so TUI sets
  only compile flags of its own and an unexport list limited to its own modules, each behind a trait
  ([who the flags reach](<Binary size.md>)).
- **Ruled out:** `-Osize` (−8.3% of Hello, but +4.5% to +20.5% CPU per frame in a pre-split A/B); disabling
  reflection metadata (`@State` and `@Environment` silently stop binding); shorter module or identifier names
  (0.15% and 0.24% of Hello, estimated); library evolution (it crashes both compilers on TUICore); ThinLTO or
  full LTO alone (larger, not smaller). Single-module emission, the machine outliner and mergeable traps are in
  [Future options](<../../Future options.md#build-and-binary-size>).
- **6.4 against 6.2.4.** 6.4.0's compiler emits 4.0% less of Hello than 6.2.4, but Swift Build's per-module
  prelink hides weak definitions, which leaves 350 KB of duplicate code per 6.4 app; SwiftPM sets
  `KEEP_PRIVATE_EXTERNS = NO` for every package target, and no setting reaches it. An issue for
  swift-package-manager is drafted for the owner to file (`SIZE3/q/swiftpm-issue-keep-private-externs.md`).
- **A side finding** became a bug fix: every TUI app stopped at launch without its resource bundle (decisions
  [BNDL](<Binary size.md>)).

### What was decided

The owner, 2026-10-10 to 2026-10-12: only final-app bytes matter; land swift-collections' removal
([its own page](<Binary size.md>)),
front-coded SF Symbol names, the README's opt-in size recipe with CI checks of what it recommends, internalize as a
default trait, per-module products ("C9b: do it"), the unexport list, and the curve editors in a module of their
own. Declined: `-non_global_symbols_strip_list` ("we need to support debugging properly"). Deferred: single-module
emission and pay-for-use services.

### Links

- README, [Shipping size](../../../README.md#shipping-size) and
  [Depending on fewer modules](../../../README.md#depending-on-fewer-modules): what an app developer can do.
- Commits: `a3218056d` (internalize trait), `d159ab542` (unexport trait), `17a63a3a7` (products), `f8ec22f19`
  (SF Symbol names, described in [Baking a large static lookup table](<../../Swift language/Baking a large static lookup table in Swift.md#front-coding-the-names-2026-10-11>)),
  `02863940b` (swift-collections out), `7612c03a4` (README's recipe), `97d8cf928` and `af87dc403` (editor modules).
- Decisions: [SHIP](<Binary size.md>),
  [SHIP2](<Binary size.md>),
  [C9B](<Per-module products.md>).
- Long form: [Per-module products](<Per-module products.md>); the earlier
  [compile time and binary size analysis](<Compile time and the test targets.md>).
- Sibling pages: [`-internalize-at-link`](<Binary size.md>),
  [`-deduplicate`](<Binary size.md>),
  [SwiftUI's size](<Binary size.md>).

## SwiftUI's size beside TUI's (2026-10-10)

> **Status:** answered, for context; no decision rested on it. **Asked by:** the owner, 2026-10-10. **Working
> notes** (not in git): `SIZE3/q/swiftui/notes.md`, with the hello-world sources and build script beside it.

### Question

The owner, during the size review: "how does SwiftUI compare, in binary size? Make it as apples-to-apples as you can
(SwiftUI is several frameworks)."

### Answer

- **Per app, the comparison is meaningless:** a stripped SwiftUI hello world is 53,048 B, almost all of it 16 KB
  page padding, because SwiftUI lives in the OS's shared cache; a stripped TUI hello world was 11,502,960 B (217
  times as large), because TUI is linked into each app.
- **Framework for framework, SwiftUI is about 3.75 times TUI's size**: 39.0 MB of code and data for SwiftUI,
  SwiftUICore and AttributeGraph, against 10.4 MB for TUI's umbrella built as one dynamic library.
- **Per type they are equally dense**: about 4,600 against 4,500 bytes per nominal type (within 3%), and within 9% per
  conformance. SwiftUI is larger because it has about 3.6 times as many types and 4.1 times as many conformances.
- **And SwiftUI leans on the rest of the OS**, uncounted here: AppKit's controls (it imports 162 `NS*` classes),
  Core Animation, Core Text, ImageIO and more. TUI builds its own renderer, terminal I/O, image conversion and SF
  Symbols table into the app.

### Key measurements

macOS 15.8.1 (24H32) arm64 VM with Xcode 26.3 (SDK 26.2): so SwiftUI is the macOS 15 generation's; macOS 26's was not
measured. Every figure is the file bytes of `__TEXT` and `__DATA*`, on both sides: `__LINKEDIT` is merged across
the shared cache, so no per-image figure exists for it. SwiftUI's images were sized with `dyld_info -segments`, and
which images are SwiftUI's own was read from the reverse-dependency graph of all 3,255 readable cache images.
TUI's figures are SIZE3's 6.4.0 build at main 247de05f9.

| | SwiftUI-specific | TUI (umbrella dylib, 6.4.0) | ratio |
|---|--:|--:|--:|
| code and data | 39,013,347 | 10,410,692 | 3.75× |
| code | 32,707,284 | 8,337,624 | 3.92× |
| Swift runtime metadata | 1,929,044 | 606,615 | 3.18× |
| nominal types | 8,420 | 2,320 | 3.63× |
| conformances | 15,406 | 3,739 | 4.12× |
| bytes per type (estimate) | 4,633 | 4,487 | 1.03× |

The SwiftUI hello world (`WindowGroup` with `Text("Hello")`, `swiftc -O`, macOS 14.0 target, Xcode's 6.2.4) is
53,048 B stripped, of which 1,798 B are sections; an AppKit one is 51,352 B.

### What makes it unequal

- **Build settings:** SwiftUI is built with library evolution for arm64e (the SDK's interfaces say so; inferred for
  the binaries measured), TUI without it for arm64. Pointer authentication adds instructions; library evolution
  adds resilience code but moves inlinable code into clients. The net effect is unknown, and TUI cannot be
  measured with library evolution because the compiler crashes on TUICore.
- **Where the line falls:** TUIFoundation holds `Button`, `ScrollView`, `Label` and others that SwiftUI keeps in
  `SwiftUI` rather than `SwiftUICore`, so a per-group comparison (engine against engine: 1.96×; controls against
  controls: 6.81×) is skewed.
- **Cost model:** SwiftUI's 39–40 MB is paid once by the OS and shared by every process; a TUI app pays its share
  of TUI on disk per app. That is why
  [shrinking what each app links](<Binary size.md>) matters for TUI.

No other Swift terminal-UI framework was available locally to compare, and nothing was downloaded.

## A program copied out of its build stopped at launch: libswiftCompatibilitySpan (2026-10-11)

> **Status:** fixed and landed, 2026-10-11 (`02863940b` to `aafa4a3cf`), with a CI check; two upstream reports are
> drafted for the owner to file. **Decided by:** the owner, 2026-10-11, who approved landing the replacement "for
> now". **Working notes** (not in git): `SIZE3/q/span/` (the cause), `SIZE3/q/spanq/` (the whole chain, the
> upstream drafts, and the downsides of swift-collections' fix), `NODQ/` (the replacement's gates).

### Question

A release hello world built with swift.org's Swift 6.4.0 and copied out of `.build` stopped before `main` on
macOS 15.8.1: `dyld: Library not loaded: @rpath/libswiftCompatibilitySpan.dylib` (2026-10-10). Xcode's 6.2.4 build
of the same code ran. Why, is TUI's own use of `Span` to blame, and what should TUI do? The owner then asked
for "the exact nature of the problem", and whether swift-collections' fix would have downsides.

### Answer

- **Not TUI's Span code.** No TUI object referred to any of the 33 symbols the library serves. The one import
  was `OutputSpan`'s metadata accessor, `$ss10OutputSpanVMa`, from swift-collections' unspecialised generic
  `RigidDeque`/`UniqueDeque` code, which TUI never called. Swift keeps every public symbol, so linking
  DequeModule linked the reference.
- **Not a compiler bug either: two intended changes collided.** swift-collections 1.4 built Deque on code that fills
  an `OutputSpan`, and SwiftPM 6.4 compiles a package for macOS 12 instead of 10.13. At 12 the import is strong
  (`OutputSpan` is declared from 10.14.4); at 10.13 it was weak, which is why the 6.2.4 build ran. macOS has the
  library from 26 only, and SwiftPM ships nothing beside an executable.
- **Weak is not a fix.** A weakly linked symbol is NULL below macOS 26: a one-line program calling into it died
  at `pc 0x0`. It is safe only where the code needing it provably never runs there.
- **TUI dropped swift-collections.** TUIApp, its only user, keeps stdin bytes in a buffer of its own
  (`InputByteBuffer`) and decoded events in `InputQueue`, about 300 lines that touch no Span type. That also saves
  about 165 KB per app.

### Key measurements

macOS 15.8.1 arm64 VM, Xcode 26.3 (SDK 26.2, ld-1230.1); swift.org 6.4.0 with Swift Build, and Xcode's 6.2.4 with
the native build system; swift-collections 1.5.1; main at 2c75a8c21. "Copied out" means the toolchain rpaths
deleted and nothing placed beside the binary.

| case | result |
|---|---|
| Hello, 6.4.0, copied out | stops at launch, exit 134 |
| Hello, Stress and Example, Xcode's 6.2.4, copied out | full PTY sessions pass (import weak) |
| DequeModule's 108 KB in a linked app | 100 B dead-stripped |
| swift-collections' cost in Hello | about 165 KB, of which TUI used 5.4 KB |
| TUI's own Span patterns that link the library strongly | none on main (three patterns found, below) |

The patterns that make a strong link, measured on both toolchains: requesting a Span type's metadata
(`Span<T>.self`, or as an argument to unspecialised generic code); mutating a `MutableSpan` or `OutputSpan` in a
public generic function that is not `@_alwaysEmitIntoClient`; a public type storing a Span. `@available(macOS 26, *)`
prevents none of them, and a debug build links the library more often than a release build of the same code.

### Reasoning

Options were priced against "every TUI app deployable with no action by its author":

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
then the choice is about 300 lines of TUI's own against about 165 KB per app.

### What landed

- `02863940b`: TUIApp's own buffers; swift-collections out of `Package.swift`.
- `914137ed6`, `c69521c23`, `aafa4a3cf`: `Tools/check-span-compatibility.sh`, run by CI on a release build. It fails
  on any load of the library, strong or weak, and on any symbol imported from it, in the executables and in every
  library module's objects. The owner asked for a unit test if cheap; it stays in CI because a debug build links the
  library where release does not (decisions
  [C-SHIP-1](#c-ship-1-the-libswiftcompatibilityspan-check-stays-in-ci-not-in-the-unit-tests)).
- `de9e3d06d`: README, [Shipping a program](../../../README.md#shipping-a-program), says what an app that uses
  Span types or swift-collections 1.4+ itself must ship or weak-link.

### Still open

Two drafts for the owner to file: to swift-collections, the change above (`SIZE3/q/spanq/swift-collections-issue.md`);
to swift-package-manager, that `swift build` makes a macOS 14 executable that cannot start there without warning,
and that under Swift Build an executable gets the `@loader_path` rpath only through a library target it depends on
(`SIZE3/q/spanq/swift-package-manager-issue.md`). The compiler team already calls the 6.4 combination a regression
and shipped an opt-in flag for it (swiftlang/swift#91294).

Part of [where the bytes of a TUI app go](<Binary size.md>).

## Dead-stripping TUI's unused API from the package: `-internalize-at-link` (2026-10-11)

> **Status:** landed, 2026-10-11 (`a3218056d`): the default-on package trait `DeadStripUnusedAPI`. **Decided by:**
> the owner, 2026-10-11 (internalize through a default-on trait: yes). **Working notes** (not in git):
> `SIZE3/q/internalize-pkg/notes.md` (acceptance, plugins, dynamic linking), `SHIP/measure.sh` (the landing
> measurement), `SYMS/notes.md` §2.1 (debugging).

### Question

Swift marks every public symbol "no dead strip", so a statically linked app kept all of TUI's public API whether
it called it or not. `-Xfrontend -internalize-at-link` removes that mark, and an app could pass it, but few would.
Can TUI set it on its own modules from its manifest, so that every app gets the saving with no action, and what
does it break? SwiftPM used to refuse `unsafeFlags` in a dependency resolved by version; whether it still did was
the first thing to find out.

### Answer

- **Yes.** SwiftPM 6.2 lifted the rule (swift-package-manager #8896, in 6.2 as #8914). Every consumer tried accepts
  the flag from a versioned dependency, with no diagnostic, and it reaches only TUI's own compile lines.
- **It saves about 15%** of a stripped hello world and 12% of Stress, the 95% of the every-module saving that TUI's
  modules account for.
- **It breaks one kind of app:** a statically linked app whose `dlopen`ed plugin calls TUI API that the app
  itself never calls. That plugin no longer loads ("symbol not found in flat namespace"). Such an app turns the
  trait off with `traits: []`. A dynamically linked TUI is unaffected.
- **Debugging loses only what was dropped:** lldb's `expr` and breakpoints by name cannot reach public API the
  app never calls, as they already could not reach unused internal functions.

### Key measurements

On the development machine (arm64 macOS 15.8.1 VM). A test library with three tags (no flag; the flag; the flag
behind a default trait) was consumed by version over a `file://` URL:

| consumer | accepted | flag on the library's compile lines | `traits: []` turns it off |
|---|---|---|---|
| SwiftPM 6.2.4 (Xcode 26.3), native and Swift Build | yes | yes | yes |
| SwiftPM 6.3.3, native and Swift Build | yes | yes | yes |
| SwiftPM 6.4.0, Swift Build and native | yes | yes | yes |
| `xcodebuild` 26.3: a root package, and a project with a remote versioned reference | yes | yes | — |

GitHub https remotes and the Xcode GUI were not tried. The landing measurement (`a3218056d`), trait off then on,
stripped, release:

| | Swift 6.4.0 | Xcode's 6.2.4 |
|---|--:|--:|
| Hello | 11,374,080 → 9,700,016 (−14.7%) | 11,476,208 → 9,764,816 (−14.9%) |
| Stress | 12,863,200 → 11,305,104 (−12.1%) | 12,997,296 → 11,402,672 (−12.3%) |
| Hello, unstripped | 25,212,792 → 20,940,200 (−16.9%) | 25,071,080 → 20,742,536 (−17.3%) |

Checks at landing: Stress `--selfcheck` passed and a stripped Hello drew in a PTY, on both toolchains; the Span
check passed. The plugin case was measured on a small library: without the flag the host exported 20 unused symbols
and the plugin loaded; with it, 10, and `dlopen` failed. A dynamic library of the same modules exported the same
24,778 symbols either way. Run time: a quiet-box A/B on the split tree before this work found the flag neutral (warm
−0.3 to −0.9%, cold −1.7 to +1.3%, launch −2.6%); the A/B of the landed trait is owed.

### Reasoning

- **A trait, on by default.** No frontend flag negates `-internalize-at-link`, so a trait is a client's only way
  out. The name says what the trait lets the app's linker do, in the words of `-dead_strip` and Xcode's "Dead Code
  Stripping"; the compiler's word, internalize, tells a reader of a client's manifest nothing.
- **Release builds on macOS only.** Debug builds (and so `swift test` and DocC) are untouched; Linux and Windows are
  unmeasured.
- **Every module a library product ships**, computed in the manifest; not the test support or width-corpus targets,
  which no app links.
- **Xcode apps** get the saving only with `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default (measured,
  Xcode 26.3); the README says so.
- **The manifest check** that once failed on any `unsafeFlags` now enforces what such a flag may reach: a compile
  flag only behind a trait, and no link flag but TUI's own unexport patterns (decisions
  [B-SHIP-2](#b-ship-2-packageswifts-unsafe-flags-every-one-behind-a-trait-link-flags-only-tuis-unexport-patterns)).

### Since

The unexport list became a second default trait, `UnexportTUISymbols`, on 2026-10-12, because ld refuses it beside
an export list of the developer's own (decisions
[B-SHIP2-1](#b-ship2-1--unexported_symbol-is-a-trait-of-its-own-unexporttuisymbols-beside-deadstripunusedapi)).
See also [which links TUI's flags reach](<Binary size.md>),
README [Shipping size](../../../README.md#shipping-size), and
[where the bytes of a TUI app go](<Binary size.md>).

## Whether `-deduplicate` is safe for TUI (2026-10-11)

> **Status:** landed: `Tools/DedupCheck` in CI on Swift 6.4 (2026-10-11, `21b2dc0a4`) and on Xcode's 6.2.4
> (2026-10-12, `e1b8e384f`); the README documents the flag as the app's own choice. **Decided by:** the owner,
> 2026-10-11 (a README opt-in section with CI checks; never an app-wide flag imposed quietly) and 2026-10-12 (the
> check on the 6.2.4 lane too). **Working notes** (not in git): `SIZE3/fu/dedup/`, `SIZE3/fu/dedup-pty/`,
> `SIZE3/q/dedup-check/notes.md`, `SYMS/notes.md` §4 (Xcode).

### Question

`-Xlinker -deduplicate` saved about 7% of every app (818 KB of a stripped hello world on 6.4.0) by giving functions
with identical machine code one address. Is a program folded that way still correct, can a check at build time keep
TUI safe under it, and should TUI apply it? (The SIZE3 review's question 10, paraphrased.)

### Answer

- **Correct today, with one latent hazard: key paths.** Swift identifies a key path to a computed property by its
  getter's address. Folding two identical getters makes two different key paths compare and hash equal; with
  different setters they still write to different places. Nothing else in TUI observes a function's address in a
  way a fold can change.
- **Xcode already does it.** An Xcode Release link hands ld `-Os`, and ld then folds: an Xcode-built hello world
  folded 20,575 of its 61,034 functions. So TUI must be safe under folding for every Xcode app now, whatever
  SwiftPM users choose. `swift build` does not fold.
- **The check is the link map, not ld's output.** `-verbose_deduplicate` prints counts, not names; a folded function
  keeps its name at the survivor's address (with size 0 in the map), so the unstripped binary's symbol table shows
  every fold as aliases.
- **TUI does not apply the flag.** SwiftPM 6.2+ would accept it from the package, but a link flag lands on the
  developer's whole program, changes what the developer's own key paths compare equal to, and on 6.4 with Swift
  Build cannot be undone, because the package's link flags come after the developer's.

### Key measurements

Stress, release, main 2c75a8c21 (swift.org 6.4.0 with Swift Build, and Xcode 26.3's 6.2.4, native), ld-1230.1, on
the development machine (arm64 macOS 15.8.1 VM). Probes of each key-path and closure shape were built on both
toolchains.

| | 6.4.0 | Xcode's 6.2.4 |
|---|--:|--:|
| functions folded / `__text` saved | 23,209 / 861,068 B | 22,110 / 763,424 B |
| TUI key-path getters in the binary | 313 | 313 |
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

### Reasoning

- **The inventory is small.** TUI compares key paths in three places: the render memo's environment slots, the
  root palette lookup, and `Table`'s same-column check. It compares one function address, the fatal-signal
  handler's, and a `@convention(c)` function never folds. The 94 `ObjectIdentifier` uses are of metatypes and
  objects, which are data, and `-deduplicate` moved no data symbol.
- **The one finding is harmless.** `installedButtonAppearance` is `buttonStyle` with a setter that also ends a custom
  primitive style. Only the environment slot table could confuse them, and no slot sees both, so the manifest
  allows the pair with that reason. 6.4.0 does not fold it.
- **Folding differs by compiler**, so the check runs per toolchain: 6.4.0 and 6.2.4 differ by that pair. Swift.org's
  6.3.3, measured once, folds what 6.2.4 folds (decisions
  [B-SHIP-1](#b-ship-1-the--deduplicate-check-runs-on-two-toolchains-64-and-624)).
- **`-no_deduplicate_allow_swift_addr_ref`** keeps key paths and closures distinct and still saves about 2%; the
  README offers it.

### What landed

- `Tools/DedupCheck` ([README](../../../Tools/DedupCheck/README.md)): key paths TUI forms (K1), the
  functions that consume them (K2), address-taken C functions (F1), addresses the manifest says must stay unique
  (F2), and a report of public alias pairs for app developers (K3). Two SwiftLint rules flag a new key-path
  comparison or function-address cast in the library. CI also fails if a release program exports a TUI symbol
  (`cd0ffeee9`).
- README, [Shipping size](../../../README.md#shipping-size): what folding changes in an app's own code, and how
  to opt in or out.

Part of [where the bytes of a TUI app go](<Binary size.md>); the flag's
reach is on [which links TUI's flags reach](<Binary size.md>).

## Which links TUI's flags reach, and the debug map (2026-10-11)

> **Status:** decided; the one lever taken landed 2026-10-12 as the `UnexportTUISymbols` trait (`d159ab542`).
> **Decided by:** the owner, 2026-10-11 and 2026-10-12. **Working notes** (not in git): `SYMS/notes.md` (revised
> after the critic's review in `CRIT/SYMS/`), with the scope probe in `SYMS/scope/`.

### Question

The owner, 2026-10-11, in three parts: which of TUI's manifest flags reach the developer's own code ("never
impose app-wide flags quietly"); can TUI shrink the debug map and the symbol table of an unstripped app without
asking anything of its users; and are internalize, single-module emission, the machine outliner, mergeable traps and
the SF Symbols table change really invisible to users?

### Answer

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

### Key measurements

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

### Reasoning and decisions

- **Link flags are the developer's.** The owner's rule since 2026-10-11: TUI never imposes an app-wide flag
  quietly. So `-deduplicate`, `-S`, `-x` and `-no_exported_symbols` stay README advice, and the manifest check
  refuses a link flag in TUI's manifest
  ([B-SHIP-2](#b-ship-2-packageswifts-unsafe-flags-every-one-behind-a-trait-link-flags-only-tuis-unexport-patterns)).
- **One exception, ruled 2026-10-12:** "-unexported_symbol sounds worth doing". It became a default trait of its
  own, limited to patterns that match only symbols Swift names after a TUI module, because ld refuses it beside a
  developer's own export list
  ([B-SHIP2-1](#b-ship2-1--unexported_symbol-is-a-trait-of-its-own-unexporttuisymbols-beside-deadstripunusedapi)).
  It also takes the developer's own extensions of TUI's types out of the exports, which the README states.
- **Declined, 2026-10-12:** the strip list ("we need to support debugging properly"); the outliner and mergeable
  traps on the same grounds, and single-module emission for its build time; both are in
  [Future options](<../../Future options.md#build-and-binary-size>).
- **A correction this work made:** Xcode Release builds already deduplicate, which made TUI's
  [dedup check](<Binary size.md>) matter for every Xcode app.

See also [dead-stripping TUI's unused API](<Binary size.md>)
and README [Shipping size](../../../README.md#shipping-size).

## Completing the SwiftUI API: lane SHIP's decisions for review

*A companion to [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>),
written by the lane that shipped the owner's size decisions of 2026-10-11: the
`DeadStripUnusedAPI` trait, the README's "Shipping size", the `-deduplicate`
check (Tools/DedupCheck) and the Span check's place. It holds only what that
work raised that was not already decided, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

### B. Shipped the safe option

#### B-SHIP-1. The `-deduplicate` check runs on two toolchains, 6.4 and 6.2.4

*`.github/workflows/ci.yml` (the step "Deduplicated, stripped release programs
…"), `Tools/DedupCheck/ci-check.sh`*

**Shipped:** the check, and the stripped `--selfcheck` and PTY smoke, on the
"macOS 26 · Swift 6.4" lane, which already built release, so there the step
only links (243 s on the development machine, nearly all of it the PTY smoke);
and, since 2026-10-12 (the owner: "Run the dedup check on 6.2.4 in CI too, if
the behaviour is known to differ vs 6.4"; it is), on "macOS 15 · Xcode 26"
(Xcode's 6.2.4), which gained a release build for it. There it costs about ten
minutes a run on the development machine (busy, -j 3): 187 s of release
build, 9 s of the Span check, which reads the same build, and 384 s of the
step; runners unmeasured.

**What it misses:** which functions fold is the compiler's and the linker's.
Xcode's 6.2.4 folds `EnvironmentValues.buttonStyle` with
`installedButtonAppearance` and 6.4.0 does not (measured 2026-10-10; allowed in
the manifest with its review). swift.org's 6.3.3 folds that same pair and no
other (K1 8 of 320 getters, one equal group, as 6.2.4; measured 2026-10-12 as
a stand-in for the 6.3 lane's Xcode toolchain), so the 6.2.4 lane answers for
6.3 today. A new pair that only 6.3 folds would pass CI.

**Fuller version and price:** the same step on "macOS 26 · Xcode 26" (6.3),
which needs a release build first: 260 s of build with 6.3.3 on the
development machine, plus the step's six minutes or so (runners unmeasured).
Worth it only once 6.3 is known to fold differently from 6.2.4.

#### B-SHIP-2. Package.swift's unsafe flags: every one behind a trait; link flags only TUI's unexport patterns

*`Tools/validate-package-manifest.sh` (commit "A macOS release build lets the
app's link drop …"; the link-flag exception from the commit that keeps
TUI's symbols out of the app's export table, 2026-10-12)*

**Shipped:** the manifest check, which failed on any `unsafeFlags` because
SwiftPM used to refuse them in a versioned dependency, fails on any
`unsafeFlags` setting whose condition names no trait (no compiler flag undoes
another, and no link flag undoes `-unexported_symbol`, so the trait is the
client's only way out), and on an `unsafeFlags` LINKER setting (it would land
on the app's own link: the owner's rule that app-wide link flags are the
developer's opt-in), with one exception since 2026-10-12, the owner's
"-unexported_symbol sounds worth doing": a linker setting whose flags are
nothing but `-Xlinker -unexported_symbol -Xlinker '_$s<length><module>*'`,
where `<module>` is a target of this manifest named `TUI…` and
`<length>` its length. Such a pattern matches only symbols Swift names under a
TUI module; the check refuses a
wider wildcard, another package's module, a wrong length, a list file, or any
other flag beside the patterns (its self-test has each case). It still
reaches the app in three ways, which Package.swift and the README spell out:
it lands on a developer's own `.dynamic` library too; the developer's own
extensions of TUI's types and protocols, whose symbols Swift names after
the extended type's module, leave the exports with TUI's (this entry first
said the patterns changed nothing of the app's own, which the lane's review
found false the same day); and ld refuses it
beside an export list (B-SHIP2-1 in
[`Shipping size and products, second round (SHIP2).md`](<Binary size.md>)).

**The looser alternative:** allow compile flags without a trait. Simpler, and
no client could turn such a flag off; nothing in the package needs it today.

### C. Declined without asking

#### C-SHIP-1. The libswiftCompatibilitySpan check stays in CI, not in the unit tests

*`Tools/check-span-compatibility.sh` (its header, "WHY NOT A UNIT TEST"), on
CI's "macOS 26 · Swift 6.4" lane*

**Asked:** a check that fails if TUI starts depending on
`libswiftCompatibilitySpan.dylib`, "ideally in unit tests, if it's cheap enough
and makes sense there, but at the very least in CI".

**Declined:** both forms of a unit test. A test runs a debug build, and a debug
build depends on the library where a release build of the same code does not.
Measured 2026-10-11, macOS 14 target, on Xcode's 6.2.4 and on 6.4.0: a `Span`
handed to a generic function, even an `@inline(__always)` one, leaves the
object an undefined `$ss4SpanVMn` (6.2.4) or `$ss4SpanVMa` (6.4.0) at -Onone
and nothing at -O. The same source built as a library gets an
`LC_LOAD_DYLIB @rpath/libswiftCompatibilitySpan.dylib` at -Onone and none at
-O.

- A test that reads the load commands of the image holding TUI's code (the
  form item 4 described) would fail on code that ships clean.
- A test that asserts the test process never loaded the library (review round
  1's suggestion; a 6.2.4 test run does not load it today, measured) fails in
  the same case: the debug image's strong load command makes dyld load the
  toolchain's copy. It adds nothing the first form lacks, and shares its false
  failure.

The debug test bundles are clean today (measured on both toolchains: no load
command names the library, and nothing is imported from it), so either test
would pass now and fail later on a change that ships nothing new.

**What ships instead:** the CI check on the 6.4 lane's release build. It reads
Stress, Example and the objects of every module a library product ships,
TUIAppKit's among them, which no executable links: "28 objects of 28
library modules … none refers to a Span-family symbol" on this tree.

**If you want a unit test anyway:** it is cheap, one image's load commands. The
price is the false failure above, the first time TUI hands a `Span` to a
generic function. Its fix would be an allow-list of debug-only references,
which is the release check's job.

## Completing the SwiftUI API: lane SHIP2's decisions for review

*A companion to [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>),
written by the lane that shipped the owner's decisions of 2026-10-12 on size and
products: TUI's symbols out of the app's export table, the gradient editor
back in TUIColorPicker, the `-deduplicate` check on the 6.2.4 lane, and the
tests' temporary directories. It holds only what that work raised that was not
already decided, in the main file's three parts.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

### B. Shipped the safe option

#### B-SHIP2-1. `-unexported_symbol` is a trait of its own, `UnexportTUISymbols`, beside `DeadStripUnusedAPI`

*`Package.swift` (the "App size" section), `README.md` ("Shipping size")*

**Asked:** the unexport patterns gated on the same `DeadStripUnusedAPI` trait,
so that `traits: []` turns both off, unless there was a reason for a trait of
their own.

**Found:** ld refuses `-unexported_symbol` beside any export list. A link
that also passes `-no_exported_symbols`, `-exported_symbol` or
`-exported_symbols_list` stops with "-unexported_symbol cannot be used with
-exported_symbol*" (or "-no_exported_symbols cannot be used with
-[un]exported_symbol*", by flag order): measured 2026-10-12 with Xcode 26.3's
ld-1230, and `-ld_classic` says the same, on a one-function program and on the
hello world relinked from both toolchains' builds. Xcode's
`LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE` pass those flags (untried
in Xcode). So a developer whose own link needs an export list (a plugin host,
a dynamic library with a curated interface, or the README's own
`-no_exported_symbols` until now) cannot build with the default traits at all.

**Shipped:** a second default trait, `UnexportTUISymbols`. `traits: []`
still turns both off; such a developer writes `traits:
["DeadStripUnusedAPI"]` and keeps the −14.7% of the dead stripping, which with
one trait they would have had to give up to make their link work at all. The
README's `-no_exported_symbols` lever is gone with it: the trait takes 97% of
what that flag saved (the hello world's export table 317 KB → 9 KB), and the
rest goes with `-Xlinker -unexported_symbol -Xlinker '*'`, which ld takes
beside the patterns (9 KB, −0.1%). `Tools/DedupCheck/ci-check.sh` follows the
README and links with `-deduplicate` alone.

**The other version, and its price:** one trait, as asked. One name fewer in
the docs; but the export-list developer's only way to a working link would be
`traits: []`, and the dead stripping with it.

## Completing the SwiftUI API: lane BNDL's decisions for review

*A companion to [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>),
written by the lane that made a TUI program run without its resource bundle
(2026-10-10): the binary-size follow-ups found that every TUI app stopped at
launch (`Fatal error: unable to find bundle named TUI_TUIStrings`) when
`TUI_TUIStrings.bundle` was not beside the binary. It holds only what
that work raised that was not already decided: the same three parts as the
main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

### B. Shipped the safe option

#### B-BNDL-1. TUI's English is compiled in as well as bundled

*`LocalizationService`, `LocalizationService+BuiltInEnglish.swift`*

**Shipped:** a copy of `en.json`, as the file's text in a raw string literal,
parsed by the same parser the bundled files go through, and only where `en.json`
cannot be read. Without it a program shipped without the bundle would not run
"in English": TUI's words would read as their keys (`statusbar.quit`), the
quiet failure the first WebAssembly build showed. `BuiltInEnglishTests` fails,
naming the keys, until the copy matches the file, and the localization article's
"Adding New Keys" says to paste it.

**Price, measured** (`swiftc -O -c`, Xcode's 6.2.4, 2026-10-10): the string is
5,462 bytes of `__cstring`. A `[String: String]` literal of the same 144 pairs
measured 8,125 bytes (4,640 of 32-byte entries in `__DATA,__const`, 3,409 of
its longer strings), so the text is the smaller form as well as the one that
can be pasted. A program with the bundle carries the 5.5 KB unused.

**Fuller version:** one English. The compiled-in table becomes the only English
and `en.json` leaves the bundle (5.5 KB less in it), or a generator writes the
Swift file from `en.json` so there is nothing to paste. Either changes how a
translator adds a key, so it is yours to choose.

#### B-BNDL-2. The version of a program without the bundle reads `unknown`

*`tuiKitVersion`*

**Shipped:** `"unknown"`, the value it already had for a `VERSION` file that
could not be read, and the one `VersionResourceTests` and the versioned-consumer
gate test against.

**Fuller version:** compile the version in, as the English is. The price is a
second place to change at every release (or a generator), for a string a
program without the bundle shows only where it prints the version.

#### B-BNDL-3. TUI looks for its bundle itself, and never at the build directory

*`ModuleResources` (was `moduleResourceURL`, a function of `Bundle.module`)*

**What was measured** (the generated `resource_bundle_accessor.swift` of a
one-target probe package, 2026-10-10, under each toolchain this repository
builds with; and `Bundle.main` / `Bundle(for:)` printed from a tool, a symbolic
link to it, a copy of it, and both kinds of test run):

| Build | Where `Bundle.module` looks | Without the bundle |
|---|---|---|
| SwiftPM native (Xcode's 6.2.4; swiftly 6.4.0 with `--build-system native`; 6.3.3 static Linux SDK) | `Bundle.main.bundleURL` + `<name>.bundle` (`.resources` off Apple platforms), then the build directory's absolute path, compiled in | `Swift.fatalError("could not load resource bundle: …")` |
| Swift Build (6.4.0's default; 6.2.4 with `--build-system swiftbuild`) | `PACKAGE_RESOURCE_BUNDLE_PATH` (debug builds), `Bundle.main.resourceURL`, `Bundle(for:).resourceURL`, `Bundle.main.bundleURL` | `fatalError("unable to find bundle named …")` — the one the binary-size lane hit |
| SwiftPM native, WebAssembly (6.3.3) | two absolute paths, both compiled in: the host toolchain's `usr/bin` (a generator quirk) and the build directory | as native |

Under `swift test` the program is the toolchain's runner, so `Bundle.main` is
the runner's: the native build finds the bundle by its compiled-in path, which
is the directory holding the `.xctest`; Swift Build copies the bundle into the
`.xctest`'s `Contents/Resources`. Started through a symbolic link, a tool's
`Bundle.main.bundleURL` is the LINK's directory, and `Bundle(for:)` the real
one.

**Shipped:** no call to `Bundle.module` (but on WebAssembly, B-BNDL-4). A
check before calling it cannot be made safe: the two accessors look in
different places, and one at a path nothing else can read, so nothing checked
here proves the one compiled in will find the bundle. TUI looks in Swift
Build's three places (not the environment variable, which is Xcode's), and in
the directory holding the bundle its code was loaded from when that is not the
main bundle, which is the native build's compiled-in path in the one layout
that needs it (a test bundle). It answers none where none of those holds the
bundle.

**What changes where the bundle exists:**

- A program **copied out of its build directory** no longer reads the bundle
  left there. Under the native build it did, on the machine that built it and
  on no other, which is how a copied binary passes on its author's machine and
  stops on every user's; under Swift Build it stopped everywhere. It now reads
  English, everywhere, and `tuiKitVersion` reads `unknown`.
- A program **started through a symbolic link** to a directory holding it and
  its bundle (how a Homebrew formula installs into `bin`) used to stop under the
  native build, unless its build directory still existed. It now reads the
  bundle (measured: `Tools/Smoke/bundleless_smoke.py`, against a build from
  before this lane with its build directory's bundle moved aside: the linked
  run stopped by signal 5).

**Fuller version:** none found that keeps reading the compiled-in path: it is
readable only through the accessor that stops the program.

**Unmeasured:** Swift Build's accessor and bundle placement on Linux (6.4's
default there too). A layout this does not cover shows as English and
`tuiKitVersion == "unknown"`, which `VersionResourceTests` fails on; CI's 6.4
Linux lane is the check.
Still unmeasured on 2026-10-19: this machine has no container runtime, and
nothing has been pushed since 2026-10-01, so that lane has not run it. What
was checked that day: `Tools/verify-versioned-consumer.sh` passes (a package
depending on TUI 1.0.0 by version reads `tuiKitVersion` 0.6.0 and German's
`button.cancel`), and `ModuleResourcesTests` now fails if any library module
reads `Bundle.module` again outside `ModuleResources`' WebAssembly arm — the
revert that would bring the stop back.

#### B-BNDL-4. On WebAssembly, a page that serves no bundle still stops the program

*`ModuleResources.current`*

**Shipped:** on WASI the lookup is still `Bundle.module`. SwiftPM compiles both
places it looks into the program as absolute paths there (B-BNDL-3's table), and
`Tools/Web/build.sh` serves the bundle at the build directory's, so there is
nothing to look for at run time, and the web demo reads its translations as
before.

**Fuller version:** the page serves the bundle beside the program's `argv[0]`
as well, and WASI searches as everywhere else. The price is a change to the web
build and a check in a browser, which this lane could not make.

## Completing the SwiftUI API: lane SIZEDOCS's decisions for review

*A companion to [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>),
written by the lane that committed the binary-size study of 2026-10-10 to
the appendices of this story (the study of 2026-10-10)
and the SwiftUI probes that TUI's code cites to
[`Tools/SwiftUIProbes/`](../../../Tools/SwiftUIProbes) (the owner, 2026-10-12:
"The SIZE3 report.md, README.md, and probe sources are fine to commit. 233 KB
is substantial but worth it"). It holds only what that work raised that was
not already decided: the same three parts as the main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

### B. Shipped the safe option

#### B-SIZEDOCS-1. Two probe sets more than the inventory listed: D1S's second round and wave 12's

*`Tools/SwiftUIProbes/Sections and subview counting/`, `Tools/SwiftUIProbes/Animation curves, springs and keyframes/`*

**Asked:** the eight probe sets that the plan for moving the working notes
listed as cited by committed code (`DYNP/probe`, `DYNP/optional`,
`SKEY/probe`, `GUIDE/probe`, `GUIDE/probe2`, `D6L/probe`, `D1S/probe`,
`w10b/probe`; about 233 KB), committed, and every citation of them pointed at
the committed copy.

**Found:** the code cites two more sets by path, without the words "session
notes" that the inventory searched for:

- `D1S/probe2`, the D1S lane's second round (sections in forms and menus, a
  view of the app's own whose body is several views, deleting a multi-view
  `List` row): four files in `Sources` (`CompositeMembers.swift`,
  `FormContentExtraction.swift`, `MenuSections.swift`,
  `ListRowEditOwner.swift`), four test files, and two places in the D1S
  decisions.
- `w12/probe`, wave 12's animation probes (`UnitCurve`, `Spring`,
  `KeyframeTimeline`): `KeyframeCurve.swift`, three test files, and wave 12's
  entries in the main decisions file.

**Shipped:** both, in a commit of their own, so that it can be dropped:
57,071 B of sources and outputs (measured), the second round beside the
first in "Sections and subview counting", and wave 12's as "Animation
curves, springs and keyframes"; their citations in `Sources`, `Tests` and the
D1S decisions repointed. With it, nothing in `Sources`, `Tests` or `Tools`
names a probe by its path in the working notes (`MeshGradientTests.swift` says
lane 17m's are there, without one). The main decisions file still
cites both `w10b/probe/` and `w12/probe/` there: that file is yours to edit.

**Fuller version, shipped 2026-10-23 (lane DOCS2, the owner's ruling
B-SIZEDOCS-1 (a)):** the SwiftUI probes that only decisions files cite (waves
6b, 8a, 8b, 10 and 11a, lanes 17, 17d, 17g and 17m, D5G and DECB), and since
then W1's, FB16's, PARITYMISC's, INPUT's and O13's, committed the same way
without the pixel dumps, renders, built programs and module caches, and their
citations in Documentation, Sources and Tests repointed. It is 174 files and
539,073 B (measured): sources, text outputs and the notes' scripts, in 16
folders of `Tools/SwiftUIProbes/` with an entry each in its README. It is
larger than the 438,206 B in 189 files the entry priced, because the sets that
lanes added since (PARITYMISC, INPUT, O13, W1 with its review round, FB16's
36 KB) came with it. Left in the working notes: wave 17t's probes, which
nothing named in the ruling; and the notes the code and decisions cite that are
not SwiftUI probes (DYNV/notes.md and DYNV2/notes.md, O9/probe, O10/probe).
Lane 8b's probes write PNGs; the committed copies write them to
`NSTemporaryDirectory()` and not to the notes folder.

## Completing the SwiftUI API: decisions from lane BT1

*Lane BT1 carried out the package-side half of the owner's request of
2026-10-06 — cut TUI's clean release compile time ("many minutes for some
people") and its release binary size — using the analysis in the session notes'
`buildtime/report.md`. It changed no public API. This file holds the judgement
calls the work reached that the request did not already settle, in the format
of [the main decisions record](<../SwiftUI parity process/Completing the SwiftUI API.md>):*

- **A-BT1-n — needs your decision.** Nothing has shipped for these.
- **B-BT1-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-BT1-n — declined.** With the reason.

### B. Shipped the safe option

#### B-BT1-1. The SF Symbol name index stays an integer array literal — superseded

*`SFSymbolTable.generated.swift`'s `nameStarts`, generated by
`Tools/GenerateSFSymbols`*

**Superseded on 2026-10-11: front-coding landed.** The owner chose D3 ("Do the
'front-coding' approach to SF Symbol names"), and lane SFQ shipped it: the names
are front-coded in blocks of 16, and `nameStarts` (8,467 offsets) is gone,
replaced by `blockStarts`, one offset per block (530 blocks, so 531
`UInt32`s with the blob-length sentinel). The `nameStarts` this entry weighs,
and both fuller versions below, no longer exist. The entry is kept as written.

A clean release build spent about 0.31 s of SIL optimisation on each of the
symbol table's two integer arrays (Xcode 26.3's Swift 6.2.4; the pass timers'
sum for each one-time initialiser, min of 3). The optimiser folds an array
literal into static data element by element, so the cost follows the element
count. The codepoints are now packed four to a `UInt64` (314 ms → 74 ms): the
lookup reads its codepoint once, after the search, with one shift.

`nameStarts`, the 8,467 byte offsets of the names in `nameBlob`, is unchanged.
The binary search reads it twice per step, so the same packing would put a
shift and a mask into the search loop, and the brief for this lane was "cheaper
to compile without making lookups slower".

**The fuller version, and its price.** Either:

- **Derive `nameStarts` from `nameBlob` at first use** (the names are
  newline-separated, so the offsets are where the newlines are): about −0.3 s of
  a clean release build and −33,868 bytes of binary. It costs one pass over the
  200 KB blob on the first symbol lookup (unmeasured; the current design's first
  access measured 0.7 µs) and 34 KB of heap, and it ends the generator's "no
  runtime parsing" design — the same reversal D3 asks about.
- **Pack it two to a `UInt64`:** about −0.15 s, for a shift and a mask on each
  of the ~26 reads a lookup makes (unmeasured; a lookup microbenchmark would
  settle it).

D3 (front-coding the names, still open) replaces `nameStarts` with one start
per block — 265 entries at blocks of 32 — which removes this cost too, so this
is best decided with D3.
