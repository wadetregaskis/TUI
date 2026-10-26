//  🖥️ TUI — A Terminal UI framework for Swift
//  StressConfig.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUI

// MARK: - Run configuration

/// Everything a scenario needs to size and seed itself, parsed once at launch
/// from environment variables (so a profiler can pin a run) and/or CLI args
/// (which override the environment).
///
/// Environment:
/// - `TUIKIT_STRESS_SCENARIO` — id to boot directly into (skips the menu).
/// - `TUIKIT_STRESS_SCALE`    — integer multiplier on every scenario's size.
/// - `TUIKIT_STRESS_SEED`     — RNG seed for synthetic data.
/// - `TUIKIT_STRESS_AUTOPILOT`— `1`/`true` to self-drive continuous re-renders.
///
/// CLI (see `main.swift`): `--scenario`, `--scale`, `--seed`, `--autopilot`,
/// plus the headless modes `--selfcheck` and `--bench`.
struct StressConfig {
    /// Multiplier applied to each scenario's base size. `1` is already heavy;
    /// `10`/`100` push into pathological territory for profiling.
    var scale: Int = 1

    /// Seed for all synthetic data. Fixed by default for reproducibility.
    var seed: UInt64 = 0x5715_2025

    /// When set, the app bumps a tick every frame to keep the demand-driven
    /// render loop busy (so a static screen still produces a steady workload to
    /// profile under `drive.py`). Scenarios may also weave the tick into their
    /// content to force cache misses.
    var autopilot: Bool = false

    /// A monotonically increasing frame counter (driven by autopilot, or by
    /// real input). Scenarios read it to animate / churn.
    var tick: Int = 0

    /// Scenario id to start in, or `nil` for the menu.
    var initialScenario: String?

    /// Which VARIANT of a matrix scenario to build.
    ///
    /// A matrix scenario is one `Scenario` covering many shapes of one API —
    /// every way a `Table` can be given its data, sized, truncated, aligned,
    /// selected and updated — rather than one scenario per shape. One id keeps
    /// the registry and its seven translation tables the size they are; the
    /// variant picks the point in the space, and `--variants` lists them.
    ///
    /// `nil` builds the variant the matrix nominates as its default, so
    /// `--bench --scenario table-api` works without one.
    var variant: String?

    /// The alternating-row behaviour `--bench` draws every scenario under, or
    /// `nil` for none stated — each table and list then stripes as it does by
    /// default (a table does, decisions A29).
    ///
    /// For pricing the stripe on ONE binary: the same build timed under
    /// `disabled` and under `automatic` differs by the stripe's own cost and
    /// nothing else, where two builds also differ by code layout, which has
    /// moved identical code by several per cent. `TUIKIT_STRESS_STRIPES` is the
    /// spelling `ab_bench.py` can carry, since it passes its environment to
    /// both binaries and no flags of its own.
    ///
    /// Only `--bench` of a scenario draws under it; `main.swift` stops any
    /// other run that states it (`--selfcheck`, a session, the interactive app
    /// each draw pages of their own), and any run whose value names no
    /// behaviour (``unknownStripes``) — an A/B meant to price the stripe must
    /// never time the striped build under a setting that says otherwise.
    var stripes: AlternatingRowBackgroundBehavior?

    /// A stated `--stripes` / `TUIKIT_STRESS_STRIPES` value that names no
    /// behaviour (`--stripes disable`; empty after a trailing `--stripes`),
    /// kept so `main.swift` can refuse the run rather than drop it silently.
    var unknownStripes: String?

    /// The behaviour a `--stripes` value names, or `nil` for none it knows.
    static func stripes(named name: String) -> AlternatingRowBackgroundBehavior? {
        switch name.lowercased() {
        case "automatic": .automatic
        case "enabled": .enabled
        case "disabled": .disabled
        default: nil
        }
    }

    /// States the behaviour `name` names, or records `name` as unknown — the
    /// later statement wins either way, so a flag overrides the environment.
    private mutating func stateStripes(named name: String) {
        if let behavior = Self.stripes(named: name) {
            stripes = behavior
            unknownStripes = nil
        } else {
            unknownStripes = name
        }
    }

    /// Scales a base count by `scale`, clamped to at least 1.
    func sized(_ base: Int) -> Int { max(1, base * scale) }

    // MARK: Parsing

    /// Builds a config from the environment, then applies CLI overrides.
    static func fromEnvironmentAndArgs(_ args: [String]) -> Self {
        var config = Self()
        config.applyEnvironment(ProcessInfo.processInfo.environment)
        config.applyArguments(args)
        return config
    }

    /// The environment half, split from the argument half only to keep each
    /// under the complexity limit — every option is readable in one of them.
    private mutating func applyEnvironment(_ env: [String: String]) {
        if let s = env["TUIKIT_STRESS_SCALE"], let value = Int(s) { scale = max(1, value) }
        if let s = env["TUIKIT_STRESS_SEED"], let value = UInt64(s) { seed = value }
        if let s = env["TUIKIT_STRESS_AUTOPILOT"] { autopilot = (s == "1" || s.lowercased() == "true") }
        if let s = env["TUIKIT_STRESS_SCENARIO"], !s.isEmpty { initialScenario = s }
        if let s = env["TUIKIT_STRESS_VARIANT"], !s.isEmpty { variant = s }
        if let s = env["TUIKIT_STRESS_STRIPES"], !s.isEmpty { stateStripes(named: s) }
    }

    /// The CLI half, which overrides the environment.
    private mutating func applyArguments(_ args: [String]) {
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--scale": if let value = it.next().flatMap(Int.init) { scale = max(1, value) }
            case "--seed": if let value = it.next().flatMap(UInt64.init) { seed = value }
            case "--autopilot": autopilot = true
            case "--scenario": if let value = it.next() { initialScenario = value }
            case "--variant": if let value = it.next() { variant = value }
            case "--stripes": stateStripes(named: it.next() ?? "")
            default: break  // headless flags are handled in main.swift
            }
        }
    }
}
