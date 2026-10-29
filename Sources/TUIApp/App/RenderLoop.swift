//  🖥️ TUI — A Terminal UI framework for Swift
//  RenderLoop.swift
//
//  Manages the rendering pipeline: scene rendering, environment
//  assembly, and status bar output.
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIChrome
import TUIFoundation

// MARK: - Render Loop

/// Manages the full rendering pipeline for each frame.
///
/// `RenderLoop` is owned by `AppRunner` and called once per frame.
/// It orchestrates the complete render pass from `App.body` to
/// terminal output.
///
/// ## Pipeline steps (per frame)
///
/// ```
/// render()
///   1. Clear per-frame state (key handlers, preferences, focus)
///   2. Begin lifecycle tracking
///   3. Build EnvironmentValues from all subsystems
///   4. Create RenderContext with layout constraints
///   5. Evaluate App.body fresh → Scene (WindowGroup)
///      @State values survive because State.init self-hydrates from StateStorage
///   6. Call SceneRenderable.renderScene() → FrameBuffer
///   7. Convert FrameBuffer to terminal-ready output lines
///   8. Begin buffered frame (terminal.beginFrame())
///      (the scene's chrome host draws the window's bars into it)
///   9. Diff against previous frame, write only changed lines to buffer
///  10. Flush entire frame in one write() syscall (terminal.endFrame())
///  11. End lifecycle tracking (fires onDisappear for removed views)
/// ```
///
/// ## Diff-Based Rendering
///
/// `RenderLoop` uses a `FrameDiffWriter` to compare each frame's output
/// with the previous frame. Only lines that actually changed are written
/// to the terminal, reducing I/O by ~94% for mostly-static UIs.
///
/// ## Output Buffering
///
/// All diff writes are collected in `Terminal`'s
/// frame buffer and flushed as a single `write()` syscall via
/// `Terminal.beginFrame()` / `Terminal.endFrame()`. This reduces
/// per-frame syscalls from ~40+ to exactly 1.
///
/// On terminal resize (SIGWINCH), the diff cache is invalidated to force
/// a full repaint.
///
/// ## Responsibilities
///
/// - Assembling ``EnvironmentValues`` from all subsystems
/// - Rendering the scene via `SceneRenderable` — the content and, framing it,
///   the chrome (never dimmed), as one frame
/// - Coordinating lifecycle tracking (appear/disappear)
/// - Diff-based terminal output via `FrameDiffWriter`
/// - Buffered frame output via `Terminal`
/// What animation clocks a render frame actually consumed.
///
/// The run loop uses this to keep a clock ticking only while a frame is still
/// consuming it — so a static screen drives no further frames. (Top-level, not
/// nested in the generic `RenderLoop`, so callers can name it without its type
/// parameter.)
struct RenderActivity {
    /// A view read the `pulsePhase` seam this frame (see
    /// ``EnvironmentValues/pulsePhase``).
    let usesPulse: Bool
    /// A view resolved the clock this frame — a focused control breathing, a
    /// focused field blinking.
    let usesCursor: Bool

    /// Clocks the frame left ``AnimatedCellRun``s for.
    ///
    /// A clock listed here can be advanced by replaying those runs against the
    /// frame already on screen. A clock some view READ cannot: that view built
    /// its appearance from the phase *while rendering*, so the only way to
    /// advance it is to render again. The two are not exclusive — a page
    /// mid-migration has both — and when they disagree the reader wins, because
    /// a frozen indicator is worse than a wasted frame.
    let animatedClocks: Set<AnimationClock>
}

@MainActor
internal final class RenderLoop<A: App> {
    /// The last frame written, for ``replayAnimations(elapsed:)``.
    /// `fileprivate` rather than `private` only so the replay half, which lives
    /// in `RenderLoop+Replay.swift`, can reach it.
    var replayable: ReplayableFrame?

    /// Where the last frame left the terminal's hidden cursor: on the focused
    /// text control's insertion point (`RenderLoop+Cursor.swift`), in screen
    /// cells from the top-left, or `nil` where it was left wherever the
    /// frame's last write ended.
    var parkedCursor: CellPoint?

    /// The terminal's size at the previous frame, `nil` before the first: a
    /// frame drawn at another size stamps `RenderCache.terminalResizedAtNanos`.
    private var lastFrameSize: (width: Int, height: Int)?

    /// The tooltip text the status bar was sized for this frame, before the
    /// walk; `nil` when it shows none. What
    /// ``requestTooltipFrames(nowNanos:scheduler:)`` holds the
    /// walk's answer against. Not private, for the reason ``terminalColors``
    /// gives.
    var statusBarTooltipText: String?

    /// What the last render reported, so the run loop can decide whether an
    /// animation tick can be replayed without rendering again.
    private(set) var lastActivity = RenderActivity(
        usesPulse: false, usesCursor: false, animatedClocks: [])

    /// The user's app instance (provides `body`).
    let app: A

    /// The terminal for output and size queries.
    ///
    /// Held as the protocol rather than the concrete `Terminal` so a test can
    /// drive a whole render pass against a `MockTerminal`. Without that, the
    /// only way to exercise this class was to run the app, and the bugs that
    /// live here — the per-pass registries the scene walk writes into — are
    /// invisible to every unit test on either side of it.
    ///
    /// One that keeps the ledger of what the app sets on it beyond its screen
    /// (``HostStateKeeping``): the frames set its window title and progress
    /// bar there (`RenderLoop+HostState.swift`).
    let terminal: any HostStateKeeping

    /// ``terminal``, where it can hold its display while a frame is drawn;
    /// `nil` where it cannot (a test's terminal, a headless one). Looked up
    /// once rather than cast on every frame.
    let synchronizedUpdates: (any SynchronizedUpdating)?

    /// The status bar state (height, items, appearance).
    let statusBar: StatusBarState

    /// The app's windows: which are open, in what order, and how they share
    /// the terminal (refusal review O9). The loop's own, like ``diffWriter``.
    let scenes = ScenePresenter()

    /// The rows the window's bars hold from frame to frame, which the scene's
    /// chrome host reserves before the content draws and adopts a frame after
    /// the content changes them: the window in front's. Each window keeps its
    /// own, so one coming back to the front has its bars where it left them.
    var windowChrome: WindowChromeState { scenes.frontChrome }

    /// The environment a window held behind the one in front starts from this
    /// frame: the loop's, without the front window's scene statements, to
    /// which the held window's own are applied (`RenderLoop+Scene.swift`).
    /// Kept only on a frame that holds a window, the only frames that read
    /// it, so a frame of one window neither copies its environment for it
    /// nor publishes the terminal's geometry twice; `nil` on any other.
    var windowBaseEnvironment: EnvironmentValues?

    /// The focus manager (cleared each frame).
    let focusManager: FocusManager

    /// The palette manager (current theme for environment).
    let paletteManager: ThemeManager

    /// The appearance manager (current border style for environment).
    let appearanceManager: ThemeManager

    /// The control style manager (the control style at the root, which View ▸
    /// Control Style ▸ chooses). The loop's own, made with it: unlike the
    /// palette and appearance managers no key cycles it, so the input chain
    /// never needs it.
    let controlStyleManager: ThemeManager

    /// The central dependency container (lifecycle, key dispatch, preferences).
    let tuiContext: TUIContext

    /// The identity at the root of the view tree.
    ///
    /// **Load-bearing invariant:** ``evaluateAppBody`` binds the app's
    /// `@State` under this identity (and marks it active, so the end-of-pass
    /// prune keeps it), and ``renderContent`` renders the scene under it too.
    /// The two MUST agree. If they diverge, App-level `@State`
    /// (e.g. a root view's selection index) lives at one root while the views it
    /// drives render under another — so it is not an ancestor of them, and
    /// `StateBox.didSet → RenderCache.clearAffected` matches none of their cache
    /// entries. The visible symptom is a value-memoized child (a `ForEach`
    /// selection highlight) frozen on its old value even though the state
    /// changed. Deriving both from this single property is what guarantees they
    /// can't drift apart.
    private var rootIdentity: ViewIdentity { ViewIdentity(rootType: A.self) }

    /// The identity the app's scene is drawn at: the one every walk of it
    /// pushes below ``rootIdentity`` (`withChildIdentity(type:)`), and so the
    /// one the scene catalogue reckons its scenes' identities from.
    private func sceneIdentity(of scene: A.Body) -> ViewIdentity {
        rootIdentity.child(type: type(of: scene))
    }

    /// The diff writer that tracks previous frames and writes only changed lines.
    let diffWriter = FrameDiffWriter()

    /// The lines `.hairline` list separators draw, as the terminal holds them
    /// (`RenderLoop+Hairlines.swift`). Idle, and never asked, on a host that
    /// draws none.
    let hairlines = HairlineLayer(z: HairlineLayer.z(for: TerminalClient.current.program))

    /// The pictures laid under glyphs that stand on a frosted picture
    /// (`RenderLoop+PicturesUnderText.swift`). Idle, and never asked, on a
    /// host that draws none.
    let picturesUnderText = PictureUnderTextLayer()

    /// The push-refreshed emoji-chrome answer (see ``ClientCapabilityRefresher``):
    /// seeded synchronously before the first frame, re-probed asynchronously
    /// when the tmux client-change hooks (or a real resize) send a SIGWINCH,
    /// and a full invalidate + render request when a landed answer differs.
    ///
    /// Instance state on the @MainActor render loop, deliberately NOT a global:
    /// a shared mutable static would be read by every headless render and test
    /// in the process, which is precisely the shape that produced the
    /// render-cache and colour-depth parallel-test flakes.
    ///
    /// Lazy because its `onChange` needs `diffWriter`, which is not available
    /// until `self` is. The capture list takes `diffWriter` itself, not `self`
    /// — a generic `self` in the closure would drag the non-Sendable `A.Type`
    /// into the refresher's detached task.
    private lazy var clientCapabilities = ClientCapabilityRefresher(
        isRefreshable: TerminalHost.isTmux,
        probe: probeClientCapabilities,
        onChange: { [diffWriter, appState = tuiContext.appState] in
            // Every glyph on screen could differ (■ vs ⬛ change cell widths):
            // full-repaint invalidation, plus a wake so the redraw happens NOW
            // even if the loop is idle-blocked awaiting input — the point is a
            // proactive refresh, not one deferred to the next keypress.
            diffWriter.invalidate()
            appState.setNeedsRender()
        })

    /// What the terminal says about its colours after the startup exchange has
    /// closed (see ``TerminalColorRefresher``): a reply that missed its deadline,
    /// or one volunteered when the terminal's theme changes.
    ///
    /// Instance state on the @MainActor render loop rather than a global, and
    /// lazy so its `onChange` can take `diffWriter` — both for the reasons
    /// ``clientCapabilities`` gives. Being lazy also means it seeds from
    /// `TerminalColors.current` at the first drain, which is after the startup
    /// exchange has published whatever it heard.
    ///
    /// A changed record repaints the whole screen: every colour on it may have
    /// been spelled or blended from the colours before the report, and the diff
    /// writer's idea of what is on screen is not reached by the generation that
    /// clears the render cache.
    ///
    /// What it publishes goes to ``publishTerminalColors``.
    ///
    /// Not private, alone among this type's stored properties, because the seam
    /// that reads it lives in `RenderLoop+TerminalColors.swift` — and `private`
    /// is file scope. The type itself is internal, so this is visible no further
    /// than it already was.
    lazy var terminalColors = TerminalColorRefresher(
        publish: publishTerminalColors,
        onChange: { [diffWriter, appState = tuiContext.appState] in
            diffWriter.invalidate()
            appState.setNeedsRender()
        })

    /// What the terminal is asked about its colours once the app is drawing (see
    /// ``TerminalColorRequester``): under tmux, the sixteen ANSI slots the
    /// startup exchange left out, once the first frame is on screen.
    ///
    /// Lazy and capturing `terminal` rather than `self`, as the two refreshers
    /// above are and do. The answer is not read here — it arrives on stdin like
    /// a keystroke, and `terminalColors` publishes it.
    /// Not private, for the reason ``terminalColors`` gives.
    lazy var colorQueries = TerminalColorRequester(
        isTmux: isTmux, send: { [terminal] request in terminal.write(request) })

    /// The environment snapshot from the previous frame.
    ///
    /// Compared after `buildEnvironment()` each frame. When the snapshot
    /// differs (e.g. palette or appearance changed), the render cache is
    /// cleared automatically. This ensures `EquatableView`-cached subtrees
    /// never serve stale content after theme changes — without requiring
    /// callers to manually invalidate the cache.
    private var lastEnvironmentSnapshot: EnvironmentSnapshot?

    /// The mouse-support configuration extracted from the scene this
    /// frame. The effective configuration (after view modifiers add
    /// per-frame requests) is `baseMouseSupport.union(with: requested)`.
    /// AppRunner reads ``effectiveMouseSupport`` after each render. Not
    /// private only because `RenderLoop+Scene.swift` sets it.
    var baseMouseSupport: MouseSupport = .standard

    /// Whether the app is running inside tmux, which decides what the terminal
    /// is asked about its colours once frames are being drawn (see
    /// ``TerminalColorRequester``), and whether the person sees the progress
    /// bar the app sends (`publishTerminalFeatures(_:)`).
    ///
    /// Taken at init rather than read from `TerminalHost.isTmux` at the point of
    /// use, for the reason `Terminal.askColors(isTmux:)` takes it too: the
    /// process's own answer is resolved once from the environment at launch, so
    /// a test that needs the other branch has no way to say so otherwise.
    /// Not private only because `RenderLoop+HostState.swift` reads it.
    let isTmux: Bool

    /// Whether the frames send the terminal the progress bar the views state
    /// (`.terminalProgress(_:)`): set by the app runner from the terminal it
    /// identified (`TerminalClient.progressReportsSupported`) — Ghostty,
    /// iTerm2, or tmux, which keeps the bar for its pane and passes it on.
    ///
    /// `false` in every loop but the app runner's, for the reason
    /// ``requestedAccessibility`` gives: what a test sends must not depend on the
    /// terminal its process was started in. Whether the person SEES the bar is
    /// `\.terminalFeatures.showsProgress`, published each frame from this and
    /// the tmux clients (`publishTerminalFeatures(_:)`).
    var sendsProgressReports = false

    /// What a progress bar that does not show says of the terminal, published
    /// to `\.terminalCapabilities` beside whether it shows
    /// (`publishTerminalFeatures(_:)`): set by the app runner from the terminal
    /// it identified (`TerminalCapabilities.progressAbsence(program:environment:)`),
    /// and undetermined in every other loop, for the reason
    /// ``sendsProgressReports`` gives.
    var progressAbsence = TerminalCapabilities.Status.undetermined

    /// Where ``terminalColors`` publishes what the terminal says about its
    /// colours: `TerminalColors.current` in an app, through
    /// `TerminalColorRefresher.publishProcessWide(_:)`.
    ///
    /// Taken at init, as ``isTmux`` is, so a test driving the loop can keep what
    /// it publishes to itself. The process-wide value is read by everything that
    /// renders in the process, and outlives the test that assigned it.
    private let publishTerminalColors: (TerminalColors) -> Void

    /// How ``clientCapabilities`` asks what the terminal(s) in front of the
    /// user can render: ``ClientCapabilityRefresher/probeHost`` in an app.
    ///
    /// Taken at init, as ``isTmux`` is, so a test can say what the terminals
    /// attached to tmux are without a tmux to ask.
    private let probeClientCapabilities: @Sendable () -> ClientCapabilities?

    /// What the user asked for with the `TUI_*` accessibility variables
    /// (`TUI_REDUCE_MOTION=1` and its three siblings), as the app runner
    /// read them from the process: written at the root of every frame
    /// (``EnvironmentValues/accessibilityReduceMotion``,
    /// ``EnvironmentValues/accessibilityReduceTransparency``,
    /// ``EnvironmentValues/accessibilityDifferentiateWithoutColor``,
    /// ``EnvironmentValues/colorSchemeContrast``).
    ///
    /// Empty unless the runner says otherwise. A headless app, the test
    /// harness and every other loop leave it out, so what they draw does not
    /// depend on the environment their process was started in — a user's
    /// exported setting would otherwise turn every transition in a test run
    /// into a fade.
    private let requestedAccessibility: AccessibilityPreferences

    /// The host's own accessibility settings, where the app runner is sure the
    /// user is at this machine (``HostSettingsRefresher``): added to
    /// ``requestedAccessibility`` at the root of every frame. Empty in every
    /// loop but the app runner's, for the same reason.
    var hostAccessibility: AccessibilityPreferences = []

    /// How the user asked for keys to be written with `TUI_KEY_SYMBOLS`, as
    /// the app runner read it from the process: written at the root of every
    /// frame as ``EnvironmentValues/keyNotation``.
    ///
    /// ``KeyNotation/symbols`` unless the runner says otherwise, for the reason
    /// ``requestedAccessibility`` gives: what a test draws must not depend on the
    /// environment its process was started in.
    private let keyNotation: KeyNotation

    /// The spring-loading delay the user asked for with
    /// `TUI_SPRING_LOADING_DELAY`, as the app runner read it from the
    /// process, or `nil`: written at the root of every frame as
    /// ``EnvironmentValues/springLoadingDelay``, over the host's own (owner
    /// ruling B82). `nil` unless the runner says otherwise, for the reason
    /// ``requestedAccessibility`` gives.
    private let springLoadingDelayRequested: Duration?

    /// The host's own spring-loading delay, where the app runner is sure the
    /// user is at this machine (``HostSettingsRefresher``), or `nil`: written
    /// at the root of every frame unless the user asked for another. `nil` in
    /// every loop but the app runner's, which takes macOS's default instead.
    var hostSpringLoadingDelay: Duration?

    init(
        app: A,
        terminal: any HostStateKeeping,
        statusBar: StatusBarState,
        focusManager: FocusManager,
        paletteManager: ThemeManager,
        appearanceManager: ThemeManager,
        tuiContext: TUIContext,
        isTmux: Bool = TerminalHost.isTmux,
        publishTerminalColors: @escaping (TerminalColors) -> Void =
            TerminalColorRefresher.publishProcessWide,
        probeClientCapabilities: @escaping @Sendable () -> ClientCapabilities? = ClientCapabilityRefresher.probeHost,
        requestedAccessibility: AccessibilityPreferences = [],
        keyNotation: KeyNotation = .symbols,
        springLoadingDelayRequested: Duration? = nil
    ) {
        self.isTmux = isTmux
        // Under tmux the bar is not sent again to keep it up: tmux keeps it,
        // and passes no repeat on.
        terminal.hostState.keepsProgressAlive = !isTmux
        self.publishTerminalColors = publishTerminalColors
        self.probeClientCapabilities = probeClientCapabilities
        self.requestedAccessibility = requestedAccessibility
        self.keyNotation = keyNotation
        self.springLoadingDelayRequested = springLoadingDelayRequested
        self.app = app
        self.terminal = terminal
        self.synchronizedUpdates = terminal as? any SynchronizedUpdating
        self.statusBar = statusBar
        self.focusManager = focusManager
        self.paletteManager = paletteManager
        self.appearanceManager = appearanceManager
        self.controlStyleManager = ThemeManager(
            items: ControlStyle.standardStyles,
            renderTrigger: { [appState = tuiContext.appState] in appState.setNeedsRender() })
        self.tuiContext = tuiContext
        // The windows ask this loop's app for a frame and for the quit, as
        // every other part of one app asks its own (`TUIContext.appState`).
        scenes.requestExit = { [appState = tuiContext.appState] in appState.requestExit() }
        scenes.requestFrame = { [appState = tuiContext.appState] in appState.setNeedsRender() }
    }

    /// The loop's last frame posted the docks of the sheets it drew for a
    /// frame that will never come, and their resolvers hold what reaches the
    /// focus manager (`FocusManager.forgetPresentationDocks()`): forgotten
    /// with the loop, so that the app's objects go with it.
    ///
    /// Not isolated: `focusManager` is a `let` of a `Sendable` type, and the
    /// loop is released where it ran, on the main thread.
    deinit {
        focusManager.forgetPresentationDocks()
    }
}

// MARK: - Internal API

extension RenderLoop {
    /// Performs a full render pass: scene content + status bar.
    ///
    /// See the class-level documentation for the complete pipeline steps.
    ///
    /// - Parameters:
    ///   - pulsePhase: The current breathing phase (0–1), from the one
    ///     animation clock (`CursorTimer.breathPhase`) via `AppRunner`.
    ///   - cursorTimer: The cursor timer for TextField/SecureField animations.
    ///   - animationScheduler: The run loop's animation scheduler, made available
    ///     to animating views via `context.requestAnimation(...)`. `nil` for
    ///     one-off renders (the backtick frame dump) that schedule no animation.
    ///   - frameNowNanos: The monotonic-clock timestamp (ns) of this frame — the
    ///     instant a wake declared this frame is measured from, and the same `now`
    ///     the run loop computes the next animation deadline after, so the two
    ///     agree exactly.
    ///   - frameDate: The wall clock at the same moment, read beside
    ///     `frameNowNanos`: the one date every walk of the frame resolves a
    ///     `TimelineView`'s schedule against. See `RenderCache.frameDate`.
    @discardableResult
    func render(
        pulsePhase: Double = 0,
        cursorTimer: CursorTimer? = nil,
        animationScheduler: AnimationScheduler? = nil,
        frameNowNanos: Int64 = FrameClock.nowNanos,
        frameDate: Date = FrameClock.nowDate
    ) -> RenderActivity {
        // This frame's instant, before anything reads a phase from the clock. The run
        // loop has already shown it; a render called any other way has not.
        cursorTimer?.observe(nowNanos: UInt64(bitPattern: frameNowNanos))
        // The timed input — drags, spring loading, gestures — runs to this
        // frame's instant first, against the last frame's regions.
        driveTimedInput(nowNanos: frameNowNanos, scheduler: animationScheduler)

        beginRenderPass()

        // The pass, to its end, as the one every `@State` made in it notes —
        // the app's body and every view value the walk makes included: what
        // tells an object made with a view value from one made before
        // (`StateStorage.inRenderPass(_:)`).
        return tuiContext.stateStorage.inRenderPass {
            renderBegunPass(
                pulsePhase: pulsePhase, cursorTimer: cursorTimer, animationScheduler: animationScheduler,
                frameNowNanos: frameNowNanos, frameDate: frameDate)
        }
    }

    /// The part of ``render(pulsePhase:cursorTimer:animationScheduler:frameNowNanos:frameDate:)``
    /// after its pass has begun, to the pass's end.
    private func renderBegunPass(
        pulsePhase: Double,
        cursorTimer: CursorTimer?,
        animationScheduler: AnimationScheduler?,
        frameNowNanos: Int64,
        frameDate: Date
    ) -> RenderActivity {
        // Terminal size: single getSize() call avoids 2 ioctl syscalls per frame.
        let terminalSize = terminal.getSize()
        let terminalWidth = terminalSize.width
        let terminalHeight = terminalSize.height
        // The instant of a resize, for `onInteractiveResizeChange`: see
        // `RenderCache.terminalResizedAtNanos`.
        if let last = lastFrameSize, last != terminalSize {
            tuiContext.renderCache.terminalResizedAtNanos = frameNowNanos
        }
        lastFrameSize = terminalSize

        // The scene walked, what its views did run once it is drawn, and the
        // walk made again while that wrote state, at most twice, before the
        // frame is written (`FrameSettling`, decisions B-D5G-11). The bars'
        // rows are the frame's: each walk made again is laid out against
        // the rows the first was, as the root's correction is.
        let geometry = tuiContext.mouseEventDispatcher.geometry
        var reservation: (top: WindowChromeState.Bar, bottom: WindowChromeState.Bar)?
        let walk = FrameSettling.settle(
            storage: tuiContext.stateStorage, cache: tuiContext.renderCache, lifecycle: tuiContext.lifecycle,
            appState: tuiContext.appState,
            walk: { effects in
                walkScene(
                    size: (terminalWidth, terminalHeight), pulsePhase: pulsePhase, cursorTimer: cursorTimer,
                    animationScheduler: animationScheduler, frameNowNanos: frameNowNanos, frameDate: frameDate,
                    effects: effects, reservation: &reservation)
            },
            // What the frame's geometry observers are owed, now it is drawn
            // (`GeometryCoordinator`): reports the frame's effects begin with.
            endWalk: { geometry.endFrame(frame: $0.frame, retainedBy: tuiContext.stateStorage) },
            beginRewalk: { [self] in
                if let reservation { windowChrome.reservation = reservation }
            })
        let buffer = walk.frame
        let environment = walk.environment
        let tooltipMovedThePage = walk.tooltipMovedThePage

        focusManager.endRenderPass()
        // Where the focus recovery left a focus a modifier-key alternate took.
        tuiContext.modifierKeys.endFrame()

        // Publish the frame's hit-test regions so the dispatcher can route
        // mouse events arriving between this frame and the next. They are in
        // the screen's coordinates, which are the pointer's: the chrome is
        // drawn into the frame with the page, so nothing is translated. A
        // hover tooltip is held through a reshape the bar's rows for it
        // caused (`RenderLoop+StatusBar.swift`).
        publishHitTestRegions(
            buffer.hitTestRegions, tooltipMovedThePage: tooltipMovedThePage, nowNanos: frameNowNanos,
            scheduler: animationScheduler)
        // A gesture this walk disabled is given up at the next frame's tick,
        // which runs what it held back: that frame is asked for now, so it
        // comes at the disable (decisions B-F2-2).
        if tuiContext.mouseEventDispatcher.hasPendingGestureDisable {
            animationScheduler?.requestWake("gesture-disable", at: frameNowNanos &+ 1)
        }

        writeFrame(
            buffer: buffer,
            environment: environment,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight,
            frameNowNanos: frameNowNanos
        )

        endRenderPass()
        // After `endRenderPass`, which drops a focus tooltip the drawn walk
        // did not publish again, and after `setRegions`, which may have put a
        // view with help under the resting pointer: a tooltip the walk changed
        // is the next frame's to draw (the bar was sized before the walk), and
        // a delay the reshape started needs its wake (`RenderLoop+StatusBar.swift`).
        requestTooltipFrames(nowNanos: frameNowNanos, scheduler: animationScheduler)

        // A frame is on screen. Under tmux that is when the sixteen ANSI slots
        // are asked for — the startup exchange left them out, because tmux holds
        // the fence about half a second when the client it forwards OSC 4 to is
        // silent, and that half second would have come out of the time before
        // this frame. Written and not waited for; the answer arrives as a late
        // reply. See `TerminalColorRequester`.
        colorQueries.noteFrameWritten()

        keepAnimating(scheduler: animationScheduler, frameNowNanos: frameNowNanos)

        // After the prune, so a value whose view left counts as removed. Run
        // last: a completion may change state, which only asks for a frame.
        tuiContext.stateStorage.animationCompletions.endPass(
            at: frameNowNanos, animations: tuiContext.stateStorage.animations)

        return recordActivity(
            usesPulse: (environment.volatileReadTracker?.demandingReads ?? 0) > 0,
            usesCursor: cursorTimer?.didReadThisFrame ?? false)
    }

    /// What one walk of the scene drew, and what it drew it from.
    private struct SceneWalk {
        /// The frame: the scene, with its chrome.
        let frame: FrameBuffer
        /// The environment the walk was rendered in.
        let environment: EnvironmentValues
        /// Whether the status bar's tooltip changed the rows the page had.
        let tooltipMovedThePage: Bool
    }

    /// One walk of the scene, with what it is drawn from: the environment
    /// built afresh, the app's body evaluated, its scenes adopted, the status
    /// bar's tooltip placed and the terminal's geometry published, then the
    /// scene rendered with its chrome
    /// (``renderContent(scene:environment:terminalWidth:terminalHeight:effects:)``) — what its
    /// views do held on the root's drawing, `effects`.
    ///
    /// `reservation` is the bars' rows the frame's first walk was laid out
    /// against: `nil` going in to the first, which notes them, and the rows
    /// a walk made again is laid out against.
    private func walkScene(
        size: (width: Int, height: Int),
        pulsePhase: Double,
        cursorTimer: CursorTimer?,
        animationScheduler: AnimationScheduler?,
        frameNowNanos: Int64,
        frameDate: Date,
        effects: ProvisionalEffects,
        reservation: inout (top: WindowChromeState.Bar, bottom: WindowChromeState.Bar)?
    ) -> SceneWalk {
        let (width, height) = size
        // If an @Published property changed, clear the entire render cache
        // so EquatableView-cached subtrees re-render with new model data.
        if tuiContext.appState.consumeNeedsCacheClear() {
            tuiContext.renderCache.clearAll()
        }

        // Create render context with environment
        var environment = buildEnvironment()
        publishAnimationValues(
            into: &environment, pulsePhase: pulsePhase, cursorTimer: cursorTimer,
            animationScheduler: animationScheduler, frameNowNanos: frameNowNanos, frameDate: frameDate)
        // Install a fresh volatile-read tracker at the render root so that, after
        // the frame, we can tell whether anything actually consumed the pulse
        // clock (the row memo reuses this same tracker further down). Likewise
        // reset the cursor clock's per-frame read flag. These drive demand-driven
        // animation: the run loop keeps a clock ticking only while a frame uses
        // it, so a static screen produces no further frames.
        // Mirrored onto the render cache as well as installed here: the measure
        // memo's gate reads it off the cache (`ChildInfo.measureChild`), and a
        // tracker the cache has not been told about switches that memo off.
        // Safe here and not earlier: `beginRenderPass()` above does not clear
        // the mirror, and `buildEnvironment()` has already wired the cache.
        environment.installVolatileReadTracker(VolatileReadTracker())
        cursorTimer?.beginFrameReadTracking()

        // The app's body reads nothing a walk keeps; a change to what it read
        // asks for a frame (`observingFrameReads`, FrameObservation.swift).
        let scene = observingFrameReads(cache: tuiContext.renderCache, identity: rootIdentity) {
            evaluateAppBody(environment: environment)
        }
        // The app's scenes, gathered in one walk of its body, and the windows
        // open on them; then what the window in front's modifiers state — its
        // root environment, mouse support, chrome style and undo keys — and
        // the app's commands (`RenderLoop+Scene.swift`).
        adoptScenes(SceneCatalog(scene, identity: sceneIdentity(of: scene)), environment: &environment)
        // Before the height is read, which is the whole trick: a tooltip's
        // triggers all land between frames (a mouse event, a key press, the
        // scheduled wake for the hover delay), so the candidate is already known
        // and the bar can be sized for it in this pass rather than the next.
        let tooltipMovedThePage = resolveStatusBarTooltip(
            terminalWidth: width, nowNanos: frameNowNanos, scheduler: animationScheduler)
        publishTerminalGeometry(into: &environment, width: width, height: height)
        invalidateCacheIfEnvironmentChanged(environment: environment)

        // Render the scene: its chrome host lays the top bar, the content
        // and the bottom bar out as one frame the size of the terminal, in one
        // walk (two on the first frame). See `renderContent`.
        // A walk made again is not the frame's first: the window's chrome is
        // seeded and its frame counted once.
        if reservation == nil { prepareWindowChrome(scene: scene, environment: environment, width: width, height: height) }
        reservation = reservation ?? windowChrome.reservation
        BindingReads.begin()
        let frame = renderContent(
            scene: scene,
            environment: environment,
            terminalWidth: width,
            terminalHeight: height,
            effects: effects)
        // Every `Binding` the walk read, read again under one scope that asks
        // for a frame when one changes: a control reads its binding in its
        // core, where no body's scope sees it (`BindingReads`).
        let bindingReads = BindingReads.end()
        if !bindingReads.isEmpty {
            observingFrameReads(cache: tuiContext.renderCache, identity: rootIdentity) {
                for read in bindingReads { read() }
            }
        }

        return SceneWalk(frame: frame, environment: environment, tooltipMovedThePage: tooltipMovedThePage)
    }

    /// Runs the timed input to this frame's instant, before
    /// ``beginRenderPass()`` clears the regions it resolves against: the drag
    /// session's auto-scroll and spring loading, the drag flights, and the
    /// gestures' clocks. What each asks for next — a lattice, a wake — goes to
    /// `scheduler`.
    private func driveTimedInput(nowNanos: Int64, scheduler: AnimationScheduler?) {
        // Drag auto-scroll: drive ONE tick against the PREVIOUS frame's zones
        // and region rects — before `beginRenderPass()` clears the dispatcher's
        // regions and before the tree re-registers this frame's zones. The drag
        // cursor is current, so a scroll near an edge shows in the frame we're
        // about to render, with no visible lag. This must precede
        // `beginRenderPass()`: that call empties `mouseEventDispatcher.regions`,
        // and `driveAutoScroll` resolves each zone's on-screen rect through the
        // dispatcher — run it after, and every `regionRect` lookup is nil and the
        // viewport never scrolls. While engaged the loop must keep ticking even
        // if the cursor holds still, so request a lattice at the auto-scroll cadence.
        //
        // Sourced from `tuiContext` (not `environment`, which the render has not
        // built yet) — the same session either way (see ServiceEnvironment).
        if tuiContext.dragAndDropSession.driveAutoScroll(
            nowNanos: UInt64(bitPattern: nowNanos))
        {
            scheduler?.request("drag-autoscroll", .dragAutoScroll)
        }

        // Spring loading, at the same point and for the same reason: the pause
        // is over what the LAST frame drew. A control the pause activates shows
        // its effect in this frame; one still pending asks for a frame at the
        // instant the pause will have lasted the delay, since a pointer resting
        // still sends nothing that would ask for one.
        if let deadline = tuiContext.dragAndDropSession.driveSpringLoading(
            nowNanos: UInt64(bitPattern: nowNanos))
        {
            scheduler?.requestWake("drag-spring-loading", at: Int64(bitPattern: deadline))
        }

        // A drag the keyboard carries stays on the stop it is at, which the
        // last frame drew — moved there, it is targeted where it now is.
        tuiContext.dragAndDropSession.followCarry()
        driveDragFlights(nowNanos: nowNanos, scheduler: scheduler)

        // The gestures' clocks — a long press's minimum duration, a tap's wait
        // for its next click — run to this frame's instant before the tree
        // renders, so what a timed end changes is drawn in this frame. Before
        // `beginRenderPass()` as well: a control a gesture was holding back is
        // handed its press here, against the handlers of the frame it was
        // pressed on.
        tuiContext.mouseEventDispatcher.advanceGestures(nowNanos: nowNanos)
        if let deadline = tuiContext.mouseEventDispatcher.gestureDeadline {
            scheduler?.requestWake("gestures", at: deadline)
        }
    }

    /// Advances the two drag flights and keeps the frames coming while either
    /// is running.
    ///
    /// A drag lifts its preview out of the row it came from over ~120 ms, and a
    /// cancelled one walks it home over ~200 ms. Same shape as the auto-scroll
    /// tick beside them: the loop is demand-driven, so each flight has to ask
    /// for its own frames or it would draw one and freeze.
    private func driveDragFlights(
        nowNanos frameNowNanos: Int64, scheduler animationScheduler: AnimationScheduler?
    ) {
        if tuiContext.dragAndDropSession.driveLift(
            nowNanos: UInt64(bitPattern: frameNowNanos))
        {
            animationScheduler?.request("drag-lift", .dragLift)
        }

        if tuiContext.dragAndDropSession.driveReturnFlight(
            nowNanos: UInt64(bitPattern: frameNowNanos)) != nil
        {
            animationScheduler?.request("drag-return", .dragReturn)
        }
    }

    /// Readies the window's chrome for the frame, before its first walk: the
    /// bars' rows seeded on a window's first frame, and the frame counted.
    ///
    /// The chrome host reserves the bars' rows before the content draws, and
    /// the content is what declares them, so the rows are last frame's answer
    /// (see ``WindowChromeState``). A window's first frame has none — the
    /// launch window's is the app's first — so it runs a throwaway measure
    /// pass first, whose only output is the chrome the content declares, and
    /// seeds the reservations from it: there is no last frame to reserve the
    /// bars from, and a window that declares its chrome once should not draw a
    /// frame without it.
    private func prepareWindowChrome(scene: A.Body, environment: EnvironmentValues, width: Int, height: Int) {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, identity: rootIdentity)
        // A window's first frame, the launch window's on the app's first: no
        // last frame to reserve its bars from.
        if let front = scenes.front, front.needsSeeding {
            var measureContext = context
            // This walk's buffer is thrown away — only the chrome it declares
            // survives it — so it is a measurement, and every guard written as
            // `!context.isMeasuring` must apply: `onAppear`, `.task`, focus and
            // mouse registration, `onChange`. Without this the discarded walk
            // was indistinguishable from a real render, so a view present here
            // and NOT in the drawn walk (the two see different heights, since
            // this one reserves no chrome) would appear, mount a task, and then
            // be told it disappeared, having never been drawn.
            //
            // `.toolbar` (under the seeding flag below) is deliberately NOT
            // guarded that way, which is what lets this walk still do its one
            // job. Anything that guards itself on the measure phase must not be
            // load-bearing for the chrome.
            measureContext.isMeasuring = true
            // The chrome host seeds every bar's rows from what this walk
            // declares, and `.toolbar` declares its items here although the
            // walk measures.
            measureContext.environment.seedsWindowChrome = true
            _ = renderScene(scene, context: measureContext.withChildIdentity(type: type(of: scene)))
            front.needsSeeding = false
        }
        windowChrome.beginFrame()
    }

    /// Renders the scene — the content framed by its chrome — and returns the
    /// frame: one walk, but one on which the scene root corrects a geometry
    /// reader (a second), discarding what the first walk's views would have
    /// done (`effects`).
    private func renderContent(
        scene: A.Body,
        environment: EnvironmentValues,
        terminalWidth: Int,
        terminalHeight: Int,
        effects: ProvisionalEffects
    ) -> FrameBuffer {
        // The render tree is rooted at `rootIdentity` — the SAME identity
        // `evaluateAppBody` hydrates `@State` under (see that property's note).
        var context = RenderContext(
            availableWidth: terminalWidth,
            availableHeight: terminalHeight,
            environment: environment,
            identity: rootIdentity
        )

        context.hasExplicitWidth = true
        context.hasExplicitHeight = true
        // The global space's origin, carried down for readers to be told where
        // they are before anything is drawn — when there are readers.
        context = context.carryingGeometryRootOrigin()
        let reservation = windowChrome.reservation
        // What the walk's views do — an `onChange` action, an `onAppear`, a
        // task's start — waits on `effects`, the root's drawing, until the
        // frame's driver keeps it once the walk is done; the scene walked
        // again below discards the first walk's (decisions B-D5G-4, B-D5G-11).
        var frame = renderScene(scene, context: context.withChildIdentity(type: type(of: scene)))

        // The scene root owns `.global` — the screen, which the frame is, with
        // the layers the window composited into it — and every name nothing
        // nearer declared: a reader that drew from a wrong answer is drawn
        // again, in a second walk of the scene. The one walk a frame after the
        // first ever draws again, and only on a frame a reader moved: the
        // chrome's rows never need it (they are last frame's answer).
        let geometry = tuiContext.mouseEventDispatcher.geometry
        let size = CellSize(width: terminalWidth, height: terminalHeight)
        if geometry.resolveRemaining(in: frame, size: size) {
            geometry.noteCorrection(.root)
            // What the first walk did is not done; the second walk's views
            // decide again from what the frame began with.
            effects.discard()
            // Laid out against the rows the first walk was, which its settling
            // may have changed for the NEXT frame — and settled again from them.
            windowChrome.reservation = reservation
            frame = renderScene(scene, context: context.withChildIdentity(type: type(of: scene)))
            if geometry.resolveRemaining(in: frame, size: size) { geometry.noteResidual() }
        }
        return frame
    }

    /// Invalidates the diff cache, forcing a full repaint on the next render.
    ///
    /// Call this when the terminal is resized (SIGWINCH).
    /// Hands the terminal back unstyled, before the app gives it to anything
    /// else — the shell on the way out, a job-control suspend.
    ///
    /// A frame may now END with styling still in force (see
    /// ``FrameDiffWriter/terminalStyle``), and leaving the alternate screen
    /// does not restore SGR, so this has to be said rather than assumed.
    func restoreTerminalStyling() {
        diffWriter.restoreDefaultStyling(on: terminal)
    }

    /// Forgets what styling the terminal is in, because something other than
    /// the diff writer has drawn on it: the frame dump's notice. The next
    /// frame then states its styling rather than carrying it over.
    func forgetTerminalStyling() {
        diffWriter.forgetTerminalStyling()
    }

    func invalidateDiffCache() {
        diffWriter.invalidate()
        // The screen is thrown away, so what the hairline layer says is on it
        // is not to be trusted either: its strips go, and every line is placed
        // again by the next frame.
        hairlines.invalidate()
        picturesUnderText.invalidate()
        // A SIGWINCH is also our signal that the tmux CLIENT may have changed —
        // either a real resize (attaching from a different-sized terminal), or
        // the synthetic one our tmux hooks send for a SAME-size attach/detach
        // (see `TerminalHost.installTmuxClientChangeHooks`). Re-ask tmux which
        // terminals are watching — asynchronously: frames keep rendering with
        // the previous answer, and if the new one differs the screen is fully
        // invalidated and redrawn when it lands.
        clientCapabilities.refresh()
        // And for the same reason the COLOURS may be a different terminal's: the
        // screen is thrown away on a resize, on a resumed suspend, and on the
        // client change those hooks turn into a SIGWINCH. Ask again — written
        // and not waited for, and not asked at all of a terminal that has never
        // said anything about its colours unless this is tmux, where the client
        // that was silent may not be the client attached now. See
        // `TerminalColorRequester`.
        colorQueries.screenInvalidated(terminalHasAnswered: terminalColors.hasAnsweredAboutColors)
    }

    /// What the attached terminal(s) can render this frame: the emoji-chrome
    /// answer for the environment, and the skin-tone answer for the writer.
    ///
    /// A pure cache read after the first call — the cache is push-refreshed by
    /// the tmux client-change hooks, off the render path; see
    /// ``ClientCapabilityRefresher``.
    func resolveClientCapabilities() -> ClientCapabilities {
        clientCapabilities.resolve()
    }

    /// The effective ``MouseSupport`` configuration after combining
    /// the scene-level base with per-frame feature requests from view
    /// modifiers.
    ///
    /// Read by the AppRunner once per frame to bring the terminal
    /// tracking mode in sync.
    func effectiveMouseSupport() -> MouseSupport {
        tuiContext.mouseEventDispatcher.effectiveSupport(baseConfig: baseMouseSupport)
    }

    /// Builds a complete ``EnvironmentValues`` with all managed subsystems.
    ///
    /// - Returns: A fully populated environment.
    func buildEnvironment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.statusBar = statusBar
        environment.appStatusBar = statusBar
        environment.windowChrome = windowChrome
        environment.openWindow = OpenWindowAction(handler: scenes.actions)
        environment.openSettings = OpenSettingsAction(handler: scenes.actions)
        environment.scenePresenterReference = scenes.environmentReference
        environment.focusManager = focusManager
        environment.paletteManager = paletteManager
        if let palette = paletteManager.currentPalette {
            environment.palette = palette
        }
        environment.appearanceManager = appearanceManager
        if let appearance = appearanceManager.currentAppearance {
            environment.appearance = appearance
        }
        environment.controlStyleManager = controlStyleManager
        // Only a choice: the default is the environment's own, so a frame no
        // one chose a style for is the frame it always was.
        if let style = controlStyleManager.currentControlStyle, style != .automatic {
            environment.controlStyle = style
        }
        environment.notificationService = NotificationService.current
        // The user's `TUI_REDUCE_MOTION`, and the host's own Reduce Motion
        // where the user is provably at this machine, at the root, where the
        // app runner passed them (see `requestedAccessibility`,
        // `hostAccessibility`); a scene's own `.reduceMotion(_:)` is applied
        // over them with the scene's other writes.
        let accessibility = requestedAccessibility.union(hostAccessibility)
        environment.accessibilityReduceMotion = accessibility.contains(.reduceMotion)
        // And the three P5 reads beside it, which no scene adds to.
        environment.accessibilityReduceTransparency = accessibility.contains(.reduceTransparency)
        environment.accessibilityDifferentiateWithoutColor = accessibility.contains(.differentiateWithoutColor)
        environment.colorSchemeContrast = accessibility.contains(.increaseContrast) ? .increased : .standard
        // The user's `TUI_KEY_SYMBOLS` likewise; a scene's `.keyNotation(_:)`
        // can only add to it.
        environment.keyNotation = keyNotation
        // The user's spring-loading delay: their `TUI_SPRING_LOADING_DELAY`,
        // else the host's where they are provably at it, else macOS's default
        // (the key's own). A view's `.springLoadingDelay(_:)` overrides it.
        if let delay = springLoadingDelayRequested ?? hostSpringLoadingDelay {
            environment.springLoadingDelay = delay
        }

        // Terminal-adaptive defaults belong to the app run loop, where a real
        // terminal exists — the bare EnvironmentValues defaults stay
        // terminal-independent so headless renders and tests are
        // deterministic. `.toggleCharacterSet(_:)` modifiers below still override.
        //
        // `resolveClientCapabilities()` rather than the static `.automatic`,
        // because under tmux the answer depends on the CLIENT terminal's font
        // and only tmux can name it — a question that costs a subprocess, so it
        // is cached here and push-refreshed by the tmux client-change hooks
        // (see `ClientCapabilityRefresher`). Off tmux it is the same static
        // allowlist. The DEFAULT is the `.automatic` marker, and the answer it
        // stands for goes alongside it. Injecting the marker (rather than a
        // style already resolved here) is what makes an app's own explicit
        // `.toggleCharacterSet(.automatic)` adapt too — it overrides this
        // default with the same marker, and the render site resolves whichever
        // arrives.
        let capabilities = resolveClientCapabilities()
        environment.toggleCharacterSet = .automatic
        environment.resolvedAutomaticToggleCharacterSet = .automatic(
            emojiChrome: capabilities.emojiChrome)
        environment.supportsEmojiChrome = capabilities.emojiChrome
        environment.blockElementsFillTheLine = capabilities.blockElementsFillTheLine
        environment.cornerTrianglesFillTheCell = capabilities.cornerTrianglesFillTheCell
        // Not per tmux client: tmux re-spells line styles for each client
        // itself (`TerminalHost.lineStyles`).
        environment.lineStyleSupport = TerminalHost.lineStyles
        // The writer's tmux skin-tone scope follows the same per-client answer:
        // keep the tone bases tmux itself merges (the measured 70 — see
        // Character.tmuxMergedToneBases) only when every attached client also
        // renders tmux's re-emission of them (Ghostty alone). Set per frame; a change always arrives via the
        // refresher's onChange, whose full invalidation keeps the writer's
        // line-reuse cache from serving lines stripped under the old policy.
        diffWriter.tmuxSkinToneScope =
            capabilities.skinTonesSafe ? .keepingTmuxMerged : .all

        // Whether the person sees the progress bar: under tmux it follows the
        // clients attached, so it is published from the same answer, before
        // the runtime services below carry it into the environment.
        publishTerminalFeatures(capabilities)

        // Runtime services (shared with ViewRenderer's one-off path so
        // the wired set can't drift — see EnvironmentValues.applyRuntimeServices).
        environment.applyRuntimeServices(from: tuiContext)

        return environment
    }
}

// MARK: - Private Helpers

extension RenderLoop {
    /// Clears all per-frame state and begins lifecycle/state/cache tracking.
    ///
    /// Only the registries that genuinely belong to the FRAME live here. The
    /// ones that belong to a single walk of the scene are reset by
    /// ``beginSceneRender()`` instead — see that method for why the difference
    /// matters and how to decide which list a new registry joins.
    fileprivate func beginRenderPass() {
        // Per-PASS. `focusManager.beginRenderPass()` snapshots `previousSections`
        // and must therefore run BEFORE anything clears the current ring.
        focusManager.beginRenderPass()
        statusBar.focusManager = focusManager
        tuiContext.lifecycle.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        // After the focus manager has let go of last frame's controls, which
        // frees a text control that has left the screen, and before the status
        // bar is sized: the control's undo steps leave the app's manager in
        // this frame, and the bar does not offer them.
        tuiContext.departedUndoSteps.takeOut()
        // Per-WALK, reset again before each scene render.
        beginSceneRender()
    }

    /// Clears the registries that belong to ONE walk of the scene tree.
    ///
    /// `renderContent` walks the scene twice inside the first frame's
    /// ``beginRenderPass()``/``endRenderPass()`` bracket: a throwaway walk to
    /// find the chrome the content declares, then the drawn one. (Every frame
    /// used to be exposed: a correction re-render ran whenever the app header's
    /// height disagreed with the estimate the frame was laid out against. The
    /// window's chrome now adopts a change a frame later instead.) It walks
    /// it again on any frame whose scene root corrects a geometry reader
    /// (`GeometryCoordinator.resolveRemaining`). Only the LAST walk's buffer
    /// is drawn — so only the last walk's registrations should survive.
    ///
    /// Resetting these once per PASS instead let the discarded walk's entries
    /// pile up on top of the drawn walk's:
    ///
    /// - `stateStorage`'s onChange counters are claimed POSITIONALLY, so the
    ///   second walk's `.onChange` claimed index 1 where the first claimed 0,
    ///   found that slot empty, and fired again — every app's
    ///   `.onChange(of:initial:true)` ran twice at launch, and the junk left in
    ///   slot 1 could fire a spurious `action(stale, new)` on a later corrected
    ///   frame even with the default `initial: false`. `.onPreferenceChange`
    ///   shares the counter and was corrupted the same way.
    /// - key handlers APPEND, and dispatch walks every entry until one
    ///   consumes, so a handler that declines with a side effect (the blessed
    ///   log-the-key pattern) ran its side effect once per duplicate.
    /// - preference values are REDUCED into a stack, so an accumulating
    ///   `reduce` collected every published value twice.
    /// - mouse handler SLOTS are positional: a handler id is interned per
    ///   `(identity, slot)`, and the slot is the ordinal of the registration at
    ///   that identity within the walk, so the counters must restart with the
    ///   walk or the second walk would mint a second id for every control.
    ///   (The IDS themselves were positional once, and a two-walk frame then
    ///   shifted every control's id, so the hover tracker's cross-frame
    ///   comparison sent `.exited` to a *different* control.)
    /// - focus sections accumulate (registration merely de-duplicates by
    ///   focusID), so a corrected frame's Tab ring was the union of both walks
    ///   in the DISCARDED walk's order — which was built at the wrong content
    ///   height, and so could contain focusables the drawn frame does not show.
    ///
    /// Called from ``renderScene(_:context:)`` — the one funnel every walk goes
    /// through — rather than at each call site, so a future third walk is
    /// correct without anyone remembering this. `WindowGroup.renderScene`
    /// already resets the drag-and-drop session the same way.
    ///
    /// What must NOT move here, and why: `focusManager.beginRenderPass()`
    /// (snapshots last frame's ring so a focus LOSS can still reach its
    /// element), `lifecycle` (what a discarded walk's views did after a reader
    /// was told an answer — their appearances, tasks and presence — is put
    /// back with the rest of what they did: `renderContent` discards its
    /// ``ProvisionalEffects``; what they did before it, the second walk draws
    /// again as it was), `renderCache` (a cache entry seen only in a discarded
    /// walk surviving one extra frame is the conservative direction — no
    /// premature eviction), and above all `stateStorage.beginRenderPass()`, which also
    /// clears `activeIdentities` — already carrying `evaluateAppBody`'s
    /// `markActive(rootIdentity)` by the time a walk starts, so clearing it
    /// mid-pass would let `endRenderPass` prune the App's own root `@State` on
    /// every corrected frame. That is why `beginSceneRender` on `StateStorage`
    /// is deliberately narrower than its `beginRenderPass`.
    fileprivate func beginSceneRender() {
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.mouseEventDispatcher.beginRenderPass()
        tuiContext.keyboardShortcuts.beginRenderPass()
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginSceneRender()
        focusManager.beginSceneRender()
        // The hint line's items and its per-frame escape and Return claims, and
        // the toolbar items: what each walk declares is that walk's.
        statusBar.beginSceneRender()
        windowChrome.beginWalk()
        // And for a tooltip's FOCUS candidate, republished by the focused
        // control every walk — marked, not cleared: the status bar is sized
        // from it before the walk republishes it, and `endRenderPass` drops it
        // if the drawn walk did not (`TooltipState.endFrame`). One the focus
        // has moved off goes now. Its hover candidate is not touched: the
        // pointer stays where it is between frames, and only an `.exited`
        // event knows it has left.
        tuiContext.tooltipState.beginWalk()
        tuiContext.tooltipState.syncFocus(focusID: focusManager.currentFocusedID)
    }

    /// Evaluates `App.body` with the App's `@State` bound under ``rootIdentity``
    /// and the environment published so `@Environment` reads from it. (The
    /// views `body` builds bind their own `@State` later, each at its own render
    /// identity, in `renderToBuffer`.)
    fileprivate func evaluateAppBody(environment: EnvironmentValues) -> A.Body {
        // An `App` is not a `View`, so no render walk ever reaches it to bind its
        // `@State`. Left unbound, each property kept the box `State.init` made,
        // which has no identity and no render cache: a write asked for nothing,
        // and a memoized view below the scene (a `ForEach` row drawing the value
        // from its closure) kept its old buffer. Bound here, a write clears
        // `rootIdentity` and everything below it, as a root view's `@State` would.
        let plan = propertyPlan(for: A.self)
        // The environment is published around `body` too, for a read the walk
        // cannot reach. The scope ends with the call, so nothing outside it
        // ever sees this value. An app property's `update()` runs inside it,
        // for the same reason, and what it left is the `App` whose body is
        // read.
        let scene = StateRegistration.withHydration(environment: environment) {
            guard let plan else { return app.body }
            var prepared = app
            prepareProperties(
                of: &prepared, plan: plan, identity: rootIdentity, storage: tuiContext.stateStorage,
                environment: environment, isMeasuring: false)
            return prepared.body
        }
        tuiContext.stateStorage.markActive(rootIdentity)
        return scene
    }

    /// Writes the assembled frame to the terminal using diff-based output.
    ///
    /// Builds terminal-ready output lines, then writes them inside a single
    /// buffered frame (one `write()` syscall). The frame is the whole screen —
    /// the chrome host stacked the header and the status bar into it.
    fileprivate func writeFrame(
        buffer: FrameBuffer,
        environment: EnvironmentValues,
        terminalWidth: Int,
        terminalHeight: Int,
        frameNowNanos: Int64
    ) {
        let backgroundCodes = RenderBackgroundCodes(palette: environment.palette)
        let reset = ANSIRenderer.reset

        // A region that reaches the root was never composited over anything,
        // so what is behind it is the page's surface. The bars are surfaces of
        // their own — a faded item in the status bar fades toward the STATUS
        // BAR's background, not the page's — and the chrome host resolved
        // theirs against them as it stacked them, so none of their claims is
        // left for this one.
        let palette = environment.palette
        let buffer = buffer.resolvingOpacity(
            surface: palette.background, palette: palette, images: tuiContext.terminalImageStore)

        let outputLines = diffWriter.buildReusingOutputLines(
            buffer: buffer,
            terminalWidth: terminalWidth,
            terminalHeight: terminalHeight,
            bgCode: backgroundCodes.content,
            reset: reset
        )

        terminal.beginFrame()

        // Images owed to the terminal, before any cell that names one. A
        // placeholder pointing at an image the terminal has not been given yet
        // draws nothing, and would go on drawing nothing until something
        // happened to make that row dirty again. Inside `beginFrame` so it
        // joins this frame's single write rather than issuing one of its own.
        let graphics = tuiContext.terminalImageStore.takePending()
        if !graphics.isEmpty { terminal.write(graphics) }
        // The hairlines' strips, and the deletes an invalidation owes, with the
        // other images: they draw nothing.
        let hairlinesPrepared = prepareHairlines(environment: environment, terminalWidth: terminalWidth)
        let picturesPrepared = preparePicturesUnderText()

        // Copies owed to the terminal's clipboard (OSC 52), made between frames
        // by a key or a release. They draw nothing and move no cursor, so they
        // go with the other out-of-band writes, ahead of every cell.
        let copies = tuiContext.clipboardWriter.takePendingSequences()
        if !copies.isEmpty { terminal.write(copies) }
        // The bell a control rang for input it turned away, and the attention
        // the app asked for, likewise; see `RenderLoop+HostState.swift`.
        let attention = attentionWrites()
        if !attention.notifications.isEmpty { terminal.write(attention.notifications) }
        if !attention.bell.isEmpty { terminal.write(attention.bell) }
        // The window title and the progress bar, where they changed; see
        // `RenderLoop+HostState.swift`.
        let host = hostStateWrites(atNanos: frameNowNanos)
        if !host.isEmpty { terminal.write(host) }

        // The terminal holds its display from here to the frame's end, if the
        // frame writes a row. After the transmissions, which draw
        // nothing and can be large enough to outlast a hold; before the first
        // cell. See `Terminal.beginSynchronizedUpdate()`.
        synchronizedUpdates?.beginSynchronizedUpdate()

        let wrote = diffWriter.writeContentDiff(
            newLines: outputLines,
            terminal: terminal,
            startRow: 1,
            terminalWidth: terminalWidth,
            bgCode: backgroundCodes.content,
            reset: reset
        )
        // The lines, after the cells they run along, inside the same hold.
        let placedHairlines = hairlinesPrepared && hairlines.place(on: terminal, startRow: 1)
        // The pictures under the glyphs, likewise.
        let placedPictures = picturesPrepared && picturesUnderText.place(on: terminal, startRow: 1)
        // The images this frame let go of, after the cells that stopped naming
        // them and inside the same hold: a picture swapped for another goes in
        // one held update, never blank in between. See
        // `TerminalImageStore.takeDeletes()`.
        let deletes = tuiContext.terminalImageStore.takeDeletes()
        if !deletes.isEmpty { terminal.write(deletes) }
        parkCursor(
            at: insertionPointOnScreen(
                in: buffer.hitTestRegions, width: terminalWidth, height: outputLines.count),
            afterWriting: wrote || placedHairlines || placedPictures)

        // Keep what an animation tick would need to patch: the lines actually on
        // screen, the runs composited into absolute positions, and the geometry
        // the diff was written with. Only runs that ANIMATE are kept — a
        // one-frame run is a still picture the render above already drew — and
        // only the ON-SCREEN part of each: content can exceed the terminal (a
        // wide unwrapped row, say — buildOutputLines clips the LINES to the
        // terminal but nothing clipped the runs), and a run patched past the
        // edge pads its row wider than the terminal, which wraps and smears
        // the row below. A run straddling the edge is CUT to the screen, not
        // dropped, so its visible cells keep animating — the same cut every
        // interior clip makes in `clamped`; see
        // `AnimatedCellRun.clipped(toCanvasColumns:rows:)`.
        replayable = ReplayableFrame(
            contentLines: outputLines,
            runs: buffer.animatedCells.compactMap { run in
                guard run.isAnimating else { return nil }
                return run.clipped(toCanvasColumns: terminalWidth, rows: outputLines.count)
            },
            terminalWidth: terminalWidth,
            startRow: 1,
            backgroundCode: backgroundCodes.content)

        terminal.endFrame()
    }

    /// Stores and returns what this frame reported, so the run loop can decide
    /// whether the next animation tick needs a render at all.
    ///
    /// Every run on screen is the frame's, the chrome's included — the bars are
    /// rows of the frame like any other, so the replay patches a `Spinner` in
    /// a toolbar as it patches one on the page.
    private func recordActivity(usesPulse: Bool, usesCursor: Bool) -> RenderActivity {
        lastActivity = RenderActivity(
            usesPulse: usesPulse,
            usesCursor: usesCursor,
            animatedClocks: Set((replayable?.runs ?? []).lazy.map(\.clock)))
        return lastActivity
    }

    /// Ends lifecycle, state, and cache tracking for this render pass.
    ///
    /// Fires `onDisappear` for removed views and removes state/cache
    /// entries for views no longer in the tree.
    fileprivate func endRenderPass() {
        tuiContext.lifecycle.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        tuiContext.renderCache.logFrameStats()
        tuiContext.tooltipState.endFrame()
    }

    /// Clears the render cache when environment values affecting visual output changed.
    ///
    /// Compares this frame's `EnvironmentSnapshot` with the previous frame's. On
    /// mismatch, all `EquatableView`-cached subtrees are invalidated so they
    /// re-render with the new palette, appearance, glyphs, locale, scene phase,
    /// cell geometry, terminal size or terminal features.
    ///
    /// This runs once per frame (a palette comparison and eleven small ones) and
    /// ensures developers never need to manually invalidate the cache after theme
    /// changes — including a palette whose colours were edited under the same id.
    fileprivate func invalidateCacheIfEnvironmentChanged(environment: EnvironmentValues) {
        let currentSnapshot = EnvironmentSnapshot(from: environment)
        if let lastSnapshot = lastEnvironmentSnapshot, lastSnapshot != currentSnapshot {
            tuiContext.renderCache.clearAll()
        }
        lastEnvironmentSnapshot = currentSnapshot
    }

    /// Renders the app's scene: its open windows, as the scene presenter's
    /// policy places them, each by descending to the primitive that draws it.
    ///
    /// The one funnel every walk of the scene passes through, which is why the
    /// per-walk registries are reset here — see ``beginSceneRender()``.
    fileprivate func renderScene<S: Scene>(_ scene: S, context: RenderContext) -> FrameBuffer {
        beginSceneRender()
        // The walk window. A `@State` write reaching the invalidation funnel
        // from THIS thread while this is open is a body mutation — it asks for
        // another frame from inside the frame being built. Opened and closed
        // here because this is the one funnel, so every walk is covered and no
        // walk is covered twice.
        let diagnostic = tuiContext.renderCache.bodyMutationDiagnostic
        diagnostic?.beginTraversal()
        defer { diagnostic?.endTraversal() }
        return scenes.render(scene, context: context) { [self] configuration in
            heldWindowEnvironment(configuration)
        }
    }
}
