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

/// Five text effects, each a renderer driven by an animation timeline.
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
                        effect("page.textStyles.effect.wave", Wave(time: time, text: sample))
                        effect("page.textStyles.effect.dissolve", Dissolve(time: time))
                        effect("page.textStyles.effect.typewriter", Typewriter(time: time))
                        effect("page.textStyles.effect.rainbow", Rainbow(time: time))
                        effect("page.textStyles.effect.sweep", UnderlineSweep(time: time, text: sample))
                    }
                    .indentedExamples()
                }
                // A row above each effect for the wave's crest to rise into.
                .padding(.top, 1)
            }
        }
    }

    /// An effect's name, and the sample drawn by it.
    private func effect(_ name: LocalizedStringKey, _ renderer: some TextRenderer) -> some View {
        HStack(spacing: 2) {
            Text(name).foregroundStyle(.palette.foregroundSecondary).frame(width: 16, alignment: .leading)
            Text("page.textStyles.effectSample").foregroundStyle(.palette.accent).textRenderer(renderer)
        }
    }
}

// MARK: - The effects

/// Every glyph of `layout`, in reading order, numbered.
private func glyphs(of layout: Text.Layout) -> [(index: Int, glyph: Text.Layout.RunSlice)] {
    var all: [(index: Int, glyph: Text.Layout.RunSlice)] = []
    for line in layout {
        for run in line {
            for glyph in run { all.append((all.count, glyph)) }
        }
    }
    return all
}

/// A "Mexican wave": capitals travel along the text, each lifted a row
/// where the wave's crest passes.
private struct Wave: TextRenderer {
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
            var lifted = ctx
            lifted.translateBy(x: 0, y: -1)
            lifted.drawSubstituting(Character(letter.uppercased()), for: glyph)
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

/// An underline drawn along the text a word at a time, then taken back.
private struct UnderlineSweep: TextRenderer {
    var time: Double
    let text: [Character]
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let all = glyphs(of: layout)
        // Which word each glyph is in: words are split by blanks.
        var words: [Int] = []
        var word = 0
        for (_, glyph) in all {
            if character(of: glyph, in: text, layout: layout)?.isWhitespace == true { word += 1 }
            words.append(word)
        }
        let count = word + 1
        // Out and back, a word every half second.
        let step = Int(time * 2) % (count * 2)
        let reached = step < count ? step + 1 : count * 2 - step - 1
        for (index, glyph) in all {
            var swept = ctx
            swept.textAttributes.underline = words[index] < reached
            swept.draw(glyph)
        }
    }
}

/// The character a glyph starts at in `text`, the text it was laid out from,
/// or `nil` past its end: its character index's distance from the layout's
/// first, which is the text's first character.
private func character(of glyph: Text.Layout.RunSlice, in text: [Character], layout: Text.Layout) -> Character? {
    guard let index = glyph.characterIndices.first,
        let first = layout.first?.first?.characterIndices.first
    else { return nil }
    let offset = first.distance(to: index)
    return text.indices.contains(offset) ? text[offset] : nil
}
