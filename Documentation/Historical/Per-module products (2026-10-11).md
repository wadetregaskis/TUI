# Per-module library products: what they are, mixing them with the umbrella, and the trade-offs

> **What this is.** The research behind TUIkit's per-module library products (item C9b of the SwiftUI API completion
> work): what a per-module product is, whether one package can offer the `TUIkit` umbrella and a product per module
> at once, what happens when an app mixes the two, and what each trade-off costs, measured on a miniature of
> TUIkit's package shape on Swift 6.2.4, 6.3.3 and 6.4.0 and xcodebuild 26.3 (2026-10-11).
>
> **Decided since.** The owner, 2026-10-11: "C9b: do it. As I understand it, we can have the umbrella target, as
> well as the individuals, all with their own products, but if a user happens to overlap the two it won't cause any
> harm." That holds for every static mix measured below; the one harmful mix is a user's own `.dynamic` library
> built from TUIkit beside a statically linked TUIkit product (E3), which the user guide warns about. The products
> shipped with the commit that added this file, and ColorPicker's editor panels moved into a module of their own
> right after it (SIZE3's Q7, change (1)).
>
> **Paths.** `pkgs/…`, `tools/…` and `logs/…` are relative to this lane's working notes (`C9B/`); `CRIT/…`,
> `SIZE3/…` and `buildtime/…` to the maintainers' working notes. None of them is in this repository. Line numbers
> into TUIkit's own files are at 0064b34bb.

Lane C9B, 2026-10-11; revised the same day after the critic's review (`CRIT/C9B/notes.md`), with one new probe
(`pkgs/Stub2`). TUIkit main at 0064b34bb (read only). Every probe ran on a miniature of TUIkit's shape in
`C9B/pkgs/` (a base module, three leaves that `@_exported import` their direct dependencies, an umbrella that
re-exports everything and declares nothing, one library product per module plus the umbrella's, MemberImportVisibility
on everywhere), consumed as a versioned `file://` git-tag dependency. Toolchains: Xcode 26.3's Swift 6.2.4 (SwiftPM
native build system), swiftly 6.4.0 (SwiftBuild, its default on macOS: `swift-build --help` says "default:
swiftbuild"), 6.4.0 `--build-system native`, 6.3.3 (native), and `xcodebuild` (Xcode 26.3). Labels: **measured** (I
ran it), **established** (read; cited), **estimate** (arithmetic shown), **hypothesis** (unverified). No timings were
taken.

## The answers

### 1. What a per-module product is

- **Established.** A SwiftPM package has *targets* (each compiles to one module) and *products* (the targets it
  offers to other packages). A consumer can depend only on products. TUIkit's Package.swift declares 30 non-test
  library targets (29 `.target`s, one of them the C target CSTBImage, plus the `@Animatable` macro plugin; counted).
  It offers them through 7 library products: the umbrella `TUIkit`, the lower four (`TUIkitCore`, `TUIkitStyling`,
  `TUIkitView`, `TUIkitImage`), `TUIkitAppKit` and `TUIkitMacros` (Package.swift lines 22–46). The 17 feature
  modules (`TUIkitApp`, `TUIkitLists`, `TUIkitTables` …) are reachable only through `TUIkit`, except TUIkitBitmaps,
  which with TUIkitFoundation is also in `TUIkitAppKit`'s closure (Package.swift:446–450). TUIkitFoundation,
  TUIkitStrings, TUIkitTerminalHost and TUIkitWidthCorpus have no product either.
- **C9b** adds one `.library(name: "TUIkitLists", targets: ["TUIkitLists"])` line per feature module. Nothing else in
  TUIkit changes: the modules already exist, each already re-exports its own dependencies, and the umbrella stays.
- **What it buys.** SwiftPM compiles and links only the closure of the products a target depends on; this probe
  confirms it (**measured**, §E1: a leaf-only app compiles and links only its closure).
  - *Bytes* (established, SIZE3/report.md:98–100): Hello world on `TUIkitApp` instead of `TUIkit` is 7.44 MB instead
    of 11.50 MB (−35.3%, measured relinks there).
  - *User compile time*: Hello would compile 11 of SIZE3's 29 modules (App, Chrome, Foundation, Core, Styling, View,
    Strings, TerminalHost and swift-collections' three; SIZE3/report.md:496), 57.2 of 86.9 MB of objects (−34%;
    an estimate from summed per-module sizes, SIZE3/report.md:540). The build-time saving itself is **unmeasured:
    timing owed**.
  - *Runtime and baseline memory*: a static à-la-carte app runs the same machine code (SIZE3/report.md:580, "none
    expected", unmeasured). It maps and relocates less `__DATA`/`__DATA_CONST` (1.06 MB in the umbrella today) and
    registers fewer conformance records, so launch time and resident memory could be lower
    (hypothesis; buildtime/split2/alacarte/design.md:280–282). **Timing and memory owed** on a quiet box: Hello on
    `TUIkitApp` vs on `TUIkit`, launch time and `phys_footprint`. The SwiftBuild dylib conversion of §E3 would add
    dylib loads at launch (hypothesis), but only in that dynamic case.

### 2. Yes: both at once, and the user's `Package.swift` decides

- **Measured.** The umbrella product and the per-module products coexist in one package. Each app chooses by what
  it lists in its target's `dependencies:`. A user who keeps `.product(name: "TUIkit", …)` and `import TUIkit` sees
  no change at all.
- **It is the `Package.swift` product list, not the `import` lines,** that decides what is compiled and linked. An
  app that depends on the umbrella product but writes only `import TUIkitLists` is exactly as large as the umbrella
  app (877,016 vs 877,000 B stripped, measured). Imports decide only what names are visible. The README's tip
  (README.md:194, "For finer control you can import individual modules") is true for names only; the à-la-carte page
  should say so.

### 3. Mixing them: it works, each module is linked once, and the saving is gone

- **Measured on 6.2.4 native, 6.3.3 native, 6.4.0 native, 6.4.0 SwiftBuild and xcodebuild 26.3:** every static mix
  builds, runs and links each module exactly once:
  - an app target on the umbrella with a library target of the same package on a leaf;
  - one file with `import Kit` and `import KitLists` (no warning for the redundant import, in Swift 6 mode with MIV
    on, the only configuration tried);
  - an app on the umbrella with a third-party package on a leaf, and the reverse (app on a leaf, third party on the
    umbrella).
  - One `RenderCache` type descriptor per app (checked with `nm -m`), no duplicate-symbol errors, one address for a
    global, one cache object, `is List` true across the boundary, no "Class X is implemented in both".
- **The size is the umbrella's** as soon as anything in the app's graph depends on the umbrella: every mixed app is
  within 0.04% of the umbrella app, and 2.6–2.75× the leaf-only app (table in §E1). In particular **a third-party
  library that depends on `TUIkit` takes the saving away from every app that uses it.** Library authors should depend
  on leaf products; this belongs in the guide.
- **The one mix that goes wrong is dynamic** (§E3): a user's own `.dynamic` library product built from the umbrella,
  plus a leaf linked statically into the app.
  - **SwiftPM native (6.2–6.4) gives two copies of the shared modules** (measured): the Objective-C runtime prints
    "Class _TtC7KitCore11RenderCache is implemented in both … One of the two will be used", type identity splits
    (a `List` made in the dylib is not `is List` in the app), and which copy of a global a call touches depends on
    whether the optimiser inlined it into the app (inferred, §E3).
  - **SwiftBuild (6.4's default on macOS, and Xcode) avoids the second copy** by silently turning the shared targets
    into dynamic libraries (`libKitCore.dylib`, `libKitLists.dylib`) that the app must then ship. It prints a
    spurious "'KitLists' is missing a dependency on 'KitCore'" warning. When a second app in the same package uses
    only the dynamic product, **6.4's SwiftPM fails to link that second app** (undefined KitCore symbols) and
    **xcodebuild fails the build** ("Multiple commands produce '…/KitCore.framework'"), both measured. The conversion
    also turned every *other* app in that package into a dylib-linked app.
  - This needs a user to build a dynamic library out of TUIkit, which a terminal app rarely does. It is possible
    today (a dynamic library from `TUIkit` plus the `TUIkitCore` product); C9b only adds more products to trip on.
    Static mixing already happens today too: an app on `TUIkit` and `TUIkitAppKit` links two products whose
    closures overlap (Package.swift:446–450), and E1 shows that is fine.
  - Untested: an `.xcodeproj` app with an embedded framework or app extension that also links TUIkit products
    (Xcode's own version of this mix). Only `xcodebuild` on packages was tried.

### Downsides and trade-offs, checked

| # | Trade-off | Verdict | Evidence |
|---|---|---|---|
| 1 | Ergonomics: several imports, and the user must know which module has what | Real. The compiler names the module only if it is already loaded and the user has MemberImportVisibility on; a missing product never gets a hint. Mitigations: a generated "which module" table (works); unavailable stubs, which help a `*Style` modifier only if they mirror every built-in style name (about 28 in TUIkit), and help no type name | §E2, §E2b, §E6 |
| 2 | Forgetting a **product** gives "value of type 'Text' has no member 'tableStyle'" / "cannot find 'Table' in scope", with no module named | Real, on every toolchain, language mode and MemberImportVisibility setting | §E2 |
| 3 | Module and product names become public API | Real. A product rename breaks the user's graph load, and the README's `branch: "main"` install (README.md:181; project-template/tuikit:415) delivers it on the next update; so would `from:` inside 0.x. Saved `NavigationPath`s and `String(reflecting:)` change on any move **for umbrella users too** (true today, without C9b) | §E4 |
| 4 | A module move breaks à-la-carte imports | Only moves sideways or upward. A move **down** the DAG (into a module every leaf re-exports) breaks nobody's imports, and even `OldModule.Type` qualified names keep resolving through the re-export | §E4 |
| 5 | CI must build each product alone | Partly covered: 6.4 SwiftBuild failed all five clean runs on an undeclared module dependency, and so did 6.2.4 native (six of six); `--explicit-target-dependency-import-check error` names the cause on 6.2. The macOS swift.org 6.4 lane runs that toolchain; the Linux and Xcode 27 lanes' build system is unchecked. Missing: a consumer fixture with one tiny app per product, about one TUIkit build | §E5 |
| 6 | Docs: a "which module provides X" table | Generatable from the symbol graphs the docs job already dumps (prototype works on the miniature) | §E6 |
| 7 | Xcode's Add Package dialog | 7 library products today → 24–25 with C9b and a Foundation product (count) | §E7 |
| 8 | 6.4: +16–33 KB per module in the link until SwiftPM's prelink fix | Established in SIZE3, not reproduced here (the miniature is inconclusive). Paid per module an app links, so an à-la-carte app pays less of it; it argues against finer products, not against C9b | §E8 |
| 9 | Third-party libraries on the umbrella erase the saving for their users | Measured. Guidance: libraries depend on leaves | §E1 |
| 10 | User-built dynamic libraries plus a static TUIkit product | Duplicate modules on native; surprise dylibs on SwiftBuild, and a link failure (6.4 SwiftPM) or build failure (xcodebuild) when a second app uses the dylib alone. `.xcodeproj` embedded frameworks untested | §E3 |
| 11 | Undeclared dependencies that work by accident | MemberImportVisibility's fix-it can name a module the app reaches only through a third party; adding that import builds on 6.2.4 and 6.4.0 without declaring the product | §E2 |
| 12 | Runtime and baseline memory | Static: same machine code expected; launch and resident memory possibly lower (hypothesis). Unmeasured: **timing owed** | §1 |
| 13 | User compile time | Hello compiles 11 of 29 modules, 57.2 of 86.9 MB of objects (−34%; SIZE3, estimate). Unmeasured: **timing owed** | §1 |

### What I would do

1. Ship C9b as purely additive: keep `TUIkit` the default in the README, add the per-module products **and one for
   TUIkitFoundation** (the base every leaf re-exports, for component libraries that need no leaf; E7's "+1"), and an
   "à la carte" page.
2. In that page: libraries depend on leaf products or `TUIkitFoundation`, never on `TUIkit`; the product list, not
   the imports, decides what is built (and correct the README tip, README.md:194); never build a dynamic library from
   TUIkit and also link a TUIkit product statically. Pinning: the README and the project template install
   `branch: "main"`, so every change on main reaches users at their next update. Advice to pin
   `.upToNextMinor(from:)` until 1.0 needs a versioned install path first (tags v0.2.0–v0.6.0 exist; the README does
   not use them), and it is not specific to à-la-carte users: 0.x breaks API for umbrella users too (no compatibility
   shims before 1.0). What C9b adds is one more kind of break, product renames, that only à-la-carte users see.
3. Generate the "which module provides X" table in the docs job, from the graphs it already dumps (§E6). Unavailable
   stubs are optional: for the `*Style` modifiers they work only by mirroring every built-in style name, and a missed
   name gives a worse error than none (§E2b).
4. CI: one consumer fixture, one tiny app per product, versioned, without any dynamic product (§E5).
5. Keep boundaries stable once products ship: prefer moves down the DAG, and treat a product rename as breaking.
6. Owed, on a quiet box: Hello on `TUIkitApp` vs on `TUIkit`, for the user's build time, launch time and
   `phys_footprint`.

## Evidence

### E1. Mixing: builds, copies and sizes (probe 1, measured)

Packages `pkgs/AppsStatic` (8 apps, all Swift 6 mode with MIV on), `pkgs/LeafOnly`; scripts `tools/apps.sh`,
`tools/xcb.sh`; logs `logs/AppsStatic-{x624,s640,xcb}.txt`, `logs/Apps-{s640n,s633}.txt`, `logs/LeafOnly-{x624,s640}.txt`.

Stripped size (`strip`) in bytes, and as a share of the umbrella app on the same toolchain:

| App | depends on | 6.2.4 native | 6.4.0 SwiftBuild | xcodebuild 26.3 | share |
|---|---|--:|--:|--:|--:|
| LeafApp | KitLists | 335,384 | 319,384 | 316,232 | 36–39% |
| ThirdPartyLeafApp | KitLists + a third-party lib on KitLists | 335,720 | 336,136 | 316,472 | 38–39% |
| UmbrellaApp | Kit | 877,000 | 877,528 | 818,328 | 100% |
| UmbrellaDepLeafImport | Kit, but `import KitLists` only | 877,016 | 877,528 | 818,328 | 100.0% |
| MixTargetsApp | Kit; a library target of the app on KitLists | 877,256 | 877,704 | 818,536 | 100.0% |
| MixFileApp | Kit + KitLists; one file imports both | 877,016 | 877,528 | 818,328 | 100.0% |
| ThirdPartyMixApp | Kit + a third-party lib on KitLists | 877,336 | 877,768 | 818,584 | 100.0% |
| LeafAppUmbrellaThird | KitLists + a third-party lib on Kit | 877,128 | 877,560 | 818,392 | 100.0% |

- **Each module once.** Every app defines KitCore's `RenderCache` type descriptor exactly once (`nm -m`; the only
  descriptor counted, `tools/apps.sh:39`), and every app's own code and its library's code report the same address
  for `KitGlobals.counter`, the same cache object, and `is List` true across the boundary. No duplicate-symbol
  errors, no duplicate-class warnings. Same on 6.3.3 and on 6.4.0 `--build-system native` (umbrella 860,424 B, leaf
  318,808 B).
- **Unused leaves are not compiled.** `LeafOnly` (a root package whose only app depends on `KitLists`) compiled
  exactly KitCore, KitLists and the app on both 6.2.4 and 6.4.0 (`-module-name` in the `-v` logs). KitTables, KitMenus
  and the umbrella target were never compiled.
- **The redundant `import Kit` + `import KitLists`** (MixFileApp, Swift 6 mode, MIV on) produces no diagnostic. MIV
  off is more permissive, so it very likely holds there too (hypothesis; not tried).
- The miniature's leaves are equal-sized by construction, so the 36–39% is the miniature's, not TUIkit's. TUIkit's
  own numbers are SIZE3's (Hello −35.3%).

### E2. What an à-la-carte user sees after forgetting an import (probe 2, measured)

Package `pkgs/Diag` (generated by `tools/gendiag.py`), 6 scenarios × Swift 5 and 6 language modes × MemberImportVisibility
off and on = 24 targets; `tools/diag.sh`; logs `logs/diag-{x624,s640}.txt`. **6.2.4 and 6.4.0 print identical
diagnostics** (compared after stripping colour codes and the build-system wrapper lines). **The language mode changes
nothing**; only MemberImportVisibility (MIV) does.

| Scenario | MIV off | MIV on |
|---|---|---|
| S1: product not in `Package.swift` (uses KitTables' `.tableStyle()` and `Table`) | `error: value of type 'Text' has no member 'tableStyle'` and `error: cannot find 'Table' in scope` | same, no module named |
| S2: product declared, another file of the target imports KitTables, this one does not | **the modifier compiles silently** (leaks from the other file); `Table`: "cannot find 'Table' in scope" | `error: instance method 'tableStyle' is not available due to missing import of defining module 'KitTables' [#MemberImportVisibility]` + `note: add import of module 'KitTables'` (a fix-it); `Table`: "cannot find 'Table' in scope" |
| S3: product declared, no file imports KitTables | "has no member 'tableStyle'", no module named | same |
| S4: KitLists reached only through a third-party library's plain `import KitLists` | **modifiers compile silently**; `List`: "cannot find 'List' in scope" | "not available due to missing import of defining module 'KitLists'" and the same for `'KitCore'` (`render()`), each with an "add import" fix-it; `List`: "cannot find" |
| S5: S4 plus `import KitLists`, still no KitLists product | **builds** (rc 0), all four variants, both toolchains | **builds** |
| S6: control, `import Kit` | builds | builds |

- **The fix-it names the module only for members, and only when that module is already loaded** (S2, S4). A type
  name (`Table`, `List`) never gets a hint, and a missing *product* (S1, S3) never does.
- **S5 is a trap:** following the S4 fix-it gives an import of a module the app never declared. It builds on both
  build systems, and breaks the day the third-party library drops its dependency.
- An app that imports any TUIkit leaf sees all of TUIkitFoundation's members, since every leaf re-exports it; S4's
  `KitCore` error arises only through a third party's plain import.

### E2b. Unavailable stubs in the base module: they help a modifier only if the stub can type the argument (measured)

Three probes; in each, 6.2.4 and 6.4.0 agree, with MIV off and on.
- **Original** (`pkgs/Stub`, `logs/stub-{x624,s640}.txt`): stub `tableStyle(_ style: Int = 0)`, called with no
  argument, gives the stub's message. That is not TUIkit's signature.
- **Generic** (the critic's, `CRIT/C9B/genstub`, `CRIT/C9B/probe.log:3–48`): TUIkit's style modifiers are generic over
  a protocol of their leaf (`tableStyle<S: TableStyle>`, Sources/TUIkitTables/Styles/TableStyle.swift:249; `listStyle`,
  `menuStyle`, `pickerStyle`, `tabViewStyle`, `textFieldStyle`, `formStyle` likewise), which a stub in TUIkitFoundation
  cannot name. With a stub `tableStyle<S>(_:)`, the usual `.tableStyle(.bordered)` without the product gives
  `cannot infer contextual base in reference to member 'bordered'`, and the stub's message never appears. It appears
  only for an argument whose type the user can name (`tableStyle(n)` with an `Int`).
- **Mirrored names** (new, `pkgs/Stub2`, `pkgs/Stub2/run.sh`, `logs/stub2.txt`): the base module declares
  `struct _TableStyleNotImported` with an unavailable `static var bordered`, and an unavailable
  `tableStyle(_: _TableStyleNotImported)`.

| Client (mirrored-name stub) | Result |
|---|---|
| no STables, `.tableStyle(.bordered)` | `error: 'tableStyle' is unavailable: tableStyle(_:) is in STables: add the STables product and `import STables`` (and the same error on `'bordered'`) |
| no STables, a style name the stub does not mirror (`.fancy`) | `error: type '_TableStyleNotImported' has no member 'fancy'`: worse than no stub, since it names an internal type |
| imports STables, or the umbrella, or both modules; `.bordered`, `.fancy` or `BorderedTableStyle()` | builds: the available real declaration wins, no ambiguity |
| STables imported by another file only | MIV on: MIV's "not available due to missing import of defining module 'STables'" on both `tableStyle` and `bordered`; MIV off: builds (the leak of E2 S2) |
| an unavailable **type** stub (`struct Table` with only an `init`; original probe) | its message did **not** appear; the error was "value of type 'Table' has no member 'render'". A type stub would need the real type's surface (hypothesis) |

- So stubs can close the S1/S3 hole for a modifier only when the stub can type the user's argument: arguments of
  standard-library or base-module types and closures (the original probe's case), or, for the `*Style` modifiers, a
  mirror of every built-in style name. TUIkit has about 28 such names over the 7 style protocols (a grep of
  `extension …Style where Self ==`; estimate). Each mirror is a second declaration to keep in step, and a missed one
  gives the worse error above. Type names (`Table`, `List`) stay unhelped.
- Cost: one public stub per leaf modifier, plus one mirror type per style protocol, in TUIkitFoundation; noise for
  DocC and Tools/APIParity to filter. Umbrella users never see a stub. How code completion treats the mirror types is
  unchecked (no IDE).

### E3. A user's own dynamic product (probe 3, measured)

Packages `pkgs/DynLib` (`.library(name: "KitDyn", type: .dynamic, targets: ["KitShared"])`, KitShared depends on the
umbrella and re-exports it), `pkgs/AppsDynOnly` (an app on KitDyn only), `pkgs/AppsDynMix` (an app on KitDyn plus the
KitLists product statically), `pkgs/AppsDynBoth` and `pkgs/Apps` (both apps in one package; `Apps` also holds the
eight static apps). Logs `logs/AppsDyn{Only,Mix}-{x624,s640,xcb}.txt`, `logs/AppsDynBoth-{x624,s640}.txt`,
`logs/Apps-{x624,s640,s640n,s633}.txt`, and `logs/dyncheck.txt` (the xcodebuild AppsDynBoth run and the two-copies
detail).

| Build | DynOnlyApp (dylib only) | DynMixApp (dylib + static leaf) |
|---|---|---|
| 6.2.4 / 6.3.3 / 6.4.0 native | one copy, in the dylib; works | **two copies** of KitCore and KitLists (the app is 335 KB stripped, as large as LeafApp, beside the 1.26 MB dylib that holds them too); ObjC "Class _TtC7KitCore11RenderCache is implemented in both"; a `List` made in the dylib is **not** `is List` in the app (the reverse is true) |
| 6.4.0 SwiftBuild, app alone in its package | one copy; works | SwiftBuild turns KitCore and KitLists into `libKitCore.dylib` and `libKitLists.dylib`; one copy; casts work; warning "'KitLists' is missing a dependency on 'KitCore' because dependency scan … discovered a dependency on 'KitCore'" |
| xcodebuild 26.3, app alone | one copy (KitDyn.framework) | same conversion, as `KitCore.framework` and `KitLists.framework`; one copy; same warning |
| 6.4.0 SwiftBuild, both apps in one package (`AppsDynBoth`) | **link fails**: undefined `KitCore.coreReport`, `KitGlobals.counter`, `List` metadata (the conversion took KitCore out of libKitDyn, and DynOnlyApp does not link libKitCore.dylib) | converted as above; works |
| 6.4.0 SwiftBuild, `Apps` (both, plus the eight static apps) | **link fails**, as above | not built: its link was interrupted after DynOnlyApp's failed (`logs/Apps-s640.log:1336–1338`) |
| xcodebuild 26.3, both apps in one package (`AppsDynBoth`) | **build fails** (rc 65): "error: Multiple commands produce '…/Frameworks/KitCore.framework'" (and KitLists) (`logs/dyncheck.txt:47–55`) | not built |
| native, both apps in one package | works | two copies, as above |

- In the 6.4.0 SwiftBuild `Apps` graph, **every other app** (UmbrellaApp, LeafApp, the mixes) was also linked against
  `libKitCore.dylib` and `libKitLists.dylib` instead of statically (`otool -L`): the conversion is graph-wide, and the
  user's command-line tools stop being self-contained.
- **Mechanism: hypothesis.** The 6.4.0 `swift-package` and `swift-build` binaries contain the diagnostics "… is linked
  as a static library by '…'. This will result in duplication of library code." and "…, but cannot be built
  dynamically because there is a package product with the same name." (`strings`), so SwiftBuild has a
  static-to-dynamic path. Neither was printed here, and KitCore was converted although it has a product of the same
  name (`pkgs/Kit/Package.swift:14`), so which rule SwiftBuild applied is not established.
- **Native's two copies, in detail** (`logs/dyncheck.txt`, 6.2.4): both images define and export
  `KitGlobals.counter`'s storage (`_$s7KitCore0A7GlobalsO7counterSivpZ`, `__DATA,__common`) and `RenderCache`. The
  dylib's own `coreReport` reaches the dylib's storage (`adrp x19, 0xac000; add x19, x19, #0x448`, its own
  `__DATA`). Yet the line the app printed for "KitShared (dylib)" named the **app's** storage, while a `List` built by
  `makeSharedList()` carried the **dylib's** metadata. The cause is **inferred from the measured call list of the
  app's `main`** (`logs/cmo.txt`): `main` calls `KitCore.coreReport` directly, twice, and references only one
  KitShared symbol from the dylib, `makeSharedList()`. SwiftPM's release builds pass `-enable-default-cmo` (7 compile
  lines in `logs/AppsDynMix-x624.log`), so the small `sharedReport()`, `bumpFromShared()` and `sharedSeesList(_:)`
  were most likely inlined into the app and ran against the app's copy of KitCore, while `makeSharedList()` ran in
  the dylib. (cmo.txt's check of whether their bodies were serialized was inconclusive: swift-ide-test unavailable.)
  **Which copy a call uses then depends on the optimiser's inlining.**
- **For TUIkit (hypothesis by analogy):** two copies would split every type-keyed registry and every `as?` check
  between the dylib's views and the app's, and duplicate global caches, with the split moving as inlining changes.
- **Advice:** a user who wants TUIkit in a shared dynamic library should depend on TUIkit only through that library
  (DynOnlyApp works on every build system when alone), and never also link a TUIkit product statically. Untested:
  an `.xcodeproj` app whose embedded framework or app extension also links TUIkit products.

### E4. Names become API (measured where marked)

- **A product rename reaches users with no warning (measured, `pkgs/Ver`, `pkgs/VerClient`, 6.2.4 and 6.4.0).** A
  client with `from: "0.6.0"` resolved to 0.7.0, whose only change was renaming the product, and then failed to load:
  `error: 'verclient': product 'VerLists' required by package 'verclient' target 'VerClient' not found in package
  'Ver'.` The original run's log was not saved; the critic's re-run on both toolchains, with the same result, is
  `CRIT/C9B/probe.log:49–60`. SwiftPM's `from:` is up-to-next-major, and resolution does not check product names.
- **What that means for TUIkit (established).** The README (README.md:181) and the project template
  (project-template/tuikit:415) install with `branch: "main"`, so today every change on main, a product rename
  included, reaches users at their next `swift package update`, whatever the pinning advice says. Pinning
  `.upToNextMinor(from:)` helps only once the README offers a versioned install (tags v0.2.0–v0.6.0 exist). It is not
  à-la-carte advice: 0.x API changes reach umbrella users too (no compatibility shims before 1.0). Product renames
  are the extra break only à-la-carte users see.
- **Moving a type between modules (measured, `pkgs/Moved`, 6.2.4 and 6.4.0).** `RouteB` moved from MovedOld to
  MovedNew, with MovedOld re-exporting MovedNew:
  - `_mangledTypeName` becomes `8MovedNew6RouteBV` and `String(reflecting:)` `MovedNew.RouteB`; a saved
    `_typeByName("8MovedOld6RouteBV")` returns `nil`. **That is what `NavigationPath.codable` stores**
    (Sources/TUIkitNavigation/Views/NavigationPath.swift:186, documented at :172–180), so a saved path holding a
    TUIkit type stops decoding **for umbrella and à-la-carte users alike**. It is a consequence of the module split
    (true today), not of C9b.
  - `MovedOld.RouteB` (a qualified name through the old module) still resolves.
  - `@_originallyDefinedIn(module: "MovedOld", macOS 14)` with `@available(macOS 14, *)` keeps the old mangled
    name, the old `String(reflecting:)` and the old `_typeByName` working. It is underscored, and Apple-platform
    only (on Linux it is a hypothesis that it does nothing).
- **Which moves break imports (established from the re-export structure).** Every leaf `@_exported import`s
  TUIkitFoundation. A type moved *down* into Foundation stays visible to every importer of its old module; one moved
  *sideways* (Lists → Tables) or *up* breaks an à-la-carte user who imported only the old module. Umbrella users see
  none of it.

### E5. CI cost of "each product alone" (probe, measured on `pkgs/KitBad`)

KitBad's `BadMenus` imports `BadLists` without declaring it. Logs `logs/bad-{x624,s640}.txt`.
- **6.4.0 SwiftBuild:** failed in all five runs (each from a clean scratch, whole package included), at dependency
  scanning before any compile (inference: so ordering cannot rescue it): `error: Sources/BadMenus/M.swift:2:8
  compilation search paths unable to resolve module dependency: 'BadLists'`. 6.4.0 *can* build a library product
  alone (`--product BadLists` built, rc 0).
- **6.2.4 native:** failed in all six clean runs (`no such module 'BadLists'`), including `--target BadMenus`, which
  never builds BadLists. Whether a whole build could ever pass because BadLists happened to be built first (native
  resolves modules through the shared Modules directory) is a **hypothesis**; no run passed. An incremental build
  where BadLists already exists would pass (hypothesis). `--explicit-target-dependency-import-check error` adds the
  precise `error: Target BadMenus imports another target (BadLists) in the package without declaring it a
  dependency.`
- `swift build --product <library>` cannot build a library product alone on 6.2.4 ("'--product' cannot be used with
  the automatic product 'BadLists'; building the default target instead", measured); use `--target`. (Package.swift
  :526 records the same for 6.2 and 6.3.)
- **TUIkit's CI (established, ci.yml).** No step passes `--build-system`, so each lane gets its toolchain's default.
  The macOS 26 swift.org 6.4 lane (ci.yml:252–259) runs the toolchain measured here, so it should catch an undeclared
  module dependency (inference). The Linux `swift:6.4-noble` and Xcode 27 lanes' default build system was not
  checked. The Windows lane's per-target steps (ci.yml:788–965) are not coverage: every step above the lower four is
  `continue-on-error: true` ("Expected to fail until the port lands"), and all run in one scratch directory.
  `Tools/ModuleMap` checks the layering.
- **So C9b adds a consumer smoke test:** one fixture package with one tiny app per product, as a versioned
  dependency. All apps share one build of TUIkit, so the cost is about one TUIkit build plus 17 small links
  (estimate), not 17 builds. It must not contain a dynamic product (§E3: SwiftBuild's conversion is graph-wide).

### E6. The "which module provides X" table can be generated (measured on the miniature)

- `tools/which_module.py` reads the directory `swift package dump-symbol-graph --minimum-access-level public` writes
  — the same graphs `Tools/BuildDocs/build-docs.sh:100` dumps for DocC. A graph `M.symbols.json` holds M's own
  declarations and `M@N.symbols.json` M's extensions of N's types, so the file name alone gives the providing
  module: `View.tableStyle(Int) -> some View → KitTables`, `View.padding() → KitCore`, `Table → KitTables`, `List →
  KitLists` (`logs/which-module-Kit.md`, 18 rows besides the generated bulk views; a protocol extension's members
  repeated on each conforming type are filtered by their `::SYNTHESIZED::` identifiers).
- TUIkit's docs deliberately erase the module (Tools/BuildDocs/unify_symbol_graphs.py rewrites every graph to
  `TUIkit`), so the table, or a "Module: TUIkitLists" line on each symbol page, has to be added at that step. The
  original module is known there (it is in the file name the script renames). Swift Package Index already builds one
  archive per module (.spi.yml).

### E7. Xcode's Add Package dialog (counted from Package.swift, no GUI)

- Today: **7 library products** (TUIkit, TUIkitAppKit, TUIkitCore, TUIkitImage, TUIkitMacros, TUIkitStyling,
  TUIkitView) and 6 executables (Example, Stress, EmojiBugScanner, EmojiBenchmark, RenderHarness, ImageHarness).
- With C9b: **+16 or +17** (the 17 leaves; Chrome is reached through App and Presentation, so it can stay
  product-less), **+1** for TUIkitFoundation (recommended above): **24 or 25 library products** (23 or 24 without Foundation's).
- Whether the dialog also lists the executables, and in what order, was not checked (no GUI).

### E8. 6.4's per-module link cost

- **Established, SIZE3/report.md:766:** "further carves cost 6.4 users about +16–33 KB each until SwiftPM keeps
  private externs" — SwiftBuild's per-module `ld -r` prelink gives each module its own copies of shared hidden weak
  definitions (report.md:387–399).
- It is paid **per module in the app's link**. The umbrella app links all of them; an à-la-carte app links fewer.
  So it is a cost of splitting further (finer products), not of C9b itself.
- **The miniature is inconclusive** (measured): the same extra module (the third-party ThirdWidget) costs +16,752 B on
  6.4.0 SwiftBuild in ThirdPartyLeafApp but +240 B in ThirdPartyMixApp; +320 B / +320 B on 6.4.0 and 6.3.3 native;
  +336 B / +336 B on 6.2.4; +240 B / +256 B under xcodebuild. 16,752 = 16,384 + 368 (arithmetic), so the one large
  delta is most likely a segment crossing a 16 KB page boundary (hypothesis), and a tiny module shares few hidden
  weak definitions anyway. The +16–33 KB rests on SIZE3 alone.

### E9. Other findings

- **The umbrella's own bytes vanish in an à-la-carte app** only if nothing depends on the umbrella (E1); a
  depended-on umbrella costs the full closure even if never imported.
- **xcodebuild produced 6–7% smaller binaries than `swift build`** for the same sources (818 vs 877 KB umbrella,
  −6.7%; 316 vs 335 KB leaf, −5.7%; measured); Xcode's release settings differ. Not investigated.
- **Linux: not measured** (no Linux runtime on this machine). SwiftPM's static link model is the same object-file
  link (hypothesis); the dynamic case differs, because ELF's flat namespace can interpose the app's exported
  symbols into the shared library (hypothesis).

## Files

- Packages: `C9B/pkgs/{Kit,ThirdParty,DynLib,AppsStatic,AppsDynOnly,AppsDynMix,AppsDynBoth,Apps,LeafOnly,Diag,KitBad,Moved,Ver,VerClient,Stub,Stub2}`.
- Scripts: `C9B/tools/{gen.py,gendiag.py,apps.sh,xcb.sh,diag.sh,bad.sh,moved.sh,symgraph.sh,which_module.py,stub.sh,dyncheck.sh,cmo.sh,run-all.sh}`, `C9B/pkgs/Stub2/run.sh`.
- Logs and reports: `C9B/logs/` (`*.txt` are the reports, `*.log` the full `-v` build logs; `stub2.txt` is the
  mirrored-name stub probe). The critic's probes: `CRIT/C9B/probe.log`.
