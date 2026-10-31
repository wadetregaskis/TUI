# Choosing Products

Depend on the whole framework, or only on the modules your app uses.

## Overview

Depend on the `TUI` product and write `import TUI`, as you would `import SwiftUI`. That is the default, it is
what every example in these docs assumes, and it is the simplest: every view, modifier and type is there, and
nothing below needs your attention.

TUI is also built as separate modules, and each module an app may want on its own is a library product of its
own. An app can list the products of the modules it uses instead of `TUI`, and SwiftPM then compiles and links
only those modules and the ones they are built on. A stripped release build of a hello world that depends only on
`TUIApp` comes out about 40% smaller than one that depends on `TUI`, and it builds a little faster.

### Depending on modules

List each product in your target's `dependencies:`, and import its module (it has the product's name):

```swift
.executableTarget(
    name: "MyApp",
    dependencies: [
        .product(name: "TUIApp", package: "TUI"),
        .product(name: "TUITables", package: "TUI"),
    ]
)
```

```swift
import TUIApp
import TUITables
```

Every app needs `TUIApp`: `App`, `Scene`, `WindowGroup`, the run loop and the terminal. It brings the two modules
it is built on: `TUIFoundation`, which has `View`, `Text`, the stacks, `ScrollView`, `Button`, `Toggle`, `Label`,
layout, state, the environment and focus, and `TUIChrome`, which has the status bar, the toolbars, the
notifications and `.help`. Then add the product of each module whose names you use:

| Product | What it has | Brings with it |
|---|---|---|
| `TUILists` | `List`, `OutlineGroup`, `EditMode`, the list styles | |
| `TUITables` | `Table`, its columns and rows, the table styles | `TUILists` |
| `TUITabs` | `TabView`, `Tab`, `TabSection`, the tab styles | `TUILists`, `TUIPresentation` |
| `TUIGrid` | `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` | |
| `TUINavigation` | `NavigationStack`, `NavigationPath`, `NavigationLink`, the zoom transition and `.matchedTransitionSource`, the split views, the inspector | |
| `TUIPresentation` | `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal` | `TUIChrome` |
| `TUIMenus` | `Menu`, `ControlGroup`, `.contextMenu`, the menu styles | |
| `TUIFilePanels` | `fileImporter`, `fileExporter`, `fileMover`, the `fileDialog` modifiers: the open and save panels | `TUINavigation`, `TUIPickers`, `TUIPresentation`, `TUITables`, `TUITextInput` |
| `TUICommands` | `Commands`, `CommandMenu`, `CommandGroup`, `CommandGroupPlacement`: the menu bar | `TUIApp`, `TUIPresentation` |
| `TUIScenes` | `Settings` (presented as a sheet) and `AlertScene`, and the scene modifiers for alerts | `TUIApp`, `TUIPresentation` |
| `TUITextInput` | `TextField`, `SecureField`, `TextEditor` | |
| `TUIPickers` | `Picker`, `RadioButtonGroup`, `DatePicker` | |
| `TUINumericControls` | `Slider`, `Stepper`, `Gauge`, `ProgressView` | |
| `TUIForms` | `Form`, `LabeledContent`, `GroupBox`, `Card`, `Panel` | |
| `TUISearch` | `.searchable`, search tokens and scopes | `TUITextInput`, `TUIPickers` |
| `TUIEffects` | transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition`, `.matchedGeometryEffect` | |
| `TUIBitmaps` | `Image` from a file, a URL or a bundle, `AsyncImage`, the `.image*` options | `TUIImage` |
| `TUITabImages` | `Tab(_:image:…)`, a tab whose picture is an image resource named by a string (a product of its own so that neither of the two it brings pays for the other) | `TUIBitmaps`, `TUITabs` |
| `TUIColorPicker` | `ColorPicker`, `ColorPickerPanel`, `GradientEditorPanel` | `TUIPresentation`, `TUITabs`, `TUITextInput`, `TUINumericControls` |
| `TUICurveEditors` | `ToneCurveEditorPanel`, `ChannelCurveEditorPanel` | `TUIColorPicker`, `TUIImage`, `TUIPickers` |
| `TUIAppKit` | `Color(nsColor:)`, `NSColor(_:)`, `Image(nsImage:)` and the other bridges to AppKit and Core Graphics (Apple platforms) | `TUIBitmaps` |
| `TUIFilePanelsAppKit` | `.fileDialogSystemIcons()`, the file panels drawn with the Finder's icons (Apple platforms; a product of its own so that `TUIAppKit` does not bring the file panels) | `TUIAppKit`, `TUIFilePanels` |
| `TUIMacros` | the `@Animatable` and `@AnimatableIgnored` macros (it builds swift-syntax) | `TUICore` |

Every product in the table but `TUIMacros` brings `TUIFoundation` too, and every module in it but `TUIAppKit`,
`TUIFilePanelsAppKit` and `TUIMacros`, which are imported beside the others, re-exports the modules it is built on, so one import covers
them: `import TUITables` gives you `List` as well. `TUIFoundation`, `TUICore`, `TUIStyling`,
`TUIView` and `TUIImage` are products too, for a library that needs nothing more. `TUIFoundation`
re-exports `TUICore`, `TUIStyling` and `TUIView`; `TUIView` re-exports `TUICore` and
`TUIStyling`, whose `FrameBuffer` and `Color` its API names, and `TUIImage` re-exports `TUIStyling`, so
one import covers either. `TUICore` and `TUIStyling` re-export nothing.

### The products decide what is built; the imports only what you can see

SwiftPM compiles and links the products your target lists, and the modules they are built on, whatever your files
import. A target that depends on `TUI` and writes only `import TUITables` is as large as one that writes
`import TUI`, and a target that does not list `TUITables` cannot import it.

So when you forget a product, the compiler names what it cannot find, not where it is:

```
error: cannot find 'Table' in scope
error: value of type 'Text' has no member 'tableStyle'
```

and an `import` of a module whose product you have not listed fails with `no such module 'TUITables'` (SwiftPM's
own build system) or `unable to resolve module dependency: 'TUITables'` (Swift Build, the default from Swift
6.4 on macOS). <doc:ModuleIndex> lists every public name with its module and product.

One case compiles when it should not: if another package your app depends on lists a TUI product, your files can
import that module without your target listing it, because it is in the build anyway. Declare it all the same:
your build breaks the day that package stops depending on it.

### Mixing them is safe, and gives you everything

An app can list `TUI` beside module products, or depend on a library that depends on `TUI`: each module is
compiled and linked into the app once, and the types are the same types everywhere. But the app is then as large
as the `TUI` app, because anything in its graph that depends on `TUI` brings in every module.

So if you write a **library** built on TUI, depend on the module products it uses (or on `TUIFoundation`),
never on `TUI`, or every app that uses your library links all of TUI.

### Never build a dynamic library from TUI beside a static TUI product

If your package makes a `.dynamic` library product out of TUI's modules, do not let an app link that library and
also a TUI product statically:

- With SwiftPM's own build system, the app holds two copies of every module they share: the Objective-C runtime
  warns that a class "is implemented in both", a view made in the library fails an `is` check against the same type
  in the app, and each global exists twice, so two calls can see two different values.
- Swift Build (the default from Swift 6.4 on macOS, and Xcode) avoids the second copy by making the shared modules
  dynamic libraries of their own, which the app must then ship; and another app in the same package that depends
  on your dynamic library alone then fails to link (Swift 6.4's `swift build`), or the build fails with "Multiple
  commands produce" the framework (`xcodebuild`).

An app that reaches TUI only through your dynamic library works with either build system, as long as no app in
the same package also links a TUI product statically. Static mixes, the ordinary kind, are all fine.

In a macOS release build, TUI's default trait `UnexportTUISymbols` keeps TUI's symbols out of what your
dynamic library exports (its own symbols still go out), so an app that uses TUI's API through the library fails to
link with "Undefined symbols", or, built against an older build of the library, to launch with "Symbol not found".
An app that calls only your library's own API is unaffected, except where that API extends a TUI type or protocol
(`extension Color { static var brand }`, `extension View { func card() }`) or conforms one to your protocol: Swift
names those symbols after the TUI module, so they leave your library's exports with TUI's, and an app calling
one fails to link unless the compiler copied its body into the app. To export TUI from your library, depend on TUI
with that trait off and the other default one kept, `.package(url: …, from: …, traits: ["DeadStripUnusedAPI"])`.

## Where the module shows

Whichever products you depend on, a type's full name includes the module that declares it, not `TUI`:

- The debugger and `String(reflecting:)` show `TUILists.List<…>` and `TUIApp.WindowGroup<…>`.
- `NavigationPath`'s ``NavigationPath/codable`` representation stores each value's type by its mangled name, which
  includes its module, so a saved path holding a TUI type stops decoding if that type moves to another module.
  TUI's types still move between modules from version to version before 1.0; keep such a path within one
  version.
- The resource bundle that holds TUI's translations and version is `TUI_TUIStrings` (named for the package
  and the module that owns the resources), whichever product you use.
- ``renderOnce(content:)``, which draws a view once without the run loop, is `TUIApp`'s: a tool that uses only it
  still depends on `TUIApp`.

Module and product names are now part of what you depend on: if a module is renamed or split, a `Package.swift` that
lists it changes with it. An app on `TUI` never sees such a change.
