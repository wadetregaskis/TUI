//  🖥️ TUI — A Terminal UI framework for Swift
//  MaskModifier.swift
//
//  A view's cells kept where another view draws: `mask(alignment:_:)`
//  (decisions A27, ruled 2026-10-26).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Masks this view using the alpha channel of the given view.
    ///
    /// The mask is laid out in this view's frame by `alignment`, as an overlay
    /// is, and a cell of this view is kept where the mask draws and cleared,
    /// to what is behind, where it does not. A cell holds one glyph, so it is
    /// kept or not, by the rules a clip keeps:
    ///
    /// - A ``Shape`` mask keeps a cell the shape covers at least half of, as
    ///   ``View/clipShape(_:style:)`` does, so the two agree as they do in
    ///   SwiftUI.
    /// - Any other mask keeps a cell where it draws a glyph or a field, at the
    ///   alpha it draws it with: a mask of `Color.black.opacity(0.5)` keeps the
    ///   view at half strength. A space the mask leaves without a field masks
    ///   the cell out.
    /// - A glyph's alpha is its letter's shape, so where the mask draws a glyph
    ///   with no field over a cell this view only fills, the cell is the mask's
    ///   glyph in this view's colour there: a gradient masked by text is the
    ///   text in the gradient, as in SwiftUI. Where this view draws a glyph of
    ///   its own, it keeps it.
    ///
    /// ```swift
    /// LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    ///     .mask { Text("Gradient text") }
    /// ```
    ///
    /// - Parameters:
    ///   - alignment: Where the mask goes in this view's frame.
    ///   - mask: The view whose drawing masks this one.
    /// - Returns: The view, masked.
    nonisolated public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        // Cut to the frame first, as `clipShape(_:style:)` is: the mask is laid
        // in the frame, so nothing past it can be under the mask.
        _MaskView(content: clipped(), mask: mask(), alignment: alignment)
    }
}

/// ``View/mask(alignment:_:)``'s view: its content, with every cell its mask
/// does not draw cleared, and every cell the mask draws translucently faded to
/// the mask's alpha.
nonisolated struct _MaskView<Content: View, Mask: View>: View {
    let content: Content
    let mask: Mask
    let alignment: Alignment

    @MainActor var body: Never { fatalError("_MaskView renders via Renderable") }
}

@MainActor extension _MaskView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIView.renderToBuffer(content, context: context)
        let (columns, rows) = (buffer.width, buffer.height)
        guard columns > 0, rows > 0 else { return buffer }
        if let shape = mask as? any Shape {
            let drawn = resolvedShape(shape, in: context, columns: columns, rows: rows)
            return buffer.clearing(
                keeping: FrameBuffer.cellsKept(
                    by: drawn, columns: columns, rows: rows, aspect: context.environment.imageCellAspect))
        }
        let maskBuffer: FrameBuffer
        let offset: (x: Int, y: Int)
        switch placeLayer(mask, in: buffer, alignment: alignment, context: context, modifierType: Self.self) {
        case .alone, .baseOnly:
            // A mask with nothing in it masks everything out.
            return buffer.clearing(keeping: [])
        case .placed(let placed, let at):
            (maskBuffer, offset) = (placed, at)
        }
        let coverage = MaskCoverage(of: maskBuffer, at: offset, columns: columns, rows: rows, context: context)
        var masked = buffer.clearing(keeping: coverage.kept)
        coverage.inkGlyphs(into: &masked, context: context)
        masked.opacityRegions = coverage.fading(masked.opacityRegions)
        return masked
    }
}

@MainActor extension _MaskView: Layoutable {
    /// Masking changes what draws, never the frame.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Which cells of a `columns` × `rows` frame a mask drawn at `offset` in it
/// keeps, and at what alpha.
private struct MaskCoverage {
    /// The kept cells, as runs of columns, one list a row.
    var kept: [[Range<Int>]] = []

    /// The runs kept at an alpha below 1: the row, the columns and the alpha.
    var translucent: [(row: Int, columns: Range<Int>, alpha: Double)] = []

    /// The cells where the mask draws a glyph with no field: the row, the
    /// column, and the mask's cell there.
    var glyphs: [(row: Int, column: Int, cell: FrameBuffer.RowCell)] = []

    @MainActor
    init(of mask: FrameBuffer, at offset: (x: Int, y: Int), columns: Int, rows: Int, context: RenderContext) {
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let foreground = palette.foreground.resolve(with: palette)
        for row in 0..<rows {
            var runs: [Range<Int>] = []
            let maskRow = row - offset.y
            guard mask.lines.indices.contains(maskRow) else {
                kept.append(runs)
                continue
            }
            let cells = FrameBuffer.cells(
                in: mask.lines[maskRow], through: columns - offset.x, defaultForeground: foreground,
                surface: surface)
            var runStart: Int?
            var runAlpha = 1.0
            func close(at column: Int) {
                guard let start = runStart else { return }
                runs.append(start..<column)
                if runAlpha < 1 { translucent.append((row, start..<column, runAlpha)) }
                runStart = nil
            }
            for column in 0..<columns {
                let maskColumn = column - offset.x
                var alpha: Double?
                if maskColumn >= 0, maskColumn < cells.count, let cell = cells[maskColumn] {
                    alpha = Self.alpha(of: cell, at: (maskColumn, maskRow), in: mask)
                    if alpha != nil, cell.character != " ", Self.field(of: cell) == nil {
                        glyphs.append((row, column, cell))
                    }
                }
                guard let alpha, alpha > 0 else {
                    close(at: column)
                    continue
                }
                if runStart != nil, alpha != runAlpha { close(at: column) }
                if runStart == nil {
                    runStart = column
                    runAlpha = alpha
                }
            }
            close(at: columns)
            kept.append(runs)
        }
    }

    /// How much of the view a mask cell keeps: `nil` where it draws nothing
    /// (a space with no field), and otherwise the alpha it draws with, its
    /// field's where it states one and its glyph's where it does not, times
    /// the layer alpha of any fade over it.
    private static func alpha(of cell: FrameBuffer.RowCell, at point: (Int, Int), in mask: FrameBuffer) -> Double? {
        let drawsGlyph = cell.character != " " || cell.style.paintsInkOnBlankCell
        let field = field(of: cell)
        guard drawsGlyph || field != nil else { return nil }
        let colour = field ?? cell.foreground
        var alpha = Double(colour?.alpha ?? 255) / 255
        if let region = mask.opacityRegions.first(where: {
            $0.offsetX <= point.0 && point.0 < $0.offsetX + $0.width
                && $0.offsetY <= point.1 && point.1 < $0.offsetY + $0.height
        }) {
            alpha *= region.opacity * (field != nil ? region.fieldOpacity : region.inkOpacity)
        }
        return alpha
    }

    /// The field `cell` paints, if it paints one: the terminal's own, stated,
    /// paints nothing over what is behind.
    private static func field(of cell: FrameBuffer.RowCell) -> Color? {
        cell.background.flatMap { $0 == .terminalBackground ? nil : $0 }
    }

    /// `buffer` with each cell it only fills, under a glyph of the mask's, made
    /// that glyph inked in the cell's field and with no field: the shape of the
    /// letter is the part of the cell the mask keeps.
    @MainActor
    func inkGlyphs(into buffer: inout FrameBuffer, context: RenderContext) {
        guard !glyphs.isEmpty else { return }
        let palette = context.environment.palette
        let surface = palette.background.resolve(with: palette)
        let foreground = palette.foreground.resolve(with: palette)
        var row = -1
        var cells: [FrameBuffer.RowCell?] = []
        for glyph in glyphs {
            if glyph.row != row {
                row = glyph.row
                cells = FrameBuffer.cells(
                    in: buffer.lines[row], through: buffer.width, defaultForeground: foreground, surface: surface)
            }
            guard glyph.column < cells.count, let under = cells[glyph.column],
                under.character == " ", !under.style.paintsInkOnBlankCell, let paint = Self.field(of: under)
            else { continue }
            let style = glyph.cell.style.settingForeground(paint).settingBackground(nil)
            buffer.lines[row] = FrameBuffer.splicing(
                style.rendered + String(glyph.cell.character) + "\u{1B}[0m", into: buffer.lines[row],
                atColumn: glyph.column)
        }
    }

    /// `regions` with the view's cells under each translucent run faded to the
    /// run's alpha, as `.opacity(_:)` fades a subtree: every region over the
    /// run scaled where it covers it, then the run's own rectangle after them,
    /// since the resolution takes the layer alpha from the first region over a
    /// cell (`OpacityFading`).
    func fading(_ regions: [OpacityRegion]) -> [OpacityRegion] {
        guard !translucent.isEmpty else { return regions }
        var result = regions
        for run in translucent {
            let rows = run.row..<(run.row + 1)
            var next: [OpacityRegion] = []
            for region in result {
                guard let inside = region.clipped(toColumns: run.columns, rows: rows) else {
                    next.append(region)
                    continue
                }
                next += region.subtracting(columns: run.columns, rows: rows)
                var scaled = inside
                scaled.opacity *= run.alpha
                scaled.cycle = inside.cycle?.scaled(by: run.alpha)
                next.append(scaled)
            }
            next.append(
                OpacityRegion(
                    offsetX: run.columns.lowerBound, offsetY: run.row, width: run.columns.count, height: 1,
                    opacity: run.alpha))
            result = next
        }
        return result
    }
}
