//  🖥️ TUI — A Terminal UI framework for Swift
//  Scenario.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUI

// MARK: - Scenario

/// One stress scenario: a heavy, scalable, deterministic view tree plus the
/// metadata the menu and the headless runners need.
///
/// `make` is type-erased to `AnyView` only at this registry boundary — each
/// scenario's *internal* tree keeps its concrete types (where the real
/// `measureChild`/`Layoutable` dispatch cost lives), so the single erasure at
/// the root is negligible against the thousands of concrete nodes beneath it.
/// (For AnyView-free micro-profiling of a specific shape, add a tree to
/// `Tools/Profiling/RenderHarness/Trees.swift` instead.)
struct Scenario {
    /// Stable id used by `--scenario` / `TUI_STRESS_SCENARIO`. Also the key
    /// stem for this scenario's localized strings (`stress.scenario.<id>.*`).
    let id: String
    /// Menu title, in English. The interactive shell shows ``localizedTitle``;
    /// this stays English for the `--selfcheck` stdout listing.
    let title: String
    /// One-line description, in English (see ``localizedBlurb``).
    let blurb: String
    /// Which part of the pipeline this is built to stress, in English
    /// (see ``localizedStresses``).
    let stresses: String
    /// Builds the scenario's view for the given configuration.
    let make: @MainActor (StressConfig) -> AnyView
    /// Builds a DRIVEN scenario — a view over a model the harness writes
    /// between frames — or `nil` for a scenario that is only a view. See
    /// ``DrivenScenario``.
    var drive: (@MainActor (StressConfig) -> DrivenScenario?)?

    /// The menu title for the current language.
    ///
    /// There is no fallback to ``title``: a table without the key shows the KEY
    /// (`L` returns what it was given), which is what the source-parity test
    /// over the string tables exists to catch. The English fields on this
    /// struct are the source text the tables are written from.
    var localizedTitle: String { L("stress.scenario.\(id).title") }
    /// The one-line description for the current language; see ``localizedTitle``.
    var localizedBlurb: String { L("stress.scenario.\(id).blurb") }
    /// The "stresses" summary for the current language; see ``localizedTitle``.
    var localizedStresses: String { L("stress.scenario.\(id).stresses") }
}

// MARK: - Driven scenarios

/// A scenario's view and what moves its model between frames.
///
/// A scenario at rest reads the shared `StressClock` and derives what it
/// shows from the tick, which is a pure function of the frame. A model an app
/// reads is not: it is WRITTEN, outside any render, and what a write
/// invalidates is part of what a frame costs. So a driven scenario hands the
/// harness the write to make before each frame, with the frame's tick.
/// `--bench` and `--selfcheck` make it; the interactive shell shows the view
/// at rest.
struct DrivenScenario {
    let view: AnyView
    let advance: @MainActor (_ tick: Int) -> Void
    /// Whether `--bench` gives each frame the clock the run loop gives it — a
    /// 60 Hz frame time from the tick, and that it can animate — rather than a
    /// one-off render's. Off for every scenario but one whose motion is what
    /// it measures (`glide`): turned on everywhere, it would let every change
    /// in every other scenario start an animation the bench never finishes.
    var runsAnimationClock = false
}

// MARK: - Registry

/// The full scenario catalogue, in a deliberate order (cheap → pathological).
enum Scenarios {
    @MainActor
    static let all: [Scenario] = [
        MegaListScenario.descriptor,
        ScrollFollowScenario.descriptor,
        ScrollEagerScenario.descriptor,
        GlideMatrix.descriptor,
        WideTableScenario.descriptor,
        MultiLineTableScenario.descriptor,
        TruncatingTableScenario.descriptor,
        ChurningTableScenario.descriptor,
        ChurningWrappedTableScenario.descriptor,
        TailingTableScenario.descriptor,
        TableAPIMatrix.descriptor,
        AppShapeMatrix.descriptor,
        TablesInScrollViewScenario.descriptor,
        TablesInVStackScenario.descriptor,
        DeepRecursionScenario.descriptor,
        WideFanoutScenario.descriptor,
        ModifierChainsScenario.descriptor,
        PreferenceRowsScenario.descriptor,
        GeometryScenario.descriptor,
        CustomLayoutScenario.descriptor,
        TextWallScenario.descriptor,
        AnyViewStormScenario.descriptor,
        DashboardScenario.descriptor,
        FramedColumnsScenario.descriptor,
        ChurnUpdateScenario.descriptor,
        AnimatingScenario.descriptor,
        TranslucentScenario.descriptor,
        GradientsScenario.descriptor,
        AlphaRampsScenario.descriptor,
        MenuBarScenario.descriptor,
        KeyRowsScenario.descriptor,
        SheetRowsScenario.descriptor,
        ControlRowsMatrix.descriptor,
        GridsMatrix.descriptor,
        PickerRowsMatrix.descriptor,
        StatefulRowsScenario.descriptor,
        KitchenSinkScenario.descriptor,
    ]

    @MainActor
    static func byID(_ id: String) -> Scenario? {
        all.first { $0.id == id }
    }
}
