//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HairlineMarkerTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore

/// The mark a `.hairline` separator leaves on a row's cells, and the writer's
/// reading of it: where a run is, that the line comes back exactly as it was
/// without it, and that the cells around a run keep their own styling.
@Suite("Hairline marker")
struct HairlineMarkerTests {

    private let grey = (red: UInt8(150), green: UInt8(150), blue: UInt8(160))

    private func mark(_ line: String, _ columns: Range<Int>) -> String {
        HairlineMarker.marking(line, columns: columns, red: grey.red, green: grey.green, blue: grey.blue)
    }

    @Test("A marked run reads back at its columns, and the line comes back unmarked")
    func roundTrip() {
        let line = "\u{1B}[38;5;3mhello\u{1B}[0m world"
        let marked = mark(line, 2..<9)
        #expect(marked != line)
        #expect(HairlineMarker.mayCarryMark(marked))
        let (stripped, runs) = HairlineMarker.extracting(marked)
        #expect(runs == [HairlineMarker.Run(column: 2, width: 7, red: 150, green: 150, blue: 160)])
        #expect(stripped.stripped == line.stripped)
        // The cells outside the run wear what they wore: the run's end restores
        // the styling in force, with nothing of the mark.
        #expect(!stripped.contains("7744"))
    }

    /// A reset inside the run would end a passthrough code; the mark goes back
    /// on after it, as a persistent background is restated.
    @Test("A reset inside the run does not end it")
    func resetInsideTheRun() {
        let line = "ab\u{1B}[1mcd\u{1B}[0mef\u{1B}[mgh"
        let (_, runs) = HairlineMarker.extracting(mark(line, 0..<8))
        #expect(runs == [HairlineMarker.Run(column: 0, width: 8, red: 150, green: 150, blue: 160)])
    }

    /// The 0 of `38;5;0` is a colour's index, not a reset: read as one, it
    /// ended the run at the first black cell.
    @Test("A colour's zero argument is not a reset")
    func colourArgumentsAreNotResets() {
        let line = "a\u{1B}[38;5;0mb\u{1B}[48;2;0;0;0mc"
        let (stripped, runs) = HairlineMarker.extracting(mark(line, 0..<3))
        #expect(runs.map(\.width) == [3])
        #expect(stripped.contains("38;5;0"))
        #expect(stripped.contains("48;2;0;0;0"))
    }

    /// The memo behind `marking` is keyed by a line's bytes: two spellings of
    /// one text are equal `String`s, and each must come back with its own
    /// bytes, not the spelling marked first.
    @Test("A line marked again comes back the same; two spellings of one text, each its own")
    func memoKeysByBytes() {
        let precomposed = "caf\u{E9} au lait"
        let decomposed = "cafe\u{301} au lait"
        #expect(precomposed == decomposed)
        let first = mark(precomposed, 0..<4)
        #expect(mark(precomposed, 0..<4) == first)
        let other = mark(decomposed, 0..<4)
        #expect(Array(other.utf8) != Array(first.utf8))
        #expect(Array(HairlineMarker.extracting(other).line.stripped.utf8) == Array(decomposed.utf8))
    }

    @Test("A wide character is marked whole when it starts in the run, not when it starts before")
    func wideCharacters() {
        let line = "中文ab"
        #expect(HairlineMarker.extracting(mark(line, 1..<4)).runs.map(\.column) == [2])
        #expect(HairlineMarker.extracting(mark(line, 2..<3)).runs.map(\.width) == [2])
    }

    @Test("A collapsed escape keeps its other parameters, and an emptied one goes")
    func collapsedSpellings() {
        let line = "\u{1B}[0;7744:1:2:3;38;5;4mab\u{1B}[7744:1:2:3mcd\u{1B}[0mef"
        let (stripped, runs) = HairlineMarker.extracting(line)
        #expect(stripped == "\u{1B}[0;38;5;4mabcd\u{1B}[0mef")
        #expect(runs == [HairlineMarker.Run(column: 0, width: 4, red: 1, green: 2, blue: 3)])
    }

    @Test("Two colours side by side are two runs")
    func twoColours() {
        let first = HairlineMarker.marking("abcdef", columns: 0..<3, red: 1, green: 1, blue: 1)
        let both = HairlineMarker.marking(first, columns: 3..<6, red: 2, green: 2, blue: 2)
        let runs = HairlineMarker.extracting(both).runs
        #expect(runs.map(\.column) == [0, 3])
        #expect(runs.map(\.width) == [3, 3])
        #expect(runs.map(\.red) == [1, 2])
    }

    @Test("Text that spells the parameter is not a mark")
    func textIsNotAMark() {
        #expect(!HairlineMarker.mayCarryMark("port 7744:1:2:3 open"))
        #expect(HairlineMarker.extracting("port 7744:1:2:3 open").runs.isEmpty)
        #expect(HairlineMarker.stripping("port 7744:1:2:3 open") == "port 7744:1:2:3 open")
    }

    @Test("An empty or out-of-line range marks nothing")
    func emptyRanges() {
        #expect(mark("abc", 1..<1) == "abc")
        #expect(HairlineMarker.extracting(mark("abc", 5..<9)).runs.isEmpty)
    }

    /// The mark rides the cells' styling, so a stage that re-spells styling
    /// through ``SGRState`` — every splitter, the collapser — carries it.
    @Test("The mark survives a re-spelling through SGRState")
    func survivesSGRState() {
        var state = SGRState()
        state.apply(HairlineMarker.sequence(red: 9, green: 8, blue: 7))
        state.apply("\u{1B}[38;5;2m")
        let respelled = state.rendered + "xy"
        #expect(HairlineMarker.extracting(respelled).runs == [HairlineMarker.Run(column: 0, width: 2, red: 9, green: 8, blue: 7)])
    }
}

/// The classic placement's spec constants.
@Suite("Kitty graphics: classic placements")
struct KittyClassicPlacementTests {

    @Test("A placement names its id and placement, crops at native size, holds the cursor, and is quiet")
    func placementKeys() {
        let escape = KittyGraphics.classicPlacement(id: 9, placement: 3, sourceWidth: 640, sourceHeight: 2, z: 1)
        #expect(escape == "\u{1B}_Ga=p,i=9,p=3,x=0,y=0,w=640,h=2,C=1,z=1,q=2\u{1B}\\")
        #expect(!escape.contains(",c="))
        #expect(!escape.contains(",r="))
    }

    /// iTerm2 draws `z=0` under the text and `z=-1` over a fill: 0 is asked
    /// for by nobody who means it.
    @Test("z=0, p=0, a zero crop and an id out of range are refused")
    func refusals() {
        #expect(KittyGraphics.classicPlacement(id: 9, placement: 3, sourceWidth: 1, sourceHeight: 1, z: 0).isEmpty)
        #expect(KittyGraphics.classicPlacement(id: 9, placement: 0, sourceWidth: 1, sourceHeight: 1, z: 1).isEmpty)
        #expect(KittyGraphics.classicPlacement(id: 9, placement: 1, sourceWidth: 0, sourceHeight: 1, z: 1).isEmpty)
        #expect(KittyGraphics.classicPlacement(id: 0, placement: 1, sourceWidth: 1, sourceHeight: 1, z: 1).isEmpty)
        #expect(KittyGraphics.deletePlacement(id: 9, placement: 0).isEmpty)
    }

    @Test("A placement's delete keeps the image's data")
    func deleteKeepsData() {
        #expect(KittyGraphics.deletePlacement(id: 9, placement: 3) == "\u{1B}_Ga=d,d=i,i=9,p=3,q=2\u{1B}\\")
    }
}

/// The stages that rewrite a row's cells on its way to the writer, and what
/// each leaves of a mark: the reason the mark rides the cells is that every
/// one of them carries it — or, an overlay, takes it away exactly where it
/// covers the cells.
@Suite("Hairline marker through the cell stages")
struct HairlineMarkerStageTests {

    private let line = HairlineMarker.marking(
        "\u{1B}[48;5;236m abcdefghijklmnopqrst \u{1B}[0m", columns: 1..<21, red: 7, green: 8, blue: 9)

    private func runs(_ line: String) -> [Range<Int>] {
        HairlineMarker.extracting(line).runs.map { $0.column..<($0.column + $0.width) }
    }

    @Test("The marked line reads as one run")
    func baseline() {
        #expect(runs(line) == [1..<21])
    }

    @Test("A clip at the right cuts the run")
    func rightClip() {
        #expect(runs(line.ansiAwarePrefix(visibleCount: 10)) == [1..<10])
    }

    @Test("A cut at the left moves it")
    func leftCut() {
        #expect(runs(line.ansiAwareCuttingLeadingColumns(5)) == [0..<16])
    }

    @Test("Collapsing adjacent escapes keeps it")
    func collapse() {
        #expect(runs(line.collapsingAdjacentSGR()) == [1..<21])
        #expect(runs(line.collapsingAdjacentSGR(resetRestoresAField: true)) == [1..<21])
    }

    @Test("A line prepended and padded, as a container does, keeps it in its cells")
    func padded() {
        #expect(runs("│ " + line + "   │") == [3..<23])
    }

    /// The case the mark exists for: a sheet or a menu over a list replaces
    /// the cells it covers, and the line must not show through it.
    @Test("An overlay takes the mark out of the cells it covers, and only those")
    func overlayCuts() {
        let base = FrameBuffer(lines: [line])
        let composited = base.composited(with: FrameBuffer(lines: ["XYZ"]), at: (x: 6, y: 0))
        #expect(runs(composited.lines[0]) == [1..<6, 9..<21])
    }
}
