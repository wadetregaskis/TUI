//  🖥️ TUI — A Terminal UI framework for Swift
//  BlockElementDrawing.swift
//
//  What the terminal draws of the Block Elements (U+2580–259F): whether they
//  reach the line's edges, and whether its font has the quadrants at all.
//
//  Created by Wade Tregaskis
//  License: MIT

/// Whether the terminal draws Block Elements glyphs the full height of the
/// line; `true` where nothing has said otherwise (headless, tests).
private struct BlockElementsFillTheLineKey: EnvironmentKey {
    static let defaultValue = true
}

/// Whether the terminal's font has the quadrants; `true` where nothing has
/// said otherwise (headless, tests).
private struct FontHasQuadrantsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the terminal draws a Block Elements glyph (U+2580–259F) the
    /// full height of its line, so that a half block meets the row above or
    /// below it. Set by the run loop from `TerminalHost`, per tmux client
    /// where there are any; read by a three-row button face, which is built
    /// of half blocks and quadrants and comes apart where they fall short.
    package var blockElementsFillTheLine: Bool {
        get { self[BlockElementsFillTheLineKey.self] }
        set { self[BlockElementsFillTheLineKey.self] = newValue }
    }

    /// Whether the terminal's font has the quadrants `▘ ▝ ▖ ▗ ▚ ▞ ▙ ▛ ▜ ▟`, so
    /// that a glyph cutting a cell in quarters draws rather than standing as a
    /// box for a glyph the font lacks. Set by the run loop: `false` only in
    /// the classic Windows console when the font it names has none, as its
    /// default, Consolas, has none (the console asked with
    /// `GetCurrentConsoleFontEx`, the font with GDI; measured 2026-11-18).
    /// Every other terminal draws them as shapes of its own, or from a font
    /// that has them.
    package var fontHasQuadrants: Bool {
        get { self[FontHasQuadrantsKey.self] }
        set { self[FontHasQuadrantsKey.self] = newValue }
    }
}

/// What the terminal draws of the Block Elements, for what is built of them:
/// a shape's fill, and a solid face.
struct BlockElementDrawing: Equatable, Sendable {
    /// Whether they reach the line's edges, so a half block meets the row
    /// above or below it (``EnvironmentValues/blockElementsFillTheLine``).
    var fillTheLine: Bool

    /// Whether the font has the quadrants (``EnvironmentValues/fontHasQuadrants``).
    var hasQuadrants: Bool

    /// Whether a quadrant draws as one: the font has it, and it reaches the
    /// line's edges. Where not, a corner is cut in whole cells, and a half
    /// block may still be drawn wherever it reaches the edges.
    var drawsQuadrants: Bool { fillTheLine && hasQuadrants }

    init(fillTheLine: Bool, hasQuadrants: Bool) {
        self.fillTheLine = fillTheLine
        self.hasQuadrants = hasQuadrants
    }

    /// What the terminal `environment` describes draws.
    init(_ environment: EnvironmentValues) {
        self.init(fillTheLine: environment.blockElementsFillTheLine, hasQuadrants: environment.fontHasQuadrants)
    }
}
