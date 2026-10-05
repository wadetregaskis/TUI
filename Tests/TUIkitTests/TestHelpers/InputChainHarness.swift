//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputChainHarness.swift
//
//  Frames rendered the way the run loop brackets them, and keys handed to a
//  real `InputHandler` over the same services — the whole input chain, for
//  tests of what a key reaches and in what order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitStyling

@MainActor
final class InputChainHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()
    let context: RenderContext
    let handler: InputHandler

    /// The frame clock, in nanoseconds: what the next frame reads as
    /// `frameNowNanos`. A test advances it to reach a deadline.
    var now: Int64 = 0

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
    }

    /// Renders one frame of `view`, clearing every per-frame registry first.
    ///
    /// - Parameter walks: How many times the frame walks the tree, the last
    ///   walk's buffer being the frame's: more than one is a corrected frame,
    ///   as the run loop's app-header height correction makes, with the
    ///   per-walk registries cleared between walks as
    ///   `RenderLoop.beginSceneRender()` clears them.
    @discardableResult
    func frame(_ view: some View, walks: Int = 1) -> FrameBuffer {
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
        statusBar.beginRenderPass()
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
        var buffer = renderToBuffer(view, context: frameContext)
        for _ in 1..<max(1, walks) {
            tui.keyEventDispatcher.clearHandlers()
            tui.mouseEventDispatcher.beginRenderPass()
            tui.keyboardShortcuts.beginRenderPass()
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginSceneRender()
            focusManager.beginSceneRender()
            statusBar.beginSceneRender()
            buffer = renderToBuffer(view, context: frameContext)
        }
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        // As the run loop hands it each composited frame: what a selection reads
        // and where its highlight is drawn.
        buffer = tui.screenSelection.takeFrame(
            buffer, width: context.availableWidth, palette: frameContext.environment.palette)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer
    }

    /// Hands `event` to the chain and reports whether some layer took it.
    @discardableResult
    func press(_ event: KeyEvent) -> Bool {
        handler.handle(event)
    }

    /// Hands a mouse event, in terminal cells, to the dispatcher, and reports
    /// whether it asked for a frame.
    @discardableResult
    func mouse(_ event: MouseEvent) -> Bool {
        tui.mouseEventDispatcher.dispatch(event)
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
