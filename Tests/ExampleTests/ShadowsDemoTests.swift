//  🖥️ TUI — A Terminal UI framework for Swift
//  ShadowsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
@testable import TUIApp

extension ShadowsDemo: ExamplePageContent {}

@MainActor
@Suite("The Colors page's shadows section")
struct ShadowsDemoTests {
    private func driver() -> ExamplePageDriver<ExamplePageApp<ShadowsDemo>> {
        ExamplePageDriver(ExamplePageApp<ShadowsDemo>(), width: 100, height: 40)
    }

    /// The spelled call under the controls.
    private func call(_ driver: ExamplePageDriver<ExamplePageApp<ShadowsDemo>>) -> String? {
        driver.lines.first { $0.contains(".shadow(color:") }?.trimmingCharacters(in: .whitespaces)
    }

    @Test("The controls start at the shadow the ramp's cards cast and write it out as code")
    func startsAtTheDefault() {
        #expect(call(driver()) == ".shadow(color: …, radius: 2, x: 2, y: 1)")
    }

    @Test("The radius and offsets are steppers, and the live card and label follow them")
    func steppersDriveTheShadow() {
        let driver = driver()
        // The colour has the focus; then Tab goes to the radius, x, then y.
        // Right raises a stepper and Left lowers it.
        driver.press(.tab)
        driver.press(.right)
        driver.press(.tab)
        driver.press(.right)
        driver.press(.right)
        driver.press(.tab)
        driver.press(.left)
        #expect(call(driver) == ".shadow(color: …, radius: 3, x: 4, y: 0)", "\(driver.lines)")
    }

    @Test("The colour is chosen from a pop-up of named colours")
    func colourChoices() {
        let driver = driver()
        #expect(driver.shows("page.colors.shadow.ink.faint"), "the first choice is showing")
        driver.click("page.colors.shadow.ink.faint")
        for ink in ["strong", "red", "accent"] {
            #expect(driver.shows("page.colors.shadow.ink.\(ink)"), "\(ink) is offered: \(driver.lines)")
        }
    }
}
