//  🖥️ TUI — A Terminal UI framework for Swift
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

import Observation

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

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

/// decisions-BUGS13 B-BUGS13-2's loop through two hover views: hovering the
/// first shows the second in its place, which pushes the first a row down,
/// and the second's going brings the first back under the pointer.
private struct TwoViewLoopApp: App {
    let log: HoverLog

    init() { log = HoverLog() }

    init(log: HoverLog) { self.log = log }

    var body: some Scene {
        WindowGroup {
            TwoViewLoopPage(log: log)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct TwoViewLoopPage: View {
    let log: HoverLog
    @State private var firstHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if firstHovered {
                Text("second").onHover { log.heard.append($0) }
            }
            Text("first").onHover {
                firstHovered = $0
                log.heard.append($0)
            }
        }
    }
}

/// A row with `.onHover` that a key moves down a row and back.
private struct KeyMovedRowApp: App {
    let log: HoverLog

    init() { log = HoverLog() }

    init(log: HoverLog) { self.log = log }

    var body: some Scene {
        WindowGroup {
            KeyMovedRowPage(log: log)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct KeyMovedRowPage: View {
    let log: HoverLog
    @State private var pushed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pushed { Text("spacer") }
            Text("row").onHover { log.heard.append($0) }
        }
        .onKeyEvent(keys: [.character("n")]) { _ in
            pushed.toggle()
            return true
        }
    }
}

/// A focused button that puts a row above an `.onHover`, so it slides under a
/// pointer resting on the blank row below it, in an app that declares no
/// mouse support: the motion is what its views ask for, the `.onHover` and
/// the button alike.
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

/// The BUGS13 lane's second review's input: three pages a key steps through,
/// in an app that declares no mouse support. The first asks for motion (its
/// button's hover face), the second asks for none, so the terminal stops
/// reporting it and the pointer goes wherever it likes unheard, and the third
/// asks for it again, with a view with help two rows below its button: under
/// the cell a pointer that rested two rows below the first page's button
/// last reported.
private struct ReportingGapApp: App {
    var body: some Scene {
        WindowGroup {
            ReportingGapPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ReportingGapPage: View {
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case 0:
                Button("first page") {}
            case 1:
                Text("quiet page")
            default:
                Button("third page") {}
                Text("filler")
                Text("under the old cell").help("HELP-STALE")
            }
        }
        .tooltipDelay(0.1)
        .onKeyEvent(keys: [.character("n")]) { _ in
            page += 1
            return true
        }
    }
}

/// A headless app and its clock, one 60 Hz frame per step.
@MainActor
private final class Driver<A: App> {
    let app: TestApp
    private var now: Int64 = 0

    init(_ page: A, height: Int = 14) {
        app = TestApp(page, width: 40, height: height)
        step()
    }

    func step() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    /// Whether `text` is anywhere on the screen.
    func shows(_ text: String) -> Bool {
        position(of: text) != nil
    }

    /// Where `text` first appears on the screen: its column and row.
    func position(of text: String) -> (x: Int, y: Int)? {
        for (row, line) in app.screen.lines.enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), row)
            }
        }
        return nil
    }
}

/// An `.onHover` whose state changes its own view's width, its left edge staying
/// where it is.
private struct WidthChangingApp: App {
    let log: HoverLog
    let hoveredLabel: String
    let restingLabel: String

    init() {
        log = HoverLog()
        hoveredLabel = ""
        restingLabel = ""
    }

    init(log: HoverLog, hoveredLabel: String, restingLabel: String) {
        self.log = log
        self.hoveredLabel = hoveredLabel
        self.restingLabel = restingLabel
    }

    var body: some Scene {
        WindowGroup {
            WidthChangingPage(log: log, hoveredLabel: hoveredLabel, restingLabel: restingLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct WidthChangingPage: View {
    let log: HoverLog
    let hoveredLabel: String
    let restingLabel: String
    @State private var isHovered = false

    var body: some View {
        Text(verbatim: isHovered ? hoveredLabel : restingLabel)
            .onHover { hovering in
                log.heard.append(hovering)
                isHovered = hovering
            }
    }
}

/// A label whose width something other than its own hover changes: a timer, a
/// network reply, or a key's action.
@Observable
private final class LabelModel {
    var label: String
    init(_ label: String) { self.label = label }
}

private struct ExternallyResizedApp: App {
    let model: LabelModel
    let log: HoverLog

    init() {
        model = LabelModel("")
        log = HoverLog()
    }

    init(model: LabelModel, log: HoverLog) {
        self.model = model
        self.log = log
    }

    var body: some Scene {
        WindowGroup {
            ExternallyResizedPage(model: model, log: log)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct ExternallyResizedPage: View {
    let model: LabelModel
    let log: HoverLog

    var body: some View {
        Text(verbatim: model.label).onHover { log.heard.append($0) }
    }
}

@MainActor
@Suite("Hover across a reshape, through the run loop")
struct HoverReshapeRunLoopTests {
    /// The hover used to be compared by rectangle where a region has no focus id,
    /// so a view that grew or shrank under the pointer read as another control:
    /// exited, and remembered as left, so it never lit again. SwiftUI keeps it
    /// hovered: the pointer has not left it.
    @Test("A view that changes its own width under the pointer stays hovered",
          arguments: [("short", "a much wider label"), ("a much wider label", "short")])
    func widthChangeKeepsTheHover(restingLabel: String, hoveredLabel: String) throws {
        let log = HoverLog()
        let driver = Driver(WidthChangingApp(log: log, hoveredLabel: hoveredLabel, restingLabel: restingLabel))
        let start = try #require(driver.position(of: restingLabel), "precondition: drawn")
        // On its first column, which both labels cover.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: start.x, y: start.y))
        for _ in 0..<12 { driver.step() }
        #expect(log.heard == [true], "it was un-hovered: \(log.heard)")
        #expect(driver.shows(hoveredLabel))
        for character in "ab" {
            driver.app.send(KeyEvent(character: character))
            for _ in 0..<4 { driver.step() }
        }
        #expect(log.heard == [true], "a key changed it: \(log.heard)")
    }

    /// A view that grows until it covers a resting pointer is what the pointer is
    /// on now, whatever made it grow.
    @Test("A view that grows under a resting pointer is entered")
    func growingOntoThePointerEnters() throws {
        let log = HoverLog()
        let wide = "a much wider label"
        let model = LabelModel("short")
        let driver = Driver(ExternallyResizedApp(model: model, log: log))
        let start = try #require(driver.position(of: "short"), "precondition: drawn")
        // Past the end of the short label, inside where the wide one will reach.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: start.x + wide.count - 1, y: start.y))
        for _ in 0..<4 { driver.step() }
        #expect(log.heard.isEmpty, "precondition: the pointer is on nothing: \(log.heard)")
        model.label = wide
        for _ in 0..<4 { driver.step() }
        #expect(log.heard == [true], "the growth did not enter it: \(log.heard)")
    }

    /// Something other than its hover shrinks it off the pointer and grows it back,
    /// with no input between, as a timer or a network reply can. Not entered today:
    /// `leftByReshape` stops a hover that moves its own view from flickering for
    /// ever, and it can't tell that apart from this.
    @Test("A view that shrinks off a resting pointer and grows back is entered again")
    func growingBackOntoThePointerEnters() throws {
        let log = HoverLog()
        let wide = "a much wider label"
        let model = LabelModel(wide)
        let driver = Driver(ExternallyResizedApp(model: model, log: log))
        let start = try #require(driver.position(of: wide), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: start.x + wide.count - 1, y: start.y))
        for _ in 0..<4 { driver.step() }
        #expect(log.heard == [true], "precondition: the move entered it: \(log.heard)")
        model.label = "short"
        for _ in 0..<4 { driver.step() }
        #expect(log.heard == [true, false], "the shrink did not exit it: \(log.heard)")
        model.label = wide
        for _ in 0..<4 { driver.step() }
        withKnownIssue("leftByReshape cannot tell an outside change from the hover's own") {
            #expect(log.heard == [true, false, true], "growing back did not enter it: \(log.heard)")
        }
    }

    /// The same, with a key between, and the growth the key's doing.
    @Test("A view a key grows back under a resting pointer is entered again")
    func aKeyGrowingItBackEnters() throws {
        let log = HoverLog()
        let wide = "a much wider label"
        let model = LabelModel(wide)
        let driver = Driver(ExternallyResizedApp(model: model, log: log))
        let start = try #require(driver.position(of: wide), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: start.x + wide.count - 1, y: start.y))
        for _ in 0..<4 { driver.step() }
        model.label = "short"
        for _ in 0..<4 { driver.step() }
        #expect(log.heard == [true, false], "precondition: \(log.heard)")
        driver.app.send(KeyEvent(character: "x"))
        model.label = wide
        for _ in 0..<4 { driver.step() }
        #expect(log.heard == [true, false, true], "growing back did not enter it: \(log.heard)")
    }

    /// The pointer really has left a view that shrank from under it, and that
    /// stays settled rather than flickering as the view grows back beneath it.
    @Test("A view that shrinks out from under the pointer is exited once and settles")
    func shrinkingOffThePointerSettles() throws {
        let log = HoverLog()
        let wide = "a much wider label"
        let driver = Driver(WidthChangingApp(log: log, hoveredLabel: "short", restingLabel: wide))
        let start = try #require(driver.position(of: wide), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: start.x + wide.count - 1, y: start.y))
        for _ in 0..<12 { driver.step() }
        #expect(log.heard == [true, false], "it flickers: \(log.heard)")
        for _ in 0..<12 { driver.step() }
        #expect(log.heard == [true, false], "it went on after it settled: \(log.heard)")
    }

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

    /// Found by the INPUT lane's review: every key forgot the row the reshape
    /// had taken the hover off, though it rested under the pointer, so each
    /// one entered it again, showed its details for a frame and took them
    /// away, and called the `.onHover` twice.
    @Test("An .onHover that settled under a resting pointer stays settled through keys")
    func selfDisplacingHoverStaysSettledThroughKeys() throws {
        let log = HoverLog()
        let driver = Driver(SelfDisplacingApp(log: log, declaresMotion: true, centred: false))
        let row = try #require(driver.position(of: "hover me"), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y))
        for _ in 0..<12 { driver.step() }
        let settled = log.heard
        #expect(settled == [true, false], "precondition: it settled: \(settled)")
        for character in "abc" {
            driver.app.send(KeyEvent(character: character))
            for _ in 0..<4 { driver.step() }
        }
        #expect(log.heard == settled, "a key entered it again: \(log.heard)")
        #expect(!driver.shows("details"))
    }

    /// decisions-BUGS13 B-BUGS13-2: each reshape moved the lane from one
    /// view to the other, and the app never idled.
    @Test("A loop through two .onHover views under a resting pointer settles")
    func twoViewLoopSettles() throws {
        let log = HoverLog()
        let driver = Driver(TwoViewLoopApp(log: log))
        let first = try #require(driver.position(of: "first"), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: first.x + 1, y: first.y))
        for _ in 0..<12 { driver.step() }
        let settled = log.heard
        #expect(settled.first == true, "precondition: the move entered it: \(settled)")
        #expect(settled.count <= 4, "it loops: \(settled)")
        for _ in 0..<12 { driver.step() }
        #expect(log.heard == settled, "it went on after it settled: \(log.heard)")
    }

    /// decisions-BUGS13 B-BUGS13-2: a row a key moves from under a resting
    /// pointer, and back, lights again; it waited for the pointer to move.
    @Test("A row a key moves away and back under a resting pointer is entered again")
    func keyMovedRowIsEnteredAgain() throws {
        let log = HoverLog()
        let driver = Driver(KeyMovedRowApp(log: log))
        let row = try #require(driver.position(of: "row"), "precondition: drawn")
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: row.x + 1, y: row.y))
        driver.step()
        #expect(driver.app.send(KeyEvent(character: "n")))
        driver.step()
        driver.step()
        #expect(log.heard == [true, false], "precondition: the key moved it away: \(log.heard)")
        #expect(driver.app.send(KeyEvent(character: "n")))
        driver.step()
        driver.step()
        #expect(log.heard == [true, false, true], "the row came back unlit: \(log.heard)")
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

    /// Found by the BUGS13 lane's second review: a reshape entered what it
    /// slid under the cell the pointer last reported motion on, as long as
    /// the last frame asked for motion, though the frame before it had asked
    /// for none and the pointer had gone wherever it liked unheard. In an
    /// app that declares no motion, which is nearly every app, the third
    /// page's view with help, drawn under that cell, was entered a frame
    /// after it was drawn and showed its help for a pointer that was not on
    /// it. Until the pointer reports again nothing is entered; a move then
    /// shows the help as any move would.
    @Test("A reshape enters nothing under a pointer that went unreported since it rested")
    func noEntryAfterAGapInReporting() throws {
        let driver = Driver(ReportingGapApp())
        let button = try #require(driver.position(of: "first page"), "precondition: drawn")
        let cell = (x: button.x + 1, y: button.y + 2)
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: cell.x, y: cell.y))
        driver.step()
        #expect(driver.app.send(KeyEvent(character: "n")), "the key went to the page")
        driver.step()
        #expect(driver.shows("quiet page"), "precondition: the page that asks for no motion")
        // The pointer moves now, and the terminal reports none of it.
        #expect(driver.app.send(KeyEvent(character: "n")))
        driver.step()
        let view = try #require(driver.position(of: "under the old cell"), "precondition: drawn")
        #expect(view.y == cell.y && view.x <= cell.x, "precondition: drawn under the old cell")
        for _ in 0..<30 { driver.step() }
        #expect(!driver.shows("HELP-STALE"), "help for a view the pointer is not known to be on")
        // A report puts the pointer back on the cell, and its help shows.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: cell.x, y: cell.y))
        for _ in 0..<30 { driver.step() }
        #expect(driver.shows("HELP-STALE"), "precondition: the view shows its help to a pointer on it")
    }
}
