//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext.swift
//
//  SwiftUI's `GraphicsContext`, the part of it a `TextRenderer` draws text
//  with (the owner's TEXT-EFFECTS ruling, 2026-10-28; `TextRenderer design
//  study, O16`): opacity, a transform, colour filters, layers, and drawing a
//  text's lines, runs and glyphs — into cells. `Canvas` will draw with the
//  same context, with paths and images, later.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import TUICore

/// An immediate-mode drawing destination — mirrors SwiftUI's
/// `GraphicsContext`, as far as a text renderer draws with it.
///
/// Positions are in cells: a point is a cell across and a row down. A glyph
/// is drawn at the cell its origin lands on under the ``transform``, rounded
/// to whole cells — a cell cannot hold part of a glyph — and at its own size
/// and angle whatever the transform scales or turns, since a glyph cannot be
/// scaled or rotated either. Colours are faded and filtered cell by cell, as
/// `View.opacity(_:)` and the colour-effect modifiers fade and filter them.
///
/// A value: copying a context copies its state (opacity, transform, filters),
/// and both copies draw into the same destination, as SwiftUI's do.
public struct GraphicsContext {
    /// Where the drawing goes.
    let canvas: Canvas

    /// The opacity of what is drawn next, 0 to 1 — composited as
    /// `View.opacity(_:)` composites, over whatever is beneath the cell.
    public var opacity: Double = 1

    /// The transform from the drawing's coordinates to the text's cells.
    /// Only where a glyph's origin lands is honoured; see the type's note.
    public var transform = CGAffineTransform.identity

    /// The colour filters what is drawn next is drawn through, in the order
    /// they were added.
    var filters: [Filter] = []

    /// The cell attributes the next draws use in place of each run's own — a
    /// TUI addition: a terminal draws bold, italic, underline and the rest
    /// per cell, so an effect can sweep them along a text by character or by
    /// word. A `nil` field keeps the run's.
    public var textAttributes = TextCellAttributes()

    init(canvas: Canvas) {
        self.canvas = canvas
    }

    // MARK: Transforming

    /// Moves the drawing's origin by `x` columns and `y` rows — mirrors
    /// SwiftUI's `translateBy(x:y:)`.
    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        transform = CGAffineTransform(translationX: x, y: y).concatenating(transform)
    }

    /// Scales the drawing's coordinates — mirrors SwiftUI's
    /// `scaleBy(x:y:)`. Moves where glyphs are drawn; a glyph keeps its size.
    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        transform = CGAffineTransform(scaleX: x, y: y).concatenating(transform)
    }

    /// Appends `matrix` to the transform — mirrors SwiftUI's `concatenate(_:)`.
    /// Moves where glyphs are drawn; a glyph keeps its size and angle.
    public mutating func concatenate(_ matrix: CGAffineTransform) {
        transform = matrix.concatenating(transform)
    }

    /// Rotates the drawing's coordinates — mirrors SwiftUI's
    /// `rotate(by:)`. Moves where glyphs are drawn; a glyph keeps its angle.
    public mutating func rotate(by angle: Angle) {
        transform = CGAffineTransform(rotationAngle: CGFloat(angle.radians)).concatenating(transform)
    }

    // MARK: Filters

    /// A colour filter — mirrors SwiftUI's `GraphicsContext.Filter`, the
    /// filters a cell's colours can take. Blurs, shaders and projections,
    /// which need pixels, are not offered.
    public struct Filter: Sendable {
        enum Kind: Sendable {
            case multiply(Color)
            case hueRotation(Double)
            case saturation(Double)
            case brightness(Double)
            case contrast(Double)
            case invert(Double)
            case grayscale(Double)
        }

        let kind: Kind

        /// Multiplies each colour by `color`, channel by channel.
        public static func colorMultiply(_ color: Color) -> Self { Self(kind: .multiply(color)) }
        /// Turns each colour's hue by `angle`.
        public static func hueRotation(_ angle: Angle) -> Self { Self(kind: .hueRotation(angle.degrees)) }
        /// Keeps `amount` of each colour's saturation (above 1 adds).
        public static func saturation(_ amount: Double) -> Self { Self(kind: .saturation(amount)) }
        /// Adds `amount` of the full range to each channel.
        public static func brightness(_ amount: Double) -> Self { Self(kind: .brightness(amount)) }
        /// Scales each channel's distance from the middle grey by `amount`.
        public static func contrast(_ amount: Double) -> Self { Self(kind: .contrast(amount)) }
        /// Inverts each colour, `amount` of the way.
        public static func colorInvert(_ amount: Double = 1) -> Self { Self(kind: .invert(amount)) }
        /// Takes `amount` of each colour's colour out, toward its grey.
        public static func grayscale(_ amount: Double) -> Self { Self(kind: .grayscale(amount)) }

        /// `color` through this filter; itself where it has no RGB.
        func applied(to color: Color) -> Color {
            switch kind {
            case .multiply(let tint): color.multiplied(by: tint)
            case .hueRotation(let degrees): color.hueRotated(byDegrees: degrees)
            case .saturation(let amount): color.saturated(keeping: amount)
            case .brightness(let amount): color.brightened(by: amount)
            case .contrast(let amount): color.contrasted(by: amount)
            case .invert(let amount): Color.lerp(color, color.inverted, phase: amount)
            case .grayscale(let amount): color.saturated(keeping: 1 - amount)
            }
        }
    }

    /// Options for a filter — mirrors SwiftUI's `GraphicsContext.FilterOptions`.
    /// None changes how a cell's colours are filtered.
    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
    }

    /// Adds `filter` to what the next draws are drawn through — mirrors
    /// SwiftUI's `addFilter(_:options:)`.
    public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) {
        filters.append(filter)
    }

    // MARK: Layers

    /// Draws `content` into a layer of this context's: what it draws takes
    /// this context's opacity, filters and transform as well as its own —
    /// mirrors SwiftUI's `drawLayer(content:)`. A cell has no layer to blend
    /// as a group beyond its own colours, so the layer composes cell by cell.
    public func drawLayer(content: (inout Self) throws -> Void) rethrows {
        var layer = self
        try content(&layer)
    }

    // MARK: Drawing text

    /// Draws a line of a text layout — mirrors SwiftUI's `draw(_:options:)`.
    public func draw(_ line: Text.Layout.Line, options: Text.Layout.DrawingOptions = .init()) {
        for run in line { draw(run, options: options) }
    }

    /// Draws a run of a text layout — mirrors SwiftUI's `draw(_:options:)`.
    public func draw(_ run: Text.Layout.Run, options: Text.Layout.DrawingOptions = .init()) {
        draw(run[run.startIndex..<run.endIndex], options: options)
    }

    /// Draws glyphs of a text layout — mirrors SwiftUI's `draw(_:options:)`.
    public func draw(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init()) {
        for index in slice.indices { place(slice.run.glyphs[index], as: nil, style: slice.run.style) }
    }

    /// Draws glyphs of a text layout each as `character`, in their style and
    /// at their place — a TUI addition: the terminal's way to change a glyph's
    /// shape, which SwiftUI's context cannot. A dissolve through ever-smaller
    /// glyphs (`█ ▓ ▒ ░ ·`), a typewriter's cursor, a scramble.
    ///
    /// Named apart from SwiftUI's `draw` methods, as a TUI addition beside them.
    public func drawSubstituting(
        _ character: Character, for slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init()
    ) {
        for index in slice.indices { place(slice.run.glyphs[index], as: character, style: slice.run.style) }
    }

    /// Writes one glyph to the canvas under this context's state.
    private func place(_ glyph: Text.Layout.Glyph, as character: Character?, style: SGRState) {
        let origin = CGPoint(x: CGFloat(glyph.column), y: CGFloat(glyph.row)).applying(transform)
        guard origin.x.isFinite, origin.y.isFinite else { return }
        let shown = character.map(String.init) ?? glyph.character
        canvas.write(
            Canvas.Cell(
                character: shown, width: character.map { max(1, $0.terminalWidth) } ?? glyph.width,
                style: textAttributes.applied(to: filtered(style)), opacity: opacity),
            column: Int(origin.x.rounded()), row: Int(origin.y.rounded()))
    }

    /// `style` with its RGB colours through the filters.
    private func filtered(_ style: SGRState) -> SGRState {
        guard !filters.isEmpty else { return style }
        var style = style
        func through(_ colour: SGRState.Colour?) -> SGRState.Colour? {
            // A pattern reading the channels, not a colour this draws with.
            // swiftlint:disable:next framework_colour_literal
            guard case .rgb(let red, let green, let blue)? = colour else { return colour }
            // The cell's own colour, filtered: content, not a framework ink.
            // swiftlint:disable:next framework_colour_literal
            var color = Color.rgb(UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue))
            for filter in filters { color = filter.applied(to: color) }
            guard let rgb = color.rgbComponents else { return colour }
            // The filtered colour's channels, restated: content, not an ink.
            // swiftlint:disable:next framework_colour_literal
            return .rgb(Int(rgb.red), Int(rgb.green), Int(rgb.blue))
        }
        style.setForeground(through(style.foregroundColour))
        style.setBackground(through(style.backgroundColour))
        return style
    }
}

/// The cell attributes a ``GraphicsContext`` draws glyphs with in place of
/// their runs' own — a TUI addition (``GraphicsContext/textAttributes``). A
/// `nil` field keeps the run's.
public struct TextCellAttributes: Equatable, Sendable {
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var dim: Bool?
    public var blink: Bool?
    public var inverse: Bool?

    public init(
        bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil,
        dim: Bool? = nil, blink: Bool? = nil, inverse: Bool? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.dim = dim
        self.blink = blink
        self.inverse = inverse
    }

    /// `style` with these attributes stated over its own.
    func applied(to style: SGRState) -> SGRState {
        guard self != Self() else { return style }
        var style = style
        // Bold and faint share their off code (22), so both are restated
        // after it: each as stated here, else as the run had it.
        if bold != nil || dim != nil {
            let isBold = bold ?? style.isBold
            let isDim = dim ?? style.isFaint
            style.apply("\u{1B}[22m")
            if isBold { style.apply("\u{1B}[1m") }
            if isDim { style.apply("\u{1B}[2m") }
        }
        func set(_ value: Bool?, on: Int, off: Int) {
            guard let value else { return }
            style.apply("\u{1B}[\(value ? on : off)m")
        }
        set(italic, on: 3, off: 23)
        set(underline, on: 4, off: 24)
        set(blink, on: 5, off: 25)
        set(inverse, on: 7, off: 27)
        set(strikethrough, on: 9, off: 29)
        return style
    }
}

// MARK: - The canvas

extension GraphicsContext {
    /// The cells a context draws into, shared by its copies: each written
    /// cell, the last write to a cell winning, as later drawing covers
    /// earlier.
    final class Canvas {
        struct Cell: Equatable {
            var character: String
            var width: Int
            var style: SGRState
            var opacity: Double
        }

        /// Row → column → cell.
        private(set) var rows: [Int: [Int: Cell]] = [:]

        func write(_ cell: Cell, column: Int, row: Int) {
            guard cell.opacity > 0 else { return }
            var line = rows[row] ?? [:]
            // A wide glyph covers the cell after it, and a glyph written over
            // either half of a wide one removes it.
            if let before = line[column - 1], before.width > 1 { line[column - 1] = nil }
            for covered in column..<(column + cell.width) where covered != column { line[covered] = nil }
            line[column] = cell
            rows[row] = line
        }

        /// The extent drawn: the smallest rectangle holding every cell
        /// written and the text's own frame, `width` × `height` at the origin.
        func extent(including width: Int, _ height: Int) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            var extent = (minX: 0, minY: 0, maxX: width, maxY: height)
            for (row, line) in rows {
                for (column, cell) in line {
                    extent.minX = min(extent.minX, column)
                    extent.maxX = max(extent.maxX, column + cell.width)
                    extent.minY = min(extent.minY, row)
                    extent.maxY = max(extent.maxY, row + 1)
                }
            }
            return extent
        }

        /// The cells as a buffer covering `extent`, its top-left the
        /// extent's, with the fade each cell was drawn at claimed for the
        /// compositor (`OpacityRegion`), and a cell nothing was drawn in left
        /// blank: what is beneath shows there.
        func buffer(covering extent: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> FrameBuffer {
            var lines: [String] = []
            var widths: [Int] = []
            var claims: [OpacityRegion] = []
            for row in extent.minY..<extent.maxY {
                var line = ""
                var state = SGRState()
                var column = extent.minX
                var drawnWidth = 0
                let cells = rows[row] ?? [:]
                while column < extent.maxX {
                    guard let cell = cells[column] else {
                        if !state.isDefault {
                            line += "\u{1B}[0m"
                            state = SGRState()
                        }
                        line += " "
                        column += 1
                        continue
                    }
                    line += cell.style.rendered(changingFrom: state)
                    state = cell.style
                    line += cell.character
                    if cell.opacity < 1 {
                        claims.append(
                            OpacityRegion(
                                offsetX: column - extent.minX, offsetY: row - extent.minY, width: cell.width, height: 1,
                                opacity: cell.opacity))
                    }
                    column += cell.width
                    drawnWidth = column - extent.minX
                }
                if !state.isDefault { line += "\u{1B}[0m" }
                lines.append(line)
                widths.append(max(drawnWidth, extent.maxX - extent.minX))
            }
            var buffer = FrameBuffer(lines: lines, width: extent.maxX - extent.minX, lineWidths: widths)
            buffer.opacityRegions = claims
            return buffer
        }
    }
}
