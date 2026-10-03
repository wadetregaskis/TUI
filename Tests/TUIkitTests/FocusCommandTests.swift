//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FocusCommandTests.swift
//
//  SwiftUI's move, exit and delete commands, as measured on macOS 15 through
//  a key window: heard only while the focus is on the view or inside it; the
//  innermost handler runs and consumes the key, a nil action included; asked
//  after the focused control lets the key go (a List keeps its arrows) and
//  before the keyboard shortcuts (an exit command takes Escape from the cancel
//  button), and after onKeyPress. Any arrow is a move, whatever is held;
//  Escape and Delete count alone or with Shift.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the handlers under test saw, in the order they ran.
private final class CommandLog: @unchecked Sendable {
    var entries: [String] = []
}

/// The string a field under test is bound to.
private final class BoundText: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}

@MainActor
@Suite("SwiftUI's move, exit and delete commands")
struct FocusCommandTests {

    @Test("An arrow is a move command in its direction, whatever modifier is held")
    func moveCommand() {
        let log = CommandLog()
        let harness = InputChainHarness()
        let events = [
            KeyEvent(key: .up), KeyEvent(key: .down, shift: true), KeyEvent(key: .left, alt: true),
            KeyEvent(key: .right, ctrl: true), KeyEvent(key: .home), KeyEvent(character: "x"),
        ]
        let consumed = harness.play(events) {
            Text("leaf").focusable()
                .onMoveCommand { direction in log.entries.append("\(direction)") }
        }
        #expect(log.entries == ["up", "down", "left", "right"])
        #expect(consumed == [true, true, true, true, false, false])
    }

    @Test("Escape is the exit command alone or with Shift, and not with Control or Option")
    func exitCommand() {
        let log = CommandLog()
        let harness = InputChainHarness()
        let events = [
            KeyEvent(key: .escape), KeyEvent(key: .escape, shift: true),
            KeyEvent(key: .escape, ctrl: true), KeyEvent(key: .escape, alt: true),
        ]
        harness.play(events) {
            Text("leaf").focusable()
                .onExitCommand { log.entries.append("exit") }
        }
        #expect(log.entries == ["exit", "exit"])
    }

    @Test("Backspace and forward Delete are the delete command, alone or with Shift")
    func deleteCommand() {
        let log = CommandLog()
        let harness = InputChainHarness()
        let events = [
            KeyEvent(key: .backspace), KeyEvent(key: .delete), KeyEvent(key: .backspace, shift: true),
            KeyEvent(key: .backspace, alt: true), KeyEvent(key: .delete, ctrl: true),
        ]
        harness.play(events) {
            Text("leaf").focusable()
                .onDeleteCommand { log.entries.append("delete") }
        }
        #expect(log.entries == ["delete", "delete", "delete"])
    }

    @Test("A command is heard only while the focus is on the view or inside it")
    func focusGated() {
        let log = CommandLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .escape), KeyEvent(key: .tab), KeyEvent(key: .escape)]) {
            VStack {
                Text("A").focusable().onExitCommand { log.entries.append("A") }
                Text("B").focusable().onExitCommand { log.entries.append("B") }
            }
        }
        #expect(log.entries == ["A", "B"])
    }

    @Test("The innermost handler runs and consumes the command, a nil one included")
    func innermostWins() {
        let log = CommandLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .escape), KeyEvent(key: .up)]) {
            VStack {
                Text("leaf").focusable()
                    .onExitCommand { log.entries.append("inner exit") }
                    .onMoveCommand(perform: nil)
            }
            .onExitCommand { log.entries.append("outer exit") }
            .onMoveCommand { _ in log.entries.append("outer move") }
        }
        #expect(log.entries == ["inner exit"], "a nil move command still keeps the arrow from the container")
    }

    @Test("An exit command takes Escape from the cancel button, after onKeyPress has had it")
    func betweenKeyPressAndShortcuts() {
        let log = CommandLog()
        let harness = InputChainHarness()
        harness.play([KeyEvent(key: .escape)]) {
            VStack {
                Text("leaf").focusable()
                    .onExitCommand { log.entries.append("exit") }
                Button("Cancel") { log.entries.append("cancel button") }
                    .keyboardShortcut(.cancelAction)
            }
            .onKeyPress(.escape) { log.entries.append("onKeyPress"); return .ignored }
        }
        #expect(log.entries == ["onKeyPress", "exit"])
    }

    @Test("A key the focused control uses is not a command")
    func afterTheFocusedControl() {
        let log = CommandLog()
        let text = BoundText("ab")
        let harness = InputChainHarness()
        // The field deletes with Backspace and moves its caret with Left; it
        // lets Escape go.
        harness.play([KeyEvent(key: .backspace), KeyEvent(key: .left), KeyEvent(key: .escape)]) {
            VStack {
                TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
            }
            .onDeleteCommand { log.entries.append("delete") }
            .onMoveCommand { direction in log.entries.append("move \(direction)") }
            .onExitCommand { log.entries.append("exit") }
        }
        #expect(text.value == "a")
        #expect(log.entries == ["exit"])
    }
}
