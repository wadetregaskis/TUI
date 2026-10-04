//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

// MARK: - Control Rows

/// Rows of one common control each: what a control costs on its own, which no
/// other scenario isolates.
///
/// The other scenarios mix controls into pages, so a change to one control's
/// per-render cost is diluted by everything around it, and several controls
/// appear in none of them at all — a tappable row, a `Label`, a `TextField`
/// outside a form, a `Text` literal holding Markdown. Each variant here is one
/// control, so a change to it reads in that variant and nowhere else.
///
/// The rows fold the harness's tick into their content, so no memo serves a
/// row and every frame pays the control's whole measure and render. The
/// `-stable` variants hold still instead, so the row memo serves every row and
/// the frame pays only what a served row replays. `scroll-resize` holds its
/// rows still and resizes the scroll view around them every frame, which is
/// what a container whose size others depend on has to survive.
enum ControlRowsMatrix {
    static let scenarioID = "controls"

    @MainActor
    static let descriptor = Scenario(
        id: scenarioID,
        title: "Control Rows",
        blurb: "Rows of one common control each — tappable text, labels, fields, interpolated and Markdown text, progress bars.",
        stresses: "one control's per-render cost in isolation · gesture registration · style hosts · Markdown keys · container resize",
        make: { config in
            ScenarioVariants.resolve(config, in: scenarioID)?.make(config)
                ?? AnyView(Text(Lf("stress.scenario.controls.heading", "?", 0)))
        }
    )

    private static func variant(
        _ id: String, _ summary: String, _ make: @escaping @MainActor (StressConfig) -> AnyView
    ) -> ScenarioVariant {
        ScenarioVariant(id: id, summary: summary, axis: "control", make: make)
    }

    /// `rows` rows of `row`, each told its index and its content's hash — the
    /// hash moving with the tick unless `stable`.
    @MainActor
    private static func rows(
        _ config: StressConfig, _ id: String, stable: Bool = false,
        _ row: @escaping @MainActor (Int, UInt64) -> some View
    ) -> AnyView {
        AnyView(ControlRowsView(config: config, variant: id, stable: stable, row: row))
    }

    @MainActor
    static let variants: [ScenarioVariant] = [
        variant("tap", "text rows, each with onTapGesture") { config in
            rows(config, "tap") { _, h in Text(verbatim: Synth.name(h)).onTapGesture(count: 1) {} }
        },
        variant("tap-stable", "the same rows held still, so the row memo serves them") { config in
            rows(config, "tap-stable", stable: true) { _, h in Text(verbatim: Synth.name(h)).onTapGesture(count: 1) {} }
        },
        variant("labels", "Label(_:systemImage:) rows in the default label style") { config in
            rows(config, "labels") { _, h in Label(Synth.name(h), systemImage: "doc") }
        },
        variant("fields", "TextField rows, each with a constant binding") { config in
            rows(config, "fields") { _, h in TextField("Name", text: .constant(Synth.name(h))) }
        },
        variant("interpolated", "Text literals with two interpolations: a key with arguments") { config in
            rows(config, "interpolated") { index, h in Text("#\(index) \(Synth.name(h))") }
        },
        variant("markdown", "Text literals holding Markdown around two interpolations") { config in
            rows(config, "markdown") { _, h in Text("**\(Synth.name(h))** in `\(Synth.status(h))`") }
        },
        variant("progress", "determinate ProgressView rows") { config in
            rows(config, "progress") { _, h in ProgressView(value: Double(h % 100) / 100) }
        },
        variant("scroll-resize", "still rows in a scroll view whose height changes every frame") { config in
            AnyView(ResizingScrollView(config: config))
        },
    ]
}

/// The rows, under a heading, in a scroll view as an app lists them.
private struct ControlRowsView<Row: View>: View {
    let config: StressConfig
    let variant: String
    let stable: Bool
    let row: @MainActor (Int, UInt64) -> Row
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(200)
        let tick = stable ? 0 : clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.controls.heading", variant, count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        row(index, mix(config.seed, index &+ tick))
                    }
                }
            }
        }
    }
}

/// Still rows in a scroll view that grows and shrinks by a row each frame,
/// over a ten-frame cycle.
private struct ResizingScrollView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(200)
        let height = 20 + clock.tick % 10
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.controls.heading", "scroll-resize", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        Text(verbatim: Synth.name(mix(config.seed, index)))
                    }
                }
            }
            .frame(height: height)
        }
    }
}
