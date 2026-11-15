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
import TUITextInput

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

/// An adder with a field after it that Escape closes, handing the focus back
/// to the button, as a row's inline rename field closes and hands it back to
/// its table (tuitree's feedback, Milestone 3 item 1). The focus moves in the
/// same event, so nothing about it asks for a frame after the one that drops
/// the field.
private struct AdderWithField: View {
    enum Control: Hashable { case add, field }

    let tally: Tally
    @State private var editing = true
    @State private var draft = ""
    @FocusState private var focus: Control?
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Total: \(tally.total)")
            Button("Add") { tally.add(undoManager: undoManager) }
                .focused($focus, equals: .add)
            if editing {
                TextField("Name", text: $draft)
                    .focused($focus, equals: .field)
                    .onExitCommand {
                        editing = false
                        focus = .add
                    }
            }
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

    @Test("A field closed by Escape takes its typing out of the undo history at once, so ⌃Z undoes the app's step")
    func closedFieldLeavesTheHistoryAtOnce() {
        let tally = Tally()
        let app = TestApp(width: 30, height: 6) { AdderWithField(tally: tally) }
        app.press(.space)
        #expect(tally.total == 1)
        app.press(.tab)
        app.type("zz")
        app.press(.escape)
        #expect(!app.screen.contains("zz"), "the field closed\n\(app.screen)")
        app.press(.character("z"), modifiers: .control)
        #expect(tally.total == 0, "the first ⌃Z undid the app's step, not the closed field's typing")
        #expect(!app.undoManager.canUndo)
    }
}
