// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

// ── Sources' directories ────────────────────────────────────────────────────────────────────────────────
// Every directory under Sources, once. A target that compiles more than one of them (TUIkitFoundation, and each
// coarse group of the module split) takes `path: "Sources"`, so it sees every file under Sources, and SwiftPM
// reports each one it neither compiles nor excludes as unhandled ("found N file(s) which are unhandled", a warning,
// which CI does not fail on). Such a target is declared with `directories:` (below), which excludes every directory
// of this list it does not name. So a new directory under Sources goes in this list, beside the target that compiles
// it (one of its own, or a `directories:` list), and no other target's list changes. A directory left out of this
// list is reported as unhandled by each such target. One in it that no target compiles is excluded by every one of
// them, and SwiftPM says nothing: for a module directory of the split's map (Tools/ModuleMap/rules.json),
// ModuleMap's `uncompiled` check, which gates CI, then fails on its files; for any other directory, nothing does.
let sourcesDirectories = [
    "CSTBImage", "Example", "Stress", "TerminalClientQuirks", "TUIkit", "TUIkitApp", "TUIkitAppKit", "TUIkitBitmaps",
    "TUIkitChrome", "TUIkitColorPicker", "TUIkitCore", "TUIkitEffects", "TUIkitForms", "TUIkitFoundation", "TUIkitGrid",
    "TUIkitImage", "TUIkitLists", "TUIkitMacros", "TUIkitMacrosPlugin", "TUIkitMenus", "TUIkitNavigation",
    "TUIkitNumericControls", "TUIkitPickers", "TUIkitPresentation", "TUIkitSearch", "TUIkitStrings", "TUIkitStyling",
    "TUIkitTables", "TUIkitTabs", "TUIkitTerminalHost", "TUIkitTextInput", "TUIkitView", "TUIkitWidthCorpus",
]

extension Target {
    /// A target that compiles the directories under Sources that `directories` names: `path: "Sources"`, those
    /// directories as its `sources:`, and every other one of `sourcesDirectories` as its `exclude:`.
    static func target(
        name: String,
        dependencies: [Dependency],
        directories: [String],
        swiftSettings: [SwiftSetting]
    ) -> Target {
        .target(
            name: name,
            dependencies: dependencies,
            path: "Sources",
            exclude: sourcesDirectories.filter { !directories.contains($0) },
            sources: directories,
            swiftSettings: swiftSettings
        )
    }
}

let package = Package(
    name: "TUIkit",
    // Minimum deployment targets for Apple platforms
    // Linux is automatically supported (no platform specification needed)
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // ── Low-level (no deps) ─────────────────────────────────────────────────────────────────────────
        .library(name: "TUIkitCore", targets: ["TUIkitCore"]),
        .library(name: "TUIkitStyling", targets: ["TUIkitStyling"]),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        .library(name: "TUIkitView", targets: ["TUIkitView"]),
        .library(name: "TUIkitImage", targets: ["TUIkitImage"]),

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        .library(name: "TUIkit", targets: ["TUIkit"]),

        // ── Bridges to Apple's graphics types (NSColor, CGColor, CGImage, NSImage) ────────────────────────
        // A module of its own so that nothing TUIkit is built from imports
        // AppKit — see Sources/TUIkitAppKit/Exports.swift.
        .library(name: "TUIkitAppKit", targets: ["TUIkitAppKit"]),

        // ── SwiftUI's `@Animatable` macros, opt-in (decisions A52) ──────────────────────────────────────
        // A product of their own, so that only an app that depends on it builds
        // the compiler plugin and swift-syntax: SwiftPM builds by target, and a
        // client of `TUIkit` alone compiles none of swift-syntax. It does still
        // RESOLVE and fetch it (measured: resolution is by package, so the
        // repository is cloned into such a client's checkouts), which is why
        // the version range below is kept wide.
        .library(name: "TUIkitMacros", targets: ["TUIkitMacros"]),

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
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.1"),
        // For the `TUIkitMacros` product's compiler plugin only. From the
        // release line of the oldest toolchain the package supports (602 is
        // Swift 6.2's) up to the next major, as macro packages commonly take
        // it: every client of TUIkit resolves this range, macros or not, so a
        // narrower one would refuse any app that also depends on a package
        // wanting a newer swift-syntax (a 602..<603 cap did, measured with
        // one requiring `from: "603.0.0"`). SwiftPM resolves the newest in
        // range; it takes swift-syntax PREBUILT only for 602.0.0 on a Swift
        // 6.2 toolchain (Linux and Windows; measured: no prebuilts published
        // for 603 or 604), so an app on 6.2 that wants them pins
        // `exact: "602.0.0"` itself. See decisions B-D6M-2.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"700.0.0"),
        // ordo-one/benchmark is added conditionally at the bottom of this file
        // (gated on TUIKIT_BENCHMARKS), so the default build/test graph stays
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
        .target(name: "TUIkitCore"),
        .target(name: "TUIkitStyling"),

        // The width corpus (`TerminalWidthCorpus`): the grapheme clusters the
        // tests and the TerminalClientQuirks app iterate, and nothing a library
        // module reads. A target of its own so that no library build compiles
        // it: inside TUIkitCore, whose job starts the chain every release build
        // waits on, its two tables took 0.39 s of SIL optimisation (2026-10-07).
        .target(name: "TUIkitWidthCorpus"),

        // ── Mid-level ───────────────────────────────────────────────────────────────────────────────────
        // TUIkitStyling came in for `Color: View`, which has to be declared in
        // the module that owns `View`: declared anywhere else, a `Color` in a
        // `@ViewBuilder` pack beside a generic view segfaults the debug
        // runtime while instantiating the pack's metadata. See §14 of
        // `Documentation/Gradients where a colour is accepted.md` — it is a
        // toolchain bug, reproduced on Swift 6.2.4 and still present on the
        // 6.5-dev snapshot of 2026-08-30. PaletteEnvironment.swift and
        // ColorAnimation.swift moved down with it.
        //
        // It is no longer the only use. OpacityClaim.swift derives a
        // translucent paint's opacity claim from the `Color`s it painted with,
        // and RenderCache.swift records the surface `Color` a memoized buffer
        // was blended over. So a toolchain fix would let `Color: View` move
        // back up, but as the code stands the dependency would stay.
        .target(name: "TUIkitView", dependencies: ["TUIkitCore", "TUIkitStyling"]),
        .target(name: "TUIkitImage", dependencies: ["CSTBImage", "TUIkitStyling"]),

        // ── The split's carved modules ──────────────────────────────────────────────────────────────────
        // Modules of the planned split (Documentation/Historical/Module split plan, revision 4) that a step
        // of Phase B has carved out of TUIkitFoundation into targets of their own. A side module, below it,
        // is one that TUIkitFoundation depends on and re-exports (Sources/TUIkitFoundation/Exports.swift); a
        // leaf, above it, depends on TUIkitFoundation, and the umbrella re-exports it. Either way `import
        // TUIkit` gives an app what it gave before. Tools/ModuleMap's `lower` lists (rules.json) say which
        // lower modules each may use; its `lower` check fails CI on any other.
        //
        // Step B2's two side modules need TUIkitCore alone, so they compile beside TUIkitView, not after
        // it. TUIkitStrings is the SF Symbols name table, the inline-Markdown parser, the format styles and
        // localization, and it holds the framework's resources: the translation tables and VERSION, read
        // through its `moduleResourceURL`, in the bundle `TUIkit_TUIkitStrings`
        // (Tools/verify-versioned-consumer.sh runs a consumer that reads both). TUIkitTerminalHost is the
        // terminal's facts as values: the host, its identity, quirks and capabilities.
        // MemberImportVisibility as on TUIkitFoundation, which compiled their files until B2.
        .target(
            name: "TUIkitStrings",
            dependencies: ["TUIkitCore"],
            resources: [.copy("Localization/translations"), .copy("VERSION")],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUIkitTerminalHost",
            dependencies: ["TUIkitCore"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B3's leaf, the first module built ON TUIkitFoundation rather than under it: `App` and its run
        // loop, `Scene`, `WindowGroup` and the Scene modifiers, the console layer (the `Terminal` class with
        // its raw mode, input and replies, the signal handlers, the stdin source) and the run loop's rendering
        // (`ViewRenderer`, `FrameDiffWriter`, `renderOnce`). Nothing in TUIkitFoundation may use it
        // (Tools/ModuleMap's upward check), so the umbrella re-exports it, not TUIkitFoundation; it re-exports
        // TUIkitFoundation in turn (Sources/TUIkitApp/Exports.swift), and TUIkitChrome since step B5b (below):
        // the run loop draws the window chrome, the status bar and the notifications around the content. POSIX
        // by design: no Windows step builds it (CLAUDE.md). DequeModule is its alone: only the `Terminal` files
        // use it.
        .target(
            name: "TUIkitApp",
            dependencies: [
                "TUIkitChrome", "TUIkitFoundation",
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B4's leaf, built on TUIkitFoundation as TUIkitApp is: `ColorPicker`, its panel and swatches, and the
        // gradient, tone-curve and channel-curve editors. The plan's map builds it on NumericControls, TextInput,
        // Pickers, Tabs and Presentation. TUIkitFoundation still compiles the first three; Presentation compiles into
        // TUIkitNavigation since step B5, whose `Dialog` and `.modal` its panels are made of, and Tabs into
        // TUIkitLists since step B6 (both below), whose `TabView` and `Tab` its panel is laid out with. Each other
        // edge appears when its module is carved. Nothing in TUIkitFoundation may use it (Tools/ModuleMap's upward
        // check), so the umbrella re-exports it. TUIkitImage is named for itself: the curve editors import it, its
        // `ASCIIToneCurve` is in their public initializers, and TUIkitFoundation, which re-exported it until step
        // B5c, does not depend on it since. The module re-exports all four (Sources/TUIkitColorPicker/Exports.swift).
        .target(
            name: "TUIkitColorPicker",
            dependencies: ["TUIkitFoundation", "TUIkitImage", "TUIkitLists", "TUIkitNavigation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5's leaf, built on TUIkitFoundation as the two above are, and the plan's first coarse GROUP: one
        // target that compiles two planned modules' directories. Sources/TUIkitNavigation holds `NavigationStack`,
        // `NavigationPath`, `NavigationLink`, the split views and the inspector; Sources/TUIkitPresentation holds
        // `alert`, `confirmationDialog`, `Dialog`, `sheet`, `fullScreenCover` and `modal`, and the presentation
        // modifiers. Step C1 peels TUIkitPresentation into a target of its own; until then its files compile into
        // this module. So the target names its two directories in `directories:`, as TUIkitFoundation does its
        // own, which excludes every other directory under Sources (`sourcesDirectories`, at the top of this
        // file). It depends on TUIkitChrome too since step B5b (below), the map's edge from Presentation:
        // a presentation draws its notifications with Chrome's `notificationHost(width:)`, and a modal docks
        // its presenter's focus through Chrome's presentation dock. Nothing in TUIkitFoundation may use it
        // (Tools/ModuleMap's upward check, which still checks the two directories as the two modules the map
        // plans), so the umbrella re-exports it, and so does TUIkitColorPicker. It re-exports TUIkitFoundation
        // and TUIkitChrome (Sources/TUIkitNavigation/Exports.swift).
        .target(
            name: "TUIkitNavigation",
            dependencies: ["TUIkitChrome", "TUIkitFoundation"],
            directories: ["TUIkitNavigation", "TUIkitPresentation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B6's leaf, built on TUIkitFoundation as the three above are, and the plan's second coarse group: one
        // target that compiles four planned modules' directories. Sources/TUIkitLists holds `List` and its core,
        // handler and styles, the rows' separators, insets, backgrounds, reordering and shortcuts, `OutlineGroup`
        // and `EditMode`; Sources/TUIkitTables holds `Table`, its columns, rows, builders and styles;
        // Sources/TUIkitTabs `TabView`, `Tab`, `TabSection` and the tab styles; Sources/TUIkitGrid `Grid`,
        // `GridRow`, `LazyVGrid` and `LazyHGrid`. Steps C2, C3 and C4 peel Tables, Tabs and Grid into targets of
        // their own; until then their files compile into this module. The map's edges from Tables and Tabs to
        // Lists stay inside the target, so of the map's modules it depends on TUIkitFoundation alone. Nothing in
        // TUIkitFoundation may use it (Tools/ModuleMap's upward check, which still checks the four directories as
        // the four modules the map plans), so the umbrella re-exports it, and so does TUIkitColorPicker. It
        // re-exports TUIkitFoundation (Sources/TUIkitLists/Exports.swift).
        .target(
            name: "TUIkitLists",
            dependencies: ["TUIkitFoundation"],
            directories: ["TUIkitLists", "TUIkitTables", "TUIkitTabs", "TUIkitGrid"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5b's three leaves, each built on TUIkitFoundation alone, each a module of the plan's map of its own
        // (no group), at its default path, Sources/<name>. TUIkitChrome is what the run loop draws around the
        // content: the `StatusBar` view, the toolbars, the notifications, the tooltip popover and `.help`,
        // `.statusBarItems`, the window chrome host, the overlay compositor, the screen selection's highlight
        // and Copy menu; the status bar's STATE, the tooltip's and the window chrome's, which focus and the
        // controls write, stay in TUIkitFoundation. TUIkitApp and TUIkitNavigation (its presentations) depend on
        // it and re-export it. TUIkitEffects is the transitions, content transitions, `.symbolEffect`,
        // `.visualEffect`, `.scrollTransition` and the colour effects; `TimelineView` and the symbol glyph's
        // effect, which `Label` and `ProgressView` draw, stay. TUIkitMenus is `Menu`, `ControlGroup`,
        // `.contextMenu`, `.menuStyle` and the menu styles, and the popup menu's core; the menu engine,
        // `ContextMenuState`, the menu-row sink and `MenuStyle` stay, so no leaf depends on it, and so do the
        // inline menu's core and the column it lays out, whose `bordered` and `foregroundStyle` results name
        // types only TUIkitFoundation can see (CONTRIBUTING.md, "Crossing a module boundary"). Nothing in
        // TUIkitFoundation may use any of the three (Tools/ModuleMap's upward check), so the umbrella re-exports
        // each. Each re-exports TUIkitFoundation (its Exports.swift).
        .target(
            name: "TUIkitChrome",
            dependencies: ["TUIkitFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUIkitEffects",
            dependencies: ["TUIkitFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "TUIkitMenus",
            dependencies: ["TUIkitFoundation"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // Step B5c's leaf, built on TUIkitFoundation as B5b's three are, a module of the plan's map of its own at its
        // default path: `Image`'s bitmap path. `Image(_:)` from a file or URL and `Image(_:bundle:)`, `AsyncImage`,
        // `_ImageCore` with its render cache, templates, resizing and orientation, `.terminalGraphics(_:)` and the
        // `.image*` rendering options, asset catalogues and `Color(_:bundle:)`, the `image:` initialisers of `Label`
        // and `ContentUnavailableView`. `Image` itself, `Image(systemName:)` and the raster seam the bitmap path
        // draws through (`_ImageRaster`, step A2's R2), `.aspectRatio`, `.scaledToFit`, `.scaledToFill` and
        // `.imageCellAspect` (A4's S1) stay. Nothing in TUIkitFoundation may use this module (Tools/ModuleMap's
        // upward check), so the umbrella re-exports it; no other leaf depends on it, and beside the umbrella and
        // the tests only TUIkitAppKit, which is no module of the map, does. It re-exports TUIkitFoundation and
        // TUIkitImage (Sources/TUIkitBitmaps/Exports.swift).
        //
        // TUIkitImage (the decoders, `ASCIIConverter`, `RGBAImage`) is a dependency of this module and of
        // TUIkitColorPicker, the only two leaves that name it. Of the framework's other modules only the umbrella,
        // which re-exports it, and TUIkitAppKit, whose `CGImage` and `NSImage` bridges make an `RGBAImage`, name
        // it; the tests and tools aside, nothing else does. TUIkitFoundation does not depend on it since this step,
        // so once per-module products ship, an app that uses none of TUIkitBitmaps, TUIkitColorPicker and
        // TUIkitAppKit links neither TUIkitImage nor CSTBImage.
        .target(
            name: "TUIkitBitmaps",
            dependencies: ["TUIkitFoundation", "TUIkitImage"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        // The umbrella: Sources/TUIkit/Exports.swift `@_exported import`s the leaves carved so far (TUIkitApp,
        // TUIkitBitmaps, TUIkitChrome, TUIkitColorPicker, TUIkitEffects, TUIkitLists, TUIkitMenus, TUIkitNavigation),
        // TUIkitFoundation and the lower four, and holds no code (Tools/ModuleMap's `umbrella` check), so `import
        // TUIkit` gives an app exactly what it gave when the framework was one TUIkit module. It names TUIkitImage
        // itself since step B5c: TUIkitFoundation no longer re-exports it. Its directory also holds the TUIkit.docc
        // catalog. Nothing in the package depends on it but the apps and the tests.
        .target(
            name: "TUIkit",
            dependencies: [
                "TUIkitApp", "TUIkitBitmaps", "TUIkitChrome", "TUIkitColorPicker", "TUIkitEffects", "TUIkitLists",
                "TUIkitMenus", "TUIkitNavigation", "TUIkitFoundation", "TUIkitCore", "TUIkitStyling", "TUIkitImage",
                "TUIkitView",
            ]
        ),

        // One target, many directories. The module split (Documentation/Historical/Module split plan,
        // revision 4) puts each planned module's files in Sources/<module>, where the module will live
        // once a step of Phase B carves it into a target of its own; until then this one target compiles
        // them all, as the module TUIkitFoundation (step B1). A carve adds `.target(name: "TUIkitX", …)`
        // at its default path and takes "TUIkitX" out of `directories:` below (as TUIkitApp, step B3,
        // TUIkitChrome, TUIkitEffects and TUIkitMenus, step B5b, and TUIkitBitmaps, step B5c); a coarse group's
        // carve adds one target over its modules' directories (`directories:`, as TUIkitNavigation, step B5, and
        // TUIkitLists, step B6) and takes each of them out. When the last module has left, this target is
        // an ordinary one at Sources/TUIkitFoundation.
        // Tools/ModuleMap checks the map: a file's directory is its module. It depends on neither TUIkitImage nor
        // CSTBImage since step B5c took the bitmap path out (the plan's B5c row): its `lower` list in rules.json
        // names TUIkitCore, TUIkitStyling and TUIkitView, and the `lower` check fails CI on a use of any other.
        .target(
            name: "TUIkitFoundation",
            dependencies: [
                "TUIkitCore", "TUIkitStyling", "TUIkitView", "TUIkitStrings", "TUIkitTerminalHost",
            ],
            // The planned modules not yet carved, in rules.json's order; every other directory under Sources
            // is excluded (`sourcesDirectories`, at the top of this file), so a module directory left out
            // here, and compiled by no other target, draws no SwiftPM warning: Tools/ModuleMap's `uncompiled`
            // check, which gates CI, fails on a file of a module's directory that the build did not compile.
            directories: [
                "TUIkitFoundation", "TUIkitNumericControls", "TUIkitTextInput", "TUIkitPickers", "TUIkitForms",
                "TUIkitSearch",
            ],
            // A member is visible in a file only if that file imports the
            // module declaring it. Without this, every extension member of
            // every module LOADED is in scope — and on macOS that included
            // SwiftUICore, which AppKit imports (not re-exports), while TUIkit
            // imported AppKit: its `AttributeScopes.SwiftUIAttributes` made
            // TUIkit's own scope of that name ambiguous wherever TUIkit spelled
            // it. Nothing TUIkit is built from imports AppKit now (decisions
            // B50: the bridges are `TUIkitAppKit`), and this stays as the
            // guard that keeps a stray import from bringing that back.
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // The bridges to AppKit and Core Graphics: the one module that
        // imports AppKit. Empty off Apple platforms. It depends on the modules
        // whose types it extends (which re-export the lower ones), not on the
        // umbrella, which only the apps and the tests depend on: since step
        // B5c TUIkitBitmaps too, whose bitmap path an image made from a
        // `CGImage` or an `NSImage`, or a compiled asset catalogue's, draws
        // through.
        .target(
            name: "TUIkitAppKit",
            dependencies: ["TUIkitBitmaps", "TUIkitFoundation", "TUIkitImage"],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),

        // The `@Animatable` macros: the declarations, and the compiler plugin
        // that expands them. Nothing else in the package depends on either.
        .target(name: "TUIkitMacros", dependencies: ["TUIkitMacrosPlugin", "TUIkitCore"]),
        .macro(
            name: "TUIkitMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // ── App & Tests ─────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "Example",
            dependencies: ["TUIkit"],
            resources: [.copy("Resources")]
        ),
        // The umbrella test target: integration tests + every test that exercises
        // a control, the App/run loop, focus, or the shared render helpers (which
        // live in this target). Module-specific *unit* tests live in the
        // per-module test targets below, which link ONLY their module (+ its
        // real deps) so a test that reaches across a module boundary fails to
        // compile. `swift test` runs every target, so the full suite is
        // unchanged. Tools/validate-test-boundaries.sh enforces this going
        // forward (see also the per-target import guard it applies). A test
        // imports TUIkit, as an app does, and `@testable import`s
        // TUIkitFoundation where it reaches the framework's internals, or the
        // carved module that declares them (TUIkitStrings, TUIkitTerminalHost,
        // TUIkitApp, TUIkitColorPicker, TUIkitNavigation, TUIkitLists,
        // TUIkitChrome, TUIkitEffects, TUIkitMenus, TUIkitBitmaps).
        .testTarget(
            name: "TUIkitTests",
            dependencies: [
                "TUIkit", "TUIkitApp", "TUIkitBitmaps", "TUIkitChrome", "TUIkitColorPicker", "TUIkitEffects",
                "TUIkitFoundation", "TUIkitLists", "TUIkitMenus", "TUIkitNavigation", "TUIkitStrings",
                "TUIkitTerminalHost", "TUIkitAppKit", "TUIkitWidthCorpus", "CTestSupport",
            ],
            // Golden snapshots are read/written by path (#filePath-relative, see
            // TestHelpers/SnapshotTesting.swift), not via the resource bundle, so
            // exclude them from the build rather than declaring them as resources.
            // The same for the fixtures read by path (an asset catalogue, and the
            // `Assets.car` Xcode compiled from it).
            exclude: ["__Snapshots__", "__Fixtures__"]
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
            dependencies: ["Example", "TUIkit", "TUIkitApp", "TUIkitFoundation"]
        ),

        // ── Per-module unit-test targets (compiler-enforced layering) ──────────────────────────────────────
        // Each links ONLY its module. A unit test that drifts into a sibling or
        // higher layer stops compiling here — that is the point: it keeps every
        // module provably testable in isolation.
        .testTarget(name: "TUIkitCoreTests", dependencies: ["TUIkitCore", "TUIkitWidthCorpus"]),
        .testTarget(name: "TUIkitStylingTests", dependencies: ["TUIkitStyling"]),
        .testTarget(name: "TUIkitViewTests", dependencies: ["TUIkitView"]),
        .testTarget(name: "TUIkitImageTests", dependencies: ["TUIkitImage"]),

        // The macros, used as an app uses them: expanded in test sources. Not
        // also on the plugin target, to check expansions as source: a test
        // target that depends on a macro target has SwiftPM build the whole
        // test product for the host, and `ExampleTests` then cannot import the
        // `Example` executable (measured, SwiftPM 6.2.4).
        .testTarget(name: "TUIkitMacrosTests", dependencies: ["TUIkitMacros", "TUIkit"]),

        // ── Stress test ─────────────────────────────────────────────────────────────────────────────────
        // A performance stress harness shaped like an app: deep/wide view
        // hierarchies over large, pseudo-randomly synthesised data sets. Runs
        // interactively, or headless (`--bench`/`--selfcheck`) as a no-PTY
        // profiling instrument (see Sources/Stress/README.md).
        .executableTarget(
            name: "TerminalClientQuirks",
            dependencies: ["TUIkit", "TUIkitWidthCorpus"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),
        .executableTarget(
            name: "Stress",
            dependencies: ["TUIkit"],
            exclude: ["README.md"]  // documentation, not a bundled resource
        ),

        // ── Tools ───────────────────────────────────────────────────────────────────────────────────────
        .executableTarget(
            name: "EmojiBugScanner",
            dependencies: ["TUIkitCore"],
            path: "Tools/EmojiBugScanner"
        ),
        .executableTarget(
            name: "EmojiBenchmark",
            dependencies: ["TUIkitCore"],
            path: "Tools/EmojiBenchmark"
        ),
        // Mode A profiling harness (see Tools/Profiling/README.md): a
        // no-PTY, no-attach executable that loops `renderToBuffer` over a
        // representative tree so it can be profiled with `xctrace --launch`
        // in environments where `--attach` is denied.
        .executableTarget(
            name: "RenderHarness",
            dependencies: ["TUIkit"],
            path: "Tools/Profiling/RenderHarness"
        ),

        // The same, for the IMAGE pipeline: an `ASCIIConverter` looped over a
        // picture. Separate from `RenderHarness` because the two halves of the
        // image path — per cell (`convert`) and per pixel (`recoloured`) —
        // have to be measured separately, and neither is a view render.
        .executableTarget(
            name: "ImageHarness",
            dependencies: ["TUIkitImage", "TUIkitStyling"],
            path: "Tools/Profiling/ImageHarness"
        ),

        // The smallest app that can be asked "does this view cost anything when
        // nothing is happening?" — one view, nothing focusable, no timers. Every
        // Example page carrying an Image also carries focusable controls, whose
        // focus pulse keeps the loop legitimately awake and makes the reading
        // meaningless. Driven by `Tools/Profiling/idle-image.sh`.
        .executableTarget(
            name: "IdleProbe",
            dependencies: ["TUIkit"],
            path: "Tools/Profiling/IdleProbe"
        ),
    ]
)

// ── Benchmarks (opt-in) ───────────────────────────────────────────────────────────────────────────
// ordo-one/package-benchmark and the `TUIkitBenchmarks` target are gated behind
// an environment flag so the default `swift build` / `swift test` graph never
// pulls in the benchmark dependency. That keeps test output free of the plugin's
// upstream PackagePlugin deprecation warnings and removes the jemalloc build
// requirement for ordinary development. Enable benchmarking by exporting
// TUIKIT_BENCHMARKS, e.g.
//   TUIKIT_BENCHMARKS=1 swift package benchmark
//   TUIKIT_BENCHMARKS=1 swift package benchmark run TUIkitBenchmarks <name>
if Context.environment["TUIKIT_BENCHMARKS"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.29.4", traits: [])
    )
    package.targets.append(
        .executableTarget(
            name: "TUIkitBenchmarks",
            dependencies: [
                "TUIkit",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/TUIkitBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    )
}
