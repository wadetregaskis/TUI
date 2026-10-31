//  🖥️ TUI — A Terminal UI framework for Swift
//  ColumnShareMeasureTests.swift
//
//  A column asked for its size measures a scroll view that gives way a second time,
//  in the share of the height the render deals it. A measure is a walk of the
//  child's content, so a column of columns must not pay for it at every level over
//  again.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// Counts how many times it is measured, at any size.
@MainActor
private final class MeasureCount {
    var count = 0
}

private struct CountedRows: View, Renderable, Layoutable {
    let counter: MeasureCount
    var body: Never { fatalError("renders via Renderable") }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        counter.count += 1
        return ViewSize.fixed(6, 100)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        FrameBuffer(lines: Array(repeating: "row  x", count: 100))
    }
}

/// `depth` columns, one in another, each with a header over the next: every level's
/// rows pass the height, and every level's child gives way.
@MainActor
private func nested(depth: Int, counter: MeasureCount) -> AnyView {
    guard depth > 0 else { return AnyView(ScrollView { CountedRows(counter: counter) }) }
    return AnyView(VStack(alignment: .leading, spacing: 0) { Text("h"); nested(depth: depth - 1, counter: counter) })
}

@MainActor
@Suite("A column measures a squeezed child in its share")
struct ColumnShareMeasureTests {

    /// Twenty levels each asked twice was 1,821,191 walks of what is inside.
    @Test("A column of columns does not measure what is inside it once per way down")
    func nestedColumnsMeasureInBoundedWalks() {
        let counter = MeasureCount()
        let context = makeRenderContext(width: 30, height: 12)
        _ = measureChild(
            nested(depth: 20, counter: counter), proposal: ProposedSize(width: nil, height: nil), context: context)
        #expect(counter.count <= 200, "\(counter.count) measures of the rows")
    }
}
