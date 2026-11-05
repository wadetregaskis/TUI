//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetObservationTests.swift
//
//  A `.sheet`'s content closure runs when the presentation modifier draws,
//  not when the enclosing `body` is evaluated, so its reads are observed
//  there: written outside an event, a model it reads asks for a frame, as
//  `FrameObservationTests` has it for the closures in lower modules.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
import TUITesting
@testable import TUITestSupport

@Observable
private final class SheetReadModel: @unchecked Sendable {
    var label = "one"
}

/// The model the app reads: an `App` is made by its type's `init()`.
private enum SheetReadModels {
    nonisolated(unsafe) static var sheet = SheetReadModel()
}

/// Reads the model inside a `.sheet`'s content closure.
private struct SheetReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Text("Page")
                .sheet(isPresented: .constant(true)) {
                    Text(verbatim: "S:" + SheetReadModels.sheet.label)
                }
        }
    }
}

@MainActor
@Suite("Sheet observation")
struct SheetObservationTests {
    /// Draws a frame 20 ms after the last and returns the screen's rows.
    private func draw(_ app: TestApp, at now: inout Int64) -> [String] {
        now += 20_000_000
        app.frame(atNanos: now)
        return app.screen.lines
    }

    @Test("A .sheet's closure reading an @Observable asks for a frame")
    func sheetClosure() {
        SheetReadModels.sheet = SheetReadModel()
        let app = TestApp(SheetReadingApp(), width: 30, height: 10)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("S:one") })
        _ = app.takeFrameRequest()
        SheetReadModels.sheet.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("S:two") })
    }
}
