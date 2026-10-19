//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeldHelpResidualTests.swift
//
//  A help held through the status bar's own reflow (decisions-HELP A-HELP-1)
//  and the cases its "Left open" list kept: a pointer moving along the rows
//  the bar covers let the help go and get it back after its delay; a frame
//  that took one surface down as it put another up kept it, the count of
//  surfaces unchanged; and a reshape the bar did not cause kept it on a view
//  the page had carried elsewhere.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A scroll view of rows with help that fills the window, so the bar's row
/// for a hover tooltip covers the page's last visible row.
struct HeldHelpRowsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<40, id: \.self) { index in
                        Text("row \(index) of the long list").help("HELP-\(index)")
                    }
                }
            }
        }
        .mouseSupport(.full)
    }
}

/// A page laid out in the middle of the window, so the bar's row moves it:
/// a focused button over a view with help, which puts a row above it.
struct HeldHelpCentredApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            HeldHelpCentredPage()
        }
        .mouseSupport(.full)
    }
}

struct HeldHelpCentredPage: View {
    @State private var inserted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("insert") { inserted = true }
            if inserted { Text("a row put above it") }
            Text("alpha").help("HELP-A")
            Text("beta")
            Text("gamma")
        }
    }
}

@MainActor
@Suite("Help held through the status bar's reflow: the residual cases")
struct HeldHelpResidualTests {
    @MainActor
    final class Driver<A: App> {
        let app: HeadlessApp<A>
        private(set) var now: Int64 = 0

        init(_ page: A) {
            app = HeadlessApp(page, width: 50, height: 14)
            step()
        }

        func step() {
            now += 16_666_667
            app.frame(atNanos: now)
        }

        @discardableResult
        func stepIfAsked() -> Bool {
            guard let wake = app.nextWake(after: now) else { return false }
            now = max(wake, now + 16_666_667)
            app.frame(atNanos: now)
            return true
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

    /// The last row drawn on the screen: its index and where it is.
    private func lastRow(_ driver: Driver<HeldHelpRowsApp>) -> (index: Int, x: Int, y: Int)? {
        driver.lines.enumerated().compactMap { row, line -> (index: Int, x: Int, y: Int)? in
            guard let range = line.range(of: #"row \d+"#, options: .regularExpression),
                let index = Int(line[range].dropFirst(4))
            else { return nil }
            return (index, line.distance(from: line.startIndex, to: range.lowerBound), row)
        }.last
    }

    @Test("A pointer moving along the row the bar covers keeps the help, every frame")
    func moveAlongACoveredRow() throws {
        let driver = Driver(HeldHelpRowsApp())
        let target = try #require(lastRow(driver), "no rows: \(driver.lines)")
        let help = "HELP-\(target.index)"
        driver.move(to: (target.x + 1, target.y))
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows(help), "precondition: shown: \(driver.lines)")
        #expect(driver.position(of: "row \(target.index) ") == nil, "precondition: the bar covers the row")
        var shown = 0
        for step in 2...10 {
            driver.move(to: (target.x + step, target.y))
            driver.step()
            shown += driver.shows(help) ? 1 : 0
        }
        #expect(shown == 9, "shown in \(shown) of 9 frames as the pointer moved along the covered row")
        driver.move(to: (target.x + 1, 0))
        driver.step()
        driver.stepIfAsked()
        #expect(!driver.shows(help), "a move off the covered rows takes it away: \(driver.lines)")
    }

    /// The page's own reshape: the button puts a row above the held view,
    /// which moves it a row from where the bar's reflow left it.
    @Test("A help held through the bar's reflow goes when the page itself moves its view")
    func pageMovesTheHeldView() throws {
        let driver = Driver(HeldHelpCentredApp())
        let alpha = try #require(driver.position(of: "alpha"))
        driver.move(to: (alpha.x + 1, alpha.y))
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("HELP-A"), "precondition: shown: \(driver.lines)")
        let held = try #require(driver.position(of: "alpha"))
        #expect(held.y != alpha.y, "precondition: the bar's growth moved the page")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("a row put above it"), "precondition: the page moved the view")
        #expect(!driver.shows("HELP-A"), "the help stayed on a view the page carried away: \(driver.lines)")
    }

    /// Unit level, as the run loop drives it: the hold begins on the rows the
    /// bar covers with one surface up, and a frame then takes it down and
    /// puts another up. The count was compared, one and one, and the help
    /// stayed over a surface that was not there when it began.
    @Test("A frame that swaps one presented surface for another lets a covered-row hold go")
    func swappedSurfaceLetsTheHoldGo() {
        let tooltips = TooltipState()
        let first = PresentedSurface(isScreenLevel: true, holdsInput: false, firstRegion: .init(10))
        let second = PresentedSurface(isScreenLevel: true, holdsInput: false, firstRegion: .init(20))
        func reshape(_ surfaces: [PresentedSurface], movedByTooltip: Bool, leaving: Bool = false) {
            tooltips.beginReshape(movedByTooltip: movedByTooltip, presentations: surfaces)
            if leaving { tooltips.leaving("HELP") }
            tooltips.endReshape(
                tooltipRows: 9..<10, pointerRow: 9, reaching: { _ in false }, region: { _ in nil })
        }
        tooltips.hovering("HELP", handlerID: .init(1), nowNanos: 0)
        reshape([first], movedByTooltip: true, leaving: true)
        #expect(tooltips.resolved(nowNanos: 1_000_000_000)?.text == "HELP", "precondition: held")
        reshape([first], movedByTooltip: false)
        #expect(tooltips.resolved(nowNanos: 1_000_000_000)?.text == "HELP", "the same surface keeps it")
        reshape([second], movedByTooltip: false)
        #expect(tooltips.resolved(nowNanos: 1_000_000_000) == nil, "a swapped surface lets it go")
    }
}
