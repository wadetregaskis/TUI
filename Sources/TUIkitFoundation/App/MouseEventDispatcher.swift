//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MouseEventDispatcher.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitCore

// MARK: - Mouse Feature

/// A single mouse feature that view modifiers can ask for on a
/// per-frame basis (see `MouseEventDispatcher.requestFeature(_:)`).
public enum MouseFeature: Sendable {
    case clicks
    case scrolling
    case drag
    case motion
}

// MARK: - Mouse Event Dispatcher

/// Routes terminal mouse events to the view tree using hit-test
/// regions emitted by `.onMouseEvent` modifiers.
///
/// The dispatcher resets its state at the start of every render pass.
/// During render, modifiers register their handlers and the
/// `RenderLoop` collects the absolute-coordinate
/// ``HitTestRegion``s from the root buffer. When a mouse event arrives
/// the dispatcher looks up the topmost region containing the cursor's
/// position and forwards the event to its handler.
///
/// Drags are tracked too: the dispatcher remembers which handler
/// received the press for each button, and routes the subsequent
/// `.dragged` and `.released` events to that same handler regardless of
/// where the cursor ended up — exactly the way GUI toolkits treat a
/// drag once it has captured a control.
/// `@usableFromInline`: the type of an `@inlinable` environment accessor (module split step A3).
@usableFromInline
package final class MouseEventDispatcher: @unchecked Sendable {
    /// The app's drag-and-drop session, when one is wired (see
    /// ``TUIContext``). The dispatcher stamps it with every press / drag /
    /// release event in ABSOLUTE coordinates before routing — a drag-captured
    /// handler only ever sees region-relative coordinates, but drop targeting
    /// needs the on-screen cursor position.
    weak var dragAndDropSession: DragAndDropSession?

    /// The app's selection of what is on the screen (``ScreenSelection``), when
    /// one is wired: a drag that no control uses makes it, and any left press
    /// clears it.
    weak var screenSelection: ScreenSelection?

    /// The app's tooltips (``TooltipState``), when wired: told when the
    /// pointer moves to another cell, which is what ends a tooltip held while
    /// the status bar's own rows moved the page under a resting pointer.
    weak var tooltipState: TooltipState?

    /// Per-frame handlers keyed by ``HitTestRegion/HandlerID``.
    ///
    /// `RenderLoop.beginRenderPass()` clears the table at the start of
    /// every frame; modifiers register their handlers again as their
    /// content renders.
    private var handlers: [HitTestRegion.HandlerID: (MouseEvent) -> Bool] = [:]

    /// Tracks the in-progress press for each button: the handler that
    /// claimed the press, plus the offset of the region it claimed it
    /// from. The offset lets us keep delivering coordinates relative
    /// to the original region even when the cursor wanders elsewhere
    /// during the drag.
    struct PressCapture {
        /// The handler that claimed the press — captured directly, NOT by id.
        /// `pressedHandlers` spans frames (a press and its release can straddle
        /// one or more renders), and while an id now names the same control
        /// across them, the table of CLOSURES does not survive: every walk
        /// clears it and re-registers what renders. A control that stops
        /// rendering mid-gesture — the row of a menu the press closed — leaves
        /// its id resolving to nothing, and a render between press and release
        /// is routine, since a consumed press requests one. Holding the closure
        /// keeps the release/drag bound to the exact handler that took the
        /// press, which is the whole point of drag capture. (It was load-bearing
        /// against a sharper failure when ids were positional and a re-render
        /// renumbered every control: the first menu click always activated item
        /// 0.)
        let handler: (MouseEvent) -> Bool
        let regionOffsetX: Int
        let regionOffsetY: Int
    }

    /// The handler that most recently consumed a button-down event for
    /// each tracked button. Populated when a `.pressed` arrives, used
    /// to route subsequent `.dragged` / `.released` events for the
    /// same button to the original handler, and cleared on
    /// `.released`.
    var pressedHandlers: [MouseButton: PressCapture] = [:]

    /// The support in force at the END of the previous frame — what the
    /// terminal's reporting mode was actually set to. The mid-gesture
    /// downgrade in `setActiveSupport` compares frame-final against
    /// frame-final: the render pass transiently sets the scene BASE mid-frame
    /// (before per-frame feature requests are collected), and comparing
    /// against that would fire the unwind every frame a dialog elevates
    /// clicks above the base. And the mode a reshape asks whether motion is
    /// reported (`reconciled`), which runs mid-frame too: a lane it enters
    /// from nothing is left again only by a reported move.
    private var frameFinalSupport: MouseSupport = .disabled

    /// Set by the handler currently taking a `.pressed` event to say it wants
    /// no drag capture — see ``handOffGesture()``. Read (and cleared) around
    /// each handler call, so it can only ever speak for that one press.
    private var gestureHandedOff = false

    /// The list of hit-test regions in absolute screen coordinates for
    /// the current frame.
    ///
    /// Populated by ``RenderLoop`` from the root buffer's
    /// ``FrameBuffer/hitTestRegions`` after compositing. Cleared on
    /// `beginRenderPass`.
    private var regions: [HitTestRegion] = []

    /// Where handler ids come from: interned per `(identity, slot)` so a
    /// control keeps its own id while it renders, and minted fresh for a
    /// registration with no view identity behind it. See
    /// ``MouseHandlerIDTable``, whose file also holds the registration entry
    /// points a render walk uses.
    let handlerIDs = MouseHandlerIDTable()

    /// Where geometry markers' ids come from: interned exactly as handler ids
    /// are, from a mint that starts at the geometry bit so the two can never
    /// meet. See ``geometryMarkerID(in:)``.
    let geometryMarkerIDs = MouseHandlerIDTable(firstRaw: HitTestRegion.HandlerID.geometryMarkerBit)

    /// What the views that stamp geometry markers asked, and what their
    /// owners found — see ``GeometryCoordinator``. Here because the markers'
    /// ids are, and because a dispatcher is wired wherever a frame is drawn.
    package let geometry = GeometryCoordinator()

    /// One lane of the hover state machine: the region the pointer was last
    /// resolved against, and the closure still owed its exit across a reshape.
    ///
    /// There are two lanes, ``hover`` and ``observedHover``, and they run the
    /// same transitions independently — see ``registerHoverObserver(in:_:)``.
    private struct HoverSlot {
        /// The handler ID of the region the cursor was sitting on
        /// when the previous `.moved` event was processed, or `nil`
        /// if the cursor wasn't over any region this lane resolves. Used to
        /// synthesise `.entered` / `.exited` transitions when the
        /// cursor crosses region boundaries. Preserved across render passes,
        /// and an id is the control's own, so it still names the control the
        /// cursor was on however the tree around it has changed.
        var handlerID: HitTestRegion.HandlerID?

        /// The hovered REGION itself, kept beside the id: what the cursor rests
        /// on is a rectangle, and a control that MOVED under a still cursor has
        /// left it even though its id is unchanged. So "the same control" is
        /// asked of the region — its focusID when it has one, its rectangle
        /// otherwise. See ``reconcileHoverAfterReshape()``.
        var region: HitTestRegion?

        /// The hovered region's closure, retained across the handler-table
        /// rebuild: if the reshape puts a different region under the resting
        /// cursor, `.exited` must still reach the one that was left — by then
        /// its numeric id belongs to someone else, or to no one.
        var pendingExit: PendingHoverExit?

        /// The control a reshape took this lane off, leaving it on nothing:
        /// a later reshape that puts that control back under the resting
        /// cursor does not enter it again, until the cursor next reports
        /// motion (which re-resolves the lane, `dispatchMotion`). Any other
        /// control a reshape slides under the cursor is entered. `nil` while
        /// the lane hovers something, or rests on nothing because the cursor
        /// moved there.
        ///
        /// Without it, a hover whose change moves its own view out from under
        /// the cursor — `.onHover` showing a line of details above its row —
        /// flickered for ever: entered, moved away and exited, moved back and
        /// entered again, a frame each, and the app never idled. By the
        /// control's id, which is its own across frames (interned per view):
        /// the view comes back where it was, or near it.
        var leftByReshape: HitTestRegion.HandlerID?
    }

    /// The control under the pointer: the innermost region that is NOT a hover
    /// observer.
    private var hover = HoverSlot()

    /// The hover observer — `.onHover`, `help(_:)` — in front of that control,
    /// on a lane of its own so the control keeps its hover.
    private var observedHover = HoverSlot()

    /// The handlers registered as hover observers this frame, cleared with the
    /// handler table.
    private var hoverObserverIDs: Set<HitTestRegion.HandlerID> = []

    /// The handlers registered as taking no plain left press this frame
    /// (``registerPassive(in:_:)``), cleared with the handler table.
    private var passiveIDs: Set<HitTestRegion.HandlerID> = []

    /// The handlers the app wrote, registered this frame
    /// (``registerApplicationHandler(in:_:)``), cleared with the handler
    /// table.
    private var applicationHandlerIDs: Set<HitTestRegion.HandlerID> = []

    /// The handlers registered to hear the wheel alone this frame
    /// (``registerWheelHandler(in:_:)``), cleared with the handler table.
    private var wheelHandlerIDs: Set<HitTestRegion.HandlerID> = []

    /// Where the cursor last reported motion, so a reshaped tree can be
    /// re-resolved against a RESTING cursor, and a report from the cell it
    /// was already on told from a move.
    private var lastMotionPosition: (x: Int, y: Int)?

    /// Where the pointer rests while that is known: the cell of the last
    /// report of its motion — a move, or a drag's, which arrives as
    /// `.dragged` and never as `.moved` — or `nil` from when the terminal may
    /// have stopped reporting where it goes until it next does.
    ///
    /// Not a press's cell, a release's or a wheel tick's. While motion is
    /// reported the terminal reports the move to that cell first, so they add
    /// nothing; and a press reported with no move before it — a script's
    /// right-click — made its cell where the pointer rests for the reshape the
    /// press itself caused, which entered the row of the context menu it
    /// opened under the pointer, a pointer-opened menu with its first item
    /// highlighted (the Stress menus session).
    ///
    /// Forgotten when the terminal's reporting stops covering motion (a
    /// frame-final support without it, ``setActiveSupport(_:isFrameFinal:)``)
    /// and when it stops reporting the pointer at all (a suspend,
    /// ``forgetRestingPointer()``): the pointer can go anywhere unheard after
    /// either, and ``lastMotionPosition`` goes on naming the cell it left.
    /// A reshape enters only what it slides under a position known here
    /// (``reconciled(_:to:at:entering:)``). Found by the BUGS13 lane's review:
    /// once a lane resting on nothing entered what a reshape put under the
    /// pointer in an app that declares no motion of its own, a page that asks
    /// none, a Ctrl-Z, or a drag reported as `.dragged` left the last `.moved`
    /// behind, and a later reshape entered the view it slid under that cell
    /// — a help shown for a view the pointer was not on.
    private var restingPosition: (x: Int, y: Int)?

    /// Where the pointer rests, in the screen's coordinates, while that is
    /// known: see ``restingPosition``. `nil` before it has reported any.
    package var restingPointer: (x: Int, y: Int)? { restingPosition }

    /// A control that was hovered and whose `.exited` still has to reach it.
    ///
    /// A named struct rather than the labelled tuple it used to be, and the
    /// reason is not taste: as a tuple inside an `Optional` it crashes
    /// `swift-frontend` on the Swift 6.5-dev snapshot of 2026-08-30 — an
    /// assertion in the `LoadableByAddress` SIL pass, on this property's
    /// setter, which stops the whole package compiling on that toolchain. A
    /// struct compiles. It reads no worse either way.
    ///
    /// `Tools/CompilerBugs/LoadableByAddressAssertion` is the bug in twelve
    /// lines, with the near-misses beside it — including this exact swap, which
    /// is the last row of its matrix.
    private struct PendingHoverExit {
        let region: HitTestRegion
        let handler: (MouseEvent) -> Bool
    }

    /// Per-frame feature requests posted by view modifiers that
    /// genuinely need a higher mouse-tracking level than the base
    /// configuration provides (e.g. an ``.onHover`` modifier asks
    /// for motion). Cleared every `beginRenderPass`; the AppRunner
    /// merges this with the base ``MouseSupport`` configuration to
    /// decide which terminal tracking mode to apply.
    private var requestedFeatures: MouseSupport = .disabled

    /// An optional view-level override of the entire ``MouseSupport``
    /// configuration. Set via the ``View/mouseSupport(_:)`` modifier
    /// during a render pass; replaces (rather than unions) the
    /// scene-level base config for that frame. Cleared every
    /// `beginRenderPass`. The latest setter wins — innermost
    /// `.mouseSupport(...)` in the view tree takes effect.
    private var configOverride: MouseSupport?

    /// The effective ``MouseSupport`` configuration in force for the
    /// dispatching of incoming events. Set by the AppRunner each
    /// frame before processing input. Determines which kinds of
    /// events the dispatcher will forward to handlers — for example
    /// if `clicks` is false, click events arriving from the
    /// terminal are silently dropped.
    private var activeSupport: MouseSupport = .standard

    /// A recorded button press, used to synthesise ``MouseEvent/clickCount``
    /// for the matching release and to carry the press's modifier state onto
    /// it (some terminals drop the SGR modifier bits on the release report).
    private struct LastClick {
        var button: MouseButton
        var x: Int
        var y: Int
        var timeNanos: UInt64
        var count: Int
        var shift: Bool
        var ctrl: Bool
        var meta: Bool
        /// Whether the press is still awaiting its matching release. Only an
        /// in-flight press donates its count/modifiers to a release — a stray
        /// release arriving long after (terminal quirk, or a press filtered by
        /// a mid-click config change) must not inherit stale state and read as
        /// a phantom modifier-click.
        var inFlight = true
    }

    /// The most recent button press. A press within ``multiClickWindowNanos``
    /// of the previous one, on the same button and (near) the same cell,
    /// increments the count.
    private var lastClick: LastClick?

    /// The cell the button currently down was pressed on, or `nil` when no
    /// press is in flight. Only the ORIGIN is kept: what a held gesture needs
    /// to know is whether it has moved at all, not how far.
    private var pressOrigin: (x: Int, y: Int)?

    /// Whether the cursor has left the cell it was pressed on, for the gesture
    /// currently in flight. See ``endsHeldGesture(_:)``.
    private var pointerMovedSincePress = false

    /// The region the held gesture's last drag was hit-tested to, while a
    /// press handed back to live hit-testing (``handOffGesture()``) is held —
    /// what ``redeliverHeldDrag()`` compares a reshaped frame against.
    private var heldDragTarget: HitTestRegion.HandlerID?

    /// The pop-up menu the press in flight opened, or `nil` when it opened
    /// none — see ``pressOpenedPopup(_:)``. Unlike ``gestureHandedOff`` this
    /// stands for the whole gesture, not for one handler call, because the
    /// question it answers is asked by a *different* handler on the release.
    private var pressPopup: OpenedPopup?

    /// Whether a render pass has begun since the press in flight opened its
    /// pop-up (``pressOpenedPopup(_:)``) — not since the press: the gesture
    /// arena can hold a press back over frames and hand it to the control
    /// that opens the pop-up only partway through its drag.
    private var renderedSincePopupOpened = false

    /// Buttons whose press was handed back to live hit-testing rather than
    /// captured — see ``handOffGesture()``.
    ///
    /// These are the only presses whose release legitimately arrives with no
    /// capture to route it, and the release has somewhere real to go: the menu
    /// the press opened. Everything else that reaches a release with no capture
    /// is a release whose press went somewhere this control never heard about.
    private var handedOffPresses: Set<MouseButton> = []

    /// The gestures attached this frame (``View/gesture(_:including:)`` and
    /// its siblings), by the handler id of the region each filed. Cleared with
    /// the handler table. See ``GestureArena``.
    var gestureRoles: [HitTestRegion.HandlerID: GestureRole] = [:]

    /// The gestures a disabled view kept from an earlier frame, by
    /// participant: filed by the walk so an arena can give them up at the
    /// disable (``fileDisabledGesture(_:in:)``, decisions B-F2-2). Cleared
    /// with the handler table.
    var disabledGestureParticipants: Set<ObjectIdentifier> = []

    /// The regions that take a left press only for its click, by handler id —
    /// see ``PressRole``. Cleared with the handler table, refiled by every walk
    /// (and every memo replay) that registers them.
    var pressRoles: [HitTestRegion.HandlerID: PressRole] = [:]

    /// The ``View/textSelection(_:)`` scopes on screen, by the handler id of the
    /// region each filed: `true` enabled, `false` disabled. Cleared with the
    /// handler table.
    private(set) var selectionScopes: [HitTestRegion.HandlerID: Bool] = [:]

    /// Whether an enabled ``View/textSelection(_:)`` scope has been filed this
    /// walk: what a `List` or a `Table` asks, after drawing its rows, to learn
    /// whether a row's own text is selectable (`Text(name).textSelection(.enabled)`
    /// in a row) — the rows' environment never reaches the list. One flag,
    /// so a list in an app with no enabled scope pays one read.
    package var hasEnabledSelectionScope: Bool { enabledSelectionScopeCount > 0 }

    /// How many enabled ``View/textSelection(_:)`` scopes have been filed this
    /// walk — read before and after a `Table` draws its cells, to learn whether
    /// they filed any.
    package var enabledSelectionScopeCount: Int { _enabledSelectionScopeCount }

    /// ``enabledSelectionScopeCount``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _enabledSelectionScopeCount = 0

    /// Files a scope's answer for the region whose handler `id` names: the
    /// registration's, and its replay's from a memo's journal.
    func fileSelectionScope(_ allowsSelection: Bool, for id: HitTestRegion.HandlerID) {
        selectionScopes[id] = allowsSelection
        if allowsSelection { _enabledSelectionScopeCount += 1 }
    }

    /// The gestures contending for the left button, an arena per press,
    /// oldest first: built at a press that lands on a gesture, kept until
    /// every one of them has decided — which can be after the release, for a
    /// tap waiting on its next click, and after later presses, which do not
    /// give a waiting gesture up (``GestureArena``). The last is the current
    /// press's while its button is down.
    var gestureArenas: [GestureArena] = []

    /// Whether a walk has filed gestures since the arenas last asked which
    /// of theirs the frame on screen still files: set as a walk begins, and
    /// cleared by the first arena input after it, so the question is asked
    /// once per walk, and only while an arena exists.
    var gestureFilingsUnread = false

    /// The maximum gap between successive clicks for them to count as one
    /// multi-click sequence (400 ms — a common desktop double-click threshold).
    private static let multiClickWindowNanos: UInt64 = 400_000_000

    /// Monotonic time source (nanoseconds): the clock an event's arrival is
    /// read on, both for a press's place in a multi-click sequence and for the
    /// hover that starts a tooltip's delay (`HelpModifier`). Defaults to the
    /// same clock the run loop uses; injectable for tests, and a `HeadlessApp`
    /// runs it on its caller's time.
    package var nowNanos: () -> UInt64 { get { _nowNanos } set { _nowNanos = newValue } }

    /// ``nowNanos``'s storage: private, under the `package` accessor
    /// (CONTRIBUTING.md, "Crossing a module boundary").
    private var _nowNanos: () -> UInt64 = { MonotonicClock.nowNanoseconds }

    init() {}
}

// MARK: - Internal API

extension MouseEventDispatcher {
    /// Resets the dispatcher's per-frame state.
    ///
    /// Called by ``RenderLoop`` at the start of every render pass. The
    /// drag-capture map (`pressedHandlers`) is intentionally *not*
    /// cleared here — captures span multiple frames, ended only by the
    /// matching `.released`.
    package func beginRenderPass() {
        // Retain each lane's hovered closure before the table dies — see
        // `HoverSlot.pendingExit`.
        if let exit = retainedExit(for: hover) { hover.pendingExit = exit }
        if let exit = retainedExit(for: observedHover) { observedHover.pendingExit = exit }
        renderedSincePopupOpened = true
        handlers.removeAll(keepingCapacity: true)
        hoverObserverIDs.removeAll(keepingCapacity: true)
        passiveIDs.removeAll(keepingCapacity: true)
        applicationHandlerIDs.removeAll(keepingCapacity: true)
        wheelHandlerIDs.removeAll(keepingCapacity: true)
        gestureRoles.removeAll(keepingCapacity: true)
        disabledGestureParticipants.removeAll(keepingCapacity: true)
        pressRoles.removeAll(keepingCapacity: true)
        selectionScopes.removeAll(keepingCapacity: true)
        _enabledSelectionScopeCount = 0
        gestureFilingsUnread = true
        regions.removeAll(keepingCapacity: true)
        // The interned ids survive this: only the per-identity slot counters
        // restart, because this runs once per WALK of the scene.
        handlerIDs.beginWalk()
        geometryMarkerIDs.beginWalk()
        geometry.beginWalk()
        requestedFeatures = .disabled
        configOverride = nil
    }

    /// Records that the rendering view tree wants `feature` reported
    /// for the current frame, on top of whatever the base scene-level
    /// ``MouseSupport`` configuration provides.
    ///
    /// Typical caller: an `.onHover` modifier asks for motion so it
    /// can highlight while the cursor is over its content. The
    /// modifier calls this every frame the view is rendered; the
    /// AppRunner takes the union with the base config when deciding
    /// which terminal tracking mode to apply.
    ///
    /// A render walk asks through ``requestFeature(_:in:)``, which also records
    /// the request for the memo that may serve the subtree; this bare form is
    /// what both that and a replay file through.
    func requestFeature(_ feature: MouseFeature) {
        switch feature {
        case .clicks: requestedFeatures.clicks = true
        case .scrolling: requestedFeatures.scrolling = true
        case .drag: requestedFeatures.drag = true
        case .motion: requestedFeatures.motion = true
        }
    }

    /// Asks for `feature` on behalf of the control `context` is rendering.
    ///
    /// The request is per-frame state exactly as the handler table is — emptied
    /// before every walk, refilled by whatever renders — so a control served
    /// from a value memo would stop asking. A page whose only control that
    /// lifts under the pointer is memoized would then be told nothing about
    /// where the pointer is, and its hover would die on the first frame the
    /// cache answered. So this declares a replayable effect and records the
    /// request beside the handler registration it accompanies.
    ///
    /// Required of every render-walk caller rather than defaulted, so the
    /// compiler asks the question of the next control somebody writes: the
    /// silent version of this is a control that stops hearing the pointer on
    /// the frames it is served.
    @MainActor
    package func requestFeature(_ feature: MouseFeature, in context: RenderContext) {
        requestFeature(feature)
        guard !context.isMeasuring else { return }
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        journal.append(
            EffectJournal.Entry(
                kind: MouseHandlerRegistrar.featureKind,
                channelToken: context.environment.keyChannelToken
            ) { replay in
                MouseHandlerRegistrar.requestFeature(feature, context: replay)
            })
    }

    /// Returns the effective ``MouseSupport`` for the current frame.
    ///
    /// Resolution order:
    /// 1. If a view-level override was posted this frame (via
    ///    ``setConfigOverride(_:)``), it replaces the scene base.
    /// 2. Otherwise, the scene base is used.
    /// 3. Either way, per-frame feature requests are unioned on top,
    ///    so a modifier that needs `motion` always gets it
    ///    regardless of which level set the base.
    package func effectiveSupport(baseConfig: MouseSupport) -> MouseSupport {
        let base = configOverride ?? baseConfig
        return base.union(with: requestedFeatures)
    }

    /// Replaces the per-frame ``MouseSupport`` configuration with
    /// `support`. Called by the ``View/mouseSupport(_:)`` view
    /// modifier during render. Last setter wins; cleared at the
    /// start of every render pass.
    func setConfigOverride(_ support: MouseSupport) {
        configOverride = support
    }

    /// Updates the effective configuration used to filter incoming events.
    ///
    /// Two callers: the render pass sets the scene BASE mid-frame (so events
    /// queued from the previous frame filter against the right floor), and
    /// the AppRunner sets the frame-final effective (base ∪ per-frame feature
    /// requests) after the render — `isFrameFinal: true`, the value the
    /// terminal's reporting mode is actually switched to.
    package func setActiveSupport(_ support: MouseSupport, isFrameFinal: Bool = false) {
        // A frame-final downgrade below clicks turns the terminal's button
        // reporting off — mid-gesture (a page with `.mouseSupport(.disabled)`
        // reached by keyboard while a button is held), the release that would
        // unwind the gesture will never arrive. Without this the press
        // captures stayed stranded forever — routing every later event for
        // that button to a dead frame's closure once reporting came back —
        // and an armed drag auto-scroll kept scrolling a list under a button
        // nobody was holding. There is no real release to deliver, so cancel
        // what is in flight and forget the captures.
        //
        // Frame-final ONLY: the mid-frame base set is a filtering floor, not
        // a terminal mode change — treating it as a downgrade cancelled the
        // gesture every frame whenever a dialog's per-frame request elevated
        // clicks above a click-less scene base (base → effective → base…).
        if isFrameFinal {
            if frameFinalSupport.clicks, !support.clicks {
                dragAndDropSession?.cancelForLostMouseReporting()
                pressedHandlers.removeAll()
                handedOffPresses.removeAll()
            }
            // Unreported from here, the pointer's moves leave its last report
            // behind (`restingPosition`).
            if !support.motion { restingPosition = nil }
            frameFinalSupport = support
        }
        activeSupport = support
    }

    /// Forgets where the pointer rests (``restingPosition``): the terminal has
    /// stopped reporting it. Called by the run loop as it hands the terminal
    /// back for a Ctrl-Z suspend, with the mouse reporting turned off, so the
    /// first frames after the resume enter nothing at the cell the pointer
    /// was on before it.
    package func forgetRestingPointer() {
        restingPosition = nil
    }

    /// Returns whether an event of the given phase should be
    /// forwarded to handlers, given the currently active
    /// ``MouseSupport`` configuration.
    private func eventIsAllowed(_ event: MouseEvent) -> Bool {
        switch event.phase {
        case .scrolled: return activeSupport.scrolling
        case .pressed, .released: return activeSupport.clicks
        case .dragged: return activeSupport.drag
        case .moved: return activeSupport.motion
        case .entered, .exited:
            // Synthetic phases — generated internally by the
            // dispatcher, never coming from the terminal. They
            // ride alongside the underlying `.moved` event's
            // permission.
            return activeSupport.motion
        }
    }

    /// Records the hit-test regions extracted from the root buffer
    /// after compositing.
    ///
    /// The regions arrive in registration order (outer-most first).
    /// The dispatcher reverses that during dispatch so the innermost
    /// matching handler wins — same intuition as a tap dispatched in a
    /// SwiftUI / AppKit view tree.
    ///
    /// - Returns: Whether a held drag was delivered again
    ///   (``redeliverHeldDrag()``), whose effect the next frame has to draw.
    @discardableResult
    package func setRegions(_ regions: [HitTestRegion]) -> Bool {
        self.regions = regions
        reconcileHoverAfterReshape()
        return redeliverHeldDrag()
    }

    /// Hands a held gesture's drag again to a region the reshape put under
    /// the pointer.
    ///
    /// A menu row is lit by the held pointer's drags (a terminal reports a
    /// held move as a drag, never as motion, so the hover lanes above never
    /// see it), and a drag arrives only when the pointer moves. The keyboard
    /// can move the rows without it: Home, End or a Page key scrolls a menu
    /// still held open, and the pointer is then on another option — the one
    /// the release will choose — while the highlight stayed where the key put
    /// it. The wheel re-lights the row itself, from inside the menu; a key
    /// reaches the menu before the rows move, so it falls to here.
    ///
    /// Only for a press handed back to live hit-testing, the menus' gestures:
    /// a captured press hears every drag at its own handler wherever the
    /// pointer is, and nothing slides under it. And only once that gesture
    /// has dragged somewhere (``heldDragTarget``), and only when the region
    /// now under the pointer is another control — a menu's rows are filed per
    /// OPTION, so a row scrolled into the pointer's cell is one — so a frame
    /// that moved nothing delivers nothing, and asks for no frame after it.
    ///
    /// A press that opened a menu and has not moved since has dragged nowhere,
    /// and its pointer rests on whatever row the menu drew under it. That row
    /// is taken as where it is — a baseline, delivered nothing — on the first
    /// frame the menu is on screen, so a key that then scrolls another row
    /// under the unmoved pointer lights that one, as it does for a pointer that
    /// had dragged. (Not from the press itself: the menu arriving under the
    /// pointer would then count as a row sliding under it, and a plain click
    /// would light, and its release choose, whatever row it opened under.)
    private func redeliverHeldDrag() -> Bool {
        // Where the pointer rests, or — a press not moved since, in a terminal
        // that reports no plain motion — where it pressed. Only for this: a
        // press counted as where the pointer rests for the hover too would
        // light the row a context menu opened under it, which a menu the
        // pointer opened must not do until the pointer moves.
        guard let position = restingPosition ?? (pointerMovedSincePress ? nil : pressOrigin),
            let button = handedOffPresses.first(where: { pressedHandlers[$0] == nil })
        else { return false }
        let matching = matchingRegions(at: position.x, y: position.y)
        guard let target = heldDragTarget else {
            if pressPopup != nil, pressPopupIsOnScreen { heldDragTarget = matching.first?.handlerID }
            return false
        }
        guard let under = matching.first, under.handlerID != target else { return false }
        let drag = MouseEvent(button: button, phase: .dragged, x: position.x, y: position.y)
        heldDragTarget = under.handlerID
        for region in matching where offer(drag, to: region) != .declined {
            heldDragTarget = region.handlerID
            return true
        }
        return false
    }

    /// Re-resolves the hover after the tree reshapes under a resting cursor.
    ///
    /// A reshape can slide a different control under a cursor that has not
    /// moved, and the lane would go on believing it hovers what it hovered: the
    /// same-region branch of `dispatchMotion` synthesises nothing, so hover
    /// strands on the control the cursor left (its box stuck lit) and never
    /// lights the one that arrived. Ids being positional made that the COMMON
    /// case, since the newcomer usually inherited the old number outright; they
    /// are interned per control now, and the re-resolve below is still what
    /// answers a control moving. The id is remapped here by the
    /// region's own identity — focusID when it has one, rectangle otherwise —
    /// and when a genuinely different control (or none) sits under the
    /// cursor, `.exited` goes to the RETAINED closure of the one that was
    /// left and `.entered` to the newcomer. Each lane is re-resolved against
    /// its own region — see ``resolveHover(at:y:)``.
    ///
    /// Re-resolved where the pointer is known to rest (``restingPosition``),
    /// and only there does anything hear `.entered`. Where that is not known
    /// — motion went unreported since — the lanes are re-resolved against the
    /// last move, as they always were, for the exits they owe, and enter
    /// nothing: the pointer may be anywhere.
    private func reconcileHoverAfterReshape() {
        guard let position = restingPosition ?? lastMotionPosition else {
            hover.pendingExit = nil
            observedHover.pendingExit = nil
            return
        }
        let entering = restingPosition != nil
        let resolved = resolveHover(at: position.x, y: position.y)
        hover = reconciled(hover, to: resolved.target, at: position, entering: entering)
        observedHover = reconciled(observedHover, to: resolved.observer, at: position, entering: entering)
    }

    /// One lane of ``reconcileHoverAfterReshape()``: `slot` re-resolved against
    /// `current`, the region its lane finds under the resting cursor now.
    ///
    /// A lane resting on nothing is re-resolved too: a control the reshape put
    /// under the cursor is entered, as a move onto it would enter it. Only a
    /// lane that hovered something used to be, so a view a reshape slid under
    /// a cursor resting on blank space heard nothing until the cursor next
    /// moved — its `.onHover` unlit, its help never starting its delay
    /// (decisions-HELP A-HELP-1, "Left open"). Only at a position known to
    /// be where the pointer rests (`entering`), and not while motion is not
    /// reported, when the control it enters would be left only by a move
    /// nobody hears: asked of ``frameFinalSupport``, the mode the terminal
    /// reports under since the last frame, not of ``activeSupport``, which
    /// the walk reset to the scene's base mid-frame — without motion unless
    /// the scene declares it, though an `.onHover` asks for it every frame.
    /// Entered once: the lane holds the control from then on,
    /// and the next reshape finds the same one. Not the control a reshape
    /// took the lane off, until the cursor moves (``HoverSlot/leftByReshape``).
    ///
    /// A lane that hovered something enters the newcomer under the pointer
    /// only at a known position too (`entering`); it is exited as before.
    private func reconciled(
        _ slot: HoverSlot, to current: HitTestRegion?, at position: (x: Int, y: Int), entering: Bool
    ) -> HoverSlot {
        guard slot.region != nil || slot.pendingExit != nil else {
            guard let current, entering, frameFinalSupport.motion, current.handlerID != slot.leftByReshape
            else { return slot }
            return entered(current, at: position)
        }
        let previous = slot.pendingExit?.region ?? slot.region
        if let current, isSameControl(previous, current) {
            return HoverSlot(handlerID: current.handlerID, region: current, pendingExit: nil)
        }
        if let pending = slot.pendingExit {
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: position.x - pending.region.localOriginX,
                y: position.y - pending.region.localOriginY)
            _ = pending.handler(exit)
        } else if let oldID = slot.handlerID, let oldHandler = handlers[oldID],
            let oldRegion = slot.region
        {
            // Regions replaced within one frame (no beginRenderPass between):
            // the old handler is still registered, and the trailing exit is
            // its due — this is the documented same-frame window.
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: position.x - oldRegion.localOriginX,
                y: position.y - oldRegion.localOriginY)
            _ = oldHandler(exit)
        }
        guard let current, entering else { return HoverSlot(leftByReshape: previous?.handlerID) }
        return entered(current, at: position)
    }

    /// A lane on `region`, its handler told the resting cursor at `position`
    /// has entered it.
    private func entered(_ region: HitTestRegion, at position: (x: Int, y: Int)) -> HoverSlot {
        if let handler = handlers[region.handlerID] {
            let enter = MouseEvent(
                button: .none, phase: .entered,
                x: position.x - region.localOriginX,
                y: position.y - region.localOriginY)
            _ = handler(enter)
        }
        return HoverSlot(handlerID: region.handlerID, region: region, pendingExit: nil)
    }

    /// The closure a lane's hovered region still has in this frame's table,
    /// kept for the exit a reshape may owe it — `nil` when the lane hovers
    /// nothing the table still holds.
    private func retainedExit(for slot: HoverSlot) -> PendingHoverExit? {
        guard let id = slot.handlerID, let handler = handlers[id], let region = slot.region
        else { return nil }
        return PendingHoverExit(region: region, handler: handler)
    }

    /// Whether two regions are the same CONTROL across a reshape: their
    /// focusIDs when both have one, their rectangles otherwise.
    private func isSameControl(_ a: HitTestRegion?, _ b: HitTestRegion) -> Bool {
        guard let a else { return false }
        if let fa = a.focusID, let fb = b.focusID { return fa == fb }
        return a.offsetX == b.offsetX && a.offsetY == b.offsetY
            && a.width == b.width && a.height == b.height
    }

    /// Registers `handler` under a fresh id that names no control.
    ///
    /// The mint for a registration with no view identity to intern against: a
    /// test driving the dispatcher directly. Everything a render walk registers
    /// goes through ``register(in:_:)`` instead, so that its id is the
    /// control's own rather than its position in the walk.
    func register(_ handler: @escaping (MouseEvent) -> Bool) -> HitTestRegion.HandlerID {
        register(id: handlerIDs.freshID(), handler)
    }

    /// Files `handler` under `id`: the one write of the handler table, so the
    /// interned and the fresh paths cannot drift apart.
    func register(
        id: HitTestRegion.HandlerID, _ handler: @escaping (MouseEvent) -> Bool
    ) -> HitTestRegion.HandlerID {
        handlers[id] = handler
        return id
    }

    /// Records that `id`'s handler watches the pointer rather than being the
    /// control under it — see ``registerHoverObserver(in:_:)``.
    func noteHoverObserver(_ id: HitTestRegion.HandlerID) {
        hoverObserverIDs.insert(id)
    }

    /// Records that `id`'s handler never takes a plain left press — see
    /// ``registerPassive(in:_:)``.
    func notePassive(_ id: HitTestRegion.HandlerID) {
        passiveIDs.insert(id)
    }

    /// Records that `id`'s handler is the app's own closure — see
    /// ``registerApplicationHandler(in:_:)``.
    func noteApplicationHandler(_ id: HitTestRegion.HandlerID) {
        applicationHandlerIDs.insert(id)
    }

    /// Whether the region `id` names is the app's own closure, whose answer
    /// to a plain left press TUIkit learns only by offering it one
    /// (``registerApplicationHandler(in:_:)``).
    func isApplicationHandler(_ id: HitTestRegion.HandlerID) -> Bool {
        applicationHandlerIDs.contains(id)
    }

    /// Whether the region `id` names is known to take no plain left press:
    /// a hover observer (a ``View/textSelection(_:)`` scope, `.onHover`,
    /// `help(_:)`, a gesture's region, which hears the pointer through its
    /// arena), a passive region (``registerPassive(in:_:)``), or one with no
    /// handler. Anything else may be a control, and is taken for one — but
    /// the app's own closure (``isApplicationHandler(_:)``), which can be
    /// asked only by being offered the press.
    func takesNoPlainLeftPress(_ id: HitTestRegion.HandlerID) -> Bool {
        handlers[id] == nil || hoverObserverIDs.contains(id) || passiveIDs.contains(id)
    }

    /// Records that `id`'s handler hears the wheel and nothing else — see
    /// ``registerWheelHandler(in:_:)``.
    func noteWheelHandler(_ id: HitTestRegion.HandlerID) {
        wheelHandlerIDs.insert(id)
    }

    /// How many handlers this walk has registered so far.
    ///
    /// For the headless bench (`HeadlessInputChannels`), which otherwise has no
    /// way to see whether the tree it rendered registered anything at all — the
    /// failure mode being a bench that measures controls with their pointer half
    /// missing and says nothing about it.
    var handlerCount: Int { handlers.count }

    /// The handler registered under `id` this frame, if any.
    ///
    /// Lets a wrapping modifier forward events to its content's handlers —
    /// ``DraggableModifier`` resolves its content's regions to closures at
    /// render time (an id outlives the walk but its entry in this table does
    /// not, and a control that stops rendering leaves nothing to look up — the
    /// same reasoning as `PressCapture`) so a click or hover on the draggable
    /// surface can reach the interactive children beneath it.
    func handler(for id: HitTestRegion.HandlerID) -> ((MouseEvent) -> Bool)? {
        handlers[id]
    }

    /// Called by a handler *while it is consuming a press* to give the rest of
    /// the gesture away: the `.dragged` / `.released` events that follow are
    /// hit-tested live, against whatever is on screen by then, instead of being
    /// routed back here by drag capture.
    ///
    /// This is how a pop-up button tracks like a Mac menu. The press opens the
    /// menu, and from that moment the gesture belongs to the MENU — dragging
    /// highlights the row under the pointer and releasing over one chooses it.
    /// Capture is exactly wrong for that: it would send every later event back
    /// to the button, which is no longer the control the user is pointing at.
    ///
    /// The ordinary press keeps its capture, and should: it is what lets you
    /// press a button, slide off it, and release to cancel.
    ///
    /// A press that hands off says too that it opened a pop-up
    /// (``pressOpenedPopup(_:)``), and until a render pass has begun since
    /// then, or once its opener says it is closed, there is nothing of it on
    /// screen to hit-test against: the dispatcher spends those drags and that
    /// release itself.
    package func handOffGesture() {
        gestureHandedOff = true
    }

    /// A pop-up a press opened, as the dispatcher holds it for the rest of
    /// that press's gesture — see ``pressOpenedPopup(_:)``.
    ///
    /// A class, not a struct of its two closures, for the menu trigger that
    /// carries one (``Button/menuTrigger(_:)``): every `Button` stores the
    /// optional, and an optional reference is one word, `nil` for a plain
    /// button and read by the measure memo's value hash as plain bytes — where
    /// the closures' optional was four words and a typed step in every
    /// button's hash. The pop-up states that hand one out build it once
    /// (``MenuPopupState/openedPopup``).
    package final class OpenedPopup {
        /// Whether the pop-up is still open — which the dispatcher takes to
        /// mean drawn, once a render pass has begun since it opened, so an
        /// opener must never say open while it draws nothing (a `Picker` with
        /// no options closes itself on its frame). One that closed — a row menu
        /// that built nothing does on the frame after its press, Escape closes
        /// any with the button still held — is not on screen to take the rest
        /// of the gesture, though a frame has gone by.
        let isOpen: () -> Bool

        /// Closes the pop-up, without choosing anything. Idempotent.
        let close: () -> Void

        package init(isOpen: @escaping () -> Bool, close: @escaping () -> Void) {
            self.isOpen = isOpen
            self.close = close
        }
    }

    /// Called by a handler *while it is consuming a press* to say that press
    /// OPENED a pop-up menu, so the release ending the same click is already
    /// spoken for. See ``endsPopupOpeningClick(_:)``.
    ///
    /// Until a render pass has begun since this call, and once the pop-up's
    /// `isOpen` says it is closed, the dispatcher spends the drags and the
    /// release of the gesture itself (``routeAgainstItsPress(_:)``):
    /// hit-tested live, they would land on whatever lies where the pop-up is
    /// not — on a control that never saw a press. Since this call, not since
    /// the press: a press the gesture arena held back (a tap ranked ahead of
    /// the control) reaches its opener only when a drag fails the tap, frames
    /// after it went down.
    ///
    /// - Parameter popup: The pop-up: whether it is open, and how to close it
    ///   if the gesture ends in a held release (``endsHeldGesture(_:)``)
    ///   while it is not on screen. Drawn, a pop-up closes on such a release
    ///   itself, wherever it lands: the dismiss backdrop closes it, its chrome
    ///   does, and a row it lands on runs and closes it. Undrawn — the press
    ///   and its release came in one input batch — the dispatcher spends the
    ///   release and closes it, without choosing anything: the user let go
    ///   before the menu was there to see.
    package func pressOpenedPopup(_ popup: OpenedPopup) {
        pressPopup = popup
        renderedSincePopupOpened = false
    }

    /// Whether the pop-up the press in flight opened is on screen to take the
    /// rest of its gesture: a render pass has begun since it opened, and its
    /// opener says it is still open (``OpenedPopup/isOpen``).
    private var pressPopupIsOnScreen: Bool {
        renderedSincePopupOpened && pressPopup?.isOpen() != false
    }

    /// Whether `event` is a button-release that ends a press-and-**hold** rather
    /// than one that merely completes a click.
    ///
    /// The distinction an open menu lives on. A menu opened by a press owns the
    /// rest of that gesture — drag down the rows, release on one to run it — so
    /// letting the button up is the user's answer, and away from every row the
    /// answer is "never mind": the menu goes. But a menu opened by a plain CLICK
    /// is sticky, staying up to be picked from at leisure, and the release that
    /// ends *that* click also lands away from every row (on the trigger, or on
    /// the menu's own top border, which is where a context menu anchors itself).
    /// Closing on that one would make a quick click open and shut the menu in a
    /// single gesture.
    ///
    /// Nothing in the event stream separates the two except whether the pointer
    /// moved, which only the dispatcher sees whole: a terminal reports a held
    /// move as a `.dragged` at the new cell, and the handler that would ask has
    /// no memory across the frames a gesture spans. So the bookkeeping lives
    /// here, beside the drag capture and the click count.
    ///
    /// A hold that never moves therefore reads as a click. That is the right way
    /// round: there is no clock in the event stream either, and treating a
    /// motionless gesture as a click leaves the menu up, which is recoverable —
    /// treating it as a hold would shut the menu under a user who was still
    /// deciding.
    func endsHeldGesture(_ event: MouseEvent) -> Bool {
        event.phase == .released && !event.button.isWheel && pointerMovedSincePress
    }

    /// Whether `event` is the release that merely ends the CLICK which opened a
    /// pop-up menu — the other half of ``endsHeldGesture(_:)``.
    ///
    /// A menu may be placed over the control that opened it: a drop-down taller
    /// than the space below it covers its own pop-up button, exactly as it does
    /// on a Mac, so the release ending the opening click lands on a menu ROW.
    /// That release must not choose it. The press was spent on opening the menu;
    /// only a release that went somewhere first (``endsHeldGesture(_:)``) is the
    /// user answering the menu they were just shown.
    ///
    /// - Precondition: the opening handler said so, via
    ///   ``pressOpenedPopup(_:)``. Without that this cannot be
    ///   distinguished from an ordinary click on a row of a menu that was
    ///   already open, which of course *does* choose it.
    func endsPopupOpeningClick(_ event: MouseEvent) -> Bool {
        event.phase == .released && !event.button.isWheel
            && pressPopup != nil && !pointerMovedSincePress
    }

    /// Updates the press-and-hold bookkeeping ``endsHeldGesture(_:)`` reads.
    ///
    /// Called for every event the dispatcher accepts, before any routing, so the
    /// record covers the whole gesture however it is routed — captured, handed
    /// off, or consumed by nobody at all.
    private func trackHeldGesture(_ event: MouseEvent) {
        switch event.phase {
        case .pressed:
            pressOrigin = (event.x, event.y)
            pointerMovedSincePress = false
            heldDragTarget = nil
            // Cleared before the press is routed, so the handler about to
            // consume it can set it (see ``pressOpenedPopup(_:)``, which
            // starts the render count with it).
            pressPopup = nil
            // A new press supersedes any record of the last one, whose release
            // evidently never arrived (a lost release, a mouse-mode change
            // mid-gesture). Otherwise that record would let one later unpaired
            // release through.
            handedOffPresses.remove(event.button)
        case .dragged:
            guard let origin = pressOrigin else { return }
            if origin.x != event.x || origin.y != event.y { pointerMovedSincePress = true }
        default:
            break
        }
    }

    /// Dispatches one mouse event to the appropriate handler.
    ///
    /// Coordinates in the event passed to the handler are **localised
    /// to the hit region** — `(0, 0)` is the region's top-left corner,
    /// matching SwiftUI's tap-gesture convention. For drag-captured
    /// handlers the same translation is applied (using the original
    /// region's offset) so a drag that leaves the source view simply
    /// produces negative or out-of-bounds local coordinates rather
    /// than re-binding to a different region.
    ///
    /// - Returns: `true` if a handler consumed the event.
    @discardableResult
    package func dispatch(_ event: MouseEvent) -> Bool {
        // Diagnostic (TUIKIT_DEBUG_FOCUS=1): log every press/release
        // with the click coords (in content-area space), the
        // registered regions, and which — if any — matched. Used to
        // diagnose "I clicked the field but no focus event fired"
        // bugs: tells us whether the click ever reached the
        // dispatcher, whether its category is allowed, and whether
        // any region's geometry covers it. The outer guard is the
        // hot-path branch — when debug is off this is a single
        // global-Bool load and one comparison.
        if isFocusDebugEnabled, event.phase == .pressed || event.phase == .released {
            let regionLines = regions.enumerated().map { index, region in
                let matches = region.contains(x: event.x, y: event.y)
                return "    [\(index)] handler=\(region.handlerID.raw) "
                    + "x=\(region.offsetX)..<\(region.offsetX + region.width) "
                    + "y=\(region.offsetY)..<\(region.offsetY + region.height)"
                    + (matches ? " ← MATCHES" : "")
            }
            debugFocusLog("""
                dispatch \(event.phase) \(event.button)
                  click at (x=\(event.x), y=\(event.y))
                  activeSupport: \(activeSupport)
                  eventIsAllowed: \(eventIsAllowed(event))
                  regions (\(regions.count)):
                \(regionLines.joined(separator: "\n"))
                """)
        }

        // Every report of the pointer's motion says where it is, a dropped one
        // too: a drag's moves arrive as `.dragged`, never as `.moved`
        // (`restingPosition`).
        if event.phase == .moved || event.phase == .dragged { restingPosition = (event.x, event.y) }

        // Honour the active MouseSupport configuration: drop events
        // whose category isn't enabled. The terminal may still send
        // them (e.g. wheel events arrive even in click-only mode),
        // but the user asked us not to surface them.
        guard eventIsAllowed(event) else { return false }

        // Synthesise the click count before any routing so every handler —
        // including a drag-captured one — sees the double-click.
        let event = stampClickCount(event)

        // Likewise the press-and-hold record: it has to be up to date before
        // any handler runs, and stay readable *through* the release that ends
        // the gesture, so it is cleared only once that release is fully routed.
        trackHeldGesture(event)
        defer {
            if event.phase == .released {
                // After routing, so whatever the release landed on could ask
                // about the gesture (``endsHeldGesture(_:)``,
                // ``endsPopupOpeningClick(_:)``).
                pressOrigin = nil
                pointerMovedSincePress = false
                heldDragTarget = nil
                pressPopup = nil
            }
        }

        // Give the drag-and-drop session the absolute cursor before any
        // localisation (drop targeting hit-tests screen coordinates).
        if event.phase == .pressed || event.phase == .dragged || event.phase == .released {
            dragAndDropSession?.lastAbsoluteEvent = event
        }

        // Bare cursor motion drives the hover state machine —
        // not the normal click routing. See dispatchMotion for
        // the rationale on why we route `.moved` separately.
        if event.phase == .moved {
            return dispatchMotion(event)
        }

        // A press on an attached gesture, and the rest of the button's
        // gesture after one, are ranked in the gesture arena — controls under
        // the press included, which it hands the press when the gestures
        // ahead of them give up. Everything else is ordinary dispatch.
        if let settled = routeThroughGestures(event, matching: { matchingRegions(at: event.x, y: event.y) }) {
            return settled
        }

        // Drag capture: when a button is currently held, route every
        // subsequent event for that button to the handler that took
        // the press, regardless of where the cursor sits now.
        if event.phase == .dragged || event.phase == .released,
            let settled = routeAgainstItsPress(event)
        {
            return settled
        }
        // Find the matching regions outside-in (innermost first
        // = last-registered first; the dispatcher's contract is
        // that views register in render order, so the inner-
        // most modifier's region is appended last). For click /
        // drag events we hand the event to the innermost match
        // and stop; for wheel events we
        // let the dispatch fall through to the next region when
        // a handler returns false. That's what makes a List or
        // ScrollView scroll even when the cursor lands on top of
        // a Button or TextField inside it — those children don't
        // handle wheel events, so the wheel bubbles past them to
        // the surrounding scroller.
        let matching = matchingRegions(at: event.x, y: event.y, includingWheelOnly: event.phase == .scrolled)
        // A left press a pane's background would take for its click is held
        // until it shows whether it is a click — see ``PressRole`` — and one
        // that nothing takes may start a selection. Any left press ends the
        // selection there was, wherever it lands, as a click does on a Mac.
        // A right press — or a Control-click, where a terminal swallows the
        // right button — on the highlight opens the selection's own menu
        // (Copy); anywhere else it is the app's, as always.
        if event.phase == .pressed, event.button == .right || (event.button == .left && event.ctrl),
            let selection = screenSelection,
            selection.openMenu(at: ScreenSelection.Point(x: event.x, y: event.y))
        {
            // The bookkeeping `.contextMenu`'s opening press does through
            // `handOffGesture()` and `pressOpenedPopup(_:)`: the held drag and
            // the release are the menu's — hit-tested live against its rows
            // once a frame has drawn it, spent here until then — and the
            // release ending a plain click leaves it up. Without it a held drag
            // had nothing captured and was dropped, so the menu's highlight
            // never followed the pointer.
            handedOffPresses.insert(event.button)
            pressOpenedPopup(selection.openedPopup)
            return true
        }
        if event.phase == .pressed, event.button == .left {
            screenSelection?.notePress()
            if !pressRoles.isEmpty || screenSelection != nil {
                return dispatchLeftPress(event, matching: matching)
            }
        }
        guard !matching.isEmpty else { return false }

        // Fall through when the handler declined: `false` means "not mine" for
        // every button, the way it always did for the wheel and the right
        // button (which is what lets a `.contextMenu` on a container open when
        // you right-click a child with no context action of its own). The left
        // button used to STOP at the first matching region regardless — so a
        // decline-everything wrapper region, `.onHover`'s, sat over its own
        // content and made every hover-wrapped control unclickable. A region
        // that wants to BLOCK what is beneath it consumes (returns true), as
        // the dimmed backdrops do.
        for region in matching where offer(event, to: region) != .declined {
            // A handed-off gesture's drag, hit-tested live: where it went is
            // what a reshape is compared against (``redeliverHeldDrag()``).
            if event.phase == .dragged { heldDragTarget = region.handlerID }
            return true
        }
        return false
    }

    /// What a region's handler did with an event offered to it.
    enum Offer: Equatable {
        /// Not its event: offer it to the next region.
        case declined

        /// Consumed. A press is captured, so the rest of its gesture comes
        /// back to the same handler.
        case captured

        /// Consumed, and — a press only — handed back to live hit-testing
        /// (``handOffGesture()``).
        case handedOff
    }

    /// Offers `event` to `region`'s handler, in the region's own coordinates,
    /// and records what consuming a press commits the rest of its gesture to.
    func offer(_ event: MouseEvent, to region: HitTestRegion) -> Offer {
        guard let handler = handlers[region.handlerID] else { return .declined }
        let localized = localize(
            event, byOffsetX: region.localOriginX, offsetY: region.localOriginY)
        gestureHandedOff = false
        guard handler(localized) else { return .declined }
        // A press captures the rest of the gesture — unless the handler handed
        // it off (``handOffGesture()``), which a menu-opening press does so the
        // drag and release find the open menu. That hand-off is recorded,
        // because it is what entitles the release to be hit-tested live with
        // nothing captured.
        guard event.phase == .pressed else { return .captured }
        if gestureHandedOff {
            handedOffPresses.insert(event.button)
            return .handedOff
        }
        pressedHandlers[event.button] = PressCapture(
            handler: handler,
            regionOffsetX: region.localOriginX,
            regionOffsetY: region.localOriginY
        )
        return .captured
    }

    /// Runs `body` — a click given whole, its press and its release, to a
    /// control a gesture arena held back until after the button came up —
    /// with the left button's capture set aside, so that a press under way
    /// meanwhile keeps the control that took it.
    func settingCaptureAside<T>(_ body: () -> T) -> T {
        let underWay = pressedHandlers.removeValue(forKey: .left)
        defer { if let underWay { pressedHandlers[.left] = underWay } }
        return body()
    }

    /// Settles a drag or release against the press that began the gesture.
    ///
    /// - Returns: the dispatch result when the press itself decides the
    ///   event's fate — routed to a live capture, to the legacy-release
    ///   fallback, spent for a pop-up that is not on screen, or dropped for
    ///   having no press behind it at all — and `nil` when the event should go
    ///   on to ordinary live hit-testing.
    func routeAgainstItsPress(_ event: MouseEvent) -> Bool? {
        // When a button is held, every subsequent event for it goes to the
        // handler that took the press, wherever the cursor sits now.
        if let capture = pressedHandlers[event.button] {
            let localized = localize(
                event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY)
            _ = capture.handler(localized)
            if event.phase == .released {
                pressedHandlers[event.button] = nil
            }
            return true
        }

        // The drags and the release a pop-up-opening press handed off, while
        // the pop-up is not on screen: before a render pass has begun since it
        // opened — the opening and they came in one input batch — or once its
        // opener says it is closed, as a row menu that built nothing does on
        // the frame after its press.
        // Hit-tested live they land on whatever lies where the pop-up is not,
        // which got a gesture it was never pressed for: a `Toggle` acting on
        // the release toggled, a text field selected to the drag, a row was
        // clicked. Drawn, the pop-up's backdrop takes them. So otherwise the
        // dispatcher spends them itself, as the backdrop would: a held release
        // closes the pop-up, a click's release leaves it up.
        if event.phase == .dragged || event.phase == .released, let pressPopup, !pressPopupIsOnScreen,
            handedOffPresses.contains(event.button)
        {
            if event.phase == .released {
                handedOffPresses.remove(event.button)
                if endsHeldGesture(event) { pressPopup.close() }
            }
            return true
        }

        // A DRAG with nothing captured is the same broken gesture as an
        // unpaired release, and was the one the guard below forgot: the press
        // landed somewhere no control took it (the app header, blank status
        // bar, a dialog's dimmed backdrop, any page background not wrapped in a
        // ScrollView), and every `.dragged` since then is being hit-tested live
        // and handed to whatever the pointer now sits over — a control that
        // never saw a press. `DialogDrag` is the visible victim: it applies the
        // motion from a never-begun anchor, so sweeping a held pointer across a
        // dialog's title row teleports the dialog by the cursor's region-local
        // coordinate.
        //
        // The hand-off is PEEKED, not consumed: a menu-opening press hands the
        // gesture to the menu, which must still see the drags AND the release
        // that follows them.
        // Every button, not only the left: an uncaptured right/middle drag
        // fell through this guard and was hit-tested LIVE, delivered to
        // whatever the pointer crossed — a TextField's .dragged arm assumes
        // its press was claimed and moved its own cursor for a gesture that
        // never touched it.
        if event.phase == .dragged {
            return handedOffPresses.contains(event.button) ? nil : false
        }

        guard event.phase == .released, event.button == .left else { return nil }

        // X10 legacy releases don't identify the button — the parser defaults
        // them to `.left`. If the press arrived as an SGR right/middle report
        // but its release fell back to legacy (which Terminal.app does on some
        // events), the capture for the REAL button would never clear, routing
        // every later event for that button to a stale closure from an old
        // frame. When a left release has no left capture and exactly ONE other
        // capture is in flight, treat it as that press's release. (A stray left
        // release while another button is genuinely held is far rarer than the
        // legacy fallback.)
        if pressedHandlers.count == 1, let (capturedButton, capture) = pressedHandlers.first {
            let localized = localize(
                event, byOffsetX: capture.regionOffsetX, offsetY: capture.regionOffsetY)
            _ = capture.handler(localized)
            pressedHandlers[capturedButton] = nil
            return true
        }

        // Nothing captured: this is a release whose press the frame's controls
        // never saw — it landed on the page background, or on something that
        // declined it — and the pointer has since travelled over whatever is
        // about to be handed a "click" it was never pressed for. Every control
        // that consumes a left press captures it, so the one legitimate way
        // here is a press that deliberately handed the gesture back: a
        // menu-opening press, whose release belongs to the menu now on screen.
        //
        // Left only. A right press is meant to bubble undeclined (that is how a
        // container's `.contextMenu` catches a right-click on a child), so a
        // right release routinely and correctly arrives with nothing captured —
        // hence the `.left` guard above.
        return handedOffPresses.remove(.left) == nil ? false : nil
    }

    /// Returns every region containing the given point, ordered
    /// innermost-first (last-registered first). Used by
    /// ``dispatch`` to implement wheel-event fall-through.
    ///
    /// A wheel handler's region (``registerWheelHandler(in:_:)``) is left out
    /// unless `includingWheelOnly`, which only a wheel event's dispatch asks
    /// for: hover, clicks and drop targeting never see it.
    func matchingRegions(at x: Int, y: Int, includingWheelOnly: Bool = false) -> [HitTestRegion] {
        // A geometry marker has no area, so `contains` already refuses it; the
        // explicit test says so, and keeps a marker inert if one ever grows a
        // size (`HitTestRegion.geometryMarker(_:)`).
        let matching = regions.reversed().filter { !$0.isGeometryMarker && $0.contains(x: x, y: y) }
        guard !includingWheelOnly, !wheelHandlerIDs.isEmpty else { return matching }
        return matching.filter { !wheelHandlerIDs.contains($0.handlerID) }
    }

    /// The two regions hover resolves against at a point, one per lane: the
    /// innermost region that is NOT a hover observer — the control the pointer
    /// is over — and the innermost observer IN FRONT of it.
    ///
    /// An observer behind that control is occluded and resolves to `nil`. That
    /// keeps the observer lane's answers exactly what they were when an observer
    /// was an ordinary region — it hears the pointer only where it was the
    /// innermost match — so a page's `.onHover` under a modal's consuming
    /// backdrop, or under an open menu, still hears nothing. The one thing that
    /// changes is that the control directly behind a stack of observers gets
    /// the hover it used to lose.
    private func resolveHover(at x: Int, y: Int) -> (target: HitTestRegion?, observer: HitTestRegion?) {
        let matching = matchingRegions(at: x, y: y)
        // The common frame has no observer, and is the old single lane.
        guard !hoverObserverIDs.isEmpty else { return (matching.first, nil) }
        var observer: HitTestRegion?
        for region in matching {
            guard hoverObserverIDs.contains(region.handlerID) else { return (region, observer) }
            if observer == nil { observer = region }
        }
        return (nil, observer)
    }

    /// Whether the hover observer registered this frame as `id` is one a
    /// pointer can reach: whether a pointer on some cell of its regions would
    /// be heard by it, rather than by nothing (no such region: the view is
    /// gone, or clipped away) or by something in front of it that takes the
    /// hover (a sheet's backdrop, an open menu, a hover observer inside it).
    ///
    /// For a tooltip held while the status bar's own rows moved the page
    /// under a resting pointer (`TooltipState.held`): the pointer is not on
    /// its view, so the hover machine reports nothing that happens to it.
    ///
    /// Every cell until one is heard, not the first alone: a view whose
    /// top-left cell something covered was taken for unreachable, and its
    /// help let go, though the pointer could rest on the rest of it
    /// (decisions-HELP A-HELP-1, "Left open"). Asked once a frame, and only
    /// while a help is held.
    package func reachesHoverObserver(_ id: HitTestRegion.HandlerID) -> Bool {
        for region in regions where region.handlerID == id {
            for y in region.offsetY..<(region.offsetY + region.height) {
                for x in region.offsetX..<(region.offsetX + region.width)
                where resolveHover(at: x, y: y).observer?.handlerID == id {
                    return true
                }
            }
        }
        return false
    }

    /// The handler ids of every region containing the given (absolute)
    /// point, innermost-first. Drop targeting matches these against the
    /// frame's registered drop targets.
    func handlerIDs(at x: Int, y: Int) -> [HitTestRegion.HandlerID] {
        matchingRegions(at: x, y: y).map(\.handlerID)
    }

    /// Delivers a click — a synthetic press, then its release — to the
    /// front-most region **behind** `handlerID`, and reports whether anything
    /// took it. `event` is in `handlerID`'s own local space, as the handler
    /// received it.
    ///
    /// For a handler that claimed the press *speculatively*. `.draggable` has
    /// to take the press to find out whether it becomes a drag; when it does
    /// not, the click was never its to keep and belongs to whatever it is
    /// sitting on. A `List` whose rows are draggable could otherwise not be
    /// selected with the mouse at all — every click on a row was swallowed by
    /// that row's own drag handle, which had no use for it.
    ///
    /// Both halves go to the same handler, and only if it takes the press: a
    /// region that declines is skipped and the search continues behind it, so
    /// an inert backdrop between the handle and the real target — a drop
    /// zone's fronted region, a container's fallback — cannot strand the click.
    @discardableResult
    func passClickThrough(from handlerID: HitTestRegion.HandlerID, event: MouseEvent) -> Bool {
        guard let origin = regionOffset(for: handlerID) else { return false }
        let (x, y) = (event.x + origin.x, event.y + origin.y)
        var reachedSelf = false
        for region in matchingRegions(at: x, y: y) {
            guard reachedSelf else {
                reachedSelf = region.handlerID == handlerID
                continue
            }
            guard let handler = handlers[region.handlerID] else { continue }
            func synthesised(_ phase: MousePhase) -> MouseEvent {
                MouseEvent(
                    button: event.button, phase: phase,
                    x: x - region.localOriginX, y: y - region.localOriginY,
                    shift: event.shift, ctrl: event.ctrl, meta: event.meta,
                    clickCount: event.clickCount)
            }
            guard handler(synthesised(.pressed)) else { continue }
            _ = handler(synthesised(.released))
            return true
        }
        return false
    }

    /// The absolute top-left offset of the region registered with `id`, or
    /// `nil` when no current region carries it. Lets a drop destination
    /// translate an absolute drop point into its local space.
    func regionOffset(for id: HitTestRegion.HandlerID) -> (x: Int, y: Int)? {
        guard let region = regions.first(where: { $0.handlerID == id }) else { return nil }
        return (region.localOriginX, region.localOriginY)
    }

    /// The full absolute rectangle of the region registered with `id`, or `nil`
    /// when no current region carries it. Unlike ``regionOffset(for:)`` this
    /// carries the size too — the drag auto-scroll driver compares the cursor
    /// against a scrollable's *edges*, which needs its width/height, not just
    /// its top-left.
    ///
    /// The **largest** region wins, because one handler may own several. A
    /// `List` stamps an extra one-row region over its cursor row with the
    /// container's own handler id (so an enclosing `ScrollView` can find the
    /// row to reveal), and it sits ahead of the container in the array — so
    /// taking the *first* match measured the list's edges as that single row.
    /// Everything below the cursor row then read as "dragged past the bottom",
    /// which armed auto-scroll from the middle of a list whose cursor was still
    /// at its top.
    func regionRect(for id: HitTestRegion.HandlerID) -> HitTestRegion? {
        regions.filter { $0.handlerID == id }.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Processes a bare cursor-motion event by synthesising
    /// `.entered` / `.exited` transitions on the affected
    /// handlers — the hover state machine.
    ///
    /// Why route `.moved` separately:
    ///
    /// - There is no useful "the cursor moved here" semantic
    ///   that a single hit-test-based dispatch could deliver.
    ///   What views actually care about is "the cursor is now
    ///   over me" / "the cursor left me", and that requires
    ///   tracking which region the cursor was over previously.
    /// - Synthesising transitions in one place keeps the rest
    ///   of the dispatcher dumb. Modifiers like ``OnHover``
    ///   only have to react to the synthetic `.entered` /
    ///   `.exited` phases; they never deal with raw motion.
    ///
    /// Returns `true` iff at least one transition fired
    /// (either an `.entered` on a new region or an `.exited`
    /// on the previous one), so the AppRunner re-renders the
    /// view tree to reflect the new hover state. Pure motion
    /// inside the already-hovered region is offered to that
    /// handler as a localized `.moved`, and re-renders only if
    /// it says the move meant something — re-rendering for
    /// every cursor twitch would peg the run loop, and most
    /// handlers care only about entering and leaving.
    ///
    /// The machine runs on two lanes: the control under the pointer, and the
    /// hover observer in front of it (``registerHoverObserver(in:_:)``). Each lane
    /// transitions on its own, and the motion wants a render when either does.
    private func dispatchMotion(_ event: MouseEvent) -> Bool {
        let resolved = resolveHover(at: event.x, y: event.y)
        // A report from the cell the pointer was already on moves nothing.
        let movedCell = lastMotionPosition.map { $0.x != event.x || $0.y != event.y } ?? true
        // Real motion supersedes any reshape bookkeeping: `advancing` hands
        // each lane back with its pending exit dropped.
        lastMotionPosition = (event.x, event.y)
        var fired = false
        hover = advancing(hover, to: resolved.target, by: event, fired: &fired)
        observedHover = advancing(observedHover, to: resolved.observer, by: event, fired: &fired)
        // After the lanes, whose `.entered` takes back a tooltip held through
        // the status bar's reflow when the move lands on its view again
        // (`TooltipState.held`); one the move left behind goes, and its
        // going is the frame this motion asks for.
        if movedCell, tooltipState?.notePointerMoved() == true { fired = true }
        return fired
    }

    /// One lane of ``dispatchMotion(_:)``: `slot` moved onto `current`, the
    /// region its lane resolves under the pointer, with the transitions that
    /// takes delivered on the way. Sets `fired` when the move wants a render.
    private func advancing(
        _ slot: HoverSlot, to current: HitTestRegion?, by event: MouseEvent, fired: inout Bool
    ) -> HoverSlot {
        let currentID = current?.handlerID
        let next = HoverSlot(handlerID: currentID, region: current, pendingExit: nil)

        // Still inside the same region: some controls are not one target but
        // many — a scrollbar's arrows and thumb share one region, and the cell
        // under the pointer is what lifts — so the move is offered to the
        // handler, which answers whether it changed anything.
        if currentID == slot.handlerID {
            if let currentID, let handler = handlers[currentID], let current {
                let moved = MouseEvent(
                    button: .none, phase: .moved,
                    x: event.x - current.localOriginX, y: event.y - current.localOriginY,
                    shift: event.shift, ctrl: event.ctrl, meta: event.meta
                )
                if handler(moved) { fired = true }
            }
            return next
        }

        // Fire .exited on the previously hovered handler if it
        // is still registered. (Between event and re-render,
        // the previous frame's handlers are still in `handlers`
        // — beginRenderPass for the next frame hasn't run yet.)
        // Coordinates are localised to the region, honouring the
        // dispatcher's contract for every phase — hover handlers
        // mostly ignore them, but DraggableModifier hit-tests the
        // transition point against its content's regions to route
        // hover through to interactive children.
        if let oldID = slot.handlerID, let oldHandler = handlers[oldID] {
            let offset = regionOffset(for: oldID) ?? (0, 0)
            let exit = MouseEvent(
                button: .none, phase: .exited,
                x: event.x - offset.x, y: event.y - offset.y,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = oldHandler(exit)
            fired = true
        }

        if let newID = currentID, let newHandler = handlers[newID], let current {
            let enter = MouseEvent(
                button: .none, phase: .entered,
                x: event.x - current.localOriginX, y: event.y - current.localOriginY,
                shift: event.shift, ctrl: event.ctrl, meta: event.meta
            )
            _ = newHandler(enter)
            fired = true
        }
        return next
    }

    /// Ends the multi-click sequence in flight, so the next press starts
    /// counting from one again.
    ///
    /// For a handler that has just ACTED on a multi-click — a `List` or `Table`
    /// row opening on its double-click. The count is otherwise cumulative for
    /// as long as the clicks keep coming, because every press extends the
    /// window from itself: a fifth click 100 ms after the fourth is still one
    /// sequence. Since "was this a double-click?" is asked as *two or more*,
    /// drumming a second double-click onto a row inside that window opened it
    /// again on every click, and a file browser dug two or three levels from
    /// what the user made as one gesture.
    ///
    /// Not done for the handler, on the release of any consumed double-click,
    /// because only the handler knows whether the gesture was spent — and an
    /// automatic reset would put ``View/onTapGesture(count:perform:)``
    /// with a count of three out of reach, its third click always arriving as
    /// the first of a new sequence.
    package func endMultiClickSequence() {
        lastClick = nil
    }

    /// Translates the event's coordinates from absolute screen-space
    /// into the local coordinate space of a hit region.
    func localize(_ event: MouseEvent, byOffsetX dx: Int, offsetY dy: Int) -> MouseEvent {
        MouseEvent(
            button: event.button,
            phase: event.phase,
            x: event.x - dx,
            y: event.y - dy,
            shift: event.shift,
            ctrl: event.ctrl,
            meta: event.meta,
            clickCount: event.clickCount
        )
    }

    /// Stamps a button press/release with the synthesised ``MouseEvent/clickCount``
    /// and carries the press's modifier state onto its matching release.
    ///
    /// A `.pressed` within the multi-click window of the previous press, on the
    /// same button and within one cell of it, advances the count; anything else
    /// resets it to 1. The matching `.released` carries the same count so a
    /// handler acting on release (the tap convention) sees the double-click.
    /// Motion / drag / wheel events are left at count 1.
    ///
    /// The release also inherits the modifier bits the press was reported with
    /// (unioned with its own). A click gesture's modifiers are fixed at press
    /// time, but a terminal could report the SGR modifier bits only on the
    /// press (`M`) and drop them on the release (`m`) — a handler that acts on
    /// release (List/Table selection, tap gestures) would then see a bare
    /// click and, for example, replace a multi-selection instead of toggling
    /// one row into it. Both macOS terminals byte-captured so far report
    /// symmetrically (see `Documentation/Terminals/Terminal compatibility survey.md`), making
    /// this a no-op there; the union stays as free defence-in-depth for
    /// unmeasured terminals.
    private func stampClickCount(_ event: MouseEvent) -> MouseEvent {
        switch event.phase {
        case .pressed:
            let now = nowNanos()
            let count: Int
            if let last = lastClick,
                last.button == event.button,
                abs(last.x - event.x) <= 1,
                abs(last.y - event.y) <= 1,
                now &- last.timeNanos <= Self.multiClickWindowNanos
            {
                count = last.count + 1
            } else {
                count = 1
            }
            lastClick = LastClick(
                button: event.button, x: event.x, y: event.y, timeNanos: now,
                count: count, shift: event.shift, ctrl: event.ctrl, meta: event.meta)
            return event.withClickCount(count)
        case .released:
            // Carry the in-flight press's count AND modifiers (if this release
            // matches it), so a terminal that drops modifier bits on the
            // release report doesn't strip the gesture's Shift/Ctrl/Option.
            // Only ONE release inherits per press: after it, the press is no
            // longer in flight, so a stray duplicate release can't pick up
            // stale modifiers from a long-finished click.
            if let last = lastClick, last.button == event.button, last.inFlight {
                lastClick?.inFlight = false
                return event.withClick(
                    count: last.count,
                    shift: event.shift || last.shift,
                    ctrl: event.ctrl || last.ctrl,
                    meta: event.meta || last.meta)
            }
            return event
        default:
            return event
        }
    }
}
