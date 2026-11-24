//  🖥️ TUI — A Terminal UI framework for Swift
//  ClosedSheetRowMemoTests.swift
//
//  A row carrying a `.sheet` nobody presents is served from the row memo, and
//  a sheet the app presents from a served row is still docked on the first
//  frame it is drawn (B-MODALS-1). A dismissed sheet posts the dock it would
//  take, every frame, for the root to lay the page out by before the walk; a
//  served row makes that post again from its journal. It declared a render
//  side effect on every frame instead, as did the `onChange` that runs a sheet's
//  `onDismiss`, attached when there was none, so no row carrying a sheet was
//  ever stored.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// Which row's sheet is up, if any.
@Observable
@MainActor
private final class SheetRows {
    var presented: Int?
}

private struct SheetRowsApp: App {
    let rows: SheetRows?

    init() { rows = nil }

    init(_ rows: SheetRows) { self.rows = rows }

    var body: some Scene {
        WindowGroup {
            if let rows { SheetRowsPage(rows: rows) }
        }
    }
}

private struct SheetRowsPage: View {
    let rows: SheetRows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                Text("room \(proxy.size.height)")
            }
            ForEach(0..<ClosedSheetRowMemoTests.rowCount, id: \.self) { index in
                Text(verbatim: "row \(index)")
                    .sheet(isPresented: presented(index)) {
                        Panel("Sheet \(index)") { Text("sheet body") }
                            .presentationDetents([.height(6)])
                            .presentationBackgroundInteraction(.enabled)
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
    let rows = SheetRows()
    let app: TestApp
    private var now: Int64 = 0

    init() {
        app = TestApp(SheetRowsApp(rows), width: 40, height: 40)
        for _ in 0..<3 { frame() }
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var rendered: Int { app.renderCache.rowWork.rendered }

    /// The height the page's reader was given: what the dock left it.
    var room: Int? {
        app.screen.styledLines.lazy.compactMap { line -> Int? in
            let text = line.stripped
            guard let range = text.range(of: "room ") else { return nil }
            return Int(text[range.upperBound...].prefix { $0.isNumber })
        }.first
    }
}

@MainActor
@Suite("Rows carrying a closed sheet, served from the row memo")
struct ClosedSheetRowMemoTests {
    static let rowCount = 20

    @Test("Rows each carrying a closed sheet compose nothing over three idle frames")
    func closedSheetRowsAreServed() {
        let harness = Harness()
        let before = harness.rendered
        for _ in 0..<3 { harness.frame() }
        #expect(harness.rendered - before == 0, "composed \(harness.rendered - before) rows over three idle frames")
    }

    @Test("A sheet the app presents from a served row is docked on the first frame it is drawn")
    func appDrivenOpenFromAServedRowIsNotLate() throws {
        let harness = Harness()
        harness.frame()
        let full = try #require(harness.room, "the page says its height")

        harness.rows.presented = 4
        harness.frame()
        #expect(harness.app.screen.contains("Sheet 4"), "the sheet did not present")
        let docked = try #require(harness.room)
        #expect(docked < full, "the page was laid out at \(docked) rows under the sheet, as if undocked (\(full))")

        harness.rows.presented = nil
        harness.frame()
        #expect(!harness.app.screen.contains("Sheet 4"), "the sheet is still drawn")
        #expect(harness.room == full, "dismissed, the page took its rows back late")

        // Torn down on that frame, the row is stored on the next and served
        // after it, its dock still posted for the root.
        harness.frame()
        let before = harness.rendered
        for _ in 0..<3 { harness.frame() }
        #expect(harness.rendered - before == 0, "composed \(harness.rendered - before) rows after the dismissal")
        harness.rows.presented = 9
        harness.frame()
        #expect(harness.app.screen.contains("Sheet 9"), "the sheet did not present")
        #expect(harness.room.map { $0 < full } == true, "the second open was laid out late")
    }
}
