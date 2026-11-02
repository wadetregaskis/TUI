//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+BlendedLayerFold.swift
//
//  A stack of translucent layers, each covering the whole canvas, folded in
//  cells. Composited one at a time, each layer parses both sides, blends, spells
//  the answer, and splices and composites those bytes, for the next layer to
//  parse them straight back: thirty full-screen gradients spent nine tenths of
//  their frame on that round trip and a twentieth on the arithmetic. Between two
//  such layers the bytes are never drawn, so they need not exist.
//
//  Nothing here decides a colour or a glyph: each cell's answer is `blendLayer`'s.
//  What the fold has to get right is that skipping the bytes changes no cell, so
//  it takes only the cells that come back from their bytes unchanged, leaves
//  everything else to the ordinary path, and hands the last layer of a run to the
//  ordinary path too (``FrameBuffer/foldingBlendedLayers(_:width:height:in:)``).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension FrameBuffer {

    /// Folds as many of `layers`, from the first, into this canvas as can be, and
    /// answers how many: `0`, with the canvas untouched, where none can.
    ///
    /// A layer can be folded when it is a whole-canvas fade
    /// (``isWholeCanvasBlend(width:height:)``) of plain cells
    /// (``plainCells(of:width:reusing:surface:defaultForeground:)``) over a canvas of
    /// plain cells, and the layer after it can be too. That second condition is what
    /// makes every cell exact. The canvas's lines after a fold are spelled here rather
    /// than by the composite, and the next layer, composited the ordinary way, replaces
    /// all of their cells: it reads them only through what they parse to, since every
    /// cell of it names its own field and it leaves none of the base's beside it. So
    /// the cells drawn from there on are the ordinary path's.
    ///
    /// The bytes are the ordinary path's too, but for what comes after a row's last
    /// cell. A composite keeps its base's closing escapes behind the overlay, and adds
    /// its own, so one composite per layer ended a row in every earlier layer's, which
    /// nothing draws: a fold has none of them, and a row of a tall stack is shorter
    /// for it.
    ///
    /// A plain cell blended over a plain cell is a plain cell, so the canvas is
    /// checked once. A plain cell's bytes parse back to the same cell, which is why
    /// the fold may skip them, and that holds only at 24-bit colour: at any other depth
    /// a blend's answer is quantised as it is spelled, and the next layer blends
    /// over the quantised colour.
    ///
    /// - Parameters:
    ///   - layers: The layers still to be drawn, in order.
    ///   - width: The canvas's width.
    ///   - height: The canvas's height.
    ///   - composite: What the compositor's environment says about spending claims.
    /// - Returns: How many layers are now drawn.
    mutating func foldingBlendedLayers(
        _ layers: ArraySlice<(buffer: FrameBuffer, x: Int, y: Int)>, width: Int, height: Int,
        in composite: CompositeEnvironment
    ) -> Int {
        // Asked of every layer of every stack, so nothing here reads a cell.
        let run = layers.prefix { layer in
            layer.x == 0 && layer.y == 0 && layer.buffer.isWholeCanvasBlend(width: width, height: height)
        }
        guard run.count >= 2, width > 0, height > 0, self.width == width, lines.count == height,
            opacityRegions.isEmpty, animatedCells.isEmpty, overlays.isEmpty, ColorDepth.current == .truecolor
        else { return 0 }
        let palette = composite.palette
        let surface = palette.background.resolve(with: palette)
        let defaultForeground = palette.foreground.resolve(with: palette)

        func plainCells(of lines: [String], reusing parsed: inout [ParsedLine]) -> [[RowCell?]]? {
            Self.plainCells(of: lines, width: width, reusing: &parsed, surface: surface, defaultForeground: defaultForeground)
        }
        var parsedLines: [ParsedLine] = []
        guard var canvas = plainCells(of: lines, reusing: &parsedLines) else { return 0 }
        // Whether each row's cells are the row above's: nothing has told them apart.
        var matchesRowAbove = lines.indices.map { $0 > 0 && lines[$0] == lines[$0 - 1] }

        parsedLines = []
        guard var source = plainCells(of: run[run.startIndex].buffer.lines, reusing: &parsedLines) else { return 0 }
        var folded = 0
        for index in run.indices.dropFirst() {
            guard let nextSource = plainCells(of: run[index].buffer.lines, reusing: &parsedLines) else { break }
            let landing = run[index - 1].buffer
            let landingLines = landing.lines
            var alpha = landing.wholeCanvasAlpha
            // As the composite marks the claims it spends.
            if composite.linearLight { alpha.linearLight = true }
            for row in canvas.indices {
                // A row the row above matches and a source line matching the one above
                // it give the same answer: a horizontal gradient asks once.
                if matchesRowAbove[row], landingLines[row] == landingLines[row - 1] {
                    canvas[row] = canvas[row - 1]
                    continue
                }
                matchesRowAbove[row] = false
                for column in 0..<width {
                    guard let cell = source[row][column] else { continue }
                    canvas[row][column] = Self.blendLayer(
                        source: cell, destination: canvas[row][column], alpha: alpha, surface: surface,
                        defaultForeground: defaultForeground)
                }
            }
            source = nextSource
            folded += 1
        }
        guard folded > 0 else { return 0 }
        var spelled: [String] = []
        spelled.reserveCapacity(height)
        for row in canvas.indices {
            spelled.append(matchesRowAbove[row] ? spelled[row - 1] : Self.spelling(canvas[row]))
        }
        self = replacingLines(spelled, width: width, uniformWidth: true)
        return folded
    }

    /// Whether this layer is nothing but a canvas-sized picture under fades that each
    /// cover all of it, with one alpha for every cell, so nothing is ever carried past
    /// the composite. Read from the buffer's records, for every layer of every stack.
    private func isWholeCanvasBlend(width: Int, height: Int) -> Bool {
        guard !opacityRegions.isEmpty, self.width == width, lines.count == height, animatedCells.isEmpty,
            overlays.isEmpty, hitTestRegions.isEmpty
        else { return false }
        return opacityRegions.allSatisfy { region in
            region.offsetX <= 0 && region.offsetY <= 0 && region.offsetX + region.width >= width
                && region.offsetY + region.height >= height && region.cycle == nil && region.fieldUnderContent == nil
                && !region.frosts && Self.modeMixesColoursOnly(region.blendMode)
        }
    }

    /// Whether `mode` only says how a cell's colours mix. The three that decide which
    /// side shows can empty a cell, and an emptied cell is not a plain one.
    private static func modeMixesColoursOnly(_ mode: BlendMode) -> Bool {
        switch mode {
        case .sourceAtop, .destinationOver, .destinationOut: return false
        default: return true
        }
    }

    /// The one alpha a ``isWholeCanvasBlend(width:height:)`` layer's cells all owe.
    private var wholeCanvasAlpha: CellAlpha {
        // Never `nil`: the claims cover the column asked about.
        Self.foldedAlphas(of: opacityRegions, over: 0..<1, row: 0) { $0.cellAlpha }[0] ?? .layer(1)
    }

    /// A line and the cells it was taken apart into.
    private typealias ParsedLine = (line: String, cells: [RowCell?])

    /// `lines` taken apart, or `nil` where a cell of them is not plain
    /// (``isPlain(_:)``) or a line is not `width` columns.
    ///
    /// Stacked layers tend to draw the same lines, and a layer's rows the same line,
    /// so each is parsed once: `parsed` holds the lines last taken apart, by row, and
    /// is replaced by these.
    private static func plainCells(
        of lines: [String], width: Int, reusing parsed: inout [ParsedLine], surface: Color, defaultForeground: Color
    ) -> [[RowCell?]]? {
        var result: [[RowCell?]] = []
        result.reserveCapacity(lines.count)
        var taken: [ParsedLine] = []
        taken.reserveCapacity(lines.count)
        for (row, line) in lines.enumerated() {
            if row > 0, line == lines[row - 1] {
                taken.append(taken[row - 1])
            } else if row < parsed.count, parsed[row].line == line {
                taken.append(parsed[row])
            } else {
                let cells = Self.cells(in: line, through: width, defaultForeground: defaultForeground, surface: surface)
                guard line.strippedLength == width, cells.allSatisfy(isPlain) else { return nil }
                taken.append((line, cells))
            }
            result.append(taken[row].cells)
        }
        parsed = taken
        return result
    }

    /// Whether `cell` comes back from its bytes as it is, and blends by colour alone: a
    /// one-column character that is no picture, in opaque 24-bit colours on a field of
    /// its own, its ink stated if it has a glyph, with no attribute.
    ///
    /// Everything `blendedSpan` does around `blendLayer` is about a cell that is not
    /// plain: a wide glyph, a reversal, the terminal's own colours, a picture, a
    /// hairline's mark, a field left to what is behind.
    private static func isPlain(_ cell: RowCell?) -> Bool {
        guard let cell, !cell.isReversed, !cell.statesTerminalField, let field = cell.background,
            isOpaqueRGB(field), cell.foreground.map(isOpaqueRGB) ?? (cell.character == " "),
            cell.character.terminalWidth == 1,
            !cell.character.unicodeScalars.contains(.terminalImagePlaceholder)
        else { return false }
        return cell.style == SGRState().settingForeground(cell.foreground).settingBackground(field)
    }

    /// Whether `colour` is stated as three components, which 24-bit SGR spells as they
    /// are and reads back as they were.
    private static func isOpaqueRGB(_ colour: Color) -> Bool {
        guard case .rgb = colour.value else { return false }
        return colour.isOpaque
    }

    /// `cells` spelled as a line, as `blendedSpan` spells a span, its colours closed at
    /// the end: only ever parsed again.
    private static func spelling(_ cells: [RowCell?]) -> String {
        var line = ""
        var emitted = SGRState()
        for case let cell? in cells {
            line += cell.style.rendered(changingFrom: emitted, resetRestoresAField: true)
            line.append(cell.character)
            emitted = cell.style
        }
        line += SGRState().rendered(changingFrom: emitted)
        return line
    }
}
