//  🖥️ TUI — A Terminal UI framework for Swift
//  BackgroundLayerTests.swift
//
//  `background(alignment:content:)`: a view laid out in the base's frame and
//  drawn behind it — the base's size, the base's glyphs in front, the
//  background's field wherever the base names none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("background(alignment:content:)")
struct BackgroundLayerTests {
    private func render<V: View>(_ view: V, width: Int = 20) -> FrameBuffer {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 5))
    }

    /// The first row's cells — glyph and SGR state — so two renders that state
    /// the same cells in a different escape order compare equal.
    private func cells<V: View>(_ view: V) -> [Cell] {
        var state = SGRState()
        var result: [Cell] = []
        for segment in (render(view).lines.first ?? "").ansiSegments() {
            switch segment {
            case .ansi(let sequence, true): state.apply(sequence)
            case .ansi: continue
            case .visible(let character): result.append(Cell(character: character, state: state))
            }
        }
        return result
    }

    private struct Cell: Equatable {
        let character: Character
        let state: SGRState
    }

    @Test("The base dominates layout: the result is the base's size")
    func baseDominatesLayout() {
        let view = Text("hi").background { Text("a much longer background") }
        let buffer = render(view)
        #expect(buffer.width == 2 && buffer.height == 1)
        #expect(buffer.lines.first?.stripped == "hi", "the base's glyphs are in front")
        let measured = measureChild(view, proposal: ProposedSize(width: 20, height: 5), context: makeRenderContext())
        #expect(measured.width == 2 && measured.height == 1)
    }

    @Test("A colour behind text is the text on that colour, as .background(_:) draws it")
    func colourBehindText() {
        #expect(cells(Text("hi").background { Color.red }) == cells(Text("hi").background(Color.red)))
    }

    @Test("Alignment places the background in the base's frame")
    func alignmentPlacesIt() {
        let partial = cells(Text("....").background(alignment: .leading) { Color.red.frame(width: 2) })
        let red = cells(Text("....").background(Color.red))
        let bare = cells(Text("...."))
        #expect(partial.count == 4)
        let partialHead: [Cell] = Array(partial.prefix(2)), redHead: [Cell] = Array(red.prefix(2))
        #expect(partialHead == redHead, "the first two cells carry the red field")
        let partialTail: [Cell] = Array(partial.suffix(2)), bareTail: [Cell] = Array(bare.suffix(2))
        #expect(partialTail == bareTail, "and the last two do not")
    }

    @Test("On an EmptyView neither a background nor an overlay is drawn, as in SwiftUI")
    func emptyBase() {
        #expect(render(EmptyView().background { Text("x") }).isEmpty)
        #expect(render(EmptyView().overlay { Text("x") }).isEmpty)
    }
}
