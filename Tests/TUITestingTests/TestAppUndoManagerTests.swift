//  🖥️ TUI — A Terminal UI framework for Swift
//  TestAppUndoManagerTests.swift
//
//  A `TestApp` has an undo manager, as a running app's window does: a view
//  reads it from `\.undoManager`, the undo keys reach it, and a test reads it
//  as `undoManager` (tuitree's feedback, Milestone 2 item 6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing
import TUITesting

@Observable
@MainActor
private final class Tally {
    var total = 0

    func add(undoManager: UndoManager?) {
        total += 1
        undoManager?.registerUndo(withTarget: self) { tally in
            MainActor.assumeIsolated { tally.total -= 1 }
        }
    }
}

private struct Adder: View {
    let tally: Tally
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Total: \(tally.total)")
            Text(verbatim: "Has undo manager: \(undoManager != nil)")
            Button("Add") { tally.add(undoManager: undoManager) }
        }
    }
}

@MainActor
@Suite("A TestApp's undo manager")
struct TestAppUndoManagerTests {
    @Test("A view reads the app's undo manager, and ⌃Z undoes what it registered")
    func undoKeysReachIt() {
        let tally = Tally()
        let app = TestApp(width: 30, height: 6) { Adder(tally: tally) }
        #expect(app.screen.contains("Has undo manager: true"), "\(app.screen)")
        app.press(.space)
        #expect(tally.total == 1)
        #expect(app.undoManager.canUndo)
        app.press(.character("z"), modifiers: .control)
        #expect(tally.total == 0)
        #expect(!app.undoManager.canUndo)
    }

    @Test("Each key's registrations are one undo step, as a running app's run loop makes them")
    func eachEventIsAStep() {
        let tally = Tally()
        let app = TestApp(width: 30, height: 6) { Adder(tally: tally) }
        app.press(.space)
        app.press(.space)
        #expect(tally.total == 2)
        app.press(.character("z"), modifiers: .control)
        #expect(tally.total == 1, "the two presses were undone as one step")
    }
}
