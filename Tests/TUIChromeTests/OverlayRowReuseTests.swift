//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlayRowReuseTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIChrome
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// ``OverlayRowReuse``: the overlay compositing's page resolution and veils answer
/// an unchanged row with what they made of it last time, and draw exactly what a
/// fresh compositing draws, whatever the layers over them do.
@MainActor
@Suite("Overlay row reuse")
struct OverlayRowReuseTests {

    private let width = 24
    private let height = 6

    /// A page of `height` rows, a faded label on its first and a translucent field
    /// on its third, with `layers` pending over it.
    private func page(label: String = "faded", row4: String = "row four", layers: [OverlayLayer]) -> FrameBuffer {
        var lines = (0..<height).map { "row \($0)" }
        lines[0] = ANSIRenderer.colorize(label, foreground: .rgb(40, 200, 40))
        lines[2] = ANSIRenderer.colorize("field", foreground: .rgb(200, 40, 40), background: .rgb(20, 20, 200))
        lines[4] = ANSIRenderer.colorize(row4, foreground: .rgb(200, 200, 40))
        var buffer = FrameBuffer(lines: lines)
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5),
            OpacityRegion(offsetX: 0, offsetY: 2, width: 5, height: 1, opacity: 1, fieldOpacity: 0.3),
        ]
        buffer.overlays = layers
        return buffer
    }

    /// A modal (a sheet) at `x`, `y` from the centre, dimming what is below it.
    private func sheet(x: Int = 0, y: Int = 0, text: String = "sheet") -> OverlayLayer {
        OverlayLayer(
            offsetX: x, offsetY: y, content: FrameBuffer(lines: [text, "body"]), level: .modal, centered: true,
            dimsBackground: true)
    }

    /// An alert, dimming the sheet and the page below it.
    private func alert(text: String = "alert") -> OverlayLayer {
        OverlayLayer(
            offsetX: 0, offsetY: 0, content: FrameBuffer(lines: [text]), level: .alert, centered: true,
            dimsBackground: true)
    }

    private func composited(_ buffer: FrameBuffer, _ palette: any Palette, _ rows: OverlayRowReuse?) -> [String] {
        buffer.compositingOverlays(maxWidth: width, maxHeight: height, palette: palette, images: nil, reusing: rows)
            .lines
    }

    @Test("Frames composited through the reuse match fresh ones, as the page and its layers change")
    func reusedFramesMatchFreshOnes() {
        let palette = makeRenderContext(width: width, height: height).environment.palette
        let other: any Palette = SystemPalette(.amber)
        let rows = OverlayRowReuse()
        let frames: [(FrameBuffer, any Palette)] = [
            (page(layers: [sheet()]), palette),
            (page(layers: [sheet()]), palette),
            // The page changes under the sheet, one row and then another.
            (page(label: "fadeD", layers: [sheet()]), palette),
            (page(label: "fadeD", row4: "row 4!", layers: [sheet()]), palette),
            // The sheet moves, and its content changes.
            (page(label: "fadeD", layers: [sheet(x: 2, y: 1)]), palette),
            (page(label: "fadeD", layers: [sheet(x: 2, y: 1, text: "sheeT")]), palette),
            // An alert over the sheet: a second veil, over the first and the sheet.
            (page(label: "fadeD", layers: [sheet(), alert()]), palette),
            (page(label: "fadeD", layers: [sheet(), alert()]), palette),
            (page(label: "fadeD", layers: [sheet(), alert(text: "alerT")]), palette),
            // Back to the sheet alone, then to another palette: another scrim.
            (page(label: "fadeD", layers: [sheet()]), palette),
            (page(label: "fadeD", layers: [sheet()]), other),
            (page(label: "fadeD", layers: [sheet()]), other),
            // And nothing over the page at all.
            (page(layers: []), palette),
            (page(layers: [sheet()]), palette),
        ]
        for (index, (buffer, palette)) in frames.enumerated() {
            #expect(composited(buffer, palette, rows) == composited(buffer, palette, nil), "frame \(index)")
        }
    }

    @Test("A veil through the reuse draws what a fresh one draws, as its scrim alone changes")
    func reusedVeilsFollowTheScrim() {
        let palette = makeRenderContext(width: width, height: height).environment.palette
        let buffer = page(layers: []).resolvingOpacity(surface: .rgb(0, 0, 0), palette: palette)
        let reuse = OpacityRowReuse()
        let scrims: [Color] = [.rgb(10, 10, 10), .rgb(10, 10, 10), .rgb(90, 20, 20), .rgb(90, 20, 20), .rgb(10, 10, 10)]
        for (index, scrim) in scrims.enumerated() {
            let fresh = buffer.veiledAsBackdrop(by: scrim, surface: .rgb(0, 0, 0), palette: palette, images: nil)
            let reused = buffer.veiledAsBackdrop(
                by: scrim, surface: .rgb(0, 0, 0), palette: palette, images: nil, reusing: reuse)
            #expect(reused.lines == fresh.lines, "frame \(index)")
        }
    }

    @Test("A veil rewrites only the rows that changed since it last drew them")
    func veilRewritesOnlyChangedRows() {
        let reuse = OpacityRowReuse()
        let inputs = OpacityRowReuse.Inputs(
            surface: .rgb(0, 0, 0), defaultForeground: .rgb(255, 255, 255), statingTheSurface: false,
            fillingStatedTerminalField: false, scrim: .rgb(10, 10, 10))
        func rewrites(_ lines: [String], under inputs: OpacityRowReuse.Inputs) -> [String] {
            var asked: [String] = []
            var rewritten = lines
            reuse.rewritingEvery(&rewritten, under: inputs) { line in
                asked.append(line)
                return line + "!"
            }
            #expect(rewritten == lines.map { $0 + "!" })
            return asked
        }
        #expect(rewrites(["a", "b", "c"], under: inputs) == ["a", "b", "c"])
        #expect(rewrites(["a", "b", "c"], under: inputs).isEmpty)
        #expect(rewrites(["a", "B", "c"], under: inputs) == ["B"])
        // Another scrim: every row.
        var other = inputs
        other.scrim = .rgb(200, 200, 200)
        #expect(rewrites(["a", "B", "c"], under: other) == ["a", "B", "c"])
        // A row drawing a picture is never kept.
        let picture = String(Character(Unicode.Scalar.terminalImagePlaceholder)) + "pic"
        #expect(rewrites(["a", picture], under: other) == [picture])
        #expect(rewrites(["a", picture], under: other) == [picture])
    }

    @Test("Each veil of a frame keeps its own rows")
    func veilsAreKeptApart() {
        let rows = OverlayRowReuse()
        let first = rows.veil(0)
        #expect(rows.veil(1) !== first)
        #expect(rows.veil(0) === first)
        #expect(rows.resolution !== rows.veil(0))
    }
}
