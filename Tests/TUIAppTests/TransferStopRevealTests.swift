//  🖥️ TUI — A Terminal UI framework for Swift
//  TransferStopRevealTests.swift
//
//  The focus stop a `.draggable` or a `.dropDestination` gives content that
//  has none of its own is brought into sight in a scroll view when Tab
//  reaches it, as a `.focusable()` view is. Its region carried no focus id,
//  so the scroll view found nothing to reveal: the focus went below the fold
//  and stayed there unseen, and Copy or Paste there acted on a view the user
//  could not see.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
import TUICore
import TUIFoundation
import TUITesting

@MainActor
private final class DropLog {
    var dropped: [String] = []
}

private struct Board: View {
    let log: DropLog
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("chip").draggable("payload")
                ForEach(0..<10, id: \.self) { Text("filler \($0)") }
                Text("ZONE").dropDestination(for: String.self) { items, _ in
                    log.dropped += items
                    return true
                }
            }
        }
    }
}

private struct SourceBelow: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("top") {}
                ForEach(0..<10, id: \.self) { Text("filler \($0)") }
                Text("CHIP").draggable("payload")
            }
        }
    }
}

@MainActor
@Suite("A drag's own focus stop in a scroll view")
struct TransferStopRevealTests {
    private func drawn(_ app: TestApp) -> String { app.screen.lines.joined(separator: "\n") }

    @Test("Tab to a draggable below the fold scrolls it into sight")
    func draggableRevealed() {
        let app = TestApp(width: 20, height: 5) { SourceBelow() }
        app.press(.tab)
        #expect(app.screen.contains("CHIP"), "\(drawn(app))")
    }

    @Test("Tab to a drop destination below the fold scrolls it into sight")
    func destinationRevealed() {
        let app = TestApp(width: 20, height: 5) { Board(log: DropLog()) }
        app.press(.tab)
        #expect(app.screen.contains("ZONE"), "\(drawn(app))")
    }
}
