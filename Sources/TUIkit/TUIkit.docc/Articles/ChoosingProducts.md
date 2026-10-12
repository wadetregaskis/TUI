# Choosing Products

Depend on the whole framework, or only on the modules your app uses.

## Overview

Depend on the `TUIkit` product and write `import TUIkit`, as you would `import SwiftUI`. That is the default, it is
what every example in these docs assumes, and it is the simplest: every view, modifier and type is there, and
nothing below needs your attention.

TUIkit is also built as separate modules, and each module an app may want on its own is a library product of its
own. An app can list the products of the modules it uses instead of `TUIkit`, and SwiftPM then compiles and links
only those modules and the ones they are built on. Measured on 2026-10-11 with Swift 6.4.0 (`swift build -c
release` with TUIkit's default traits, then `strip`), a hello world (`Text("Hello, world")` in a `WindowGroup`):

| The app depends on | Stripped size | TUIkit modules compiled |
|---|--:|--:|
| `TUIkit` | 9,552,376 bytes | 25, the umbrella, and the C image decoder |
| `TUIkitApp` | 5,964,832 bytes (−37.6%) | 8 |
| `TUIkitApp` and `TUIkitColorPicker`, with one `ColorPicker` | 7,833,208 bytes | 14 |

Launch time and memory use have not been measured.

### Depending on modules

List each product in your target's `dependencies:`, and import its module (it has the product's name):

```swift
.executableTarget(
    name: "MyApp",
    dependencies: [
        .product(name: "TUIkitApp", package: "TUIkit"),
        .product(name: "TUIkitTables", package: "TUIkit"),
    ]
)
```

```swift
import TUIkitApp
import TUIkitTables
```

Every app needs `TUIkitApp`: `App`, `Scene`, `WindowGroup`, the run loop and the terminal. It brings the two modules
it is built on: `TUIkitFoundation`, which has `View`, `Text`, the stacks, `ScrollView`, `Button`, `Toggle`, `Label`,
layout, state, the environment and focus, and `TUIkitChrome`, which has the status bar, the toolbars, the
notifications and `.help`. Then add the product of each module whose names you use:

| Product | What it has | Brings with it |
|---|---|---|
| `TUIkitLists` | `List`, `OutlineGroup`, `EditMode`, the list styles | |
| `TUIkitTables` | `Table`, its columns and rows, the table styles | `TUIkitLists` |
| `TUIkitTabs` | `TabView`, `Tab`, `TabSection`, the tab styles | `TUIkitLists` |
| `TUIkitGrid` | `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` | |
| `TUIkitNavigation` | `NavigationStack`, `NavigationPath`, `NavigationLink`, the split views, the inspector | |
| `TUIkitPresentation` | `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal` | `TUIkitChrome` |
| `TUIkitMenus` | `Menu`, `ControlGroup`, `.contextMenu`, the menu styles | |
| `TUIkitTextInput` | `TextField`, `SecureField`, `TextEditor` | |
| `TUIkitPickers` | `Picker`, `RadioButtonGroup`, `DatePicker` | |
| `TUIkitNumericControls` | `Slider`, `Stepper`, `Gauge`, `ProgressView` | |
| `TUIkitForms` | `Form`, `LabeledContent`, `GroupBox`, `Card`, `Panel` | |
| `TUIkitSearch` | `.searchable`, search tokens and scopes | `TUIkitTextInput`, `TUIkitPickers` |
| `TUIkitEffects` | transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition` | |
| `TUIkitBitmaps` | `Image` from a file, a URL or a bundle, `AsyncImage`, the `.image*` options | `TUIkitImage` |
| `TUIkitColorPicker` | `ColorPicker`, `ColorPickerPanel` | `TUIkitPresentation`, `TUIkitTabs`, `TUIkitTextInput`, `TUIkitNumericControls` |
| `TUIkitColorEditors` | `GradientEditorPanel`, `ToneCurveEditorPanel`, `ChannelCurveEditorPanel` | `TUIkitColorPicker`, `TUIkitImage`, `TUIkitPickers` |
| `TUIkitAppKit` | `Color(nsColor:)`, `NSColor(_:)`, `Image(nsImage:)` and the other bridges to AppKit and Core Graphics (Apple platforms) | `TUIkitBitmaps` |
| `TUIkitMacros` | the `@Animatable` and `@AnimatableIgnored` macros (it builds swift-syntax) | `TUIkitCore` |

Every product in the table but `TUIkitMacros` brings `TUIkitFoundation` too, and every module in it but `TUIkitAppKit`
and `TUIkitMacros`, which are imported beside the others, re-exports the modules it is built on, so one import covers
them: `import TUIkitTables` gives you `List` as well. `TUIkitFoundation`, `TUIkitCore`, `TUIkitStyling`,
`TUIkitView` and `TUIkitImage` are products too, for a library that needs nothing more. `TUIkitFoundation`
re-exports `TUIkitCore`, `TUIkitStyling` and `TUIkitView`, but those four lower modules re-export nothing: a file
that imports `TUIkitView` or `TUIkitImage` also imports the module of each lower type it names, `TUIkitStyling` for
`Color` and `TUIkitCore` for `FrameBuffer`. The product brings those modules, so they need no product of their own.

### The products decide what is built; the imports only what you can see

SwiftPM compiles and links the products your target lists, and the modules they are built on, whatever your files
import. A target that depends on `TUIkit` and writes only `import TUIkitTables` is as large as one that writes
`import TUIkit`, and a target that does not list `TUIkitTables` cannot import it.

So when you forget a product, the compiler names what it cannot find, not where it is:

```
error: cannot find 'Table' in scope
error: value of type 'Text' has no member 'tableStyle'
```

and an `import` of a module whose product you have not listed fails with `no such module 'TUIkitTables'` (SwiftPM's
own build system) or `unable to resolve module dependency: 'TUIkitTables'` (Swift Build, the default from Swift
6.4 on macOS). <doc:ModuleIndex> lists every public name with its module and product.

One case compiles when it should not: if another package your app depends on lists a TUIkit product, your files can
import that module without your target listing it, because it is in the build anyway. Declare it all the same:
your build breaks the day that package stops depending on it.

### Mixing them is safe, and gives you everything

An app can list `TUIkit` beside module products, or depend on a library that depends on `TUIkit`: each module is
compiled and linked into the app once, and the types are the same types everywhere. But the app is then as large
as the `TUIkit` app, because anything in its graph that depends on `TUIkit` brings in every module.

So if you write a **library** built on TUIkit, depend on the module products it uses (or on `TUIkitFoundation`),
never on `TUIkit`, or every app that uses your library links all of TUIkit.

### Never build a dynamic library from TUIkit beside a static TUIkit product

If your package makes a `.dynamic` library product out of TUIkit's modules, do not let an app link that library and
also a TUIkit product statically:

- With SwiftPM's own build system, the app holds two copies of every module they share: the Objective-C runtime
  warns that a class "is implemented in both", a view made in the library fails an `is` check against the same type
  in the app, and each global exists twice, so two calls can see two different values.
- Swift Build (the default from Swift 6.4 on macOS, and Xcode) avoids the second copy by making the shared modules
  dynamic libraries of their own, which the app must then ship; and another app in the same package that depends
  on your dynamic library alone then fails to link (Swift 6.4's `swift build`), or the build fails with "Multiple
  commands produce" the framework (`xcodebuild`).

An app that reaches TUIkit only through your dynamic library works with either build system, as long as no app in
the same package also links a TUIkit product statically. Static mixes, the ordinary kind, are all fine.

In a macOS release build, TUIkit's default trait `UnexportTUIkitSymbols` keeps TUIkit's symbols out of what your
dynamic library exports (its own symbols still go out), so an app that uses TUIkit's API through the library fails to
link with "Undefined symbols", or, built against an older build of the library, to launch with "Symbol not found".
An app that calls only your library's own API is unaffected. To export TUIkit from your library, depend on TUIkit
with that trait off and the other default one kept, `.package(url: …, from: …, traits: ["DeadStripUnusedAPI"])`
(the README's "Shipping size" has what each trait does).

## Where the module shows

Whichever products you depend on, a type's full name includes the module that declares it, not `TUIkit`:

- The debugger and `String(reflecting:)` show `TUIkitLists.List<…>` and `TUIkitApp.WindowGroup<…>`.
- `NavigationPath`'s ``NavigationPath/codable`` representation stores each value's type by its mangled name, which
  includes its module, so a saved path holding a TUIkit type stops decoding if that type moves to another module.
  TUIkit's types still move between modules from version to version before 1.0; keep such a path within one
  version.
- The resource bundle that holds TUIkit's translations and version is `TUIkit_TUIkitStrings` (named for the package
  and the module that owns the resources), whichever product you use.
- ``renderOnce(content:)``, which draws a view once without the run loop, is `TUIkitApp`'s: a tool that uses only it
  still depends on `TUIkitApp`.

Module and product names are now part of what you depend on: if a module is renamed or split, a `Package.swift` that
lists it changes with it. An app on `TUIkit` never sees such a change.
