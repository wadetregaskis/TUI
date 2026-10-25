//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ExamplePageDriver.swift
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import Example
import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation

/// One Example page (or part of one) in a ``HeadlessApp``, driven the way a
/// person drives it: a click on what is on screen, a key to the focused
/// control, a frame after each on a clock that only moves when told to.
///
/// The Example's strings are not registered in a test process, so every `Text`
/// draws its key (`page.menus.chose`), and a test finds things on screen by
/// the same keys it would write in the page.
@MainActor
final class ExamplePageDriver<A: App> {
    private let app: HeadlessApp<A>
    private var now: Int64 = 0
    private static var frameNanos: Int64 { 16_666_667 }

    init(_ app: A, width: Int = 100, height: Int = 40) {
        self.app = HeadlessApp(app, width: width, height: height)
        advance(frames: 2)
    }

    /// Renders `frames` frames, a sixtieth of a second apart.
    func advance(frames: Int = 2) {
        for _ in 0..<frames {
            now += Self.frameNanos
            app.frame(atNanos: now)
        }
    }

    /// The screen's rows, styling stripped.
    var lines: [String] { app.screen.map(\.stripped) }

    /// Where `text` first appears from row `row` down: its row and column.
    func position(of text: String, fromRow row: Int = 0) -> (row: Int, column: Int)? {
        for (index, line) in lines.enumerated() where index >= row {
            if let range = line.range(of: text) {
                return (index, line.distance(from: line.startIndex, to: range.lowerBound))
            }
        }
        return nil
    }

    /// Whether `text` is on screen.
    func shows(_ text: String) -> Bool { position(of: text) != nil }

    /// Clicks the middle of `text`, where it first appears from row `row` down,
    /// and settles. Whether it was found.
    @discardableResult
    func click(_ text: String, fromRow row: Int = 0) -> Bool {
        guard let at = position(of: text, fromRow: row) else { return false }
        click(row: at.row, column: at.column + text.count / 2)
        return true
    }

    /// Presses and releases the left button at (`column`, `row`), a frame
    /// between, and settles.
    func click(row: Int, column: Int) {
        _ = app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        advance(frames: 1)
        _ = app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        advance()
    }

    /// Sends `key` to the focused control and settles.
    @discardableResult
    func press(_ key: Key, shift: Bool = false) -> Bool {
        let taken = app.send(KeyEvent(key: key, shift: shift))
        advance()
        return taken
    }

    /// Sends `event`, as the terminal would, and settles.
    @discardableResult
    func send(_ event: KeyEvent) -> Bool {
        let taken = app.send(event)
        advance()
        return taken
    }

    /// What the terminal can do, as a run's launch would have settled it
    /// (`\.terminalCapabilities`): set, the page is drawn again with it.
    var terminalCapabilities: TerminalCapabilities {
        get { app.terminalCapabilities }
        set {
            app.terminalCapabilities = newValue
            advance()
        }
    }

    /// Scrolls the wheel over (`column`, `row`) by `ticks` and settles.
    func scroll(row: Int, column: Int, down ticks: Int) {
        for _ in 0..<abs(ticks) {
            _ = app.send(MouseEvent(button: ticks > 0 ? .scrollDown : .scrollUp, phase: .pressed, x: column, y: row))
        }
        advance()
    }
}

/// A view an app can make with no arguments: an Example page.
protocol ExamplePageContent: View {
    init()
}

/// An app of one window holding a `Page`.
struct ExamplePageApp<Page: ExamplePageContent>: App {
    init() {}

    var body: some Scene {
        WindowGroup { Page() }
    }
}
