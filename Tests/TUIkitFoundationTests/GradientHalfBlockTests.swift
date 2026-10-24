//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GradientHalfBlockTests.swift
//
//  A ramp that changes down a column is drawn two samples a cell behind blank
//  cells — `▄` in the bottom half's colour over the top half's, the shapes'
//  half-block rule — where the terminal's Block Elements fill the line, and
//  one sample a cell where they do not (decisions B95).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// `view` drawn in a `width` × `height` frame, on a terminal whose Block
/// Elements fill the line or not.
@MainActor
private func drawn(_ view: some View, width: Int, height: Int, blocksFill: Bool = true) -> [[PaintedCell]] {
    var context = makeRenderContext(width: width, height: height)
    context.environment.blockElementsFillTheLine = blocksFill
    return renderToBuffer(view, context: context).lines.map(paintedCells)
}

private func glyphs(_ rows: [[PaintedCell]]) -> [String] {
    rows.map { String($0.map(\.glyph)) }
}

private let downward = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
private let across = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)

@MainActor
@Suite("Gradients two samples a cell")
struct GradientHalfBlockTests {

    @Test("A downward ramp as a view is ▄ in the bottom half's colour over the top half's")
    func viewDrawsHalves() {
        let rows = drawn(downward, width: 4, height: 3)
        #expect(glyphs(rows) == ["▄▄▄▄", "▄▄▄▄", "▄▄▄▄"])
        // Each cell is two samples, and the bottom of one row is not the top
        // of the next: six steps down three rows.
        let cell = rows[1][0]
        #expect(cell.ink != nil && cell.ink != cell.state.backgroundColour)
        #expect(rows[0][0].ink != rows[1][0].ink)
        #expect(rows[0][0].background != rows[1][0].background)
    }

    @Test("Where Block Elements fall short of the line, a ramp keeps one sample a cell")
    func appleTerminalKeepsOneSample() {
        #expect(glyphs(drawn(downward, width: 4, height: 3, blocksFill: false)) == ["    ", "    ", "    "])
        let box = drawn(RoundedRectangle(cornerRadius: 1).fill(downward), width: 6, height: 3, blocksFill: false)
        #expect(!glyphs(box).joined().contains("▄"))
    }

    @Test("A ramp along the row is the same in both halves, and stays spaces")
    func horizontalRampIsUnchanged() {
        #expect(glyphs(drawn(across, width: 6, height: 2)) == ["      ", "      "])
    }

    @Test("Behind content, the bare cells take halves and the content keeps its letters on one sample")
    func backgroundBehindText() {
        let view = Text("ab").frame(width: 5, height: 2, alignment: .topLeading).background(downward)
        let rows = drawn(view, width: 5, height: 2)
        #expect(glyphs(rows) == ["ab▄▄▄", "▄▄▄▄▄"])
        // The letters' field is the cell's one sample, between the halves.
        #expect(!rows[0][0].background.isEmpty && rows[0][0].glyph == "a")
    }

    @Test("A text's own styled spaces are not bare, and keep their colours")
    func styledSpacesAreContent() {
        let view = Text("a b").underline().frame(width: 4, alignment: .leading).background(downward)
        let row = glyphs(drawn(view, width: 4, height: 1))[0]
        #expect(row == "a b▄")
    }

    @Test("A rounded rectangle's whole cells take halves, its corners their quadrants")
    func roundedRectangleFill() {
        let rows = glyphs(drawn(RoundedRectangle(cornerRadius: 1).fill(downward), width: 6, height: 3))
        #expect(rows[1] == "▄▄▄▄▄▄")
        #expect(rows[0].dropFirst().dropLast() == "▄▄▄▄")
        #expect(rows[0].first != "▄" && rows[0].first != " ", "a corner is its quadrant")
    }

    @Test("A mesh is sampled at the half rows too")
    func meshDrawsHalves() {
        let mesh = MeshGradient(
            width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [.red, .red, .blue, .blue])
        #expect(glyphs(drawn(mesh, width: 4, height: 3)).joined().allSatisfy { $0 == "▄" })
    }

    @Test("With no colour, or translucent, or blended, a ramp keeps one sample a cell")
    func declinedCases() {
        withColorDepth(.noColor) {
            #expect(!glyphs(drawn(downward, width: 4, height: 2)).joined().contains("▄"))
        }
        let faded = LinearGradient(colors: [.red.opacity(0.5), .blue.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        #expect(!glyphs(drawn(faded, width: 4, height: 2)).joined().contains("▄"))
        let blended = Text("").frame(width: 4, height: 2).background(downward.blendMode(.multiply))
        #expect(!glyphs(drawn(blended, width: 4, height: 2)).joined().contains("▄"))
    }

    @Test("A row's bare cells are the spaces with nothing in force")
    func bareCells() {
        #expect("  ".bareCells(width: 2) == [true, true])
        #expect("a\u{1B}[1m \u{1B}[0m ".bareCells(width: 3) == [false, false, true])
        #expect("\u{1B}]8;;https://example.com\u{1B}\\a\u{1B}]8;;\u{1B}\\ ".bareCells(width: 2) == nil)
        #expect("界 ".bareCells(width: 3) == [false, false, true])
    }
}
