//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasTextIdentityTests.swift
//
//  Each text a `Canvas` draws keeps its state at its own place, and is
//  measured once (hunt H-47, LEAF-10).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

/// How often the texts beneath were measured and drawn.
private final class Tally: @unchecked Sendable {
    var measures = 0
    var draws = 0
}

/// Draws a text as it is, counting.
private struct Counting: TextRenderer {
    let tally: Tally
    var animatableData = EmptyAnimatableData()

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        tally.draws += 1
        for line in layout { ctx.draw(line) }
    }

    func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> ViewSize {
        tally.measures += 1
        return text.sizeThatFits(proposal)
    }
}

@MainActor
@Suite("Canvas: each text's place")
struct CanvasTextIdentityTests {
    @Test("A text drawn at its own size is measured once, not once to size it and again to draw it")
    func measuredOnce() {
        let tally = Tally()
        let canvas = Canvas { context, _ in
            context.draw(Text(verbatim: "ab"), at: .zero, anchor: .topLeading)
        }
        _ = canvasDrawn(canvas.textRenderer(Counting(tally: tally)), columns: 4, rows: 1)
        #expect(tally.draws > 0)
        #expect(tally.measures == tally.draws, "measures \(tally.measures), draws \(tally.draws)")
    }

    @Test("Two texts under a dissolving content transition do not dissolve from each other's drawing")
    func textsKeepTheirOwnState() throws {
        var context = makeRenderContext(width: 6, height: 1)
        context.environment.canAnimate = true
        context.environment.transaction = Transaction(animation: .linear(duration: 1))
        context.environment.contentDissolves = true
        let canvas = Canvas { context, _ in
            context.draw(Text(verbatim: "ab"), at: .zero, anchor: .topLeading)
            context.draw(Text(verbatim: "cd"), at: CGPoint(x: 3, y: 0), anchor: .topLeading)
        }
        let storage = try #require(context.environment.stateStorage)
        for _ in 0..<2 {
            storage.beginRenderPass()
            let buffer = ColorDepth.withCurrent(.truecolor) { renderToBuffer(canvas, context: context) }
            storage.endRenderPass()
            #expect(buffer.lines[0].stripped == "ab cd ", "each label its own: \(buffer.lines[0].stripped)")
        }
    }
}
