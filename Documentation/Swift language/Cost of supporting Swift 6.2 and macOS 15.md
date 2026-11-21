# Cost of supporting Swift 6.2 and macOS 15

This is the ledger of what TUI pays to keep its two floors, Swift 6.2 and macOS 15 Sequoia: code that exists only
for them, features it can't use, workarounds, duplicated tests and CI time. It exists so that dropping a floor can
be decided on data. Each row cites the code or the record it came from. A size is measured where it says so, and
"not measured" otherwise.

The two studies beside this one say what a rise would gain and what it would take on the day: [Raising the floor to macOS 26](<Raising the floor to macOS 26.md>)
and [Raising the minimum Swift to 6.4](<Raising the minimum Swift to 6.4.md>). This ledger is the running account
they draw on.

## The floors and the rule

**Where they are declared.**

- `Package.swift:1`: `// swift-tools-version: 6.2`. SwiftPM refuses the package on an older toolchain.
- `Package.swift:20-22`: `platforms: [.macOS(.v15)]`. Linux, WebAssembly and Windows have no deployment target.
- `.claude/CLAUDE.md`, "Compatibility": Swift 6.2 compatible, with language features up to 6.2 encouraged. Its CI
  list: macOS 15 and 26 with Xcode 26, macOS 27 with Xcode 27 and swift.org's 6.4 and trunk, Linux containers for
  6.2, 6.3 and 6.4 on arm64 plus 6.4 on x86_64, and Windows on 6.4 only.
- `.github/workflows/ci.yml:38-49`: the support matrix. Swift 6.2 is the `macOS 15 · Xcode 26` lane (`ci.yml:333`)
  and `Linux · Swift 6.2 · arm64` (`ci.yml:879`). Swift 6.3 is `macOS 26 · Xcode 26` (`ci.yml:354`) and `Linux ·
  Swift 6.3 · arm64` (`ci.yml:886`).
- `CONTRIBUTING.md:22` and `:286-294`: Swift 6.2 or newer, and on macOS the macOS 26 SDK, from Xcode 26 or Command
  Line Tools 26. The macOS 15 SDKs (Command Line Tools 16.x) cannot build TUI (the owner's ruling of 2026-11-19); a
  macOS 15 deployment target, built with the 26 SDK, is supported and runs on macOS 15.

Each macOS carries its own Swift runtime: macOS 15.0 has Swift 6.0's, 15.4 has 6.1's, 26.0 has 6.2's and 26.4 has
6.3's. So the two floors are separate costs. The compiler floor decides syntax, compiler bugs and attribute
spellings. The macOS floor decides which standard-library and Foundation APIs exist at run time, whatever the
compiler.

**The owner's rule (2026-11-17).** Stay mindful of significant problems that supporting Swift 6.2 and macOS 15
Sequoia causes. Dropping them has no fixed date. It depends on how much keeping them costs (development time,
complexity, a worse experience), and the owner wants that decision to rest on data. This ledger is that data.

**What a drop would take.** The [API stability policy](<../API stability policy.md#minimum-swift-and-macos>)
(decision B, owner 2026-11-09) lets only a major release raise a minimum Swift or macOS. Before 1.0 any release
may. After 1.0, a drop waits for 2.0.

## The ledger

Floors: **macOS 15** means the macOS 15 runtime, so it goes with a macOS 26 deployment target. TUI builds only with
the macOS 26 SDK; the macOS 15 SDK's own rows (S1 to S5) ended on 2026-11-19 (see "What has already been paid
down"). **6.2** means the compiler, and goes with a 6.3 minimum. **6.2 and 6.3** goes only with a 6.4 minimum.

### Runtime and Foundation (macOS 15)

| # | What | Where | Floor | Kind | Size | Dropping it would | Found |
|---|---|---|---|---|---|---|---|
| M1 | The attributed text selection's fallbacks. macOS 15's Foundation has no `isValid(within:)`, no index tracking (`transform(updating:body:)`), no `removeSubranges(_:)` and no `AttributedString` UTF-8 view. Linux and Windows have all of them. | `Sources/TUITextInput/AttributedText/AttributedTextSelection+MacOS15Fallbacks.swift`; the `else` arms at `AttributedTextSelection.swift:258` and `AttributedString+AttributedTextSelection.swift:44, :111, :159`; G3 design §9 | macOS 15 | Fallback code; behaviour | 229 lines (111 of code). **Behaviour:** a stale index that falls inside the text counts as valid; several disjoint changes in one body are tracked as one span; tracking a change costs 2.6 to 2.9 ms on a 3.07 MB text (measured, macOS 15.8.3) | Delete the file and the four arms; exact validity and tracking everywhere | 2026-11-17 (G3 L3) |
| M2 | The same fallbacks, tested twice: each case runs through the platform's path and through the fallback called directly, and the Foundation comparisons skip on macOS 15. | `Tests/TUITextInputTests/AttributedStringSelectionEditTests.swift:7-8, :24, :117, :223, :286`; `AttributedTextSelectionTests.swift:98, :110` | macOS 15 | Test duplication | The two files have 493 lines; the fallback's share is not measured | Delete the direct-fallback tests and the guards | 2026-11-17 |
| M3 | `Span` over a standard type: `Array.span`, `String.utf8.span`, `UTF8Span`. All are macOS 26 on every compiler, so hot byte loops stay on unsafe buffer closures. | 87 `withUnsafe(Mutable)BufferPointer` calls in `Sources` (grep, 2026-11-17); the 6.4 study's table | macOS 15 | Forgone feature | **Behaviour, not speed:** a `Span` measured 15 to 70% slower than the buffer it replaces in a micro-benchmark, and 0 to 4% in TUI's prototypes (6.4 study). The gain is bounds checking and fewer `unsafe` sites | Bounds-checked buffers in hot code, each move A/B'd | 2026-11-08 (6.4 study) |
| M4 | `libswiftCompatibilitySpan.dylib`. Below macOS 26 any `Span`-family type in unspecialised generic code, or in a dependency, links a toolchain library. A program copied out of `.build` then stops at launch on macOS 15, with no build error or warning. | `Tools/check-span-compatibility.sh`; CI step `ci.yml:705-721`; `CONTRIBUTING.md:86` | macOS 15 | Workaround; CI cost | The script is 227 lines and 7 commits, plus 14 commits that mention the check. The CI step took 9 s on the development machine on 2026-10-12 (runners not measured). **Behaviour:** every use of a `Span` type, and every new dependency, has to pass it | Delete the script and its CI step; `Span` usable in generic code | 2026-10-10 (914137ed6) |
| M5 | Stdin's byte queue is TUI's own, not swift-collections' `UniqueDeque`, because `DequeModule` linked the library in M4. TUI no longer depends on swift-collections (965a4884b, 2026-10-20). That commit does not say whether M4 was its only reason. | `Sources/TUIApp/Rendering/InputByteBuffer.swift:22-28` | macOS 15 | Forgone dependency; workaround | 305 lines, a hand-written deque | Allow swift-collections 1.4 or later again, if wanted | 2026-10-10 |
| M6 | `InlineArray` is macOS 26, though `.claude/CLAUDE.md` tells contributors to use it freely. The terminal palette is a 16-tuple instead, and the type walk's conformance is gated. | `Sources/TUIStyling/Color/TerminalColors.swift:60-63`; `Sources/TUIView/Rendering/TypeWalk.swift:68`; tests skip at `Tests/TUIViewTests/TypeWalkTests.swift:197` and `Tests/TUIIntegrationTests/ValueHashPlanTests.swift:549` | macOS 15 | Forgone feature; version gate | Small: one tuple type, one `@available`, two guards. The two tests cannot run on the development machine (macOS 15), and were checked under WebAssembly instead | Plainer code; CLAUDE.md's advice holds on Apple | 2026-09-14 (the tuple) |
| M7 | Task names: `task(name:)` is accepted everywhere, but on macOS 15 the runtime has no task names, so the name is dropped. | `Sources/TUIFoundation/Environment/TUIContext.swift:262`; the doc comments at `Sources/TUIFoundation/Extensions/View+TaskExecutor.swift:34, :78`; `Tests/TUIAppTests/NamedTaskTests.swift:20, :26` | macOS 15 | Version gate; behaviour | 4 lines and two doc sentences. **Behaviour:** a debugger or Instruments shows no names on macOS 15 | Names everywhere; the gate and the caveat go | by 2026-10-24 (b21a6ebda) |
| M8 | `#expect` comparing a metatype with `nil` is a SIGSEGV on the macOS 15 runtime. It kills the whole test process and fails no test. | `CONTRIBUTING.md:723-728`; `Tests/TUIFoundationTests/DynamicPropertyTests.swift:522` | macOS 15 | Workaround; test rule | A rule every test author has to know, and two tests rewritten | Delete the rule after checking it on macOS 26 | by 2026-11-01 |
| M9 | Markdown's content type: macOS 26 dropped four extensions and MIME types that macOS 15 declares, so the test expects either. | `Tests/TUIFilePanelsTests/ContentTypeTableTests.swift:27-33` | macOS 15 | Test duplication | 4 lines. The table keeps the entries for Linux whatever happens | Drop the `else` | not recorded |
| M10 | `Task.immediate` (macOS 26) could replace part of `ActivationHold`, which lets a task an action started reach its first suspension before a frame draws. | the macOS 26 study's table | macOS 15 | Forgone feature | Not measured; inferred, never tried | Possibly a simpler `ActivationHold` | 2026-11-01 (macOS 26 study) |
| M11 | A paragraph's alignment in an `AttributedString`. On the macOS 26 SDK `alignment` is Core Text's own (the owner's ruling attralign, 2026-11-19), so before macOS 26 a program cannot set it, as in SwiftUI. TUI adds `paragraphAlignment`, its own attribute under a name SwiftUI does not use, which draws on every macOS, and draws `alignment` where it exists and `paragraphAlignment` otherwise. | `Sources/TUIFoundation/Views/AttributeScopes+CoreText.swift` (the attribute, its subscript and `drawnParagraphAlignment`); `Tests/TUITestSupport/ParagraphAlignmentSpelling.swift`; G3 design §5 | macOS 15 | Fallback API; behaviour; test duplication | About 40 lines of fallback (the attribute, its subscript, the read). **Behaviour:** a program that runs on macOS 15 writes TUI's spelling, which a SwiftUI build of the same file does not have. The alignment tests run twice where both spellings exist (11 cases), and on macOS 15 only through the fallback, so the development machine never runs Core Text's spelling: CI's macOS 26 lane does | Delete `paragraphAlignment` (pre-1.0, or deprecate it to the next major); `alignment` alone, as in SwiftUI | 2026-11-19 |
| M12 | A paragraph's line height in an `AttributedString`. On Apple platforms `lineHeight` is Core Text's own (the owner's ruling A-ATTRED-13 (b), 2026-11-19), so before macOS 26 a program cannot set it, as in SwiftUI, and TUI adds no attribute of its own: a paragraph on macOS 15 has no line height. | `Sources/TUIFoundation/Views/AttributeScopes+LineHeight.swift` (the attribute, its subscript, `drawnRows`, `drawnLineRows`); `TextEditorHandler.lineRowsOfRun`; G3 design §5 | macOS 15 | Forgone feature; test duplication | No fallback code. **Behaviour:** none on macOS 15 to draw. The drawing tests run there only through `Text`'s runs and an attribute of the tests' own read through the editor's `lineRowsOfRun` seam (`RichTextEditorLineHeightTests`, which also runs every case through `lineHeight` where it exists); the development machine never runs Core Text's spelling: CI's macOS 26 lane does | Nothing to delete; `lineHeight` on every supported macOS, and the tests' own attribute could go | 2026-11-19 |

### The Swift 6.2 compiler

| # | What | Where | Floor | Kind | Size | Dropping it would | Found |
|---|---|---|---|---|---|---|---|
| C1 | swift.org's 6.2.4 (an assertions build) aborts on a `@preconcurrency` conformance of a type with a parameter pack. `TupleView` spells its `Equatable` conformance `@MainActor` instead, unlike every other view. It also asserted in the Linux static-SDK and WebAssembly builds. Fixed in 6.3.3. | `Sources/TUIView/Core/TupleViews.swift:72-81`; `Tools/CompilerBugs/README.md` §3 and `Tools/CompilerBugs/PackPreconcurrencyConformance/` | 6.2 | Workaround | One declaration, plus a repro kept to retest | One spelling for every view; the repro goes | 2026-09-14 (9ca2fd8ea) |
| C2 | swift.org's 6.2.4 aborts converting a function with an opaque result in a generic context. The navigation bar's crumb trail takes one closure parameter instead of destructuring the pair. Fixed in 6.3.3. | `Sources/TUINavigation/Views/NavigationBar.swift:208-212`; `Tools/CompilerBugs/README.md` §4 and `Tools/CompilerBugs/GenericOpaqueResultConversion/` | 6.2 | Workaround | One closure, plus a repro | The natural spelling; the repro goes | 2026-09-14 (8e51390e1) |
| C3 | Strict memory safety is checked only on 6.4. 6.2 and 6.3 want an `unsafe` on a call whose closure takes an unsafe type, and 6.4 warns about that same `unsafe`, so no single spelling is clean on both. The package turns the check on from 6.4, and source that must compile cleanly everywhere carries both spellings. Outside that one shape 6.2.4 and 6.4.2 agree on what is unsafe (measured 2026-11-19 on reductions of each shape below), and both warn of a needless `unsafe` without the flag, so a marker 6.2 calls needless fails the local gate while a missing one passes it unseen. Marking a closure-taking call as 6.4 wants (no `unsafe` on the call, one inside the closure: `String+CursorCompensation.swift`, `TableColumnSpec.swift`) is therefore clean on every lane. **2026-11-19:** a clean build of main with 6.4.2 gave 36 warnings, all in code written from 2026-11-15 on and built since only by the 6.2.4 gates: the measure memo's keep (`PassValueKeep`), the reads of `@exclusivity(unchecked)` `RenderCache.rowWork` and `measuredValues`, `CountCheck`'s `setenv`, the attributed selection's macOS 15 fallbacks, `isIdentical`'s `MemoryLayout<UnsafeRawPointer>` and a table's contiguous rows. Not a 6.4.1 or 6.4.2 change: 6.2.4 with the flag flags every one of those shapes too, and the same shapes were marked when 6.4.0 first checked (52db9548e, 353987bcb). 6.3 was not run: it shares 6.2's reading of the closure shape, no marker added is on that shape, and the one taken off (`PassValueKeep`'s `withUnsafePointer`, which 6.4.2 called needless) is one a lane without the flag never asks for. | `Package.swift:1281-1299`; `Sources/TUITextInput/Focus/EditorLayout.swift:388-398` | 6.2 and 6.3 | Version gate; forgone feature | One `#if` in the manifest, one in source so far. **Behaviour:** local gates (Xcode's 6.2.4) never check memory safety; only CI's 6.4 lanes do | One spelling; the check on every lane. A 6.3 minimum does not remove this | 2026-11-07 (c75b43ca7) |
| C4 | Three compiler lines resolve overloads differently. `_printChanges` passed typed pointers that 6.2 converted to raw and 6.3 and 6.4 compared as values. Four tests failed on every 6.3 and 6.4 lane from the day they were added, while the local gates, which build with 6.2, passed. | 01a80f6c4 (CI run 99) | 6.2 (and 6.3) | Test duplication; CI cost | One fix. **Behaviour:** a class of failure only multi-compiler CI finds, found days late | Fewer compiler lines to diverge; local gates on the compiler TUI targets first | 2026-11-09 |
| C5 | 6.3's official attributes: `@inline(always)`, `@export(implementation)`, `@specialized` and `@c`. 6.2 has only the underscored forms. | 115 `@inline(__always)` and 76 `@_alwaysEmitIntoClient` in `Sources` (grep, 2026-11-17) | 6.2 | Forgone feature (spelling) | No code-generation difference (6.4 study) | Official spellings | 2026-11-08 (6.4 study) |
| C6 | Safe ways to fill a new array or read bytes: `Array(capacity:initializingWith:)` (6.3), `withTemporaryAllocation`'s `OutputSpan` (6.4), a safe `RawSpan.load` and `bitCast` (6.4). | 14 `Array(unsafeUninitializedCapacity:)` calls in `Sources` (grep, 2026-11-17); the image decoders | 6.2 (and 6.3 for the 6.4 ones) | Forgone feature | **Safety, not speed:** the `OutputSpan` prototype was about 4% slower (6.4 study) | Fewer `unsafe` sites in the image pipeline | 2026-11-08 (6.4 study) |
| C7 | The type-check budget is counted per compiler, and 6.2.4 counts far more solver scopes for ordinary code than 6.4. Its lane runs at 2,000 against 6.4's 1,500, so expressions that are cheap on 6.4 have to stay under 6.2's cap. 6.2's two worst sites are under 300 on 6.4. | `ci.yml:787-858`; `CONTRIBUTING.md:87` | 6.2 | CI cost | One build of the library on the macOS 15 lane (time not measured). 6.4 type-checks the library's function bodies 13 to 17% faster than 6.2.4 ([Compile time and the test targets](<../Historical/Module split, compile time and binary size/Compile time and the test targets.md>)), which an app on 6.2 pays | One cap, on 6.4 | 2026-10-07 |
| C8 | Address folding with `-Xlinker -deduplicate` is the compiler's answer, and Xcode's 6.2.4 folds a pair that 6.4.0 does not. So the dedup check runs on the 6.2.4 lane too, after a release build of its own. | `ci.yml:741-756` | 6.2 | CI cost | About 10 minutes a run: 187 s of release build, 9 s of Span check and 384 s of dedup check on the development machine, 2026-10-12 (runners not measured) | 10 minutes a CI run | 2026-10-12 (e1b8e384f) |
| C9 | macOS's native build on 6.2 lets an import of an undeclared package module through, which 6.4's links and the WebAssembly build fail. A validator catches it before any build. | `Tools/validate-target-imports.py`; `ci.yml:160-165`; `CONTRIBUTING.md:819-824` | 6.2 | Workaround | Seconds a run. The validator would probably stay as a fast check | Little | 2026-11-10 (ed42d2f4b) |
| C10 | swift-syntax's range starts at 602, Swift 6.2's line, so the Linux 6.2 lane pins it there to build `TUIMacros` against the oldest version in range. An app on 6.2 that wants swift-syntax prebuilt pins 602.0.0 itself. | `Package.swift:204-218`; `ci.yml:935-945` | 6.2 | Dependency constraint; CI cost | One CI step | A higher floor for the range; the pin step goes | decision B-D6M-2 |
| C11 | 6.3's `-O` pipeline drops a nested function's actor isolation when it clones it, and fails the release build. Theme's notes are typed `& Sendable` for that compiler alone, and a Linux 6.3 lane builds in release to catch the next one. | `Sources/TUIFoundation/Styling/Theme.swift:228-239`; `ci.yml:974-989` | 6.2 and 6.3 (6.3 is inside any floor below 6.4) | Workaround; CI cost | One annotation and one release build (time not measured) | The annotation and the 6.3 release build | 2026-10-08 (fed3b535e) |

### CI lanes (both floors)

| # | What | Where | Floor | Kind | Size | Dropping it would | Found |
|---|---|---|---|---|---|---|---|
| L1 | The lanes that exist for the floors. Swift 6.2: `macOS 15 · Xcode 26` and `Linux · Swift 6.2 · arm64`. macOS 15: the same macOS lane. Swift 6.3, which any minimum below 6.4 implies: `macOS 26 · Xcode 26` and `Linux · Swift 6.3 · arm64`. | `ci.yml:333, :354, :879, :886` | both | CI cost | 2 lanes for a 6.3 or macOS 26 floor, 4 for a 6.4 floor. Runner minutes not measured | Fewer runs per push. The macOS 15 lane's own steps (module map, API baseline, warnings check, type-check budget, dedup check) would move to another lane, not vanish | 2026-11-17 |

### What has already been paid down

- **macOS 14 to 15** (November 2026, [Raising the floor to
  macOS 15](<../Historical/Swift language and platforms/Raising the floor to macOS 15.md>)): `Mutex`, `Atomic`, `String(validating:)` adopted, every macOS 15 gate deleted, and
  the `@unchecked Sendable` and `nonisolated(unsafe)` lines down from about 147 and 74 to 8 and 4 declarations.
- **The macOS 15 SDKs declared unsupported** (SDK15-CI (c), 2026-10-26, 4c1ec10f9): the guards for task names,
  `InlineArray` and the named-task tests on that SDK were deleted. Rows S1 to S3 came back later, and S4 and S5
  joined them, until the SDK went for good (below).
- **Windows on Swift 6.4 only** (owner, 2026-11-16, 9c4948f6c): the port does not carry 6.2 or 6.3.
- **The macOS 15 SDKs no longer build TUI** (the owner's ruling of 2026-11-19): TUI needs the macOS 26 SDK, from
  Xcode 26 or Command Line Tools 26; the macOS 15 runtime is still supported, through a macOS 15 deployment target
  built with the 26 SDK, as CI's macOS 15 lane builds. Unsupported since 2026-10-26, that SDK had still been served
  in practice for a downstream app, tuitree, which moves to Xcode 26's SDK. The five rows it cost, and what became
  of each:
  - **S1, `UndoManager`** (2026-10-15, 1f49c77e9). The 15 SDK's `UndoManager` is not main-actor isolated and its
    handler is `@Sendable`, so the manager travelled as `MainActorUndoManager` and each handler hopped back with
    `MainActor.assumeIsolated`. The 26 SDK isolates the class to the main actor (so it is `Sendable`) and types the
    handler `@MainActor`, as TUI's own `UndoManager` off Darwin already did. The wrapper is gone; the status bar
    holds the manager itself, and the handlers in `TextUndoBridge`, `registerRestoring`, the Example's undo page and
    four test suites call their steps directly. The isolated step objects stay as the registration targets.
  - **S2, `fileExporter`'s `unsafeBitCast`** (2026-11-15, 34bd2840f). `Transferable` refines `Sendable` in the 26
    SDK, so `NSItemProvider.register(_:)` is called plainly: one `unsafe` site fewer.
  - **S3, `String(unsafeFormat:)`'s Darwin body** (2026-11-15, 34bd2840f). The 26 SDK's `String(format:)` is
    `@unsafe`, so on Darwin the function calls it under `unsafe` rather than through `withVaList` and
    `NSString(format:arguments:)`. The function stays, for swift-corelibs-foundation's (see "Not costs of either
    floor").
  - **S4, the attributed selection's SDK arms** (2026-11-17). The six `#if !canImport(Darwin) ||
    canImport(FoundationModels)` guards and their three duplicated fallback calls are gone; each macOS 26 call sits
    under its `#available` alone, and `subscript(_:)` with a selection is always declared (macOS 26, as SwiftUI's).
    The macOS 15 runtime's fallbacks are M1 and stay.
  - **S5, Core Text's paragraph types** (2026-11-19). Told apart by `canImport(CoreText)` now, not by
    FoundationModels: Core Text's own on Apple platforms, TUI's identical declarations on Linux, Windows and
    WebAssembly, which keep them. `Tools/SwiftUIProbes/Paragraph attribute types (attralign)/` keeps its `sdk15`
    mode and FoundationModels test as the dated record of the measurement the ruling rested on.

## Pending

Costs known to be coming, or not yet priced:

- **The attributed editor's line height** (G3 L4, A-ATTRED-3; owner question A-ATTRED-13, 2026-11-19). On Apple
  platforms `AttributedString.LineHeight` is Core Text's macOS 26 type, and its factor has no public accessor (only
  `==` against made values, an undocumented Codable encoding, or reflection), none of which can run on the
  development machine (macOS 15.8). Not built; the options and prices are in [the G3
  design](<../Historical/Text, editing and the clipboard/An attributed TextEditor - design (G3).md>) §6. Alignment,
  which this bullet also held until 2026-11-19, is row M11 (and was S5, until the 15 SDK went). Size: not
  measured.
- **The highlighter's line lexer** (G3 H0). It would take a `Span<UInt8>` of the line, but `String`'s span needs
  the macOS 26 runtime, so it takes a buffer instead ([Highlighting a large source in
  TextEditor](<../Historical/Text, editing and the clipboard/Highlighting a large source in TextEditor - design (G3, A-ATTRED-1).md>)).
  Another instance of M3, when H0 is built.
- **Marks stated as ranges of an `AttributedString`** (G3 H4′, B-ATTRED-52, 2026-11-20). `.textEditorMarks(_:in:)`
  takes ranges of a `String` only; an attributed editor's marks are ranges of `String(value.characters)`. An
  `AttributedString` form was declined mostly on TUI's own rules (few overloads, and the app's parse has the
  `String`), but also because an `AttributedString.Index` becomes a UTF-8 offset in constant time only through the
  UTF-8 view macOS 15 lacks (M1): before macOS 26 each mark would cost a walk of the characters up to it. Additive if
  an app asks, best once macOS 26 is the floor. Size: nothing built.
- **WebAssembly at the floor is unmeasured.** The wasm lane runs 6.3.3, because 6.2.4 asserted on `TupleView` (C1).
  Nobody has built for WebAssembly with 6.2 since the workaround, so "Swift 6.2 or newer" is untested there
  (`ci.yml:1410-1412`; [WebAssembly port](<../WebAssembly port.md>), step 10).
- **Each new API that macOS 26 or Swift 6.3 adds.** Every SwiftUI API that needs a macOS 26 Foundation or
  standard-library type, and every new use of a 6.3 or 6.4 feature, adds a row here. M1 is what one such API cost.

## Not costs of either floor

These come up when the floors are discussed, and a rise would not remove them:

- **Yielding accessors.** `_read` and `_modify` are used because no compiler supports SE-0474 without
  `-enable-experimental-feature CoroutineAccessors`, 6.4 included (`.claude/CLAUDE.md`).
- **Regex lookbehind** compiles on no compiler TUI uses, at either target, though CLAUDE.md lists it.
- **Returning a `Span` from a function, or a `~Escapable` type that holds one,** is experimental (`Lifetimes`) on
  6.2, 6.3 and 6.4 alike.
- **A noncopyable field described as `()`** by the runtime lasts until the macOS 27 runtime and 6.4 elsewhere
  (`Tests/TUIViewTests/TypeWalkTests.swift:262-277`). A macOS 26 floor does not remove it.
- **SwiftUICore leaking through AppKit,** which is why `TUIAppKit` is a module of its own, why `ImageLoader`
  decodes with ImageIO, and why `SystemFormatStyle+DiscreteStatics.swift` declares its statics twice. It starts
  with the macOS 15 SDK and continues in the 26 SDK.
- **`String(unsafeFormat:)` itself.** It exists because Apple's Foundation and swift-corelibs-foundation disagree
  about whether `String(format:)` is unsafe, which is a Linux matter. Only its Darwin body was S3.
- **The WebAssembly executor stall** (a pending `Task.sleep` holds up everything) affects every toolchain through
  6.4.2. Its fix is on `main` after 6.4 (`Sources/TUI/TUI.docc/Articles/RunningInABrowser.md`).
- **The `concurrency_escape` exceptions** come from SwiftUI's own signatures, Apple classes not marked `Sendable`
  and a signal handler, not from a floor (macOS 26 study).
- **SwiftUI behaviour not measured on macOS 26 or 27** (A-ATTRED-4, MACOS27-PARITY, the drag containers of A53).
  The development machine runs macOS 15.8, which is a host limit, not a support floor.
- **Three `-sil-verify-all` failures** found on 2026-10-17. Two fail on 6.2.4, 6.3.3 and 6.4.0. One, in
  `TrackRenderer.render`, is 6.2-only, but nothing miscompiles and nothing works around it, so it costs nothing today.

## Keeping this up to date

- **Every change that adds a fallback, a version gate, a workaround for one toolchain, or forgoes a feature because
  of either floor adds a row,** in the same commit: what, where (file:line), which floor, kind, size, what dropping
  the floor would let go, and the date. Write "not measured" rather than guess a size.
- **A change that removes one deletes its row,** or moves it to "What has already been paid down" if the reason is
  worth keeping.
- **The lead flags a significant row to the owner** when it lands: one that costs days, changes what an app sees
  on one platform, or adds a CI lane. Flagging it is how the owner's rule is kept.
- **To find candidates,** search `Sources` and `Tests` for `#if compiler(`, `#available(`, `@available(macOS 26`,
  "macOS 15" and "6.2", and `Tools/CompilerBugs/README.md` for workarounds marked "for as long as swift.org's 6.2
  builds are supported".
