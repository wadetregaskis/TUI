//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext+Text.swift
//
//  Drawing resolved text and symbols: the cells their views draw, written
//  glyph by glyph under the context's state.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import TUICore
import TUIStyling
import TUIView

// MARK: - Text

extension GraphicsContext {
    /// A text prepared for drawing — mirrors SwiftUI's
    /// `GraphicsContext.ResolvedText`.
    public struct ResolvedText {
        let text: Text
        let views: CanvasViews
        let unitsPerRow: CGFloat

        /// The colour the text is drawn in. `nil` keeps what it would draw in as
        /// a view, in this context's environment.
        public var shading: Shading?

        /// The text's size, in the context's units, offered `size`.
        public func measure(in size: CGSize) -> CGSize {
            let (views, text) = (views, text)
            let (width, height) = (GraphicsContext.cellCount(size.width), GraphicsContext.cellCount(size.height / unitsPerRow))
            let cells = MainActor.assumeIsolated { views.size(of: text, width: width, height: height) }
            return CGSize(width: CGFloat(cells.width), height: CGFloat(cells.height) * unitsPerRow)
        }

        /// The first line's baseline, from the text's top: a line has no descent
        /// here (`Text.Layout`), so it is that line's bottom.
        public func firstBaseline(in size: CGSize) -> CGFloat { unitsPerRow }

        /// The last line's baseline, from the text's top: the text's bottom.
        public func lastBaseline(in size: CGSize) -> CGFloat { measure(in: size).height }
    }

    /// `text` prepared for drawing — mirrors SwiftUI's `resolve(_:)`.
    public func resolve(_ text: Text) -> ResolvedText {
        ResolvedText(text: text, views: surface.views, unitsPerRow: surface.unitsPerRow, shading: nil)
    }

    /// Draws `text` wrapped to `rect`'s width, from its top-left — mirrors
    /// SwiftUI's `draw(_:in:)`. Whatever does not fit `rect`'s height is cut.
    public func draw(_ text: ResolvedText, in rect: CGRect) {
        let shading = text.shading.map(resolve)
        let (views, words) = (surface.views, text.text)
        let (width, height) = (Self.cellCount(rect.width), Self.cellCount(rect.height / surface.unitsPerRow))
        let cells = MainActor.assumeIsolated { views.cells(of: words, shading: shading, width: width, height: height) }
        stamp(cells, atCellOf: rect.origin.applying(transform))
    }

    /// Draws `text` at its own size, unwrapped, `anchor` of it at `point` —
    /// mirrors SwiftUI's `draw(_:at:anchor:)`.
    public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        let shading = text.shading.map(resolve)
        let (views, words) = (surface.views, text.text)
        let cells = MainActor.assumeIsolated {
            let size = views.size(of: words, width: nil, height: nil)
            return views.cells(of: words, shading: shading, width: size.width, height: size.height)
        }
        let size = CGSize(width: CGFloat(cells.width), height: CGFloat(cells.lines.count) * surface.unitsPerRow)
        stamp(cells, atCellOf: Self.rect(of: size, at: point, anchor: anchor).origin.applying(transform))
    }

    /// Draws `text` in `rect` — mirrors SwiftUI's `draw(_:in:)`.
    public func draw(_ text: Text, in rect: CGRect) {
        draw(resolve(text), in: rect)
    }

    /// Draws `text`, `anchor` of it at `point` — mirrors SwiftUI's `draw(_:at:anchor:)`.
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(text), at: point, anchor: anchor)
    }

    /// A length in units held to a count of cells.
    static func cellCount(_ length: CGFloat) -> Int? {
        guard length.isFinite, length >= 0, length < 1_048_576 else { return nil }
        return Int(length.rounded(.up))
    }

    func cellLength(_ length: CGFloat) -> Int { Self.cellCount(length) ?? 0 }

    // MARK: Stamping

    /// `cells`, the lines of a drawn view, written glyph by glyph from the cell
    /// `origin` lands on, under this context's state. A blank with no field of
    /// its own is not drawn, so a text's padding does not cover what is beneath
    /// it, as it would not in a `ZStack` of glyphs.
    func stamp(_ cells: FrameBuffer, atCellOf origin: CGPoint) {
        let cell = CGPoint(x: origin.x, y: origin.y / surface.unitsPerRow)
        // Held while still floats: `Int(_:)` traps on a far-off coordinate.
        guard cell.x.isFinite, cell.y.isFinite, abs(cell.x) < 1_048_576, abs(cell.y) < 1_048_576 else { return }
        let (left, top) = (Int(cell.x.rounded()), Int(cell.y.rounded()))
        for (rowOffset, line) in cells.lines.enumerated() {
            var state = SGRState()
            var column = left
            _ = line.forEachANSISegment { segment in
                switch segment {
                // A rendered line's escape, not a colour: the rule matches
                // `.ansi(` wherever it is written.
                // swiftlint:disable:next framework_colour_literal
                case .ansi(let sequence, let isSGR):
                    if isSGR { state.apply(sequence) }
                case .visible(let character):
                    let width = max(1, character.terminalWidth)
                    defer { column += width }
                    if character == " ", !state.namesBackground, !state.reversesVideo, !state.paintsInkOnBlankCell { return true }
                    let target = CGPoint(x: CGFloat(column), y: CGFloat(top + rowOffset))
                    if surface.reaches(target) {
                        writeGlyph(String(character), width: width, style: state, column: column, row: top + rowOffset)
                    }
                }
                return true
            }
        }
    }
}

// MARK: - Symbols

extension GraphicsContext {
    /// A symbol prepared for drawing — mirrors SwiftUI's
    /// `GraphicsContext.ResolvedSymbol`.
    public struct ResolvedSymbol {
        /// Which of the canvas's symbols.
        let index: Int
        /// Its cell size.
        let cells: (width: Int, height: Int)
        /// The symbol's size, in the context's units.
        public let size: CGSize
    }

    /// The symbol `.tag(id)` names among the canvas's `symbols`, or `nil` —
    /// mirrors SwiftUI's `resolveSymbol(id:)`.
    public func resolveSymbol<ID: Hashable>(id: ID) -> ResolvedSymbol? {
        guard let index = surface.symbolValues.firstIndex(where: { $0.tag(for: ID.self) == id }) else { return nil }
        let views = surface.views
        let found = MainActor.assumeIsolated { views.symbolSize(at: index) }
        return ResolvedSymbol(
            index: index, cells: (found.width, found.height),
            size: CGSize(width: CGFloat(found.width), height: CGFloat(found.height) * surface.unitsPerRow))
    }

    /// Draws `symbol` in `rect` — mirrors SwiftUI's `draw(_:in:)`. A view cannot
    /// be stretched, so it is drawn laid out in `rect`'s size, from its
    /// top-left, and takes this context's opacity and colour filters in its
    /// cells.
    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        draw(
            symbol, cellWidth: Self.cellCount(rect.width) ?? symbol.cells.width,
            cellHeight: Self.cellCount(rect.height / surface.unitsPerRow) ?? symbol.cells.height, atCellOf: rect.origin)
    }

    /// Draws `symbol` at its own size, `anchor` of it at `point` — mirrors
    /// SwiftUI's `draw(_:at:anchor:)`.
    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(
            symbol, cellWidth: symbol.cells.width, cellHeight: symbol.cells.height,
            atCellOf: Self.rect(of: symbol.size, at: point, anchor: anchor).origin)
    }

    private func draw(_ symbol: ResolvedSymbol, cellWidth: Int, cellHeight: Int, atCellOf origin: CGPoint) {
        let (views, index) = (surface.views, symbol.index)
        let cells = MainActor.assumeIsolated { views.symbolCells(at: index, width: cellWidth, height: cellHeight) }
        stamp(cells, atCellOf: origin.applying(transform))
    }
}
