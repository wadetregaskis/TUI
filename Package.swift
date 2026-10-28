// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

/// Every library module: what TUIIntegrationTests, the one test target that can see everything, depends on.
let umbrellaTestDependencies: [Target.Dependency] = [
    "TUI", "TUIApp", "TUIBitmaps", "TUIChrome", "TUIColorPicker", "TUICommands", "TUICurveEditors",
    "TUIEffects", "TUIFilePanelImages", "TUIFilePanels", "TUIForms", "TUIFoundation", "TUIGrid", "TUILists",
    "TUIMenus", "TUINavigation", "TUINumericControls", "TUIPickers", "TUIPresentation", "TUIScenes", "TUISearch",
    "TUIStrings", "TUITabImages", "TUITables", "TUITabs", "TUITerminalHost", "TUITextInput",
    "TUIAppKit", "TUIFilePanelsAppKit", "TUIWidthCorpus", "CTestSupport",
]

let package = Package(
    name: "TUI",
    // Minimum deployment targets for Apple platforms
    // Linux is automatically supported (no platform specification needed)
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // What a client's target lists among its `dependencies:` decides what SwiftPM compiles and links into
        // it: the closure of the targets of the products it names. Its `import` lines decide only which names
        // its files can see. So a target that depends on `TUI` compiles and links every module below,
        // whichever of them it imports, and one that depends on `TUILists` alone compiles and links
        // TUILists and what TUILists is built on, and nothing else (measured on a miniature of this
        // package: `Per-module products.md` in Documentation/Historical/Module split, compile time and
        // binary size/, which also has the rest of what is said here).

        // ── The umbrella: the default ───────────────────────────────────────────────────────────────────
        // `import TUI` is the whole framework, as `import SwiftUI` is the whole of SwiftUI: every module
        // below but TUIAppKit, TUIFilePanelsAppKit and TUIMacros, which are opt-in. Start here; the README and the docs do.
        .library(name: "TUI", targets: ["TUI"]),

        // ── À la carte: one product per module ──────────────────────────────────────────────────────────
        // For an app that wants to compile and link less than the whole framework, and for a LIBRARY built on
        // TUI, which should depend on these and never on `TUI`: anything in an app's graph that depends
        // on `TUI` gives that app the whole framework, whatever the app itself lists. Each module from
        // TUIFoundation up re-exports the modules it is built on (its Sources/<module>/Exports.swift), so a
        // client imports the modules whose names it uses and gets their foundations with them, as TUIView
        // and TUIImage do the lower modules their API names; TUICore, TUIStyling, TUIAppKit,
        // TUIFilePanelsAppKit and TUIMacros re-export nothing. Mixing these with `TUI` in one
        // app is safe: each module is linked into it once. What is not: a `.dynamic` library product of the
        // client's own built from TUI while an app also links a TUI product statically (two copies of
        // the shared modules with SwiftPM's native build system; Swift Build turns them into dynamic
        // libraries, which the app must then ship, and can fail to link a second app of the package). And
        // in a macOS release build such a library exports none of TUI's symbols, so a client cannot use
        // TUI through it (the trait `UnexportTUISymbols`, at the end of this file). The
        // user guide is Sources/TUI/TUI.docc/Articles/ChoosingProducts.md, and the docs' generated
        // ModuleIndex page lists every public name with its module and product.
        //
        // TUIApp: `App`, `Scene`, `WindowGroup` and the Scene modifiers, the run loop and the terminal
        // (POSIX: it has no Windows build), and `renderOnce`. Every app needs it, beside the products of the
        // views it uses; a library of views does not. Re-exports TUIChrome and TUIFoundation.
        .library(name: "TUIApp", targets: ["TUIApp"]),
        // TUIFoundation: what every module below is built on and re-exports: `View` and `Text`, the
        // stacks, `ScrollView`, `Button`, `Toggle`, `Label`, `Image(systemName:)`, layout, state, the
        // environment, focus and rendering. It re-exports TUICore, TUIStyling, TUIView, and the two
        // modules carved beside it that have no product of their own, TUIStrings (localization, the SF
        // Symbols names, the resource bundle) and TUITerminalHost (the terminal's identity and quirks).
        // For a library of views that needs no other module; it cannot run an app (that is TUIApp).
        .library(name: "TUIFoundation", targets: ["TUIFoundation"]),
        // TUIBitmaps: `Image` from a file, a URL or a bundle, `AsyncImage`, the `.image*` rendering
        // options and `.terminalGraphics(_:)`. Re-exports TUIImage (the decoders and `ASCIIConverter`).
        .library(name: "TUIBitmaps", targets: ["TUIBitmaps"]),
        // TUIChrome: what is drawn around the content: the `StatusBar` view and `.statusBarItems`, the
        // toolbars, the notifications, tooltips and `.help`. TUIApp and TUIPresentation re-export it,
        // so an app rarely names it; a product of its own lets a library that adds a toolbar item or a status
        // bar item depend on it without TUIApp's console layer, which has no Windows build.
        .library(name: "TUIChrome", targets: ["TUIChrome"]),
        // TUIColorPicker: `ColorPicker` and `ColorPickerPanel` with its swatches, and
        // `GradientEditorPanel`. Re-exports TUINumericControls, TUIPresentation, TUITabs and
        // TUITextInput, which its panels are made of.
        .library(name: "TUIColorPicker", targets: ["TUIColorPicker"]),
        // TUICommands: SwiftUI's commands — `Commands`, `CommandMenu`, `CommandGroup` and the placements —
        // and the scene they are declared on: `Scene.commands(content:)` and its kin draw the menu bar.
        // Re-exports TUIApp, whose `Scene` they extend, and TUIPresentation.
        .library(name: "TUICommands", targets: ["TUICommands"]),
        // TUIScenes: the scenes presented over an app's windows — the `Settings` scene, as a sheet, and
        // `AlertScene` — and the scene modifiers for the alerts a scene presents. Re-exports TUIApp, whose
        // scene presenter shows them, and TUIPresentation, whose sheet and alert they are drawn with.
        .library(name: "TUIScenes", targets: ["TUIScenes"]),
        // TUICurveEditors: the tone-curve and channel-curve editor panels, which host `ColorPickerPanel`'s
        // body. Re-exports TUIColorPicker, TUIImage (their initializers take an `ASCIIToneCurve`),
        // TUINumericControls and TUIPickers.
        .library(name: "TUICurveEditors", targets: ["TUICurveEditors"]),
        // TUIEffects: transitions, content transitions, `.symbolEffect`, `.visualEffect`,
        // `.scrollTransition` and the colour effects.
        .library(name: "TUIEffects", targets: ["TUIEffects"]),
        // TUIFilePanels: `fileImporter`, `fileExporter`, `fileMover` and the `fileDialog` customizations, the
        // open and save panels TUI draws for them, `FileDialogBrowserOptions`, `FileDocument` on Apple platforms
        // and `UTType` where UniformTypeIdentifiers is absent. Re-exports TUIPresentation, TUITables and
        // TUITextInput, which its panel is made of.
        .library(name: "TUIFilePanels", targets: ["TUIFilePanels"]),
        // TUIForms: `Form`, `LabeledContent`, `GroupBox`, `Card` and `Panel`, and their styles.
        .library(name: "TUIForms", targets: ["TUIForms"]),
        // TUIGrid: `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` and `GridItem`.
        .library(name: "TUIGrid", targets: ["TUIGrid"]),
        // TUILists: `List`, `OutlineGroup`, `EditMode`, the list styles and the rows' separators, insets,
        // backgrounds, reordering and shortcuts.
        .library(name: "TUILists", targets: ["TUILists"]),
        // TUIMenus: `Menu`, `ControlGroup`, `.contextMenu`, `.menuStyle` and the menu styles.
        .library(name: "TUIMenus", targets: ["TUIMenus"]),
        // TUINavigation: `NavigationStack`, `NavigationPath`, `NavigationLink`, the split views and the
        // inspector.
        .library(name: "TUINavigation", targets: ["TUINavigation"]),
        // TUINumericControls: `Slider`, `Stepper`, `Gauge` and `ProgressView`, and their styles.
        .library(name: "TUINumericControls", targets: ["TUINumericControls"]),
        // TUIPickers: `Picker` and its styles, `RadioButtonGroup` and `DatePicker`.
        .library(name: "TUIPickers", targets: ["TUIPickers"]),
        // TUIPresentation: `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover`, `modal`
        // and the presentation modifiers. Re-exports TUIChrome.
        .library(name: "TUIPresentation", targets: ["TUIPresentation"]),
        // TUISearch: `.searchable`, the search tokens and scopes, `searchSuggestions` and
        // `dismissSearch`. Re-exports TUITextInput and TUIPickers.
        .library(name: "TUISearch", targets: ["TUISearch"]),
        // TUITables: `Table`, its columns, rows and builders, the table styles and row drag and drop.
        // Re-exports TUILists.
        .library(name: "TUITables", targets: ["TUITables"]),
        // TUITabs: `TabView`, `Tab`, `TabSection` and the tab styles. Re-exports TUILists and
        // TUIPresentation, whose adapting presenter a tab's popover is shown with.
        .library(name: "TUITabs", targets: ["TUITabs"]),
        // TUITabImages: `Tab(_:image:…)`, the tabs whose picture is an image resource named by a string, found
        // as `Image(_:bundle:)` finds it. Re-exports TUIBitmaps and TUITabs, which it is built on, so that
        // neither pays for the other (decisions C11).
        .library(name: "TUITabImages", targets: ["TUITabImages"]),
        // TUIFilePanelImages: `fileDialogPicturePreviews()`, the file panels previewing a selected picture.
        // Re-exports TUIBitmaps and TUIFilePanels, which it is built on, so that neither pays for the other
        // (the owner's PREVIEW-IMAGES option "glue", 2026-10-28).
        .library(name: "TUIFilePanelImages", targets: ["TUIFilePanelImages"]),
        // TUITextInput: `TextField`, `SecureField` and `TextEditor`.
        .library(name: "TUITextInput", targets: ["TUITextInput"]),

        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        // The four modules beneath TUIFoundation: products of their own since before the split, and the
        // four that build on Windows today. TUIFoundation is built on TUICore, TUIStyling and
        // TUIView and re-exports them; TUIImage is the bitmap path's (TUIBitmaps, TUICurveEditors
        // and TUIAppKit use it). TUIView re-exports TUICore and TUIStyling, and TUIImage
        // TUIStyling, the modules their API names (decisions B-C9B-3), so a client of either product
        // writes one import and needs no product of the lower ones; TUICore and TUIStyling re-export
        // nothing.
        .library(name: "TUICore", targets: ["TUICore"]),
        .library(name: "TUIStyling", targets: ["TUIStyling"]),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        .library(name: "TUIView", targets: ["TUIView"]),
        .library(name: "TUIImage", targets: ["TUIImage"]),

        // ── Bridges to Apple's graphics types (NSColor, CGColor, CGImage, NSImage) ────────────────────────
        // A module of its own so that nothing TUI is built from imports
        // AppKit — see Sources/TUIAppKit/Exports.swift.
        .library(name: "TUIAppKit", targets: ["TUIAppKit"]),
        // TUIFilePanelsAppKit: `fileDialogSystemIcons()`, the file panels drawn with the Finder's icons. Opt-in
        // like TUIAppKit, and a module of its own so that TUIAppKit does not depend on TUIFilePanels
        // (decisions A-FP2-1).
        .library(name: "TUIFilePanelsAppKit", targets: ["TUIFilePanelsAppKit"]),

        // ── SwiftUI's `@Animatable` and `@Entry` macros, opt-in (decisions A52) ─────────────────────────
        // A product of their own, so that only an app that depends on it builds
        // the compiler plugin and swift-syntax: SwiftPM builds by target, and a
        // client of `TUI` alone compiles none of swift-syntax. It does still
        // RESOLVE and fetch it (measured: resolution is by package, so the
        // repository is cloned into such a client's checkouts), which is why
        // the version range below is kept wide.
        .library(name: "TUIMacros", targets: ["TUIMacros"]),

        // ── App ─────────────────────────────────────────────────────────────────────────────────────────
        .executable(name: "Example", targets: ["Example"]),

        // ── Stress test (perf instrument; secondarily a complex-TUI demo) ────────────────────────────────
        .executable(name: "Stress", targets: ["Stress"]),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executable(name: "EmojiBugScanner", targets: ["EmojiBugScanner"]),
        .executable(name: "EmojiBenchmark",  targets: ["EmojiBenchmark"]),
        .executable(name: "RenderHarness",   targets: ["RenderHarness"]),
        .executable(name: "ImageHarness",    targets: ["ImageHarness"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        // For the `TUIMacros` product's compiler plugin only. From the
        // release line of the oldest toolchain the package supports (602 is
        // Swift 6.2's) up to the next major, as macro packages commonly take
        // it: every client of TUI resolves this range, macros or not, so a
        // narrower one would refuse any app that also depends on a package
        // wanting a newer swift-syntax (a 602..<603 cap did, measured with
        // one requiring `from: "603.0.0"`). SwiftPM resolves the newest in
        // range, and takes swift-syntax PREBUILT only where one is published
        // for that version and toolchain: 602.0.0 for Swift 6.2 (Linux and
        // Windows; measured: none for 603, nor for 604 under 6.2), and
        // 604.0.0 for swift.org's Swift 6.4.0 on macOS (SwiftPM fetched it,
        // 2026-10-07, and Tools/ProductSmoke's build used it). So an app on
        // 6.2 that wants them pins `exact: "602.0.0"` itself. See decisions
        // B-D6M-2.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"700.0.0"),
        // ordo-one/benchmark is added conditionally at the bottom of this file
        // (gated on TUI_BENCHMARKS), so the default build/test graph stays
        // free of its plugin's upstream deprecation warnings and the jemalloc
        // build requirement.
    ],
    targets: [
        // Tools/validate-test-boundaries.sh keeps a hand copy of the four
        // library targets' `dependencies:` below (its `allowed_for` table,
        // which decides what each per-module test target may import). It
        // cannot read this file, so change that table whenever these change.

        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        .target(name: "CSTBImage", publicHeadersPath: "include"),
        .target(name: "TUICore"),
        .target(name: "TUIStyling"),

        // The width corpus (`TerminalWidthCorpus`): the grapheme clusters the
        // tests and the TerminalClientQuirks app iterate, and nothing a library
        // module reads. A target of its own so that no library build compiles
        // it: inside TUICore, whose job starts the chain every release build
        // waits on, its two tables took 0.39 s of SIL optimisation (2026-10-07).
        .target(name: "TUIWidthCorpus"),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        // TUIStyling came in for `Color: View`, which has to be declared in
        // the module that owns `View`: declared anywhere else, a `Color` in a
        // `@ViewBuilder` pack beside a generic view segfaults the debug
        // runtime while instantiating the pack's metadata. See §14 of
        // `Documentation/Colour and styling/Gradients where a colour is accepted.md` — it is a
        // toolchain bug, reproduced on Swift 6.2.4 and still present on the
        // 6.5-dev snapshot of 2026-08-30. PaletteEnvironment.swift and
        // ColorAnimation.swift moved down with it.
        //
        // It is no longer the only use. OpacityClaim.swift derives a
        // translucent paint's opacity claim from the `Color`s it painted with,
        // and RenderCache.swift records the surface `Color` a memoized buffer
        // was blended over. So a toolchain fix would let `Color: View` move
        // back up, but as the code stands the dependency would stay.
        .target(name: "TUIView", dependencies: ["TUICore", "TUIStyling"]),
        .target(name: "TUIImage", dependencies: ["CSTBImage", "TUIStyling"]),

        // ── The split's carved modules ──────────────────────────────────────────────────────────────────
        // Modules of the planned split (Documentation/Historical/Module split plan, revision 4) that a step
        // of Phase B has carved out of TUIFoundation into targets of their own. A side module, below it,
        // is one that TUIFoundation depends on and re-exports (Sources/TUIFoundation/Exports.swift); a
        // leaf, above it, depends on TUIFoundation, and the umbrella re-exports it. Either way `import
        // TUI` gives an app what it gave before. Tools/ModuleMap's `lower` lists (rules.json) say which
        // lower modules each may use; its `lower` check fails CI on any other.
        //
        // Step B2's two side modules need TUICore alone, so they compile beside TUIView, not after
        // it. TUIStrings is the SF Symbols name table, the inline-Markdown parser, the format styles and
        // localization, and it holds the framework's resources: the translation tables and VERSION, read
        // through its `ModuleResources`, in the bundle `TUI_TUIStrings`
        // (Tools/verify-versioned-consumer.sh runs a consumer that reads both). TUITerminalHost is the
        // terminal's facts as values: the host, its identity, quirks and capabilities.
        // MemberImportVisibility as on TUIFoundation, which compiled their files until B2.
        .target(
            name: "TUIStrings",
            dependencies: ["TUICore"],
            resources: [.copy("Localization/translations"), .copy("VERSION")],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUITerminalHost",
            dependencies: ["TUICore"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B3's leaf, the first module built ON TUIFoundation rather than under it: `App` and its run
        // loop, `Scene`, `WindowGroup` and the Scene modifiers, the console layer (the `Terminal` class with
        // its raw mode, input and replies, the signal handlers, the stdin source) and the run loop's rendering
        // (`ViewRenderer`, `FrameDiffWriter`, `renderOnce`). Nothing in TUIFoundation may use it
        // (Tools/ModuleMap's upward check), so the umbrella re-exports it, not TUIFoundation; it re-exports
        // TUIFoundation in turn (Sources/TUIApp/Exports.swift), and TUIChrome since step B5b (below):
        // the run loop draws the window chrome, the status bar and the notifications around the content. POSIX
        // by design: no Windows step builds it (CLAUDE.md).
        .target(
            name: "TUIApp",
            dependencies: ["TUIChrome", "TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Lane O13's leaf, built on TUIApp: SwiftUI's commands and the menu bar a scene that declares them
        // draws (refusal review O13, ruled 2026-10-12: a full menu bar). `Commands`, `CommandsBuilder`,
        // `CommandMenu`, `CommandGroup`, `CommandGroupPlacement` and `EmptyCommands`. On TUIApp because
        // `Scene.commands(content:)` is a modifier of TUIApp's `Scene`, and no lower module may see a scene;
        // the menu bar's drop-downs are TUIFoundation's menu engine, the one a pop-up `Menu` uses, so it needs
        // nothing of TUIMenus; on TUIPresentation for the app menu's About alert; on TUIPickers for
        // `DisplayCommands`, whose submenus are `Picker`s (A-MENUBAR-1). The run loop and the
        // chrome host reach the bar through hooks of their own that name nothing of this module (an opaque scene
        // declaration, the window chrome's menu-bar view), so an app that declares no commands links none of it. Nothing in TUIFoundation may use it
        // (Tools/ModuleMap's upward check), so the umbrella re-exports it. It re-exports TUIApp,
        // TUIFoundation and TUIPresentation (Sources/TUICommands/Exports.swift).
        .target(
            name: "TUICommands",
            dependencies: ["TUIApp", "TUIFoundation", "TUIPickers", "TUIPresentation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Lane O9's leaf, built on TUIApp and TUIPresentation: the scenes an app's scene presenter shows
        // over the window in front rather than as windows (refusal review O9, ruled 2026-10-12: (b)), the
        // `Settings` scene, presented as a sheet, and `AlertScene`, and the scene modifiers for the alerts a scene
        // presents (`dialogSeverity`, `dialogIcon`, `dialogSuppressionToggle`). On TUIApp because they are
        // scenes, and on TUIPresentation because they are drawn with its sheet and alert, which TUIApp does
        // not link: the presenter reaches them through a hook that names nothing of this module (`OverlayScene`),
        // so an app that declares neither links none of it. Nothing in TUIFoundation may use it
        // (Tools/ModuleMap's upward check), so the umbrella re-exports it. It re-exports TUIApp,
        // TUIFoundation and TUIPresentation (Sources/TUIScenes/Exports.swift). Like TUIApp it has no
        // Windows build.
        .target(
            name: "TUIScenes",
            dependencies: ["TUIApp", "TUIFoundation", "TUIPresentation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B4's leaf, built on TUIFoundation as TUIApp is: `ColorPicker`, its panel and swatches, the
        // gradient editor, and, until C9b moved them into TUICurveEditors (below), the tone-curve and
        // channel-curve editors.
        // The plan's map builds it on NumericControls, TextInput, Pickers, Tabs and Presentation. Presentation is a module of its own since step C1 (below), whose `Dialog`
        // and `.modal` its panels are made of (it depended on TUINavigation for them from step B5, while that
        // target compiled the presentations' directory too, and on nothing of the navigation containers'); Tabs is
        // one since step C3 (below), whose `TabView` and `Tab` its panel is laid out with (it depended on
        // TUILists for them from step B6, while that target compiled the tabs' directory too, and on nothing of
        // the lists'); NumericControls is one since step C7 (below), whose `Slider`s its channel rows are (it
        // depended on TUITextInput for them from step B7, while that target compiled their directory too); and
        // TextInput is TUITextInput since step B7 (below), whose `TextField` the panel's hex field is. Pickers
        // and TUIImage were the curve editors' alone, and left with them. Nothing in TUIFoundation may use
        // it (Tools/ModuleMap's upward check), so the umbrella re-exports it, and so does TUICurveEditors. The
        // module re-exports all five (Sources/TUIColorPicker/Exports.swift).
        .target(
            name: "TUIColorPicker",
            dependencies: [
                "TUIFoundation", "TUINumericControls", "TUIPresentation", "TUITabs", "TUITextInput",
            ],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // C9b's peel, out of TUIColorPicker above: `ToneCurveEditorPanel` and `ChannelCurveEditorPanel`
        // (Sources/TUICurveEditors). Each hosts the colour panel's body in the editor chrome `ColorPickerPanel`
        // is drawn in, but `ColorPicker` uses neither, so while they were TUIColorPicker's every app with a
        // `ColorPicker` compiled and linked them and what only they use (SIZE3's Q7, change (1), with per-module
        // products). C9b moved `GradientEditorPanel` here too, as TUIColorEditors; the owner moved it back on
        // 2026-10-12 ("GradientEditorPanel should stay with the general ColorPicker"), since it needs nothing
        // TUIColorPicker does not have, and the module was named for what it then held. Built on
        // TUIColorPicker, whose `_EditorPanelChrome`, `_ColorPickerBody`, `_ColorSwatchButtonStyle` and the
        // gradient editor's `StopChip` and `chipRows(count:)` are `package` for them; on TUIImage, whose
        // `ASCIIToneCurve` is in both panels' public initializers; on TUIPickers, whose `RadioButtonGroup` the
        // channel-curve editor picks its channel with; and on TUINumericControls, whose `Slider`s both are made
        // of. Not TUIImage itself, which is built on TUIStyling alone and has no `View`; not TUIBitmaps,
        // which would bring TUIColorPicker and its five modules into every app that shows an `Image`. Nothing
        // depends on it but the umbrella, which re-exports it, and the tests. It re-exports all five
        // (Sources/TUICurveEditors/Exports.swift).
        .target(
            name: "TUICurveEditors",
            dependencies: [
                "TUIColorPicker", "TUIFoundation", "TUIImage", "TUINumericControls", "TUIPickers",
            ],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5's leaf, built on TUIFoundation as the two above are: `NavigationStack`, `NavigationPath`,
        // `NavigationLink`, the split views and the inspector. It was the plan's first coarse GROUP, one target over
        // two planned modules' directories, until step C1 peeled the second, Sources/TUIPresentation, into the
        // target below; so since C1 it is an ordinary target at its default path, Sources/TUINavigation, and
        // depends on TUIFoundation alone, as the map's entry does (it depended on TUIChrome from step B5b
        // only for the presentations). Nothing in TUIFoundation may use it (Tools/ModuleMap's upward check), so
        // the umbrella re-exports it. It re-exports TUIFoundation (Sources/TUINavigation/Exports.swift).
        .target(
            name: "TUINavigation",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C1's module, the first PEEL: the presentations, which compiled into TUINavigation (above) from
        // step B5 until this step gave them a target of their own at their default path, Sources/TUIPresentation:
        // `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover` and `modal`, the dismissal
        // confirmation, dialog suppression, and the presentation modifiers (detents, sizing, background,
        // interaction). Built on TUIFoundation and TUIChrome, the map's edges: a presentation draws its
        // notifications with Chrome's `notificationHost(width:)`, and a modal docks its presenter's focus through
        // Chrome's presentation dock. It does not depend on TUINavigation, nor TUINavigation on it (no file
        // of either names a declaration of the other). Nothing in TUIFoundation may use it (Tools/ModuleMap's
        // upward check), so the umbrella re-exports it, and so do TUIColorPicker and TUITabs (A21). It
        // re-exports TUIFoundation and TUIChrome (Sources/TUIPresentation/Exports.swift).
        .target(
            name: "TUIPresentation",
            dependencies: ["TUIChrome", "TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B6's leaf, built on TUIFoundation as the three above are: `List` and its core, handler and styles,
        // the rows' separators, insets, backgrounds, reordering and shortcuts, `OutlineGroup` and `EditMode`, the row
        // memo a table keeps, and the sidebar list and lifted surface a tab view is drawn with. It was the plan's
        // second coarse group, one target over four planned modules' directories, until steps C2 to C4 peeled
        // Sources/TUITables, TUITabs and TUIGrid into the targets below; so since C4 it is an ordinary
        // target at its default path, Sources/TUILists. Nothing in TUIFoundation may use it (Tools/ModuleMap's
        // upward check), so the umbrella re-exports it, and so do TUITables and TUITabs. It re-exports
        // TUIFoundation (Sources/TUILists/Exports.swift).
        .target(
            name: "TUILists",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C2's peel, out of the Lists group above: `Table`, its columns, rows, builders and customization, the
        // outline rows, the table styles and row drag and drop (Sources/TUITables). Built on TUIFoundation and
        // TUILists, the map's edge: a table's rows run on the list's row engine (`ItemListHandler`, the row
        // memo, row selection, reorder and context menus), which stays in TUILists for `List`. TUILists does
        // not depend on it, nor does anything in TUIFoundation (Tools/ModuleMap's upward check), so the umbrella
        // re-exports it. It re-exports TUIFoundation and TUILists (Sources/TUITables/Exports.swift), so an
        // app that imports it has `List` too (plan §4).
        .target(
            name: "TUITables",
            dependencies: ["TUIFoundation", "TUILists"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C3's peel, out of the Lists group above: `TabView`, `Tab`, `TabSection`, `TabContent` with its builder
        // and modifiers, the tab strip, sidebar and customization, and the tab styles (Sources/TUITabs). Built on
        // TUIFoundation and TUILists, the map's edge: a `.sidebarAdaptable` tab view lists its tabs in a
        // `List`, a tab body is painted on the lists' lifted surface, and a tab's drop destination is a row's drop
        // slot. TUILists does not depend on it, nor does anything in TUIFoundation (Tools/ModuleMap's upward
        // check), so the umbrella re-exports it, and so do TUIColorPicker, whose panel is a `TabView`, and
        // TUITabImages, which adds `Tab`'s `image:` initialisers (decisions C11). Since
        // 2026-10-23 also on TUIPresentation (decisions A21, the owner's A21-TABPOPOVER option 1): a tab's
        // popover is shown with its adapting presenter, so it becomes a sheet in a compact size class as
        // `View.popover`'s does. TUIPresentation does not depend on it. It re-exports TUIFoundation,
        // TUILists and TUIPresentation (Sources/TUITabs/Exports.swift), so an app that imports it has
        // `List` too (plan §4).
        .target(
            name: "TUITabs",
            dependencies: ["TUIFoundation", "TUILists", "TUIPresentation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C4's peel, out of the Lists group above: `Grid`, `GridRow`, `LazyVGrid`, `LazyHGrid` and `GridItem`,
        // and the grid layout (Sources/TUIGrid). Built on TUIFoundation alone, the map's edge: a grid uses
        // nothing of the lists', which compiled it from step B6 until this step. TUILists does not depend on it,
        // nor does anything in TUIFoundation (Tools/ModuleMap's upward check), so the umbrella re-exports it, and
        // nothing else does. It re-exports TUIFoundation (Sources/TUIGrid/Exports.swift).
        .target(
            name: "TUIGrid",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B7's leaf, built on TUIFoundation as the four above are: `TextField`, `SecureField` and
        // `TextEditor`, their handlers, renderer, mouse handling, editing commands, undo and suggestions. It was the
        // plan's third and last coarse group, one target over five planned modules' directories, named after the one
        // the peels leave, until steps C5 to C8 peeled Sources/TUISearch, TUIForms, TUINumericControls and
        // TUIPickers into the targets below; so since C7, the last of them (after C8), it is an ordinary target at
        // its default path, Sources/TUITextInput, and no target compiles another module's directory. Nothing in
        // TUIFoundation may use it (Tools/ModuleMap's upward check), so the umbrella re-exports it, and so do
        // TUIColorPicker and TUISearch. It re-exports TUIFoundation (Sources/TUITextInput/Exports.swift).
        .target(
            name: "TUITextInput",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C7's peel, out of the TextInput group above: `Slider` with its ticks and value labels, `Stepper`,
        // `Gauge` and its concrete styles, `ProgressView` with its timer, their handlers and styles, the track and
        // indeterminate renderers and rasters they share with `.trackStyle`, and `.sliderShowsValue`
        // (Sources/TUINumericControls). Built on TUIFoundation alone, the map's edge: a numeric control names
        // nothing of the text inputs' or pickers', which compiled beside it from step B7 until this step and step C8.
        // TUITextInput does not depend on it, nor does anything in TUIFoundation (Tools/ModuleMap's upward
        // check), so the umbrella re-exports it, and so do TUIColorPicker and TUICurveEditors, whose channel
        // rows and editors are made of `Slider`s.
        // It re-exports TUIFoundation (Sources/TUINumericControls/Exports.swift).
        .target(
            name: "TUINumericControls",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C8's peel, out of the TextInput group above: `Picker` with its automatic, menu, inline, radio-group,
        // segmented and palette styles, `RadioButtonGroup` with its edge behaviour and its `FormControlRow`
        // conformance, `DatePicker` with its field, stepper-field, compact and graphical styles, and the pickers' SF
        // Symbols initializers (Sources/TUIPickers). Built on TUIFoundation alone, the map's edge: a picker
        // names nothing of the text inputs' or numeric controls', which compiled beside it from step B7 until this
        // step. TUITextInput does not depend on it, nor does anything in TUIFoundation (Tools/ModuleMap's
        // upward check), so the umbrella re-exports it, and so do TUICurveEditors, whose channel-curve editor
        // picks its channel with a `RadioButtonGroup`, and TUISearch, whose scope bar is a segmented `Picker`. It
        // re-exports TUIFoundation (Sources/TUIPickers/Exports.swift).
        .target(
            name: "TUIPickers",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C5's peel, out of the TextInput group above: `.searchable` and its search field, the search tokens
        // and their chips, the scopes and their bar, `searchSuggestions` and `searchCompletion`, the placements, the
        // toolbar behaviour and `dismissSearch` (Sources/TUISearch). Built on TUIFoundation, TUITextInput
        // and TUIPickers, the map's edges: a search field is a `TextField`, which offers its suggestions in the
        // text fields' menu, and the scope bar is a segmented `Picker` (TUITextInput's until step C8 peeled the
        // pickers out of it, so the search depended on TUITextInput alone from step C5 until then). Neither
        // depends on it, nor does anything in TUIFoundation (Tools/ModuleMap's upward check), so the umbrella
        // re-exports it, and nothing else does. It re-exports TUIFoundation, TUIPickers and TUITextInput
        // (Sources/TUISearch/Exports.swift), so an app that imports it has `TextField` and `Picker` too (plan §4).
        .target(
            name: "TUISearch",
            dependencies: ["TUIFoundation", "TUIPickers", "TUITextInput"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step C6's peel, out of the TextInput group above: `Form`, `LabeledContent`, `GroupBox`, `Card` and `Panel`,
        // their styles, and the walk that lays a form's content out in rows (Sources/TUIForms). Built on
        // TUIFoundation alone, the map's edge: a form names nothing of the text inputs', pickers', search's or
        // numeric controls', which compiled beside it from step B7 until this step (a `Picker` or a `TextField` in a
        // form is a row the form lays out like any other view). TUITextInput does not depend on it, nor does
        // anything in TUIFoundation (Tools/ModuleMap's upward check), so the umbrella re-exports it, and nothing
        // else does. It re-exports TUIFoundation (Sources/TUIForms/Exports.swift).
        .target(
            name: "TUIForms",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5b's three leaves, each built on TUIFoundation alone, each a module of the plan's map of its own
        // (no group), at its default path, Sources/<name>. TUIChrome is what the run loop draws around the
        // content: the `StatusBar` view, the toolbars, the notifications, the tooltip popover and `.help`,
        // `.statusBarItems`, the window chrome host, the overlay compositor, the screen selection's highlight
        // and Copy menu; the status bar's STATE, the tooltip's and the window chrome's, which focus and the
        // controls write, stay in TUIFoundation. TUIApp and TUIPresentation (TUINavigation, from B5b until
        // step C1 peeled the presentations out of it) depend on it and re-export it. TUIEffects is the transitions,
        // content transitions, `.symbolEffect`, `.visualEffect`, `.scrollTransition` and the colour effects;
        // `TimelineView` and the symbol glyph's effect, which `Label` and `ProgressView` draw, stay. TUIMenus is
        // `Menu`, `ControlGroup`, `.contextMenu`, `.menuStyle` and the menu styles, and the popup menu's core; the menu
        // engine, `ContextMenuState`, the menu-row sink and `MenuStyle` stay, so no leaf depends on it, and so do the
        // inline menu's core and the column it lays out, whose `bordered` and `foregroundStyle` results name types only
        // TUIFoundation can see (CONTRIBUTING.md, "Crossing a module boundary"). Nothing in TUIFoundation may use
        // any of the three (Tools/ModuleMap's upward check), so the umbrella re-exports each. Each re-exports
        // TUIFoundation (its Exports.swift).
        .target(
            name: "TUIChrome",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUIEffects",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUIMenus",
            dependencies: ["TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5c's leaf, built on TUIFoundation as B5b's three are, a module of the plan's map of its own at its
        // default path: `Image`'s bitmap path. `Image(_:)` from a file or URL and `Image(_:bundle:)`, `AsyncImage`,
        // `_ImageCore` with its render cache, templates, resizing and orientation, `.terminalGraphics(_:)` and the
        // `.image*` rendering options, asset catalogues and `Color(_:bundle:)`, the `image:` initialisers of `Label`
        // and `ContentUnavailableView`. `Image` itself, `Image(systemName:)` and the raster seam the bitmap path
        // draws through (`_ImageRaster`, step A2's R2), `.aspectRatio`, `.scaledToFit`, `.scaledToFill` and
        // `.imageCellAspect` (A4's S1) stay. Nothing in TUIFoundation may use this module (Tools/ModuleMap's
        // upward check), so the umbrella re-exports it; of the other leaves only TUITabImages (`Tab`'s `image:`
        // initialisers, since 2026-10-24) depends on it, and beside the umbrella and the tests only TUIAppKit,
        // which is no module of the map, does. It re-exports TUIFoundation and TUIImage
        // (Sources/TUIBitmaps/Exports.swift).
        //
        // TUIImage (the decoders, `ASCIIConverter`, `RGBAImage`) is a dependency of this module and of
        // TUICurveEditors (TUIColorPicker's until C9b), the only two leaves that name it. Of the framework's other modules only the umbrella,
        // which re-exports it, and TUIAppKit, whose `CGImage` and `NSImage` bridges make an `RGBAImage`, name
        // it; the tests and tools aside, nothing else does. TUIFoundation does not depend on it since this step,
        // so an app that depends on none of the TUI, TUIBitmaps, TUICurveEditors, TUIAppKit and
        // TUIImage products links neither TUIImage nor CSTBImage.
        .target(
            name: "TUIBitmaps",
            dependencies: ["TUIFoundation", "TUIImage"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Lane O10's leaf, built on TUIFoundation: the file panels (refusal review O10, ruled 2026-10-12: open and
        // save dialogs drawn by TUI, adapted to the terminal). `fileImporter`, `fileExporter`, `fileMover` and
        // the `fileDialog` customizations present a panel TUI draws in a sheet, listing a folder in a `Table`
        // with a path bar and, to save, a name field; so it is built on TUIPresentation (the sheet and the
        // replace alert), TUITables (the folder's rows, which bring TUILists), TUITextInput (the name
        // and path fields) and TUIPickers (the path control, a segmented picker; lane FP2). A module of its own
        // so that an app with no file panel compiles and links none of it. Nothing in TUIFoundation may use
        // it (Tools/ModuleMap's upward check), so the umbrella re-exports it. It re-exports the five
        // (Sources/TUIFilePanels/Exports.swift).
        .target(
            name: "TUIFilePanels",
            dependencies: ["TUIFoundation", "TUIPickers", "TUIPresentation", "TUITables", "TUITextInput"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // The owner's TAB-IMAGE-NAME option 2 (2026-10-24, decisions C11): `Tab`'s `image:` initialisers, which
        // find their image as `Image(_:bundle:)` does, as `Label(_:image:)`'s do, in a module of their own built on
        // TUIBitmaps and TUITabs. In TUIBitmaps they made it depend on TUITabs (and so TUILists and
        // TUIPresentation), which made an app on TUIApp and TUIBitmaps with no tab view 10.9% larger; in
        // TUITabs they would put the image decoders under TUIColorPicker, whose panel is a `TabView`, which
        // its `lower` list in Tools/ModuleMap/rules.json forbids. Here an app pays for them only when it uses both.
        // Nothing but the umbrella and the tests depends on it. It re-exports both
        // (Sources/TUITabImages/Exports.swift).
        .target(
            name: "TUITabImages",
            dependencies: ["TUIBitmaps", "TUIFoundation", "TUITabs"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        // The owner's PREVIEW-IMAGES option "glue" (2026-10-28): `fileDialogPicturePreviews()`, the file panels'
        // column view previewing a selected picture, in a module of its own on TUIBitmaps and TUIFilePanels, as
        // TUITabImages is for tabs: in TUIFilePanels every app with a file panel would carry the image decoders,
        // and in TUIBitmaps every app showing a picture the file panels (and through them the lists, tables,
        // pickers and presentations). Here an app pays for them only when it uses both. Nothing but the umbrella
        // and the file panels' tests depends on it. It re-exports both (Sources/TUIFilePanelImages/Exports.swift).
        .target(
            name: "TUIFilePanelImages",
            dependencies: ["TUIBitmaps", "TUIFilePanels", "TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        // The umbrella: Sources/TUI/Exports.swift `@_exported import`s the leaves carved so far (TUIApp,
        // TUIBitmaps, TUIChrome, TUIColorPicker, TUICommands, TUICurveEditors, TUIEffects,
        // TUIFilePanels, TUIForms, TUIGrid, TUILists, TUIMenus, TUINavigation, TUINumericControls,
        // TUIPickers, TUIPresentation, TUIScenes, TUISearch, TUITabImages, TUITables, TUITabs,
        // TUITextInput, TUIFilePanelImages),
        // TUIFoundation and the lower four, and holds no code (Tools/ModuleMap's `umbrella` check), so
        // `import TUI` gives an app exactly what it gave when the framework was one TUI module. It names
        // TUIImage itself since step B5c: TUIFoundation no longer re-exports it. Its directory also holds the
        // TUI.docc catalog. Nothing in the package depends on it but the apps and the tests.
        .target(
            name: "TUI",
            dependencies: [
                "TUIApp", "TUIBitmaps", "TUIChrome", "TUIColorPicker", "TUICommands", "TUICurveEditors",
                "TUIEffects", "TUIFilePanelImages", "TUIFilePanels", "TUIForms", "TUIGrid", "TUILists", "TUIMenus",
                "TUINavigation", "TUINumericControls", "TUIPickers", "TUIPresentation", "TUIScenes",
                "TUISearch", "TUITabImages", "TUITables", "TUITabs", "TUITextInput", "TUIFoundation",
                "TUICore", "TUIStyling", "TUIImage", "TUIView",
            ]
        ),

        // The substrate. The module split (Documentation/Historical/Module split plan, revision 4) put each
        // planned module's files in Sources/<module>, and from step B1 this one target compiled them all, as the
        // module TUIFoundation, until a step of Phase B carved each into a target of its own: TUIApp (step
        // B3), TUIChrome, TUIEffects and TUIMenus (step B5b) and TUIBitmaps (step B5c) at their
        // default paths, and the coarse groups TUINavigation (step B5), TUILists (step B6) and
        // TUITextInput (step B7) over their modules' directories, whose members phase C peeled into targets of
        // their own at their default paths (steps C1 to C8). B7 took the last of them out, so this is an
        // ordinary target at its default path, Sources/TUIFoundation.
        // Tools/ModuleMap checks the map: a file's directory is its module. It depends on neither TUIImage nor
        // CSTBImage since step B5c took the bitmap path out (the plan's B5c row): its `lower` list in rules.json
        // names TUICore, TUIStyling and TUIView, and the `lower` check fails CI on a use of any other.
        .target(
            name: "TUIFoundation",
            dependencies: [
                "TUICore", "TUIStyling", "TUIView", "TUIStrings", "TUITerminalHost",
            ],
            // A member is visible in a file only if that file imports the
            // module declaring it. Without this, every extension member of
            // every module LOADED is in scope — and on macOS that included
            // SwiftUICore, which AppKit imports (not re-exports), while TUI
            // imported AppKit: its `AttributeScopes.SwiftUIAttributes` made
            // TUI's own scope of that name ambiguous wherever TUI spelled
            // it. Nothing TUI is built from imports AppKit now (decisions
            // B50: the bridges are `TUIAppKit`), and this stays as the
            // guard that keeps a stray import from bringing that back.
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // The bridges to AppKit and Core Graphics: the one module that
        // imports AppKit. Empty off Apple platforms. It depends on the modules
        // whose types it extends (which re-export the lower ones), not on the
        // umbrella, which only the apps and the tests depend on: since step
        // B5c TUIBitmaps too, whose bitmap path an image made from a
        // `CGImage` or an `NSImage`, or a compiled asset catalogue's, draws
        // through.
        .target(
            name: "TUIAppKit",
            dependencies: ["TUIBitmaps", "TUIFoundation", "TUIImage"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // `fileDialogSystemIcons()`: the file panels' items drawn with NSWorkspace's icons (decisions A-FP2-1, the
        // owner's option 2, 2026-10-24). A module of its own, on TUIAppKit and TUIFilePanels, because in
        // TUIAppKit it made that depend on the file panels (and through them the lists, tables, pickers and
        // presentation modules): an app on TUIApp and TUIAppKit using only `Color(nsColor:)` grew 29.3%. Opt-in
        // like TUIAppKit, which it is imported beside; nothing but the tests depends on it, and the umbrella does
        // not re-export it. Empty off Apple platforms.
        .target(
            name: "TUIFilePanelsAppKit",
            dependencies: ["TUIAppKit", "TUIBitmaps", "TUIFilePanels", "TUIFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // The `@Animatable` and `@Entry` macros: the declarations, and the compiler plugin
        // that expands them. Nothing else in the package depends on either.
        .target(name: "TUIMacros", dependencies: ["TUIMacrosPlugin", "TUICore"]),
        .macro(
            name: "TUIMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // ── App & Tests ─────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "Example",
            dependencies: ["TUI"],
            resources: [.copy("Resources")]
        ),
        // The framework's suite, a test target per module (the owner's request B-TC1-1, 2026-10-12; placed
        // by Tools/TestSplit from the compiler's index of what each file references). A test lives in the
        // target of the highest module it needs, its helpers' needs counted, and its target depends on
        // what its files import, so an edit to a module rebuilds only the tests that can see it:
        // - TUIFoundationTests: tests needing only TUIFoundation and what it re-exports;
        // - TUIAppTests: those needing TUIApp and no feature module;
        // - TUI<Module>Tests: those needing one feature module, with or without TUIApp;
        // - TUIIntegrationTests, the one target that depends on everything: those needing two.
        // A test target is one module, whose interface is emitted by one serial job whatever the -j, and
        // every edit to any of its files waits for that job: more, smaller targets also re-emit less
        // and compile in parallel (the commit that split them records the times). Test files that share
        // a helper declared in one of them land together. Tools/validate-test-boundaries.sh checks that
        // every test file imports only what its target depends on.
        //
        // Helpers two targets share live in support targets split the same way: TUITestSupport for the
        // base, TUIAppTestSupport, and a feature's own (TUIListsTestSupport, ...). Each is a plain
        // target, as CTestSupport is, which `swift build` builds even without `--build-tests`: in a release
        // build, which has no testability, its `@testable import`s of the library would fail ("module
        // 'TUIFoundation' was not compiled for testing"). So every file is wrapped in
        // `#if TUI_TEST_SUPPORT && canImport(Testing)`, which these targets define for debug builds
        // only, and a release build compiles them empty. The alternatives, measured 2026-10-10 in a probe
        // package (lane TT2) on Swift 6.2.4, 6.3.3 and 6.4.0: as a test target the others depend on,
        // 6.4's build system still builds it in release; `swift build -c release --product <a library
        // product>` builds every target on 6.2 and 6.3; and `package` access instead of `@testable` would
        // put every internal a helper uses into the library's package interface. A release TEST build
        // passes the define itself:
        // `swift build -c release --build-tests -Xswiftc -enable-testing -Xswiftc -DTUIKIT_TEST_SUPPORT`.
        // `canImport(Testing)`: a static Linux SDK ships no Testing module, and a debug build of the whole
        // package for it would fail here. Golden snapshots are read and written by path (#filePath-relative,
        // see TestHelpers/SnapshotTesting.swift), not via the resource bundle, so they are excluded from
        // the build rather than declared as resources; so are the asset-catalogue fixtures.
        .target(
            name: "TUITestSupport",
            dependencies: [
                "TUICore", "TUIFoundation", "TUIStrings", "TUIStyling", "TUIView",
            ],
            path: "Tests/TUITestSupport", exclude: ["__Snapshots__"],
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .target(
            name: "TUIAppTestSupport",
            dependencies: [
                "TUIApp", "TUIChrome", "TUICore", "TUIFoundation", "TUIStyling", "TUITestSupport",
                "TUIView",
            ],
            path: "Tests/TUIAppTestSupport",
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .target(
            name: "TUIBitmapsTestSupport",
            dependencies: [
                "TUIBitmaps", "TUIFoundation", "TUITestSupport",
            ],
            path: "Tests/TUIBitmapsTestSupport",
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .target(
            name: "TUIListsTestSupport",
            dependencies: [
                "TUIApp", "TUICore", "TUIFoundation", "TUILists", "TUITestSupport",
            ],
            path: "Tests/TUIListsTestSupport",
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .target(
            name: "TUITablesTestSupport",
            dependencies: [
                "TUIApp", "TUICore", "TUIFoundation", "TUILists", "TUITables", "TUITestSupport",
                "TUIView",
            ],
            path: "Tests/TUITablesTestSupport",
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .target(
            name: "TUITabsTestSupport",
            dependencies: [
                "TUIFoundation", "TUITabs", "TUITestSupport",
            ],
            path: "Tests/TUITabsTestSupport",
            swiftSettings: [.define("TUI_TEST_SUPPORT", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "TUIAppKitTests",
            dependencies: [
                "TUIApp", "TUIAppKit", "TUIAppTestSupport", "TUIBitmaps", "TUIBitmapsTestSupport",
                "TUICore", "TUIFoundation", "TUIImage", "TUITestSupport",
            ],
            exclude: ["__Fixtures__"]
        ),
        .testTarget(
            name: "TUIAppTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUIChrome", "TUICore", "TUIFoundation", "TUIImage",
                "TUIStrings", "TUIStyling", "TUITerminalHost", "TUITestSupport", "TUIView",
                "TUIWidthCorpus",
            ]
        ),
        .testTarget(
            name: "TUIBitmapsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUIBitmaps", "TUIBitmapsTestSupport", "TUICore",
                "TUIFoundation", "TUIImage", "TUIStyling", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIChromeTests",
            dependencies: [
                "TUIChrome", "TUICore", "TUIFoundation", "TUIStrings", "TUIStyling",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIColorPickerTests",
            dependencies: [
                "TUIApp", "TUIColorPicker", "TUICore", "TUIFoundation", "TUILists",
                "TUINumericControls", "TUIStrings", "TUIStyling", "TUITabsTestSupport",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUICommandsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICommands", "TUICore", "TUIFoundation",
                "TUINavigation", "TUIPresentation", "TUITestSupport", "TUITextInput", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIScenesTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICommands", "TUICore", "TUIFoundation",
                "TUIPresentation", "TUIScenes", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUICurveEditorsTests",
            dependencies: [
                "TUIApp", "TUICurveEditors", "TUIFoundation", "TUIImage", "TUITestSupport",
            ]
        ),
        .testTarget(
            name: "TUIEffectsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIEffects", "TUIFoundation",
                "TUIStyling", "TUITerminalHost", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIFilePanelsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUIChrome", "TUICore", "TUIFilePanelImages", "TUIFilePanels",
                "TUIFoundation", "TUILists", "TUIPresentation", "TUIStrings", "TUITables", "TUITestSupport",
                "TUITextInput", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIFormsTests",
            dependencies: [
                "TUIForms", "TUIFoundation", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIFoundationTests",
            dependencies: [
                "CTestSupport", "TUICore", "TUIFoundation", "TUIImage", "TUIStrings", "TUIStyling",
                "TUITerminalHost", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIGridTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUIGrid",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIIntegrationTests",
            dependencies: umbrellaTestDependencies + [
                "TUIAppTestSupport", "TUIListsTestSupport", "TUITabsTestSupport", "TUITestSupport",
            ]
        ),
        .testTarget(
            name: "TUIListsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUILists",
                "TUIListsTestSupport", "TUIStyling", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIMenusTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUIMenus", "TUIStyling",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUINavigationTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUINavigation",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUINumericControlsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUINumericControls",
                "TUIStyling", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIPickersTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUIPickers",
                "TUIStyling", "TUITerminalHost", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIPresentationTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUIChrome", "TUICore", "TUIFoundation",
                "TUIPresentation", "TUIStrings", "TUIStyling", "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUISearchTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUISearch", "TUIStrings",
                "TUIStyling", "TUITestSupport", "TUITextInput", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUITablesTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUILists",
                "TUIListsTestSupport", "TUIStyling", "TUITables", "TUITablesTestSupport",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUIFilePanelsAppKitTests",
            dependencies: [
                "TUIAppTestSupport", "TUICore", "TUIFilePanels", "TUIFilePanelsAppKit", "TUIFoundation",
                "TUITestSupport",
            ]
        ),
        .testTarget(
            name: "TUITabImagesTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUIBitmaps", "TUIFoundation", "TUITabImages", "TUITabs",
                "TUITestSupport",
            ]
        ),
        .testTarget(
            name: "TUITabsTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUIStyling", "TUITabs",
                "TUITestSupport", "TUIView",
            ]
        ),
        .testTarget(
            name: "TUITextInputTests",
            dependencies: [
                "TUIApp", "TUIAppTestSupport", "TUICore", "TUIFoundation", "TUIStyling",
                "TUITerminalHost", "TUITestSupport", "TUITextInput", "TUIView",
            ]
        ),
        // C declarations a test needs that only the C importer makes — a struct
        // with bitfields, which the runtime's field list leaves out. Tests
        // only; no product names it.
        .target(name: "CTestSupport", path: "Tests/CTestSupport"),

        // The Example app's own views, where a test must hold the view the
        // app ships rather than a copy of its shape — a copy goes on passing
        // after the app's view is changed back. `@testable import Example`: an
        // executable target can be imported by a test target on macOS and
        // Linux, its `main.swift` left unrun.
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example", "TUI", "TUIApp", "TUIFoundation"]
        ),

        // ── Per-module unit-test targets (compiler-enforced layering) ──────────────────────────────────────
        // Each links ONLY its module. A unit test that drifts into a sibling or
        // higher layer stops compiling here — that is the point: it keeps every
        // module provably testable in isolation.
        .testTarget(name: "TUICoreTests", dependencies: ["TUICore", "TUIWidthCorpus"]),
        .testTarget(name: "TUIStylingTests", dependencies: ["TUIStyling"]),
        .testTarget(name: "TUIViewTests", dependencies: ["TUIView"]),
        .testTarget(name: "TUIImageTests", dependencies: ["TUIImage"]),

        // The macros, used as an app uses them: expanded in test sources. Not
        // also on the plugin target, to check expansions as source: a test
        // target that depends on a macro target has SwiftPM build the whole
        // test product for the host, and `ExampleTests` then cannot import the
        // `Example` executable (measured, SwiftPM 6.2.4).
        .testTarget(name: "TUIMacrosTests", dependencies: ["TUIMacros", "TUI"]),

        // ── Stress test ─────────────────────────────────────────────────────────────────────────────────
        // A performance stress harness shaped like an app: deep/wide view
        // hierarchies over large, pseudo-randomly synthesised data sets. Runs
        // interactively, or headless (`--bench`/`--selfcheck`) as a no-PTY
        // profiling instrument (see Sources/Stress/README.md).
        .executableTarget(
            name: "TerminalClientQuirks",
            dependencies: ["TUI", "TUIWidthCorpus"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),
        .executableTarget(
            name: "Stress",
            dependencies: ["TUI"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "EmojiBugScanner",
            dependencies: ["TUICore"],
            path: "Tools/EmojiBugScanner"
        ),
        .executableTarget(
            name: "EmojiBenchmark",
            dependencies: ["TUICore"],
            path: "Tools/EmojiBenchmark"
        ),
        // Mode A profiling harness (see Tools/Profiling/README.md): a
        // no-PTY, no-attach executable that loops `renderToBuffer` over a
        // representative tree so it can be profiled with `xctrace --launch`
        // in environments where `--attach` is denied.
        .executableTarget(
            name: "RenderHarness",
            dependencies: ["TUI"],
            path: "Tools/Profiling/RenderHarness"
        ),

        // The same, for the IMAGE pipeline: an `ASCIIConverter` looped over a
        // picture. Separate from `RenderHarness` because the two halves of the
        // image path — per cell (`convert`) and per pixel (`recoloured`) —
        // have to be measured separately, and neither is a view render.
        .executableTarget(
            name: "ImageHarness",
            dependencies: ["TUIImage", "TUIStyling"],
            path: "Tools/Profiling/ImageHarness"
        ),

        // The smallest app that can be asked "does this view cost anything when
        // nothing is happening?" — one view, nothing focusable, no timers. Every
        // Example page carrying an Image also carries focusable controls, whose
        // focus pulse keeps the loop legitimately awake and makes the reading
        // meaningless. Driven by `Tools/Profiling/idle-image.sh`.
        .executableTarget(
            name: "IdleProbe",
            dependencies: ["TUI"],
            path: "Tools/Profiling/IdleProbe"
        ),
    ]
)

// ── App size: the traits `DeadStripUnusedAPI` and `UnexportTUISymbols` (both default on) ──────────────
// `DeadStripUnusedAPI`. Swift marks every public symbol "no dead strip", so that code outside the link could
// call it. An app linking TUI statically, as every SwiftPM app does, therefore keeps ALL of TUI's public
// API, called or not. `-internalize-at-link` drops that mark from TUI's own symbols, and the app's linker keeps
// what the app reaches (`swift build -c release` passes `-dead_strip`; an Xcode app needs
// `DEAD_CODE_STRIPPING = YES`, which Xcode's default is not). Measured 2026-10-11, stripped: a hello-world
// app -14.7% and Stress -12.1% on Swift 6.4.0, -14.9% and -12.3% on Xcode's 6.2.4.
//
// What it breaks: a statically linked app whose dlopened plugin calls TUI API that the app itself never
// calls. That symbol is no longer in the app, and the plugin fails to load (measured with a small
// library). A dylib that links TUI in, TUI's own or one of the app's, is unaffected: ld keeps every
// symbol a dylib exports as a dead-strip root (measured on a dylib product of TUI's modules, the same link
// SwiftPM makes for an app's dylib), unless that dylib's own link narrows its exports, as the next trait does.
//
// `UnexportTUISymbols`. A program exports every external symbol it defines, TUI's that the linker kept among
// them, in a table (the export trie) whose bytes `strip` leaves in place. One `-unexported_symbol` pattern per TUI
// module, `_$s` + the module name's length + the name + `*`, the start of every symbol Swift mangles for a
// declaration of that module, takes them out of it. Measured 2026-10-12, stripped, against `DeadStripUnusedAPI`
// alone: a hello-world app -3.2% and Stress -2.9%, on Swift 6.4.0 and on Xcode's 6.2.4 (the hello world's export
// table 317 KB -> 9 KB; what is left is the app's own and TUI's extensions of other modules' types, such as
// `$sSS7TUICoreE…`, whose symbols start with the extended type's module). It is a link flag, so it lands on
// every final link that contains a TUI module, a `.dynamic` library product of the developer's as well, with the
// patterns of the modules in that link. What it breaks (measured with a small library built the same way, on both
// toolchains):
// - A plugin dlopened into a statically linked app that calls ANY TUI API through the app: `dlopen` fails with
//   "symbol not found in flat namespace". With `DeadStripUnusedAPI` alone, only one calling API the app never calls.
// - A `.dynamic` library containing TUI exports none of TUI's symbols (its own still go out, but for the next
//   point's), and keeps only the TUI code its own code reaches. A client that uses TUI through it fails to
//   link ("Undefined symbols: type metadata accessor for …"), or, linked against an older build of the library, to
//   launch ("Symbol not found"). A client of the library's own API alone is unaffected, unless it calls one of:
// - The developer's own extensions of TUI's types and protocols (`extension Color { static var brand }`,
//   `extension View { func card() }`) and conformances of TUI's types to the developer's protocols. Swift begins
//   their symbols with the extended type's module, so the patterns take them out of the app's or the library's
//   exports with TUI's (measured: a `.dynamic` library's three such declarations, 5 symbols exported -> 0). A
//   client that calls one fails to link ("Undefined symbols", naming the member), unless Swift's cross-module
//   optimization copied its body into the client, as it did for one built on public API alone; and a plugin that
//   calls one in the app fails to load ("symbol not found in flat namespace").
// - ld refuses `-unexported_symbol` beside an export list: a link that also passes `-no_exported_symbols`,
//   `-exported_symbol` or `-exported_symbols_list` (as Xcode's `LD_EXPORT_SYMBOLS = NO` and `EXPORTED_SYMBOLS_FILE`
//   do) stops with "-unexported_symbol cannot be used with -exported_symbol*". `-unexported_symbol '*'`, which takes
//   the rest of the program's exports out as well, combines with it.
// That last is why it is a trait of its own rather than part of `DeadStripUnusedAPI`: a developer whose link needs an
// export list turns off this one and keeps the dead stripping.
//
// The opt-out is the app's: `.package(url: …, from: …, traits: [])` turns off EVERY default trait of TUI's
// (today these two), and `traits: ["DeadStripUnusedAPI"]` keeps that one alone. No compiler flag undoes
// `-internalize-at-link` and no link flag undoes `-unexported_symbol`, so the traits are the only way out.
// `DeadStripUnusedAPI` is named for what it lets the app's linker do, not for its compiler flag.
//
// On every module a library product ships (the same closure Tools/check-span-compatibility.sh reads),
// in macOS release builds only: debug builds, and so `swift test` and DocC's symbol graphs, compile and link as
// before. Not on Linux or Windows: unmeasured there. SwiftPM 6.2 and later accept `unsafeFlags` from a
// dependency resolved by version (swift-package-manager #8896, in 6.2 as #8914), and this package needs
// 6.2; Tools/validate-package-manifest.sh keeps them behind a trait, and link flags to these patterns, which
// match only what Swift names under a TUI module: TUI's own symbols, and those of the developer's extensions
// of TUI's types above.
package.traits.formUnion([
    .default(enabledTraits: ["DeadStripUnusedAPI", "UnexportTUISymbols"]),
    .trait(
        name: "DeadStripUnusedAPI",
        description: "Lets an app's static link drop the TUI API it never calls (macOS release builds)."
    ),
    .trait(
        name: "UnexportTUISymbols",
        description: "Keeps TUI's symbols, and those of extensions of TUI's types, out of the export table of "
            + "every program and library linking it (macOS release builds)."
    ),
])
let libraryModules: Set<String> = {
    let targets = Dictionary(uniqueKeysWithValues: package.targets.map { ($0.name, $0) })
    var pending = package.products.compactMap { $0 as? Product.Library }.flatMap(\.targets)
    var found = Set<String>()
    while let name = pending.popLast() {
        guard let target = targets[name], found.insert(name).inserted else { continue }
        for dependency in target.dependencies {
            if case .targetItem(let name, _) = dependency { pending.append(name) }
            if case .byNameItem(let name, _) = dependency { pending.append(name) }
        }
    }
    return found
}()
for target in package.targets where target.type == .regular && libraryModules.contains(target.name) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .unsafeFlags(
            ["-Xfrontend", "-internalize-at-link"],
            .when(platforms: [.macOS], configuration: .release, traits: ["DeadStripUnusedAPI"])
        )
    ]
    // The Swift modules only: CSTBImage is C, whose symbols carry no module prefix.
    guard target.name.hasPrefix("TUI") else { continue }
    // `_$s`, the name's length, the name: how Swift begins the symbol of every declaration in module `name`.
    // A link flag, so on each final link that contains this module, and only those.
    target.linkerSettings = (target.linkerSettings ?? []) + [
        .unsafeFlags(
            ["-Xlinker", "-unexported_symbol", "-Xlinker", "_$s\(target.name.utf8.count)\(target.name)*"],
            .when(platforms: [.macOS], configuration: .release, traits: ["UnexportTUISymbols"])
        )
    ]
}

// ── Benchmarks (opt-in) ───────────────────────────────────────────────────────────────────────────
// ordo-one/package-benchmark and the `TUIBenchmarks` target are gated behind
// an environment flag so the default `swift build` / `swift test` graph never
// pulls in the benchmark dependency. That keeps test output free of the plugin's
// upstream PackagePlugin deprecation warnings and removes the jemalloc build
// requirement for ordinary development. Enable benchmarking by exporting
// TUI_BENCHMARKS, e.g.
//   TUI_BENCHMARKS=1 swift package benchmark
//   TUI_BENCHMARKS=1 swift package benchmark run TUIBenchmarks <name>
if Context.environment["TUI_BENCHMARKS"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.29.4", traits: [])
    )
    package.targets.append(
        .executableTarget(
            name: "TUIBenchmarks",
            dependencies: [
                "TUI",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/TUIBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    )
}
