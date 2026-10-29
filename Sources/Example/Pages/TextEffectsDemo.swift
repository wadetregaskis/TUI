//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEffectsDemo.swift
//
//  Text effects drawn with `TextRenderer`: a wave of capitals, a dissolve
//  through ever-smaller glyphs, a typewriter, a rainbow and an underline
//  sweeping word by word — each a few lines over the glyphs of a
//  `Text.Layout` (the owner's TEXT-EFFECTS ruling, 2026-10-28).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// The text effects, each a renderer driven by an animation timeline.
struct TextEffectsDemo: View {
    var body: some View {
        DemoSection("page.textStyles.section.effects") {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                // The sample's characters, which the renderers that change a
                // glyph's shape or find words read by each glyph's
                // `characterIndices`, as a SwiftUI renderer reads its text.
                let sample = Array(L("page.textStyles.effectSample"))
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.textStyles.effectsExplain").foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        // Rows above and below for the ripple's crests and troughs.
                        effect("page.textStyles.effect.ripple", Ripple(time: time))
                            .padding(.vertical, Ripple.reach)
                        effect("page.textStyles.effect.wave", CapitalsWave(time: time, text: sample))
                        effect("page.textStyles.effect.dissolve", Dissolve(time: time))
                        effect("page.textStyles.effect.shrink", Shrink(time: time, text: sample))
                        effect("page.textStyles.effect.typewriter", Typewriter(time: time))
                        effect("page.textStyles.effect.rainbow", Rainbow(time: time))
                        // Rows for the rain to fall through, above the text and below.
                        effect("page.textStyles.effect.matrix", MatrixRain(time: time))
                            .padding(.top, MatrixRain.above).padding(.bottom, MatrixRain.below)
                        effect("page.textStyles.effect.congeal", MatrixArrival(time: time))
                            .padding(.top, MatrixRain.above)
                        effect("page.textStyles.effect.sweepChars", LetterSweep(time: time))
                        effect("page.textStyles.effect.sweep", WordGlide(time: time, text: sample))
                    }
                    .indentedExamples()
                }
            }
        }
    }

    /// An effect's name, and the sample drawn by it.
    private func effect(_ name: LocalizedStringKey, _ renderer: some TextRenderer) -> some View {
        HStack(spacing: 2) {
            Text(name).foregroundStyle(.palette.foregroundSecondary).frame(width: 24, alignment: .leading)
            Text("page.textStyles.effectSample").foregroundStyle(.palette.accent).textRenderer(renderer)
        }
    }
}

// MARK: - The effects

/// Every glyph of `layout`, in reading order, numbered.
func glyphs(of layout: Text.Layout) -> [(index: Int, glyph: Text.Layout.RunSlice)] {
    var all: [(index: Int, glyph: Text.Layout.RunSlice)] = []
    for line in layout {
        for run in line {
            for glyph in run { all.append((all.count, glyph)) }
        }
    }
    return all
}

/// A ripple running along the text: each glyph lifted or lowered by a sine of
/// its place and the time, up to ``reach`` rows either way.
private struct Ripple: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// The rows a glyph moves up or down at most.
    static let reach = 2

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for (index, glyph) in glyphs(of: layout) {
            let lift = (Double(Self.reach) * sin(Double(index) * 0.35 - time * 4)).rounded()
            var moved = ctx
            moved.translateBy(x: 0, y: lift)
            moved.draw(glyph)
        }
    }
}

/// A "Mexican wave" of capitals travelling along the text, in place.
private struct CapitalsWave: TextRenderer {
    var time: Double
    let text: [Character]
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for (index, glyph) in glyphs(of: layout) {
            let crest = sin(Double(index) * 0.45 - time * 5)
            guard crest > 0.8, let letter = character(of: glyph, in: text, layout: layout) else {
                ctx.draw(glyph)
                continue
            }
            ctx.drawSubstituting(Character(letter.uppercased()), for: glyph)
        }
    }
}

/// From the end, each glyph steps through ever-smaller blocks to nothing,
/// then the next; then the text comes back.
private struct Dissolve: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    private static let steps: [Character] = ["▓", "▒", "░", "·"]

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = glyphs(of: layout)
        // Ten steps a second; a cycle dissolves every glyph and holds.
        let stepsPerGlyph = Self.steps.count + 1
        let cycle = Double(all.count * 2 + 10)
        let elapsed = Int((time * 10).truncatingRemainder(dividingBy: cycle))
        for (index, glyph) in all {
            // How far this glyph is into its dissolve, counted from the end.
            let stage = elapsed - (all.count - 1 - index) * 2
            if stage <= 0 {
                ctx.draw(glyph)
            } else if stage < stepsPerGlyph {
                ctx.drawSubstituting(Self.steps[stage - 1], for: glyph)
            }
        }
    }
}

/// From the end, each glyph steps down through ever-smaller glyphs to
/// nothing, then the next; then the text comes back. The steps are a short
/// ramp by ink — a letter's lowercase, where it differs, then `+`, `-` and
/// `.` — as the image glyph ramps step by ink, which every font draws alike.
private struct Shrink: TextRenderer {
    var time: Double
    let text: [Character]
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    private static let ramp: [Character] = ["+", "-", "."]

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = glyphs(of: layout)
        let cycle = Double(all.count * 2 + 12)
        let elapsed = Int((time * 10).truncatingRemainder(dividingBy: cycle))
        for (index, glyph) in all {
            let stage = elapsed - (all.count - 1 - index) * 2
            guard stage > 0 else {
                ctx.draw(glyph)
                continue
            }
            // A blank has nothing to shrink, and goes at once.
            guard let letter = character(of: glyph, in: text, layout: layout), !letter.isWhitespace else { continue }
            var steps: [Character] = []
            if let lower = letter.lowercased().first, lower != letter { steps.append(lower) }
            steps += Self.ramp
            if stage <= steps.count { ctx.drawSubstituting(steps[stage - 1], for: glyph) }
        }
    }
}

/// The text typed out a glyph at a time, a blinking cursor after it.
private struct Typewriter: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = glyphs(of: layout)
        let cycle = Double(all.count + 15)
        let typed = Int((time * 12).truncatingRemainder(dividingBy: cycle))
        let cursorOn = Int(time * 2).isMultiple(of: 2)
        for (index, glyph) in all {
            if index < typed {
                ctx.draw(glyph)
            } else if index == typed, cursorOn {
                ctx.drawSubstituting("▏", for: glyph)
            }
        }
    }
}

/// Each glyph's colour turned round the colour wheel by its place and the
/// time.
private struct Rainbow: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for (index, glyph) in glyphs(of: layout) {
            var tinted = ctx
            tinted.addFilter(.hueRotation(.degrees(Double(index) * 18 + time * 120)))
            tinted.draw(glyph)
        }
    }
}

/// The character a glyph starts at in `text`, the text it was laid out from,
/// or `nil` past its end: its character index's distance from the layout's
/// first, which is the text's first character.
func character(of glyph: Text.Layout.RunSlice, in text: [Character], layout: Text.Layout) -> Character? {
    guard let index = glyph.characterIndices.first,
        let first = layout.first?.first?.characterIndices.first
    else { return nil }
    let offset = first.distance(to: index)
    return text.indices.contains(offset) ? text[offset] : nil
}
