//  🖥️ TUI — A Terminal UI framework for Swift
//  NoColorReverseTests.swift
//
//  A focused control at no colour reverses part of its row; what follows the
//  part keeps the styling it had.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("Reverse video at no colour")
struct NoColorReverseTests {
    @Test("The row after a reversed span keeps the styling it was drawn in")
    func suffixKeepsStyling() {
        let line = "\u{1B}[1m[x] Label\u{1B}[0m"
        let reversed = ColorDepth.withCurrent(.noColor) {
            FrameBuffer(lines: [line])
                .reversedWithoutColor(if: true, columns: 1..<2, context: RenderContext(availableWidth: 20, availableHeight: 1))
                .lines[0]
        }
        #expect(reversed.stripped == "[x] Label")
        // The last cell, "l", is still bold after the reversed "x".
        var state = SGRState()
        var boldAtEnd = false
        _ = reversed.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { state.apply(sequence) }
            case .visible:
                boldAtEnd = state.isBold
            }
            return true
        }
        #expect(boldAtEnd, "\(reversed.debugDescription)")
    }
}
