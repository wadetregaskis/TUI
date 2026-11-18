//  🖥️ TUI — A Terminal UI framework for Swift
//  OpacityRowReuseTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// ``OpacityRowReuse``: the screen root's resolution answers an unchanged row with
/// what it made of it last time, and draws exactly what a fresh one draws.
@MainActor
@Suite("Opacity row reuse")
struct OpacityRowReuseTests {

    private func palette() -> any Palette {
        makeRenderContext(width: 24, height: 4).environment.palette
    }

    /// Three rows: a faded label, a row no claim covers, and a translucent field.
    private func frame(label: String = "faded", field: String = "field") -> FrameBuffer {
        var buffer = FrameBuffer(lines: [
            ANSIRenderer.colorize(label, foreground: .rgb(40, 200, 40)),
            "plain",
            ANSIRenderer.colorize(field, foreground: .rgb(200, 40, 40), background: .rgb(20, 20, 200)),
        ])
        buffer.opacityRegions = [
            OpacityRegion(offsetX: 0, offsetY: 0, width: 5, height: 1, opacity: 0.5),
            OpacityRegion(offsetX: 0, offsetY: 2, width: 5, height: 1, opacity: 1, fieldOpacity: 0.3),
        ]
        return buffer
    }

    private let inputs = OpacityRowReuse.Inputs(
        surface: .rgb(0, 0, 0), defaultForeground: .rgb(255, 255, 255), statingTheSurface: true,
        fillingStatedTerminalField: false)

    @Test("A frame resolved through the reuse draws what a fresh resolution draws, frame after frame")
    func reusedFramesMatchFreshOnes() {
        let palette = palette()
        let reuse = OpacityRowReuse()
        let frames = [
            frame(), frame(), frame(label: "fadeD"), frame(label: "fadeD"), frame(field: "fiel!"), frame(),
        ]
        for (index, buffer) in frames.enumerated() {
            let fresh = buffer.resolvingOpacity(surface: .rgb(0, 0, 0), palette: palette, images: nil)
            let reused = buffer.resolvingOpacity(
                surface: .rgb(0, 0, 0), palette: palette, images: nil, reusing: reuse)
            #expect(reused.lines == fresh.lines, "frame \(index)")
            #expect(reused.opacityRegions.isEmpty)
        }
        // And against another surface, which every kept row was resolved without.
        let buffer = frame()
        #expect(
            buffer.resolvingOpacity(surface: .rgb(90, 0, 0), palette: palette, images: nil, reusing: reuse).lines
                == buffer.resolvingOpacity(surface: .rgb(90, 0, 0), palette: palette, images: nil).lines)
    }

    /// The rebuilds the reuse asks for, by row, over one resolution of `buffer`.
    private func rebuilds(
        of buffer: FrameBuffer, _ reuse: OpacityRowReuse, under inputs: OpacityRowReuse.Inputs? = nil
    ) -> [Int] {
        var asked: [Int] = []
        var lines = buffer.lines
        reuse.rebuild(&lines, claims: buffer.opacityRegions, under: inputs ?? self.inputs) { row, line, _ in
            asked.append(row)
            return line + "!"
        }
        return asked
    }

    @Test("Only a row whose line or claims changed is rebuilt again")
    func onlyChangedRowsAreRebuilt() {
        let reuse = OpacityRowReuse()
        #expect(rebuilds(of: frame(), reuse) == [0, 2])
        #expect(rebuilds(of: frame(), reuse).isEmpty)
        #expect(rebuilds(of: frame(label: "fadeD"), reuse) == [0])
        var moved = frame(label: "fadeD")
        moved.opacityRegions[1].fieldOpacity = 0.4
        #expect(rebuilds(of: moved, reuse) == [2])
        // Other inputs: every row.
        var other = inputs
        other.surface = .rgb(1, 2, 3)
        #expect(rebuilds(of: moved, reuse, under: other) == [0, 2])
        reuse.removeAll()
        #expect(rebuilds(of: moved, reuse, under: other) == [0, 2])
    }

    @Test("A kept row answers with what its rebuild made of it, a line left alone included")
    func keptAnswersAreTheRebuilds() {
        let reuse = OpacityRowReuse()
        let buffer = frame()
        var first = buffer.lines
        reuse.rebuild(&first, claims: buffer.opacityRegions, under: inputs) { row, line, _ in
            row == 0 ? line + "!" : nil
        }
        var second = buffer.lines
        reuse.rebuild(&second, claims: buffer.opacityRegions, under: inputs) { _, _, _ in "never" }
        #expect(second == first)
        #expect(second[0] == buffer.lines[0] + "!")
        #expect(second[2] == buffer.lines[2])
    }

    @Test("A row drawing a picture is rebuilt on every frame")
    func pictureRowsAreNeverKept() {
        let reuse = OpacityRowReuse()
        var buffer = frame()
        buffer = buffer.replacingLines([
            buffer.lines[0], buffer.lines[1], String(Character(Unicode.Scalar.terminalImagePlaceholder)) + "pic",
        ])
        #expect(rebuilds(of: buffer, reuse) == [0, 2])
        #expect(rebuilds(of: buffer, reuse) == [2])
    }
}
