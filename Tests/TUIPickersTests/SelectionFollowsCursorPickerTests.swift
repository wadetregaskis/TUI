//  🖥️ TUI — A Terminal UI framework for Swift
//  SelectionFollowsCursorPickerTests.swift
//
//  `.selectionFollowsCursor()` reaches the other controls with a cursor apart
//  from their selection: a radio group and a segmented picker, which key
//  through one handler. An arrow then chooses the option it lands on, as a
//  macOS radio group's does; by default it only moves the cursor.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUIApp
@testable import TUICore
@testable import TUIFoundation
import TUIPickers
import TUITesting

@Observable
@MainActor
private final class Choice {
    var value = 1
}

@MainActor
@Suite("Selection follows the cursor in a picker")
struct SelectionFollowsCursorPickerTests {
    private func app<Style: PickerStyle>(_ choice: Choice, style: Style, follows: Bool) -> TestApp {
        let app = TestApp(width: 50, height: 8) {
            Picker("Size", selection: Binding(get: { choice.value }, set: { choice.value = $0 })) {
                Text("Small").tag(1)
                Text("Medium").tag(2)
                Text("Large").tag(3)
            }
            .pickerStyle(style)
            .selectionFollowsCursor(follows)
        }
        app.press(.tab)
        return app
    }

    @Test("By default a radio group's arrow moves the cursor; Space chooses")
    func radioDefault() {
        let choice = Choice()
        let app = app(choice, style: .radioGroup, follows: false)
        app.press(.down)
        #expect(choice.value == 1)
        app.press(.space)
        #expect(choice.value == 2)
    }

    @Test("Following, a radio group's arrows choose the option they land on")
    func radioFollows() {
        let choice = Choice()
        let app = app(choice, style: .radioGroup, follows: true)
        app.press(.down)
        #expect(choice.value == 2)
        app.press(.end)
        #expect(choice.value == 3)
        app.press(.up)
        #expect(choice.value == 2)
    }

    @Test("Following, a segmented picker's arrows choose the segment they land on")
    func segmentedFollows() {
        let choice = Choice()
        let app = app(choice, style: .segmented, follows: true)
        app.press(.right)
        #expect(choice.value == 2)
        app.press(.right)
        #expect(choice.value == 3)
    }
}
