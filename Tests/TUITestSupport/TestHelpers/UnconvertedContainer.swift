//  🖥️ TUI — A Terminal UI framework for Swift
//  UnconvertedContainer.swift
//
//  A container the geometry prediction knows nothing about, for tests of what
//  a coordinate-space owner does when a reader's prediction misses.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

@testable import TUICore
@testable import TUIView

/// Draws its content `rows` rows down, without saying so before the content
/// renders (`RenderContext.placingChild(gradient:x:y:)`) — as a container an
/// app writes for itself does, and as every container the prediction rungs
/// have not converted does (design study A2 §6). A reader inside it is
/// predicted `rows` rows too high until its residual has carried the shift:
/// the shape that makes an owner correct.
struct UnconvertedContainer<Content: View>: View, Renderable {
    let rows: Int
    let content: Content

    init(rows: Int = 1, @ViewBuilder content: () -> Content) {
        self.rows = rows
        self.content = content()
    }

    var body: Never { fatalError("UnconvertedContainer renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        var shifted = context
        shifted.availableHeight = max(0, context.availableHeight - rows)
        let drawn = TUIView.renderToBuffer(content, context: shifted)
        var result = FrameBuffer(emptyWithHeight: rows)
        result.appendVertically(drawn, spacing: 0)
        return result
    }
}

#endif
