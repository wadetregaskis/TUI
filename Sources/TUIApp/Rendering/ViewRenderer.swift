//  🖥️ TUI — A Terminal UI framework for Swift
//  ViewRenderer.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIChrome
import TUIFoundation

/// Convenience class for standalone one-off view rendering.
///
/// `ViewRenderer` wraps the free function ``renderToBuffer(_:context:)``
/// with terminal cursor positioning. It is a thin wrapper — the actual
/// rendering dispatch happens in `renderToBuffer`, not here.
///
/// This class is **not** part of the main render pipeline. The main
/// pipeline is:
///
/// ```
/// AppRunner → RenderLoop.render() → renderToBuffer() → FrameDiffWriter → Terminal
/// ```
///
/// `ViewRenderer` is used by the ``renderOnce(_:)`` convenience API
/// for simple CLI tools that don't need a full ``App``. It bypasses
/// `RenderLoop`, `FrameDiffWriter`, and diff-based rendering, but it
/// still has to provide the runtime services the render pass reads
/// (state storage, lifecycle, render cache, …) — so it builds a
/// private snapshot ``TUIContext``.
///
/// ## Snapshot semantics
///
/// A `renderOnce` render is a one-shot **snapshot of the initial
/// frame**. Its lifecycle manager runs with effects disabled, so
/// `onAppear` actions and `.task` work do **not** fire: there is no
/// run loop to observe their results and no teardown pass to balance
/// them, and a snapshot must not mutate shared state as a side effect.
/// The render cache is private to this renderer, so a snapshot never
/// disturbs the shared cache a live app may be using.
///
/// Once the frame is written, the renderer empties what the walk left in its
/// services — the `@State`, the render cache, the preferences, and what was
/// registered with the focus manager, the key and mouse dispatchers, the
/// shortcut registry and the drag session — because those registrations hold
/// closures over the walk's `RenderContext`, whose environment holds the
/// services themselves: left filled, they kept the renderer and its whole
/// render alive after it was let go of. That is not a teardown pass either.
/// No view's code runs in it: nothing disappears, and the control the
/// snapshot focused is not told its focus ended, so a `TextField` reports
/// `onEditingChanged(true)` and never `false`. What the context keeps beyond
/// that (`TUIContext.reset()` lists it), the images sent to the terminal
/// among it, is left as it is, and goes with the renderer.
///
/// What a snapshot does NOT skip is the root composite. `.offset`,
/// `.position`, `.popover`, `.sheet` and `.alert` leave their drawing in
/// `overlays` rather than in the lines, and `.opacity` leaves a blend still
/// to perform in `opacityRegions`; `flush` walks only `lines`, so both are
/// resolved first, by the same
/// ``FrameBuffer/compositingOverlays(maxWidth:maxHeight:palette:)`` the live
/// pipeline runs at the screen root. Without it a displaced view drew nothing
/// at all and a faded one drew at full strength. The palette that resolves
/// the fade is this renderer's own default: a snapshot has no scene, so there
/// is no `.palette(_:)` scene override to hoist.
@MainActor
final class ViewRenderer {
    /// The terminal to render to.
    ///
    /// Typed as ``TerminalProtocol`` rather than the concrete
    /// ``Terminal`` so tests can inject a capturing mock — the
    /// renderer only needs `getSize()`, `moveCursor(toRow:column:)`,
    /// and `write(_:)`.
    private let terminal: any TerminalProtocol

    /// The private snapshot context supplying runtime services. Internal, not
    /// private, so a test can watch it go.
    let context: TUIContext

    /// A focus manager for the snapshot (interactive views read it). Internal
    /// for the same test.
    let focusManager = FocusManager()

    /// The host's cursor-advance model.
    ///
    /// This path skips the diff, the reuse cache and the whole frame pipeline —
    /// it draws one buffer once — but it does not get to skip THIS. A terminal
    /// whose cursor advance disagrees with a glyph's painted width disagrees
    /// however the bytes were produced, so a snapshot containing `⚙️` on
    /// Terminal.app puts the rest of its line one cell to the left without it.
    /// See ``FrameDiffWriter/compensatingCursorAdvance(_:)``
    /// and `Documentation/Terminals/Terminal compatibility survey.md`.
    private let writer: FrameDiffWriter

    /// Creates a new ViewRenderer.
    ///
    /// - Parameters:
    ///   - terminal: The target terminal. No default: the console `Terminal`
    ///     is the app layer's, which ``renderOnce(content:)`` passes, and a
    ///     test passes a capturing one.
    ///   - writer: The advance model to emit through (default: the detected
    ///     host). Injectable for the same reason `terminal` is: `TerminalHost`
    ///     answers once, from the process environment, so a test cannot ask it
    ///     what a different terminal would receive.
    init(terminal: any TerminalProtocol, writer: FrameDiffWriter = FrameDiffWriter()) {
        self.terminal = terminal
        self.writer = writer
        self.context = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage(),
            renderCache: RenderCache(valueHashPlans: .tuikit())
        )
    }
}

// MARK: - Internal API

extension ViewRenderer {
    /// Renders a view to the terminal.
    ///
    /// Queries the terminal size, renders the view into a ``FrameBuffer``,
    /// and writes the result line-by-line to the terminal. Then empties what
    /// the walk left in the renderer's services, without running any view's
    /// code (see the type's documentation), so a second render on the same
    /// renderer starts from empty `@State` and an empty render cache, and
    /// nothing the walk registered keeps the renderer alive.
    ///
    /// - Parameters:
    ///   - view: The view to render.
    ///   - row: The starting row (1-based, default: 1).
    ///   - column: The starting column (1-based, default: 1).
    func render<V: View>(_ view: V, atRow row: Int = 1, column: Int = 1) {
        let size = terminal.getSize()

        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: context)
        environment.focusManager = focusManager

        // Initialise per-frame tracking the way the live pipeline does
        // before evaluating a frame, so @State hydration and the render
        // cache behave. No matching end-of-frame pass runs: a snapshot
        // has no removed views to fire `onDisappear`, and the context
        // is discarded afterwards.
        context.stateStorage.beginRenderPass()
        context.lifecycle.beginRenderPass()
        context.renderCache.beginRenderPass()
        // One wall-clock date for the snapshot's measure and render alike, as
        // the loop stamps one per frame: a timeline measured for one entry and
        // drawn for the next is laid out for the wrong text.
        context.renderCache.frameDate = FrameClock.nowDate

        let renderContext = RenderContext(
            availableWidth: size.width,
            availableHeight: size.height,
            environment: environment
        )
        // In the pass, as the run loop draws a frame: a `@State` made in it
        // notes it (`StateStorage.inRenderPass(_:)`).
        let buffer = context.stateStorage.inRenderPass { renderToBuffer(view, context: renderContext) }
        // Any image the view drew has to reach the terminal before the cells
        // that name it — the same ordering the run loop keeps at `beginFrame`,
        // and for the same reason: a placeholder pointing at an image the
        // terminal has not been given draws nothing at all. This context is
        // discarded afterwards, so the images it transmitted are never deleted;
        // a one-off render is a one-off, and there is no lifecycle here to hang
        // a release on.
        let graphics = context.terminalImageStore.takePending()
        if !graphics.isEmpty { terminal.write(graphics) }
        // The root composite, before the write. `.offset`/`.position`/
        // `.popover`/`.alert` put their drawing in `buffer.overlays` and
        // `.opacity` leaves a blend still to perform in `buffer.opacityRegions`,
        // and `flush` walks neither: a snapshot of `Text("A").offset(x: 2)`
        // wrote one empty row and no "A" at all, and one of
        // `Text("x").opacity(0.3)` wrote the unfaded cells. This is the call
        // `RenderLoop` makes at the screen root (`compositeOverlays`), and its
        // first act is that root's opacity resolve — so ONE call covers both
        // halves and leaves a second nothing to do: resolution CLEARS the
        // regions, so a separate `resolvingOpacity` would not double-fade, it
        // would simply be dead. (The live loop calls it twice for that reason.)
        //
        // Unconditional, unlike the live loop's `!overlays.isEmpty` guard,
        // because the opacity half has to run when there are no layers at all.
        // Free when there is neither payload: the opacity pass returns `self`
        // on an empty region list and the layer queue never iterates, so the
        // buffer comes back byte-identical.
        let composited = buffer.compositingOverlays(maxWidth: size.width, maxHeight: size.height, palette: environment.palette)
        flush(composited, atRow: row, column: column)
        // Then what the walk left is emptied, as `App.cleanup` empties its own
        // at quit: the focus manager, then the context, in that order. Letting
        // go of them is not enough. What the walk left in them holds closures
        // over its `RenderContext` — a `List`'s handler answers row heights
        // from the rows it drew, each row's box holds the context it was built
        // under, the mouse dispatcher holds the row's hit-test handler — and
        // that context's environment holds the state storage, the cache, the
        // focus manager and the dispatcher themselves. So each was in a cycle
        // with what it kept, and every snapshot of a list stayed alive, whole,
        // for the life of the process.
        //
        // The focus manager WITHOUT `clear()`'s first step, which tells the
        // focused control it lost the focus. At quit that is the focused
        // field's commit; here it ran the control's callbacks after the frame
        // was on the terminal — the field the snapshot auto-focused reported
        // `onEditingChanged(false)` — and a snapshot runs no view's code once
        // it has drawn.
        focusManager.clearWithoutNotifying()
        context.reset()
    }
}

// MARK: - Private Helpers

extension ViewRenderer {
    /// Flushes a FrameBuffer to the terminal at the specified position.
    fileprivate func flush(_ buffer: FrameBuffer, atRow row: Int, column: Int) {
        for (index, line) in buffer.lines.enumerated() {
            terminal.moveCursor(toRow: row + index, column: column)
            // Through the SAME two treatments the live writer's `buildLine`
            // applies at its write boundary: the row sanitiser (a tab or a
            // newline in user data would otherwise move the cursor here, as it
            // cannot in an `App`) and the host's cursor-advance compensation.
            // This is a second write boundary, and it used to skip the first.
            // And without a hairline's mark (`HairlineMarker`), which a list
            // makes on a host that draws hairlines: a one-off render places no
            // lines, so the mark only has to go.
            var sanitized = line.sanitizedForTerminalRow()
            if KittyGraphics.isHairlineSupported { sanitized = HairlineMarker.stripping(sanitized) }
            terminal.write(writer.compensatingCursorAdvance(sanitized))
            // Styled bytes this writer did not plan, so its belief about what
            // the terminal is wearing no longer holds — see
            // ``FrameDiffWriter/terminalStyle``.
            writer.forgetTerminalStyling()
        }
    }
}
