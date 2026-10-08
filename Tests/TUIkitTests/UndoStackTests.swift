//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoStackTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation

/// The `UndoManager` TUIkit provides where Foundation has none (Linux), tested
/// through its engine on every platform. The expectations are
/// `NSUndoManager`'s, measured on macOS 15 by a probe under an async main
/// (whose run loop closes the event's group): two explicit groups in one event
/// are one step, an undo in the event that registered closes the group first,
/// and an undo's own registrations are the redo.
@MainActor
@Suite("UndoStack (UndoManager where Foundation has none)")
struct UndoStackTests {

    private final class Model {
        var value = 0
    }

    /// A stack whose events end only when the test says so.
    private func makeStack() -> (UndoStack, () -> Void) {
        let stack = UndoStack()
        let pending = Pending()
        stack.scheduleEndOfEvent = { pending.bodies.append($0) }
        return (stack, {
            let bodies = pending.bodies
            pending.bodies.removeAll()
            for body in bodies { body() }
        })
    }

    private final class Pending {
        var bodies: [@MainActor () -> Void] = []
    }

    /// Sets `model.value` to `value`, registering the inverse — which, run as
    /// an undo, registers its own inverse as the redo.
    private func set(_ model: Model, to value: Int, on stack: UndoStack) {
        let old = model.value
        model.value = value
        stack.registerUndo(withTarget: model) { [self] model in self.set(model, to: old, on: stack) }
    }

    @Test("Each event is one step, closed when the event ends")
    func groupsByEvent() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 1, on: stack)
        set(model, to: 2, on: stack)
        #expect(stack.groupingLevel == 1)
        #expect(stack.canUndo)
        endEvent()
        #expect(stack.groupingLevel == 0)
        set(model, to: 3, on: stack)
        endEvent()
        #expect(stack.undoCount == 2)
        stack.undo()
        #expect(model.value == 2)
        stack.undo()
        #expect(model.value == 0, "the first event's two changes are one step")
        #expect(!stack.canUndo)
    }

    @Test("An undo in the event that registered closes the group and undoes it")
    func undoInTheSameEvent() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 5, on: stack)
        stack.undo()
        #expect(model.value == 0)
        endEvent()
        #expect(stack.groupingLevel == 0, "the scheduled end finds nothing left to close")
    }

    @Test("Redo reapplies what undo took back, and a new change forgets redo")
    func redo() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 1, on: stack)
        endEvent()
        set(model, to: 2, on: stack)
        endEvent()
        stack.undo()
        stack.undo()
        #expect(model.value == 0)
        #expect(stack.redoCount == 2)
        stack.redo()
        #expect(model.value == 1)
        #expect(stack.canUndo)
        set(model, to: 7, on: stack)
        endEvent()
        #expect(!stack.canRedo)
    }

    @Test("Two explicit groups in one event are one step, as NSUndoManager makes them")
    func explicitGroupsInOneEvent() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        stack.beginUndoGrouping()
        set(model, to: 1, on: stack)
        stack.endUndoGrouping()
        stack.beginUndoGrouping()
        set(model, to: 2, on: stack)
        stack.endUndoGrouping()
        #expect(stack.groupingLevel == 1)
        endEvent()
        #expect(stack.undoCount == 1)
    }

    @Test("Without grouping by event, explicit groups are the steps, and a bare registration its own")
    func explicitGroupsWithoutEvents() {
        let (stack, _) = makeStack()
        stack.groupsByEvent = false
        let model = Model()
        stack.beginUndoGrouping()
        set(model, to: 1, on: stack)
        set(model, to: 2, on: stack)
        stack.endUndoGrouping()
        set(model, to: 3, on: stack)
        #expect(stack.undoCount == 2)
        stack.undo()
        #expect(model.value == 2)
        stack.undo()
        #expect(model.value == 0)
    }

    @Test("Removing a target's actions drops the steps it leaves empty")
    func removeTarget() {
        let (stack, endEvent) = makeStack()
        let first = Model()
        let second = Model()
        set(first, to: 1, on: stack)
        endEvent()
        set(second, to: 1, on: stack)
        set(first, to: 2, on: stack)
        endEvent()
        stack.removeAllActions(withTarget: first)
        #expect(stack.undoCount == 1)
        stack.undo()
        #expect(second.value == 0)
        #expect(first.value == 2)
    }

    @Test("Disabled registration records nothing; levels of undo keep the newest steps")
    func disablingAndLevels() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        stack.disableUndoRegistration()
        set(model, to: 1, on: stack)
        stack.enableUndoRegistration()
        #expect(!stack.canUndo)
        stack.levelsOfUndo = 2
        for value in 2...5 {
            set(model, to: value, on: stack)
            endEvent()
        }
        #expect(stack.undoCount == 2)
        stack.undo()
        stack.undo()
        #expect(model.value == 3)
    }

    @Test("A step keeps its name through undo and redo")
    func actionNames() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 1, on: stack)
        stack.setActionName("Typing")
        endEvent()
        #expect(stack.undoActionName == "Typing")
        stack.undo()
        #expect(stack.redoActionName == "Typing")
        #expect(stack.undoActionName.isEmpty)
    }

    @Test("Unbalanced grouping does nothing rather than trap")
    func unbalanced() {
        let (stack, _) = makeStack()
        stack.endUndoGrouping()
        stack.beginUndoGrouping()
        stack.beginUndoGrouping()
        stack.undo()
        #expect(stack.groupingLevel == 3, "the event's group and two explicit ones stay open")
    }

    // MARK: - Unbalanced grouping inside an undo

    @Test("An undo handler's unbalanced endUndoGrouping does nothing: no trap, and the stack goes on")
    func unbalancedEndInHandler() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        model.value = 1
        stack.registerUndo(withTarget: model) { model in
            stack.endUndoGrouping()
            model.value = 0
        }
        endEvent()
        stack.undo()
        #expect(model.value == 0)
        #expect(stack.groupingLevel == 0)
        set(model, to: 2, on: stack)
        endEvent()
        #expect(stack.undoCount == 1)
        stack.undo()
        #expect(model.value == 0)
    }

    @Test("An undo handler's removeAllActions forgets every other step and lets the undo finish, where NSUndoManager raises")
    func removeAllInHandler() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 1, on: stack)
        endEvent()
        stack.registerUndo(withTarget: model) { model in
            stack.removeAllActions()
            model.value = 0
        }
        model.value = 2
        endEvent()
        stack.undo()
        #expect(model.value == 0)
        #expect(!stack.canUndo && !stack.canRedo, "the older step is forgotten too")
        #expect(stack.groupingLevel == 0)
        set(model, to: 3, on: stack)
        endEvent()
        #expect(stack.undoCount == 1, "the stack goes on")
        stack.undo()
        #expect(model.value == 0)
    }

    @Test("What an undo or redo's handler registers after removeAllActions is the step that takes it back")
    func registerAfterRemoveAllInHandler() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        stack.registerUndo(withTarget: model) { [self] model in
            stack.removeAllActions()
            self.set(model, to: 1, on: stack)
        }
        model.value = 2
        endEvent()
        stack.undo()
        #expect(model.value == 1)
        #expect(!stack.canUndo && stack.canRedo)
        stack.redo()
        #expect(model.value == 2)
        #expect(stack.canUndo && !stack.canRedo)
    }

    @Test("A redo handler's removeAllActions lets the redo finish too")
    func removeAllInRedoHandler() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        stack.registerUndo(withTarget: model) { model in
            model.value = 0
            stack.registerUndo(withTarget: model) { model in
                stack.removeAllActions()
                model.value = 5
            }
        }
        model.value = 1
        endEvent()
        stack.undo()
        #expect(model.value == 0 && stack.canRedo)
        stack.redo()
        #expect(model.value == 5)
        #expect(!stack.canUndo && !stack.canRedo)
        #expect(stack.groupingLevel == 0)
    }

    @Test("An undo handler's unbalanced beginUndoGrouping is closed with the undo, into its redo")
    func unbalancedBeginInHandler() {
        let (stack, endEvent) = makeStack()
        let model = Model()
        set(model, to: 1, on: stack)
        endEvent()
        stack.registerUndo(withTarget: model) { [self] model in
            stack.beginUndoGrouping()
            self.set(model, to: 1, on: stack)
        }
        model.value = 2
        endEvent()
        stack.undo()
        #expect(model.value == 1)
        #expect(stack.groupingLevel == 0, "nothing left open")
        #expect(stack.canRedo)
        stack.redo()
        #expect(model.value == 2, "the redo the handler registered inside its group")
        stack.undo()
        stack.undo()
        #expect(model.value == 0, "undo still reaches the first step")
        set(model, to: 3, on: stack)
        endEvent()
        #expect(stack.undoCount == 1, "a new change is a step of its own, not caught in an open group")
    }
}
