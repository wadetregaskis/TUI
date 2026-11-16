//  🖥️ TUI — A Terminal UI framework for Swift
//  TableChromeMeasureMemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUITables
@testable import TUITestSupport
@testable import TUIView

/// A table measured more than once in a pass measures its chrome once.
///
/// The analytic measure sizes a table's border and header by measuring the
/// container around a stand-in for the rows, at the size the rows come to,
/// which is the same whatever height the table itself was offered. The pass's
/// measure memo answers the second ask of the same container — as long as its
/// key, which reads the addresses the value holds, comes out the same. It held
/// the header's line, a string built afresh for each ask, and the memo keeps
/// every value it stored a size for to the pass's end (so no address can name
/// two values), so each ask's line had its own buffer and missed: on
/// `app-shapes/fixed-size-table`, 14 more misses a frame and 7.4% more CPU.
@MainActor
@Suite("A Table's chrome is measured once a pass")
struct TableChromeMeasureMemoTests {
    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
        var size: String { "\(id * 1_024) bytes" }
    }

    /// The render loop's shape: an isolated cache and the volatile-read tracker
    /// whose presence turns the pass's measure memo on.
    private func memoisedContext() -> RenderContext {
        var context = makeRenderContext(width: 40, height: 24)
        let storage = StateStorage()
        context.environment.stateStorage = storage
        context.stateStorage = storage
        context.environment.installVolatileReadTracker(VolatileReadTracker())
        return context
    }

    @Test("A second ask with another proposal misses only the table, not its chrome")
    func chromeIsServedToTheSecondAsk() throws {
        let rows = (1...20).map(Row.init)
        let table = Table(rows) {
            TableColumn("Name", value: \.name)
            TableColumn("Size", value: \.size)
        }
        let context = memoisedContext()
        let cache = try #require(context.renderCache)

        let first = measureChild(table, proposal: ProposedViewSize(width: 40, height: nil), context: context)
        let afterFirst = cache.measureMemoTotals
        // Another proposal, so the table's own entry cannot answer and it
        // measures again: its chrome, at the same width and height as before,
        // can.
        let second = measureChild(table, proposal: ProposedViewSize(width: nil, height: nil), context: context)
        let afterSecond = cache.measureMemoTotals

        #expect(first == second)
        // The table, its two modifiers and its core miss again; the container
        // around the rows' stand-in, and the six views inside it, do not: 4
        // misses of the first ask's 11, where the header's line made it 10.
        let firstMisses = afterFirst.misses
        let secondMisses = afterSecond.misses - afterFirst.misses
        #expect(
            secondMisses * 2 <= firstMisses,
            "the second ask missed \(secondMisses) times, of the first's \(firstMisses)")
    }
}
