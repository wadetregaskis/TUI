//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HoverReshapeRunLoopTests.swift
//
//  A frame's reshape moving views under a resting pointer, through the run
//  loop: a view slid under a pointer resting on nothing hears `.entered` in an
//  app that declares no mouse support of its own, and an `.onHover` whose
//  change moves its own view out from under the pointer settles rather than
//  flickering at frame rate.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What an `.onHover` heard, in order.
private final class HoverLog {
    var heard: [Bool] = []
}

/// The review's page (BUGS13, round 1): an `.onHover` whose state shows a line
/// of details next to its own row. Above it on a page laid out from the top,
/// so the row moves down a row; below it on a page a `WindowGroup` centres,
/// which moves the row up when the page's new height takes the centring
/// across a cell (half the window heights). `declaresMotion`: whether the
/// scene says `.mouseSupport(.full)`, or leaves the motion to the
/// `.onHover`'s own request.
private struct SelfDisplacingApp: App {
    let log: HoverLog
    var declaresMotion = true
    var centred = false

    init() { log = HoverLog() }

    init(log: HoverLog, declaresMotion: Bool, centred: Bool) {
        self.log = log
        self.declaresMotion = declaresMotion
        self.centred = centred
    }

    var body: some Scene {
        WindowGroup {
            if centred {
                SelfDisplacingPage(log: log, detailsAbove: false)
            } else {
                SelfDisplacingPage(log: log, detailsAbove: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .mouseSupport(declaresMotion ? .full : .standard)
    }
}

private struct SelfDisplacingPage: View {
    let log: HoverLog
    let detailsAbove: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if detailsAbove, hovered { Text("details") }
            Text("hover me").onHover {
                hovered = $0
                log.heard.append($0)
            }
            if !detailsAbove, hovered { Text("details") }
        }
    }
}

/// A focused button that puts a row above an `.onHover`, so it slides under a
/// pointer resting on the blank row below it, in an app that declares no
/// mouse support: the motion is the `.onHover`'s request alone.
private struct SlidingHoverApp: App {
    let log: HoverLog

    init() { log = HoverLog() }

    init(log: HoverLog) { self.log = log }

    var body: some Scene {
        WindowGroup {
            SlidingHoverPage(log: log)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct SlidingHoverPage: View {
    let log: HoverLog
    @State private var inserted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("insert") { inserted = true }
            if inserted { Text("new row") }
            Text("slides").onHover { log.heard.append($0) }
        }
    }
}

/// A headless app and its clock, one 60 Hz frame per step.
@MainActor
private final class Driver<A: App> {
    let app: HeadlessApp<A>
    private var now: Int64 = 0

    init(_ page: A, height: Int = 14) {
        app = HeadlessApp(page, width: 40, height: height)
        step()
    }

    func step() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    /// Where `text` first appears on the screen: its column and row.
    func position(of text: String) -> (x: Int, y: Int)? {
        for (row, line) in app.screen.map(\.stripped).enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), row)
            }
        }
        return nil
    }
}

@MainActor
@Suite("Hover across a reshape, through the run loop")
struct HoverReshapeRunLoopTests {
    /// Found by the BUGS13 lane's review: once a lane resting on nothing
    /// entered what a reshape put under the pointer, this page entered,
    /// moved its row away and exited, moved it back and entered again, on
    /// every frame, and never idled; before that it settled after the exit.
    /// It settles after the exit again, in an app that declares motion and in
    /// one whose `.onHover` asks for it.
    @Test("An .onHover whose change moves its own row off a resting pointer settles",
          arguments: [true, false], [false, true])
    func selfDisplacingHoverSettles(declaresMotion: Bool, centred: Bool) throws {
        for height in centred ? [13, 14] : [14] {
            let log = HoverLog()
            let driver = Driver(
                SelfDisplacingApp(log: log, declaresMotion: declaresMotion, centred: centred), height: height)
            let row = try #require(driver.position(of: "hover me"), "precondition: drawn")
            driver.app.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y))
            for _ in 0..<12 { driver.step() }
            let settled = log.heard
            #expect(settled.first == true, "precondition: \(height) rows: the move entered it: \(settled)")
            #expect(settled.count <= 2, "\(height) rows: it flickers: \(settled)")
            for _ in 0..<12 { driver.step() }
            #expect(log.heard == settled, "\(height) rows: it went on after it settled: \(log.heard)")
        }
    }

    /// Found by the BUGS13 lane's review: the reshape asked whether motion is
    /// reported of the support the walk had reset to the scene's base, which
    /// is `.standard`, with no motion, unless the scene declares it; an
    /// `.onHover` asks for motion for the frame only. So in such an app the
    /// view slid under a pointer resting on nothing heard nothing.
    @Test("A view slid under a pointer resting on nothing hears .entered in an app that declares no motion")
    func slidUnderWithoutDeclaredMotion() throws {
        let log = HoverLog()
        let driver = Driver(SlidingHoverApp(log: log))
        let slides = try #require(driver.position(of: "slides"), "precondition: drawn")
        // The blank row below it.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: slides.x + 1, y: slides.y + 1))
        driver.step()
        #expect(log.heard.isEmpty, "precondition: the pointer rests on nothing: \(log.heard)")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        #expect(driver.position(of: "slides")?.y == slides.y + 1, "precondition: it slid under the pointer")
        driver.step()
        driver.step()
        #expect(log.heard == [true], "entered once: \(log.heard)")
    }
}
