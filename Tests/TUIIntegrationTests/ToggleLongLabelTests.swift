//  🖥️ TUI — A Terminal UI framework for Swift
//  ToggleLongLabelTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
import TUITesting

/// A toggle whose label is wider than its space wraps it, as a `Text` does and
/// as SwiftUI's checkbox does, rather than cutting it off.
@MainActor
@Suite("A toggle's long label wraps")
struct ToggleLongLabelTests {
    @Test("Every word of a long label is drawn")
    func wraps() {
        let app = TestApp(width: 40, height: 8) {
            VStack(alignment: .leading) {
                Toggle("Simulate an ssh session, to see the panels' notice that they browse another machine", isOn: .constant(false))
                Text("after")
            }
        }
        #expect(app.screen.contains("machine"), "\(app.screen)")
    }

    @Test("Squeezed narrower than one word, the word breaks rather than being cut")
    func squeezed() {
        let app = TestApp(width: 30, height: 6) {
            Toggle("AsyncImage", isOn: .constant(false)).frame(width: 7, alignment: .leading)
        }
        // Each row past the indicator's two columns, in order: the label, whole.
        let label = app.screen.lines.map { String($0.dropFirst(2)) }.joined()
        #expect(label.contains("AsyncImage"), "\(app.screen)")
    }
}
