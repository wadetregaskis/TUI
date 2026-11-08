//  🖥️ TUI — A Terminal UI framework for Swift
//  DifferentiateWithoutColorTests.swift
//
//  Under Differentiate Without Colour a control says its state as it does at
//  no colour, over its colours: the focus reversed, disabled faint.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("Differentiate Without Colour")
struct DifferentiateWithoutColorTests {
    /// A context whose environment asks for cues beyond colour, or doesn't.
    private func context(differentiating: Bool) -> RenderContext {
        var environment = EnvironmentValues()
        environment._accessibilityDifferentiateWithoutColor = differentiating
        return RenderContext(availableWidth: 20, availableHeight: 1, environment: environment)
    }

    /// Every visible cell's state in `line`.
    private func states(of line: String) -> [SGRState] {
        var state = SGRState()
        var cells: [SGRState] = []
        _ = line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { state.apply(sequence) }
            case .visible:
                cells.append(state)
            }
            return true
        }
        return cells
    }

    private let line = "\u{1B}[38;2;200;30;30m[x]\u{1B}[0m Label"

    @Test("Said without colour at no colour, and over colours only when asked")
    func theGate() {
        let (unasked, asked) = ColorDepth.withCurrent(.truecolor) {
            (context(differentiating: false).statesWithoutColor, context(differentiating: true).statesWithoutColor)
        }
        let noColor = ColorDepth.withCurrent(.noColor) { context(differentiating: false).statesWithoutColor }
        #expect(!unasked)
        #expect(asked)
        #expect(noColor)
    }

    @Test("Asked, a disabled control is faint over its colours")
    func disabledFaint() {
        let (asked, unasked) = ColorDepth.withCurrent(.truecolor) {
            (
                FrameBuffer(lines: [line]).fadedWithoutColor(if: true, context: context(differentiating: true)).lines[0],
                FrameBuffer(lines: [line]).fadedWithoutColor(if: true, context: context(differentiating: false)).lines[0]
            )
        }
        #expect(states(of: asked).allSatisfy { $0.isFaint }, "\(asked.debugDescription)")
        #expect(unasked == line, "the colours keep the job unless asked")
    }

    @Test("Asked, the focus is reversed over its colours, the palette's pair restated")
    func focusReversed() {
        let (asked, unasked) = ColorDepth.withCurrent(.truecolor) {
            (
                FrameBuffer(lines: [line])
                    .reversedWithoutColor(if: true, columns: 4..<9, context: context(differentiating: true)).lines[0],
                FrameBuffer(lines: [line])
                    .reversedWithoutColor(if: true, columns: 4..<9, context: context(differentiating: false)).lines[0]
            )
        }
        let cells = states(of: asked)
        #expect(asked.stripped == "[x] Label")
        #expect(cells[0..<4].allSatisfy { !$0.reversesVideo }, "the mark isn't reversed")
        #expect(cells[4..<9].allSatisfy { $0.reversesVideo && $0.foregroundColour != nil }, "\(asked.debugDescription)")
        #expect(unasked == line)
    }
}
