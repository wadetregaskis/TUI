//  🖥️ TUI — A Terminal UI framework for Swift
//  NestedHelpTests.swift
//
//  Help on a view inside a view with help. Every hover observer whose region
//  holds the pointer hears it now (semantic audit item 31), so both help
//  views do, and the innermost is the candidate, as AppKit shows the tooltip
//  of the deepest view under the pointer. Until then only the outermost help
//  heard the pointer, and the inner help never showed.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// A row with help inside a column with help, at the top-left corner; a key
/// adds a row to the column, which changes its rectangle under a resting
/// pointer.
struct NestedHelpApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NestedHelpPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tooltipDelay(0.1)
        }
        .mouseSupport(.full)
    }
}

struct NestedHelpPage: View {
    @State private var extra = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("inner row").help("INNER-HELP")
            Text("outer row")
            if extra { Text("added row, wider than the rest") }
        }
        .help("OUTER-HELP")
        .onKeyEvent(keys: [.character("n")]) { _ in
            extra.toggle()
            return true
        }
    }
}

@MainActor
@Suite("Help inside help")
struct NestedHelpTests {
    @MainActor
    final class Driver {
        let app = TestApp(NestedHelpApp(), width: 50, height: 14)
        private(set) var now: Int64 = 0

        init() { step() }

        func step() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        func run(forSeconds seconds: Double) {
            let end = now + Int64(seconds * 1_000_000_000)
            while now < end { step() }
        }

        func shows(_ text: String) -> Bool { app.screen.lines.contains { $0.contains(text) } }

        func position(of text: String) -> (x: Int, y: Int)? {
            for (row, line) in app.screen.lines.enumerated() {
                if let range = line.range(of: text) {
                    return (line.distance(from: line.startIndex, to: range.lowerBound), row)
                }
            }
            return nil
        }

        func move(to point: (x: Int, y: Int)) {
            app.send(MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
        }
    }

    @Test("Over the inner view its help shows; over the rest of the outer, the outer's")
    func innermostHelpShows() throws {
        let driver = Driver()
        let inner = try #require(driver.position(of: "inner row"))
        let outer = try #require(driver.position(of: "outer row"))
        driver.move(to: (inner.x + 1, inner.y))
        driver.run(forSeconds: 0.5)
        #expect(driver.shows("INNER-HELP"), "the inner view's help: \(driver.app.screen.lines)")
        #expect(!driver.shows("OUTER-HELP"))
        driver.move(to: (outer.x + 1, outer.y))
        driver.run(forSeconds: 0.5)
        #expect(driver.shows("OUTER-HELP"), "the outer view's help once the pointer leaves the inner")
        #expect(!driver.shows("INNER-HELP"))
    }

    /// The outer view's rectangle changes under a pointer resting on the
    /// inner one, so the reshape exits it and enters it again: entered last,
    /// it would be the candidate, though the pointer is still on the inner
    /// view.
    @Test("A reshape that re-enters the outer view leaves the inner view's help showing")
    func reshapeKeepsTheInnermost() throws {
        let driver = Driver()
        let inner = try #require(driver.position(of: "inner row"))
        driver.move(to: (inner.x + 1, inner.y))
        driver.run(forSeconds: 0.5)
        #expect(driver.shows("INNER-HELP"), "precondition")
        #expect(driver.app.send(KeyEvent(character: "n")))
        driver.run(forSeconds: 0.5)
        #expect(driver.shows("added row"), "precondition: the column grew")
        #expect(driver.shows("INNER-HELP"), "the inner view's help: \(driver.app.screen.lines)")
        #expect(!driver.shows("OUTER-HELP"))
    }
}
