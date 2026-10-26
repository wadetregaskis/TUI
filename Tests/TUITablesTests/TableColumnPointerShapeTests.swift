//  🖥️ TUI — A Terminal UI framework for Swift
//  TableColumnPointerShapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITables
@testable import TUITestSupport

private struct Entry: Identifiable, Equatable {
    let id: Int
    var alpha: String { "a\(id)" }
    var beta: String { "b\(id)" }
}

/// The column's resize arrow over the gap after a resizable column's title,
/// where TUI's controls set their own shapes (decisions O12, B-O12-6).
@MainActor
@Suite("Table columns' pointer shapes")
struct TableColumnPointerShapeTests {
    @Test("The gap after a resizable column's title gives a column's arrow; the title does not")
    func columnGap() {
        let harness = PointerShapeHarness(controlShapes: true, width: 40, height: 8)
        let buffer = harness.frame(
            Table((1...3).map(Entry.init), columnCustomization: .constant(TableColumnCustomization<Entry>())) {
                TableColumn("Alpha", value: \.alpha).width(min: 4, ideal: 8, max: 30).customizationID("alpha")
                TableColumn("Beta", value: \.beta).width(min: 4, ideal: 8, max: 30).customizationID("beta")
            })
        guard let beta = harness.cell(of: "Beta", in: buffer), let alpha = harness.cell(of: "Alpha", in: buffer) else {
            Issue.record("the header was not drawn: \(buffer.lines.map(\.stripped))")
            return
        }
        #expect(harness.shape(atX: beta.x - 1, y: beta.y) == .columnResize)
        #expect(harness.shape(atX: alpha.x, y: alpha.y) == nil)
    }
}
