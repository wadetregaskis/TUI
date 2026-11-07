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

/// A `Transition` whose body shows the model's label beside its content.
private struct LabellingTransition: Transition {
    let model: DeferredReadModel
    func body(content: Content, phase: TransitionPhase) -> some View {
        HStack {
            content
            Text(verbatim: "TR:" + model.label)
        }
    }
}

/// Commands of the app's own, whose body reads the model.
private struct ReadingCommands: Commands {
    var body: some Commands {
        CommandMenu("CM" + DeferredReadModels.commands.label) {}
    }
}

/// The models the apps read: an `App` is made by its type's `init()`.
private enum DeferredReadModels {
    nonisolated(unsafe) static var commands = DeferredReadModel()
}

private struct CommandsReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("page") }
            .commands { ReadingCommands() }
    }
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

    @Test("A Form's ForEach row reading an @Observable asks for a frame")
    mutating func formForEachRow() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 6) {
            Form {
                ForEach(0..<1, id: \.self) { _ in Text(verbatim: "FF:" + model.label) }
            }
        }
        expectRedraw(app, from: "FF:one", to: "FF:two") { model.label = "two" }
    }

    @Test("A Commands type's body reading an @Observable asks for a frame")
    mutating func commandsBody() {
        DeferredReadModels.commands = DeferredReadModel()
        let app = TestApp(CommandsReadingApp(), width: 40, height: 6)
        expectRedraw(app, from: "CMone", to: "CMtwo") { DeferredReadModels.commands.label = "two" }
    }

    @Test("An open list selection menu reading an @Observable asks for a frame")
    mutating func listSelectionMenu() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 10) {
            List(selection: .constant(Set<Int>())) {
                ForEach(0..<3, id: \.self) { Text("row \($0)") }
            }
            .contextMenu(forSelectionType: Int.self) { _ in Button("LM:" + model.label) {} }
        }
        _ = draw(app)
        app.send(KeyEvent(key: .f10, shift: true))
        expectRedraw(app, from: "LM:one", to: "LM:two") { model.label = "two" }
    }

    @Test("A visualEffect closure reading an @Observable asks for a frame")
    mutating func visualEffectClosure() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 6) {
            Text("VE").visualEffect { effect, _ in effect.offset(x: model.shift) }
        }
        expectRedraw(app, from: "VE", to: nil) { model.shift = 3 }
    }

    @Test("A scrollTransition closure reading an @Observable asks for a frame")
    mutating func scrollTransitionClosure() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 6) {
            Text("ST").scrollTransition { effect, _ in effect.offset(x: model.shift) }
        }
        expectRedraw(app, from: "ST", to: nil) { model.shift = 3 }
    }

    @Test("A Transition's body reading an @Observable asks for a frame")
    mutating func transitionBody() {
        let model = DeferredReadModel()
        let app = TestApp(width: 30, height: 6) {
            Text("x").transition(LabellingTransition(model: model))
        }
        expectRedraw(app, from: "TR:one", to: "TR:two") { model.label = "two" }
    }
}
