//  🖥️ TUI — A Terminal UI framework for Swift
//  VerifiedSubtreeKeepTests.swift
//
//  What is kept below a pane re-checked and served after a page's write
//  (VIEWR-4, O-21).
//
//  A page's `@State` write marks everything kept below the page suspect. The
//  walk re-checks the pane, finds its value and environment unchanged, and
//  serves it, visiting nothing below. The rows below it were never looked up,
//  so they were still suspect at the pass's end, and the prune dropped them:
//  the next change inside the pane, one row's, drew every row again. A suspect
//  below an entry a re-check found unchanged is drawn from what that entry was
//  drawn from, and nothing between them was written, so it is kept.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// Reaches the page's and the rows' `@State` from outside, between frames,
/// and counts the rows' bodies.
///
/// Setters, not `Binding`s: the views hold this object, and a `Binding` in
/// what a row holds, even inside a class, keeps the row from being re-checked.
@MainActor
private final class Handles {
    var setQuery: ((String) -> Void)?
    var setMark: [Int: (Bool) -> Void] = [:]
    /// The rows whose body ran, by id.
    var drawnRows: Set<Int> = []
}

private let rowCount = 200

/// A row with state of its own.
private struct Row: View {
    let id: Int
    let handles: Handles
    @State private var marked = false

    var body: some View {
        handles.drawnRows.insert(id)
        let binding = $marked
        handles.setMark[id] = { binding.wrappedValue = $0 }
        return Text(verbatim: "\(marked ? "*" : "-") row \(id)")
    }
}

extension Row: @preconcurrency Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// A pane of plain data: memoized whole by its value, and not changed by the
/// page's query.
private struct Sidebar: View {
    let count: Int
    let handles: Handles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { id in
                Row(id: id, handles: handles)
            }
        }
    }
}

/// The page: its query is written on each keystroke.
private struct Page: View {
    let handles: Handles
    @State private var query = ""

    var body: some View {
        let binding = $query
        handles.setQuery = { binding.wrappedValue = $0 }
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "query: \(query)")
            Sidebar(count: rowCount, handles: handles)
        }
    }
}

@MainActor
@Suite("What is kept below a pane re-checked after a page's write")
struct VerifiedSubtreeKeepTests {
    private func step(_ app: TestApp, _ frame: Int) {
        app.frame(atNanos: 1_000_000_000 + Int64(frame) * 16_666_667)
    }

    @Test("After the page's write, one row's write draws that row and no other")
    func oneRowAfterThePageWrite() {
        let handles = Handles()
        let app = TestApp(width: 30, height: 12) { Page(handles: handles) }
        for frame in 0..<3 { step(app, frame) }
        #expect(app.screen.contains("- row 3"), "precondition: \(app.screen)")

        let recheckedBefore = app.renderCache.revalidation.counts.rechecked
        handles.drawnRows = []
        handles.setQuery?("a")
        step(app, 3)
        #expect(app.screen.contains("query: a"))
        #expect(handles.drawnRows.isEmpty, "the page's write drew rows: \(handles.drawnRows.count)")
        #expect(
            app.renderCache.revalidation.counts.rechecked > recheckedBefore,
            "the pane was not re-checked and served, so this proved nothing")

        handles.drawnRows = []
        let renderedBefore = app.renderCache.rowWork.rendered
        handles.setMark[3]?(true)
        step(app, 4)
        #expect(app.screen.contains("* row 3"), "the row's write was not drawn: \(app.screen)")
        #expect(app.screen.contains("- row 4"))
        #expect(handles.drawnRows == [3], "rows drawn again: \(handles.drawnRows.count)")
        // The row, and the pane and page above the write: 202 before (VIEWR-4).
        let composed = app.renderCache.rowWork.rendered - renderedBefore
        #expect(composed <= 3, "memos composed: \(composed)")
    }

    @Test("A change inside the pane after the page's write is drawn, and so is the next")
    func changesAfterThePageWriteAreDrawn() {
        let handles = Handles()
        let app = TestApp(width: 30, height: 12) { Page(handles: handles) }
        for frame in 0..<3 { step(app, frame) }
        var frame = 3
        for round in 1...4 {
            handles.setQuery?(String(repeating: "q", count: round))
            step(app, frame)
            frame += 1
            handles.setMark[round]?(true)
            handles.setMark[round - 1]?(false)
            step(app, frame)
            frame += 1
            #expect(app.screen.contains("* row \(round)"), "round \(round): \(app.screen)")
            #expect(app.screen.contains("- row \(round - 1)"), "round \(round): \(app.screen)")
        }
    }

    @Test("With re-checked rows not served, the same writes are drawn: the control")
    func controlWithoutRecheckedServes() {
        let handles = Handles()
        let app = TestApp(width: 30, height: 12) { Page(handles: handles) }
        app.renderCache.revalidation.servesRechecked = false
        for frame in 0..<3 { step(app, frame) }
        handles.setQuery?("a")
        step(app, 3)
        handles.setMark[3]?(true)
        step(app, 4)
        #expect(app.screen.contains("* row 3"))
        #expect(app.screen.contains("query: a"))
    }
}
