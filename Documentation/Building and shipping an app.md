# Building and shipping an app

What to know once a TUI app works and is on its way to its users: which of
TUI's products to depend on, what to ship beside the executable, how to make
it smaller, and why a release build takes the time it does.

- [Depending on fewer modules](#depending-on-fewer-modules)
- [What `import TUI` brings](#what-import-tui-brings)
- [Shipping a program](#shipping-a-program)
- [Shipping size](#shipping-size)
- [Build time](#build-time)

## Depending on fewer modules

`import TUI` is the whole framework, as `import SwiftUI` is SwiftUI, and the
`TUI` product is the simplest way to depend on it. Start there.

TUI is built as separate modules, and each module an app may want on its own is a library product too. An app that lists the products of only the modules it uses compiles and links only those and what they are built on:

```swift
.executableTarget(
    name: "YourApp",
    dependencies: [
        .product(name: "TUIApp", package: "TUI"),     // App, WindowGroup, Text, stacks, Button, …
        .product(name: "TUITables", package: "TUI"),  // Table, and List with it
    ]
)
```

```swift
import TUIApp
import TUITables
```

Measured 2026-10-11 with Swift 6.4.0 (`swift build -c release`, then `strip`), a hello world is 5,964,832 bytes on `TUIApp` against 9,552,376 on `TUI` (−37.6%), and compiles 8 of TUI's modules where the umbrella compiles 26. On a quiet machine the same day (release, 12 jobs, two clean builds each), it built in 62.8 and 58.7 s against 68.9 and 75.1 s, reached its first output in 6.8 ms against 7.1 ms, and used 2.76 MiB against 2.85 MiB (`footprint`; medians of 20 launches each, alternated).

- **The products decide what is built; the imports only which names you can see.** Depending on `TUI` and writing `import TUITables` builds and links everything.
- **A forgotten product** reads `cannot find 'Table' in scope` or `value of type 'Text' has no member 'tableStyle'`, naming no module. The documentation's *Which Module Provides It* page (built by `Tools/BuildDocs/build-docs.sh`) lists every public name with its module and product.
- **Mixing is safe**: an app can list `TUI` beside module products, or use a library that depends on `TUI`, and each module is linked once. But then the app is as large as the `TUI` app, so a **library** built on TUI should depend on module products (or `TUIFoundation`), never on `TUI`.
- **Never build a `.dynamic` library from TUI while an app also links a TUI product statically**: SwiftPM's own build system gives the app two copies of the shared modules, and Swift Build turns them into dynamic libraries the app must ship, and can fail to link another app in the package.

[Choosing products](https://github.com/wadetregaskis/TUI/blob/main/Sources/TUI/TUI.docc/Articles/ChoosingProducts.md) has the product list, what each brings with it, and where the module still shows when you use the umbrella: the debugger's and `String(reflecting:)`'s type names (`TUILists.List<…>`), `NavigationPath`'s saved form, the `TUI_TUIStrings` resource bundle, and `renderOnce`, which is `TUIApp`'s.

## What `import TUI` brings

`import TUI` re-exports every module: `TUIFoundation` (the views and modifiers), `TUIApp` (`App`, `Scene` and the run loop), `TUICommands` (`Commands`, `CommandMenu`, `CommandGroup` and the menu bar a scene's `.commands` draws), `TUIFilePanels` (`fileImporter`, `fileExporter`, `fileMover` and the open and save panels TUI draws for them), `TUIScenes` (the `Settings` scene and `AlertScene`), `TUIColorPicker` (`ColorPicker`, `ColorPickerPanel` and `GradientEditorPanel`), `TUICurveEditors` (the tone-curve and channel-curve editors), `TUINavigation` (the navigation containers), `TUIPresentation` (alerts, dialogs, sheets and the presentation modifiers), `TUILists` (lists), `TUITables` (tables), `TUITabs` (tab views), `TUITabImages` (`Tab`'s `image:` initialisers, which find the image by name), `TUIGrid` (grids), `TUIChrome` (the status bar, toolbars, notifications and tooltips), `TUIEffects` (transitions and visual effects), `TUIMenus` (`Menu`, `ControlGroup` and `.contextMenu`), `TUIBitmaps` (`Image` from a file, a URL or a bundle, `AsyncImage` and the `.image*` options), `TUITextInput` (the text fields and editors), `TUIForms` (`Form`, `LabeledContent`, `GroupBox` and the other view groupings), `TUISearch` (`.searchable`, search tokens and scopes), `TUIPickers` (`Picker`, `RadioButtonGroup` and `DatePicker`), `TUINumericControls` (`Slider`, `Stepper`, `Gauge` and `ProgressView`) and `TUICore`, `TUIStyling`, `TUIView`, and `TUIImage` (via `@_exported`). Each of these is also a library product of its own (TUIStrings and TUITerminalHost come with `TUIFoundation`); [Choosing products](https://github.com/wadetregaskis/TUI/blob/main/Sources/TUI/TUI.docc/Articles/ChoosingProducts.md) says when to depend on them instead. The AppKit bridges — `Color(nsColor:)`, `NSColor(_:)` and `Image(nsImage:)` — are the separate `TUIAppKit` product: add `import TUIAppKit` where you use them. The Core Graphics ones — `Color(cgColor:)`, `Color.Resolved.cgColor`, `Image(_:scale:orientation:label:)` and `Image(decorative:scale:orientation:)` — need only TUI, on Apple platforms. They are kept out of TUI because AppKit imports SwiftUICore, and a module that imports AppKit makes every app importing it see SwiftUI's own extension members (its `FormatStyle.offset(to:)` and others) beside TUI's.

## Shipping a program

`swift build` puts TUI's resource bundle beside your executable: `TUI_TUIStrings.bundle` on macOS, `TUI_TUIStrings.resources` elsewhere. It holds the translations of TUI's own words (German, French, Italian, Spanish, Chinese and Japanese) and TUI's version. Copy it beside the executable wherever you install it — a release archive, an installer, a Homebrew formula that links the executable into `bin` (TUI looks beside the real file too) — and TUI's words follow the user's language.

The bundle is optional. A program shipped as the executable alone runs: TUI's words read in English, which is compiled in, whatever language the user asks for, and `tuiKitVersion` reads `unknown`. A copied executable does not read the bundle it left in `.build`, so it behaves the same on the machine that built it as on any other. Your own targets' resources are bundles of their own, which SwiftPM's `Bundle.module` still requires wherever your code reads it.

TUI itself needs no library beside the executable on any macOS it supports. A program that uses the standard library's `Span` types itself (`Span`, `RawSpan`, `MutableSpan`, `OutputSpan` and their kin), or links swift-collections 1.4 or later, may link `libswiftCompatibilitySpan.dylib` (`otool -L` on the executable says whether it does), which macOS has only from 26: copied out of `.build`, a program that links it strongly (the usual case: weak only where the code needing it was compiled for a macOS older than 10.14.4) stops at launch on macOS 14 and 15 with `Library not loaded: @rpath/libswiftCompatibilitySpan.dylib`. Ship that library beside the executable — copy it from `usr/lib/swift-6.2/macosx/` in the toolchain that built the program (Xcode's is `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`, swift.org's and swiftly's `~/Library/Developer/Toolchains/swift-<version>-RELEASE.xctoolchain`), and sign it with your own identity if you notarise the program — or link it weakly, `swift build -c release -Xlinker -weak_library -Xlinker <that directory>/libswiftCompatibilitySpan.dylib`, which is safe only if the code that needs it never runs before macOS 26. To check a built program, run `Tools/check-span-compatibility.sh <executable>` from a TUI checkout: it fails on any load of the library, strong or weak, and on any symbol imported from it.

## Shipping size

`swift build -c release` does not strip the program (measured), and a link flag shrinks it further; each of these costs something only you can weigh. The figures are for a stripped hello-world app (`Text("Hello, world")` in a `WindowGroup`), built with Swift 6.4.0 on 2026-10-11; Xcode's Swift 6.2.4 is within a point. The Xcode settings named are untried in Xcode unless marked measured.

### Depend on fewer modules

−37.6% for the hello world on `TUIApp` alone (stripped, with the trait below on); the link flags below apply to it as well.

**Cost.** A product per module you use, in your `Package.swift`.

The [section above](#depending-on-fewer-modules) says how.

### `strip`

20.9 MB → 9.7 MB, the symbol tables and the debug map.

**Cost.** Crash reports and profiles show addresses, so keep the dSYM to symbolicate them. `dsymutil` makes one and must run before `strip`; `swift build -c release` already runs it and leaves `MyApp.dSYM` beside the executable (measured, 6.2.4 and 6.4.0). In Xcode, Strip Linked Product (`STRIP_INSTALLED_PRODUCT`) with `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`; Xcode applies it only when it installs or archives the product (`DEPLOYMENT_POSTPROCESSING = YES`, per Xcode's build-setting reference), so a plain Release build stays unstripped.

### The `DeadStripUnusedAPI` trait, on by default

−14.7% with `swift build -c release`, the TUI API the app never calls. It works through the linker's dead stripping, so an Xcode app needs `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default (measured, Xcode 26.3).

**Cost.** A statically linked app whose `dlopen`ed plugin calls TUI API the app itself never calls: the plugin no longer loads. Such an app turns the trait off with `.package(url: …, from: …, traits: [])`, which turns off every default trait of TUI's (today, this one and the next, which such a plugin needs off as well).

### The `UnexportTUISymbols` trait, on by default

−3.2%, TUI's entries in the program's export table, whose bytes `strip` leaves in place (measured 2026-10-12, Swift 6.4.0 and Xcode's 6.2.4: 317 KB of export table down to 9 KB; the 227 entries left are the program's own and TUI's extensions of other modules' types, `String`'s and Foundation's). It works on every link that contains TUI, a `.dynamic` library of yours as well, and keeps TUI's symbols out of what that link exports, and with them your own extensions of TUI's types and protocols (`extension View { func card() }`, `extension Color { static var brand }`) and your conformances of TUI's types to your protocols, whose symbols Swift names after the TUI module (measured with a small library on both toolchains).

**Cost.** A plugin `dlopen`ed into your app that calls any TUI API through it no longer loads ("symbol not found in flat namespace"), where with the trait above alone only one calling API the app never calls fails; a dynamic library of yours that contains TUI no longer exports TUI's symbols, so an app that uses TUI through it fails to link ("Undefined symbols"), or, built against an older build of the library, to launch ("Symbol not found"); an app that calls one of your library's extensions of TUI's types fails to link as well, unless the compiler copied the extension's body into the app (it did for one built on public API alone), and a plugin that calls one in your app no longer loads; and the linker refuses it beside an export list of your own: `-no_exported_symbols`, `-exported_symbol` or `-exported_symbols_list` stop the link with "-unexported_symbol cannot be used with -exported_symbol*", and so would `LD_EXPORT_SYMBOLS = NO` or `EXPORTED_SYMBOLS_FILE` in Xcode, which pass those flags (untried in Xcode). Turn this trait off alone, and keep the other, with `.package(url: …, from: …, traits: ["DeadStripUnusedAPI"])`. The program's remaining exports go with `-Xlinker -unexported_symbol -Xlinker '*'`, which the linker takes beside the trait's patterns: 9 KB more (−0.1%), at the cost of any plugin linked against the executable (`-bundle_loader`) or `dlsym` on it.

### `-Xlinker -deduplicate`

−7.5% with both traits on (measured 2026-10-12). An Xcode Release build already does this: Xcode hands the linker `-Os`, and the linker then folds identical functions (measured, Xcode 26.3: a hello-world built from a SwiftPM package dependency folds 20,575 of its 61,034 functions). `swift build` does not.

**Cost.** The linker gives functions whose machine code is identical one address, across your whole program. Swift identifies a key path to a computed property by its getter's address, so two key paths with one root and one value type whose getters compile alike — `var a: Int { x }` and `var b: Int { x }`, or two constants — compare and hash equal. They still read the same values, but code using key paths as names can tell: a `Set` or `Dictionary` of key paths, `KeyPathComparator` equality (a `Table` then treats two such columns as one), and writable key paths whose setters differ. Swift closures compared by function pointer can likewise compare equal (`@convention(c)` functions are not merged), and a crash report or profile may name one of several merged functions. Adding `-Xlinker -no_deduplicate_allow_swift_addr_ref` keeps key paths and closures distinct (measured) and saves 2.2% instead. TUI's CI checks TUI's own code under it, with both traits on, as Swift 6.4.0 and Xcode's 6.2.4 compile it (each compiler folds its own set: 6.2.4 folds one more pair, reviewed; swift.org's 6.3.3, measured once outside CI, folds the same as 6.2.4; other compilers are unchecked) and in the modules its test programs link (TUIAppKit's key paths are not among them); `Tools/DedupCheck/dedup_check.py --report` lists, before `strip`, what it did to yours ([Tools/DedupCheck/README.md](../Tools/DedupCheck/README.md)).

The link flag, per build or in your app's own manifest, and in Xcode (Release configuration, where deduplication is already on):

```bash
swift build -c release -Xlinker -deduplicate
```

```swift
.executableTarget(
    name: "MyApp",
    dependencies: ["TUI"],
    linkerSettings: [
        .unsafeFlags(
            ["-Xlinker", "-deduplicate"],
            .when(platforms: [.macOS], configuration: .release))
    ]
)
```

```
// Deduplication is on already. To keep key paths and closures distinct instead:
OTHER_LDFLAGS = $(inherited) -Xlinker -no_deduplicate_allow_swift_addr_ref
```

## Build time

A clean release build of TUI takes minutes, not seconds. Two things decide most of it (measured 2026-10-07 on a 12-core arm64 Mac VM, Swift 6.2.4):

- **Which compiler you have.** Run `swift --version`. If it prints `Build config: +assertions`, the compiler is an assertions build — swift.org's 6.2.4 for macOS is one, whether installed by hand or by swiftly (its 6.3.3 and 6.4.0 are not) — and Xcode's own Swift of the same version compiles TUI in about 26% less time: 86.4 s against 116.7 s to the end of TUI's compile, paired on one machine. (Part of the gap is the swift.org toolchain rebuilding SDK module interfaces that Xcode ships prebuilt.) With Xcode installed, build with its toolchain:

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release
  ```

  Both halves are needed. `DEVELOPER_DIR` alone does not change which compiler swiftly's `swift` runs, and `xcrun --toolchain XcodeDefault` without it runs the Command Line Tools' `swift` whenever `xcode-select` points at them.
- **Why more cores help little.** A release build compiles each module as one whole-module job, and the modules build in a chain: TUICore, then TUIView, then TUI. Inside a job, type checking and the SIL optimiser — about three quarters of TUI's job — run on one thread; only LLVM's code generation spreads across cores. The whole build averaged about 1.7 cores busy.
