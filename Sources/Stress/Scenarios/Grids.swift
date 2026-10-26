//  🖥️ TUI — A Terminal UI framework for Swift
//  Grids.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - Grids

/// The dashboard's metric panels in a grid: what a `LazyVGrid` and a `Grid`
/// cost per cell, which no other scenario draws (decisions SPB6, B-SPB6-2).
///
/// `lazy` is the default, so the sweep runs it: an adaptive `LazyVGrid` in a
/// scroll view, the shape decisions B71 owes a lazy grid's cost to. `fixed` is
/// the eager kind, a `Grid` of `GridRow`s whose every cell is measured for its
/// column's width, a header spanning the row (`gridCellColumns(_:)`), and the
/// figures trailing-aligned in their columns — the lattice's alignment offsets
/// and the layout's subview placement, per cell.
enum GridsMatrix {
    static let scenarioID = "grids"

    @MainActor
    static let descriptor = Scenario(
        id: scenarioID,
        title: "Grids",
        blurb: "Metric panels in an adaptive LazyVGrid, or a Grid of GridRows with a spanning header.",
        stresses: "lazy grid columns and rows · the eager grid's per-cell measure, alignment and placement",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.grids.heading", "?", 0)))
        }
    )

    private static func variant(
        _ id: String, _ summary: String, _ make: @escaping @MainActor (StressConfig) -> AnyView
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: "grid", make: make)
    }

    @MainActor
    static let variants: [ScenarioVariant] = [
        variant("lazy", "the dashboard's panels in a LazyVGrid of adaptive columns, in a scroll view") { config in
            AnyView(LazyPanelGrid(config: config))
        },
        variant("fixed", "a Grid of GridRows: a spanning header over rows of trailing-aligned figures") { config in
            AnyView(FigureGrid(config: config))
        },
    ]
}

/// `MetricCard`s in adaptive columns at least 24 cells wide.
private struct LazyPanelGrid: View {
    let config: StressConfig

    var body: some View {
        let cards = config.sized(48)
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.grids.heading", "lazy", cards)).bold()
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 24))], spacing: 1) {
                    ForEach(0..<cards, id: \.self) { index in
                        MetricCard(seed: config.seed, index: index)
                    }
                }
            }
        }
    }
}

/// A table of figures as a `Grid`: one header row spanning every column, then
/// a name and four figures a row, the figures moving with the tick.
private struct FigureGrid: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let rows = config.sized(60)
        let tick = clock.tick
        VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.grids.heading", "fixed", rows * 5)).bold()
            Divider()
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 2, verticalSpacing: 0) {
                    GridRow {
                        Text(verbatim: Synth.name(config.seed)).bold().gridCellColumns(5)
                    }
                    ForEach(0..<rows, id: \.self) { row in
                        let h = mix(config.seed, row &+ tick)
                        GridRow {
                            Text(verbatim: Synth.slug(h))
                            ForEach(0..<4, id: \.self) { column in
                                Text(verbatim: "\(mix(h, column) % 10_000)")
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}
