//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputChainHarness.swift
//
//  Frames rendered the way the run loop brackets them, and keys handed to a
//  real `InputHandler` over the same services — the whole input chain, for
//  tests of what a key reaches and in what order.
//
//  Created by Wade Tregaskis
//  License: MIT

@testable import TUIkit
@testable import TUIkitStyling

@MainActor
final class InputChainHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    let statusBar = StatusBarState()
    let context: RenderContext
    let handler: InputHandler

    /// How many times the chain asked the app to quit.
    var quits: Int { quitCount.value }
    private let quitCount = QuitCount()

    /// A box the quit callback counts into, built before `self` is.
    private final class QuitCount {
        var value = 0
    }

    /// - Parameter configure: Changes the root environment before any frame —
    ///   to hand the page a fake clipboard, for one.
    init(width: Int = 40, height: Int = 12, configure: (inout EnvironmentValues) -> Void = { _ in }) {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        statusBar.focusManager = focusManager
        environment.statusBar = statusBar
        configure(&environment)
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
            onQuit: { [quitCount] in quitCount.value += 1 }, onSuspend: {})
    }

    /// Renders one frame of `view`, clearing every per-frame registry first.
    @discardableResult
    func frame(_ view: some View) -> FrameBuffer {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        tui.keyboardShortcuts.beginRenderPass()
        tui.preferences.beginRenderPass()
        statusBar.beginRenderPass()
        focusManager.beginRenderPass()
        // A fresh tracker per frame, as the run loop installs one: without it
        // the per-pass memos stay off, and a test of what a served frame
        // still registers would pass with nothing served.
        var frameContext = context
        frameContext.environment.installVolatileReadTracker(VolatileReadTracker())
        let buffer = renderToBuffer(view, context: frameContext)
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
