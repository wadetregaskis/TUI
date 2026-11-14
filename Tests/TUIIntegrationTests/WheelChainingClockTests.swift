//  🖥️ TUI — A Terminal UI framework for Swift
//  WheelChainingClockTests.swift
//
//  A nested scroller holds the wheel at its edge for `.scrollChainingDelay`
//  before passing it to the scroll view around it, and that delay is timed on
//  the clock events arrive on: in a `TestApp`, the test's own, which moves only
//  when told to. It read the real clock, so a `TestApp` could not chain the
//  wheel out of a list or a table at all — two seconds of real time never
//  pass between two ticks — and advancing the test's clock did nothing. Found
//  by the real-world screens (`RealWorld/ScrollingTablesScreens.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

@MainActor
@Suite("Wheel chaining is timed on the clock events arrive on")
struct WheelChainingClockTests {
    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    /// A short list or table framed in a scroll view, a footer far below it.
    private struct Page: View {
        let table: Bool

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        if table {
                            Table((1...12).map(Row.init)) { TableColumn("Name", value: \Row.name) }
                        } else {
                            List((1...12).map(Row.init)) { Text($0.name) }
                        }
                    }
                    .frame(height: 6)
                    ForEach(1...20, id: \.self) { Text("below \($0)") }
                }
            }
        }
    }

    @Test("Ticks at an inner scroller's end chain to the scroll view once the test's clock passes the delay",
          arguments: [false, true])
    func chainsOnTheTestClock(table: Bool) {
        let app = TestApp(width: 30, height: 10) { Page(table: table) }
        let inside = CellPoint(x: 3, y: 2)
        app.scroll(.down, by: 8, at: inside)
        #expect(app.screen.contains("row 12"), "the inner scroller did not reach its end:\n\(app.screen)")
        let held = app.screen
        app.scroll(.down, by: 1, at: inside)
        #expect(app.screen == held, "a tick within the delay chained:\n\(app.screen)")
        app.advance(by: .seconds(3))
        app.scroll(.down, by: 3, at: inside)
        #expect(app.screen.contains("below 5"), "the delay passed and the wheel still did not chain:\n\(app.screen)")
    }
}
