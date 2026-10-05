//  🖥️ TUIkit — Terminal UI Kit for Swift
//  HeadlessInputChannels.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Headless Input Channels

/// The per-walk input registries a renderer without a `RenderLoop` wires into
/// its environment: a key event dispatcher, a keyboard-shortcut registry, a
/// status bar and a mouse dispatcher, emptied before every walk the way the
/// render loop empties them.
///
/// For the `Stress` bench, which renders headless and cannot see these types.
/// Without them a bench renders a tree whose registrations all go nowhere:
/// `onKeyEvent` traps on its dispatcher, and a `Button` with
/// `.keyboardShortcut` neither registers nor declares, so the bench measured
/// cheaper frames than the app draws and could not see a memo that keeps a
/// subtree's registrations alive.
///
/// The mouse is one of those registries, not a separate kind of thing: a
/// control with a dispatcher in the environment registers a hit-test handler,
/// asks for the features it needs and emits a region into its buffer, and all
/// three are work an app pays on every frame. Without one the bench measured
/// controls with their pointer half removed.
///
/// `package`, not public: it is harness plumbing, not API.
package final class HeadlessInputChannels {
    private let keyEventDispatcher = KeyEventDispatcher()
    private let keyboardShortcuts = KeyboardShortcutRegistry()
    private let statusBar = StatusBarState()
    private let mouseEventDispatcher = MouseEventDispatcher()

    /// Creates four empty channels.
    package init() {}

    /// Wires the channels into `environment`.
    ///
    /// The status bar is the app's as well (`appStatusBar`), as the render loop
    /// publishes it: a `StatusBar()` drawn in a backdrop — whose isolation swaps
    /// `statusBar` for a throwaway — reads the app's line from it, so a bench
    /// draws the line the app draws there, not an empty one.
    package func install(into environment: inout EnvironmentValues) {
        environment.keyEventDispatcher = keyEventDispatcher
        environment.keyboardShortcutRegistry = keyboardShortcuts
        environment.statusBar = statusBar
        environment.appStatusBar = statusBar
        environment.mouseEventDispatcher = mouseEventDispatcher
    }

    /// Empties what the previous walk registered, as `RenderLoop` does before
    /// each walk of the scene.
    package func beginWalk() {
        keyEventDispatcher.clearHandlers()
        keyboardShortcuts.beginRenderPass()
        statusBar.beginSceneRender()
        mouseEventDispatcher.beginRenderPass()
    }

    /// Answers the frame's readers of `.global` and of names nothing declared,
    /// as the scene root does in `RenderLoop`, and draws the frame once more
    /// when one of them drew from a wrong answer — the root's correction.
    ///
    /// - Parameters:
    ///   - frame: The frame as rendered.
    ///   - width: The width it was rendered at.
    ///   - height: The height it was rendered at.
    ///   - stateStorage: The storage it rendered against, whose per-walk
    ///     counters a second walk restarts.
    ///   - redraw: Renders the frame again.
    /// - Returns: The frame to show.
    package func settleRootGeometry(
        _ frame: FrameBuffer, width: Int, height: Int, stateStorage: StateStorage?,
        redraw: () -> FrameBuffer
    ) -> FrameBuffer {
        let geometry = mouseEventDispatcher.geometry
        let size = CellSize(width: width, height: height)
        guard geometry.resolveRemaining(in: frame, size: size) else { return frame }
        geometry.noteCorrection(.root)
        beginWalk()
        stateStorage?.beginSceneRender()
        let redrawn = redraw()
        if geometry.resolveRemaining(in: redrawn, size: size) { geometry.noteResidual() }
        return redrawn
    }

    /// How often the frame's geometry owners have drawn their subtrees again,
    /// so far — the Stress `geometry` scenario's acceptance metric.
    package var geometryCorrections: GeometryCorrections {
        mouseEventDispatcher.geometry.corrections
    }

    /// Reports what the frame owes its geometry observers, as `RenderLoop`
    /// does once a frame is drawn (`GeometryCoordinator.endFrame`).
    ///
    /// - Parameters:
    ///   - frame: The frame as rendered.
    ///   - stateStorage: The storage the frame rendered against, which says
    ///     whether a view that drew nothing is still in the tree.
    package func endFrame(_ frame: FrameBuffer, stateStorage: StateStorage?) {
        mouseEventDispatcher.geometry.endFrame(frame: frame, retainedBy: stateStorage)
    }

    /// How many key handlers the last walk left registered.
    package var keyHandlerCount: Int { keyEventDispatcher.handlerCount }

    /// How many mouse handlers the last walk left registered.
    package var mouseHandlerCount: Int { mouseEventDispatcher.handlerCount }
}
