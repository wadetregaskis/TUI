//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndrawnPopupGestureTests.swift
//
//  The rest of a gesture whose press opened a pop-up, arriving before any
//  frame has drawn the pop-up — the press and its drag and release in one
//  input batch. The press hands the gesture off to live hit-testing
//  (`MouseEventDispatcher.handOffGesture`), which would land it on the screen
//  as the last frame left it, where nothing of the pop-up's is yet. The
//  dispatcher spends it instead, as the pop-up's backdrop does once drawn: the
//  quick gesture and the slow one end alike.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIkit
@testable import TUIkitCore

@Observable
@MainActor
private final class Model {
    var on = false
}

private struct PopupApp: App {
    let model: Model?

    init() { model = nil }

    init(_ model: Model) { self.model = model }

    var body: some Scene {
        WindowGroup {
            if let model { PopupPage(model: model) }
        }
    }
}

private struct PopupPage: View {
    let model: Model

    var body: some View {
        // The toggle above the menu, so the menu, hanging below its label,
        // never covers it: once drawn, its backdrop does.
        VStack {
            Toggle("flag", isOn: Bindable(model).on)
            Menu("pull") { Button("pulled") {} }
        }
    }
}

@MainActor
private final class Harness {
    let model = Model()
    let app: HeadlessApp<PopupApp>
    private var now: Int64 = 0

    init() {
        app = HeadlessApp(PopupApp(model), width: 40, height: 12)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var screen: String { app.screen.map(\.stripped).joined(separator: "\n") }

    func position(of text: String) throws -> (x: Int, y: Int) {
        let y = try #require(app.screen.firstIndex { $0.stripped.contains(text) }, "\(text) is not drawn")
        let line = app.screen[y].stripped
        let range = try #require(line.range(of: text))
        return (line.distance(from: line.startIndex, to: range.lowerBound), y)
    }
}

@MainActor
@Suite("The rest of a pop-up's gesture before a frame draws it")
struct UndrawnPopupGestureTests {
    @Test(
        "The release of a press that opened a menu acts on no control under it, held or not, with or without a frame between",
        arguments: [false, true], [false, true])
    func releaseActsOnNoControl(held: Bool, frameBetween: Bool) throws {
        let harness = Harness()
        let flag = try harness.position(of: "flag")
        let pull = try harness.position(of: "pull")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: pull.x, y: pull.y))
        if frameBetween { harness.frame() }
        if held {
            harness.app.send(MouseEvent(button: .left, phase: .dragged, x: flag.x, y: flag.y))
            if frameBetween { harness.frame() }
        }
        harness.app.send(MouseEvent(button: .left, phase: .released, x: flag.x, y: flag.y))
        harness.frame()
        #expect(!harness.model.on, "the release toggled the toggle:\n\(harness.screen)")
        // And a click on the toggle still toggles it.
        if harness.screen.contains("pulled") {
            harness.app.send(KeyEvent(key: .escape))
            harness.frame()
        }
        let again = try harness.position(of: "flag")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: again.x, y: again.y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: again.x, y: again.y))
        harness.frame()
        #expect(harness.model.on, "\(harness.screen)")
    }
}
