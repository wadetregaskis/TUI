//  🖥️ TUI — A Terminal UI framework for Swift
//  ClosedAlertRowMemoTests.swift
//
//  A row carrying an `.alert` nobody presents is served from the row memo like
//  any other, and the alert still presents, dismisses and gives the focus back.
//  A closed alert declared a render side effect on EVERY frame — for the
//  section a just-dismissed alert may leave to tear down — so no memo above it
//  stored: fifty rows each carrying one were composed again on every frame.
//  Only the frame that tears the section down has a side effect now.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
import TUITesting
@testable import TUITestSupport

/// Which row's alert is up, if any.
@Observable
@MainActor
private final class Rows {
    var presented: Int?
    var deleted: [Int] = []
}

private struct RowsApp: App {
    let rows: Rows?

    init() { rows = nil }

    init(_ rows: Rows) { self.rows = rows }

    var body: some Scene {
        WindowGroup {
            if let rows { RowsPage(rows: rows) }
        }
    }
}

private struct RowsPage: View {
    let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Top") {}
            ForEach(0..<ClosedAlertRowMemoTests.rowCount, id: \.self) { index in
                Text(verbatim: "row \(index)")
                    .alert("Delete row \(index)?", isPresented: presented(index)) {
                        Button("Delete", role: .destructive) { rows.deleted.append(index) }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
    }

    private func presented(_ index: Int) -> Binding<Bool> {
        let rows = rows
        return Binding(
            get: { rows.presented == index },
            set: { if !$0, rows.presented == index { rows.presented = nil } })
    }
}

@MainActor
private final class Harness {
    let rows = Rows()
    let app: TestApp
    private var now: Int64 = 0

    init() {
        app = TestApp(RowsApp(rows), width: 40, height: ClosedAlertRowMemoTests.rowCount + 6)
        for _ in 0..<3 { frame() }
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var rendered: Int { app.renderCache.rowWork.rendered }

    /// Rows composed over `count` idle frames.
    func idle(_ count: Int = 3) -> Int {
        let rendered = self.rendered
        for _ in 0..<count { frame() }
        return self.rendered - rendered
    }
}

@MainActor
@Suite("Rows carrying a closed alert, served from the row memo", .rendersEnglishUI)
struct ClosedAlertRowMemoTests {
    static let rowCount = 50

    @Test("Fifty rows each carrying a closed alert compose nothing over three idle frames")
    func closedAlertRowsAreServed() {
        let harness = Harness()
        #expect(harness.app.screen.contains("row 49"), "every row is on screen")
        let idle = harness.idle()
        #expect(idle == 0, "composed \(idle) rows over three idle frames")
    }

    @Test("A served row's alert presents, Escape dismisses it, and the focus goes back to the page")
    func presentsAndDismisses() throws {
        let harness = Harness()
        let pageFocus = try #require(harness.app.focusedID, "the page's button holds the focus")

        harness.rows.presented = 7
        harness.frame()
        #expect(harness.app.screen.contains("Delete row 7?"), "the alert did not present")
        #expect(harness.app.focusedID != pageFocus, "the alert took the focus")

        _ = harness.app.send(KeyEvent(key: .escape))
        let before = harness.rendered
        harness.frame()
        #expect(harness.rows.presented == nil, "Escape did not dismiss the alert")
        #expect(!harness.app.screen.contains("Delete row 7?"), "the alert is still drawn")
        // The frame that tears the alert's section down gives the focus back
        // to the page, which only the section's teardown does.
        #expect(harness.app.focusedID == pageFocus, "the focus is \(harness.app.focusedID ?? "nil")")
        #expect(harness.rendered > before, "the dismissed row was served, so nothing tore its section down")

        // The teardown declared its side effect on that frame alone, which kept
        // that row, and what holds it, out of the memo: composed again on the
        // next frame, the only ones, and stored there. Two frames are given to
        // settle: one subtree more is composed once after a dismissal, and not
        // for the alert (before this was fixed, the three idle frames after a
        // dismissal composed 151 rows, not 150).
        let afterTeardown = harness.rendered
        harness.frame()
        harness.frame()
        let next = harness.rendered - afterTeardown
        #expect(next > 0 && next < ClosedAlertRowMemoTests.rowCount, "composed \(next) rows in two frames after the teardown")
        let idle = harness.idle()
        #expect(idle == 0, "composed \(idle) rows over three idle frames after dismissal")
        #expect(harness.app.focusedID == pageFocus)
    }

    @Test("A served row's alert presents again after its button answered it")
    func presentsAgainAfterAnAnswer() {
        let harness = Harness()
        harness.rows.presented = 3
        harness.frame()
        #expect(harness.app.screen.contains("Delete row 3?"))
        _ = harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.rows.presented == nil, "Return answered the alert")
        harness.frame()
        harness.frame()
        harness.rows.presented = 3
        harness.frame()
        #expect(harness.app.screen.contains("Delete row 3?"), "the alert did not present a second time")
    }
}
