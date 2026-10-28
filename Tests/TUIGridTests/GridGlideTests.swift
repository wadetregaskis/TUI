//  🖥️ TUI — A Terminal UI framework for Swift
//  GridGlideTests.swift
//
//  A grid's cells glide to where the lattice puts them after a change under
//  an animation, as a stack's children do (decisions FB16 (a′), B-FB16-3).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUIGrid
@testable import TUITestSupport

/// Two rows of two cells, the first column as wide as its widest cell.
private struct Lattice: View {
    let wide: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text(wide ? "AAAA" : "A")
                Text("B")
            }
            GridRow {
                Text("C")
                Text("D")
            }
        }
    }
}

@MainActor
@Suite("A grid's cells glide when the lattice changes")
struct GridGlideTests {
    private var context: RenderContext = {
        var context = makeRenderContext(width: 12, height: 6)
        context.environment.canAnimate = true
        return context
    }()

    /// `view` at `millis`, under `animation` when the frame carries a change.
    private func draw(_ view: some View, atMillis millis: Int, animating animation: Animation? = nil) -> [String] {
        var context = context
        context.environment.frameNowNanos = Int64(millis) * 1_000_000
        context.environment.transaction = Transaction(animation: animation)
        let storage = context.environment.stateStorage!
        storage.beginRenderPass()
        defer { storage.endRenderPass() }
        return renderToBuffer(view, context: context).withLayersDrawn().lines.map(\.stripped)
    }

    /// The column `glyph` is drawn at on `row`, or `nil`.
    private func column(of glyph: Character, row: Int, in lines: [String]) -> Int? {
        guard row < lines.count, let at = lines[row].firstIndex(of: glyph) else { return nil }
        return lines[row].distance(from: lines[row].startIndex, to: at)
    }

    @Test("Cells a widened column pushes along glide there with the change")
    func cellsGlide() {
        _ = draw(Lattice(wide: false), atMillis: 0)
        let start = draw(Lattice(wide: true), atMillis: 1000, animating: .linear(duration: 1))
        #expect(column(of: "B", row: 0, in: start) == 1, "B starts where it was: \(start)")
        #expect(column(of: "D", row: 1, in: start) == 1, "and D: \(start)")
        let half = draw(Lattice(wide: true), atMillis: 1500)
        let halfB = column(of: "B", row: 0, in: half) ?? -1
        #expect((2...3).contains(halfB), "B part-way along: \(half)")
        #expect(column(of: "D", row: 1, in: half) == halfB, "D beside it: \(half)")
        let end = draw(Lattice(wide: true), atMillis: 2000)
        #expect(end.prefix(2) == ["AAAAB", "C   D"], "landed: \(end)")
    }

    @Test("An unanimated change moves the cells at once")
    func unanimatedChangeJumps() {
        _ = draw(Lattice(wide: false), atMillis: 0)
        let lines = draw(Lattice(wide: true), atMillis: 1000)
        #expect(lines.prefix(2) == ["AAAAB", "C   D"], "\(lines)")
    }
}
