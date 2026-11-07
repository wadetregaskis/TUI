# Raising the floor to macOS 15

*What raising the package's minimum macOS from 14 to 15 would unlock, and
what was adopted when it was raised on 2026-10-31. The research of that day,
with its adoption table.*

## In short

The floor is macOS 15 since 2026-10-31 (`2b2a82d1f`), by the owner's
decision. macOS 15 carries Swift 6.0's runtime, so it gave `Mutex`, `Atomic`,
`String(validating:)`, five more `UTType`s for Linux, and read-only global
array literals, and made 39 availability attributes and every
`#available(macOS 15` dead (`84e8c178a`). It does not give `Array.span`,
`InlineArray`, `Observations`, `UTF8Span` or `Task.immediate`, all macOS 26.

## The problem

The owner said, among his main-actor rulings of that weekend, that the floor
may rise to macOS 15; the research below priced what it would give, feature
by feature, with evidence per platform. CI's oldest macOS lane already ran
macOS 15, so nothing tested went away (`2b2a82d1f`). The adoption went wider
than the research first proposed (`Atomic` for the process-wide flags too)
because the owner wants `nonisolated(unsafe)` gone.

## Where it stands

Adopted as the record's last table says. What a further raise to macOS 26
would gain is a live note: [Raising the floor to macOS 26](<../../Swift language/Raising the floor to macOS 26.md>).

## For a future reader

- **Re-entering a `Mutex` kills the process**, where `NSLock`'s behaviour
  differed; read the body of each lock that calls out before converting it.
- **An `Atomic` `static let` is lazy even with a constant argument**: touch
  it before installing a signal handler.
- **A `mutex.withLock { }` inside a `@MainActor` function costs about
  100 ns, not 3**, for the executor check Swift 6 inserts.
- **At a macOS 15 target on a macOS 15 runtime, `#expect(metatype == nil)`
  crashes** without failing a test; CONTRIBUTING's Testing section says to
  compare outside the macro.
- The probe generator and throwaway package it cites were in the scratchpad
  and were not kept.

## The record

### The research, 2026-10-31

Research for the floor raise, 2026-10-31, against worktree `df6f260da`. Nothing in the worktree was built or changed; the throwaway package is in the scratchpad (`floor15/pkg`, its build directories removed).

**The short answer.** macOS 15 carries Swift 6.0's runtime (`utils/availability-macros.def`: `SwiftStdlib 6.0: macOS 15.0`, `6.1: 15.4`, `6.2: 26.0`, `6.3: 26.4`). So the floor gives Synchronization, `TaskExecutor`, `RangeSet`, `Int128`, `DiscreteFormatStyle`, `UndoManager` user info, `String(validating:)`, the metadata of typed-throws and `@isolated(any)` function types, and read-only global array literals. It does **not** give `Array.span`, `InlineArray`, `Observations`, `UTF8Span` or `Task.immediate` (all macOS 26), and it does not remove `libswiftCompatibilitySpan`. The biggest gains are `Mutex` in place of `NSLock` and `OSAllocatedUnfairLock`, one spelling on all platforms, and the array literals, which come free.

**How to read the evidence.** "SDK" is the `.swiftinterface` or header in Xcode 26.3's 26.2 SDK. "Probe" is `swiftc -typecheck` at targets 14.0, 15.0, 15.4 and 26.0 with Xcode's 6.2.4 (`floor15/probes/gen.py`). "Built" is a real build in the throwaway package. "Source" is the Swift repo at `swift-6.3.3-RELEASE`. Host: macOS 15.8.1 on a virtual M4 Max with 14 cores. There is no Linux or Windows machine here, so anything on those is from source or a cross-compile, and the table says so. File paths in the lists are as `git grep` prints them, shortened to the file name where that is unique.

#### Features

| feature | what it gives | availability evidence | where TUI could use it now | cost | recommendation |
|---|---|---|---|---|---|
| `Mutex<Value>` | Lock and state as one value, no heap allocation, typed-throws `withLock`, `withLockIfAvailable`. | **macOS:** 15.0 (SDK; probe errors at 14). Built and run on Xcode 6.2.4, swiftly 6.3.3 and 6.4.0 at `.v15`, and on swiftly 6.2.4 with the Command Line Tools' 15.5 SDK under `env -i`. **Linux:** in the toolchain, futex (`LinuxImpl.swift`); static-linux x86_64 and aarch64 built and linked, not run. `Tests/TUIAppTests/TaskExecutorPreferenceTests.swift:10` already imports it unguarded. **wasip1:** built and run, works (below). **Windows:** `WindowsImpl.swift`, SRWLOCK, and `SWIFT_SOURCES_DEPENDS_WINDOWS` in its CMakeLists; source only, not run here. | Stored-state locks, listed under "Where the locks are". | One `import Synchronization` per file (MemberImportVisibility). Re-entry changes behaviour, see below. Storing a captured non-Sendable value into the state is an error on all three compilers (`'inout sending' parameter … cannot be task-isolated`, found with `-emit-sil`; `-typecheck` does not show it). `Tests/TUIAppKitTests/AppKitBridgeTests.swift:151` already allows the module. | **Adopt.** Uncontended cost equals `OSAllocatedUnfairLock`; about a third of `NSLock` (bench). Read the body of each lock that calls out. |
| `Lock<State>` over `Mutex` | `Sources/TUICore/Concurrency/Lock.swift` loses its `#if`, the `os` import and the `NSLock` arm: one implementation on every platform, one allocation fewer on macOS. | As `Mutex`. | `Lock.swift:21-67`. Keep it as a class: `StateStorage.swift:1066` keeps an array of them, and `Mutex` is `~Copyable`. | Small. Signature stays. | **Adopt, first.** It is the shared reuse point, and it helps the Windows port. |
| `Atomic<T>`, custom `enum: UInt8, AtomicRepresentable` | Lock-free values with a stated ordering; `RawRepresentable` enums conform with the declaration alone. | **macOS:** 15.0 (SDK). `static let` in a generic-free enum and `private static let` of a custom enum: built and run on all three compilers. **Linux:** built static-linux. **wasip1:** run. **Windows:** source only. | `FatalSignalTerminalRestore.swift:161,166,199,207` and `poppedByWatchdog` at `:183`, read by a crash handler. | An Atomic `static let` is **lazy even with a constant argument** (disassembly: a `swift_once` token check before the `ldrb`), so touch it before installing a handler, as `installIfNeeded()` already does for `poppedByWatchdog`. | **Adopt in the signal path.** `owedCount` published with `.releasing` after the bytes is a real ordering gain, should a crash arrive on another thread. **Not** for the startup-written flags (`KittyGraphics.swift:342,363`, `TerminalHyperlink.swift:339`, `TerminalURLOpening.swift:27`, `ColorDepth.swift:83,97`, the two `generation`s): their comments rule out a race and the read costs the same, so it would be churn. |
| `AtomicLazyReference` | Lock-free set-once reference. | macOS 15.0 (SDK). Run on Darwin and wasip1. | `ASCIIPalette+SearchIndex.swift:200-213` (`SearchIndexHandle`; `SearchIndex` is a class at `:53`). | `load()` returns a retained reference, so it may not beat a 2.8 ns lock; not measured. | **No for now.** `Mutex<SearchIndex?>` is the simpler move. The hoist in `ASCIIConverter+RowBuilder.swift:79` stays either way, for the retain. |
| `WordPair` / `Atomic<WordPair>` | Double-word atomic. | macOS 15.0. Built on x86_64 and aarch64 static-linux, run on Darwin and wasip1. | Nothing needs it. | None. | **No.** No use. |
| Noncopyable generics in the stdlib (`Optional<~Copyable>`, `UnsafePointer<~Copyable>`) | Generic code over noncopyable values. | **Not floor-gated:** no `@available` on the declarations, probe passes at 14, as does a cast to `Box<NC>` emitted with `-c`. `FeatureAvailability.def` lists `NoncopyableGenerics (6,0)`, which no probe tripped. | No `~Copyable` anywhere in `Sources`. | None. | **No.** The raise changes nothing here. |
| `@isolated(any)` as a generic argument | `[@isolated(any) …]` and `Optional<…>` compile. | **macOS:** 15.0 (probe at 14: `runtime support for '@isolated(any)' function types is only available in macOS 15.0.0`). A parameter or direct field works at 14. | Direct fields and parameters only: `LifecycleModifier.swift:136`, `TUIContext.swift:251,272`. No workaround for the limit found. | None. | **No change needed.** It is available if a design wants it. |
| Typed-throws function types as generic arguments | Metadata for `(Int) throws(E) -> Void`. | **macOS:** 15.0 (probe). Plain `throws(E)` functions and stdlib closures (`map`, `withLock`) work at 14: they are `@_alwaysEmitIntoClient`, no `@available`. | No `throws(` in `Sources`. `rethrows` at `InputByteBuffer.swift:134`, `Lock.swift:36`, `StallWatchdog.swift:74` could be typed at any floor. | None. | **No.** Not floor-tied, and nothing wants it. |
| Task executor preference, `TaskExecutor`, `globalConcurrentExecutor` | Prefer an executor for nonisolated work. | **macOS:** 15.0 (SDK, probe). Linux and wasm already build it (`TUIFoundation`). | `View+TaskExecutor.swift:43,87,102` already use it, gated. | Remove three attributes. | **Drop the gates.** No internal use: `@concurrent` covers the off-main work, and a preference cannot move an actor's work. |
| `String(validating:as:)` | Stdlib UTF-8 validation with no Foundation, reading contiguous storage in place. | **macOS:** 15.0 (`init?(validating:as:)`, `@inlinable`; probe errors at 14). Linux: `#available` is always true, so Linux already takes it. wasm, Windows: stdlib. | `Terminal+Input.swift:653`. | Delete two lines and a paragraph. | **Adopt; delete the old path.** The branch is what it looks like: `String(validating: bytes, as: UTF8.self)` versus Foundation's `String(bytes:encoding:)`. Line 656 is reachable only on macOS 14, which no test ran (its own comment says so). |
| Other `String(bytes:encoding:.utf8)` | The same swap. | As above. | `KeyEvent.swift:387,488`, `TerminalHost.swift:716`, `TextUndoHistory.swift:400`, about 10 more. | Each needs a look at BOM behaviour. | **No, not as part of this.** No measured gain off the paste path. |
| Foundation on swift-foundation | Swift 6 "unifies the implementation of Foundation across all platforms"; core types "share their implementation with macOS 15 and iOS 18" (swift.org, *Announcing Swift 6*). | macOS 15 forward. | Automatic: macOS and Linux now run closer code. | None. | **Take it for free.** |
| `DiscreteFormatStyle`, `Date.FormatStyle` etc. conforming | Styles that report the next change. | macOS 15 (SDK, Foundation `:11865`). Linux: swift-foundation. | `SystemFormatStyle*`, `TimeDataSource*`, already built on it. | Remove the gates. | **Drop the gates.** |
| `AttributedString`, `Predicate`, `Expression`, `Calendar.RecurrenceRule`, `Calendar.dates(byAdding:…)` | Additions in 15: inflection options, `#Expression`, recurrence rules, date sequences. | macOS 15 (SDK; `RecurrenceRule` members 15.2; `Bundle.localizedString(…localizations:)` **15.4**). | Date picker loops could use `Calendar.dates(byAdding:)`; no proposal in hand. | Not assessed. | **No.** Nothing needs them. |
| `RangeSet`, `DiscontiguousSlice` | Non-contiguous index sets. | macOS 15.0 (SDK). | `TextSelection.swift:61,88` already uses it; that is why the type is gated. | None. | **Drop the gate.** No new use. |
| `Int128`, `Duration.attoseconds` | 128-bit integers. | macOS 15.0 (SDK, probe). | `MonotonicClock.swift`'s `components` split works and is simple. | None. | **No.** |
| `Duration` and clock fixes | `SuspendingClock.now` and `ContinuousClock.now` build their `Duration` directly rather than by `.seconds + .nanoseconds`; `.seconds(…)` etc. became `@inlinable`; both clocks `Sendable` (diff of 5.10.1 and 6.0.3 sources). No bug fix that TUI works around. | In the OS from 15. | Automatic: `MonotonicClock.swift:57`, `TypeSelectingFocusHandler.swift:90`. | None. | **Take it for free.** No source change. |
| Regex | Regex is macOS 13; at 15 only an underscored property. **Lookbehind does not compile** on 6.2.4, 6.3.3 or 6.4.0 at target 15 or 26 (`lookbehind is not currently supported`); SE-0448 is Accepted, and names no release. | Probe on all three compilers. | One regex in `Stress/Sessions/PlaylistSession.swift:221`. | None. | **No.** Note for the owner: `CLAUDE.md`'s Swift 6.2 list names "regex lookbehind", and it does not work yet. |
| Observation | `withObservationTracking` is unchanged at 15: macOS 14 in the interface. The 5.10.1 to 6.0.3 diff adds an SPI `changed` key path and removes a registration in place; **no behaviour fix**. `Observations` is macOS 26. No public cancel at any version. | SDK; source diff. | `ObservationLease.swift`'s sentinel remains needed. | None. | **No.** Nothing unlocked. |
| `Span`, `RawSpan` and kin | Unchanged. The types are `@available(macOS 10.14.4, …)` (back-deployed), `Array.span` is macOS 26. `libswiftCore.tbd` still has `$ld$previous$@rpath/libswiftCompatibilitySpan.dylib$$1$10.14$26.0$…`. | **Built:** a generic use of `OutputSpan` at target 15 links `@rpath/libswiftCompatibilitySpan.dylib` on 6.2.4 and 6.4.0. | `InputByteBuffer.swift` must keep avoiding them. | Comments only. | **No change.** `Tools/check-span-compatibility.sh` stays; only macOS 26 lifts it. |
| `InlineArray` | Unchanged: macOS 26 (SDK, probe errors at 15.4). | SDK. | `TerminalColors.swift:60` stays a tuple. | None. | **No.** |
| Isolated deinit | Works at any target through a client-side shim. | **Built:** weak `swift_task_deinitOnExecutor` plus `_deinitOnExecutorMainActorBackDeploy` at 14 and 15, strong at 15.4. | Not floor-tied. | None. | **No change.** |
| **Read-only global array literals** | Global `[T]` literals go in `__DATA,__const` with no `swift_once` or `swift_initStaticObject`. | **Built, -O, Darwin** (`FeatureAvailability.def`: `StaticReadOnlyArrays (6,0)`). Three big arrays and one small, at 14: `__DATA,__data` 56,200 bytes, `__text` 748, imports `swift_once` and `swift_initStaticObject`. At 15: `__DATA,__const` 56,200, `__text` 172, imports only `__swiftImmortalRefCount`. The imports are the same on 6.4.0. Not tried on Linux. | Automatic for every such `let`; a rough grep finds about 57 in `Sources/TU*`, more in generated tables. | None. | **Take it for free.** A release size or A/B reading in the floor commit would price it; not measured on TUI, since no TUI build was run. |
| `UndoManager` action user info | Lets a step be identified. | macOS 15 (`NSUndoManager.h:209-219`). TUI's own on Linux. | `TextUndoBridge.swift:111,140` already use it. | Remove guards. | **Drop the gates.** On macOS 14 "the run goes on"; that path is gone. |
| Symbols: `BreatheSymbolEffect`, `WiggleSymbolEffect`, `RotateSymbolEffect` | Effect types. | macOS 15.0 (SDK). | `SymbolEffects+Symbols.swift:27`. | Drop a clause. | **Drop the gate.** |
| UTType additions | `.heics`, `.exr`, `.dng`, `.css` at 15.0, `.jpegxl` at 15.2. | SDK, probe. | **Gap:** TUI's Linux `UTType` (`ContentTypes/UTType.swift`, `ContentTypeTable.swift`) has none of them, and a macOS app at the new floor can now name the first four unguarded. | Five records; `ContentTypeTableTests` already checks records against Apple's. | **Adopt**, small. |
| CoreTransferable `exported(as:)` | Direct export of a `Transferable`. | **macOS 15.2**, not 15.0 (interface `:37`; probe errors at 15.0). | `View+FileExporter.swift:266-268` and its `NSItemProvider` route. | Would need a 15.2 gate and a second path. | **No.** Keep the route; fix the comment and the compatibility guide line 157. |
| CoreGraphics and ImageIO HDR | `CGContextDrawImageApplyingToneMapping`, `CGImage.shouldToneMap`, `kCGImageSourceGenerateImageSpecificLumaScaling` (15.0). | Headers. | `ImageLoader.swift` draws to 8-bit sRGB; Linux and wasm use stb. | Not assessed: needs HDR test images. | **No.** No report of a wrong picture, and it would be macOS-only. |
| AppKit | No macOS 15 additions in `NSImage.h`, `NSColor.h`, `NSBitmapImageRep.h` or `NSWorkspace.h`. | Headers. | `TUIAppKit`, `TUIFilePanelsAppKit`: nothing to change. `Exports.swift:16` is about the SDK, not the target. | None. | **No.** |
| Swift runtime fixes (casting, metadata) | Runtime features of 6.0: typed throws, `@isolated(any)`, noncopyable generics, raw-struct metadata, read-only arrays, ObjC symbolic references. | `FeatureAvailability.def`, `RuntimeVersions.def`. | **No gate or comment in TUI names a macOS 14 runtime bug.** The noncopyable field reported as `()` (`TypeWalkTests.swift:280`, `ValueHashPlan.swift:97`) lasts until macOS 27. Dynamic casts are avoided for cost, not for a bug. | None. | **Nothing to remove.** A `Mutex` field in a class is safe for the walk, per that test's comment: only a source reader counts inside a class. |
| Link line | No compatibility library differs between 14 and 15; `hello` is the same 34,264 bytes. `libswiftSynchronization.tbd` is in the SDK. | Built. | None. | None. | Nothing to do. Windows and dynamic Linux ship one more runtime library; **bytes not measured** (the disk fell to 804 MiB). |

#### Re-entering a lock: the one behaviour that changes

Each is run or read, as marked. `Mutex` has no re-entrant mode on any platform.

| platform | `Mutex` re-entered | `NSLock` re-entered |
|---|---|---|
| macOS 15.8 (run) | Process **killed, exit 137** (SIGKILL), nothing on stderr. `OSAllocatedUnfairLock`, so TUI's `Lock` today: the same, also run. No handler can run, so `FatalSignalTerminalRestore` cannot restore the terminal. | Hangs (alarm at 5 s). |
| Linux | `fatalError("Recursive call to lock Mutex")` from `EDEADLK` (`LinuxImpl.swift:157`; source only). | Not tested here. |
| wasip1 (run) | **Spins forever** (`_wait` compiles to nothing without `_runtime(_multithreaded)`, `WasmImpl.swift:27-37`, and the loop at `:92`). Normal run 0.12 s; this one still going at a 20 s alarm. | **No-op:** locks twice without blocking, and `try()` answers `true` while held. |
| Windows | SRWLOCK; not tested. | Not tested. |

So moving an `NSLock` turns a hang into an uncatchable kill on macOS, and a silent pass into a hang on wasm. TUI has had this bug: `StorageFailureTests.swift:118` records a handler that "re-entered a non-recursive `NSLock` and never came back". **Move memo caches freely, and read the body first for any lock that calls out.** `withLockIfAvailable` answers `nil` when held, on Darwin (three compilers) and wasip1.

A `Mutex` body also cannot `await`, which suits all of these.

#### Where the locks are

**Move: the bodies I read are closed, a dictionary or value, and `nonisolated(unsafe)` goes too.**
`Sources/TUIStyling/Color/Color+Downsampling.swift:355-360,442-443`, `Color+PulseRamp.swift:288-289`, `Theme/FieldSurfaceMemo.swift:45-46`, `Theme/RowFills.swift:152-153`, `Theme/StripeFill.swift:143-144`; `Sources/TUIBitmaps/Styling/AssetCatalog.swift:107-108,144`; `Sources/TUIAppKit/AssetCatalog+AppKit.swift:126-132`; `Sources/TUIFoundation/Extensions/View+ClipboardCommands.swift:204,224`.

**Probably move, after a closer read: the lock is held across real work.**
`Sources/TUIImage/ASCIIPalette.swift:250-253` (builds a palette while held), `ASCIIPalette+SearchIndex.swift:201,243` (builds an index while held), `Sources/TUIBitmaps/Views/Image+Bundle.swift:124-125` (decodes a file while held), `Sources/TUIPickers/Styles/GraphicalDatePickerStyle+MonthTitle.swift:50` (makes a `DateFormatter` while held), `Sources/TUIStyling/Color/LightDarkColor.swift:156`, `Sources/TUIView/Rendering/BodyMutationDiagnostic.swift:81`.

**Read the body first: these may call out, or guard more than state. Not read for this.**
`Sources/TUIFoundation/State/AppStorage.swift:40` (comment at `:127` warns of a deadlock), `State/UserDefaultsStorage.swift:37`, `Environment/TUIContext.swift:23`, `Focus/TextUndoBridge.swift:184`, `Modifiers/RefreshableModifier.swift:44`; `Sources/TUIChrome/Notification/NotificationService.swift:120`; `Sources/TUIStrings/Localization/LocalizationService.swift:145`; `Sources/TUIImage/ImageLoader.swift:519` (guards a stderr redirect, not state), `:627`, `:888`.

Most of the lower modules' files import Foundation for other reasons, so this is not by itself a route to dropping Foundation from a module. It may remove the need in `Lock.swift` and in `LightDarkColor.swift:11`, whose comment says `NSLock` is why.

#### Dead after the raise

##### `#available` in Sources: remove

- `Sources/TUIApp/Rendering/Terminal+Input.swift:653` (and the fallback at `:656`)
- `Sources/TUIEffects/SFSymbols/SymbolEffects+Symbols.swift:27`
- `Sources/TUIFoundation/Focus/TextUndoBridge.swift:111`, `:140`
- `Sources/TUISearch/Modifiers/SearchableModifier.swift:278`

**Not dead:** `TUIContext.swift:293` (macOS 26), `TypeWalk.swift:68` (macOS 26), and the macOS 26 and 27 checks in `NamedTaskTests.swift:20,26`, `ContentTypeTableTests.swift:29,56`, `ValueHashPlanTests.swift:551`, `TypeWalkTests.swift:197,271`.

No gate has to go for the build's sake: `if` and `guard #available(macOS 15, *)`, and `#available(macOS 14, *)`, give **no warning** at a macOS 15 target, also inside a result builder (probe, stand-in builder). They go because they are dead.

##### `@available(macOS 15, *)` on declarations in Sources: redundant, remove

`View+TaskExecutor.swift:43,87,102`; `SystemFormatStyle+SizeVariants.swift:9,24,40,47`; `LocalizedStringKey+Interpolation.swift:157`; `LocalizedStringKey+Live.swift:79,91`; `Text+TimeDataSource.swift:14,99,113`; `TextSelection.swift:53`; `TimeDataSource.swift:23,47,55,78`; `SearchSelection.swift:36,55`; `SystemFormatStyle+DateOffset.swift:12,155`; `+DateReference.swift:13,253`; `+DiscreteStatics.swift:55,93,113,133`; `+Stopwatch.swift:12,108`; `+Timer.swift:12,140`; `SystemFormatStyle.swift:33,36`; `TextEditor.swift:164`; `TextField.swift:445,464,546`; `TextSelectionChannel.swift:30`. That is 39.

**Removing them is right, and parity does not ask to keep them.**
- CLAUDE.md's parity table covers names, order and types, not availability.
- TUI already differs from SwiftUI's versions, which shows these are mechanical: `task(…executorPreference:…)` is macOS 26.4 in SwiftUI and 15 here; `searchSelection` is 26.0 there and 15 here. `TextSelection`, `TimeDataSource` and `SystemFormatStyle` match at 15.
- `Tools/APIParity/api_parity.py` ignores `introduced`: `unavailable()` and `deprecation()` read only unavailable, deprecated and obsoleted, and neither it nor `baseline.json` mentions `introduced`. So the report should not move, though I did not run it.
- SwiftUI source keeps compiling: a client's own `if #available(macOS 15, *)` around these gives no warning (probe).
- The attributes have no effect on Linux, wasm or Windows, and SwiftPM refuses a client below the floor.

##### Tests: remove

- `guard` / `if #available(macOS 15, *)`: `TaskExecutorPreferenceTests.swift:41,56`; `SymbolEffectTests.swift:115,131`; `LocalizedStringKeyTests.swift:424`; `SystemFormatStyleClockTests.swift:52,63,69,97,135,141,156,167`; `SystemFormatStyleDateTests.swift:55,61,89,132,138,154,172,203,213`; `TextAttributedStringTests.swift:271`; `TimeDataSourceTests.swift:50,59,68,83,98,108`; `UmbrellaQualifiedNameTests.swift:640`; `SearchSelectionTests.swift:63,68`; `FindNavigatorTests.swift:56,129,173,218`; `TextSelectionTests.swift:52,57,62,67`; `TextUndoCoalescingTests.swift:258`; `TypeWalkTests.swift:289`.
- `@available(macOS 15, *)`: `SizeDependentTextTests.swift:66`; `TaskExecutorPreferenceTests.swift:19`; `SystemFormatStyleClockTests.swift:31,37`; `SystemFormatStyleDateTests.swift:32,37,194`; `TextAttributedStringTests.swift:257`; `SearchSelectionTests.swift:20,43,71,86`; `TextSelectionTests.swift:20,70,88,104,122`.
- Follow-on: `stepsCanBeAsked` and its `.enabled(if:)` at `TextUndoCoalescingTests.swift:257,267,290`. The body-helper split at `SearchSelectionTests.swift:58-68` and `TextSelectionTests.swift:47-67` exists only for the gate and can collapse.
- `TypeWalkTests.swift:13,288`'s `#if canImport(Synchronization)` is a capability check, not an OS gate. Keep it until a Windows lane shows the import.

##### Keep, though always true

- `Tests/TUIAppTests/SceneCompositionTests.swift:34` and `Tools/APIParity/CompileCorpus.swift:4320`: `#available(macOS 14, *)` is **the subject of the test**, an availability check every supported system passes, in a scene builder.
- `Tools/APIParity/CompileCorpus.swift:573,618,762,1283,2596` and `CompileCorpusTUIOnly.swift:24`: they are SwiftUI source, and writing `@available` is part of what they check.
- `Tools/SwiftUIProbes/**`: standalone SwiftUI probes, a record of what was measured.
- `Tools/CompilerBugs/PackMetadataSegfault/Package.swift:13`: a minimised repro, as filed.

##### Comments that go stale

- `Sources/TUIApp/Rendering/Terminal+Input.swift:625-626`, `:640-651`
- `Sources/TUIApp/Rendering/Terminal.swift:186-187`
- `Sources/TUIApp/Rendering/InputByteBuffer.swift:25`, `:130-131`
- `Sources/TUIFoundation/Focus/TextUndoBridge.swift:131-132`
- `Sources/TUIFilePanels/Modifiers/View+FileExporter.swift:267-268`: `exported(as:)` is still out of reach at 15.0, so the reason survives with a new number
- `Sources/TUIStrings/Formatting/SystemFormatStyle.swift:31-32`
- `Sources/TUISearch/Environment/SearchSelection.swift:31-32`, `:46`
- `Tests/TUISearchTests/SearchSelectionTests.swift:58`, `Tests/TUITextInputTests/TextSelectionTests.swift:47`, `Tests/TUITextInputTests/TextUndoCoalescingTests.swift:255`
- `Tools/check-span-compatibility.sh:32,99,137`, `.github/workflows/ci.yml:610`: "macOS 14 and 15" becomes macOS 15. `:72` and `:95` are dated measurements; leave them.
- `Documentation/SwiftUI parity/SwiftUI compatibility guide.md:157`

**Still true, keep:** `TextUndoBridge.swift:95,217` and `Sources/Example/Pages/UndoDemo.swift:35` are about the macOS 15 *SDK*, not the target. `Animation.swift:141` and `ShapeStyle.swift:20` are SwiftUI's history. CHANGELOG 377 and 380 are history; add a new entry.

##### The floor itself, and what names it

`Package.swift:20`; `README.md:159`; `Sources/TUI/TUI.docc/Articles/GettingStarted.md:7,31`, `BuildingYourFirstApp.md:31`, `Troubleshooting.md:48,58,80`; `Tools/ProductSmoke/Package.swift:28`; `Tools/ScreenClips/Package.swift:21`; `Tools/verify-versioned-consumer.sh:68`.

A client below macOS 15 gets SwiftPM's "requires macos 15.0" error, so the CHANGELOG should say this is breaking. The Command Line Tools' 15, 15.2 and 15.5 SDKs all have `Synchronization.swiftmodule`, and the semantics run passed there (swiftly 6.2.4, 15.5 SDK, `env -i`, fresh scratch path).

#### Bench

`-c release`, single thread, uncontended. Each figure is the best of 3 trials in-process, by thread CPU time; three process runs each. Functions `@inline(never)`, results summed into a global. Source: `floor15/pkg/Sources/bench/main.swift`, records `floor15/bench2.log`.

**Box:** macOS 15.8.1, virtual M4 Max, 14 cores. `uptime` 1-minute load across these runs 6.4 to 10.2, others' jobs running (an earlier full run at load 9 to 33 agreed on the rows it measured validly). So: not a quiet-box A/B, and these are for orders of magnitude; wall clock tracked CPU within a few percent. **No Linux numbers: no VM here.** By source only, `Mutex` on Linux is a thread-id compare-and-swap from a TLS-cached `gettid`.

ns per call, three runs, including the 0.95 ns call-and-increment baseline:

| case | Xcode 6.2.4 | swift.org 6.4.0 |
|---|---|---|
| baseline: call + increment, no lock | 0.96, 0.94, 0.96 | 0.93, 0.94, 0.94 |
| `Mutex`, `let` in a final class, `withLock` | 2.81, 2.88, 2.90 | 2.79, 2.79, 2.75 |
| `OSAllocatedUnfairLock`, `let`, `withLock` | 2.87, 2.85, 2.98 | 2.79, 2.88, 2.79 |
| `NSLock` `let` + `var`, `lock()`/`unlock()` | 7.78, 7.56, 7.62 | 7.53, 7.58, 7.48 |
| `NSLock` `let` + `var`, `withLock` | 7.76, 7.81, 7.77 | 7.56, 7.68, 7.48 |
| same module: `Atomic<Bool>` static, `load(.relaxed)` | 0.97, 0.97, 0.96 | 0.83, 0.94, 0.94 |
| same module: `Atomic<UInt8>` static, `load(.relaxed)` | 0.96, 0.98, 0.96 | 0.93, 0.94, 0.95 |
| same module: `nonisolated(unsafe) static var Bool` | 0.96, 0.99, 0.94 | 0.82, 0.95, 0.93 |
| same module: `nonisolated(unsafe) static var UInt8` | 0.95, 0.95, 0.94 | 0.84, 0.94, 0.92 |
| other module: `Atomic<Bool>`, direct | 1.61, 1.64, 1.57 | 1.56, 1.57, 1.57 |
| other module: `Atomic<UInt8>`, direct | 1.59, 1.61, 1.60 | 1.57, 1.56, 1.55 |
| other module: `Atomic<UInt8> = detect()` | 1.62, 1.59, 1.58 | 1.56, 1.57, 1.56 |
| other module: `static var Bool`, direct | 0.95, 0.96, 0.96 | 0.96, 0.94, 0.94 |
| other module: `static var UInt8`, direct | 0.95, 1.00, 0.84 | 0.93, 0.94, 0.94 |
| other module: `static var UInt8 = detect()` | 5.16, 5.07, 4.95 | 5.04, 5.06, 4.97 |
| other module, through a getter in the module: `Atomic<Bool>` | 0.97, 0.96, 0.95 | 0.93, 0.94, 0.92 |
| other module, through a getter in the module: `static var Bool` | 0.97, 0.97, 0.94 | 0.94, 0.95, 0.93 |
| `MainActor.assumeIsolated`, main thread, no task | 124, 121, 123 | 122, 121, 121 |
| `MainActor.assumeIsolated`, main thread, in a `@MainActor` task | 106, 105, 103 | 100, 102, 99 |

What the numbers say:

- **`Mutex` = `OSAllocatedUnfairLock`**, about 1.9 ns above baseline. **`NSLock` is about 6.7 ns**, so moving one saves about 4.8 ns per uncontended lock.
- **An atomic relaxed load costs what a plain read costs.** The disassembly is `ldrb` either way. An Atomic `static let` adds a `swift_once` token check; a `static var` with a constant initialiser has none. Read directly across a module, the atomic pays about 0.6 ns for the addressor call; through a getter in its own module, the shape TUI uses, nothing measurable.
- **A cross-module `static var x = detect()` costs about 3.5 ns more than an atomic**, because the read calls `swift_beginAccess` (disassembly). `ColorDepth.swift:83` has this initialiser but is `private`, and I did not check whether a TUI release build keeps the check there.
- **`MainActor.assumeIsolated` is about 100 to 125 ns**, about 40 times a `Mutex` `withLock`. No floor effect; just keep it off per-cell paths.
- A first version of the bench read same-module `static var`s at 0.00 ns: nothing wrote them, so they folded to a constant. These figures write them first from a runtime value.

#### Cross-platform verification, by compile and by run

| check | result |
|---|---|
| Xcode 6.2.4 at `.v15` (`DEVELOPER_DIR=… xcrun swift build`) | Built, debug and release. 16 of 16 semantic checks pass. Plain `swift` is swiftly's, whatever `DEVELOPER_DIR` says, so the run went through `xcrun`. |
| `swiftly run swift +6.3.3`, `+6.4.0` | Built, 16 of 16 on both (release also on 6.4.0; 6.4.0 uses Swift Build). |
| swiftly 6.2.4 with the Command Line Tools' 15.5 SDK, `env -i`, fresh scratch path | Built, 16 of 16. |
| `Atomic` as `static let` in a generic-free enum; `private static let` of a custom `enum: UInt8, AtomicRepresentable` | Compile and run in every row above. |
| wasm: `swiftly run swift +6.3.3 build --swift-sdk swift-6.3.3-RELEASE_wasm --static-swift-stdlib` | `import Synchronization`, `Mutex`, `Atomic<Int>`, `Atomic<Bool>`, custom-enum atomic, `AtomicLazyReference`, `Atomic<WordPair>`: **compile, link and run.** All 16 checks pass under the toolchain's `wasmkit`, with `_runtime(_multithreaded): no`. wasmtime is not installed here, so it was not tried on it. Only 6.3.3: no other wasm SDK here. |
| What `Mutex` does with no threads | `WasmImpl.swift`: a three-state atomic. `_wait` and `_wake` compile to nothing without `_runtime(_multithreaded)`, so a free lock costs one compare-and-swap, and re-entry spins forever. |
| `NSLock` on wasm | A no-op, run: `try()` is `true` while held, and a second `lock()` returns. |
| static-linux 6.3.3, x86_64 and aarch64 | `synccheck` and `wordpair` built and linked into ELF. Not run. |
| Windows | Source only: `WindowsImpl.swift` wraps `SRWLOCK` through `WinSDK.core.synch`, and the CMake lists Windows sources. **Unverified here.** A one-file `import Synchronization` in `TUICore` is the cheapest proof, and the Windows lanes are the check that matters before moving the lower modules' locks. |

#### What was adopted, on branch worktree-agent-a3b9be0cfaca71ff5

| feature | adopted? | where, and what it did |
|---|---|---|
| Floor | yes | `Package.swift`, README, articles, ProductSmoke, ScreenClips, versioned-consumer script. |
| `Mutex` | yes | Every `NSLock` beside stored state in Sources but `TerminalWriteGate`'s `NSCondition`, which a `Mutex` cannot replace (no condition to wait on). `Lock<State>` is now a thin class over it. |
| `Atomic`, including a custom `AtomicRepresentable` enum | yes, wider than this note first said | The process-wide flags too (`KittyGraphics`, `TerminalHyperlink`, `TerminalURLOpening`, `ColorDepth`, the generations, `PictureUnderTextMarker`), because the owner wants `nonisolated(unsafe)` gone and a relaxed load through a getter costs the same (bench above). The signal path, with `count` published by a release. |
| `Atomic` of a pointer | **no, the compiler refuses it** | `Atomic<UnsafeMutablePointer<T>>` is not `Sendable`, a pointer not being. So three pointer `let`s in `FatalSignalTerminalRestore` stay `nonisolated(unsafe)`. |
| `String(validating:as:)` | yes | `Terminal.utf8Text`, fallback deleted. |
| UTType additions | yes | `.heics`, `.exr`, `.dng`, `.css`, `.jpegxl` in the Linux `UTType` and the table. |
| Dead gates | yes | 39 attributes and every `#available(macOS 15` in Sources and Tests. `SceneCompositionTests:34` and the compile corpus keep theirs, being the subject of the test. |
| `.attributedStyle` for `.attributed` | yes, forced | A macOS 15 target warns of the deprecated one, in one test. |
| `isolated deinit` | yes, one | `PresentationDockForgetting`, a non-generic object `RenderLoop` holds, because a `FocusManager` stopped being `Sendable`. On the generic class itself it stops swiftc 6.2.4's assertions build. |
| `SendableMetatype` (Swift 6.2, not the floor) | yes, one | `CustomPresentationDetent`, so a detent's height closure can be `@Sendable`. |
| Free: read-only array literals, clock improvements, Foundation unification | taken, no source change | Not measured on TUI. |
| Everything else in the table above marked **No** | no | For the reasons given there. |

**A finding that governs where `Mutex` and `@MainActor` may go.** `Synchronization` and the standard library are built in Swift 5 mode, so Swift 6 inserts a run-time executor check (`swift_task_isCurrentExecutor`, the 100 to 125 ns measured above for `assumeIsolated`) on entry to a closure that a main-actor function hands to them (SE-0423). `StackGuard.currentStackPointer` already documents it for `withUnsafeMutablePointer`. So a `mutex.withLock { }` in a `@MainActor` function costs 100 ns, not 3, and a hot class marked `@MainActor` starts paying it in every `first(where:)`. This is why the render-path classes were made not `Sendable` and not `@MainActor`.

**A second finding, about SwiftUI.** Its interface states `@available(*, unavailable) extension X: Sendable` for `EnvironmentValues`, `Transaction`, `ToolbarItemPlacement`, `DropInfo`, `RenameAction` and `FocusState`. TUI was declaring as `Sendable` (unchecked) what SwiftUI declares as not. That is what made most of Part 3 possible without leaving parity.

**A third finding, raised by the floor itself.** At a macOS 15 target on a macOS 15 runtime, `#expect(metatype == nil)` is a SIGSEGV that fails no test: `~/Desktop/Metatype compared with nil has no runtime type on macOS 15, crashes generics.md`. CONTRIBUTING's Testing section says to compare outside the macro.
