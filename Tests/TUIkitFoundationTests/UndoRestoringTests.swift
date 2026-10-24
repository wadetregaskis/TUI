//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoRestoringTests.swift
//
//  A list's reorders and deletions, and a drop's moves, were not undoable in
//  the Example (owner, 2026-10-23, #16): SwiftUI leaves their undo to the app,
//  and the app registered none. `UndoManager.registerRestoring(_:to:actionName:)`
//  is the TUIkit-only helper the Example now registers them with.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation

/// The value a binding reads and writes.
@MainActor
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
    var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

@MainActor
@Suite("UndoManager.registerRestoring(_:to:actionName:)")
struct UndoRestoringTests {

    /// A manager that groups only what it is told to, as with no run loop
    /// turning: each registration is its own step, as each event's are in a
    /// running app.
    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test("Undo puts the value back, and redo puts the change back, under the step's name")
    func undoAndRedo() {
        let manager = makeManager()
        let items = Box(["a", "b", "c"])
        let before = items.value
        items.value.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        manager.registerRestoring(items.binding, to: before, actionName: "Move")
        #expect(items.value == ["b", "c", "a"])
        #expect(manager.canUndo)
        #expect(manager.undoActionName == "Move", "Edit ▸ Undo would not name the move")

        #expect(UndoCommand.undo.perform(on: manager))
        #expect(items.value == ["a", "b", "c"], "the undo did not put the order back")
        #expect(manager.canRedo)
        #expect(manager.redoActionName == "Move", "the redo lost the step's name")

        #expect(UndoCommand.redo.perform(on: manager))
        #expect(items.value == ["b", "c", "a"], "the redo did not put the move back")
        #expect(UndoCommand.undo.perform(on: manager), "the redo registered no undo")
        #expect(items.value == ["a", "b", "c"])
    }

    @Test("Two changes undo one at a time, newest first")
    func twoSteps() {
        let manager = makeManager()
        let items = Box(["a", "b", "c"])
        var before = items.value
        items.value.remove(at: 1)
        manager.registerRestoring(items.binding, to: before, actionName: "Delete")
        before = items.value
        items.value.reverse()
        manager.registerRestoring(items.binding, to: before, actionName: "Move")

        #expect(manager.undoActionName == "Move")
        _ = UndoCommand.undo.perform(on: manager)
        #expect(items.value == ["a", "c"])
        #expect(manager.undoActionName == "Delete")
        _ = UndoCommand.undo.perform(on: manager)
        #expect(items.value == ["a", "b", "c"])
        #expect(!manager.canUndo)
    }
}
