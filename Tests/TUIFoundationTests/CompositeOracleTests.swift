//  🖥️ TUI — A Terminal UI framework for Swift
//  CompositeOracleTests.swift
//
//  The copying `composited(with:at:)` used to rebuild and measure every row of
//  the base per call; over a uniform base it now copies the buffer and
//  composites in place, touching only the rows the overlay covers (hunt 11-20,
//  CORE1-4). That must not change a cell. This keeps the old copying body as an
//  oracle and holds both twins to it over random bases and overlays: styled,
//  with fields, wide glyphs, runs, opacity claims, placed past every edge.
//
//  Before the fix it caught the in-place twin twice: grounding a painted
//  overlay's runs on the base's fields (CORE1-9), and giving a result of no
//  rows a width where the copying twin measured none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUITestSupport

@Suite("Compositing draws what the old copying composite drew")
struct CompositeOracleTests {

    // MARK: - The oracle: the copying composite before CORE1-4, verbatim

    /// `FrameBuffer.insertOverlay(base:overlay:atColumn:overlayIsPainted:)`.
    private static func insert(
        base: String, overlay: String, atColumn column: Int, overlayIsPainted: Bool
    ) -> (line: String, fields: FieldsUnderOverlay) {
        guard column >= 0 else {
            guard column + overlay.strippedLength > 0 else { return (base, .none) }
            return insert(
                base: base, overlay: overlay.ansiAwareCuttingLeadingColumns(-column), atColumn: 0,
                overlayIsPainted: overlayIsPainted)
        }
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + overlay.strippedLength)
        return (
            FrameBuffer.insertOverlay(split: split, overlay: overlay, atColumn: column, overlayIsPainted: overlayIsPainted),
            split.fieldsUnderOverlay
        )
    }

    private static func oracle(
        _ base: FrameBuffer, _ overlay: FrameBuffer, at position: (x: Int, y: Int), overlayIsPainted: Bool
    ) -> FrameBuffer {
        guard !overlay.isEmpty else {
            var result = base
            result.appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
            result.appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
            result.animatedCells.append(contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
            result.opacityRegions.append(contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
            return result
        }
        let resultWidth = max(base.width, position.x + overlay.width)
        let resultHeight = max(base.height, position.y + overlay.height)
        var fields =
            overlay.animatedCells.isEmpty || overlayIsPainted
            ? nil : [FieldsUnderOverlay](repeating: .none, count: overlay.lines.count)
        func overlayLine(onRow row: Int) -> String? {
            let overlayRow = row - position.y
            guard overlayRow >= 0, overlayRow < overlay.lines.count, !overlay.lines[overlayRow].isEmpty
            else { return nil }
            return overlay.lines[overlayRow]
        }
        var result = (0..<resultHeight).map { $0 < base.lines.count ? base.lines[$0] : "" }
        for row in result.indices {
            let baseLine = result[row].padToVisibleWidth(resultWidth)
            if overlayIsPainted && position.x >= 0 {
                let line = overlayLine(onRow: row)
                result[row] = FrameBuffer.paintedOverlayPieces(
                    base: baseLine, atColumn: position.x, overlayWidth: line?.strippedLength,
                    terminalForeground: { nil }
                ).joined(around: line ?? "")
                continue
            }
            guard let line = overlayLine(onRow: row) else {
                result[row] = baseLine
                continue
            }
            let inserted = insert(base: baseLine, overlay: line, atColumn: position.x, overlayIsPainted: overlayIsPainted)
            fields?[row - position.y] = inserted.fields
            result[row] = inserted.line
        }
        // The one change to the old body: a result of no rows (an overlay wholly
        // above a base of none) measured as none wide; it is now as wide as a
        // result of any rows would be, as the in-place twin always made it.
        var composited =
            result.isEmpty ? FrameBuffer(lines: [], width: resultWidth, uniformWidth: true) : FrameBuffer(lines: result)
        composited.overlays = base.overflowCovered(under: overlay, at: position)
        composited.appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
        composited.hitTestRegions = base.hitTestRegions
        composited.appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
        composited.animatedCells =
            base.animatedCellsPunched(by: overlay, at: position)
            + overlay.shiftedRuns(groundedOn: fields, byX: position.x, y: position.y)
        composited.opacityRegions =
            base.opacityRegionsPunched(by: overlay, at: position)
            + overlay.shiftedOpacityRegions(byX: position.x, y: position.y)
        return composited
    }

    // MARK: - Random buffers

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    /// A run of cells: plain, coloured, on a field, wide or accented.
    private static func segment(_ random: inout Seeded) -> String {
        let text = ["ab", "x", "世", "é界", "  ", "q 世"].randomElement(using: &random)!
        switch Int.random(in: 0..<5, using: &random) {
        case 0: return "\u{1B}[3\(Int.random(in: 1...6, using: &random))m\(text)\u{1B}[0m"
        case 1: return "\u{1B}[4\(Int.random(in: 1...6, using: &random))m\(text)\u{1B}[49m"
        case 2: return "\u{1B}[1;4\(Int.random(in: 1...6, using: &random))m\(text)\u{1B}[0m"
        case 3: return "\u{1B}[49m\(text)"
        default: return text
        }
    }

    private static func lines(rows: Int, uniform: Bool, _ random: inout Seeded) -> [String] {
        var lines = (0..<rows).map { _ in
            (0..<Int.random(in: 0...4, using: &random)).map { _ in segment(&random) }.joined()
        }
        if uniform {
            let width = lines.map(\.strippedLength).max() ?? 0
            lines = lines.map { $0.padToVisibleWidth(width) }
        }
        return lines
    }

    private static func buffer(rows: Int, uniform: Bool, _ random: inout Seeded) -> FrameBuffer {
        var buffer = FrameBuffer(lines: lines(rows: rows, uniform: uniform, &random))
        guard buffer.width > 0, !buffer.lines.isEmpty else { return buffer }
        if Bool.random(using: &random) {
            let row = Int.random(in: 0..<buffer.height, using: &random)
            let column = Int.random(in: 0..<buffer.width, using: &random)
            let width = Int.random(in: 1...max(1, buffer.width - column), using: &random)
            let frames = ["*", "+"].map { String(repeating: $0, count: width) }
            buffer.animatedCells = [
                AnimatedCellRun(offsetX: column, offsetY: row, width: width, frames: frames, clock: .cursor)
            ]
        }
        if Bool.random(using: &random) {
            buffer.opacityRegions = [
                OpacityRegion(
                    offsetX: Int.random(in: 0..<buffer.width, using: &random),
                    offsetY: Int.random(in: 0..<buffer.height, using: &random),
                    width: Int.random(in: 1...3, using: &random), height: Int.random(in: 1...2, using: &random),
                    opacity: [0.25, 0.5, 0.75].randomElement(using: &random)!)
            ]
        }
        if Bool.random(using: &random) {
            buffer.hitTestRegions = [
                HitTestRegion(
                    offsetX: 0, offsetY: 0, width: buffer.width, height: 1, handlerID: HitTestRegion.HandlerID(7),
                    focusID: nil)
            ]
        }
        return buffer
    }

    /// Each line's cells: the glyph and the SGR state it is drawn in. What a
    /// terminal shows of a line, whatever escapes spell it — the in-place twin
    /// writes a row it covers whole without the base's trailing reset, and
    /// draws exactly what the oracle does.
    private static func cells(_ line: String) -> [String] {
        var state = SGRState()
        var cells: [String] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let glyph): cells.append("\(state.rendered)|\(glyph)")
            }
        }
        return cells
    }

    // MARK: - The test

    @Test("Both twins draw what the old copying composite drew, over random overlays", arguments: 0..<8)
    func twinsMatchTheOracle(seed: UInt64) {
        var random = Seeded(state: seed)
        for _ in 0..<250 {
            let base = Self.buffer(
                rows: Int.random(in: 0...5, using: &random), uniform: Bool.random(using: &random), &random)
            let overlay = Self.buffer(
                rows: Int.random(in: 1...3, using: &random), uniform: Bool.random(using: &random), &random)
            let position = (
                x: Int.random(in: -3...(base.width + 2), using: &random),
                y: Int.random(in: -2...(base.height + 1), using: &random)
            )
            let painted = Bool.random(using: &random)

            let expected = Self.oracle(base, overlay, at: position, overlayIsPainted: painted)
            let copied = base.composited(with: overlay, at: position, overlayIsPainted: painted)
            var inPlace = base
            inPlace.composite(with: overlay, at: position, overlayIsPainted: painted, terminalForeground: { nil })

            for (name, result) in [("copied", copied), ("in place", inPlace)] {
                let context = "\(name), seed \(seed), at \(position), painted \(painted): \(base.lines) ← \(overlay.lines)"
                #expect(result.lines.map(Self.cells) == expected.lines.map(Self.cells), "\(context)")
                #expect(result.width == expected.width, "\(context)")
                #expect(result.animatedCells == expected.animatedCells, "\(context)")
                #expect(result.opacityRegions == expected.opacityRegions, "\(context)")
                #expect(result.hitTestRegions == expected.hitTestRegions, "\(context)")
                #expect(result.overlays == expected.overlays, "\(context)")
                if result.linesAreUniformWidth {
                    #expect(result.lines.allSatisfy { $0.strippedLength == result.width }, "\(context)")
                }
                if let widths = result.lineWidths {
                    #expect(widths == result.lines.map(\.strippedLength), "\(context)")
                }
            }
        }
    }
}
