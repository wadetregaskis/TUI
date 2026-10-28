//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEffects.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

// MARK: - Text Effects

/// Many lines of text drawn by `TextRenderer`s whose time moves every frame:
/// glyphs lifted and replaced, tinted, faded and underlined, beside lines drawn
/// plainly. Stresses the renderer path: building a text's layout from its
/// drawing, the context's per-glyph writes and the canvas it emits, none of it
/// memoizable while the time moves.
enum TextEffectsScenario {
    @MainActor
    static let descriptor = Scenario(
        id: "texteffects",
        title: "Text Effects",
        blurb: "N lines drawn by text renderers that change every frame.",
        stresses: "text layout from drawing · per-glyph drawing · canvas emission",
        make: { config in AnyView(TextEffectsView(config: config)) }
    )
}

private struct TextEffectsView: View {
    let config: StressConfig
    private let lines: [String]

    /// The harness's own frame counter: every frame moves every effect,
    /// deterministically.
    @Environment(StressClock.self) private var clock

    init(config: StressConfig) {
        self.config = config
        lines = (0..<config.sized(120)).map { Synth.sentence(mix(config.seed, $0), words: 6) }
    }

    var body: some View {
        let time = Double(clock.tick) / 10
        return VStack(alignment: .leading, spacing: 0) {
            Text(Lf("stress.scenario.texteffects.heading", lines.count)).bold()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<lines.count, id: \.self) { index in
                        line(index, time: time)
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func line(_ index: Int, time: Double) -> some View {
        let text = Text(verbatim: lines[index])
        switch index % 5 {
        case 0: text.textRenderer(StressWave(time: time))
        case 1: text.textRenderer(StressTint(time: time))
        case 2: text.textRenderer(StressDissolve(time: time))
        case 3: text.textRenderer(StressSweep(time: time))
        default: text
        }
    }
}

/// Every glyph of a layout, numbered in reading order.
private func numberedGlyphs(_ layout: Text.Layout) -> [(Int, Text.Layout.RunSlice)] {
    var all: [(Int, Text.Layout.RunSlice)] = []
    for line in layout {
        for run in line {
            for glyph in run { all.append((all.count, glyph)) }
        }
    }
    return all
}

private struct StressWave: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for (index, glyph) in numberedGlyphs(layout) {
            var copy = ctx
            if sin(Double(index) * 0.45 - time) > 0.8 { copy.translateBy(x: 0, y: -1) }
            copy.draw(glyph)
        }
    }
}

private struct StressTint: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for (index, glyph) in numberedGlyphs(layout) {
            var copy = ctx
            copy.addFilter(.hueRotation(.degrees(Double(index) * 18 + time * 120)))
            copy.opacity = 0.5 + 0.5 * sin(Double(index) * 0.3 + time)
            copy.draw(glyph)
        }
    }
}

private struct StressDissolve: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    private static let steps: [Character] = ["▓", "▒", "░", "·"]

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = numberedGlyphs(layout)
        let reached = Int(time * 4) % (all.count + Self.steps.count + 1)
        for (index, glyph) in all {
            let stage = reached - index
            if stage <= 0 {
                ctx.draw(glyph)
            } else if stage <= Self.steps.count {
                ctx.drawSubstituting(Self.steps[stage - 1], for: glyph)
            }
        }
    }
}

private struct StressSweep: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = numberedGlyphs(layout)
        let reached = Int(time * 6) % max(1, all.count)
        for (index, glyph) in all {
            var copy = ctx
            copy.textAttributes.underline = index < reached
            copy.textAttributes.bold = index == reached
            copy.draw(glyph)
        }
    }
}
