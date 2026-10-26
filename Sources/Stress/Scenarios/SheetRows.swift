//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetRows.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

// MARK: - Sheet Rows

/// Rows that each hold a sheet nobody presents: what a page pays every frame
/// for the presentations it could make.
///
/// Every row changes with the tick, so each frame draws every presenter
/// again, dismissed. A dismissed sheet's content is built only when it is
/// presented, so its cost here is the presenter's own: its focus section's
/// name, the dock it posts for the root, its closed-frame bookkeeping. The
/// content is one a real sheet might hold — a `Dialog` with a form's worth of
/// rows, two buttons and two presentation traits — so that building it on
/// every frame, as sheets once did, would show.
enum SheetRowsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "sheetrows",
        title: "Sheet Rows",
        blurb: "Rows that each hold a dismissed sheet, redrawn every frame (tick-driven).",
        stresses: "dismissed presenters on every frame · the dock each posts · a sheet's content built only when presented",
        make: { config in AnyView(SheetRowsView(config: config)) }
    )
}

private struct SheetRowsView: View {
    let config: StressConfig
    @Environment(StressClock.self) private var clock

    var body: some View {
        let count = config.sized(60)
        let tick = clock.tick
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.sheetrows.heading", count)).bold()
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    // Folding `tick` into the hash makes the row differ every
                    // frame, so its presenter is drawn every frame.
                    let h = mix(config.seed, index &+ tick)
                    Text("#\(index) \(Synth.slug(h))")
                        .sheet(isPresented: .constant(false)) {
                            SheetRowsDraft(seed: mix(config.seed, index))
                        }
                }
            }
        }
    }
}

/// What each row's sheet would show.
private struct SheetRowsDraft: View {
    let seed: UInt64

    var body: some View {
        Dialog(title: Synth.name(seed)) {
            ForEach(0..<6, id: \.self) { line in
                HStack {
                    Text(Synth.slug(mix(seed, line)))
                    Spacer()
                    Text(Synth.status(mix(seed, line &+ 100)))
                }
            }
        } footer: {
            HStack {
                Button(L("stress.scenario.sheetrows.cancel")) {}
                    .keyboardShortcut(.cancelAction)
                Button(L("stress.scenario.sheetrows.save")) {}
                    .keyboardShortcut(.defaultAction)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
