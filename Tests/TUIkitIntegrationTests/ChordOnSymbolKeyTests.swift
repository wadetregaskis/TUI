//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ChordOnSymbolKeyTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A control that answers to a bare symbol or digit does not answer to a
/// Control or Option chord on it: Ctrl-minus (the legacy byte 0x1F, which
/// Ctrl-_ and Ctrl-/ also send) is the app's undo, Option-_ its redo, and a
/// chord is never the key it is on.
@MainActor
@Suite("Chords on a control's symbol keys")
struct ChordOnSymbolKeyTests {

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The chords a stepping control must leave alone, on both of its
    /// decrement keys and both of its increment keys.
    private static let chords: [KeyEvent] = [
        KeyEvent(key: .character("-"), ctrl: true),
        KeyEvent(key: .character("_"), ctrl: true),
        KeyEvent(key: .character("_"), alt: true),
        KeyEvent(key: .character("-"), alt: true),
        KeyEvent(key: .character("+"), alt: true),
        KeyEvent(key: .character("="), ctrl: true),
    ]

    @Test("A focused Slider takes no chord on + = - _, and still steps on the bare keys")
    func slider() {
        let harness = InputChainHarness()
        let value = Box(5.0)
        let view = { Slider(value: Binding(get: { value.value }, set: { value.value = $0 }), in: 0...10, step: 1) }
        harness.play(Self.chords, view)
        #expect(value.value == 5)
        harness.play([KeyEvent(character: "-"), KeyEvent(character: "-"), KeyEvent(character: "+")], view)
        #expect(value.value == 4)
    }

    @Test("A focused Stepper takes no chord on + = - _, and still steps on the bare keys")
    func stepper() {
        let harness = InputChainHarness()
        let value = Box(5)
        let view = { Stepper("Count", value: Binding(get: { value.value }, set: { value.value = $0 }), in: 0...10) }
        harness.play(Self.chords, view)
        #expect(value.value == 5)
        harness.play([KeyEvent(character: "_"), KeyEvent(character: "=")], view)
        #expect(value.value == 5)
        harness.play([KeyEvent(character: "-")], view)
        #expect(value.value == 4)
    }

    @Test("A focused DatePicker types no digit for an Option or Control chord on one")
    func datePickerDigits() {
        let harness = InputChainHarness()
        let consumed = harness.play([
            KeyEvent(key: .character("1"), alt: true), KeyEvent(key: .character("2"), ctrl: true),
        ]) {
            DatePicker("When", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date)
        }
        #expect(consumed == [false, false])
    }
}
