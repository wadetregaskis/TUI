//  🖥️ TUI — A Terminal UI framework for Swift
//  BorderInsetBackgroundTests.swift
//
//  The framework's bordered chrome (`bordered(…, insetsContent: true)`: a
//  menu, a popover, a toast, `Box`) puts its inset beneath the background of
//  the view it borders, so the background reaches the line as SwiftUI's does
//  (GLASS-BORDER-GAP (a), 2026-10-27). An app's `.border()` has no inset since
//  2026-11-17 (`BorderHugsContentTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A bordered box's inset takes its content's background")
struct BorderInsetBackgroundTests {
    /// Whether the cell at `column` of the middle row names a background.
    private func filled<V: View>(_ view: V, column: Int) -> Bool {
        let lines = renderToBuffer(view, context: makeRenderContext(width: 20, height: 5)).lines
        return lines[1].ansiSGRStateAt(visibleColumn: column).namesBackground
    }

    /// The chrome's box round `view`: the line and a blank cell either side.
    private func boxed<V: View>(_ view: V) -> some View {
        view.bordered(style: nil, colour: nil, width: 1, insetsContent: true)
    }

    @Test("A colour behind the content fills the inset up to the line")
    func colourFillsInset() {
        let view = boxed(Text("ab").background(Color.red))
        // │ab│ drawn as "│ ab │": the line at 0, the inset at 1, the text at 2.
        #expect(filled(view, column: 1), "the inset cell before the text")
        #expect(filled(view, column: 4), "the inset cell after it")
        #expect(!filled(view, column: 0), "not the line itself")
    }

    @Test("A background view fills the inset too")
    func layerFillsInset() {
        let view = boxed(Text("ab").background { Color.blue })
        #expect(filled(view, column: 1))
        #expect(filled(view, column: 4))
    }

    @Test("The bordered view is as wide as before")
    func sameSize() {
        let filledView = renderToBuffer(
            boxed(Text("ab").background(Color.red)), context: makeRenderContext(width: 20, height: 5))
        let plain = renderToBuffer(boxed(Text("ab")), context: makeRenderContext(width: 20, height: 5))
        #expect(filledView.width == plain.width)
        #expect(filledView.height == plain.height)
    }
}
