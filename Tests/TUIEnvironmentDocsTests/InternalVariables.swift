//  🖥️ TUI — A Terminal UI framework for Swift
//  InternalVariables.swift
//
//  The variables that don't go in the public table, because nobody using TUI has a
//  use for them, each with the reason it's kept from them. `Documentation/Environment
//  variables for developing TUI.md` says what each does, and a test holds that page
//  and this list together.
//
//  Created by Wade Tregaskis
//  License: MIT

enum InternalVariables {
    /// Read by the framework, for debugging the framework, each with why it isn't
    /// documented for the people who use TUI.
    static let framework: [String: String] = [
        "TUI_DEBUG_FOCUS": "Its log is of the focus system's own workings, which only TUI's developers read.",
        "TUI_HEADLESS_STREAM": "It feeds TUI's own output tools.",
        "TUI_KEEP_BODIES": "It turns an optimisation off to compare with it, and `all` is for a run of TUI's tests.",
        "TUI_OBSERVATION_RETIREMENT": "It picks between implementations, to compare them.",
        "TUI_OPTION_C": "It turns an optimisation off to compare with it.",
        "TUI_PLAIN_TEXT": "The owner ruled (2026-11-01) that nothing should encourage an ASCII-only mode except for testing.",
        "TUI_SCROLL_CENSUS": "It measures what the scroll levels would do, for TUI's developers.",
        "TUI_STILL": "It freezes the screen for clips and tests; the owner kept it internal (2026-11-01).",
    ]

    /// Read by the Example and Stress targets alone, which aren't what an app links.
    static let exampleAndStress: [String: String] = [
        "TUI_EXAMPLE_GROUND_ALPHA": "The Example alone reads it.",
        "TUI_EXAMPLE_PAGE": "The Example alone reads it.",
        "TUI_EXAMPLE_PALETTE_ALPHA": "The Example alone reads it.",
        "TUI_EXAMPLE_PICTURE": "The Example alone reads it.",
        "TUI_STRESS_AUTOPILOT": "Stress alone reads it.",
        "TUI_STRESS_SCALE": "Stress alone reads it.",
        "TUI_STRESS_SCENARIO": "Stress alone reads it.",
        "TUI_STRESS_SEED": "Stress alone reads it.",
        "TUI_STRESS_STRIPES": "Stress alone reads it.",
        "TUI_STRESS_VARIANT": "Stress alone reads it.",
    ]

    /// Read or set by the package manifest, the tests and the tools alone.
    static let testsAndTools: [String: String] = [
        "TUI_AUDIT_DUMP": "A test alone reads it.",
        "TUI_BENCHMARKS": "The manifest reads it, to build TUI's own benchmarks.",
        "TUI_BENCH_MAX_DURATION_MS": "The benchmarks alone read it.",
        "TUI_BENCH_RUN_VIEW": "The benchmarks alone read it.",
        "TUI_MEASURE_FLEX_PROBE": "A test alone reads it.",
        "TUI_PARALLEL_TEST_LOCK": "A tool alone reads it.",
        "TUI_PARALLEL_TEST_STALL_SECONDS": "A tool alone reads it.",
        "TUI_PRODUCT_SMOKE_URL": "A tool alone reads it.",
        "TUI_RUN_WRAPPER": "A tool alone reads it.",
        "TUI_SEED_MECHANISM_PROBE": "A test makes it up and reads it.",
        "TUI_WASM_SDK": "The web demo's build script alone reads it.",
        "TUI_WASM_SWIFT": "The web demo's build script alone reads it.",
        "TUI_WASM_TOOLCHAIN": "The web demo's build script alone reads it.",
    ]

    /// Every name above.
    static let all = Set(framework.keys).union(exampleAndStress.keys).union(testsAndTools.keys)

    /// What looks like a variable and isn't: compile-time conditions, set with `-D`, and
    /// the names a test of `TerminalCapabilities.isForced` makes up.
    static let compileConditions: Set<String> = ["TUI_TEST_SUPPORT", "TUI_VALUE_HASH_CENSUS", "TUI_X", "TUI_Y"]

    /// String literals in capitals, in a file that reads the environment, that aren't
    /// the name of a variable.
    static let notVariables: Set<String> = ["A", "B", "ESC", "FAIL", "P", "SCREEN", "SS", "VERSION", "X"]
}
