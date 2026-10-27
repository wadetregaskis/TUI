//  🖥️ TUI — A Terminal UI framework for Swift
//  PictureUnderTextMarkerTests.swift
//
//  A glyph over a frosted picture carries a mark naming the picture's copy and
//  the pixels of it the cell covers; the diff writer reads the marked runs
//  back and takes the marks out. These pin the spelling, the read-back, and
//  how cells join into runs.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore

@Suite("Picture under text marks")
struct PictureUnderTextMarkerTests {

    /// `text`'s characters, each marked as the cell at `x` + its index × 4 of
    /// image `image`, row `y`: one cell of a copy at 4 pixels a cell.
    private func marked(_ text: String, image: UInt32 = 0x01_2345, x: Int = 0, y: Int = 8) -> String {
        text.enumerated().map { index, character in
            PictureUnderTextMarker.sequence(.init(image: image, x: x + index * 4, y: y, width: 4, height: 8))
                + String(character)
        }.joined() + "\u{1B}[0m"
    }

    @Test("Marked cells read back as one run, and the line loses its marks")
    func readsBackOneRun() {
        let line = "ab" + marked("Hi!") + "cd"
        #expect(PictureUnderTextMarker.mayCarryMark(line))
        let (stripped, runs) = PictureUnderTextMarker.extracting(line)
        #expect(stripped.stripped == "abHi!cd")
        #expect(!stripped.contains("7745"))
        #expect(runs == [.init(column: 2, columns: 3, image: 0x01_2345, x: 0, y: 8, width: 12, height: 8)])
    }

    @Test("A cell that does not continue the run starts another")
    func breaksRuns() {
        let gap = marked("ab", x: 0) + marked("cd", x: 40)
        #expect(PictureUnderTextMarker.extracting(gap).runs.map(\.column) == [0, 2])
        let otherImage = marked("ab") + marked("cd", image: 7, x: 8)
        #expect(PictureUnderTextMarker.extracting(otherImage).runs.map(\.image) == [0x01_2345, 7])
        let unmarked = marked("ab") + "-" + marked("cd", x: 12)
        #expect(PictureUnderTextMarker.extracting(unmarked).runs.map(\.columns) == [2, 2])
    }

    /// The share panel's checkbox, `⬛︎`, squeezed one column's pixels into two
    /// and left the rest of its row's run a column short of its pixels.
    @Test("A wide glyph's mark covers its pixels for every column it takes")
    func wideGlyph() {
        let line = marked("a") + marked("⬛︎", x: 4) + marked("b", x: 12)
        let runs = PictureUnderTextMarker.extracting(line).runs
        #expect(runs == [.init(column: 0, columns: 4, image: 0x01_2345, x: 0, y: 8, width: 16, height: 8)])
    }

    @Test("Text that only looks like a mark is text")
    func textIsNotAMark() {
        #expect(!PictureUnderTextMarker.mayCarryMark("port 7745:1:2 open"))
        #expect(PictureUnderTextMarker.stripping("plain") == "plain")
    }

    @Test("An image id past sixteen bits survives the spelling")
    func largeIDs() {
        let (_, runs) = PictureUnderTextMarker.extracting(marked("x", image: 0xFF_FFFF))
        #expect(runs.first?.image == 0xFF_FFFF)
    }

    @Test("A hairline's mark and a picture's ride one line without mixing")
    func besideHairlines() {
        let line = HairlineMarker.marking(marked("abc"), columns: 0..<3, red: 1, green: 2, blue: 3)
        let pictures = PictureUnderTextMarker.extracting(line)
        #expect(pictures.runs.count == 1)
        let hairlines = HairlineMarker.extracting(pictures.line)
        #expect(hairlines.runs.map(\.width) == [3])
        #expect(hairlines.line.stripped == "abc")
    }
}
