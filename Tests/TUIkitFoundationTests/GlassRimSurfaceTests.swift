//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GlassRimSurfaceTests.swift
//
//  A glass's rim is laid over its surface, and the surface stays under it:
//  the corner cells of a rounded glass, which the surface only part-covers,
//  carry the surface under their `╭ ╮ ╰ ╯` as every other rim cell does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
@Suite("A glass's rim keeps the surface under it")
struct GlassRimSurfaceTests {
    private func screen(_ view: some View, width: Int, height: Int, appearance: Appearance = .rounded) -> [String] {
        let context = makeRenderContext(width: width, height: height) { environment, _ in
            environment.palette = SystemPalette.green
            environment.appearance = appearance
        }
        return ColorDepth.withCurrent(.truecolor) { renderToScreen(view, context: context).lines }
    }

    /// The background of every cell of `lines`, row by row.
    private func backgrounds(_ lines: [String]) -> [[String]] {
        lines.map { paintedCells($0).map(\.background) }
    }

    @Test(
        "Every cell of a capsule glass, its four corners among them, is painted with the surface",
        arguments: [Glass.regular, .clear, .regular.tint(.red)])
    func capsuleCorners(_ glass: Glass) {
        let lines = screen(Text("Flag").padding().glassEffect(glass), width: 6, height: 3)
        let painted = backgrounds(lines)
        let surface = painted[1][2]
        #expect(!surface.isEmpty, "the surface itself is painted: \(lines.debugDescription)")
        for (row, cells) in painted.enumerated() {
            #expect(cells.count == 6)
            #expect(cells.allSatisfy { $0 == surface }, "row \(row) of \(painted)")
        }
        #expect(lines.map(\.stripped) == ["╭────╮", "│Flag│", "╰────╯"])
    }

    @Test("A rounded rectangle of glass keeps the surface under its corners too")
    func roundedRectangleCorners() {
        let view = Text("Flag").padding().glassEffect(.regular.tint(.red), in: RoundedRectangle(cornerRadius: 4))
        let painted = backgrounds(screen(view, width: 6, height: 3))
        let surface = painted[1][2]
        #expect(painted.allSatisfy { $0.allSatisfy { $0 == surface } }, "\(painted)")
    }

    @Test("Under a rim of no lines the corners stay the surface's quadrants, as they were")
    func blankRimUnchanged() {
        let lines = screen(Text("Flag").padding().glassEffect(), width: 6, height: 3, appearance: .blank).map(\.stripped)
        #expect(lines[1] == " Flag ")
        #expect((lines[0] + lines[2]).allSatisfy { $0 == " " || TerminalSymbols.quadrants.contains($0) }, "\(lines)")
    }
}
