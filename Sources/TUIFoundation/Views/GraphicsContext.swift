//  🖥️ TUI — A Terminal UI framework for Swift
//  GraphicsContext.swift
//
//  SwiftUI's `GraphicsContext`: its state (opacity, a transform, a blend mode,
//  filters, a clip) and drawing a text's lines, runs and glyphs, which is what
//  a `TextRenderer` draws with (the owner's TEXT-EFFECTS ruling, 2026-10-28;
//  `TextRenderer design study, O16`). `Canvas` draws with the same context;
//  paths and shadings, images and symbols, and filters are in the extensions
//  beside this file.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import TUICore

/// An immediate-mode drawing destination — mirrors SwiftUI's
/// `GraphicsContext`.
///
/// **Units.** In a ``Canvas`` a position is in the square units a ``Shape``'s
/// is: a column across, and ``EnvironmentValues/imageCellAspect`` of them, about
/// two, down a row, so a circle is round. In a ``TextRenderer`` a position is in
/// cells, a cell across and a row down, as its ``Text/Layout`` is.
///
/// **Paths, images and shadings** paint pixels at the finest grain the terminal
/// offers (``CanvasGrain``), honouring the whole transform. **Text and symbols**
/// are cells: a glyph is drawn at the cell its origin lands on under the
/// ``transform``, rounded to whole cells — a cell cannot hold part of a glyph —
/// and at its own size and angle whatever the transform scales or turns, since a
/// glyph cannot be scaled or rotated either. Its colours are faded and filtered
/// cell by cell, as `View.opacity(_:)` and the colour-effect modifiers fade and
/// filter them. A shape painted over at least half of a glyph's cell covers the
/// glyph; a glyph drawn over pixels takes them as its field.
///
/// A value: copying a context copies its state (opacity, transform, filters,
/// clip), and both copies draw into the same destination, as SwiftUI's do.
public struct GraphicsContext {
    /// Where the drawing goes.
    let surface: Surface

    /// The layer paths and images paint into: `nil` for the surface's own
    /// pixels. See ``drawLayer(content:)``.
    var layer: CanvasRaster?

    /// The serial the layer began at: what it covers when it lands is older.
    var layerStart = 0

    /// The clip in force, or `nil` for the whole surface.
    var clipMask: CanvasMask?

    /// The opacity and filters of the contexts this one's layer is inside,
    /// which a glyph, drawn straight into its cell, takes at once.
    var enclosing = (opacity: 1.0, filters: [Filter]())

    /// How what is drawn next combines with what it lands on.
    public var blendMode = BlendMode.normal

    /// The opacity of what is drawn next, 0 to 1 — composited as
    /// `View.opacity(_:)` composites, over whatever is beneath the cell.
    public var opacity: Double = 1

    /// The transform from the drawing's coordinates to the canvas's or the
    /// text's. Of a glyph, only where its origin lands is honoured; see the
    /// type's note.
    public var transform = CGAffineTransform.identity

    /// The colour filters what is drawn next is drawn through, in the order
    /// they were added.
    var filters: [Filter] = []

    /// The cell attributes the next draws use in place of each run's own — a
    /// TUI addition: a terminal draws bold, italic, underline and the rest
    /// per cell, so an effect can sweep them along a text by character or by
    /// word. A `nil` field keeps the run's.
    public var textAttributes = TextCellAttributes()

    init(surface: Surface) {
        self.surface = surface
    }

    /// The environment of the view this context draws — mirrors SwiftUI's
    /// `environment`.
    public var environment: EnvironmentValues { surface.environment }

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
        let shown = character.map(String.init) ?? glyph.character
        let origin = CGPoint(x: CGFloat(glyph.column), y: CGFloat(glyph.row) * surface.unitsPerRow)
        writeGlyph(
            shown, width: character.map { max(1, $0.terminalWidth) } ?? glyph.width, style: style,
            atCellOf: origin.applying(transform))
    }

    /// Writes one glyph to the cell `origin`, in this context's units past its
    /// transform, lands on, under this context's state.
    func writeGlyph(_ character: String, width: Int, style: SGRState, atCellOf origin: CGPoint) {
        let cell = CGPoint(x: origin.x, y: origin.y / surface.unitsPerRow)
        // Within the surface's reach, which also keeps `Int(_:)` from trapping
        // on a huge or non-finite coordinate (NaN fails both comparisons).
        guard surface.reaches(cell) else { return }
        writeGlyph(character, width: width, style: style, column: Int(cell.x.rounded()), row: Int(cell.y.rounded()))
    }

    /// Writes one glyph to cell (`column`, `row`) under this context's state.
    func writeGlyph(_ character: String, width: Int, style: SGRState, column: Int, row: Int) {
        guard clipKeeps(column: column, row: row) else { return }
        surface.write(
            Surface.Cell(
                character: character, width: width, style: textAttributes.applied(to: filtered(style, for: character)),
                opacity: opacity * enclosing.opacity, serial: surface.nextSerial()),
            column: column, row: row)
    }

    /// Whether the clip keeps at least half of a cell, which is all of it or
    /// none: a glyph cannot be cut.
    private func clipKeeps(column: Int, row: Int) -> Bool {
        guard let clipMask else { return true }
        let grid = surface.grid
        guard column >= 0, row >= 0, (column + 1) * grid.across <= clipMask.width, (row + 1) * grid.down <= clipMask.height
        else { return false }
        return clipMask.meanShare(column: column, row: row, across: grid.across, down: grid.down) >= 0.5
    }

    /// `style` with its colours through the filters.
    private func filtered(_ style: SGRState, for character: String? = nil) -> SGRState {
        guard !filters.isEmpty || !enclosing.filters.isEmpty else { return style }
        var style = style
        func colour(_ raw: SGRState.Colour?, background: Bool) -> Color? {
            // A pattern reading the channels, not a colour this draws with.
            // swiftlint:disable framework_colour_literal
            switch raw {
            case .rgb(let red, let green, let blue):
                return Color.rgb(UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue))
            case .indexed(let index):
                return UInt8(exactly: index).map(Color.palette256)
            case .named(let code):
                let base = background ? 40 : 30
                let isBright = code >= 90
                let slot = code - (isBright ? base + 60 : base)
                return SGRColorRewrite.basicColor(base: slot, isBright: isBright)
            case nil:
                guard !background else { return nil }
                let resolved = surface.environment.palette.foreground.resolve(with: surface.environment.palette)
                if case .terminalDefault = resolved.value { return .terminalForeground }
                return resolved
            }
            // swiftlint:enable framework_colour_literal
        }
        func through(_ color: Color) -> Color {
            var color = color
            for filter in filters + enclosing.filters { color = filter.applied(to: color) }
            return color
        }
        if let foreground = colour(style.foregroundColour, background: false) {
            let filtered = through(foreground)
            if style.foregroundColour != nil || filtered != foreground {
                style = style.settingForeground(filtered)
            }
        }
        if let background = colour(style.backgroundColour, background: true) {
            style = style.settingBackground(through(background))
        }
        // Only an underline colour the run states: one it leaves unset is the
        // text's colour, filtered above, and resolving it here made it the
        // palette's foreground instead (or, from the terminal's own, SGR 39
        // written as 58:5:9, a red underline).
        if character?.unicodeScalars.first != .terminalImagePlaceholder, style.underlineColour != nil,
            let underline = colour(style.underlineColour, background: false)
        {
            style = style.settingUnderlineColour(through(underline))
        }
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
