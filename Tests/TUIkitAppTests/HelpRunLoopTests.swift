//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HelpRunLoopTests.swift
//
//  `help(_:)` through the real frame sequence: `RenderLoop.render` over an
//  in-memory terminal (`HeadlessApp`), with the keys and the pointer going
//  through the input chain. The unit suites in `HelpTooltipTests.swift` drive
//  `TooltipState` directly with one reset a frame, which is how two defects in
//  the focus path shipped: the run loop sizes the status bar before the walk
//  republishes the focus candidate, and resets the walk twice a frame.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A non-focusable `Text` with help, a `Button` with help (focused from the
/// first frame), and a `Button` without.
private struct HelpPageApp: App {
    var trigger: TooltipTrigger = .automatic
    var style: TooltipStyle = .statusBar
    var delay: Double = 0.6

    init() {}

    init(trigger: TooltipTrigger, style: TooltipStyle, delay: Double = 0.6) {
        self.trigger = trigger
        self.style = style
        self.delay = delay
    }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("button") {}.help("HELP-FOR-BUTTON")
                Text("plain text").help("HELP-FOR-TEXT")
                Button("no help") {}
            }
            .tooltips(trigger)
            .tooltipStyle(style)
            .tooltipDelay(delay)
        }
        // Motion reporting, which a live app turns on for the frame after a
        // view asks; a headless one applies only what the scene says.
        .mouseSupport(.full)
    }
}

/// A headless app and its clock, one 60 Hz frame per step.
@MainActor
private final class HelpDriver<A: App> {
    static var frameNanos: Int64 { 16_666_667 }

    let app: HeadlessApp<A>
    private(set) var now: Int64 = 0

    init(_ page: A, width: Int = 50, height: Int = 14) {
        app = HeadlessApp(page, width: width, height: height)
        step()
    }

    /// Renders the next frame.
    func step() {
        now += Self.frameNanos
        app.frame(atNanos: now)
    }

    /// Renders frames until `seconds` have passed since the first.
    func run(until seconds: Double) {
        while now < Self.frameNanos + Int64(seconds * 1_000_000_000) { step() }
    }

    /// The screen, without its escape codes.
    var lines: [String] { app.screen.map(\.stripped) }

    /// Whether `text` is anywhere on the screen.
    func shows(_ text: String) -> Bool {
        lines.contains { $0.contains(text) }
    }

    /// Where `text` first appears on the screen: its column and row.
    func position(of text: String) -> (x: Int, y: Int)? {
        for (row, line) in lines.enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), row)
            }
        }
        return nil
    }
}

@MainActor
@Suite("help(_:) through the run loop")
struct HelpRunLoopTests {
    private typealias Driver = HelpDriver<HelpPageApp>

    /// Defect 1 (found 2026-10-12): the status bar is sized before the walk,
    /// and the walk's reset had already emptied the focus slot, so a revealed
    /// focus tooltip never reached the bar — the DEFAULT presentation, so the
    /// help key showed nothing in an app that had chosen nothing.
    @Test("? shows the focused control's help, and ? again hides it", arguments: TooltipStyle.allCases)
    func helpKeyReveals(style: TooltipStyle) {
        let driver = Driver(HelpPageApp(trigger: .automatic, style: style))
        #expect(!driver.shows("HELP-FOR-BUTTON"), "precondition: nothing shows unasked")
        #expect(driver.app.send(KeyEvent(character: "?")), "the key was consumed")
        driver.step()
        #expect(driver.shows("HELP-FOR-BUTTON"), "\(style): the help key showed nothing")
        // Shown on the frame the key asked for, and still on the next: the
        // candidate survives the frame's own walks.
        driver.step()
        #expect(driver.shows("HELP-FOR-BUTTON"), "\(style): the help went after one frame")
        #expect(driver.app.send(KeyEvent(character: "?")))
        driver.step()
        #expect(!driver.shows("HELP-FOR-BUTTON"), "\(style): the second press did not hide it")
    }

    /// Defect 2 (found 2026-10-12): a frame runs the per-walk reset twice,
    /// and the second saved the focus deadline from the slot the first had
    /// emptied, so every frame set a new deadline a delay in its own future.
    @Test(".onFocus shows the focused control's help once its delay has passed", arguments: TooltipStyle.allCases)
    func onFocusWaitsOutItsDelay(style: TooltipStyle) {
        let driver = Driver(HelpPageApp(trigger: .onFocus, style: style))
        driver.run(until: 0.4)
        #expect(!driver.shows("HELP-FOR-BUTTON"), "\(style): shown before the 0.6 s delay")
        driver.run(until: 1.0)
        #expect(driver.shows("HELP-FOR-BUTTON"), "\(style): the delay never ran out")
    }

    /// A focus moved by a key between frames takes its tooltip with it on the
    /// frame that shows the move. The candidate now outlives the walk's reset,
    /// so this is what keeps the bar from drawing the help of the control the
    /// reader has just left — on a frame after which nothing else would draw.
    @Test("Moving the focus off a shown tooltip removes it at once", arguments: TooltipStyle.allCases)
    func focusMoveRemovesIt(style: TooltipStyle) {
        let driver = Driver(HelpPageApp(trigger: .onFocus, style: style, delay: 0))
        driver.step()
        #expect(driver.shows("HELP-FOR-BUTTON"), "precondition: \(style) shows the focused button's help")
        #expect(driver.app.send(KeyEvent(key: .tab)))
        driver.step()
        #expect(!driver.shows("HELP-FOR-BUTTON"), "\(style): the help stayed after the focus left")
    }
}
