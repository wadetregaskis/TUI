//  🖥️ TUI — A Terminal UI framework for Swift
//  InternalVariables.swift
//
//  The variables that don't go in the public table, because nobody using TUI has a
//  use for them. `Documentation/Environment variables for developing TUI.md` says
//  what each is for, and a test holds that page and this list together.
//
//  Created by Wade Tregaskis
//  License: MIT

enum InternalVariables {
    /// Read by the framework, for debugging the framework.
    static let framework: Set<String> = [
        "TUI_DEBUG_FOCUS", "TUI_OBSERVATION_RETIREMENT", "TUI_OPTION_C",
    ]

    /// Read by the Example and Stress targets alone, which aren't what an app links.
    static let exampleAndStress: Set<String> = [
        "TUI_EXAMPLE_GROUND_ALPHA", "TUI_EXAMPLE_PALETTE_ALPHA", "TUI_EXAMPLE_PICTURE",
        "TUI_STRESS_AUTOPILOT", "TUI_STRESS_SCALE", "TUI_STRESS_SCENARIO", "TUI_STRESS_SEED",
        "TUI_STRESS_STRIPES", "TUI_STRESS_VARIANT",
    ]

    /// Read or set by the package manifest, the tests and the tools alone.
    static let testsAndTools: Set<String> = [
        "TUI_AUDIT_DUMP", "TUI_BENCHMARKS", "TUI_BENCH_MAX_DURATION_MS", "TUI_BENCH_RUN_VIEW",
        "TUI_MEASURE_FLEX_PROBE", "TUI_PARALLEL_TEST_LOCK", "TUI_PARALLEL_TEST_STALL_SECONDS",
        "TUI_PRODUCT_SMOKE_URL", "TUI_SEED_MECHANISM_PROBE", "TUI_WASM_SDK", "TUI_WASM_SWIFT",
        "TUI_WASM_TOOLCHAIN",
    ]

    /// Every name above.
    static let all = framework.union(exampleAndStress).union(testsAndTools)

    /// What looks like a variable and isn't: compile-time conditions, set with `-D`, and
    /// the names a test of `TerminalCapabilities.isForced` makes up.
    static let compileConditions: Set<String> = ["TUI_TEST_SUPPORT", "TUI_VALUE_HASH_CENSUS", "TUI_X", "TUI_Y"]

    /// String literals in capitals, in a file that reads the environment, that aren't
    /// the name of a variable.
    static let notVariables: Set<String> = ["A", "B", "ESC", "SCREEN", "SS", "VERSION"]
}
