//  🖥️ TUI — A Terminal UI framework for Swift
//  TextEffectsDemo+Matrix.swift
//
//  Two "Matrix" text effects: rain falling through the text, which brightens
//  each glyph it crosses and never changes it, and rain falling into place as
//  the text (the owner's afternoon list, 2026-10-28, #5.3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// What the rain is drawn with: half-width katakana and digits, one cell each,
/// as the film's rain is.
private let rainGlyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789")

/// The rain glyph at `column` and `row` at `step`: changing as it falls, the
/// same for the same three, so a frame drawn twice draws alike.
private func rainGlyph(column: Int, row: Int, step: Int) -> Character {
    var hash = UInt64(bitPattern: Int64(column &* 7919 &+ row &* 104_729 &+ step &* 1_299_709))
    hash ^= hash >> 33
    hash &*= 0xff51_afd7_ed55_8ccd
    hash ^= hash >> 33
    return rainGlyphs[Int(hash % UInt64(rainGlyphs.count))]
}

/// A drop's cell at `row` rows from the text, `fade` of the way down its trail
/// (0 its head, nearly 1 its tail): green, the head nearly white.
private func drawDrop(
    _ character: Character, for glyph: Text.Layout.RunSlice, row: Int, fade: Double, in ctx: GraphicsContext
) {
    var drop = ctx
    drop.translateBy(x: 0, y: CGFloat(row))
    drop.opacity = 1 - fade * 0.8
    // Whatever the text's colour: white, then tinted.
    drop.addFilter(.brightness(1))
    drop.addFilter(.colorMultiply(fade == 0 ? .rgb(210, 255, 210) : .rgb(60, 230, 90)))
    drop.drawSubstituting(character, for: glyph)
}

/// Rain falling down every column of the text and the rows around it, over
/// and over. The text stays as it is; a glyph is drawn bold while a drop
/// passes over it.
struct MatrixRain: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// The rows the rain falls through above the text, and below it.
    static let above = 3
    static let below = 1

    /// The cells a drop's trail takes, its head included.
    static let trail = 3

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // A drop runs from above the top to past the bottom, then waits a few
        // rows' time before falling again.
        let path = Self.above + 1 + Self.below + Self.trail + 4
        for (index, glyph) in glyphs(of: layout) {
            // Each column at its own speed and phase.
            let speed = 5 + Double((index * 7) % 5)
            let fallen = time * speed + Double((index * 13) % 17)
            let head = Int(fallen.truncatingRemainder(dividingBy: Double(path))) - Self.above
            let step = Int(fallen)
            var base = ctx
            if head - Self.trail < 0, head >= 0 { base.textAttributes.bold = true }
            base.draw(glyph)
            for back in 0..<Self.trail {
                let row = head - back
                guard row >= -Self.above, row <= Self.below, row != 0 else { continue }
                drawDrop(
                    rainGlyph(column: index, row: row, step: step), for: glyph, row: row,
                    fade: Double(back) / Double(Self.trail), in: ctx)
            }
        }
    }
}

/// Rain falling into empty rows, each drop stopping on the text's row as its
/// glyph; then, the text whole, it holds, and begins again.
struct MatrixArrival: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    /// Seconds a cycle takes: the drops land within the first three.
    private static let cycle = 6.0

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let elapsed = time.truncatingRemainder(dividingBy: Self.cycle)
        for (index, glyph) in glyphs(of: layout) {
            // Each column's drop starts within the first two seconds, falling
            // eight rows a second.
            let start = Double((index * 37) % 17) / 17 * 2
            let fallen = (elapsed - start) * 8
            guard fallen >= 0 else { continue }
            let head = Int(fallen) - MatrixRain.above
            if head >= 0 {
                // Landed: the glyph, bold for the moment it arrives.
                var landed = ctx
                if head < 3 { landed.textAttributes.bold = true }
                landed.draw(glyph)
                continue
            }
            for back in 0..<MatrixRain.trail {
                let row = head - back
                guard row >= -MatrixRain.above else { continue }
                drawDrop(
                    rainGlyph(column: index, row: row, step: Int(fallen)), for: glyph, row: row,
                    fade: Double(back) / Double(MatrixRain.trail), in: ctx)
            }
        }
    }
}
