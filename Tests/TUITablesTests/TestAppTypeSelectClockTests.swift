//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppTypeSelectClockTests.swift
//
//  Type select's pause runs on the clock a `TestApp` moves (tuitree's
//  feedback, Milestone 2 item 7): two type selects with `advance(by:)`
//  between them find a row each, where on the machine's clock they ran
//  together into one prefix that matched nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUILists
import TUITesting

private struct Letters: View {
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Selected: \(selection ?? "none")")
            List(selection: $selection) {
                ForEach(["sierra", "tango"], id: \.self) { Text($0) }
            }
            .selectionFollowsCursor()
        }
    }
}

@MainActor
@Suite("Type select on a TestApp's clock")
struct TestAppTypeSelectClockTests {
    @Test("A pause the test makes with advance(by:) starts a new prefix")
    func advanceSeparatesTwoTypeSelects() {
        let app = TestApp(width: 30, height: 8) { Letters() }
        app.press(.tab)
        app.type("t")
        #expect(app.screen.contains("Selected: tango"), "\(app.screen)")
        app.advance(by: .seconds(2))
        app.type("s")
        #expect(app.screen.contains("Selected: sierra"), "\(app.screen)")
    }

    @Test("Without a pause, the characters are one prefix, however long the test takes between them")
    func noAdvanceKeepsOnePrefix() {
        let app = TestApp(width: 30, height: 8) { Letters() }
        app.press(.tab)
        app.type("t")
        app.type("a")
        #expect(app.screen.contains("Selected: tango"), "\(app.screen)")
    }
}
