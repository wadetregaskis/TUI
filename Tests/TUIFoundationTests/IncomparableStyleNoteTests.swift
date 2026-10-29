//  🖥️ TUI — A Terminal UI framework for Swift
//  IncomparableStyleNoteTests.swift
//
//  A style or a text renderer that is not `Equatable` cannot be compared, and
//  the environment's slot tracking has an answer for that: `.incomparable`,
//  which declines the memos below. `StyleChain` and `AnyTextRenderer` are
//  `Equatable` wrappers around such a value, and answered `false` for it, so the
//  tracking saw `.changed` on every pass and cleared the subtree — its buffers
//  and its sizes — on every frame of an app that had changed nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// A custom primitive style with no `Equatable` conformance — the shape a style
/// holding a closure has.
private struct Outlined: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).border(.red)
    }
}

/// A text renderer with no `Equatable` conformance, which draws the text as it is.
private struct AsIs: TextRenderer {
    var animatableData = EmptyAnimatableData()

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout { ctx.draw(line) }
    }
}

/// The same, but `Equatable`: the control, whose slot compares as unchanged.
private struct AsIsEquatable: TextRenderer, Equatable {
    var animatableData = EmptyAnimatableData()

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout { ctx.draw(line) }
    }
}

@MainActor
@Suite("A style that cannot be compared is reported incomparable, not changed")
struct IncomparableStyleNoteTests {

    /// How many subtree clears each of `frames` frames of `view` ran, through one cache.
    private func clearsPerFrame(_ view: some View, frames: Int = 4) -> [Int] {
        let context = makeRenderContext(width: 30, height: 6)
        var clears: [Int] = []
        for frame in 0..<frames {
            if frame > 0 { context.renderCache?.beginRenderPass() }
            let before = context.renderCache?.stats.subtreeClears ?? 0
            _ = renderToBuffer(view, context: context)
            clears.append((context.renderCache?.stats.subtreeClears ?? 0) - before)
        }
        return clears
    }

    @Test("A primitive button style that is not Equatable clears nothing on a frame that changed nothing")
    func primitiveButtonStyleDoesNotClearEveryFrame() {
        let clears = clearsPerFrame(VStack { Button("Save") {} }.buttonStyle(Outlined()))
        #expect(clears.dropFirst(2).allSatisfy { $0 == 0 }, "unchanged frames cleared subtrees: \(clears)")
    }

    @Test("A text renderer that is not Equatable clears nothing on a frame that changed nothing")
    func textRendererDoesNotClearEveryFrame() {
        let clears = clearsPerFrame(VStack { Text("hello") }.textRenderer(AsIs()))
        #expect(clears.dropFirst(2).allSatisfy { $0 == 0 }, "unchanged frames cleared subtrees: \(clears)")
    }

    /// The slot's own answers: incomparable from the first note, for the wrapped
    /// value that cannot be compared, and unchanged for the one that can.
    @Test("The slot answers incomparable for a wrapper around a value that cannot be compared")
    func slotAnswersIncomparable() {
        let cache = RenderCache()
        let identity = ViewIdentity(path: "Root")
        func note(_ value: Any) -> RenderCache.EnvironmentChange {
            cache.noteAppliedEnvironment(
                value, identity: identity, keyPath: \EnvironmentValues.textRenderer, depth: 0)
        }
        #expect(note(AnyTextRenderer(AsIs())) == .incomparable)
        cache.beginRenderPass()
        #expect(note(AnyTextRenderer(AsIs())) == .incomparable)

        let control = RenderCache()
        func noteControl(_ value: Any) -> RenderCache.EnvironmentChange {
            control.noteAppliedEnvironment(
                value, identity: identity, keyPath: \EnvironmentValues.textRenderer, depth: 0)
        }
        #expect(noteControl(AnyTextRenderer(AsIsEquatable())) == .first)
        control.beginRenderPass()
        #expect(noteControl(AnyTextRenderer(AsIsEquatable())) == .unchanged)
    }
}
