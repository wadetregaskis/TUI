//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessApp.swift
//
//  An app driven frame by frame with no terminal: the real render loop and the
//  real input chain, over an in-memory terminal, for a harness that plays an
//  interaction script against an app and watches what it draws.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitChrome
import TUIkitFoundation

// MARK: - Headless App

/// An app assembled the way `AppRunner` assembles one — `RenderLoop`, the
/// five-layer ``InputHandler``, the focus manager, the status bar state,
/// the theme managers — and driven one frame at a time, with no terminal, no
/// signals and no stdin.
///
/// For the `Stress` harness's SESSIONS: an interaction script played against an
/// app, frame after frame, the way a person uses one. A key goes through the
/// chain a keypress goes through, so it reaches the focused control, moves the
/// focus, scrolls the scroll view that owns the key; a frame is the loop's own
/// frame, chrome and diff writer included, so what it costs is
/// what a frame costs. The existing `--bench` renders a view with
/// `renderToBuffer`, which has none of that — no focus manager to type into,
/// no chrome, no emission.
///
/// Time is the caller's: ``frame(atNanos:)`` takes the frame's instant, so two
/// instances fed the same script draw the same pictures, carets and spinners
/// included. A hover or a click arrives at the caller's time too — at the
/// instant of the frame before it, which is the last time the caller named — so
/// what counts from it counts the same in both: a tooltip's delay, and the
/// window that makes two clicks a double click. Not every event path yet: the
/// wheel's edge grace (`WheelEdgeHold`), a link's key-repeat window and a held
/// arrow's repeat still read the machine's clock. Read off the machine's clock, as the
/// hover once was, each instance stamped its own arrival, microseconds apart
/// and further on a loaded machine, so a tooltip could appear a frame sooner in
/// one than in the other; and its delay counted from wherever the machine's
/// clock had got to, which a script stepping its own frames cannot see — a slow
/// machine put the tooltip past the last frame the script played. And a resize
/// is what `SIGWINCH` does in the app — the terminal reports the new size and
/// the diff writer forgets what it drew.
///
/// A change made inside `withAnimation` plays out over the frames that follow
/// it, as it does in the app: each frame is fenced by an ``AnimationScheduler``
/// the way `AppRunner.renderFrame` fences it. Without one a frame cannot
/// animate — `AnimationFrame.canAnimate` is false, because a one-off render
/// would show an animation's first value and never advance — so every
/// animated change, every transition in and out, landed on its end state in
/// one frame, and a harness that exists to watch what an app draws could not
/// see any of them move. Only the fence: the loop's next firing is still the
/// caller's to choose, since time is.
///
/// `package`, not public: harness plumbing, not API.
@MainActor
package final class HeadlessApp<A: App> {
    private let terminal: InMemoryTerminal
    private let renderer: RenderLoop<A>
    private let inputHandler: InputHandler
    private let tuiContext: TUIContext
    private let focusManager: FocusManager
    private let animationScheduler = AnimationScheduler()
    /// The quits asked for: see ``quitsRequested``.
    private let quits: QuitCount
    /// The instant of the last frame, which the mouse dispatcher reads as the
    /// time an event arrives. See the type's discussion.
    private let eventClock = EventClock()

    /// Whether every frame starts from an EMPTY render cache — every memo
    /// missing, every kept size and buffer gone. `@State` survives, as it does
    /// across frames in the app; only what the cache keeps does not. The
    /// oracle a session holds a normal instance against: a cache is right
    /// exactly when a frame drawn through it is the frame drawn without it.
    package var clearsRenderCacheEachFrame = false

    /// Assembles `app` over an in-memory terminal of `width` × `height` cells.
    package init(_ app: A, width: Int, height: Int) {
        let terminal = InMemoryTerminal(width: width, height: height)
        let quits = QuitCount()
        self.quits = quits
        // The context's render state, which its cache's link asks for frames
        // and its loop draws the pending transaction of: the app's own, as
        // `AppRunner`'s is, so two instances in one process — the warm and the
        // cold app a session compares, two tests at once — never take each
        // other's.
        let tuiContext = TUIContext()
        let statusBar = StatusBarState(appState: tuiContext.appState)
        let focusManager = FocusManager()
        let paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: {})
        let appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: {})
        self.terminal = terminal
        self.tuiContext = tuiContext
        self.focusManager = focusManager
        self.renderer = RenderLoop(
            app: app, terminal: terminal, statusBar: statusBar,
            focusManager: focusManager, paletteManager: paletteManager,
            appearanceManager: appearanceManager, tuiContext: tuiContext, isTmux: false)
        self.inputHandler = InputHandler(
            statusBar: statusBar, keyEventDispatcher: tuiContext.keyEventDispatcher,
            focusManager: focusManager, paletteManager: paletteManager,
            appearanceManager: appearanceManager, keyboardShortcuts: tuiContext.keyboardShortcuts,
            dragAndDropSession: tuiContext.dragAndDropSession,
            tooltipState: tuiContext.tooltipState, unhandledKeyBell: tuiContext.terminalBell,
            // A script has no process to quit or suspend: a quit is counted.
            onQuit: { quits.count += 1 }, onSuspend: {}, screenSelection: tuiContext.screenSelection)
        // The last window closing asks the app to quit: counted, as the quit
        // key's quit is, rather than asked of the process's `AppState`.
        renderer.scenes.requestExit = { quits.count += 1 }
        // As `AppRunner` wires it, so a click on a status-bar item that only
        // names a key goes through the same chain the key does.
        let inputHandler = self.inputHandler
        tuiContext.synthesizeKeyEvent = { _ = inputHandler.handle($0) }
        // The dispatcher's clock is the one an arrival is read on — the hover
        // that starts a tooltip's delay, the press that may make a double click.
        let eventClock = self.eventClock
        tuiContext.mouseEventDispatcher.nowNanos = { eventClock.nanos }
        // Counted where `AppRunner.wireFocusRepaints` asks the loop for them.
        focusManager.onFocusChange = { [weak self] in self?.framesAsked += 1 }
        focusManager.focusedValues.requestFrame = { [weak self] in self?.framesAsked += 1 }
    }

    /// How many frames the focus system has asked for, where the app's run
    /// loop is asked (`AppRunner.wireFocusRepaints`): a move of the focus to
    /// show, a `@FocusedValue` reader to catch up. A harness renders whenever
    /// it is told to, so a frame asked for shows only here — and a count that
    /// goes on rising over frames that change nothing is an app that never
    /// idles.
    package private(set) var framesAsked = 0

    /// How many times the app quit — the quit key, the menu bar's Quit —
    /// where a running app's loop would have ended. A script has no process
    /// to end, so it carries on.
    package var quitsRequested: Int { quits.count }

    /// Renders one frame at `nanos` on the monotonic clock's scale, and at
    /// `date` on the wall clock — the date a `TimelineView` resolves its
    /// schedule against. The wall clock now unless given, since a script that
    /// holds no timeline has no use for one of its own.
    ///
    /// Events sent after it arrive at `nanos`, and so does a hover the frame
    /// itself moves onto a resting pointer.
    package func frame(atNanos nanos: Int64, date: Date = FrameClock.nowDate) {
        // This app's work, as `AppRunner.run()` binds its whole run: a change
        // made with no view in hand asks this app for its frame.
        AmbientApp.$renderState.withValue(tuiContext.appState) { drawFrame(atNanos: nanos, date: date) }
    }

    private func drawFrame(atNanos nanos: Int64, date: Date) {
        eventClock.nanos = UInt64(bitPattern: nanos)
        if clearsRenderCacheEachFrame { tuiContext.renderCache.clearAll() }
        animationScheduler.beginFrame()
        renderer.render(animationScheduler: animationScheduler, frameNowNanos: nanos, frameDate: date)
        animationScheduler.endFrame()
        // As `AppRunner.renderFrame` ends a frame: the events until the next one
        // are filtered against the support the frame asked for, the scene's
        // base with what its views requested (an `.onHover` asks for motion),
        // and the reshape after the next walk reads it as the mode the pointer
        // last reported under. Not set, the dispatcher kept the base the walk
        // sets mid-frame, so a pointer's move in an app that declares no
        // `.mouseSupport` was dropped here, though the app hears it.
        tuiContext.mouseEventDispatcher.setActiveSupport(renderer.effectiveMouseSupport(), isFrameFinal: true)
        // As `AppRunner` presses them, once the frame is drawn: a menu bar's
        // item's key, or its Quit. The next frame shows what they did.
        for owed in tuiContext.keysAfterFrame.take() { inputHandler.perform(owed) }
    }

    /// Delivers a key through the five-layer chain, as a keypress is — noted
    /// first as the keyboard's, as the app's event funnel notes it.
    /// - Returns: Whether some layer consumed it.
    @discardableResult
    package func send(_ event: KeyEvent) -> Bool {
        focusManager.noteInputSource(.keyboard)
        tuiContext.mouseEventDispatcher.noteInput()
        return AmbientApp.$renderState.withValue(tuiContext.appState) { inputHandler.handle(event) }
    }

    /// Delivers a mouse event to the handlers the last frame registered, as
    /// the app's event funnel delivers one: noted as the pointer's, which is
    /// what a menu it opens asks (the pointer highlights nothing, the keyboard
    /// the first item), and in the screen's coordinates — where a script aims,
    /// at what it sees — which are the frame's, chrome and all.
    /// - Returns: Whether a handler consumed it.
    @discardableResult
    package func send(_ event: MouseEvent) -> Bool {
        focusManager.noteInputSource(.pointer)
        return AmbientApp.$renderState.withValue(tuiContext.appState) {
            tuiContext.mouseEventDispatcher.dispatch(event, noting: focusManager)
        }
    }

    /// Reports the terminal's window gaining or losing the focus, as a focus
    /// report (mode 1004) does: losing it lets go of the pointer, as the app's
    /// event funnel does (``MouseEventDispatcher/pointerLeft()``). The scene's
    /// phase is the app's run loop's, which a script does not run.
    package func reportFocus(_ isFocused: Bool) {
        if !isFocused { tuiContext.mouseEventDispatcher.pointerLeft() }
    }

    /// Changes the terminal's size, as `SIGWINCH` reports it: the next frame
    /// is laid out at the new size and rewrites every line.
    package func resize(width: Int, height: Int) {
        terminal.size = (width, height)
        renderer.invalidateDiffCache()
    }

    /// The focused control's id, `nil` when nothing holds the focus.
    package var focusedID: String? { focusManager.currentFocusedID }

    /// The frame on screen — the bars and the content, row by row — as the
    /// diff writer last built it for the terminal.
    package var screen: [String] { renderer.diffWriter.shownLines }

    /// How many bytes every frame so far has written to the terminal.
    package var bytesWritten: Int { terminal.bytesWritten }

    /// How many times a frame rang the terminal's bell (``TerminalBell``).
    package var bellsWritten: Int { terminal.bellsWritten }

    /// Where the frames so far left the terminal's cursor, in cells from the
    /// top-left, if they put it somewhere and wrote nothing after —
    /// where they parked it (`RenderLoop.parkCursor`) — or `nil`.
    package var cursor: CellPoint? { terminal.cursor }

    /// The app's render cache, for what its counters say about the frames: how
    /// many rows were served and how many drawn, what the memos hit.
    package var renderCache: RenderCache { tuiContext.renderCache }

    /// The app's runtime services — for a test that hands it a clipboard
    /// writer of its own, or reads its screen selection.
    var services: TUIContext { tuiContext }

    /// The app's windows: which are open, in what order.
    package var scenes: ScenePresenter { renderer.scenes }

    /// The title the frames have given the terminal's window, or `nil` while
    /// it shows its own (``TerminalHostState``).
    var terminalWindowTitle: String? { renderer.hostState.writtenTitle }

    /// What the frames wrote to the terminal beyond its cells — each title
    /// change, with the save before the first, and each progress report — in
    /// order.
    var hostWrites: [String] { terminal.hostWrites }

    /// What handing the terminal back — a suspend, the exit — would write,
    /// written to it as the app's hand-back does.
    func handBackHostState() {
        terminal.write(renderer.handBackHostState())
    }

    /// What the app's run loop writes between frames at `nanos`, where the
    /// progress bar is due to be sent again, written as it writes it — with
    /// no frame (`AppRunner.keepHostStateAlive`).
    func keepHostStateAlive(atNanos nanos: Int64) {
        let resend = renderer.hostState.keepAlive(atNanos: nanos)
        if !resend.isEmpty { terminal.write(resend) }
    }

    /// When the run loop would next send the progress bar again, with nothing
    /// else to wake it (``TerminalHostState/keepAliveDeadline``).
    var hostStateKeepAliveDeadline: Int64? { renderer.hostState.keepAliveDeadline }

    /// Whether the frames send the terminal the progress bar the views state,
    /// as the app runner sets it for a terminal that takes one
    /// (`RenderLoop.sendsProgressReports`): `false` until a test says so.
    var sendsProgressReports: Bool {
        get { renderer.sendsProgressReports }
        set { renderer.sendsProgressReports = newValue }
    }

    /// How many views' parting pictures the app is holding — every view with a
    /// transition that is on screen, and every removal still playing. A removal
    /// that has played out is no longer counted.
    package var departureCount: Int { tuiContext.stateStorage.departures.count }

    /// The soonest instant after `nanos` that anything the last frame declared
    /// — a lattice or a one-shot wake — asks to be drawn at: what the app's run
    /// loop would sleep until. `nil` when nothing asked, and a real loop would
    /// idle. A harness renders whenever it is told to, so a wake nobody
    /// declared shows only here.
    package func nextWake(after nanos: Int64) -> Int64? {
        animationScheduler.nextFiring(after: nanos)
    }
}

/// The caller's clock, as the mouse dispatcher reads it: a box, so the
/// dispatcher's closure holds the clock rather than the app that owns the
/// dispatcher.
private final class EventClock {
    /// The last frame's instant; zero before the first frame.
    var nanos: UInt64 = 0
}

// MARK: - In-Memory Terminal

/// A ``TerminalProtocol`` that writes nowhere and counts what it was asked to
/// write: the terminal a ``HeadlessApp`` draws on.
@MainActor
final class InMemoryTerminal: TerminalProtocol {
    var size: (width: Int, height: Int)
    private(set) var bytesWritten = 0
    /// How many lone `BEL`s were written: the terminal's bell, which a frame
    /// writes as a write of its own (``TerminalBell/takePending()``).
    private(set) var bellsWritten = 0
    /// Where the cursor was last put, in cells from the top-left, or `nil`
    /// once something has been drawn after it, which moved it on.
    private(set) var cursor: CellPoint?
    /// The writes that set or restored the window title, or reported progress
    /// (``TerminalHostState``).
    private(set) var hostWrites: [String] = []

    init(width: Int, height: Int) {
        size = (width, height)
    }

    func getSize() -> (width: Int, height: Int) { size }
    func write(_ string: String) {
        bytesWritten &+= string.utf8.count
        if string == "\u{07}" { bellsWritten += 1 }
        if string.hasPrefix(TerminalHostState.saveTitle) || string.hasPrefix(TerminalHostState.restoreTitle)
            || string.hasPrefix("\u{1B}]2;") || string.hasPrefix("\u{1B}]9;")
        {
            hostWrites.append(string)
        }
        if cursor != nil, !string.stripped.isEmpty { cursor = nil }
    }
    func readKeyEvent() -> KeyEvent? { nil }
    func enableRawMode() {}
    func disableRawMode() {}
    func beginFrame() {}
    func endFrame() {}
    // Counted as what a real terminal is sent for it, so the byte total is
    // the emission volume: a frame that repositions more writes more.
    func moveCursor(toRow row: Int, column: Int) {
        write(ANSIRenderer.moveCursor(toRow: row, column: column))
        cursor = CellPoint(x: column - 1, y: row - 1)
    }
    func hideCursor() {}
    func showCursor() {}
    func enterAlternateScreen() {}
    func exitAlternateScreen() {}
}

/// A ``HeadlessApp``'s quits, counted where the app's would end its loop.
private final class QuitCount {
    var count = 0
}
