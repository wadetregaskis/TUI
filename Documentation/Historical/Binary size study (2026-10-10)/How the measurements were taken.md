# SIZE3 artifacts: the built TUIkit libraries, before and after an app links them

> **What this is.** The method behind the binary-size study of 2026-10-10 (SIZE3): which toolchains built what, the
> exact commands, how every report was made, and the full byte inventory of the built libraries and four apps, at
> 247de05f9. The study's findings, levers and follow-ups are in
> [Where the bytes go in a release build.md](<Where the bytes go in a release build.md>), beside this file, which
> also lists what was decided since.
>
> **Historical.** TUIkit has changed since: it no longer depends on swift-collections, every module is a library
> product, and two default-on traits change how an app links it, so a rebuild today gives other numbers.
>
> **Paths.** Relative paths here (`artifacts/…`, `tools/…`, `minapp/`, `linkcwd/`, `<tag>/…`) are in the
> maintainers' working notes, in the folder SIZE3, and `plan/slot.py` and `buildtime/minapp` are elsewhere in those
> notes; none of them is in this repository, and the worktree the builds ran in is gone. The commands in §2 are
> kept as they ran.

Prepared 2026-10-10 for an analysis of where the bytes of the BUILT TUIkit libraries go (objects, archives, a dylib),
with four linked apps beside them for the "linked vs unlinked" and API-usage angles. This directory holds artifacts and
per-file reports only; it draws no conclusions beyond the observations in §5. Every byte count here is **measured**
(a file size, or a field read from a Mach-O header) unless it says otherwise; causes are labelled **established** or
**hypothesis**.

- Source: TUIkit main **247de05f9**, built from the worktree `.claude/worktrees/wf_16d11454-ce5-1`, with ONE
  uncommitted edit during the builds: a product `.library(name: "TUIkitDynamic", type: .dynamic, targets:
  ["TUIkit"])` (`tools/worktree-edits.diff`; resolution also added a swift-syntax pin to `Package.resolved`). Both
  edits were reverted afterwards; nothing was committed.
- Machine: the 16 GiB arm64 VM, macOS 15 (Darwin 24.6.0), Xcode 26.3 (17C529), SDK MacOSX26.2, linker ld-1230.1
  (Xcode's; both toolchains linked with it: every binary's LC_BUILD_VERSION names LD 1230.1). Release, default settings, `-j 4`, every build through `plan/slot.py`
  under an RSS guard (`tools/guard.sh`, 7 GiB; the largest sampled `swift-frontend` RSS was 3,397,616 KB, in x624's TUIkit step).
- Apps: Hello (one `Text`) and Typical (List, Table, TextField, Toggle) from `minapp/` (a copy of
  `buildtime/minapp`, depending on the worktree by path, pinned to the same swift-collections 1.5.1); Example and Stress
  from the package itself.

## 1. Toolchains

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

## 2. Exact commands

```sh
N=/Users/robot/Documents/TUIkit-session-notes; Z=$N/SIZE3; WT=/Users/robot/Documents/TUIkit/.claude/worktrees/wf_16d11454-ce5-1
# builds (one slot each; tools/build.sh runs every step under tools/guard.sh with J=4 LIMIT_GB=7 and -v):
cd $WT
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run $Z/tools/build.sh s640 root   +6.4.0   # TUIkit, TUIkitAppKit, TUIkitDynamic, Example, Stress
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run $Z/tools/build.sh s640 minapp +6.4.0   # Hello, Typical
python3 $N/plan/slot.py $Z/tools/build.sh x624 root
python3 $N/plan/slot.py $Z/tools/build.sh x624 minapp
#   each step is: swift build -c release -j 4 --scratch-path $Z/scratch-<tag>-<root|minapp> -v --product <P> \
#                 [-Xlinker -map -Xlinker $Z/artifacts/<tag>/{lib/dylib,apps/<P>}/<P>.map]   (dylib and apps only)
# extraction (copies out of the scratch, then the reports; no slot: no compiling or linking):
python3 $Z/tools/extract.py <tag> lib            # objects, module files, archives (libtool -static), reports
python3 $Z/tools/extract.py <tag> apps-root      # Example, Stress  (strip -o <P>.stripped)
python3 $Z/tools/extract.py <tag> apps-minapp    # Hello, Typical
python3 $Z/tools/extract.py <tag> dylib          # libTUIkitDynamic.dylib (+ strip -S -x copy)
# per-module dylibs, linked from the copied objects (a slot each; run from $Z/linkcwd, see §6):
cd $Z/linkcwd
TUIKIT_SWIFT=swiftly python3 $N/plan/slot.py swiftly run python3 $Z/tools/link_dylibs.py s640 +6.4.0
python3 $N/plan/slot.py python3 $Z/tools/link_dylibs.py x624
python3 $Z/tools/extract.py <tag> permodule
python3 $Z/tools/inventory.py s640 x624 > $Z/artifacts/inventory.md
```

Archives: `xcrun libtool -static -no_warning_for_no_symbols -o lib<M>.a <M's objects in the build's own order>`, and
`libTUIkit-all.a` from every module of the umbrella closure (all but TUIkitAppKit) in dependency order; libtool
reported no duplicate member names. Per-module dylibs (`lib/dylib/per-module/link-commands.txt` has each command):
`swiftc -Xlinker -reproducible -target arm64-apple-macos14.0 -emit-library -sdk <SDK> @<objects> -l<every module in
its declared dependency closure> -Xlinker -install_name -Xlinker @rpath/lib<M>.dylib -Xlinker -rpath -Xlinker
/usr/lib/swift -Xlinker -rpath -Xlinker @loader_path -Xlinker -dead_strip -link-objc-runtime -Xlinker -map …
-no-stdlib-rpath`, mirroring the build systems' own TUIkitDynamic link (no dsymutil). Stripping: apps `strip -o`
(full), dylibs `strip -S -x` (debug STABS and local symbols; exported symbols must stay).

Scratch directories (`scratch-<tag>-<root|minapp>`, 0.6–1.1 GB each) were deleted once extracted. Disk on
/System/Volumes/Data went from 17 GiB free to a low of 10 GiB (another lane's clean test build was running at the
time) and was 11 GiB at the end, with other lanes still building; `artifacts/` is about 1.5 GB.

## 3. Layout

```
artifacts/<tag>/
  logs/                 toolchain-*.txt, build-<step>.log (-v), build-<step>.err (/usr/bin/time -l + guard peak), steps-*.txt, df-*.txt
  lib/objects-inventory.tsv
  lib/<Module>/objects/*.o        per-file objects as the compiler wrote them (+ ORDER.txt, the build's link order)
  lib/<Module>/<Module>.o         s640 only: SwiftBuild's per-module `ld -r` object, what its products link
  lib/<Module>/modules/           .swiftmodule, .swiftdoc, .abi.json, .swiftsourceinfo (+ s640: -Swift.h, .swiftconstvalues)
  lib/<Module>/objects.*          reports over the per-file objects (below); merged.* = the same for <Module>.o
  lib/archives/lib<Module>.a, libTUIkit-all.a (+ .members.tsv), archive-overhead.tsv, and reports per archive
  lib/archives/swiftbuild/        s640 only: SwiftBuild's own libTUIkit.a (kept) and libTUIkitAppKit.a (members + sizes only)
  lib/dylib/libTUIkitDynamic.dylib(.stripped), TUIkitDynamic.map, .exports.txt (dyld_info -exports), reports, sizes.tsv
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

## 4. Inventory (all bytes measured)

Columns: `.o files`/`objects` = the per-file objects; `of which DWARF` = their `__DWARF` sections; `__text` = summed over
those objects; `merged .o` = s640's per-module `ld -r` object; `lib<M>.a` = libtool archive of the per-file objects;
per-module dylib = linked by `link_dylibs.py`; module files as copied. The bold row sums every module except
TUIkitAppKit (not in the umbrella). `dep` = CSTBImage (the C target) or swift-collections 1.5.1.

### s640: library modules (bytes, measured)

| module | src | .o files | objects | of which DWARF | `__text` | merged `.o` | `lib<M>.a` | per-module dylib | stripped (-S -x) | .swiftmodule | .swiftdoc | .abi.json | .swiftsourceinfo |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| CSTBImage | dep | 1 | 339,592 | 226,396 | 54,876 | 112,908 | 341,216 | 120,368 | 103,384 |  |  |  |  |
| InternalCollectionsUtilities | dep | 19 | 333,536 | 178,898 | 17,880 | 153,512 | 368,704 | 151,736 | 104,832 | 251,736 | 18,460 | 149 | 60,392 |
| ContainersPreview | dep | 39 | 188,424 | 104,844 | 3,208 | 16,064 | 197,808 | 63,160 | 54,800 | 86,964 | 3,164 | 149 | 17,300 |
| DequeModule | dep | 45 | 1,083,568 | 613,518 | 96,296 | 419,624 | 1,141,640 | 344,312 | 226,208 | 945,288 | 181,680 | 149 | 215,848 |
| TUIkitCore | TUIkit | 69 | 4,743,432 | 2,660,661 | 496,072 | 1,846,760 | 5,094,952 | 1,287,120 | 817,120 | 763,440 | 466,028 | 149 | 416,220 |
| TUIkitStyling | TUIkit | 39 | 3,120,344 | 1,807,141 | 319,096 | 1,237,184 | 3,353,368 | 833,368 | 527,680 | 467,496 | 188,072 | 149 | 208,752 |
| TUIkitView | TUIkit | 81 | 5,015,248 | 2,413,771 | 534,500 | 2,523,696 | 5,550,848 | 1,696,944 | 1,018,400 | 958,028 | 429,736 | 149 | 525,428 |
| TUIkitStrings | TUIkit | 27 | 2,426,720 | 975,366 | 201,980 | 1,242,975 | 2,621,688 | 900,152 | 636,912 | 409,120 | 59,772 | 149 | 96,876 |
| TUIkitTerminalHost | TUIkit | 10 | 554,904 | 287,514 | 51,332 | 249,488 | 605,144 | 201,304 | 137,704 | 122,688 | 36,276 | 149 | 47,768 |
| TUIkitFoundation | TUIkit | 478 | 35,145,096 | 17,233,068 | 3,187,068 | 17,194,215 | 39,114,048 | 10,501,224 | 5,477,664 | 5,667,232 | 1,732,304 | 149 | 2,255,656 |
| TUIkitChrome | TUIkit | 29 | 1,705,360 | 843,937 | 174,600 | 768,608 | 1,864,056 | 562,968 | 348,400 | 215,500 | 47,852 | 149 | 60,136 |
| TUIkitApp | TUIkit | 60 | 2,875,736 | 1,497,977 | 250,356 | 1,131,160 | 3,096,832 | 785,232 | 465,960 | 329,740 | 38,548 | 149 | 53,680 |
| TUIkitImage | TUIkit | 21 | 1,851,296 | 1,122,987 | 177,020 | 681,552 | 1,980,824 | 504,280 | 322,048 | 230,636 | 87,408 | 149 | 72,088 |
| TUIkitBitmaps | TUIkit | 19 | 1,213,368 | 581,493 | 120,616 | 596,504 | 1,335,264 | 417,336 | 242,272 | 190,384 | 40,820 | 149 | 37,104 |
| TUIkitNumericControls | TUIkit | 26 | 2,673,088 | 1,374,304 | 319,308 | 1,262,455 | 2,922,864 | 864,464 | 531,992 | 489,396 | 131,316 | 149 | 131,884 |
| TUIkitPickers | TUIkit | 18 | 1,690,536 | 743,139 | 207,008 | 939,680 | 1,867,056 | 651,848 | 398,160 | 319,176 | 65,536 | 149 | 70,012 |
| TUIkitPresentation | TUIkit | 26 | 1,800,312 | 750,485 | 200,824 | 1,100,664 | 2,035,184 | 712,424 | 382,936 | 333,016 | 113,296 | 149 | 100,048 |
| TUIkitLists | TUIkit | 61 | 4,232,352 | 1,981,062 | 489,332 | 2,266,624 | 4,668,064 | 1,539,688 | 914,464 | 682,912 | 153,944 | 149 | 261,780 |
| TUIkitTabs | TUIkit | 19 | 1,989,560 | 926,911 | 228,120 | 1,123,176 | 2,209,408 | 729,392 | 409,056 | 336,172 | 75,040 | 149 | 82,472 |
| TUIkitTextInput | TUIkit | 36 | 2,869,400 | 1,560,216 | 274,496 | 1,077,912 | 3,084,920 | 745,720 | 448,752 | 352,984 | 80,140 | 149 | 80,592 |
| TUIkitColorPicker | TUIkit | 13 | 2,268,648 | 1,082,578 | 225,036 | 1,348,552 | 2,577,048 | 839,128 | 392,272 | 243,360 | 36,328 | 149 | 31,408 |
| TUIkitEffects | TUIkit | 14 | 1,107,816 | 473,592 | 121,388 | 711,552 | 1,254,984 | 475,912 | 259,792 | 233,396 | 83,096 | 149 | 73,128 |
| TUIkitForms | TUIkit | 9 | 848,720 | 376,715 | 88,504 | 534,128 | 967,000 | 364,840 | 199,152 | 176,908 | 48,488 | 149 | 47,932 |
| TUIkitGrid | TUIkit | 8 | 581,536 | 288,130 | 53,760 | 317,568 | 647,384 | 241,264 | 142,288 | 143,404 | 25,648 | 149 | 26,568 |
| TUIkitMenus | TUIkit | 7 | 483,768 | 194,213 | 44,780 | 345,192 | 558,264 | 260,504 | 154,288 | 142,740 | 31,068 | 149 | 35,916 |
| TUIkitNavigation | TUIkit | 20 | 1,759,968 | 821,683 | 182,276 | 988,432 | 1,968,840 | 650,696 | 346,272 | 266,772 | 58,228 | 149 | 59,836 |
| TUIkitSearch | TUIkit | 10 | 604,768 | 222,537 | 68,500 | 435,576 | 690,456 | 308,328 | 190,368 | 163,388 | 36,664 | 149 | 34,012 |
| TUIkitTables | TUIkit | 30 | 3,364,680 | 1,619,146 | 430,924 | 1,809,344 | 3,678,760 | 1,241,944 | 759,264 | 546,860 | 170,344 | 149 | 174,124 |
| TUIkit | TUIkit | 1 | 9,552 | 5,758 | 0 | 4,168 | 10,248 | 34,800 | 33,752 | 41,628 | 372 | 149 | 644 |
| TUIkitAppKit | TUIkit | 4 | 162,776 | 74,621 | 14,820 | 80,176 | 177,152 | 100,808 | 79,504 | 72,528 | 9,900 | 149 | 8,916 |
| **umbrella closure (all but TUIkitAppKit)** | | 1235 | 86,881,328 | 42,968,040 | 8,619,156 | 42,439,273 | 95,806,872 | 28,030,456 | 16,046,192 | 15,110,364 | 4,439,628 | 4,172 | 5,277,604 |

### s640: whole-library forms (bytes, measured)

| form | bytes |
|---|--:|
| `libTUIkit-all.a` (libtool -static, every per-file object of the umbrella closure) | 95,804,080 |
| `libTUIkit.a` made by SwiftBuild itself (the per-module `ld -r` objects) | 44,273,328 |
| `libTUIkitDynamic.dylib` (the umbrella as a `.dynamic` product, unstripped) | 25,618,376 |
| `libTUIkitDynamic.dylib` after `strip -S -x` | 13,616,080 |
| `libTUIkitDynamic.dylib.dSYM` (not kept) | 53,305,572 |

### s640: apps (bytes, measured)

| app | unstripped | `strip` | dSYM (not kept) | link map | app's own objects | resource bundles beside it (not kept) |
|---|--:|--:|--:|--:|--:|--:|
| Hello | 25,538,248 | 11,502,960 | 53,332,502 | 13,870,341 | 17,256 | 41,913 |
| Typical | 25,571,208 | 11,519,568 | 53,389,740 | 13,885,706 | 85,440 | 41,913 |
| Example | 31,047,656 | 13,816,720 | 62,998,302 | 20,708,602 | 14,249,856 | 279,673 |
| Stress | 29,082,040 | 13,008,592 | 60,483,446 | 17,003,957 | 11,150,696 | 279,673 |

### x624: library modules (bytes, measured)

| module | src | .o files | objects | of which DWARF | `__text` | merged `.o` | `lib<M>.a` | per-module dylib | stripped (-S -x) | .swiftmodule | .swiftdoc | .abi.json | .swiftsourceinfo |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| CSTBImage | dep | 1 | 486,632 | 324,010 | 99,972 |  | 488,264 | 169,040 | 152,984 |  |  |  |  |
| InternalCollectionsUtilities | dep | 19 | 325,744 | 174,094 | 19,084 |  | 360,488 | 154,120 | 105,600 | 249,036 | 18,480 | 149 | 60,412 |
| ContainersPreview | dep | 39 | 172,368 | 99,025 | 4,908 |  | 180,256 | 67,400 | 55,968 | 92,340 | 3,184 | 149 | 17,320 |
| DequeModule | dep | 45 | 937,160 | 504,873 | 92,332 |  | 993,800 | 328,840 | 210,560 | 962,896 | 181,700 | 149 | 215,868 |
| TUIkitCore | TUIkit | 69 | 5,300,984 | 3,077,913 | 566,884 |  | 5,641,760 | 1,385,456 | 900,128 | 753,576 | 466,048 | 149 | 416,240 |
| TUIkitStyling | TUIkit | 39 | 3,301,568 | 1,937,559 | 340,576 |  | 3,531,576 | 867,368 | 546,240 | 459,724 | 188,092 | 149 | 208,772 |
| TUIkitView | TUIkit | 81 | 5,166,512 | 2,571,554 | 560,388 |  | 5,690,928 | 1,737,616 | 1,034,672 | 941,544 | 429,756 | 149 | 525,448 |
| TUIkitStrings | TUIkit | 27 | 2,533,248 | 1,076,101 | 213,512 |  | 2,721,832 | 928,168 | 653,056 | 399,080 | 59,792 | 149 | 96,876 |
| TUIkitTerminalHost | TUIkit | 10 | 612,504 | 326,160 | 57,208 |  | 660,512 | 223,256 | 154,456 | 109,688 | 36,296 | 149 | 47,788 |
| TUIkitFoundation | TUIkit | 478 | 36,468,872 | 18,490,741 | 3,361,464 |  | 40,366,296 | 10,836,712 | 5,662,592 | 5,672,436 | 1,732,324 | 149 | 2,255,676 |
| TUIkitChrome | TUIkit | 29 | 1,747,344 | 909,366 | 180,884 |  | 1,899,672 | 569,848 | 347,792 | 196,104 | 47,872 | 149 | 60,156 |
| TUIkitApp | TUIkit | 60 | 2,920,680 | 1,620,731 | 261,368 |  | 3,121,752 | 807,440 | 483,528 | 308,660 | 38,568 | 149 | 53,700 |
| TUIkitImage | TUIkit | 21 | 2,107,128 | 1,331,530 | 185,204 |  | 2,236,232 | 512,488 | 322,736 | 213,896 | 87,428 | 149 | 72,108 |
| TUIkitBitmaps | TUIkit | 19 | 1,265,016 | 634,953 | 124,856 |  | 1,383,064 | 425,704 | 242,656 | 173,516 | 40,840 | 149 | 37,124 |
| TUIkitNumericControls | TUIkit | 26 | 2,730,608 | 1,390,355 | 330,608 |  | 2,978,312 | 871,968 | 531,816 | 474,008 | 131,336 | 149 | 131,904 |
| TUIkitPickers | TUIkit | 18 | 1,761,808 | 784,994 | 224,820 |  | 1,938,880 | 677,192 | 413,840 | 301,724 | 65,556 | 149 | 70,032 |
| TUIkitPresentation | TUIkit | 26 | 1,834,664 | 792,074 | 212,416 |  | 2,063,056 | 718,696 | 382,888 | 318,164 | 113,316 | 149 | 100,068 |
| TUIkitLists | TUIkit | 61 | 4,310,936 | 2,068,207 | 512,836 |  | 4,736,344 | 1,578,984 | 930,704 | 654,248 | 153,964 | 149 | 261,800 |
| TUIkitTabs | TUIkit | 19 | 2,192,888 | 1,066,022 | 243,496 |  | 2,421,136 | 756,944 | 425,584 | 313,412 | 75,060 | 149 | 82,492 |
| TUIkitTextInput | TUIkit | 36 | 2,792,736 | 1,548,622 | 265,720 |  | 2,998,832 | 734,264 | 432,176 | 338,292 | 80,160 | 149 | 80,612 |
| TUIkitColorPicker | TUIkit | 13 | 2,337,024 | 1,146,768 | 224,724 |  | 2,650,392 | 826,280 | 375,424 | 221,800 | 36,348 | 149 | 31,428 |
| TUIkitEffects | TUIkit | 14 | 1,113,592 | 486,764 | 127,160 |  | 1,256,168 | 492,872 | 276,608 | 213,160 | 83,116 | 149 | 73,148 |
| TUIkitForms | TUIkit | 9 | 758,240 | 318,511 | 85,212 |  | 878,408 | 370,152 | 199,152 | 158,212 | 48,508 | 149 | 47,952 |
| TUIkitGrid | TUIkit | 8 | 606,136 | 309,877 | 56,696 |  | 672,968 | 263,344 | 159,072 | 125,668 | 25,668 | 149 | 26,588 |
| TUIkitMenus | TUIkit | 7 | 484,304 | 193,399 | 47,680 |  | 560,000 | 264,216 | 153,920 | 125,192 | 31,088 | 149 | 35,936 |
| TUIkitNavigation | TUIkit | 20 | 1,852,768 | 892,340 | 192,788 |  | 2,062,064 | 680,888 | 361,968 | 246,632 | 58,248 | 149 | 59,856 |
| TUIkitSearch | TUIkit | 10 | 589,680 | 220,894 | 70,544 |  | 672,736 | 308,184 | 189,696 | 141,808 | 36,684 | 149 | 34,032 |
| TUIkitTables | TUIkit | 30 | 3,517,984 | 1,724,574 | 451,352 |  | 3,830,688 | 1,265,816 | 776,160 | 527,532 | 170,364 | 149 | 174,144 |
| TUIkit | TUIkit | 1 | 9,120 | 5,319 | 0 |  | 9,816 | 34,800 | 33,752 | 18,312 | 392 | 149 | 664 |
| TUIkitAppKit | TUIkit | 4 | 167,304 | 85,782 | 16,132 |  | 180,104 | 101,272 | 79,664 | 43,072 | 9,920 | 149 | 8,936 |
| **umbrella closure (all but TUIkitAppKit)** | | 1235 | 90,238,248 | 46,027,330 | 9,114,692 |  | 99,006,232 | 28,858,056 | 16,515,728 | 14,710,660 | 4,440,188 | 4,172 | 5,278,144 |

### x624: whole-library forms (bytes, measured)

| form | bytes |
|---|--:|
| `libTUIkit-all.a` (libtool -static, every per-file object of the umbrella closure) | 99,003,448 |
| `libTUIkitDynamic.dylib` (the umbrella as a `.dynamic` product, unstripped) | 25,524,408 |
| `libTUIkitDynamic.dylib` after `strip -S -x` | 13,768,144 |
| `libTUIkitDynamic.dylib.dSYM` (not kept) | 53,447,347 |

### x624: apps (bytes, measured)

| app | unstripped | `strip` | dSYM (not kept) | link map | app's own objects | resource bundles beside it (not kept) |
|---|--:|--:|--:|--:|--:|--:|
| Hello | 25,411,432 | 11,621,760 | 53,373,998 | 15,518,116 | 16,800 | 40,769 |
| Typical | 25,427,352 | 11,621,824 | 53,414,836 | 15,535,898 | 83,472 | 40,769 |
| Example | 31,189,656 | 13,884,848 | 62,366,526 | 22,710,426 | 14,572,976 | 277,397 |
| Stress | 28,984,456 | 13,126,496 | 59,939,623 | 18,418,975 | 11,654,320 | 277,397 |


## 5. Observations made while preparing the artifacts

Facts read from the files (measured, cause established unless marked):

1. **Objects: one per source file, on both toolchains.** Release compiles each module whole-module with
   `-num-threads 12`, which writes one object per source file: 1,235 objects for the umbrella closure (TUIkit's 1,131
   plus 104 from CSTBImage and swift-collections). **SwiftBuild (s640) then `clang -r`s each module's objects into one
   `Products/Release/<M>.o`, and every product it links (its own `libTUIkit.a`, the dylib, the apps) takes those**
   (`Link <M>.o` steps and the `LinkFileList`s in `s640/logs/build-TUIkit.log`). Native SwiftPM (x624) links the
   per-file objects directly and makes no archive for an automatic library product.
2. **Debug info.** Every per-file object carries DWARF: 42,968,040 of 86,881,328 B (49.5%) on s640 and 46,027,330 of
   90,238,248 B (51.0%) on x624. SwiftBuild's per-module `ld -r` objects carry no `__DWARF` at all: they have a STABS
   debug map instead (312,249 STABS entries across the closure, among them one `N_OSO` per per-file object and one
   `N_AST` naming the `.swiftmodule`), and their string tables are larger (17,522,712 B against 13,291,424 B for the
   per-file objects; the debug map's names and object paths, inferred). So SwiftBuild's `libTUIkit.a` (44,273,328 B) can be symbolicated only while the intermediate objects
   exist (inferred from how a debug map works; not tested).
3. **What `ld -r` removes besides DWARF (s640).** Per-file objects less their DWARF: 43,913,288 B; the merged objects:
   42,439,273 B (−1,474,015). `__text`: 8,619,156 → 8,339,516 B (−279,640, −3.2%). Hypothesis: `ld -r` coalesces the
   weak definitions that several files of one module each emit, and merges literal sections. The same hypothesis would
   explain why x624's Hello map lists 296,673 dead-stripped bytes for TUIkitFoundation against s640's 26,433: in
   x624 those duplicates first reach the final link.
4. **Root and dependency builds are the same code.** The library objects of the worktree build (root package) and of
   the minapp build (TUIkit as a path dependency) match section for section, outside debug info:
   - s640: 28 of 29 merged module objects have byte-identical sections; TUIkit.o differs only in
     `__LLVM,__swift_modhash`; file sizes differ by 0–952 B, all of it string table (the longer scratch path in the
     debug map).
   - x624: 1,234 of 1,235 per-file objects are identical outside `__DWARF` and `__swift_modhash`; the exception is
     TUIkitStrings' `resource_bundle_accessor.swift.o`, whose `__cstring` holds the bundle's build path.
   So `lib/` stands for what a consumer's build compiles (`<tag>/root-vs-dependency-build.tsv`).
5. **Module files.** No `.swiftinterface` and a 149-byte `.abi.json` stub per module: library evolution is off (no
   `-enable-library-evolution` in any command). `.swiftmodule` totals 15,110,364 B (s640) and 14,710,660 B (x624);
   `.swiftsourceinfo` about 5.28 MB and `.swiftdoc` about 4.44 MB on both.
6. **Archives.** The `__.SYMDEF` table is 8,816,112 B of `libTUIkit-all.a`'s 95,804,080 B (s640); per archive in
   `lib/archives/archive-overhead.tsv`.
7. **Dylibs.** The umbrella dylib exports 24,743 symbols on both toolchains (`dyld_info -exports`). The 29 per-module
   dylibs of the umbrella closure together are larger than the single one: s640 28,030,456 against 25,618,376 B unstripped, 16,046,192 against
   13,616,080 B after `strip -S -x` (umbrella closure only).
8. **Apps.** Typical's stripped binary is 64 B larger than Hello's on x624 and 16,608 B larger on s640. s640's stripped
   Hello is 118,800 B (1.0%) smaller than x624's. Whether the compiler or the build system's flags cause the
   s640/x624 differences (here and in `__text`: 8,619,156 against 9,114,692 B over the per-file objects) is not
   established (§6).
9. **Build behaviour seen on the way (not a benchmark: busy box, wall times from the logs).** On x624 (native),
   `swift build -c release --product TUIkit` also compiled and linked the package's executables (Example, Stress,
   TerminalClientQuirks, the tools) and the macro plugin with swift-syntax's host (`-tool`) modules, in 154.9 s; the later `--product Example` and
   `Stress` steps only relinked. On s640 (SwiftBuild) the same command built only the product's closure (68.4 s), and
   the Example and Stress steps then compiled those modules (34.0 s and 16.5 s). For comparison, the minapp's Hello
   step, which compiles TUIkit as a dependency, took 81.9 s on s640 and 74.1 s on x624. Cause of the native
   behaviour not investigated.

## 6. What failed, and what was not done

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
  s640/x624 difference above; skipped because disk was at the 10 GiB line during the other lane's build); TUIkitMacros
  (needs swift-syntax; not part of the umbrella); dSYMs were measured, not kept; the apps' resource bundles were
  measured, not kept; nothing was run (no runtime measurements).
- No message from the owner arrived during this task.
