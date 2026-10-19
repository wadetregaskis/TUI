//  🖥️ TUIkit — Terminal UI Kit for Swift
//  App.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitChrome
import TUIkitFoundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(WASILibc)
    import WASILibc
#endif

/// Whether the backtick frame-dump debug shortcut is armed — opt-in via
/// `TUIKIT_DEBUG_FRAME_DUMP=1`, same convention as `TUIKIT_DEBUG_FOCUS`.
/// File-scope (the runner is generic, which forbids static stored properties)
/// and read once: it's consulted per keystroke.
private let frameDumpEnabled: Bool =
    getenv("TUIKIT_DEBUG_FRAME_DUMP").map { String(cString: $0) == "1" } ?? false

// MARK: - App Protocol

/// The base protocol for TUIkit applications.
///
/// `App` is the entry point for every TUIkit application,
/// similar to `App` in SwiftUI.
///
/// # Example
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///         }
///     }
/// }
/// ```
@MainActor
public protocol App {
    /// The type of the main scene.
    associatedtype Body: Scene

    /// The main scene of the app.
    @SceneBuilder
    var body: Body { get }

    /// Initializes the app.
    init()

    /// The maximum render frame rate, in frames per second.
    ///
    /// Rendering is demand-driven: the app renders only when something changes,
    /// and never more often than this. A static screen (no animation, no input)
    /// renders nothing at all. Raise it for smoother animation, lower it to cap
    /// CPU while something is animating. Default: 60.
    var maxFrameRate: Int { get }
}

extension App {
    /// The maximum render frame rate (frames per second). Default 60; override
    /// `maxFrameRate` on your `App` to change it.
    public var maxFrameRate: Int { 60 }

    /// Starts the app.
    ///
    /// This method is called by the `@main` attribute and starts
    /// the main run loop of the application.
    ///
    /// `main()` is `async` so the run loop can suspend once per frame
    /// (via `Task.sleep`) instead of blocking the thread. Each suspension
    /// releases the main actor, so work scheduled with `Task { @MainActor }`,
    /// `MainActor.run`, or `DispatchQueue.main` runs interleaved with
    /// rendering — rather than being starved until the app exits.
    @MainActor
    public static func main() async {
        let app = Self()
        let runner = AppRunner<Self>(app: app)
        await runner.run()
    }
}

// MARK: - App Runner

/// Runs an App.
///
/// `AppRunner` is the main coordinator that owns the run loop and
/// delegates to specialized managers:
/// - `SignalManager` - POSIX signal handling (SIGINT, SIGWINCH)
/// - `InputHandler` - Key event dispatch (status bar, views, defaults)
/// - `RenderLoop` — Rendering pipeline (scene + status bar)
@MainActor
internal final class AppRunner<A: App> {
    private let app: A
    private let appearanceManager: ThemeManager
    private let appState: AppState
    private let focusManager: FocusManager
    private let paletteManager: ThemeManager
    private let statusBar: StatusBarState
    private let terminal: Terminal
    /// Internal rather than private so a test can read and set the scene phase
    /// the loop holds (see `terminalFocusChanged(isFocused:cursorTimer:)`).
    let tuiContext: TUIContext
    private var isRunning = false

    /// Which of ⌃4, ⌃| and ⌃⇧\\ the host may send ⌃\\'s byte for in its
    /// legacy encoding (`TerminalClient.quitByteAliases(_:)`): settled once
    /// the host is identified, at startup; until then, as for any host not
    /// measured, all of them.
    private var hostQuitByteAliases: TerminalClient.QuitByteAliases = .all

    /// The host's Reduce Motion, read at launch and whenever the terminal
    /// regains the focus (refusal review O1). Internal so a test can stand in
    /// for the host; `nil` until ``run()`` makes it.
    var hostMotion: HostReduceMotionRefresher?
    private let signals = SignalManager()

    /// - Parameters:
    ///   - app: The app whose scene this runner drives.
    ///   - appState: The app's render state: the render-request queue the loop
    ///     polls, the one every seam here signals, and the runner's context's
    ///     (`TUIContext.appState`), which a `@State` write and an `@Observable`
    ///     change reach through the render cache's link, and the changes made
    ///     with no view in hand reach as the app whose work is under way
    ///     (`AmbientApp`, bound by ``run()``). A fresh one by default: every app
    ///     has its own.
    ///
    ///     A parameter only so a TEST can hold the instance this runner signals
    ///     before it makes one; `tuiContext.appState` is the same object.
    init(app: A, appState: AppState = AppState()) {
        self.app = app
        self.appState = appState
        self.appearanceManager = ThemeManager(items: AppearanceRegistry.all, renderTrigger: { [appState] in appState.setNeedsRender() })
        self.focusManager = FocusManager()
        self.paletteManager = ThemeManager(items: PaletteRegistry.all, renderTrigger: { [appState] in appState.setNeedsRender() })
        // No style assignment here: the bars' default lives on the window's
        // chrome state, and an app picks another with
        // `Scene.windowToolbarStyle(_:)`. Overriding it here made that default
        // dead code and the footer a box under a ruled header.
        self.statusBar = StatusBarState(appState: appState)
        self.terminal = Terminal()
        // The one context whose copies reach this machine's clipboard (where
        // the rule sends them there at all), and whose links reach its URL
        // opener (where opening URLs is on): the app's, which runs the
        // platform's helpers. Every other context keeps both in memory.
        self.tuiContext = TUIContext(
            clipboard: SystemClipboard.Backend(), urlOpener: SystemURLOpener(), appState: appState)
    }
}

// MARK: - Internal API

extension AppRunner {
    /// Publishes this runner's URL opener to the actions no environment handed
    /// one (``TerminalURLOpening/runLoopOpener``): an `OpenURLAction` the app
    /// made itself and calls directly. ``run()`` calls it at startup and
    /// withdraws it when the run ends.
    ///
    /// Its own method only so a test can check what is published, in an exit
    /// test: it is the process's.
    func publishURLOpener() {
        TerminalURLOpening.runLoopOpener = tuiContext.urlOpener
    }

    /// The five-layer key-dispatch chain over the runner's collaborators —
    /// which an OSC 5522 paste asks, too, which of the clipboard's types the
    /// focused view's paste commands take.
    private func makeInputHandler() -> InputHandler {
        let handler = makeKeyDispatchChain()
        terminal.acceptsPasteType = { [handler] mime in handler.acceptsPaste(ofMIMEType: mime) }
        return handler
    }

    private func makeKeyDispatchChain() -> InputHandler {
        InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tuiContext.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            keyboardShortcuts: tuiContext.keyboardShortcuts,
            dragAndDropSession: tuiContext.dragAndDropSession,
            tooltipState: tuiContext.tooltipState,
            unhandledKeyBell: tuiContext.terminalBell,
            onQuit: { [weak self] in
                self?.isRunning = false
            },
            // Ctrl-Z, unconsumed by any view: give it its shell meaning by
            // re-raising the signal it would have been in cooked mode. The
            // SIGTSTP source observes it and the loop suspends between frames.
            onSuspend: {
                // Job control, so POSIX-only: wasip1 has no process to signal
                // and no shell to hand the terminal back to. Ctrl-Z there is a
                // keystroke like any other, and an app that wants it can bind
                // it; what it must not be is a crash.
                #if !canImport(WASILibc)
                    kill(getpid(), SIGTSTP)
                #endif
            },
            undoManager: tuiContext.undoManager,
            undoKeys: tuiContext.undoKeys,
            screenSelection: tuiContext.screenSelection,
            quitKey: { [terminal] in terminal.quitKeyByte },
            // The user's quit key, reported by the kitty keyboard protocol
            // rather than sent as the byte the driver acts on: the signal the
            // byte would have raised, to the process group the driver would
            // have raised it in (`QuitKeyReport`), which leaves the terminal
            // as a quit does (`FatalSignalTerminalRestore`).
            onQuitKey: {
                #if !canImport(WASILibc)
                    QuitKeyReport.quit()
                #endif
            },
            // ⌃\ may be ⌃4, ⌃| or ⌃⇧\ only in the legacy encoding: under the
            // kitty keyboard protocol each arrives as itself.
            quitByteAliasing: { [weak self, terminal] in
                terminal.keyboardEnhancement.isEmpty ? (self?.hostQuitByteAliases ?? .all) : []
            }
        )
    }

    /// Makes the app's one undo manager and hands it to everything that uses
    /// it: the environment (`\.undoManager`, through the context), the input
    /// chain's undo and redo keys, and the status bar's undo and redo items.
    /// Here rather than in `TUIContext`'s initialiser because `UndoManager` is
    /// isolated to the main actor, and that initialiser is not.
    private func makeUndoManager() {
        let undoManager = UndoManager()
        tuiContext.undoManager = undoManager
        statusBar.undoManager = undoManager
        statusBar.undoKeys = tuiContext.undoKeys
    }

    /// Publishes what the host does that a view decides on as it renders,
    /// which the render path cannot ask, not being main-actor isolated:
    /// whether it honours OSC 8 hyperlinks (a `Link` decides whether to emit
    /// one while rendering), and whether this process may launch a browser at
    /// all, which defaults to NO (activation is not main-actor isolated
    /// either; see ``TerminalClient/urlOpeningSupport``).
    ///
    /// And whether it takes the pointer's shape by name (OSC 22), which the
    /// terminal decided as it was made, to `\.terminalFeatures`, which
    /// `pointerStyle(_:)` reads as it renders; with whether TUIkit's own
    /// controls set theirs.
    private func publishHostAnswers() {
        TerminalClient.applyHyperlinkSupport()
        TerminalClient.applyURLOpeningSupport()
        let pointerHost = terminal.pointerShapeHost
        tuiContext.terminalFeatures = TerminalFeatures(
            pointerShapes: pointerHost != nil,
            controlPointerShapes: TerminalClient.builtInPointerShapes(
                host: pointerHost, environment: ProcessInfo.processInfo.environment))
    }

    /// Gives the pointer the shape the views under it ask for
    /// (`MouseEventDispatcher.pointerShapeUnderPointer()`), where the terminal
    /// takes one: after each batch of input, which may have moved the pointer,
    /// and after each frame, which may have moved what is under it. Written
    /// only when it changes.
    private func showPointerShape() {
        guard terminal.pointerShapeHost != nil else { return }
        terminal.showPointerShape(tuiContext.mouseEventDispatcher.pointerShapeUnderPointer())
    }

    /// Names the terminal where the environment did not, and asks what may be
    /// asked only of a named one: before the render loop, whose
    /// `FrameDiffWriter` freezes what it reads of the host at construction.
    private func identifyHost() {
        // If nothing in the environment named the host, ask the terminal
        // itself — which is the only question that survives an ssh hop, where
        // `TERM_PROGRAM` does not (see TerminalHost.hostProgram). One write and
        // one round trip, and only in the case that is otherwise rendering
        // incorrectly: an Apple Terminal reached over ssh, painting every VS-16
        // emoji, lone regional indicator and SF Symbol two cells wide while
        // advancing one.
        //
        // BEFORE the render loop, and deliberately: TerminalHost's detectors
        // are `static let`, so each freezes on first read, and the loop's
        // FrameDiffWriter reads all of them as its init defaults. Under tmux
        // there is nothing to ask — the pane's grid is tmux's, not the
        // client's, and `$TMUX` has already answered.
        if !TerminalHost.hostIsNamedByEnvironment, !TerminalHost.isTmux {
            TerminalHost.identify(using: terminal)
            // An Apple Terminal named only now keeps autowrap on, as one the
            // environment named does; raw mode turned it off before anything
            // knew (`Terminal.keepsAutowrap`).
            terminal.keepAutowrapIfAppleTerminal(environment: ProcessInfo.processInfo.environment)
        }

        // AFTER identification, because the question is only safe to ask a host
        // known to answer it: DECRQM's `CSI ? Ps $ p` is the one CSI shape
        // Apple Terminal prints instead of consuming. Before the render loop,
        // for the same reason identification is — the advance model this
        // protects is frozen into `FrameDiffWriter` at construction. And
        // whether a copy can carry more than text (OSC 5522), asked under the
        // same rule.
        terminal.askModesOfIdentifiedHost()

        // Which other chords the host may send ⌃\'s byte for, now that it
        // is named.
        hostQuitByteAliases = TerminalClient.quitByteAliases(TerminalClient.current.program)
    }
    /// Turns on the kitty keyboard protocol where the terminal speaks it, and
    /// publishes what the terminal reports: to the environment
    /// (`\.keyboardReporting`), and to the undo keys, which name in the status
    /// bar the first of each command's keys this terminal can deliver.
    private func negotiateKeyboardProtocol() {
        terminal.negotiateKeyboardProtocol()
        tuiContext.keyboardReporting = KeyboardReporting(flags: terminal.keyboardEnhancement)
        tuiContext.undoKeys.reporting = tuiContext.keyboardReporting
    }

    /// The loop that renders this app's frames to its terminal.
    private func makeRenderLoop() -> RenderLoop<A> {
        RenderLoop(
            app: app,
            terminal: terminal,
            statusBar: statusBar,
            focusManager: focusManager,
            paletteManager: paletteManager,
            appearanceManager: appearanceManager,
            tuiContext: tuiContext,
            // The one loop that reads the process's environment for it: an
            // app in a real terminal, run by the user who set it.
            reducesMotion: TerminalClient.reduceMotionRequested,
            keyNotation: TerminalClient.keyNotationRequested
        )
    }

    /// Starts reading the host's own Reduce Motion, where the user is provably
    /// at this machine: off the main actor now, and again whenever the terminal
    /// regains the focus (`terminalFocusChanged`). What it reads goes to
    /// `renderer`'s root, and a change draws a frame.
    private func startHostMotion(renderer: RenderLoop<A>) {
        let hostMotion = HostReduceMotionRefresher { [weak self, weak renderer] reduces in
            renderer?.hostReducesMotion = reduces
            self?.appState.setNeedsRender()
        }
        self.hostMotion = hostMotion
        hostMotion.refresh()
    }

    /// Has the focus system ask for the frames its changes need.
    private func wireFocusRepaints(cursorTimer: CursorTimer) {
        // Restart the breath and re-render when the focus moves, so the newly
        // focused control is at its brightest the moment it takes the focus
        // (the phase starts at its bright end — see `CursorTimer.pulsePhase`).
        focusManager.onFocusChange = { [weak cursorTimer, weak appState] in
            cursorTimer?.restartFocusPhase()
            appState?.setNeedsRender()
        }
        // A `@FocusedValue` reader drawn ahead of the view that changed what it
        // reads: one more frame shows the change (`FocusedValueRegistry`).
        focusManager.focusedValues.requestFrame = { [weak appState] in
            appState?.setNeedsRender()
        }
    }

    /// Runs the app until it quits (``whileRunning(_:)``).
    func run() async {
        await whileRunning { await runLoop() }
    }

    /// Runs `body` — the run loop, but for a test — as this app's run.
    ///
    /// This app is the one whose work is under way (`AmbientApp`) for all of
    /// it: every event it handles, every frame it draws, and every task they
    /// start, so a change made there with no view in hand — an `@AppStorage`
    /// write, a top-level `dismiss()` — asks this app for its frame. And it is
    /// noted as running from the localization service, the process's, so a
    /// change of language or of the strings registered asks this app for its
    /// frame wherever it was made: on a queue of the app's own too, where no
    /// app's work is under way.
    func whileRunning(_ body: () async -> Void) async {
        let localization = LocalizationService.shared
        localization.noteRunning(appState)
        defer { localization.noteStopped(appState) }
        await AmbientApp.$renderState.withValue(appState) {
            await body()
        }
    }

    private func runLoop() async {
        makeUndoManager()
        // Create run-loop dependencies (previously IUOs, now local variables)
        let inputHandler = makeInputHandler()
        // Wire the synthesised-key path: clicks on system status-
        // bar items (Back / Quit / Show — items with only a
        // triggerKey, no inline action) route their click through
        // the same 5-layer dispatch chain that a physical
        // keypress goes through. See StatusBar.swift's mouse
        // handler for the consumer side and TUIContext.swift's
        // `synthesizeKeyEvent` doc-comment for why this is a
        // closure threaded through the context.
        tuiContext.synthesizeKeyEvent = { _ = inputHandler.handle($0) }
        let cursorTimer = CursorTimer(renderNotifier: appState)
        // Coalesces the periodic re-render requests of every animating view
        // (Spinner, indeterminate ProgressView, …) into the fewest distinct render
        // instants, and tells the loop when the next one is due. See
        // AnimationScheduler / RenderContext.requestAnimation.
        let animationScheduler = AnimationScheduler()

        // Wakes the main loop on stdin data (a DispatchSource on STDIN_FILENO)
        // and on render-requests (via `wake()`). The loop awaits its
        // `waitForArrival(...)`. See StdinArrivalStream.swift. Created before the
        // signal install below because the signal sources' wake closure captures
        // it (a SIGWINCH / SIGINT / SIGTERM must rouse the idle-blocked loop).
        let stdinArrival = StdinArrivalNotifier()
        stdinArrival.start()
        defer { stdinArrival.stop() }

        // Setup: install the dispatch signal sources (SIGWINCH resize, SIGINT /
        // SIGTERM graceful shutdown, SIGTSTP / SIGCONT job control) and set
        // SIGPIPE to SIG_IGN. Each source's handler sets a flag the loop
        // drains and wakes the notifier. `await`s until every source is armed.
        await signals.install(wake: { [weak stdinArrival] in stdinArrival?.wake() })
        terminal.enterAlternateScreen()
        // From here stderr is the screen being drawn, so a soft trap's report is
        // held until the terminal is handed back (`cleanup`, `suspendUntilContinued`).
        SoftTrap.holdUntilTerminalRestored()
        terminal.hideCursor()
        terminal.enableRawMode()

        // Who the terminal is, where the environment did not say, and what may
        // be asked of it now that it is named: before the render loop below.
        identifyHost()

        // The host's width traits, published before anything measures a view:
        // the claim follows the host now, so layout must see it from frame one.
        // And, for the same reason, what else it does that a view decides on
        // as it renders (``publishHostAnswers()``).
        TerminalClient.applyWidthTraits()
        publishHostAnswers()
        // And the opener that gate guards, for the one caller no environment
        // reaches: an `OpenURLAction` the app made itself and calls directly.
        // Withdrawn when the run ends, so nothing outside a running app reaches
        // this machine's opener. See ``TerminalURLOpening/runLoopOpener``.
        publishURLOpener()
        defer { TerminalURLOpening.runLoopOpener = nil }
        // And whether it will draw a real picture. Unlike the two above, this
        // one is ASKED rather than looked up — see ``TerminalGraphicsQuery``,
        // which is also why it comes after identification: the exchange is an
        // APC sequence, and Apple Terminal prints those instead of consuming
        // them, so it has to know which host this is before it can decide not
        // to ask. Costs one terminal round trip at startup, and only when
        // nothing has already answered.
        TerminalClient.detectGraphics(using: terminal)
        // And how many of the pixels it reports make a point — the unit an
        // image's natural size is in. After identification, which names the
        // host; it asks iTerm2 one question (`CSI 14 t`) and nothing else
        // anything. See ``CellPointsCalibration``.
        TerminalClient.detectCellPoints(using: terminal)
        // And what colours it paints: its default foreground and background
        // (OSC 10/11) and, outside tmux, its sixteen ANSI slots (OSC 4),
        // published to `TerminalColors.current` so the first frame is drawn
        // with them. Also asked rather than looked up, in one round trip
        // fenced by `CSI 5n`, which every measured host answered. Under tmux
        // the slots are left out: tmux forwards OSC 4 to one client and holds
        // the fence about half a second when that client is silent. See
        // ``TerminalColorQuery``.
        TerminalClient.detectColors(using: terminal)
        // The kitty keyboard protocol, where the terminal speaks it: key
        // releases, repeats, modifier keys alone, Caps Lock and the keypad,
        // and Ctrl-H/I/J/M/[ as themselves. Its first question rode on the
        // colour exchange just made, so a terminal that does not speak it
        // pays no round trip; one that does pays one, for the push and its
        // answer. Published before the first frame, which is when a view
        // first reads it.
        negotiateKeyboardProtocol()
        // And what it does with what the app asks of it beyond the screen — a
        // progress bar on its tab — by which terminal it is, now that it is
        // named: published to `\.terminalFeatures` before the first frame, and
        // what decides whether the frames send it at all.
        tuiContext.terminalFeatures = TerminalFeatures(showsProgress: TerminalClient.progressReportsSupported)

        let renderer = makeRenderLoop()
        startHostMotion(renderer: renderer)

        // Under tmux, have it PUSH a SIGWINCH at us whenever a client attaches,
        // detaches, or changes session — the only events that can change which
        // terminal is painting our output (and so the emoji-chrome answer). A
        // same-size attach sends no SIGWINCH of its own, so without this the
        // answer could go stale until something happened to resize. Comes after
        // signals.install() so the SIGWINCH source exists before the first
        // hook can fire. Failure (a tmux too old for these hooks) is tolerated:
        // the app then adapts only on real resizes.
        // Also the hooks for a client switching its THEME, which changes what
        // the pane is painted in without changing which client is attached; they
        // ride the same SIGWINCH, and go out as their own `set-hook` invocation
        // so a tmux too old for them cannot take the rest down with them (see
        // `TerminalHost.installTmuxHooks`).
        if TerminalHost.isTmux {
            TerminalHost.installTmuxHooks()
        }

        // Apply the initial mouse-tracking mode based on the scene's
        // configuration. We do this before the first render so the
        // terminal is reporting the right events by the time any
        // input is processed. The mode is re-evaluated each frame
        // (and only re-emitted when it actually changes) — see the
        // re-apply step inside the main loop below.
        terminal.applyMouseSupport(.standard)

        // Register for state changes: wake the (possibly idle-blocked) loop.
        // `setNeedsRender` already set `appState.needsRender` synchronously (the
        // loop polls it), so the observer's only job is to rouse the loop.
        // `setNeedsRender`'s observers can fire off the main actor, so hop to the
        // main actor to touch the MainActor-isolated notifier. `stdinArrival` is
        // captured weakly so this persistent observer doesn't keep it alive past
        // the run.
        appState.observe { [weak stdinArrival] in
            Task { @MainActor in stdinArrival?.wake() }
        }

        wireFocusRepaints(cursorTimer: cursorTimer)

        // The timer plans its own next sleep, at the moment it wakes, from the frame on
        // screen. Deciding it here in the loop after serving the tick was one wake too
        // late — see `CursorTimer.planner`.
        cursorTimer.planner = { [weak renderer] elapsed in
            renderer?.timeUntilNextChange(elapsed: elapsed)
                ?? AnimationClock.seconds(forTicks: AnimationClock.standardFrameTicks)
        }

        isRunning = true

        // Owns when a frame is due: never renders two frames closer together than
        // the app's rate (default 60 FPS), so a burst of render-requests — an
        // animation ticking faster than the cap, say — coalesces into at most one
        // render per frame. Otherwise purely demand-driven: with nothing pending
        // the loop blocks until woken, so a static screen does ZERO renders.
        var pacer = FramePacer(
            maxFrameRate: app.maxFrameRate,
            startedAtNanos: MonotonicClock.nowNanoseconds)
        let renderOneFrame = {
            let frame = self.renderFrame(
                renderer: renderer,
                cursorTimer: cursorTimer,
                scheduler: animationScheduler)
            self.finishFrame(with: inputHandler)
            return frame
        }

        // Under the kitty keyboard protocol ⌃\ is a report only a running
        // loop reads: should the loop stall with input waiting, a thread of
        // its own pops the protocol's flags so the next ⌃\ is the byte the
        // driver quits on.
        let stopStallWatchdog = startStallWatchdog()

        // Initial render
        pacer.render(renderOneFrame)

        // Main loop
        while isRunning {
            // Check for graceful shutdown request (from SIGINT handler)
            if signals.shouldShutdown {
                isRunning = false
                break
            }

            // Check for an in-app `@Environment(\.dismiss)` call. Lets a
            // view exit the run loop cleanly without resorting to `exit()`,
            // which would skip the terminal-restore teardown below. The
            // top-level action asks this app's render state
            // (`TUIContext.exitAction`).
            if appState.consumeShouldExit() {
                isRunning = false
                break
            }

            // Terminal resize (SIGWINCH): rewrite every line at the new size.
            if signals.consumeResizeFlag() {
                renderer.invalidateDiffCache()
                pacer.requestRender()
            }

            // Ctrl-Z (SIGTSTP): hand the terminal back to the shell, stop for
            // real, and rebuild everything when `fg` resumes us. Runs here —
            // not in the signal handler — because only the loop owns the
            // terminal state it has to tear down and rebuild.
            if signals.consumeSuspendFlag() {
                // The one scene-phase transition a terminal can actually
                // report. Render a frame at `.background` BEFORE stopping, so
                // an `onChange(of: scenePhase)` observer gets to run while the
                // process is still alive — an app that saves on the way down
                // has no other moment. See ``ScenePhase``.
                tuiContext.scenePhase = .background
                renderOutsidePacer(renderer: renderer, cursorTimer: cursorTimer)
                suspendUntilContinued(renderer: renderer)
                // The animation clocks are the monotonic clock, which ran on while
                // the process was stopped: looping animations resume where it now
                // is, and the caret and focus breath restart at their bright end.
                cursorTimer.restartFocusPhase()
                tuiContext.scenePhase = .active
                pacer.requestRender()
            }

            // Resumed from an *external* SIGSTOP, which cannot be caught, so
            // nothing was torn down and nothing needs rebuilding — but the
            // screen may have been disturbed while the process slept.
            if signals.consumeContinueFlag() {
                // The same long gap as Ctrl-Z's, so the same restart.
                cursorTimer.restartFocusPhase()
                renderer.invalidateDiffCache()
                pacer.requestRender()
            }

            // Read + dispatch all pending terminal events (non-blocking),
            // BEFORE the render so a keypress / mouse action shows up in the
            // same frame it triggers. Extracted so the main loop stays legible.
            drainTerminalEvents(
                inputHandler: inputHandler,
                renderer: renderer,
                cursorTimer: cursorTimer)

            // Fold a state change, and any animation tick the cheap path could
            // not serve, into the pending-render flag.
            if foldPendingWork(
                alreadyPending: pacer.isRenderPending, renderer: renderer,
                cursorTimer: cursorTimer) {
                pacer.requestRender()
            }

            // One monotonic reading drives every decision this iteration — the
            // animation-fired test, the render-now test, and the wait length all
            // share it, so none can disagree about whether a deadline has passed.
            let now = MonotonicClock.nowNanoseconds

            // Render if a frame is due — a state change, or an animation lattice
            // or wake whose deadline `now` has reached — AND the frame-rate cap has
            // cleared. The render moves both the cap and the next deadline
            // strictly past `now`, so the wait computed below is always a real
            // positive interval, never a spurious "block forever".
            pacer.renderIfDue(now: now, renderOneFrame)

            // The progress bar, sent again where it has gone unsent long enough
            // for a terminal to drop it: a write between frames, which draws
            // nothing, so a still screen with a bar up renders no frame for it.
            keepHostStateAlive(renderer: renderer, now: now)

            // How long to wait until the next render is due (cap and/or animation
            // folded into one instant), or nil to block until woken. While the
            // input parser holds something that resolves on a timeout — a lone
            // ESC being disambiguated from a sequence, or a split sequence
            // awaiting its tail — the wait is shortened to a poll, so the partial
            // resolves on a bounded wall-clock deadline (a prompt Escape) instead
            // of waiting for unrelated input or an animation tick. The progress
            // bar's next send shortens it too, and owes no frame.
            let waitNanos = pacer.waitNanos(
                now: now, pollingPendingInput: terminal.hasPendingInput,
                until: renderer.hostState.keepAliveDeadline.map { UInt64(bitPattern: $0) })

            // Block until woken (stdin data or a render-request `wake()`), or —
            // when a render is pending or an animation is due — until that target.
            // The wait releases the main actor, so the observer's `wake()` hop and
            // other queued main-actor work run between frames.
            await stdinArrival.waitForArrival(timeoutNanoseconds: waitNanos)
        }

        // Stop the animation clock before cleanup
        cursorTimer.stop()
        // And the watchdog, before the teardown writes and pops for itself.
        stopStallWatchdog()

        // Cleanup
        cleanup(renderer: renderer)
    }
}

// MARK: - Private Helpers

extension AppRunner {
    /// Masks the user's quit key in the driver while the bindings the frame
    /// just registered declare one on a chord its byte could be for, and
    /// gives it back otherwise (`Terminal.maskQuitKey(for:)`): asked after
    /// every frame, the line discipline set only when the answer changes.
    private func maskQuitKeyForBindings(of inputHandler: InputHandler) {
        terminal.maskQuitKey(
            for: inputHandler.quitKeyBindings(byte: terminal.quitKeyByte, hostAliases: hostQuitByteAliases))
    }

    /// What follows every frame once it is on the screen: the driver's quit
    /// key masked or given back for the bindings it registered, and the keys
    /// it owes pressed.
    private func finishFrame(with inputHandler: InputHandler) {
        maskQuitKeyForBindings(of: inputHandler)
        pressKeysAfterFrame(to: inputHandler)
    }

    /// Presses the keys owed once a frame is on the screen (`KeysAfterFrame`):
    /// a menu bar's item's key, which goes once the frame that closed the
    /// menu has handed the focus back. Each through the whole chain, as a key
    /// typed now — or the quit, as the quit key asks for it; another frame
    /// shows what they did.
    private func pressKeysAfterFrame(to inputHandler: InputHandler) {
        let owed = tuiContext.keysAfterFrame.take()
        guard !owed.isEmpty else { return }
        for item in owed { inputHandler.perform(item) }
        appState.setNeedsRender()
    }

    /// Starts the stall watchdog (`StallWatchdog`), which pops the kitty
    /// keyboard protocol's flags while the loop is stalled with input
    /// waiting, armed only while that can help
    /// (`Terminal.refreshStallWatch()`). Returns what stops it. wasip1 has
    /// no driver to hand ⌃\ back to, and no watchdog.
    private func startStallWatchdog() -> () -> Void {
        #if canImport(WASILibc)
            return {}
        #else
            let watchdog = StallWatchdog(gate: terminal.writeGate)
            watchdog.start()
            return watchdog.stop
        #endif
    }

    /// Folds this iteration's reasons to render into one flag.
    ///
    /// A state change always needs a frame. An animation tick usually does not:
    /// it is served by advancing the animated cells of the frame already on
    /// screen. Replay is skipped when a render is due anyway — one is strictly
    /// better, and replaying first would paint the old frame's cells over
    /// content about to change.
    /// Internal rather than `fileprivate` only so a test can name it: the sole
    /// caller is the `while isRunning` loop, which enters raw mode and installs
    /// signal handlers before it gets here, so the three rules below were
    /// reachable from nothing a unit test can drive.
    func foldPendingWork(
        alreadyPending: Bool, renderer: RenderLoop<A>, cursorTimer: CursorTimer
    ) -> Bool {
        var pending = alreadyPending
        if appState.needsRender {
            appState.didRender()
            pending = true
        }
        if pending {
            // A full frame supersedes any tick, so drop them rather than let
            // them queue up and fire against the frame after next.
            _ = appState.consumePendingAnimationClocks()
            return true
        }
        return !serveAnimationTicks(renderer: renderer, cursorTimer: cursorTimer)
    }

    /// Advances the clocks that ticked, without rendering, by replaying the
    /// runs the frame on screen left for them.
    ///
    /// - Returns: `false` if a full render is needed instead — some view still
    ///   builds its appearance from a phase as it renders, there is no frame to
    ///   patch yet, nothing on screen animates on any clock that ticked, or the
    ///   chrome animates on one that did, which only a render can advance.
    ///   That is the behaviour this replaces, so falling back is always safe.
    /// Internal rather than `fileprivate` for the same reason as
    /// ``foldPendingWork(alreadyPending:renderer:cursorTimer:)``.
    func serveAnimationTicks(
        renderer: RenderLoop<A>, cursorTimer: CursorTimer
    ) -> Bool {
        let ticked = appState.consumePendingAnimationClocks()
        guard !ticked.isEmpty else { return true }  // nothing ticked; nothing owed
        // The clocks worth advancing, not all of the ones that ticked: the
        // timer posts both on every wake, and a clock this frame left no runs
        // for has nothing to advance. See `replayableClocks(among:)`.
        let replayable = renderer.lastActivity.replayableClocks(among: ticked)
        guard !replayable.isEmpty else { return false }
        var elapsed: [AnimationClock: Double] = [:]
        for clock in replayable {
            elapsed[clock] = cursorTimer.elapsed(for: clock)
        }
        // No re-plan of the sleep here, although there used to be one. By the time this
        // runs the timer has already begun its next sleep — the plan it needed was the
        // one made at its wake, which `CursorTimer.planner` now makes.
        return renderer.replayAnimations(elapsed: elapsed)
    }

    /// Renders one frame and returns the per-frame state the run loop tracks: the
    /// timestamp of this render (for the frame-rate cap) and the soonest instant
    /// any live animation lattice or wake next fires (`nil` if nothing is animating).
    ///
    /// The scheduler is fenced begin…end around the render: animating views
    /// re-declare their lattices and wakes *during* the render (via
    /// `requestAnimation` and `requestWake`), then the next-firing query reads the
    /// union of every one still live. Wakes and the query use `frameNow`, so
    /// "soonest firing after this frame" is exact integer arithmetic, not a clock
    /// that drifted between the two. Also
    /// republishes the demand-driven pulse/cursor clocks (kept ticking only while
    /// a frame consumed them) and the mouse-tracking mode.
    fileprivate func renderFrame(
        renderer: RenderLoop<A>,
        cursorTimer: CursorTimer,
        scheduler: AnimationScheduler
    ) -> FramePacer.Frame {
        scheduler.beginFrame()
        // The two clocks read together, so a wake counted from the wall clock
        // lands where it was counted to on the monotonic one.
        let frameNow = FrameClock.nowNanos
        let frameDate = FrameClock.nowDate
        // Before the breath is read below, so the phase it passes and every clock
        // read inside the frame are this frame's instant — see `CursorTimer.observe`.
        cursorTimer.observe(nowNanos: UInt64(bitPattern: frameNow))
        let activity = renderer.render(
            pulsePhase: cursorTimer.breathPhase,
            cursorTimer: cursorTimer,
            animationScheduler: scheduler,
            frameNowNanos: frameNow,
            frameDate: frameDate)
        scheduler.endFrame()
        // Demand-driven animation clock: kept ticking only while a frame
        // actually consumed it, so a static screen drives no further frames.
        // It keeps running while EITHER a view reads it as it renders or the
        // frame left runs on it — the second is the cheap path, and stopping
        // the clock because nobody read the phase would freeze it.
        // ANY clock: the frame may animate content without anything focused
        // reading the phase, and stopping the timer then freezes the
        // indeterminate bars.
        let clockLive =
            activity.usesPulse || activity.usesCursor || !activity.animatedClocks.isEmpty
        if clockLive {
            // Sleep exactly as long as nothing can change — see
            // `RenderLoop.timeUntilNextChange(elapsed:)`.
            cursorTimer.advance(by: renderer.timeUntilNextChange(elapsed: cursorTimer.elapsed))
            cursorTimer.start()
        } else {
            cursorTimer.stop()
        }
        let deadline = scheduler.nextFiring(after: frameNow).map { UInt64(bitPattern: $0) }
        // Re-evaluate the mouse-tracking mode (modifiers may elevate it this
        // frame); only re-emitted when it actually changes.
        let effective = renderer.effectiveMouseSupport()
        terminal.applyMouseSupport(effective)
        tuiContext.mouseEventDispatcher.setActiveSupport(effective, isFrameFinal: true)
        // After the mouse mode, which on Ghostty resets the pointer's shape.
        showPointerShape()
        // What a SIGQUIT owes for the images this frame put in or took out,
        // and a signal for the title it saved.
        terminal.oweFarewell(for: tuiContext.terminalImageStore)
        terminal.oweHostState(renderer.hostState.debt)
        return FramePacer.Frame(
            renderedAtNanos: MonotonicClock.nowNanoseconds,
            animationDeadlineNanos: deadline)
    }

    /// A frame rendered outside the pacer — the one before a Ctrl-Z suspend, the
    /// debug frame dump — stamped and shown to the clock the way `renderFrame`
    /// does it: one reading, observed before the breath is read.
    fileprivate func renderOutsidePacer(renderer: RenderLoop<A>, cursorTimer: CursorTimer) {
        let frameNow = FrameClock.nowNanos
        let frameDate = FrameClock.nowDate
        cursorTimer.observe(nowNanos: UInt64(bitPattern: frameNow))
        renderer.render(
            pulsePhase: cursorTimer.breathPhase, cursorTimer: cursorTimer, frameNowNanos: frameNow,
            frameDate: frameDate)
    }

    /// Reads and dispatches every terminal event currently pending (up to a
    /// per-frame cap of 128, which avoids paste lag without letting a flood
    /// spin the loop). Called BEFORE the frame renders so a keypress / mouse
    /// action shows up in the same frame it triggers.
    ///
    /// A consumed key or mouse event requests a render: focus / scroll moves go
    /// through plain (non-`@State`) handler properties that don't themselves
    /// call `setNeedsRender()`, so without this an arrow-key List navigation
    /// would move the selection but never repaint.
    /// The Ctrl-Z round trip: hands the terminal back to the shell exactly the
    /// way quitting would, stops the process for real, and — execution resumes
    /// at the next line when `fg` delivers SIGCONT — rebuilds the terminal
    /// exactly the way `run` set it up.
    ///
    /// `SIGSTOP` is used for the stop because it cannot be caught or ignored:
    /// SIGTSTP's default action is suppressed by the signal source's
    /// registration (stopping the instant it lands would strand the shell in
    /// raw mode on the alternate screen), so re-raising it would just re-enter
    /// the handler.
    ///
    /// The mouse mode is set to `.none` on the way down and NOT re-applied here
    /// on the way up: the loop re-evaluates the effective mode every frame and
    /// re-emits it on change, so the first frame after resume — forced by the
    /// diff-cache invalidation — restores whatever mode the scene wants.
    fileprivate func suspendUntilContinued(renderer: RenderLoop<A>) {
        terminal.applyMouseSupport(.disabled)
        // The pointer goes where it likes, unreported, until the mode is back.
        tuiContext.mouseEventDispatcher.forgetRestingPointer()
        // The styling reset first: a frame may have ended with styling in
        // force, and leaving the alternate screen does not restore SGR. The
        // shell's window title back with it; the first frame after the resume
        // sets the app's again.
        terminal.handBack(
            farewell: handBackHostState(renderer), restoringStyling: renderer.restoreTerminalStyling)
        // The shell's screen is back, so held soft-trap reports can be read there.
        SoftTrap.terminalRestored()
        // Our own resume delivers a SIGCONT too; the repaint is already
        // forced below, so arm the source to swallow that one signal.
        // Arming (not consume-after-resume): the SIGCONT source runs on the
        // main queue, which cannot fire until this synchronous path has
        // finished — a consume here would run before the flag is ever set,
        // and the loop would double-repaint on the next iteration.
        signals.expectSelfResume()
        // The stop itself, and the dance with the foreground process group that
        // follows it, are job control — POSIX, and absent on wasip1. The whole
        // path is unreachable there (nothing ever sets the suspend flag), but
        // unreachable code still has to compile.
        #if !canImport(WASILibc)
        kill(getpid(), SIGSTOP)
        // ── stopped; `fg` resumes here ──
        //
        // So does `bg`, and a BACKGROUND process must not touch the terminal:
        // the escapes below would garble the shell's prompt, and grabbing raw
        // mode would steal the foreground shell's keystrokes. Re-stop until
        // the shell actually hands the terminal over (`fg` makes this group
        // the foreground group) — which is also what the kernel's SIGTTOU
        // default would do to a background job touching the tty, so `bg`
        // behaves the way it does for any full-screen program: the job
        // reports stopped again, and finishes its resume when foregrounded.
        // The `>= 0` guards a failed query (not a tty): never loop on an
        // answer that cannot change.
        while tcgetpgrp(STDIN_FILENO) >= 0, tcgetpgrp(STDIN_FILENO) != getpgrp() {
            signals.expectSelfResume()
            kill(getpid(), SIGSTOP)
        }
        #endif
        terminal.enterAlternateScreen()
        SoftTrap.holdUntilTerminalRestored()
        terminal.hideCursor()
        terminal.enableRawMode()
        // `disableRawMode` put grapheme clustering (mode 2027) back the way the
        // shell had it, and `enableRawMode` re-emits bracketed paste and the
        // cursor-key mode but not that: the advance model was frozen into the
        // diff writer at startup on the strength of the pin, so a resume
        // without it compensated every later frame against a terminal whose
        // mode had changed under it. Paste events (mode 5522) likewise.
        terminal.resumeModesOfIdentifiedHost()
        // The kitty keyboard protocol's flags are pushed again by
        // `enableRawMode`, as `disableRawMode` popped them.
        renderer.invalidateDiffCache()
    }

    /// Moves the scene between ``ScenePhase/active`` and ``ScenePhase/inactive``
    /// on a focus report from the terminal (mode 1004, which `enableRawMode`
    /// turns on).
    ///
    /// - While the scene is ``ScenePhase/background`` it does nothing: that
    ///   phase belongs to the suspend, which sets `.active` again itself.
    /// - A report of the phase the scene already has asks for no frame. A
    ///   terminal may report focus in as reporting is enabled.
    /// - Focus in restarts the focus breath and the caret, so they come back at
    ///   their bright start rather than wherever the clock has run to, and asks
    ///   the terminal what colours it paints now: the user has been in another
    ///   window, and may have changed this one while they were there (step 5d
    ///   of the colour plan — see ``TerminalColorRequester``). Only when the
    ///   phase actually moved, so the report a terminal may send as reporting is
    ///   enabled costs nothing.
    /// - Focus out lets go of the pointer, whatever the phase: its hover is
    ///   exited and its help goes (``MouseEventDispatcher/pointerLeft()``).
    /// - Otherwise it asks for a frame, which draws the new look. After a focus-out
    ///   frame nothing reads the cursor clock or leaves runs on it, so the
    ///   timer stops, or keeps running only for content animations.
    func terminalFocusChanged(isFocused: Bool, cursorTimer: CursorTimer, renderer: RenderLoop<A>) {
        // The pointer goes with the focus: nothing reports it while it is in
        // another window (`MouseEventDispatcher.pointerLeft()`).
        if !isFocused, tuiContext.mouseEventDispatcher.pointerLeft() { appState.setNeedsRender() }
        guard tuiContext.scenePhase != .background else { return }
        let phase: ScenePhase = isFocused ? .active : .inactive
        guard tuiContext.scenePhase != phase else { return }
        tuiContext.scenePhase = phase
        if isFocused {
            cursorTimer.restartFocusPhase()
            renderer.terminalFocusRegained()
            // The user may have changed the host's Reduce Motion while away.
            hostMotion?.refresh()
        }
        appState.setNeedsRender()
    }

    fileprivate func drainTerminalEvents(
        inputHandler: InputHandler,
        renderer: RenderLoop<A>,
        cursorTimer: CursorTimer
    ) {
        // The loop is reading its input: what tells the stall watchdog it is
        // not stalled. If it popped the kitty flags while the loop was, push
        // them back before reading what came in meanwhile.
        #if !canImport(WASILibc)
            if terminal.writeGate.noteDrain() { terminal.recoverFromStall() }
        #endif
        var eventsProcessed = 0
        let maxEventsPerFrame = 128
        while eventsProcessed < maxEventsPerFrame, let input = terminal.readEvent() {
            switch input {
            case .key(let keyEvent):
                focusManager.noteInputSource(.keyboard)
                tuiContext.mouseEventDispatcher.noteInput()
                // "`": dump the current frame to a file (debug shortcut, not
                // consumed). Opt-in via TUIKIT_DEBUG_FRAME_DUMP=1 — unguarded,
                // every backtick ANYWHERE (typing one into a TextField, a
                // Markdown snippet in a TextEditor) silently wrote a frame
                // file into the user's working directory. Force a full
                // repaint first so the snapshot captures every line.
                if keyEvent.key == .character("`"), keyEvent.phase == .press, frameDumpEnabled {
                    renderer.invalidateDiffCache()
                    renderOutsidePacer(renderer: renderer, cursorTimer: cursorTimer)
                    terminal.dumpLastFrame()
                    // The notice went out behind the diff writer's back.
                    renderer.forgetTerminalStyling()
                }
                let silencedTooltip = inputHandler.silencePointerTooltip(for: keyEvent)
                if inputHandler.handle(keyEvent) || silencedTooltip {
                    appState.setNeedsRender()
                }

            case .mouse(let mouseEvent):
                focusManager.noteInputSource(.pointer)
                // Re-render only when a handler consumed the event — with
                // any-event mouse mode the terminal reports every motion.
                // In the screen's coordinates, which are the frame's: the
                // chrome is drawn into the frame with the page, so nothing
                // needs translating.
                if tuiContext.mouseEventDispatcher.dispatch(mouseEvent, noting: focusManager) {
                    appState.setNeedsRender()
                }

            case .focusChanged(let isFocused):
                // Deliberately no `noteInputSource`: a focus report is the
                // terminal speaking, not the user choosing the keyboard or the
                // pointer.
                terminalFocusChanged(
                    isFocused: isFocused, cursorTimer: cursorTimer, renderer: renderer)

            case .modifierKeys(let state):
                // A modifier key on its own (kitty keyboard protocol only).
                // Not a key, so no key handler hears it and it does not make
                // the keyboard the input source: a Shift held for a Shift-click
                // is the pointer's. The views listening for it hear it now,
                // and a frame follows only if one drew from it.
                tuiContext.mouseEventDispatcher.noteInput()
                if tuiContext.modifierKeys.record(state) {
                    appState.setNeedsRender()
                }
            }
            eventsProcessed += 1
        }
        // Colour answers that came in among those bytes: one that missed the
        // startup exchange's deadline (under tmux that is the normal case for the
        // sixteen slots — a silent client holds its fence about half a second),
        // or one the terminal volunteered because its theme changed. The parser
        // siphons them out of the keystrokes; taking them once per drain makes a
        // burst of replies one publication and one repaint.
        renderer.noteVolunteeredColorReplies(
            terminal.takeVolunteeredColorReplies(), sawStatusFence: terminal.takeStatusFence())
        // The pointer may have moved onto another style: shown now, with no
        // frame needed for it.
        showPointerShape()
    }

    /// Sends the progress bar again where it is due (`TerminalHostState.keepAlive(atNanos:)`),
    /// at `now` on the monotonic clock, straight to the terminal: no frame is
    /// being written between frames.
    fileprivate func keepHostStateAlive(renderer: RenderLoop<A>, now: UInt64) {
        let resend = renderer.hostState.keepAlive(atNanos: Int64(bitPattern: now))
        if !resend.isEmpty { terminal.write(resend) }
    }

    /// What the app set on the terminal emulator, given back — the window
    /// title restored where it was saved, the progress bar taken down — and
    /// owed no more.
    fileprivate func handBackHostState(_ renderer: RenderLoop<A>) -> String {
        let restore = renderer.handBackHostState()
        terminal.oweHostState(renderer.hostState.debt)
        return restore
    }

    fileprivate func cleanup(renderer: RenderLoop<A>) {
        // Before the terminal teardown: this forks tmux, and doing it while our
        // pane is still alive is the tidy window. A crash skips this — then the
        // hooks' own `||` arm removes them on their next firing instead (see
        // `TerminalHost.tmuxClientChangeHookArguments`).
        if TerminalHost.isTmux {
            TerminalHost.removeTmuxHooks()
        }
        // Give the terminal back the images this app put in it, while there is
        // still a terminal to write to. A transmitted image is retained under
        // its id for as long as the TERMINAL runs, which outlives the app —
        // quitting without this leaves a tab holding megabytes for a picture
        // nobody can see. Written directly rather than queued: there is no
        // further frame to drain it.
        tuiContext.terminalImageStore.releaseAll()
        // The same hand-back as `suspendUntilContinued`'s, with the farewell:
        // the image deletes, and then a copy made in the last moments — a
        // Ctrl-C and then `q` before a frame drew — which is still owed to the
        // terminal's clipboard.
        terminal.handBack(
            farewell: tuiContext.terminalImageStore.takePending()
                + tuiContext.clipboardWriter.takePendingSequences() + handBackHostState(renderer),
            restoringStyling: renderer.restoreTerminalStyling)
        SoftTrap.terminalRestored()
        signals.stop()
        appState.clearObservers()
        focusManager.clear()
        tuiContext.reset()
        // Persistence writes are queued asynchronously (and coalesced), so a
        // value stored moments before quitting may not have reached disk yet.
        // Flush behind any queued save — without this, "change a setting and
        // quit" sometimes silently lost the setting.
        StorageDefaults.backend.synchronize()
    }
}

// MARK: - Identifying the host at startup

/// The app's startup asks the terminal what it is (``AppRunner``, before the
/// render loop is built). Here, beside that one caller, because the exchange
/// needs the console ``Terminal`` and seeding the answer writes the process
/// environment: both the app layer's. What the exchange records
/// (``TerminalHost/startupIdentity``) and the verdict on its answers
/// (``TerminalHost/nameFromDeviceAttributes(_:)``) stay with the host
/// detection that reads them.
extension TerminalHost {
    /// Runs the identity exchange, records it, and seeds whatever it named.
    ///
    /// The one entry point, so that the recording and the seeding cannot drift
    /// apart: a diagnostic that reported a different host from the one actually
    /// being compensated for would be worse than no diagnostic.
    ///
    /// - Parameter terminal: the terminal to ask — it owns stdin, the termios
    ///   state the replies depend on, and the input buffer any stray keystrokes
    ///   have to be handed back to.
    /// - Returns: the name discovered, or `nil`.
    @MainActor @discardableResult
    static func identify(using terminal: Terminal) -> String? {
        let (identity, name) = terminal.queryIdentity()
        startupIdentity = identity
        if let name { seedDiscoveredHost(name) }
        return name
    }

    /// Records a host discovered at runtime, so every existing reader of
    /// ``isAppleTerminal`` and friends sees it.
    ///
    /// It goes into the process environment — the same place the answer would
    /// have come from had ssh forwarded it — rather than into a new global.
    /// That keeps exactly one source of truth for "which terminal is this",
    /// and means nothing downstream needs to know the answer arrived late.
    ///
    /// - Important: the detectors are `static let`, so each freezes on first
    ///   read. This must therefore run **before** anything reads one, which in
    ///   practice means before the render loop (and its `FrameDiffWriter`) is
    ///   constructed. `Tools/Smoke/identity_smoke.py` is what holds that
    ///   ordering: nothing in the type system can.
    ///
    /// - Parameter name: a `TERM_PROGRAM`-style name, as
    ///   ``nameFromDeviceAttributes(_:)`` returns.
    static func seedDiscoveredHost(_ name: String) {
        setenv("TUIKIT_TERM_PROGRAM", name, 1)
    }
}

// MARK: - Scene Rendering Protocol

/// Bridge from the `Scene` hierarchy to the `View` rendering system.
///
/// `SceneRenderable` sits outside the `View`/`Renderable` dual system.
/// It connects the `App.body` (which produces a `Scene`) to the view
/// tree rendering via ``renderToBuffer(_:context:)``.
///
/// `RenderLoop` renders the scene returned by `App.body` through
/// ``Scene/renderSceneTree(context:)``, which walks that scene's `body`
/// chain to the first conformer of this protocol — so a custom scene is
/// rendered by whichever primitive it is made of. The primitive (typically
/// ``WindowGroup``) then invokes the free function `renderToBuffer` on its
/// content view, entering the standard `Renderable`-or-`body` dispatch.
///
/// This protocol stays `internal` on purpose: it is the scene-side twin of
/// `Renderable`, but where a `View` outside the framework has a legitimate
/// reason to draw itself into a buffer, a scene does not — a terminal app has
/// exactly one window, and what a custom scene has to say is said by the
/// `WindowGroup` (and the scene modifiers) its `body` returns.
@MainActor
internal protocol SceneRenderable {
    /// Renders the scene's content into a ``FrameBuffer``.
    ///
    /// The caller (`RenderLoop`) is responsible for writing the buffer
    /// to the terminal via `FrameDiffWriter`.
    ///
    /// - Parameter context: The rendering context with layout constraints.
    /// - Returns: The rendered frame buffer.
    func renderScene(context: RenderContext) -> FrameBuffer
}
