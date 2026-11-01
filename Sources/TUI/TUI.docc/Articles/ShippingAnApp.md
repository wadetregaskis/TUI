# Building and Shipping an App

Get a working app to the people who will use it, and make it smaller if that matters to you.

## Overview

A release build is one command:

```bash
swift build -c release
```

It leaves your program at `.build/release/MyApp`. Copy that wherever it installs to, with TUI's resource bundle
beside it, and you are done. Most apps need nothing else, and the rest of this page is for when you want to know more:

- <doc:ShippingAnApp#Shipping-a-Program> says what goes beside the executable.
- <doc:ShippingAnApp#Shipping-Size> lists ways to make the program smaller, and what each one costs.
- <doc:ShippingAnApp#Build-Time> says why a release build takes minutes, and what helps.

To choose what your app depends on, see <doc:ChoosingProducts>.

## Shipping a Program

`swift build` puts TUI's resource bundle beside your executable: `TUI_TUIStrings.bundle` on macOS and
`TUI_TUIStrings.resources` elsewhere. It holds the translations of TUI's own words (German, French, Italian, Spanish,
Chinese and Japanese) and TUI's version.

Copy it beside the executable wherever you install it: a release archive, an installer, or a Homebrew formula that
links the executable into `bin` (TUI looks beside the real file too). TUI's words then follow the user's language.

The bundle is optional. A program shipped as the executable alone still runs, with these differences:

- TUI's words read in English, whatever language the user asks for.
- ``tuiVersion`` reads `unknown`.

A copied executable does not read the bundle it left in `.build`, so it behaves the same on the machine that built it
as on any other.

Your own targets' resources are separate bundles, and SwiftPM's `Bundle.module` still requires them wherever your
code reads it.

### A Library for macOS 15

TUI itself needs no library beside the executable on any macOS it supports. Your program might, if it:

- uses the standard library's `Span` types itself (`Span`, `RawSpan`, `MutableSpan`, `OutputSpan` and their kin), or
- links swift-collections 1.4 or later.

Either can make it link `libswiftCompatibilitySpan.dylib`, which macOS has only from version 26. Run `otool -L` on the
executable to see whether it does. A program that links the library stops at launch on macOS 15, once copied
out of `.build`:

```
Library not loaded: @rpath/libswiftCompatibilitySpan.dylib
```

There are two ways out.

**Ship the library beside the executable.** Copy it from `usr/lib/swift-6.2/macosx/` in the toolchain that built the
program, and sign it with your own identity if you notarise the program:

| Toolchain | Where it is |
|---|---|
| Xcode's | `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain` |
| swift.org's or swiftly's | `~/Library/Developer/Toolchains/swift-<version>-RELEASE.xctoolchain` |

**Or link it weakly**, which is safe only if the code that needs it never runs before macOS 26:

```bash
swift build -c release -Xlinker -weak_library -Xlinker <that directory>/libswiftCompatibilitySpan.dylib
```

To check a built program, run `Tools/check-span-compatibility.sh <executable>` from a TUI checkout. It fails on any
load of the library, strong or weak, and on any symbol imported from it.

## Shipping Size

Everything here is optional. Each step costs something only you can weigh, and the savings are rough figures for a
hello-world app, so yours will differ.

| Step | Saves about | Costs |
|---|---|---|
| Depend on fewer modules | The most of any step: see <doc:ChoosingProducts> | A product per module you use, in your `Package.swift` |
| `strip` | Half | Crash reports and profiles show addresses, until you symbolicate them |
| The `DeadStripUnusedAPI` trait, on by default | 15% | A plugin may not load |
| The `UnexportTUISymbols` trait, on by default | 3% | A plugin may not load, and a dynamic library no longer exports TUI |
| `-Xlinker -deduplicate` | 8% | Some key paths and closures compare equal |

### Strip the Program

`swift build -c release` does not strip the program, so its symbol tables and debug map are still in it:

```bash
strip .build/release/MyApp
```

Crash reports and profiles then show addresses, so keep the dSYM to symbolicate them. On macOS, `swift build -c release`
already makes one and leaves `MyApp.dSYM` beside the executable. If you make your own, `dsymutil` must run before
`strip`.

In Xcode, use Strip Linked Product (`STRIP_INSTALLED_PRODUCT`) with `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`. Xcode
applies it only when it installs or archives the product (`DEPLOYMENT_POSTPROCESSING = YES`), so a plain Release build
stays unstripped.

### The Two Default Traits

TUI has two package traits that make a program smaller, and both are on unless you turn them off. An ordinary app
never notices them.

- `DeadStripUnusedAPI` removes the TUI API your app never calls. It works through the linker's dead stripping, so an
  Xcode app needs `DEAD_CODE_STRIPPING = YES`, which is not Xcode's default.
- `UnexportTUISymbols` removes TUI's entries from the program's export table, whose bytes `strip` leaves in place. It
  works on every link that contains TUI, including a `.dynamic` library of your own. It also hides your own extensions
  of TUI's types and protocols (`extension View { func card() }`, `extension Color { static var brand }`) and your
  conformances of TUI's types to your protocols, because Swift names those symbols after the TUI module.

They matter only if something outside your program reaches for TUI's symbols, or you set your own export list:

| If | Then | Turn off |
|---|---|---|
| A plugin you `dlopen` calls TUI API your app itself never calls | The plugin no longer loads | Both |
| A plugin you `dlopen` calls any TUI API through your app | The plugin no longer loads ("symbol not found in flat namespace") | `UnexportTUISymbols` |
| A plugin calls one of your app's extensions of TUI's types | The plugin no longer loads | `UnexportTUISymbols` |
| An app uses TUI through a dynamic library of yours | The app fails to link ("Undefined symbols"), or if built against an older build of the library, to launch ("Symbol not found") | `UnexportTUISymbols` |
| An app calls your library's extensions of TUI's types | The app fails to link, unless the compiler copied the extension's body into it | `UnexportTUISymbols` |
| You pass the linker `-no_exported_symbols`, `-exported_symbol` or `-exported_symbols_list` | The link stops ("-unexported_symbol cannot be used with -exported_symbol*"), as it would with `LD_EXPORT_SYMBOLS = NO` or `EXPORTED_SYMBOLS_FILE` in Xcode | `UnexportTUISymbols` |

A trait is turned off where your package depends on TUI. Name the traits to keep:

```swift
// Export TUI's symbols, and keep removing the API the app never calls.
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: ["DeadStripUnusedAPI"])

// Turn off every default trait of TUI's, these two included.
.package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main", traits: [])
```

The program's own remaining exports can go too, for very little more. Add `-Xlinker -unexported_symbol -Xlinker '*'`
to the link, unless a plugin is linked against the executable (`-bundle_loader`) or calls `dlsym` on it.

### Merge Identical Functions

```bash
swift build -c release -Xlinker -deduplicate
```

This has the linker give functions with identical machine code one address, across your whole program. An Xcode
Release build already does it: Xcode hands the linker `-Os`, and the linker then folds them. `swift build` does not.

To turn it on in your own manifest instead of on each build:

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

The cost is that merged functions can no longer be told apart:

- **Key paths.** Swift identifies a key path to a computed property by its getter's address. So two key paths with one
  root and one value type whose getters compile alike (`var a: Int { x }` and `var b: Int { x }`, or two constants)
  compare and hash equal. They still read the same values, but code that uses key paths as names can tell: a `Set` or
  `Dictionary` of key paths, `KeyPathComparator` equality (a ``Table`` then treats two such columns as one), and
  writable key paths whose setters differ.
- **Closures.** Swift closures compared by function pointer can compare equal. `@convention(c)` functions are not
  merged.
- **Reports.** A crash report or profile may name one of several merged functions.

To keep key paths and closures distinct, add `-Xlinker -no_deduplicate_allow_swift_addr_ref`. It saves about 2%
instead. In Xcode, where deduplication is already on:

```
OTHER_LDFLAGS = $(inherited) -Xlinker -no_deduplicate_allow_swift_addr_ref
```

TUI's own code is checked under this flag on each change, with Swift 6.4.0 and Xcode's 6.2.4; other compilers are
unchecked. For your own code, `Tools/DedupCheck/dedup_check.py --report` lists what the flag did to your program. Run it
before `strip`; [its README](https://github.com/wadetregaskis/TUI/blob/main/Tools/DedupCheck/README.md) says how.

## Build Time

A clean release build of TUI takes minutes, not seconds. Two things decide most of it.

**Which compiler you have.** Run `swift --version`. If it prints `Build config: +assertions`, your compiler is an
assertions build, and Xcode's own Swift of the same version compiles TUI in about a quarter less time. swift.org's 6.2.4
for macOS is an assertions build, whether installed by hand or by swiftly; its 6.3.3 and 6.4.0 are not.

With Xcode installed, build with its toolchain:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release
```

Both halves are needed. `DEVELOPER_DIR` alone does not change which compiler swiftly's `swift` runs, and
`xcrun --toolchain XcodeDefault` without it runs the Command Line Tools' `swift` whenever `xcode-select` points at them.

**How little more cores help.** A release build compiles each module as one whole-module job, and the modules build in
a chain. Inside a job, type checking and the optimiser take most of the time and run on one thread; only the final code
generation spreads across cores.

## See Also

- <doc:ChoosingProducts>
- <doc:ModuleIndex>
