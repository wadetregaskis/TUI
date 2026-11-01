//  🖥️ TUI — A Terminal UI framework for Swift
//  ShadowsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Colors page's shadows section")
struct ShadowsDemoTests {
    private func makeApp() -> TestApp {
        TestApp(width: 100, height: 40) { ShadowsDemo() }
    }

    /// The spelled call under the controls.
    private func call(_ app: TestApp) -> String? {
        app.screen.line(containing: ".shadow(color:")?.trimmingCharacters(in: .whitespaces)
    }

    @Test("The controls start at the shadow the ramp's cards cast and write it out as code")
    func startsAtTheDefault() {
        #expect(call(makeApp()) == ".shadow(color: …, radius: 2, x: 2, y: 1)")
    }

    @Test("The radius and offsets are steppers, and the live card and label follow them")
    func steppersDriveTheShadow() {
        let app = makeApp()
        // The colour has the focus; then Tab goes to the radius, x, then y.
        // Right raises a stepper and Left lowers it.
        app.press(.tab)
        app.press(.right)
        app.press(.tab)
        app.press(.right, times: 2)
        app.press(.tab)
        app.press(.left)
        #expect(call(app) == ".shadow(color: …, radius: 3, x: 4, y: 0)", "\(app.screen)")
    }

    @Test("The colour is chosen from a pop-up of named colours")
    func colourChoices() throws {
        let app = makeApp()
        #expect(app.screen.contains("page.colors.shadow.ink.faint"), "the first choice is showing")
        try app.click("page.colors.shadow.ink.faint")
        for ink in ["strong", "red", "accent"] {
            #expect(app.screen.contains("page.colors.shadow.ink.\(ink)"), "\(ink) is offered: \(app.screen)")
        }
    }
}
