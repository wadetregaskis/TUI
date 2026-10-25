//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MixerClip.swift
//
//  `mixer`: the README's hero, the code beside it and this its result — a
//  slider dragged up and down by the script, and the gauge following it,
//  turning from green through yellow to red as it climbs.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let mixerClip = Clip(
    id: "mixer",
    title: "Mixer",
    columns: 24,
    rows: 10,
    output: 720,
    script: mixerScript(),
    run: { await MixerApp.main() }
)

/// Up to the top in single steps, a sweep, down to near nothing, and back to
/// where it started, so the loop has no seam.
private func mixerScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: -0.45, y: 1.5, width: 26.9, height: 8)), .wait(0.7)]
    script += Step.repeat(.right, 60, interval: 0.045)      // 0.40 → 1.00
    script += [.wait(0.8)]
    script += Step.repeat(.left, 85, interval: 0.03)        // 1.00 → 0.15
    script += [.wait(0.7)]
    script += Step.repeat(.right, 25, interval: 0.06)       // 0.15 → 0.40
    script += [.wait(0.9)]
    return script
}

struct MixerApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Mixer") {
            Mixer()
                .palette(LiveTerminalPalette())
        }
    }
}

// The code the README shows beside the clip, as it runs. It differs from the
// README's first draft in two places. TUIkit's `tint` takes a `Color`, not
// SwiftUI's any `ShapeStyle`, so there is no `.tint(Gradient(…))`: the colour
// is picked from the level instead. And the gauge is the capacity ring with
// its value in it: TUIkit's `.accessoryCircular` lights a single cell of its
// ring, which at this size reads as a box rather than a gauge.
struct Mixer: View {
    @State var level = 0.4
    var body: some View {
        VStack {
            Gauge(value: level) {
                Text("Level")
            } currentValueLabel: {
                Text(level, format: .percent.precision(.fractionLength(0)))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(level < 0.6 ? .green : level < 0.85 ? .yellow : .red)
            Slider(value: $level)
        }
        .animation(.spring, value: level)
    }
}
