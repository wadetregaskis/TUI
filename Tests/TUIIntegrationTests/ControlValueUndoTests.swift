//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlValueUndoTests.swift
//
//  Undo for the built-in controls that change a value (owner, 2026-10-26):
//  a change a person makes is a step in the app's undo manager — one per
//  change for a toggle or a picker, one per run for a slider or a stepper —
//  and a change the control makes itself, or the app makes, is none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Undo for the controls that change a value")
struct ControlValueUndoTests {

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }

    private func makeManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test("A toggle's flip is a step: undo flips it back, redo again")
    func toggle() {
        let manager = makeManager()
        let box = Box(false)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([KeyEvent(key: .space)]) { Toggle("Wi-Fi", isOn: box.binding) }
        #expect(box.value)
        manager.undo()
        #expect(!box.value)
        manager.redo()
        #expect(box.value)
    }

    @Test("Two flips are two steps")
    func toggleTwice() {
        let manager = makeManager()
        let box = Box(false)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([KeyEvent(key: .space), KeyEvent(key: .space)]) { Toggle("Wi-Fi", isOn: box.binding) }
        #expect(!box.value)
        manager.undo()
        #expect(box.value, "the second flip undone")
        manager.undo()
        #expect(!box.value, "the first")
    }

    @Test("A run of slider moves is one step, back to where it began")
    func sliderRun() {
        let manager = makeManager()
        let box = Box(0.5)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([KeyEvent(key: .right), KeyEvent(key: .right), KeyEvent(key: .right)]) {
            Slider(value: box.binding, in: 0...1, step: 0.1)
        }
        #expect(abs(box.value - 0.8) < 0.0001, "\(box.value)")
        manager.undo()
        #expect(abs(box.value - 0.5) < 0.0001, "\(box.value)")
        #expect(!manager.canUndo, "one step")
    }

    @Test("A step registered by anything else ends the slider's run")
    func sliderRunEnds() {
        let manager = makeManager()
        let box = Box(0.5)
        let harness = InputChainHarness(undoManager: manager)
        let slider = { Slider(value: box.binding, in: 0...1, step: 0.1) }
        harness.play([KeyEvent(key: .right)], slider)
        final class Flag { var on = true }
        let flag = Flag()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: flag) { $0.on = false }
        manager.endUndoGrouping()
        harness.play([KeyEvent(key: .right)], slider)
        manager.undo()
        #expect(abs(box.value - 0.6) < 0.0001, "the second run undone alone: \(box.value)")
        manager.undo()
        #expect(!flag.on)
        manager.undo()
        #expect(abs(box.value - 0.5) < 0.0001, "\(box.value)")
    }

    @Test("A run of stepper presses is one step")
    func stepperRun() {
        let manager = makeManager()
        let box = Box(3)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([KeyEvent(key: .right), KeyEvent(key: .right)]) {
            Stepper("Count", value: box.binding, in: 0...10)
        }
        #expect(box.value == 5)
        manager.undo()
        #expect(box.value == 3)
    }

    @Test("Each choice a segmented picker takes is a step")
    func segmentedPicker() {
        let manager = makeManager()
        let box = Box("a")
        let harness = InputChainHarness(undoManager: manager)
        // The arrows move along the segments; Space chooses.
        let keys = [KeyEvent(key: .right), KeyEvent(key: .space), KeyEvent(key: .right), KeyEvent(key: .space)]
        harness.play(keys) {
            Picker("Letter", selection: box.binding) {
                Text("A").tag("a")
                Text("B").tag("b")
                Text("C").tag("c")
            }
            .pickerStyle(.segmented)
        }
        #expect(box.value == "c")
        manager.undo()
        #expect(box.value == "b")
        manager.undo()
        #expect(box.value == "a")
    }

    @Test("A run of moves on the graphical calendar is one step")
    func calendarRun() {
        let manager = makeManager()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let box = Box(start)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([KeyEvent(key: .right), KeyEvent(key: .right)]) {
            DatePicker("Day", selection: box.binding, displayedComponents: .date).datePickerStyle(.graphical)
        }
        #expect(box.value != start)
        manager.undo()
        #expect(box.value == start)
    }

    @Test("A slider's clamp of an out-of-range value is no step; the app's own writes are none")
    func clampIsNoStep() {
        let manager = makeManager()
        let box = Box(1.5)
        let harness = InputChainHarness(undoManager: manager)
        harness.play([]) { Slider(value: box.binding, in: 0...1) }
        box.value = 0.25
        harness.play([]) { Slider(value: box.binding, in: 0...1) }
        #expect(!manager.canUndo, "nothing a person did")
    }

    @Test("With no undo manager the controls change as they always did")
    func noManager() {
        let box = Box(false)
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .space)]) { Toggle("Wi-Fi", isOn: box.binding) }
        #expect(box.value)
    }
}
