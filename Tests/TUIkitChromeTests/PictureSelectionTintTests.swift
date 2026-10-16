//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PictureSelectionTintTests.swift
//
//  A screen selection over a picture tints the picture's cells — their glyphs
//  kept, their colours moved toward the selection's — where it repaints text
//  in the selection colours. Repainted, a solid-style picture (pixels as
//  coloured spaces) became a flat field of selection colour, and a fine-style
//  one (two pixels a half block) scattered half blocks over it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A selection over a picture")
struct PictureSelectionTintTests {

    /// Each visible cell's glyph and the SGR state it is drawn in.
    private func cells(_ line: String) -> [(glyph: Character, state: SGRState)] {
        var state = SGRState()
        var cells: [(Character, SGRState)] = []
        for segment in line.ansiSegments() {
            switch segment {
            case .ansi(let sequence, _): state.apply(sequence)
            case .visible(let glyph): cells.append((glyph, state))
            }
        }
        return cells
    }

    @Test("A picture's cells keep their glyphs and take a tint; the text beside them is selected as text")
    func tintsPictureCells() {
        // "ab", four half-block pixels in red over blue, "cd".
        let pixels = ANSIRenderer.colorize(
            "▀▀▀▀",
            foreground: Color.rgb(200, 0, 0), background: Color.rgb(0, 0, 200))
        var buffer = FrameBuffer(lines: ["ab" + pixels + "cd"])
        buffer.hitTestRegions += HitTestRegion.pictureCorners(width: 4, height: 1).map { $0.shifted(byX: 2, y: 0) }
        let selection = ScreenSelection.Selection(
            anchor: .init(x: 0, y: 0), head: .init(x: 7, y: 0),
            clip: .init(x: 0, y: 0, width: 8, height: 1), shape: .stream, unit: .character, text: "")
        let palette = PaletteRegistry.all[0]
        let drawn = ColorDepth.withCurrent(.truecolor) {
            ScreenSelection.highlighting(
                selection, in: buffer, palette: palette, pictures: buffer.hitTestRegions.pictureRects)
        }
        let before = cells(buffer.lines[0])
        let after = cells(drawn.lines[0])
        #expect(after.map(\.glyph) == before.map(\.glyph), "every glyph kept: \(drawn.lines[0].debugDescription)")
        for column in 2..<6 {
            #expect(after[column].state != before[column].state, "pixel \(column) is tinted")
            #expect(after[column].state != after[0].state, "pixel \(column) is not repainted as text")
        }
        #expect(after[0].state == after[7].state, "the text either side is selected alike")
        #expect(after[0].state != before[0].state, "and is selected")
    }

    @Test("A picture's corners read back as its rectangle wherever its buffer is carried")
    func cornersReadBack() {
        var picture = FrameBuffer(lines: ["xxx", "xxx"])
        picture.hitTestRegions += HitTestRegion.pictureCorners(width: 3, height: 2)
        var page = FrameBuffer(lines: ["ab", "cd"])
        page.appendHorizontally(picture)
        var screen = FrameBuffer(lines: ["header"])
        screen.appendVertically(page)
        #expect(screen.hitTestRegions.pictureRects == [CellRect(x: 2, y: 1, width: 3, height: 2)])
    }
}
