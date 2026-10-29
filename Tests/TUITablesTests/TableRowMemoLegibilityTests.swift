//  🖥️ TUI — A Terminal UI framework for Swift
//  TableRowMemoLegibilityTests.swift
//
//  A table keeps its rows' composed lines across frames (`TableRowMemo.swift`),
//  keyed on the row and on what the frame settles. Under a bold legibility
//  weight its cells are drawn a tier heavier — the introducer states bold, and
//  the close under a still fill ends it — and that weight is neither the row nor
//  anything the frame's key carried, so turning it on served every kept row in
//  its old weight.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUILists
import TUITables
@testable import TUITestSupport
@testable import TUIView

private struct Fruit: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

@MainActor
@Suite("A table's kept rows follow the legibility weight")
struct TableRowMemoLegibilityTests {
    private let fruit = (0..<6).map { Fruit(id: $0, name: "fruit \($0)") }

    /// Every column names its value, so the table keeps its rows.
    private var table: some View {
        Table(fruit) {
            TableColumn("Name", value: \Fruit.name)
        }
    }

    /// `frames` frames through one context, the last under `weight`.
    private func lines(_ context: RenderContext, frames: Int = 1, weight: LegibilityWeight?) -> [String] {
        var context = context
        context.environment.legibilityWeight = weight
        var drawn: [String] = []
        for _ in 0..<frames {
            context.renderCache?.beginRenderPass()
            drawn = renderToBuffer(table, context: context).lines
        }
        return drawn
    }

    @Test("Turning on a bold legibility weight redraws the rows a table kept")
    func keptRowsFollowTheWeight() {
        let warm = makeRenderContext(width: 30, height: 10)
        let regular = lines(warm, frames: 3, weight: nil)
        let bold = lines(warm, weight: .bold)
        let fresh = lines(makeRenderContext(width: 30, height: 10), frames: 3, weight: .bold)
        #expect(fresh != regular, "the weight must change the rows, or this proves nothing")
        #expect(bold == fresh, "the rows kept under the regular weight were served under the bold one")
    }
}
