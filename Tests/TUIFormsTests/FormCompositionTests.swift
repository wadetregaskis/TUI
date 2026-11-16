//  🖥️ TUI — A Terminal UI framework for Swift
//  FormCompositionTests.swift
//
//  A form reads its content into rows and measures them before it can lay
//  out its column, and is asked for that column by each measure and by the
//  draw. It does that once a pass at its place and width, and serves the
//  rest, while its value and environment stay the same
//  (`RenderCache.composedOncePerPass(for:context:_:)`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIForms
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// How many times a row's body was evaluated.
@MainActor
private final class BodyCount {
    var count = 0
}

/// A row of the app's own, which the form reads through its body.
private struct CountedRow: View {
    let index: Int
    let bodies: BodyCount

    var body: some View {
        bodies.count += 1
        return LabeledContent("Row \(index)") { Text("value \(index)") }
    }
}

@MainActor
@Suite("A form reads its content once a pass at one place")
struct FormCompositionTests {
    /// The render loop's shape: an isolated cache, state storage, and the
    /// volatile-read tracker whose presence turns the pass's memos on.
    private func memoisedContext(labels: Visibility = .automatic) -> RenderContext {
        var context = makeRenderContext(width: 40, height: 30)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        context.environment.formStyle = GroupedFormStyle()
        context.environment.labelsVisibility = labels
        return context
    }

    private func form(_ bodies: BodyCount) -> _FormLayout<some View> {
        _FormLayout(
            content: Section("Section") {
                ForEach(0..<3, id: \.self) { index in CountedRow(index: index, bodies: bodies) }
            })
    }

    @Test("Measured and drawn in one pass, a grouped form reads its rows once")
    func measureAndDrawShareOneComposition() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let bodies = BodyCount()
        let layout = form(bodies)
        let size = measureChild(layout, proposal: ProposedViewSize(width: 40, height: nil), context: context)
        let drawn = renderToBuffer(layout, context: context)

        #expect(cache.compositionCounts.kept == 1)
        #expect(cache.compositionCounts.served == 1)
        #expect(bodies.count == 3, "each row's body once, for the measure; the draw took the measure's rows")
        #expect(drawn.height == size.height)

        // The same picture as a form drawn with nothing kept.
        let plain = makeRenderContext(width: 40, height: 30) { environment, _ in
            environment.formStyle = GroupedFormStyle()
        }
        let fresh = renderToBuffer(form(BodyCount()), context: plain)
        #expect(drawn.lines.map(\.stripped) == fresh.lines.map(\.stripped))
    }

    @Test("A new pass reads the rows again")
    func aNewPassComposesAgain() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let bodies = BodyCount()
        let layout = form(bodies)
        _ = renderToBuffer(layout, context: context)
        cache.beginRenderPass()
        _ = renderToBuffer(layout, context: context)

        #expect(cache.compositionCounts.kept == 2)
        #expect(cache.compositionCounts.served == 0)
        #expect(bodies.count == 6)
    }

    @Test("Under an environment it can tell apart, the draw reads the rows itself")
    func aDifferentEnvironmentComposesAgain() throws {
        let hidden = memoisedContext(labels: .hidden)
        let cache = try #require(hidden.renderCache)
        var shown = hidden
        shown.environment.labelsVisibility = .visible
        let bodies = BodyCount()
        let layout = form(bodies)
        _ = measureChild(layout, proposal: ProposedViewSize(width: 40, height: nil), context: hidden)
        let drawn = renderToBuffer(layout, context: shown)

        #expect(cache.compositionCounts.served == 0)
        #expect(bodies.count == 6)
        #expect(drawn.lines.contains { $0.stripped.contains("Row 1") }, "the labels the draw's environment shows")
    }

    @Test("Laid out at another width, the form reads its rows for that width")
    func anotherWidthComposesAgain() throws {
        let context = memoisedContext()
        let cache = try #require(context.renderCache)
        let layout = form(BodyCount())
        _ = measureChild(layout, proposal: ProposedViewSize(width: 40, height: nil), context: context)
        _ = measureChild(layout, proposal: ProposedViewSize(width: 30, height: nil), context: context)

        #expect(cache.compositionCounts.kept == 2)
        #expect(cache.compositionCounts.served == 0)
    }
}
