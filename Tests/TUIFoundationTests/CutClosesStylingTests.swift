//  🖥️ TUI — A Terminal UI framework for Swift
//  CutClosesStylingTests.swift
//
//  A cut through a styled run closes what it leaves open (H-37, CORE1-2). A
//  clip keeps the bytes before the cut cell and drops the rest, the run's own
//  reset with them; everything appended after the cut — a sibling, a gap, a
//  row's padding — then drew in the run's background or underline.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A cut through a styled run closes it")
struct CutClosesStylingTests {

    /// The netted styling in force at each column of `line`, one entry per
    /// cell: what a terminal fed the line draws each cell with.
    private func cellStyles(_ line: String) -> [SGRState] {
        var state = SGRState()
        var styles: [SGRState] = []
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { state.apply(sequence) }
            case .visible(let character):
                for _ in 0..<max(0, character.terminalWidth) { styles.append(state) }
            }
            return true
        }
        return styles
    }

    @Test("A sibling after a clamped, filled child is not drawn on its fill")
    func siblingAfterClampIsNotFilled() throws {
        // The child renders wider than the five cells it is given, and the
        // clamp every child goes through cuts it there, through the blue run.
        let view = HStack(spacing: 2) {
            Text("AAAAAAAAAAAA").fixedSize().background(.blue).frame(width: 5, alignment: .leading)
            Text("B")
        }
        let buffer = renderToBuffer(view, context: makeRenderContext(width: 10, height: 1))
        let line = try #require(buffer.lines.first)
        let styles = cellStyles(line)
        let column = try #require(line.stripped.firstIndex(of: "B"), "\(line.debugDescription)")
            .utf16Offset(in: line.stripped)
        #expect(styles[column].backgroundColour == nil, "\(line.debugDescription)")
        // And the line ends closed, so the writer's padding after it is not blue.
        #expect(!line.leavesSGROpen, "\(line.debugDescription)")
    }

    @Test("A clamp closes a run it cuts, and leaves a closed line's bytes alone")
    func clampClosesOnce() {
        let open = FrameBuffer(lines: ["\u{1B}[44mAAAA\u{1B}[0m"]).clamped(toWidth: 2, height: 1)
        #expect(open.lines[0] == "\u{1B}[44mAA\u{1B}[0m")
        let closed = FrameBuffer(lines: ["\u{1B}[44mAA\u{1B}[0mBB"]).clamped(toWidth: 3, height: 1)
        #expect(closed.lines[0] == "\u{1B}[44mAA\u{1B}[0mB")
        let plain = FrameBuffer(lines: ["ABCD"]).clamped(toWidth: 2, height: 1)
        #expect(plain.lines[0] == "AB")
    }
}
