//  🖥️ TUI — A Terminal UI framework for Swift
//  BorderInsetBackgroundTests.swift
//
//  A border's inset takes the background of the view it borders, so the
//  background reaches the line as SwiftUI's does (GLASS-BORDER-GAP (a),
//  2026-10-27); `.backgroundStopsAtContent()` keeps it clear.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A border's inset takes its content's background")
struct BorderInsetBackgroundTests {
    /// Whether the cell at `column` of the middle row names a background.
    private func filled<V: View>(_ view: V, column: Int) -> Bool {
        let lines = renderToBuffer(view, context: makeRenderContext(width: 20, height: 5)).lines
        return lines[1].ansiSGRStateAt(visibleColumn: column).namesBackground
    }

    @Test("A colour behind the content fills the inset up to the line")
    func colourFillsInset() {
        let view = Text("ab").background(Color.red).border()
        // │ab│ drawn as "│ ab │": the line at 0, the inset at 1, the text at 2.
        #expect(filled(view, column: 1), "the inset cell before the text")
        #expect(filled(view, column: 4), "the inset cell after it")
        #expect(!filled(view, column: 0), "not the line itself")
    }

    @Test("A background view fills the inset too")
    func layerFillsInset() {
        let view = Text("ab").background { Color.blue }.border()
        #expect(filled(view, column: 1))
        #expect(filled(view, column: 4))
    }

    @Test("Stopped at the content, the background leaves the inset clear")
    func stopsAtContent() {
        let view = Text("ab").background(Color.red).backgroundStopsAtContent().border()
        #expect(!filled(view, column: 1))
        #expect(filled(view, column: 2), "the content keeps it")
    }

    @Test("The bordered view is as wide as before")
    func sameSize() {
        let filledView = renderToBuffer(
            Text("ab").background(Color.red).border(), context: makeRenderContext(width: 20, height: 5))
        let plain = renderToBuffer(Text("ab").border(), context: makeRenderContext(width: 20, height: 5))
        #expect(filledView.width == plain.width)
        #expect(filledView.height == plain.height)
    }
}
