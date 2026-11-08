//  🖥️ TUI — A Terminal UI framework for Swift
//  DisabledFaintTests.swift
//
//  Disabled is faint, and italic too where the host doesn't show faint: Warp
//  with a light background (the compatibility survey's faint table).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("Disabled where faint doesn't show")
struct DisabledFaintTests {
    /// Every visible cell's attributes in `line`: (faint, italic).
    private func attributes(of line: String) -> [(faint: Bool, italic: Bool)] {
        var state = SGRState()
        var cells: [(faint: Bool, italic: Bool)] = []
        _ = line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if isSGR { state.apply(sequence) }
            case .visible:
                cells.append((state.isFaint, state.isItalic))
            }
            return true
        }
        return cells
    }

    /// A line with a reset inside it, which a bare wrapper would die at.
    private let styledLine = "\u{1B}[1mOK\u{1B}[0m Cancel"

    @Test("Only Warp with a light background is said not to draw faint")
    func decision() {
        #expect(!TerminalClient.drawsFaint(on: .warp, prefersDark: false))
        #expect(TerminalClient.drawsFaint(on: .warp, prefersDark: true))
        #expect(TerminalClient.drawsFaint(on: .warp, prefersDark: nil))
        for program in TerminalClient.Program.allCases where program != .warp {
            #expect(TerminalClient.drawsFaint(on: program, prefersDark: false), "\(program)")
        }
    }

    @Test("At no colour, a disabled control is faint and italic in every cell where faint doesn't show")
    func italicWhereFaintIsLost() {
        let line = TerminalClient.$drawsFaintPin.withValue(false) {
            ColorDepth.withCurrent(.noColor) {
                FrameBuffer(lines: [styledLine]).fadedWithoutColor(if: true).lines[0]
            }
        }
        #expect(line.stripped == "OK Cancel")
        let cells = attributes(of: line)
        #expect(cells.count == 9)
        #expect(cells.allSatisfy { $0.faint && $0.italic }, "\(line.debugDescription)")
    }

    @Test("Where faint shows, a disabled control draws exactly what it did")
    func unchangedWhereFaintShows() {
        let line = TerminalClient.$drawsFaintPin.withValue(true) {
            ColorDepth.withCurrent(.noColor) {
                FrameBuffer(lines: [styledLine]).fadedWithoutColor(if: true).lines[0]
            }
        }
        #expect(line == ANSIRenderer.applyPersistentDim(styledLine))
        #expect(attributes(of: line).allSatisfy { $0.faint && !$0.italic })
    }

    @Test("At a colour depth an enabled or disabled control is left to its colours")
    func colourDepthLeftAlone() {
        let line = TerminalClient.$drawsFaintPin.withValue(false) {
            ColorDepth.withCurrent(.truecolor) {
                FrameBuffer(lines: [styledLine]).fadedWithoutColor(if: true).lines[0]
            }
        }
        #expect(line == styledLine)
    }

    @Test("A row drawn disabled at any depth is italic too where faint doesn't show")
    func drawnDisabledAtColour() {
        let line = TerminalClient.$drawsFaintPin.withValue(false) {
            ColorDepth.withCurrent(.truecolor) {
                FrameBuffer(lines: [styledLine]).drawnDisabled().lines[0]
            }
        }
        #expect(attributes(of: line).allSatisfy { $0.faint && $0.italic }, "\(line.debugDescription)")
    }
}
