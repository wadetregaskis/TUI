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

/// A focused button that puts a row above two `Text`s with help, so the
/// first slides under a pointer resting on the second, and the second under
/// one resting on the blank row below it: a hover that the frame's reshape
/// starts once the walk is over, rather than a mouse event between frames.
private struct SlidingHelpApp: App {
    var style: TooltipStyle = .statusBar

    init() {}

    init(style: TooltipStyle) {
        self.style = style
    }

    var body: some Scene {
        WindowGroup {
            SlidingHelpPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tooltipStyle(style)
        }
        .mouseSupport(.full)
    }
}

private struct SlidingHelpPage: View {
    @State private var inserted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("insert") { inserted = true }
            if inserted { Text("new row") }
            Text("slides").help("HELP-SLIDES")
            Text("rested on").help("HELP-RESTED-ON")
        }
    }
}

/// The review's page (2026-10-12): three rows of `Text`, the first with help,
/// laid out in the middle of the window, as a `WindowGroup` lays out a page
/// that does not fill it. Nothing on it hovers but the help, so nothing else
/// asks for a frame.
private struct CentredTextsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text("alpha").help("HELP-A")
                Text("beta")
                Text("gamma")
            }
        }
        .mouseSupport(.full)
    }
}

/// A centred page like that one under a focused button, which takes the
/// `Text` with help away (another takes its row) or presents a sheet over the
/// page. Five rows, so the bar's row moves it as it moves three.
private struct CentredHelpUnderAButtonApp: App {
    var presentsSheet = false

    init() {}

    init(presentsSheet: Bool) {
        self.presentsSheet = presentsSheet
    }

    var body: some Scene {
        WindowGroup {
            CentredHelpUnderAButtonPage(presentsSheet: presentsSheet)
        }
        .mouseSupport(.full)
    }
}

private struct CentredHelpUnderAButtonPage: View {
    let presentsSheet: Bool
    @State private var removed = false
    @State private var sheetShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("press") {
                if presentsSheet { sheetShown = true } else { removed = true }
            }
            if removed { Text("other") } else { Text("alpha").help("HELP-A") }
            Text("beta")
            Text("gamma")
            Text("delta")
        }
        .sheet(isPresented: $sheetShown) {
            Text("SHEET-BODY")
        }
    }
}

/// The HELP lane review's page (decisions-HELP A-HELP-1, "Left open"): a
/// `ScrollView` of rows with help that fills the window, so the status bar
/// growing for a hover tooltip moves nothing and covers the page's last
/// visible rows instead — as many as the tooltip takes, `helpLines` of text
/// in the bar's chrome style.
///
/// `presentsSheet`: a focused button above the rows presents a sheet over the
/// page when pressed.
private struct FullWindowRowsApp: App {
    var chrome: ChromeStyle = .bordered
    var helpLines = 1
    var presentsSheet = false

    init() {}

    init(chrome: ChromeStyle, helpLines: Int, presentsSheet: Bool = false) {
        self.chrome = chrome
        self.helpLines = helpLines
        self.presentsSheet = presentsSheet
    }

    var body: some Scene {
        WindowGroup {
            FullWindowRowsPage(helpLines: helpLines, presentsSheet: presentsSheet)
        }
        .windowToolbarStyle(WindowToolbarStyleCase.drawing(chrome).style)
        .mouseSupport(.full)
    }
}

private struct FullWindowRowsPage: View {
    let helpLines: Int
    let presentsSheet: Bool
    @State private var sheetShown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if presentsSheet { Button("present") { sheetShown = true } }
                ForEach(0..<40, id: \.self) { index in
                    Text("row \(index)").help(help(index))
                }
            }
        }
        .sheet(isPresented: $sheetShown) {
            Text("SHEET-BODY")
        }
    }

    /// One line at the bar's width, or two: a 50-column bar's content is 46
    /// to 50 wide.
    private func help(_ index: Int) -> String {
        helpLines == 1 ? "HELP-\(index)" : "HELP-\(index) " + String(repeating: "wraps ", count: 9)
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

    /// The `helpLines`-th row of `FullWindowRowsApp`'s from the bottom of
    /// the screen: its index, and where it is drawn.
    func visibleRow(helpLines: Int) -> (index: Int, x: Int, y: Int)? {
        let visible = lines.enumerated().compactMap { row, line -> (index: Int, x: Int, y: Int)? in
            guard let range = line.range(of: #"row \d+"#, options: .regularExpression),
                let index = Int(line[range].dropFirst(4))
            else { return nil }
            return (index, line.distance(from: line.startIndex, to: range.lowerBound), row)
        }
        return visible.dropLast(helpLines - 1).last
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

    /// Found by review, 2026-10-12: a reshape that slides a view with help
    /// under a resting pointer makes it the hover candidate after the walk
    /// (`MouseEventDispatcher.setRegions` re-resolves the hover), and the
    /// wake for the end of its delay was asked for only during the walk, by
    /// the view itself — which had already drawn. Nothing woke for it, and
    /// its help never showed while the pointer rested.
    @Test("A view a reshape slides under the resting pointer shows its help after the delay",
          arguments: TooltipStyle.allCases)
    func reshapeSlidesAViewUnderThePointer(style: TooltipStyle) throws {
        let driver = HelpDriver(SlidingHelpApp(style: style))
        let restedOn = try #require(driver.position(of: "rested on"))
        // On the second `Text`, until its help shows: nothing is pending then,
        // so no wake of its own can stand in for the one under test.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: restedOn.x + 1, y: restedOn.y))
        driver.step()
        driver.run(until: 0.7)
        #expect(driver.shows("HELP-RESTED-ON"), "precondition: \(style) shows the rested-on view's help")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        #expect(driver.position(of: "slides")?.y == restedOn.y, "precondition: the first Text slid under the pointer")
        let pressed = driver.now
        while driver.now < pressed + 700_000_000, driver.stepIfAsked() {}
        #expect(driver.shows("HELP-SLIDES"), "\(style): nothing woke for the delay: \(driver.lines)")
    }

    /// decisions-HELP A-HELP-1, "Left open": under the popover style the walk
    /// attaches the panel of the candidate it finds, and a reshape that slides
    /// another view with help under the resting pointer makes that one the
    /// candidate after the walk. Nothing asked for a frame until the new
    /// candidate's delay ran out, so the old panel stayed up that long.
    @Test("Under the popover style a panel goes the frame after a reshape slides another view under the pointer")
    func popoverGoesWhenAReshapeReplacesItsView() throws {
        let driver = HelpDriver(SlidingHelpApp(style: .popover))
        let restedOn = try #require(driver.position(of: "rested on"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: restedOn.x + 1, y: restedOn.y))
        driver.step()
        driver.run(until: 0.7)
        #expect(driver.shows("HELP-RESTED-ON"), "precondition: shown: \(driver.lines)")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        #expect(driver.shows("HELP-RESTED-ON"), "precondition: the frame of the press drew the old panel")
        let pressed = driver.now
        #expect(driver.stepIfAsked(), "nothing asked for a frame")
        #expect(driver.now - pressed < 100_000_000, "the next frame came \(driver.now - pressed) ns later")
        #expect(!driver.shows("HELP-RESTED-ON"), "the old panel stayed up: \(driver.lines)")
    }

    /// Found by the HELP lane's review (A-HELP-1, "Left open"): the dispatcher
    /// re-resolved the hover after a reshape only for a pointer that was over
    /// something, so a view slid under a pointer resting on blank space got no
    /// `.entered`, and its help never started its delay until the pointer moved.
    @Test("A view a reshape slides under a pointer resting on nothing shows its help after the delay",
          arguments: TooltipStyle.allCases)
    func reshapeSlidesAViewUnderAPointerOnNothing(style: TooltipStyle) throws {
        let driver = HelpDriver(SlidingHelpApp(style: style))
        let restedOn = try #require(driver.position(of: "rested on"))
        // The blank row below the last `Text`.
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: restedOn.x + 1, y: restedOn.y + 1))
        driver.step()
        driver.run(until: 0.7)
        #expect(!driver.shows("HELP-"), "precondition: \(style): the pointer rests on nothing: \(driver.lines)")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        #expect(driver.position(of: "rested on")?.y == restedOn.y + 1, "precondition: it slid under the pointer")
        let pressed = driver.now
        while driver.now < pressed + 700_000_000, driver.stepIfAsked() {}
        #expect(driver.shows("HELP-RESTED-ON"), "\(style): no help for the view slid under the pointer: \(driver.lines)")
    }

    /// Decided 2026-10-12 (decisions-HELP A-HELP-1, option 1). The status bar
    /// grows upwards for a tooltip, so the page above it is a row shorter, and
    /// a page laid out in the middle of the window moves up; the view slides
    /// out from under a resting pointer. Taken as the pointer leaving, that
    /// took the tooltip away, gave the row back, slid the view under the
    /// pointer again and restarted the delay: shown for one frame in every
    /// 0.6 s. A reshape the bar's rows for a tooltip cause is not a hover
    /// change to the tooltip (`TooltipState.held`). This steps every frame
    /// (`step`), so a frame drawn for any reason keeps it; the popover moves
    /// nothing and never had the defect (`hoverOnANonFocusableView`).
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
        #expect(shownFrames == 30, "shown in \(shownFrames) of 30 frames")
    }

    /// The review's reproduction (2026-10-12), stepping only the frames
    /// something asked for, as the live loop draws them. Once a walk's
    /// change to the bar asked for its frame (e73abfced), the help was on
    /// screen for one frame and did not come back while the pointer rested:
    /// the frame after it drew the bar empty, the page moved back, and the
    /// re-entry that restarted the delay came after the walk, which no wake
    /// answered.
    @Test("Over a centred page the hovered help shows after its delay, stays while the pointer rests, and goes when it moves off")
    func hoverRestsOverACentredPage() throws {
        let driver = HelpDriver(CentredTextsApp())
        let alpha = try #require(driver.position(of: "alpha"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: alpha.x + 1, y: alpha.y))
        driver.step()
        #expect(!driver.shows("HELP-A"), "shown before the pointer had rested")
        #expect(driver.stepIfAsked(), "nothing asked for the frame at the end of the delay")
        #expect(driver.shows("HELP-A"), "the delay's frame showed nothing: \(driver.lines)")
        #expect(driver.position(of: "alpha")?.y != alpha.y, "precondition: the bar's growth moved the page")
        let shownFrames = (0..<30).reduce(0) { count, _ in
            driver.stepIfAsked()
            return count + (driver.shows("HELP-A") ? 1 : 0)
        }
        #expect(shownFrames == 30, "shown in \(shownFrames) of 30 frames while the pointer rested")
        // Off the page, on the same row: the help goes, and the move is what
        // asks for the frame that takes it away.
        #expect(
            driver.app.send(MouseEvent(button: .none, phase: .moved, x: 45, y: alpha.y)),
            "nothing asked for the frame that takes the help away")
        driver.step()
        driver.stepIfAsked()
        #expect(!driver.shows("HELP-A"), "the help stayed after the pointer moved off: \(driver.lines)")
    }

    /// The bar moved the page, so the help's view is a row from the pointer:
    /// a pointer that moves onto it where it now is keeps the help up, its
    /// delay served, as one that moves off takes it away.
    @Test("A help held through the bar's reflow stays when the pointer moves onto its view again")
    func heldHelpStaysOnItsView() throws {
        let driver = HelpDriver(CentredTextsApp())
        let alpha = try #require(driver.position(of: "alpha"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: alpha.x + 1, y: alpha.y))
        driver.step()
        driver.stepIfAsked()
        let moved = try #require(driver.position(of: "alpha"))
        #expect(driver.shows("HELP-A"), "precondition: shown: \(driver.lines)")
        #expect(moved.y != alpha.y, "precondition: the bar's growth moved the page")
        #expect(
            driver.app.send(MouseEvent(button: .none, phase: .moved, x: moved.x + 2, y: moved.y)),
            "precondition: the move onto the view was heard")
        driver.step()
        #expect(driver.shows("HELP-A"), "the help went as the pointer moved onto its view: \(driver.lines)")
        // Every frame, so a delay restarted by the move cannot pass unseen.
        let shownFrames = (0..<10).reduce(0) { count, _ in
            driver.step()
            return count + (driver.shows("HELP-A") ? 1 : 0)
        }
        #expect(shownFrames == 10, "shown in \(shownFrames) of 10 frames after the pointer moved onto its view")
    }

    /// No hover transition reaches a held help's view, the pointer being
    /// elsewhere, so the frame itself asks whether a pointer could still rest
    /// on it: one whose view has gone, or that a sheet covers, goes.
    @Test("A help held through the bar's reflow goes when its view goes or is covered", arguments: [false, true])
    func heldHelpGoesWithItsView(presentsSheet: Bool) throws {
        let driver = HelpDriver(CentredHelpUnderAButtonApp(presentsSheet: presentsSheet))
        let alpha = try #require(driver.position(of: "alpha"))
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: alpha.x + 1, y: alpha.y))
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("HELP-A"), "precondition: shown: \(driver.lines)")
        #expect(driver.position(of: "alpha")?.y != alpha.y, "precondition: the bar's growth moved the page")
        #expect(driver.app.send(KeyEvent(key: .enter)), "the button took the press")
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("SHEET-BODY") == presentsSheet, "precondition: the sheet: \(driver.lines)")
        #expect(!driver.shows("HELP-A"), "the help outlived its view: \(driver.lines)")
    }

    /// decisions-HELP A-HELP-1, "Left open": on a page that fills the window
    /// the bar's new rows do not move the page, they cover its last visible
    /// rows. The hold found the hovered view unreachable and dropped it in the
    /// same frame; the next frame emptied the bar, the row came back under the
    /// pointer, and the help was on screen for one frame in every delay. A
    /// row covered by the tooltip's own bar still counts as its view's. Every
    /// chrome style, and a help of two lines with the pointer on the upper of
    /// the two rows it covers (a bordered bar takes up to three).
    @Test("Hovered help on a full-window page's last rows stays while the pointer rests, though its bar covers them",
          arguments: ChromeStyle.allCases, [1, 2])
    func hoverOnARowTheBarCovers(chrome: ChromeStyle, helpLines: Int) throws {
        let driver = HelpDriver(FullWindowRowsApp(chrome: chrome, helpLines: helpLines))
        // The last visible row, and the one `helpLines - 1` above it.
        let target = try #require(driver.visibleRow(helpLines: helpLines), "no rows: \(driver.lines)")
        let help = "HELP-\(target.index)"
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: target.x + 1, y: target.y))
        driver.step()
        #expect(!driver.shows(help), "\(chrome): shown before the pointer had rested")
        #expect(driver.stepIfAsked(), "\(chrome): nothing asked for the frame at the end of the delay")
        #expect(driver.shows(help), "\(chrome): the delay's frame showed nothing: \(driver.lines)")
        #expect(
            driver.position(of: "row \(target.index)") == nil,
            "precondition: \(chrome): the bar covers the row: \(driver.lines)")
        // Only the frames something asks for, as the live loop draws them…
        let askedFrames = (0..<30).reduce(0) { count, _ in
            driver.stepIfAsked()
            return count + (driver.shows(help) ? 1 : 0)
        }
        #expect(askedFrames == 30, "\(chrome): shown in \(askedFrames) of 30 frames while the pointer rested")
        // …and every frame, as one drawn for any other reason would be.
        let everyFrame = (0..<30).reduce(0) { count, _ in
            driver.step()
            return count + (driver.shows(help) ? 1 : 0)
        }
        #expect(everyFrame == 30, "\(chrome): shown in \(everyFrame) of 30 frames drawn while the pointer rested")
        #expect(driver.app.nextWake(after: driver.now) == nil, "\(chrome): the app does not idle")
        // A move off the row takes it away.
        #expect(
            driver.app.send(MouseEvent(button: .none, phase: .moved, x: 45, y: 0)),
            "\(chrome): nothing asked for the frame that takes the help away")
        driver.step()
        driver.stepIfAsked()
        #expect(!driver.shows(help), "\(chrome): the help stayed after the pointer moved off: \(driver.lines)")
    }

    /// Found by the BUGS13 lane's review: a help held while the pointer rests
    /// on the rows its bar covers was kept without asking whether its view
    /// is still in front, so a sheet a key (or a timer) presented over the
    /// page left the covered row's help in the bar, over the sheet, until the
    /// pointer moved.
    @Test("Help held on a row its bar covers goes when a sheet comes up over the page",
          arguments: ChromeStyle.allCases)
    func heldHelpOnACoveredRowGoesUnderASheet(chrome: ChromeStyle) throws {
        let driver = HelpDriver(FullWindowRowsApp(chrome: chrome, helpLines: 1, presentsSheet: true))
        let target = try #require(driver.visibleRow(helpLines: 1), "no rows: \(driver.lines)")
        let help = "HELP-\(target.index)"
        driver.app.send(MouseEvent(button: .none, phase: .moved, x: target.x + 1, y: target.y))
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows(help), "precondition: \(chrome): shown: \(driver.lines)")
        #expect(
            driver.position(of: "row \(target.index)") == nil,
            "precondition: \(chrome): the bar covers the row: \(driver.lines)")
        #expect(driver.app.send(KeyEvent(key: .enter)), "\(chrome): the button took the press")
        driver.step()
        driver.stepIfAsked()
        #expect(driver.shows("SHEET-BODY"), "precondition: \(chrome): the sheet: \(driver.lines)")
        #expect(!driver.shows(help), "\(chrome): the page's help stayed over the sheet: \(driver.lines)")
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
