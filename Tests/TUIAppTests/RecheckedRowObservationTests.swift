//  🖥️ TUI — A Terminal UI framework for Swift
//  RecheckedRowObservationTests.swift
//
//  A `ForEach` row re-checked and served goes on observing what its closure
//  read.
//
//  A row's closure is built under an observation scope that reports to the
//  row's parent, so a write to what the closure read re-checks the rows: each
//  is built again and compared with what it was drawn from, and served where
//  it is equal. That second build ran under no scope. The first scope had
//  fired, and fires once; so after one write that left every row on screen
//  equal, nothing watched what the closures read, and the next write, which
//  did change a row, was never drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// What a sidebar's rows mark themselves by: read in the `ForEach` closure,
/// and by no body.
@Observable
private final class Selection {
    var current = 0
    /// A title per row id, read the same way.
    var titles: [Int: String] = [:]
}

private struct Entry: Identifiable, Equatable {
    let id: Int
    var name: String { "row\(id)" }
}

private let entries = (0..<4).map(Entry.init)

/// The master-detail sidebar: its body reads nothing of `selection`; each
/// row's closure does.
private struct Sidebar: View {
    let selection: Selection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                HStack(spacing: 0) {
                    Text(selection.current == entry.id ? ">" : "-")
                    Text(entry.name)
                    Text(selection.titles[entry.id] ?? "")
                }
            }
        }
    }
}

@MainActor
@Suite("A re-checked ForEach row still observes what its closure read")
struct RecheckedRowObservationTests {
    /// Draws the frame the app asked for, if it asked for one.
    /// - Returns: Whether it had.
    @discardableResult
    private func drawAskedFrame(_ app: TestApp, atNanos nanos: Int64) -> Bool {
        guard app.takeFrameRequest() else { return false }
        app.frame(atNanos: nanos)
        return true
    }

    @Test("After a write that leaves every row equal, a write that changes a row is drawn")
    func writeAfterAnAllEqualRecheckIsDrawn() {
        let selection = Selection()
        let app = TestApp(width: 20, height: 6) { Sidebar(selection: selection) }
        app.frame(atNanos: 0)
        #expect(app.screen.contains(">row0"))

        // The first write moves the mark, so a row is drawn again: the
        // ordinary case, which has always worked.
        selection.current = 1
        #expect(drawAskedFrame(app, atNanos: 1))
        #expect(app.screen.contains(">row1"))
        #expect(app.screen.contains("-row0"))

        // A row out of sight: every row on screen is rebuilt, compared equal
        // and served.
        let recheckedBefore = app.renderCache.revalidation.counts.rechecked
        selection.titles[40] = "elsewhere"
        #expect(drawAskedFrame(app, atNanos: 2))
        #expect(
            app.renderCache.revalidation.counts.rechecked >= recheckedBefore + entries.count,
            "the rows were not re-checked and served, so this proved nothing")

        // And one in sight.
        selection.current = 3
        #expect(drawAskedFrame(app, atNanos: 3), "the write asked for no frame")
        #expect(app.screen.contains(">row3"), "the row was served as it was drawn before the write")
        #expect(app.screen.contains("-row1"))
    }

    @Test("Every write after any number of all-equal re-checks is drawn")
    func writesAfterManyAllEqualRechecksAreDrawn() {
        let selection = Selection()
        let app = TestApp(width: 20, height: 6) { Sidebar(selection: selection) }
        app.frame(atNanos: 0)
        var nanos: Int64 = 0
        for round in 1...6 {
            for step in 0..<3 {
                nanos += 1
                selection.titles[40 + step] = "elsewhere \(round)"
                #expect(drawAskedFrame(app, atNanos: nanos), "round \(round): an unseen write asked for no frame")
            }
            nanos += 1
            let chosen = round % entries.count
            selection.current = chosen
            selection.titles[chosen] = "!\(round)"
            #expect(drawAskedFrame(app, atNanos: nanos), "round \(round): the write asked for no frame")
            #expect(app.screen.contains(">row\(chosen)!\(round)"), "round \(round): \(app.screen)")
        }
    }

    @Test("With re-checked rows not served, the same writes are drawn: the control")
    func controlWithoutRecheckedServes() {
        let selection = Selection()
        let app = TestApp(width: 20, height: 6) { Sidebar(selection: selection) }
        app.renderCache.revalidation.servesRechecked = false
        app.frame(atNanos: 0)
        selection.titles[40] = "elsewhere"
        drawAskedFrame(app, atNanos: 1)
        selection.current = 3
        #expect(drawAskedFrame(app, atNanos: 2))
        #expect(app.screen.contains(">row3"))
    }
}
