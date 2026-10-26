//  🖥️ TUI — A Terminal UI framework for Swift
//  RunningAppLocalizationTests.swift
//
//  A change to the localization service reaches the running app wherever it
//  was made — on a queue of the app's own too, where no app's work is under
//  way.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation

/// A scene with one line in it: what it draws does not matter here.
private struct StillApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
        }
    }
}

@MainActor
@Suite("A change to the localization service reaches the running app, wherever it was made")
struct RunningAppLocalizationTests {
    /// A key no other test registers or draws: registering it into the
    /// process's one service changes nothing any other test reads.
    nonisolated private static let key = "test.running-app.registration"

    /// Registers the key on a task of its own: a detached task inherits no
    /// task local, so no app's work is under way there, as on a download's
    /// callback.
    private func registerOutsideEveryAppsWork() async {
        // Read there, and checked here: a detached task does not inherit the
        // test either, so an expectation recorded in it is not this test's.
        let ambientWasNil = await Task.detached { () -> Bool in
            let ambientWasNil = AmbientApp.renderState == nil
            LocalizationService.shared.register(translations: ["en": [Self.key: "registered"]])
            return ambientWasNil
        }.value
        #expect(ambientWasNil, "precondition: no app's work is under way")
    }

    /// The run notes its app with the service the app's frames read, for as
    /// long as it runs: translations registered off every app's task clear
    /// its render cache while it runs, and ask nothing of it once the run
    /// has ended. Asked only of the app whose work made the change, the
    /// registration asked no app.
    @Test("Translations registered outside every app's work clear the running app's cache, until its run ends")
    func registrationReachesTheRunningApp() async {
        let appState = AppState()
        let runner = AppRunner(app: StillApp(), appState: appState)
        await runner.whileRunning {
            await registerOutsideEveryAppsWork()
            #expect(appState.consumeNeedsCacheClear(), "the running app's memoized rows keep the old strings")
            #expect(appState.needsRender, "the running app was not asked to draw the new strings")
        }
        appState.didRender()
        await registerOutsideEveryAppsWork()
        #expect(!appState.needsRender, "an app whose run has ended was asked for a frame")
    }
}
