//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

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
        variant("alert", "text rows, each carrying an .alert nobody presents") { config in
            rows(config, "alert") { _, h in
                Text(verbatim: Synth.name(h)).alert("Delete?", isPresented: .constant(false)) { Button("Delete") {} }
            }
        },
        variant("alert-stable", "the same rows held still, so the row memo may serve them") { config in
            rows(config, "alert-stable", stable: true) { _, h in
                Text(verbatim: Synth.name(h)).alert("Delete?", isPresented: .constant(false)) { Button("Delete") {} }
            }
        },
        variant("sheet", "text rows, each carrying a .sheet nobody presents") { config in
            rows(config, "sheet") { _, h in
                Text(verbatim: Synth.name(h)).sheet(isPresented: .constant(false)) { Text(verbatim: "sheet") }
            }
        },
        variant("sheet-stable", "the same rows held still, so the row memo may serve them") { config in
            rows(config, "sheet-stable", stable: true) { _, h in
                Text(verbatim: Synth.name(h)).sheet(isPresented: .constant(false)) { Text(verbatim: "sheet") }
            }
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
        variant("buttons-50", "50 still buttons in one focus section, served by the row memo") { config in
            AnyView(ButtonGrid(config: config, count: 50))
        },
        variant("buttons-100", "100 still buttons in one focus section, served by the row memo") { config in
            AnyView(ButtonGrid(config: config, count: 100))
        },
        variant("buttons-200", "200 still buttons in one focus section, served by the row memo") { config in
            AnyView(ButtonGrid(config: config, count: 200))
        },
        variant("buttons-200-live", "the 200 buttons redrawn every frame, nothing served") { config in
            AnyView(ButtonGrid(config: config, count: 200, live: true))
        },
        variant("focused", "40 fields bound by .focused(_:equals:) in a scroll view in a scroll view") { config in
            AnyView(FocusedFields(config: config))
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

/// `count` still buttons, ten to a line and none in a scroll view, so every one
/// is drawn and registers in the one focus section every frame: what focus
/// registration costs a page of controls. Only the line above them moves with
/// the tick, so the lines of buttons are served from the memo, their
/// registrations replayed — unless `live`, when the page reads the tick and
/// every button is measured and rendered again each frame.
private struct ButtonGrid: View {
    let config: StressConfig
    let count: Int
    var live = false
    @Environment(StressClock.self) private var clock

    var body: some View {
        let tick = live ? clock.tick : 0
        let lines = (count + 9) / 10
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.controls.heading", "buttons", count)).bold()
            TickLine(seed: config.seed)
            Divider()
            ForEach(0..<lines, id: \.self) { line in
                ButtonLine(first: line * 10, end: min(count, line * 10 + 10), tick: tick)
            }
        }
    }
}

/// A line that moves with the tick, so the page draws a new frame each time.
private struct TickLine: View {
    let seed: UInt64
    @Environment(StressClock.self) private var clock

    var body: some View { Text(verbatim: Synth.name(mix(seed, clock.tick))) }
}

/// The buttons `first..<end`, the same every frame unless `tick` moves.
private struct ButtonLine: View {
    let first: Int
    let end: Int
    let tick: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(first..<end, id: \.self) { index in
                Button {} label: { Text(verbatim: "B\(index &+ tick % 2)") }
            }
        }
    }
}

/// Fields bound to the page's `@FocusState` by `.focused(_:equals:)`, in a
/// scroll view inside a scroll view, the first focused: a form of editable
/// rows. Their text moves with the tick, so every row is measured and rendered
/// each frame, and the page holding the `@FocusState` evaluates its body.
private struct FocusedFields: View {
    let config: StressConfig
    @FocusState private var focus: Int?
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = 40
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.controls.heading", "focused", count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: Synth.name(mix(config.seed, tick)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<count, id: \.self) { index in
                                TextField("Name", text: .constant(Synth.name(mix(config.seed, index &+ tick))))
                                    .focused($focus, equals: index)
                            }
                        }
                    }
                    .frame(height: count)
                }
            }
        }
    }
}
