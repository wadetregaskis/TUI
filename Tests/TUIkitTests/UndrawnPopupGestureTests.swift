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

/// The pop-ups a press opens, one per opener that hands its gesture off.
enum PopupSurface: CaseIterable, Sendable {
    /// A `.contextMenu`, opened by the right button.
    case contextMenu
    /// A pull-down `Menu`.
    case pullDown
    /// A `Picker`'s drop-down.
    case picker
    /// A text field's suggestions, opened by its `▾`.
    case suggestions
}

@Observable
@MainActor
private final class Model {
    var on = false
    var surface = PopupSurface.pullDown
    var choice = 1
    var text = ""
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
            switch model.surface {
            case .contextMenu:
                Text("ctx").contextMenu { Button("ctxitem") {} }
            case .pullDown:
                Menu("pull") { Button("pulled") {} }
            case .picker:
                Picker("pick", selection: Bindable(model).choice) {
                    Text("one").tag(1)
                    Text("two").tag(2)
                    Text("three").tag(3)
                }
                .pickerStyle(.menu)
            case .suggestions:
                TextField("field", text: Bindable(model).text)
                    .textInputSuggestions {
                        Text("apricot")
                        Text("blackberry")
                    }
                    .frame(width: 24)
            }
        }
    }
}

@MainActor
private final class Harness {
    let model = Model()
    let app: HeadlessApp<PopupApp>
    private var now: Int64 = 0

    init(_ surface: PopupSurface = .pullDown) {
        model.surface = surface
        app = HeadlessApp(PopupApp(model), width: 40, height: 12)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    var screen: String { app.screen.map(\.stripped).joined(separator: "\n") }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    /// Where a press opens the surface, with which button, and a text only the
    /// open pop-up shows.
    func opener(_ surface: PopupSurface) throws -> (x: Int, y: Int, button: MouseButton, shows: String) {
        switch surface {
        case .contextMenu:
            let at = try position(of: "ctx")
            return (at.x, at.y, .right, "ctxitem")
        case .pullDown:
            let at = try position(of: "pull")
            return (at.x, at.y, .left, "pulled")
        case .picker:
            let at = try position(of: "one")
            return (at.x, at.y, .left, "three")
        case .suggestions:
            let at = try position(of: "▾")
            return (at.x, at.y, .left, "blackberry")
        }
    }

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

    @Test(
        "A held release away from a pop-up closes it, with or without a frame between, from every opener",
        arguments: PopupSurface.allCases, [false, true])
    func heldReleaseCloses(surface: PopupSurface, frameBetween: Bool) throws {
        // Drawn, the pop-up's backdrop closes it on a held release anywhere
        // away from its rows. Undrawn, the dispatcher spends the release and
        // runs the opener's close: the user let go before the pop-up was there
        // to see.
        let harness = Harness(surface)
        let open = try harness.opener(surface)
        let away = try harness.position(of: "flag")
        #expect(!harness.shows(open.shows), "\(harness.screen)")
        harness.app.send(MouseEvent(button: open.button, phase: .pressed, x: open.x, y: open.y))
        if frameBetween {
            harness.frame()
            #expect(harness.shows(open.shows), "the press opened nothing:\n\(harness.screen)")
        }
        harness.app.send(MouseEvent(button: open.button, phase: .dragged, x: away.x, y: away.y))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: open.button, phase: .released, x: away.x, y: away.y))
        harness.frame()
        #expect(!harness.shows(open.shows), "letting go left the pop-up up:\n\(harness.screen)")
        #expect(!harness.model.on)
        // A click that never moved leaves it up, quick or slow.
        harness.app.send(MouseEvent(button: open.button, phase: .pressed, x: open.x, y: open.y))
        if frameBetween { harness.frame() }
        harness.app.send(MouseEvent(button: open.button, phase: .released, x: open.x, y: open.y))
        harness.frame()
        #expect(harness.shows(open.shows), "a click closed the pop-up:\n\(harness.screen)")
    }

    @Test("The release of a press whose menu was closed while the button was held acts on no control")
    func releaseAfterTheMenuClosedActsOnNoControl() throws {
        // Escape closes the menu with the button still down; the rest of the
        // gesture is still the menu's, though nothing of it is on screen.
        let harness = Harness()
        let flag = try harness.position(of: "flag")
        let pull = try harness.position(of: "pull")
        harness.app.send(MouseEvent(button: .left, phase: .pressed, x: pull.x, y: pull.y))
        harness.frame()
        #expect(harness.shows("pulled"), "\(harness.screen)")
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        #expect(!harness.shows("pulled"), "\(harness.screen)")
        harness.app.send(MouseEvent(button: .left, phase: .dragged, x: flag.x, y: flag.y))
        harness.app.send(MouseEvent(button: .left, phase: .released, x: flag.x, y: flag.y))
        harness.frame()
        #expect(!harness.model.on, "the release toggled the toggle:\n\(harness.screen)")
    }
}
