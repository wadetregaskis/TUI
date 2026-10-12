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
    /// Whether the views sit at the top-left corner rather than in the
    /// middle of the window, so a status bar growing at the foot moves none
    /// of them.
    var topLeading = false

    init() {}

    init(trigger: TooltipTrigger, style: TooltipStyle, delay: Double = 0.6, topLeading: Bool = false) {
        self.trigger = trigger
        self.style = style
        self.delay = delay
        self.topLeading = topLeading
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if topLeading {
                    page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    page
                }
            }
            .tooltips(trigger)
            .tooltipStyle(style)
            .tooltipDelay(delay)
        }
        // Motion reporting, which a live app turns on for the frame after a
        // view asks; a headless one applies only what the scene says.
        .mouseSupport(.full)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("button") {}.help("HELP-FOR-BUTTON")
            Text("plain text").help("HELP-FOR-TEXT")
            Button("no help") {}
        }
    }
}

/// Two `Text`s with help, one above the other at the top-left corner, every
/// panel shown: on a 22 × 5 screen there is room for one panel of theirs.
private struct DenseHelpApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("first").help("FIRST-HELP-TEXT")
                Text("second").help("SECOND-HELP-TEXT")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tooltips(.always)
        }
        .mouseSupport(.full)
    }
}

/// Two `Text`s with help, the second drawn through `.offset`, which floats
/// its drawing (and the panel attached to it) as a layer of its own.
private struct OffsetHelpApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("a-view").help("AAAA")
                Text("b-view").help("BBBB").offset(x: 0, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tooltips(.always)
        }
    }
}

/// Two buttons with help under `.onFocus` with no delay, the first focused
/// from the first frame.
private struct TwoHelpedButtonsApp: App {
    var style: TooltipStyle = .statusBar

    init() {}

    init(style: TooltipStyle) {
        self.style = style
    }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Button("first") {}.help("HELP-FOR-FIRST")
                Button("second") {}.help("HELP-FOR-SECOND")
            }
            .tooltips(.onFocus)
            .tooltipStyle(style)
            .tooltipDelay(0)
        }
    }
}

/// A button whose help says what pressing it does, so the help changes when
/// it is pressed; or, with `dropsHelp`, the press takes the help away.
private struct ChangingHelpApp: App {
    var dropsHelp = false

    init() {}

    init(dropsHelp: Bool) {
        self.dropsHelp = dropsHelp
    }

    var body: some Scene {
        WindowGroup {
            PlayButton(dropsHelp: dropsHelp)
        }
    }
}

private struct PlayButton: View {
    let dropsHelp: Bool
    @State private var isPlaying = false

    var body: some View {
        Button(isPlaying ? "pause" : "play") { isPlaying.toggle() }
            .help(isPlaying ? "HELP-PAUSE" : "HELP-PLAY")
            .tooltips(dropsHelp && isPlaying ? .never : .automatic)
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

    /// Renders the next frame only if the last one asked for it, at the
    /// instant it asked for and no sooner than a frame on: what the live run
    /// loop does once the input and the state changes are spent. ``step()``
    /// renders whether or not anything asked, so it cannot see a frame that
    /// nothing asks for.
    /// - Returns: Whether it rendered.
    @discardableResult
    func stepIfAsked() -> Bool {
        guard let wake = app.nextWake(after: now) else { return false }
        now = max(wake, now + Self.frameNanos)
        app.frame(atNanos: now)
        return true
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
        driver.stepIfAsked()
        #expect(driver.shows("HELP-FOR-BUTTON"), "precondition: \(style) shows the focused button's help")
        #expect(driver.app.send(KeyEvent(key: .tab)))
        driver.step()
        #expect(!driver.shows("HELP-FOR-BUTTON"), "\(style): the help stayed after the focus left")
    }

    // MARK: - The frame after the walk

    /// Found by review, 2026-10-12: the status bar is sized before the walk,
    /// and the walk is where the focused control publishes its help, so a
    /// walk that changes what the bar should show leaves it for the next
    /// frame — and nothing asked for one. Under `.onFocus` with no delay the
    /// frame of a Tab drew the bar empty (the help of the control left behind
    /// goes at once), the control tabbed to published help due at once, and
    /// with no deadline to wake for and a breath replayed rather than
    /// rendered, its help never showed. These step only when a frame asked
    /// (`stepIfAsked`), as the live loop does; `step` renders regardless,
    /// which is how `focusMoveRemovesIt` passed with the gap open.
    @Test("Tabbing to a control under .onFocus with no delay shows its help", arguments: TooltipStyle.allCases)
    func tabShowsTheNextControlsHelp(style: TooltipStyle) {
        let driver = HelpDriver(TwoHelpedButtonsApp(style: style))
        driver.stepIfAsked()
        #expect(driver.shows("HELP-FOR-FIRST"), "precondition: \(style) shows the first button's help")
        #expect(driver.app.send(KeyEvent(key: .tab)))
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("HELP-FOR-SECOND"), "\(style): the second button's help never showed")
        #expect(!driver.shows("HELP-FOR-FIRST"), "\(style): the first button's help stayed")
    }

    /// Help revealed with `?` whose text changes under the focus: the
    /// press's frame is sized from the old text, and the walk publishes the
    /// new; the next frame must show the new.
    @Test("Help revealed with ? follows its text when the text changes")
    func revealedHelpFollowsItsText() {
        let driver = HelpDriver(ChangingHelpApp())
        #expect(driver.app.send(KeyEvent(character: "?")))
        driver.step()
        #expect(driver.shows("HELP-PLAY"), "precondition: ? shows the help")
        #expect(driver.app.send(KeyEvent(key: .enter)))
        driver.step()
        #expect(driver.shows("pause"), "precondition: the press toggled the button")
        driver.stepIfAsked()
        #expect(driver.shows("HELP-PAUSE"), "the new help never showed: \(driver.lines)")
        #expect(!driver.shows("HELP-PLAY"), "the old help stayed: \(driver.lines)")
    }

    /// The focused control stops carrying help while it is revealed: the bar
    /// must let it go rather than keep the text of help that is gone.
    @Test("Help revealed with ? goes when the focused control stops carrying it")
    func revealedHelpGoesWithIt() {
        let driver = HelpDriver(ChangingHelpApp(dropsHelp: true))
        #expect(driver.app.send(KeyEvent(character: "?")))
        driver.step()
        #expect(driver.shows("HELP-PLAY"), "precondition: ? shows the help")
        #expect(driver.app.send(KeyEvent(key: .enter)))
        driver.step()
        driver.stepIfAsked()
        #expect(!driver.shows("HELP-"), "help that is gone stayed in the bar: \(driver.lines)")
    }

    // MARK: - Views that cannot take the focus

    /// The owner's 2026-10-12 ruling: `help(_:)` works on a view that cannot
    /// take the focus, by hover. It always did (MISC12 §3.2 cases A and B);
    /// pinned here through the run loop so it stays that way — and it stays
    /// up for as long as the pointer rests, frame after frame.
    @Test("Hovering a view that cannot take the focus shows its help", arguments: TooltipStyle.allCases)
    func hoverOnANonFocusableView(style: TooltipStyle) throws {
        let driver = Driver(HelpPageApp(trigger: .automatic, style: style, topLeading: true))
        let text = try #require(driver.position(of: "plain text"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: text.x + 1, y: text.y))
        driver.step()
        #expect(!driver.shows("HELP-FOR-TEXT"), "\(style): shown before the pointer had rested")
        driver.run(until: 0.7)
        #expect(driver.shows("HELP-FOR-TEXT"), "\(style): hover showed nothing")
        driver.run(until: 1.5)
        #expect(driver.shows("HELP-FOR-TEXT"), "\(style): the help went while the pointer rested")
    }

    /// **Known defect, found 2026-10-12 and not fixed here** (decisions
    /// A-HELP-1). The status bar grows upwards for a tooltip, so the page
    /// above it is a row or two shorter; a page laid out in the middle of the
    /// window moves up, the view slides out from under a resting pointer, the
    /// dispatcher reports it left, and the tooltip goes, the page moves back,
    /// the pointer is on the view again and the delay restarts. Measured: shown
    /// for one frame in every 0.6 s. The popover moves nothing and is
    /// unaffected (the pin above runs both styles). When this starts passing,
    /// drop `withKnownIssue` and the decisions entry.
    @Test("A hover tooltip in the status bar stays up over a page laid out in the middle")
    func hoverOverACentredPage() throws {
        let driver = Driver(HelpPageApp(trigger: .automatic, style: .statusBar))
        let text = try #require(driver.position(of: "plain text"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: text.x + 1, y: text.y))
        driver.run(until: 0.7)
        let shownFrames = (0..<30).reduce(0) { count, _ in
            driver.step()
            return count + (driver.shows("HELP-FOR-TEXT") ? 1 : 0)
        }
        withKnownIssue("A-HELP-1: the bar's growth moves a centred page out from under the pointer") {
            #expect(shownFrames == 30, "shown in \(shownFrames) of 30 frames")
        }
    }

    /// The app-wide feature, `.tooltips(.always)`, with a focusable and a
    /// non-focusable view: both panels are readable, and neither covers the
    /// other view. Measured before the panels were placed as a set (MISC12
    /// §3.2 case F), the `Button`'s covered the `Text`'s.
    @Test("Under .always every panel is drawn whole, over neither view", arguments: TooltipStyle.allCases)
    func alwaysShowsEveryPanel(style: TooltipStyle) {
        let driver = Driver(HelpPageApp(trigger: .always, style: style))
        driver.step()
        #expect(driver.shows("HELP-FOR-BUTTON"), "\(style): \(driver.lines)")
        #expect(driver.shows("HELP-FOR-TEXT"), "\(style): the Text's panel was covered: \(driver.lines)")
        #expect(driver.shows("plain text"), "\(style): a panel covers the Text: \(driver.lines)")
        #expect(driver.shows("button"), "\(style): a panel covers the Button: \(driver.lines)")
    }

    /// Found by review, 2026-10-12: a panel inside `.offset` rode in the
    /// offset's layer and was placed alone when that layer composited, so the
    /// page's panel went directly below its view, over the offset view, and
    /// the offset view's panel over the page's.
    @Test("Under .always a panel inside .offset is placed with the page's")
    func alwaysPlacesAnOffsetViewsPanelWithThePages() {
        let driver = HelpDriver(OffsetHelpApp())
        driver.step()
        for text in ["a-view", "b-view", "AAAA", "BBBB"] {
            #expect(driver.shows(text), "\(text) is covered: \(driver.lines)")
        }
    }

    /// No room for both panels: the first in reading order has its panel and
    /// the other is left out rather than drawn over it — and pointing at the
    /// view that lost its panel brings that one back, which is how a reader
    /// gets at every view's help on a page too dense for all of them.
    @Test("On a page too dense for every panel, the hovered view's panel is the one drawn")
    func densePageRanksTheHoveredView() {
        let driver = HelpDriver(DenseHelpApp(), width: 22, height: 5)
        driver.step()
        #expect(driver.shows("FIRST-HELP-TEXT"), "the first in reading order is drawn: \(driver.lines)")
        #expect(!driver.shows("SECOND-HELP-TEXT"), "and the second is left out: \(driver.lines)")
        // The second `Text` is on the second row, under the first's panel.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: 2, y: 1))
        driver.step()
        #expect(driver.shows("SECOND-HELP-TEXT"), "the hovered view's panel is drawn: \(driver.lines)")
        #expect(!driver.shows("FIRST-HELP-TEXT"), "in place of the other: \(driver.lines)")
        // And the pointer leaving gives the room back to reading order.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: 20, y: 4))
        driver.step()
        #expect(driver.shows("FIRST-HELP-TEXT"), "reading order again after the pointer left: \(driver.lines)")
    }
}
