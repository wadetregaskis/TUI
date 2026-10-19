//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputChainHarness.swift
//
//  Frames rendered the way the run loop brackets them, and keys handed to a
//  real `InputHandler` over the same services — the whole input chain, for
//  tests of what a key reaches and in what order.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

import Foundation

@testable import TUIkitApp
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

@MainActor
final class InputChainHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()
    let context: RenderContext
    let handler: InputHandler

    /// The frame clock, in nanoseconds: what the next frame reads as
    /// `frameNowNanos`. A test advances it to reach a deadline.
    ///
    /// The event clock too: an event handed to the dispatcher arrives at
    /// `now`, as in an app, where the two are one clock. A gesture's timer
    /// runs from its event's time and ends at a frame's, so kept apart they
    /// would never meet (decisions B92).
    var now: Int64 = 0

    /// The transaction the next frame is drawn under, as the run loop hands
    /// each frame the change it shows — an animated one's for the frame that
    /// makes it, and none after. An animation needs the frame to be able to
    /// animate too: `configure` sets `canAnimate`.
    ///
    /// It starts as the transaction `configure` left in the environment — none
    /// unless it set one — so a test that sets one there draws every frame
    /// under it: set over the root's environment on each frame, a default of
    /// none undid what `configure` set, and a test drawing under an animation
    /// drew under none (`VisualEffectTests.firstFrameUnderAnimationDoesNotSlide`).
    var transaction: Transaction

    /// How many times the chain asked the app to quit.
    var quits: Int { quitCount.value }
    private let quitCount = QuitCount()

    /// How many times the chain asked the app to suspend (an unclaimed Ctrl-Z).
    var suspends: Int { suspendCount.value }
    private let suspendCount = QuitCount()

    /// A box the quit callback counts into, built before `self` is.
    private final class QuitCount {
        var value = 0
    }

    /// - Parameters:
    ///   - keyboard: The kitty keyboard protocol's flags the terminal took, for
    ///     a test of what it reports; none, a legacy terminal, by default.
    ///   - configure: Changes the root environment before any frame — to hand
    ///     the page a fake clipboard, for one.
    ///   - undoManager: The app's undo manager, published to the environment
    ///     and given to the chain's undo keys and the status bar; none by
    ///     default, as outside a running app.
    init(
        width: Int = 40, height: Int = 12, keyboard: KittyKeyboardFlags = [],
        undoManager: UndoManager? = nil,
        configure: (inout EnvironmentValues) -> Void = { _ in }
    ) {
        tui.keyboardReporting = KeyboardReporting(flags: keyboard)
        tui.undoManager = undoManager
        tui.undoKeys.reporting = tui.keyboardReporting
        statusBar.undoManager = undoManager
        statusBar.undoKeys = tui.undoKeys
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        statusBar.focusManager = focusManager
        environment.statusBar = statusBar
        configure(&environment)
        transaction = environment.transaction
        // No run loop unions in a modifier's `.motion` request; without it the
        // dispatcher refuses every `.moved`.
        tui.mouseEventDispatcher.setActiveSupport(.full)
        context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        handler = InputHandler(
            statusBar: statusBar,
            keyEventDispatcher: tui.keyEventDispatcher,
            focusManager: focusManager,
            paletteManager: ThemeManager(items: PaletteRegistry.all, renderTrigger: {}),
            appearanceManager: ThemeManager(items: AppearanceRegistry.all, renderTrigger: {}),
            keyboardShortcuts: tui.keyboardShortcuts,
            dragAndDropSession: tui.dragAndDropSession,
            onQuit: { [quitCount] in quitCount.value += 1 },
            onSuspend: { [suspendCount] in suspendCount.value += 1 },
            undoManager: undoManager,
            undoKeys: tui.undoKeys,
            screenSelection: tui.screenSelection)
        tui.mouseEventDispatcher.nowNanos = { [weak self] in UInt64(max(0, self?.now ?? 0)) }
    }

    /// Renders one frame of `view`, clearing every per-frame registry first.
    ///
    /// - Parameter walks: How many times the frame walks the tree, the last
    ///   walk's buffer being the frame's: more than one is a corrected frame,
    ///   as the run loop's app-header height correction makes, with the
    ///   per-walk registries cleared between walks as
    ///   `RenderLoop.beginSceneRender()` clears them.
    ///
    /// `view` is made inside the pass, as an app's body makes its views, so
    /// an object a view makes with each of its values is one made in the
    /// pass (`StateStorage.inRenderPass(_:)`).
    @discardableResult
    func frame<V: View>(_ view: @autoclosure () -> V, walks: Int = 1) -> FrameBuffer {
        // As the run loop does: the gestures' clocks run to the frame's
        // instant before anything is cleared or rendered.
        tui.mouseEventDispatcher.advanceGestures(nowNanos: now)
        tui.mouseEventDispatcher.beginRenderPass()
        tui.dragAndDropSession.beginFrame()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        // The walk's claims too — the escape claim, the Return verb — as
        // `RenderLoop.beginSceneRender()` empties them before every walk: a
        // claim kept from the frame before read as one made inside this walk,
        // so a `NavigationStack` saw its own last claim and made none.
        statusBar.beginSceneRender()
        focusManager.beginRenderPass()
        // As `RenderLoop.beginRenderPass()` does, once the focus manager has
        // let go of last frame's controls: a text control that went away takes
        // its steps out of the undo manager here.
        tui.departedUndoSteps.takeOut()
        // A fresh tracker per frame, as the run loop installs one: without it
        // the per-pass memos stay off, and a test of what a served frame
        // still registers would pass with nothing served.
        var frameContext = context
        frameContext.environment.installVolatileReadTracker(VolatileReadTracker())
        frameContext.environment.frameNowNanos = now
        frameContext.environment.transaction = transaction
        // The global space's origin, carried down when there are readers, as
        // `RenderLoop.renderContent` carries it.
        frameContext = frameContext.carryingGeometryRootOrigin()
        let geometry = tui.mouseEventDispatcher.geometry
        var buffer = tui.stateStorage.inRenderPass {
            let view = view()
            var buffer = renderToBuffer(view, context: frameContext)
            for _ in 1..<max(1, walks) {
                beginSceneRender()
                buffer = renderToBuffer(view, context: frameContext)
            }
            // The scene root's geometry: `.global` and every name nothing nearer
            // declared, answered from the frame, and drawn once more when a reader
            // drew from a wrong answer — as `RenderLoop.renderContent` does.
            let size = CellSize(width: context.availableWidth, height: context.availableHeight)
            if geometry.resolveRemaining(in: buffer, size: size) {
                geometry.noteCorrection(.root)
                beginSceneRender()
                buffer = renderToBuffer(view, context: frameContext)
                if geometry.resolveRemaining(in: buffer, size: size) { geometry.noteResidual() }
            }
            return buffer
        }
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        // As the run loop hands it each composited frame: what a selection reads
        // and where its highlight is drawn.
        buffer = tui.screenSelection.takeFrame(
            buffer, width: context.availableWidth, palette: frameContext.environment.palette)
        focusManager.endRenderPass()
        tui.modifierKeys.endFrame()
        geometry.endFrame(frame: buffer, retainedBy: tui.stateStorage)
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// Clears the per-walk registries for another walk of the same frame, as
    /// `RenderLoop.beginSceneRender()` does.
    private func beginSceneRender() {
        tui.keyEventDispatcher.clearHandlers()
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginSceneRender()
        focusManager.beginSceneRender()
        statusBar.beginSceneRender()
    }

    /// How often the frames' geometry owners have drawn their subtrees again.
    var geometryCorrections: GeometryCorrections { tui.mouseEventDispatcher.geometry.corrections }

    /// Hands `event` to the chain and reports whether some layer took it.
    @discardableResult
    func press(_ event: KeyEvent) -> Bool {
        // As the app's funnel notes every input (`AppRunner`).
        tui.mouseEventDispatcher.noteInput()
        return handler.handle(event)
    }

    /// Hands a mouse event, in terminal cells, to the dispatcher, and reports
    /// whether it asked for a frame — noting it with the focus manager, as the
    /// app's funnel does.
    @discardableResult
    func mouse(_ event: MouseEvent) -> Bool {
        tui.mouseEventDispatcher.dispatch(event, noting: focusManager)
    }

    /// Moves the pointer through `path` over the view `build` makes, with a
    /// frame before the first move and after each.
    func hover(_ path: [(x: Int, y: Int)], _ build: () -> some View) {
        frame(build())
        for point in path {
            mouse(MouseEvent(button: .none, phase: .moved, x: point.x, y: point.y))
            frame(build())
        }
    }

    /// Plays `events` into the view `build` makes — built afresh for every
    /// frame, as an app's body is, so nothing rides along in a reused value —
    /// with a frame before the first key and after each one, so every key
    /// reaches what the last frame registered.
    ///
    /// - Returns: For each key, whether some layer of the chain took it.
    @discardableResult
    func play(_ events: [KeyEvent], _ build: () -> some View) -> [Bool] {
        frame(build())
        frame(build())
        var consumed: [Bool] = []
        for event in events {
            consumed.append(press(event))
            frame(build())
        }
        return consumed
    }
}

#endif
