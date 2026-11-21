//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameSqueezedAlignmentTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

/// A frame whose minimum is larger than it is offered is cut to the offer by
/// the universal clamp, which keeps the leading columns and the top rows. Its
/// alignment must place the content in what survives that cut, not in the
/// unsqueezed frame: centred in a 20-wide frame cut to 12, an 11-wide text
/// was drawn four columns in and lost its last three letters, and the macOS
/// boilerplate `.frame(minWidth: 400, minHeight: 300)` drew a blank 80×24.
@MainActor
@Suite("A frame squeezed below its minimum")
struct FrameSqueezedAlignmentTests {

    @Test("Across: the content is centred in the columns that survive the cut")
    func squeezedWidthCentresInTheOffer() {
        let view = Text("Hello world").frame(minWidth: 20)
        let buffer = renderToBuffer(view, context: makeBareRenderContext(width: 12, height: 3))
        #expect(buffer.lines.map(\.stripped) == ["Hello world "])
    }

    @Test("Down: the content is centred in the rows that survive the cut")
    func squeezedHeightCentresInTheOffer() {
        let view = Text("Hi").frame(minHeight: 10)
        let buffer = renderToBuffer(view, context: makeBareRenderContext(width: 10, height: 4))
        #expect(buffer.lines.map(\.stripped).map { $0.trimmingTrailingSpaces } == ["", "Hi", "", ""])
    }

    @Test("A minimum in points on an 80×24 screen draws its content in the middle, not a blank screen")
    func pointMinimumOnATerminalScreen() {
        let view = Text("Hi").frame(minWidth: 400, minHeight: 300)
        let buffer = renderToBuffer(view, context: makeBareRenderContext(width: 80, height: 24))
        let lines = buffer.lines.map(\.stripped)
        #expect(lines.count == 24)
        let row = lines.firstIndex { $0.contains("Hi") }
        #expect(row == 11)
        #expect(row.map { lines[$0].hasPrefix(String(repeating: " ", count: 39) + "Hi") } == true)
    }

    @Test("Trailing alignment puts the content at the trailing edge of what is drawn")
    func squeezedTrailingAlignment() {
        let view = Text("abc").frame(width: 20, alignment: .trailing)
        let buffer = renderToBuffer(view, context: makeBareRenderContext(width: 8, height: 1))
        #expect(buffer.lines.map(\.stripped) == ["     abc"])
    }
}

extension String {
    fileprivate var trimmingTrailingSpaces: String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
