//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PointerShapeHarness.swift
//
//  Frames rendered as the run loop brackets them, with the terminal's
//  features posed, and the pointer moved about: for the tests of the shape
//  `pointerStyle(_:)` and TUIkit's own controls give the pointer.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUIkitTestSupport in Package.swift).
#if TUIKIT_TEST_SUPPORT && canImport(Testing)

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
@testable import TUIkitView

/// Renders frames as `RenderLoop` brackets them — every per-walk registry
/// emptied first, the frame's regions published after — with the terminal's
/// features posed: whether it takes pointer shapes, and whether TUIkit's own
/// controls set theirs.
@MainActor
final class PointerShapeHarness {
    let tui = TUIContext()
    let focusManager = FocusManager()
    var cache: RenderCache { tui.renderCache }
    var dispatcher: MouseEventDispatcher { tui.mouseEventDispatcher }
    let width: Int
    let height: Int

    init(shapes: Bool = true, controlShapes: Bool = false, width: Int = 40, height: Int = 10) {
        self.width = width
        self.height = height
        tui.terminalFeatures = TerminalFeatures(pointerShapes: shapes, controlPointerShapes: controlShapes)
        dispatcher.setActiveSupport(.full)
    }

    /// Renders one frame and publishes its regions.
    @discardableResult
    func frame(_ view: some View) -> FrameBuffer {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tui)
        environment.installVolatileReadTracker(VolatileReadTracker())
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui)
        tui.stateStorage.beginRenderPass()
        cache.beginRenderPass()
        focusManager.beginRenderPass()
        focusManager.beginSceneRender()
        dispatcher.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tui.stateStorage.endRenderPass()
        cache.removeInactive()
        dispatcher.setRegions(buffer.hitTestRegions)
        return buffer
    }

    /// Moves the pointer to `(x, y)`, and returns whether the move asked for a
    /// frame.
    @discardableResult
    func move(x: Int, y: Int) -> Bool {
        dispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: x, y: y))
    }

    /// The shape the pointer is given at `(x, y)`.
    func shape(atX x: Int, y: Int) -> PointerShape? {
        move(x: x, y: y)
        return dispatcher.pointerShapeUnderPointer()
    }

    /// Where `text` is drawn in `buffer`: its first cell, found in the drawn
    /// lines rather than computed.
    func cell(of text: String, in buffer: FrameBuffer) -> (x: Int, y: Int)? {
        for (y, line) in buffer.lines.enumerated() {
            let stripped = line.stripped
            guard let range = stripped.range(of: text) else { continue }
            return (stripped.distance(from: stripped.startIndex, to: range.lowerBound), y)
        }
        return nil
    }
}

#endif
