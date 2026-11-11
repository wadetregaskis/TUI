//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppHandOffTests.swift
//
//  `\.handOffTerminal` in an app with no terminal to hand over: a test's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

/// A button that hands the terminal over, and shows what the closure gave.
private struct Editor: View {
    @Environment(\.handOffTerminal) private var handOffTerminal
    @State private var note = "draft"
    @State private var failure = ""

    private struct Refused: Error {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note: \(note)")
            Text("Failure: \(failure)")
            Button("Edit") {
                note = handOffTerminal { note + ", edited" }
            }
            .focusID("edit")
            Button("Fail") {
                do {
                    try handOffTerminal { () throws(Refused) in throw Refused() }
                } catch {
                    failure = "refused"
                }
            }
            .focusID("fail")
        }
    }
}

@MainActor
@Suite("TestApp: handing the terminal over")
struct TestAppHandOffTests {
    @Test("With no terminal to hand over, the closure just runs, and its value comes back")
    func closureRuns() {
        let app = TestApp(width: 40, height: 4) { Editor() }
        #expect(app.press(.space))
        #expect(app.screen.contains("Note: draft, edited"))
        app.press(.space)
        #expect(app.screen.contains("Note: draft, edited, edited"))
    }

    @Test("What the closure throws comes back out of the action")
    func errorComesBack() {
        let app = TestApp(width: 40, height: 4) { Editor() }
        app.press(.tab)
        #expect(app.focusedID == "fail")
        app.press(.space)
        #expect(app.screen.contains("Failure: refused"))
    }
}
