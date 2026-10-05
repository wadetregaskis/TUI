// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

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

        // ── High-level (aggregates all) ─────────────────────────────────────────────────────────────────
        .target(
            name: "TUIkit",
            dependencies: [
                "TUIkitCore", "TUIkitStyling", "TUIkitImage", "TUIkitView",
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            resources: [.copy("Localization/translations"), .copy("VERSION")],
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
        // imports AppKit. Empty off Apple platforms.
        .target(
            name: "TUIkitAppKit",
            dependencies: ["TUIkit", "TUIkitImage"],
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
        // forward (see also the per-target import guard it applies).
        .testTarget(
            name: "TUIkitTests",
            dependencies: ["TUIkit", "TUIkitAppKit", "CTestSupport"],
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
            dependencies: ["Example", "TUIkit"]
        ),

        // ── Per-module unit-test targets (compiler-enforced layering) ──────────────────────────────────────
        // Each links ONLY its module. A unit test that drifts into a sibling or
        // higher layer stops compiling here — that is the point: it keeps every
        // module provably testable in isolation.
        .testTarget(name: "TUIkitCoreTests", dependencies: ["TUIkitCore"]),
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
            dependencies: ["TUIkit"],
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
