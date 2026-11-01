//  🖥️ TUI — A Terminal UI framework for Swift
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

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
import TUITextInput

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
        let events = [
            KeyEvent(key: .up), KeyEvent(key: .down, shift: true), KeyEvent(key: .left, alt: true),
            KeyEvent(key: .right, ctrl: true), KeyEvent(key: .home), KeyEvent(character: "x"),
        ]
        let app = TestApp(width: 40, height: 12) {
            Text("leaf").focusable()
                .onMoveCommand { direction in log.entries.append("\(direction)") }
        }
        let consumed = (events).map { app.press($0) }
        #expect(log.entries == ["up", "down", "left", "right"])
        #expect(consumed == [true, true, true, true, false, false])
    }

    @Test("Escape is the exit command alone or with Shift, and not with Control or Option")
    func exitCommand() {
        let log = CommandLog()
        let events = [
            KeyEvent(key: .escape), KeyEvent(key: .escape, shift: true),
            KeyEvent(key: .escape, ctrl: true), KeyEvent(key: .escape, alt: true),
        ]
        let app = TestApp(width: 40, height: 12) {
            Text("leaf").focusable()
                .onExitCommand { log.entries.append("exit") }
        }
        for event in events { app.press(event) }
        #expect(log.entries == ["exit", "exit"])
    }

    @Test("Backspace and forward Delete are the delete command, alone or with Shift")
    func deleteCommand() {
        let log = CommandLog()
        let events = [
            KeyEvent(key: .backspace), KeyEvent(key: .delete), KeyEvent(key: .backspace, shift: true),
            KeyEvent(key: .backspace, alt: true), KeyEvent(key: .delete, ctrl: true),
        ]
        let app = TestApp(width: 40, height: 12) {
            Text("leaf").focusable()
                .onDeleteCommand { log.entries.append("delete") }
        }
        for event in events { app.press(event) }
        #expect(log.entries == ["delete", "delete", "delete"])
    }

    @Test("A command is heard only while the focus is on the view or inside it")
    func focusGated() {
        let log = CommandLog()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Text("A").focusable().onExitCommand { log.entries.append("A") }
                Text("B").focusable().onExitCommand { log.entries.append("B") }
            }
        }
        for event in [KeyEvent(key: .escape), KeyEvent(key: .tab), KeyEvent(key: .escape)] { app.press(event) }
        #expect(log.entries == ["A", "B"])
    }

    @Test("The innermost handler runs and consumes the command, a nil one included")
    func innermostWins() {
        let log = CommandLog()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Text("leaf").focusable()
                    .onExitCommand { log.entries.append("inner exit") }
                    .onMoveCommand(perform: nil)
            }
            .onExitCommand { log.entries.append("outer exit") }
            .onMoveCommand { _ in log.entries.append("outer move") }
        }
        for event in [KeyEvent(key: .escape), KeyEvent(key: .up)] { app.press(event) }
        #expect(log.entries == ["inner exit"], "a nil move command still keeps the arrow from the container")
    }

    @Test("An exit command takes Escape from the cancel button, after onKeyPress has had it")
    func betweenKeyPressAndShortcuts() {
        let log = CommandLog()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Text("leaf").focusable()
                    .onExitCommand { log.entries.append("exit") }
                Button("Cancel") { log.entries.append("cancel button") }
                    .keyboardShortcut(.cancelAction)
            }
            .onKeyPress(.escape) { log.entries.append("onKeyPress"); return .ignored }
        }
        app.press(KeyEvent(key: .escape))
        #expect(log.entries == ["onKeyPress", "exit"])
    }

    /// An app's page-level Escape — Example's "⎋ back", an `.onKeyEvent` around
    /// the page — took the key from a focused board whose exit command was to
    /// fill it again: the view nearest the focus answers first.
    @Test("An exit command takes Escape from the page's own key handler while the focus is inside it")
    func beforeThePagesHandler() {
        let log = CommandLog()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Text("board").focusable()
                    .onExitCommand { log.entries.append("exit") }
                Text("other").focusable()
            }
            .onKeyEvent { event in
                guard event.key == .escape else { return false }
                log.entries.append("page")
                return true
            }
        }
        for event in [KeyEvent(key: .escape), KeyEvent(key: .tab), KeyEvent(key: .escape)] { app.press(event) }
        #expect(log.entries == ["exit", "page"])
    }

    @Test("A key the focused control uses is not a command")
    func afterTheFocusedControl() {
        let log = CommandLog()
        let text = BoundText("ab")
        // The field deletes with Backspace and moves its caret with Left; it
        // lets Escape go.
        let app = TestApp(width: 40, height: 12) {
            VStack {
                TextField("Name", text: Binding(get: { text.value }, set: { text.value = $0 }))
            }
            .onDeleteCommand { log.entries.append("delete") }
            .onMoveCommand { direction in log.entries.append("move \(direction)") }
            .onExitCommand { log.entries.append("exit") }
        }
        for event in [KeyEvent(key: .backspace), KeyEvent(key: .left), KeyEvent(key: .escape)] { app.press(event) }
        #expect(text.value == "a")
        #expect(log.entries == ["exit"])
    }
}
