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

    /// Draws the frame, answers its readers of `.global` and of names nothing
    /// declared, as the scene root does in `RenderLoop`, and draws the frame
    /// once more when one of them drew from a wrong answer — the root's
    /// correction. What the views do waits until the drawing kept is known,
    /// as the root's does (``ProvisionalEffects``).
    ///
    /// - Parameters:
    ///   - width: The width the frame is rendered at.
    ///   - height: The height it is rendered at.
    ///   - stateStorage: The storage it renders against, whose per-walk
    ///     counters a second walk restarts, and whose stage holds the views'
    ///     effects.
    ///   - draw: Renders the frame.
    /// - Returns: The frame to show.
    package func drawSettlingRootGeometry(
        width: Int, height: Int, stateStorage: StateStorage?, draw: () -> FrameBuffer
    ) -> FrameBuffer {
        let effects = ProvisionalEffects(stateStorage: stateStorage)
        defer { effects.keep() }
        let frame = draw()
        let geometry = mouseEventDispatcher.geometry
        let size = CellSize(width: width, height: height)
        guard geometry.resolveRemaining(in: frame, size: size) else { return frame }
        geometry.noteCorrection(.root)
        effects.discard()
        beginWalk()
        stateStorage?.beginSceneRender()
        let redrawn = draw()
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

    /// Ends a context these channels were installed into, as an app ends its
    /// own on the way out (`TUIContext.reset()`): empties what its last walk
    /// registered with the channels, and its state storage, render cache and
    /// preference storage.
    ///
    /// Letting go of the context does not free them. Each keeps closures that
    /// captured a `RenderContext` — a `List`'s handler answers row heights
    /// from the frame's rows, each row's box holds the context it was built
    /// under, a memo's effect journal holds a `Button`'s registration — and a
    /// context's environment holds the storage and the cache themselves. So
    /// each is in a cycle with what it keeps, and a context dropped without
    /// this stayed alive, whole. An app has one context, which lives as long
    /// as it runs; the Stress bench's `--cold` makes one a frame, and kept
    /// every one of them.
    ///
    /// The channels first, as ``beginWalk()`` empties them. They outlive the
    /// context, and what its walk registered with them — a `List` row's
    /// hit-test handler holds the list's handler and the walk's
    /// `RenderContext` — keeps the context's storage and cache alive through
    /// them. Left to the next walk's ``beginWalk()``, a cold bench freed the
    /// last frame's render inside the next frame's timed region.
    ///
    /// - Parameter context: The context to end.
    @MainActor
    package func discard(_ context: RenderContext) {
        beginWalk()
        context.environment.stateStorage?.reset()
        context.environment.renderCache?.reset()
        context.environment.preferenceStorage?.reset()
    }

    /// How many key handlers the last walk left registered.
    package var keyHandlerCount: Int { keyEventDispatcher.handlerCount }

    /// How many mouse handlers the last walk left registered.
    package var mouseHandlerCount: Int { mouseEventDispatcher.handlerCount }
}
