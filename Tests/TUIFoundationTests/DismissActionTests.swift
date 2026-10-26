//  🖥️ TUI — A Terminal UI framework for Swift
//  DismissActionTests.swift
//
//  Created by LAYERED.work
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Dismiss Action Tests")
struct DismissActionTests {

    @Test("Calling dismiss requests an exit of the app whose work calls it")
    func dismissRequestsExit() {
        let app = AppState()
        let dismiss = DismissAction()
        AmbientApp.$renderState.withValue(app) { dismiss() }
        #expect(app.consumeShouldExit() == true)
        // Flag clears after one consume.
        #expect(app.consumeShouldExit() == false)
    }

    @Test("The default environment dismiss action signals an exit of the app whose work calls it")
    func defaultEnvironmentDismissSignalsExit() {
        let app = AppState()
        AmbientApp.$renderState.withValue(app) { EnvironmentValues().dismiss() }
        #expect(app.consumeShouldExit() == true)
    }

    @Test("A context's top-level dismiss action exits that context's app, from anywhere")
    func contextExitActionExitsItsApp() {
        let tui = TUIContext()
        let other = AppState()
        AmbientApp.$renderState.withValue(other) { tui.exitAction() }
        #expect(tui.appState.consumeShouldExit() == true)
        #expect(other.consumeShouldExit() == false, "the app whose work called it is not the one it names")
    }

    @Test("requestExit is independent of needsRender flag")
    func requestExitDoesNotInterfereWithRender() {
        let app = AppState()
        app.requestExit()
        #expect(!app.needsRender)
        #expect(app.consumeShouldExit() == true)
    }
}
