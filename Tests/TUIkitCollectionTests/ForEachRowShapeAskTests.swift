//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ForEachRowShapeAskTests.swift
//
//  How a `ForEach`'s rows map onto a list's rows is a property of the row
//  TYPE (`ForEach.rowShape(sectionWholeness:)`, decisions B15), so a list
//  asks it once for all the rows it reads — not once per row, which cost a
//  conformance test (and, for a provider row, its static count) on every row
//  of every section's loop, every frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitTestSupport
@testable import TUIkitView

/// How many times a row type's shape was asked.
@MainActor
private enum ShapeAsks {
    static var count = 0
}

/// A row that is a provider of one view, counting each time its static member
/// count — the row shape's question — is asked.
private struct CountedRow: View, ChildViewProvider, StaticMemberCounting {
    let label: String

    var body: some View { Text(label) }

    func childViews(context: RenderContext) -> [ChildView] { [ChildView(Text(label))] }

    static var staticMemberCount: Int? {
        ShapeAsks.count += 1
        return 1
    }
}

@MainActor
@Suite("A list asks a loop's row shape once, not per row")
struct ForEachRowShapeAskTests {

    @Test("A Section's loop of fifty rows asks its row shape a few times, not once a row")
    func sectionLoop() {
        ShapeAsks.count = 0
        let section = Section { ForEach(0..<50, id: \.self) { CountedRow(label: "row \($0)") } }
        let extracted: SectionContentRows<Int> = section.extractSectionContentRows(
            context: makeRenderContext(width: 30, height: 8))
        #expect(extracted.rows.count == 50)
        #expect(ShapeAsks.count < 10, "asked \(ShapeAsks.count) times for 50 rows")
    }

    @Test("A List's loop of fifty rows asks its row shape a few times, not once a drawn row")
    func windowedLoop() {
        ShapeAsks.count = 0
        _ = renderToBuffer(
            List { ForEach(0..<50, id: \.self) { CountedRow(label: "row \($0)") } }.frame(height: 20),
            context: makeRenderContext(width: 30, height: 20))
        #expect(ShapeAsks.count < 10, "asked \(ShapeAsks.count) times")
    }

    @Test("A Section's loop of EmptyView rows makes no rows, as the loop's row count says")
    func emptyRows() {
        let loop = ForEach(0..<4, id: \.self) { _ in EmptyView() }
        #expect(loop.listRowCount == 0)
        let section = Section { loop }
        let extracted: SectionContentRows<Int> = section.extractSectionContentRows(
            context: makeRenderContext(width: 30, height: 8))
        #expect(extracted.rows.isEmpty, "\(extracted.rows.count) rows")
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(String?.none)) { Section("S") { ForEach(["a", "b"], id: \.self) { _ in EmptyView() } } }
                .frame(height: 8))
        // The header alone: no invisible row for the cursor to stop on.
        #expect(fixture.handler?.itemCount == 1)
    }
}
