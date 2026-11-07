//  🖥️ TUI — A Terminal UI framework for Swift
//  DeferredClosureObservationIntegrationTests.swift
//
//  The deferred closures of modules above `TUIApp` — an `AsyncImage`'s
//  content, a `Form`'s `ForEach` rows, a `Commands` type's body, a list's
//  selection menu, a `visualEffect`, a scroll transition and a `Transition`'s
//  body — each called in a core, after the body that made it returned, and
//  so outside any observation scope: a write to an `@Observable` it read,
//  made outside an event, asked for no frame. The `TUIApp`-level twins are
//  in `TUIAppTests/DeferredClosureObservationTests.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

@Observable
private final class DeferredReadModel {
    var label = "one"
    var shift = 0
}

@MainActor
@Suite("Deferred closures above TUIApp are observed", .serialized)
struct DeferredClosureObservationIntegrationTests {
    private var now: Int64 = 0

    private mutating func draw(_ app: TestApp) -> String {
        now += 20_000_000
        app.frame(atNanos: now)
        return app.screen.lines.joined(separator: "\n")
    }

    /// Draws `app` until `before` shows, runs `write`, and expects it to ask
    /// for a frame that shows `after` (or, with `after` nil, a different
    /// screen).
    private mutating func expectRedraw(
        _ app: TestApp, from before: String, to after: String?, write: () -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        _ = draw(app)
        let first = draw(app)
        #expect(first.contains(before), "\(first)", sourceLocation: sourceLocation)
        _ = app.takeFrameRequest()
        write()
        #expect(app.takeFrameRequest(), "the write asked for no frame", sourceLocation: sourceLocation)
        let second = draw(app)
        if let after {
            #expect(second.contains(after), "\(second)", sourceLocation: sourceLocation)
        } else {
            #expect(second != first, "the screen drew as it was", sourceLocation: sourceLocation)
        }
    }

    @Test("An AsyncImage's content closure reading an @Observable asks for a frame")
    mutating func asyncImageContent() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 6) {
            AsyncImage(url: nil) { _ in Text(verbatim: "AI:" + model.label) }
        }
        expectRedraw(app, from: "AI:one", to: "AI:two") { model.label = "two" }
    }
}
