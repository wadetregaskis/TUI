//  🖥️ TUI — A Terminal UI framework for Swift
//  PointerLeftTests.swift
//
//  A terminal reports no motion once the pointer has left its window, and no
//  mouse mode reports the leaving. Its window losing the focus — a focus-out
//  report, mode 1004 — is the one report that the pointer has gone
//  elsewhere, and it lets go of the pointer: what it hovered is exited and its
//  help goes. Found by the BUGS13 lane and left open: a control stayed lit
//  and a help stayed in the bar for as long as the pointer was away.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

/// A `Text` with help and one with `.onHover`, at the top-left corner, or the
/// help's in the middle of the window, where the status bar's row moves it.
struct PointerPageApp: App {
    static let hovers = PointerLeftHoverLog()
    var centred = false

    init() {}

    init(centred: Bool) {
        self.centred = centred
    }

    var body: some Scene {
        WindowGroup {
            if centred {
                page
            } else {
                page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .mouseSupport(.full)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("alpha").help("HELP-A")
            Text("beta").onHover { Self.hovers.entries.append($0) }
            Text("gamma")
        }
    }
}

/// What an `.onHover` heard, in order.
final class PointerLeftHoverLog: @unchecked Sendable {
    var entries: [Bool] = []
}

@MainActor
@Suite("The pointer goes with the terminal's focus")
struct PointerLeftTests {
    static let frameNanos: Int64 = 16_666_667

    /// A headless app and its clock, a 60 Hz frame per step.
    @MainActor
    final class Driver {
        let app: HeadlessApp
        private(set) var now: Int64 = 0

        init(_ page: PointerPageApp) {
            app = HeadlessApp(page, width: 50, height: 14)
            step()
        }

        func step() {
            now += PointerLeftTests.frameNanos
            app.frame(atNanos: now)
        }

        func run(forSeconds seconds: Double) {
            let end = now + Int64(seconds * 1_000_000_000)
            while now < end { step() }
        }

        var lines: [String] { app.screen.map(\.stripped) }

        func shows(_ text: String) -> Bool { lines.contains { $0.contains(text) } }

        func position(of text: String) -> (x: Int, y: Int)? {
            for (row, line) in lines.enumerated() {
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

    @Test("Focus out takes away the help the pointer was showing, and it does not come back while the window is away")
    func focusOutTakesTheHelpAway() throws {
        let driver = Driver(PointerPageApp())
        let alpha = try #require(driver.position(of: "alpha"))
        driver.move(to: (alpha.x + 1, alpha.y))
        driver.run(forSeconds: 1)
        #expect(driver.shows("HELP-A"), "precondition: hovered help shows: \(driver.lines)")
        driver.app.reportFocus(false)
        driver.step()
        #expect(!driver.shows("HELP-A"), "the help stayed with the pointer gone: \(driver.lines)")
        #expect(driver.app.services.mouseEventDispatcher.restingPointer == nil)
        driver.run(forSeconds: 1)
        #expect(!driver.shows("HELP-A"), "and came back with nothing reported: \(driver.lines)")
        // Back, and the pointer moves: it is heard again.
        driver.app.reportFocus(true)
        driver.move(to: (alpha.x + 2, alpha.y))
        driver.run(forSeconds: 1)
        #expect(driver.shows("HELP-A"), "a move after the focus came back shows it again: \(driver.lines)")
    }

    @Test("Focus out exits the .onHover the pointer was in")
    func focusOutExitsAnOnHover() throws {
        PointerPageApp.hovers.entries = []
        let driver = Driver(PointerPageApp())
        let beta = try #require(driver.position(of: "beta"))
        driver.move(to: (beta.x + 1, beta.y))
        driver.step()
        #expect(PointerPageApp.hovers.entries == [true], "precondition")
        driver.app.reportFocus(false)
        #expect(PointerPageApp.hovers.entries == [true, false], "the .onHover never heard the pointer go")
        driver.run(forSeconds: 0.5)
        #expect(PointerPageApp.hovers.entries == [true, false], "nothing enters it again")
    }

    /// A help held through the status bar's reflow (decisions-HELP A-HELP-1)
    /// is the pointer's too: the pointer is not on its view, so no exit
    /// reaches it, and it went only when the pointer next moved.
    @Test("Focus out takes away a help held through the bar's reflow")
    func focusOutTakesAHeldHelpAway() throws {
        let driver = Driver(PointerPageApp(centred: true))
        let alpha = try #require(driver.position(of: "alpha"))
        driver.move(to: (alpha.x + 1, alpha.y))
        driver.run(forSeconds: 1)
        #expect(driver.shows("HELP-A"), "precondition: shown: \(driver.lines)")
        #expect(driver.position(of: "alpha")?.y != alpha.y, "precondition: the bar's growth moved the page")
        driver.app.reportFocus(false)
        driver.step()
        #expect(!driver.shows("HELP-A"), "the held help stayed with the pointer gone: \(driver.lines)")
        driver.run(forSeconds: 1)
        #expect(!driver.shows("HELP-A"), "and came back: \(driver.lines)")
    }
}
